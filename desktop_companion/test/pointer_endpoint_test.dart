import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumiakeys_protocol/lumiakeys_protocol.dart';
import 'package:lumiakeys_companion/main.dart';

class _NoopDiscovery implements ApplicationDiscovery {
  @override
  Future<List<RemoteApplication>> refresh(List<RemoteApplication> apps) async =>
      apps;
}

class _RecordingPointerInput implements DesktopPointerInput {
  final List<PointerInput> inputs = [];
  Object? failNext;
  @override
  Future<void> apply(List<PointerInput> values) async {
    final failure = failNext;
    failNext = null;
    if (failure != null) throw failure;
    inputs.addAll(values);
  }
}

Future<({CompanionServer server, _RecordingPointerInput pointer})>
_startServer() async {
  final pointer = _RecordingPointerInput();
  final controller = DesktopController(
    store: MemoryDesktopConfigStore(),
    discovery: _NoopDiscovery(),
    actions: DesktopActions(pointerInput: pointer),
  );
  addTearDown(controller.dispose);
  await controller.initialize();
  final server = CompanionServer(controller: controller, discoveryPort: 45842);
  await server.start();
  return (server: server, pointer: pointer);
}

Future<HttpClientResponse> _postPointer(
  CompanionServer server,
  HttpClient client,
  Object body, {
  String? token,
}) async {
  final request = await client.post(
    InternetAddress.loopbackIPv4.address,
    server.actionPort!,
    '/pointer',
  );
  request.headers.contentType = ContentType.json;
  if (token != null) request.headers.set('x-lumiakeys-token', token);
  request.write(jsonEncode(body));
  return request.close();
}

void main() {
  test('pointer endpoint rejects requests without authorization', () async {
    final fixture = await _startServer();
    addTearDown(fixture.server.dispose);
    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    final response = await _postPointer(fixture.server, client, {'inputs': []});
    await response.drain<void>();
    expect(response.statusCode, HttpStatus.forbidden);
    expect(fixture.pointer.inputs, isEmpty);
  });

  test('pointer endpoint rejects invalid authenticated coordinates', () async {
    final fixture = await _startServer();
    addTearDown(fixture.server.dispose);
    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    final response = await _postPointer(fixture.server, client, {
      'inputs': [
        {'kind': 'move', 'x': 1000, 'y': 0},
      ],
    }, token: fixture.server.token);
    await response.drain<void>();
    expect(response.statusCode, HttpStatus.badRequest);
    expect(fixture.pointer.inputs, isEmpty);
  });

  test('pointer endpoint preserves accepted event order', () async {
    final fixture = await _startServer();
    addTearDown(fixture.server.dispose);
    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    final response = await _postPointer(fixture.server, client, {
      'inputs': [
        const PointerInput.move(7, -2).toJson(),
        const PointerInput.button(secondary: true).toJson(),
        const PointerInput.scroll(3).toJson(),
      ],
    }, token: fixture.server.token);
    await response.drain<void>();
    expect(response.statusCode, HttpStatus.ok);
    expect(fixture.pointer.inputs.map((input) => input.kind), [
      PointerInputKind.move,
      PointerInputKind.button,
      PointerInputKind.scroll,
    ]);
    expect(fixture.pointer.inputs[1].secondary, isTrue);
  });

  test(
    'switching server endpoints uses the destination token and preserves independent pointer state',
    () async {
      final first = await _startServer();
      final second = await _startServer();
      addTearDown(first.server.dispose);
      addTearDown(second.server.dispose);
      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      expect(first.server.capabilities, contains('mouse-control-v1'));
      expect(second.server.capabilities, contains('mouse-control-v1'));
      expect(first.server.token, isNot(second.server.token));
      final original = await _postPointer(first.server, client, {
        'inputs': [const PointerInput.move(11, -2).toJson()],
      }, token: first.server.token);
      await original.drain<void>();
      expect(original.statusCode, HttpStatus.ok);
      final oldCredentials = await _postPointer(second.server, client, {
        'inputs': [const PointerInput.move(30, 40).toJson()],
      }, token: first.server.token);
      await oldCredentials.drain<void>();
      expect(oldCredentials.statusCode, HttpStatus.forbidden);
      expect(second.pointer.inputs, isEmpty);
      final switched = await _postPointer(second.server, client, {
        'inputs': [
          const PointerInput.move(-7, 3).toJson(),
          const PointerInput.button(secondary: false).toJson(),
          const PointerInput.scroll(-1).toJson(),
        ],
      }, token: second.server.token);
      await switched.drain<void>();
      expect(switched.statusCode, HttpStatus.ok);
      expect(first.pointer.inputs.single.x, 11);
      expect(second.pointer.inputs.map((value) => value.kind), [
        PointerInputKind.move,
        PointerInputKind.button,
        PointerInputKind.scroll,
      ]);
      expect(second.pointer.inputs.first.x, -7);
      expect(second.pointer.inputs[1].secondary, isFalse);
    },
  );

  test(
    'a rejected native pointer batch reports failure without poisoning later input',
    () async {
      final fixture = await _startServer();
      addTearDown(fixture.server.dispose);
      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      fixture.pointer.failNext = StateError('fixture native rejection');
      final rejected = await _postPointer(fixture.server, client, {
        'inputs': [const PointerInput.move(4, 2).toJson()],
      }, token: fixture.server.token);
      final error = jsonDecode(await utf8.decoder.bind(rejected).join()) as Map;
      expect(rejected.statusCode, HttpStatus.badRequest);
      expect(error['error'], contains('fixture native rejection'));
      expect(fixture.pointer.inputs, isEmpty);
      final recovered = await _postPointer(fixture.server, client, {
        'inputs': [const PointerInput.move(8, -3).toJson()],
      }, token: fixture.server.token);
      await recovered.drain<void>();
      expect(recovered.statusCode, HttpStatus.ok);
      expect(fixture.pointer.inputs.single.x, 8);
    },
  );
}
