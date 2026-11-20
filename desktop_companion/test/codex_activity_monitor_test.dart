import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumiakeys_companion/codex_activity.dart';
import 'package:lumiakeys_companion/companion_server.dart';
import 'package:lumiakeys_companion/desktop_controller.dart';
import 'package:lumiakeys_protocol/codex_activity.dart';
import 'package:lumiakeys_protocol/lumiakeys_protocol.dart';

class _NoopDiscovery implements ApplicationDiscovery {
  @override
  Future<List<RemoteApplication>> refresh(List<RemoteApplication> apps) async =>
      apps;
}

Future<void> _until(
  CodexActivityMonitor monitor,
  CodexActivityStatus? expected,
) async {
  if (monitor.status == expected) return;
  final completer = Completer<void>();
  void changed() {
    if (monitor.status == expected && !completer.isCompleted) {
      completer.complete();
    }
  }

  monitor.addListener(changed);
  try {
    await completer.future.timeout(const Duration(seconds: 4));
  } finally {
    monitor.removeListener(changed);
  }
}

void main() {
  const chat = 'test-chat-1';

  test('status configuration is limited to numeric loopback WebSockets', () {
    expect(
      CodexActivityTarget(
        'ws://127.0.0.1:7337',
        'codex://threads/$chat',
      ).threadId,
      chat,
    );
    expect(CodexActivityTarget('ws://[::1]:7337', chat).endpoint.host, '::1');
    for (final endpoint in [
      'ws://192.168.1.2:7337',
      'ws://localhost:7337',
      'ws://127.0.0.1.example.com:7337',
      'ws://name@127.0.0.1:7337',
      'ws://127.0.0.1:7337?token=hidden',
      'http://127.0.0.1:7337',
    ]) {
      expect(() => CodexActivityTarget(endpoint, chat), throwsFormatException);
    }
    expect(
      () => CodexActivityTarget('ws://127.0.0.1:7337', '../other-chat'),
      throwsFormatException,
    );
  });

  test(
    'only real chat status and the final turn determine the five colors',
    () async {
      final mock = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final monitor = CodexActivityMonitor(
        pollInterval: const Duration(milliseconds: 20),
        requestTimeout: const Duration(seconds: 1),
      );
      final calls = <Map>[];
      var status = <String, Object?>{'type': 'idle'};
      var turns = <Map<String, Object?>>[];
      mock.listen((request) async {
        final socket = await WebSocketTransformer.upgrade(request);
        socket.listen((message) {
          final call = jsonDecode(message as String) as Map;
          calls.add(call);
          if (call['id'] case final int id) {
            socket.add(
              jsonEncode({
                'id': id,
                'result': switch (call['method']) {
                  'initialize' => <String, Object?>{},
                  'thread/read' => {
                    'thread': {'id': chat, 'status': status},
                  },
                  'thread/turns/list' => {'data': turns},
                  _ => throw StateError('Unexpected method'),
                },
              }),
            );
          }
        });
      });
      addTearDown(() => mock.close(force: true));
      addTearDown(monitor.dispose);

      await monitor.start();
      expect(monitor.status, isNull);
      await monitor.setTarget(
        CodexActivityTarget('ws://127.0.0.1:${mock.port}', chat),
      );
      await _until(monitor, CodexActivityStatus.idle);

      status = {'type': 'active', 'activeFlags': <String>[]};
      await _until(monitor, CodexActivityStatus.thinking);
      status = {
        'type': 'active',
        'activeFlags': ['waitingOnApproval'],
      };
      await _until(monitor, CodexActivityStatus.needsInput);
      status = {'type': 'active', 'activeFlags': <String>[]};
      await _until(monitor, CodexActivityStatus.thinking);
      status = {
        'type': 'active',
        'activeFlags': ['waitingOnUserInput'],
      };
      await _until(monitor, CodexActivityStatus.needsInput);
      status = {'type': 'idle'};
      turns = [
        {'status': 'completed'},
      ];
      await _until(monitor, CodexActivityStatus.complete);
      status = {'type': 'notLoaded'};
      turns = [
        {'status': 'failed'},
      ];
      await _until(monitor, CodexActivityStatus.error);
      turns = [
        {'status': 'interrupted', 'error': null},
      ];
      await _until(monitor, CodexActivityStatus.idle);
      status = {'type': 'systemError'};
      await _until(monitor, CodexActivityStatus.error);
      status = {'type': 'notLoaded'};
      turns = [
        {'status': 'inProgress'},
      ];
      await _until(monitor, null);

      expect(calls.map((call) => call['method']).toSet(), {
        'initialize',
        'initialized',
        'thread/read',
        'thread/turns/list',
      });
      for (final call in calls.where(
        (call) => call['method'] == 'thread/read',
      )) {
        expect(call['params'], {'threadId': chat, 'includeTurns': false});
      }
      for (final call in calls.where(
        (call) => call['method'] == 'thread/turns/list',
      )) {
        expect(call['params'], {
          'threadId': chat,
          'limit': 1,
          'sortDirection': 'desc',
          'itemsView': 'notLoaded',
        });
      }
      status = {'type': 'active', 'activeFlags': <String>[]};
      await _until(monitor, CodexActivityStatus.thinking);
      await mock.close(force: true);
      await _until(monitor, null);
    },
  );

  test(
    'older App Server can still report live idle without reading chat history',
    () async {
      final mock = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final monitor = CodexActivityMonitor(
        pollInterval: const Duration(milliseconds: 20),
        requestTimeout: const Duration(seconds: 1),
      );
      final reads = <Object?>[];
      var type = 'idle';
      var error = -32601;
      mock.listen((request) async {
        final socket = await WebSocketTransformer.upgrade(request);
        socket.listen((message) {
          final call = jsonDecode(message as String) as Map;
          final id = call['id'];
          switch (call['method']) {
            case 'initialize':
              socket.add(jsonEncode({'id': id, 'result': {}}));
            case 'initialized':
              break;
            case 'thread/read':
              reads.add(call['params']);
              socket.add(
                jsonEncode({
                  'id': id,
                  'result': {
                    'thread': {
                      'id': chat,
                      'status': {'type': type},
                    },
                  },
                }),
              );
            case 'thread/turns/list':
              socket.add(
                jsonEncode({
                  'id': id,
                  'error': {'code': error, 'message': 'Test RPC error'},
                }),
              );
            default:
              throw StateError('Unexpected method');
          }
        });
      });
      addTearDown(() => mock.close(force: true));
      addTearDown(monitor.dispose);
      await monitor.start();
      await monitor.setTarget(
        CodexActivityTarget('ws://127.0.0.1:${mock.port}', chat),
      );

      await _until(monitor, CodexActivityStatus.idle);
      type = 'notLoaded';
      await _until(monitor, null);
      type = 'idle';
      await _until(monitor, CodexActivityStatus.idle);
      error = -32603;
      await _until(monitor, null);
      expect(reads, everyElement({'threadId': chat, 'includeTurns': false}));
    },
  );

  test(
    'approval-paired endpoint only returns the scalar and uses no cache',
    () async {
      final controller = DesktopController(
        store: MemoryDesktopConfigStore(),
        discovery: _NoopDiscovery(),
      );
      await controller.initialize();
      addTearDown(controller.dispose);
      final server = CompanionServer(controller: controller, discoveryPort: 0);
      addTearDown(server.dispose);
      await server.start();
      final client = HttpClient();
      addTearDown(() => client.close(force: true));

      expect(server.capabilities, contains(codexActivityCapability));
      final unauthorized = await client.get(
        '127.0.0.1',
        server.actionPort!,
        codexActivityPath,
      );
      final rejected = await unauthorized.close();
      expect(rejected.statusCode, HttpStatus.forbidden);
      await rejected.drain<void>();

      final request = await client.get(
        '127.0.0.1',
        server.actionPort!,
        codexActivityPath,
      );
      request.headers.set('x-lumiakeys-token', server.token);
      final response = await request.close();
      expect(response.statusCode, HttpStatus.ok);
      expect(
        response.headers.value(HttpHeaders.cacheControlHeader),
        'no-store',
      );
      expect(jsonDecode(await utf8.decoder.bind(response).join()), {
        'status': null,
      });
    },
  );
}
