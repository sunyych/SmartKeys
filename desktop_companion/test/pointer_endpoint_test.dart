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
  @override
  Future<void> apply(List<PointerInput> values) async => inputs.addAll(values);
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

  final nativePointerUnavailable = !Platform.isWindows && !Platform.isMacOS;
  test(
    'pointer endpoint rejects invalid authenticated coordinates',
    () async {
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
    },
    skip: nativePointerUnavailable
        ? 'Desktop pointer support requires Windows or macOS.'
        : false,
  );

  test(
    'pointer endpoint preserves accepted event order',
    () async {
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
    },
    skip: nativePointerUnavailable
        ? 'Desktop pointer support requires Windows or macOS.'
        : false,
  );
}
