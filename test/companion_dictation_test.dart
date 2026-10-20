import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_keys/services/companion_service.dart';

void main() {
  test('requires the advertised capability before any HTTP request', () async {
    final service = RecordingCompanionService()
      ..host.value = const CompanionHost(
        name: 'Old Desktop',
        platform: 'windows',
        address: '127.0.0.1',
        port: 1,
        token: 'secret',
        protocolVersion: 2,
        capabilities: {'manifest'},
      );

    await expectLater(
      service.sendDictation(sessionId: 's', sequence: 1, text: 'hello'),
      throwsA(isA<CompanionDictationException>()),
    );
    expect(service.dictationRequests, isEmpty);
    service.dispose();
  });

  test(
    'sends authenticated multilingual final text unchanged and once',
    () async {
      const transcript = 'Crème brûlée — 你好, 東京';
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final requestReceived =
          Completer<({String path, String? token, String body})>();
      var requests = 0;
      server.listen((request) async {
        requests++;
        final body = await utf8.decoder.bind(request).join();
        requestReceived.complete((
          path: request.uri.path,
          token: request.headers.value('x-lumiakeys-token'),
          body: body,
        ));
        request.response
          ..statusCode = HttpStatus.ok
          ..write('{"ok":true}');
        await request.response.close();
      });
      final service = await _discover(
        server.port,
        hostExpiry: const Duration(seconds: 3),
        expiryPollInterval: const Duration(milliseconds: 100),
      );
      await service.sendDictation(
        sessionId: 'phone-session-1',
        sequence: 7,
        text: transcript,
      );
      final request = await requestReceived.future;
      expect(request.path, '/dictation');
      expect(request.token, 'test-token');
      expect(jsonDecode(request.body), {
        'sessionId': 'phone-session-1',
        'sequence': 7,
        'text': transcript,
      });
      expect(requests, 1);
      await _dispose(service, server);
    },
  );

  test('reports server rejection without retrying the phrase', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var requests = 0;
    server.listen((request) async {
      requests++;
      await request.drain<void>();
      request.response
        ..statusCode = HttpStatus.conflict
        ..write('Text insertion failed');
      await request.response.close();
    });
    final service = await _discover(server.port);
    await expectLater(
      service.sendDictation(sessionId: 's1', sequence: 1, text: 'phrase'),
      throwsA(
        isA<CompanionDictationException>().having(
          (error) => error.message,
          'message',
          contains('Text insertion failed'),
        ),
      ),
    );
    expect(requests, 1);
    await _dispose(service, server);
  });

  test(
    'input busy is typed only for the exact 409 response and is not retried',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var requests = 0;
      server.listen((request) async {
        requests++;
        await request.drain<void>();
        request.response.statusCode = switch (requests) {
          1 || 3 || 5 => HttpStatus.conflict,
          2 => HttpStatus.ok,
          _ => HttpStatus.internalServerError,
        };
        request.response.write(switch (requests) {
          1 => '{"error":"input_busy"}',
          2 => '{"ok":true}',
          3 => '{"error":"input_busy","extra":true}',
          4 => '{"error":"input_busy"}',
          _ => 'not json',
        });
        await request.response.close();
      });
      final service = await _discover(server.port);

      await expectLater(
        service.sendDictation(
          sessionId: 's1',
          sequence: 1,
          text: 'busy phrase',
        ),
        throwsA(isA<CompanionInputBusyException>()),
      );
      expect(requests, 1);
      await service.sendDictation(
        sessionId: 's1',
        sequence: 2,
        text: 'next phrase',
      );
      expect(requests, 2);

      for (final sequence in [3, 4, 5]) {
        await expectLater(
          service.sendDictation(
            sessionId: 's1',
            sequence: sequence,
            text: 'generic failure $sequence',
          ),
          throwsA(
            isA<CompanionDictationException>().having(
              (error) => error.runtimeType,
              'runtimeType',
              CompanionDictationException,
            ),
          ),
        );
      }
      expect(requests, 5);
      await _dispose(service, server);
    },
  );

  test('phrase rejection leaves the discovered connection usable', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var requests = 0;
    server.listen((request) async {
      requests++;
      await request.drain<void>();
      request.response
        ..statusCode = requests == 1 ? HttpStatus.conflict : HttpStatus.ok
        ..write(requests == 1 ? 'No focused text field' : '{"ok":true}');
      await request.response.close();
    });
    final service = await _discover(server.port);
    await expectLater(
      service.sendDictation(sessionId: 's1', sequence: 1, text: 'rejected'),
      throwsA(isA<CompanionDictationException>()),
    );
    expect(service.syncStatus.value, CompanionSyncStatus.ready);
    await service.sendDictation(
      sessionId: 's1',
      sequence: 2,
      text: 'next phrase',
    );
    expect(requests, 2);
    expect(service.syncStatus.value, CompanionSyncStatus.ready);
    await _dispose(service, server);
  });

  test(
    'connection expiry during delivery is reported as stale and not retried',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var requests = 0;
      server.listen((request) async {
        requests++;
        await request.drain<void>();
        await Future<void>.delayed(const Duration(milliseconds: 100));
        request.response
          ..statusCode = HttpStatus.conflict
          ..write('{"error":"input_busy"}');
        await request.response.close();
      });
      final service = await _discover(
        server.port,
        hostExpiry: const Duration(milliseconds: 25),
        expiryPollInterval: const Duration(milliseconds: 5),
      );
      await expectLater(
        service.sendDictation(
          sessionId: 'stale',
          sequence: 1,
          text: 'one phrase',
        ),
        throwsA(
          isA<CompanionDictationException>().having(
            (error) => error.runtimeType,
            'runtimeType',
            CompanionDictationException,
          ),
        ),
      );
      expect(service.activeHost.value, isNull);
      expect(requests, 1);
      await _dispose(service, server);
    },
  );

  test('delivery timeout is surfaced without automatic retry', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var requests = 0;
    server.listen((request) async {
      requests++;
      await request.drain<void>();
      await Future<void>.delayed(const Duration(milliseconds: 150));
      try {
        request.response
          ..statusCode = HttpStatus.ok
          ..write('{"ok":true}');
        await request.response.close();
      } on HttpException {
        // The phone closed the timed-out request.
      }
    });
    final service = await _discover(
      server.port,
      dictationTimeout: const Duration(milliseconds: 30),
    );
    await expectLater(
      service.sendDictation(sessionId: 'timeout', sequence: 1, text: 'phrase'),
      throwsA(isA<CompanionDictationException>()),
    );
    expect(requests, 1);
    await _dispose(service, server);
  });

  test('rejects overlong and unsafe text before sending', () async {
    final service = RecordingCompanionService()
      ..host.value = const CompanionHost(
        name: 'Desktop',
        platform: 'windows',
        address: '127.0.0.1',
        port: 1,
        token: 'token',
        protocolVersion: 2,
        capabilities: {'local-dictation-v1'},
      );
    await expectLater(
      service.sendDictation(sessionId: 's', sequence: 1, text: 'x' * 8001),
      throwsA(isA<CompanionDictationException>()),
    );
    await expectLater(
      service.sendDictation(sessionId: 's', sequence: 1, text: 'bad\u0001text'),
      throwsA(isA<CompanionDictationException>()),
    );
    expect(service.dictationRequests, isEmpty);
    service.dispose();
  });
}

Future<LanCompanionService> _discover(
  int hostPort, {
  Duration hostExpiry = const Duration(seconds: 8),
  Duration expiryPollInterval = const Duration(seconds: 3),
  Duration dictationTimeout = const Duration(seconds: 8),
}) async {
  final service = LanCompanionService(
    discoveryPort: 0,
    hostExpiry: hostExpiry,
    expiryPollInterval: expiryPollInterval,
    dictationTimeout: dictationTimeout,
  );
  await service.start();
  final sender = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
  sender.send(
    utf8.encode(
      jsonEncode({
        'service': 'lumiakeys-companion',
        'name': 'Test Desktop',
        'platform': 'windows',
        'port': hostPort,
        'token': 'test-token',
        'version': 2,
        'revision': 1,
        'capabilities': ['local-dictation-v1'],
      }),
    ),
    InternetAddress.loopbackIPv4,
    service.boundDiscoveryPort!,
  );
  for (
    var attempt = 0;
    attempt < 50 && service.activeHost.value == null;
    attempt++
  ) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  sender.close();
  expect(service.activeHost.value, isNotNull);
  return service;
}

Future<void> _dispose(LanCompanionService service, HttpServer server) async {
  service.dispose();
  await server.close(force: true);
}
