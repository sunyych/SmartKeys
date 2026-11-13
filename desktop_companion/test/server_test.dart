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

void main() {
  test(
    'server publishes manifest and accepts identifier-only profile action',
    () async {
      final controller = DesktopController(
        store: MemoryDesktopConfigStore(),
        discovery: _NoopDiscovery(),
      );
      await controller.initialize();
      final server = CompanionServer(
        controller: controller,
        discoveryPort: 45839,
      );
      addTearDown(server.dispose);
      await server.start();
      expect(server.running, isTrue);

      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final manifestRequest = await client.get(
        InternetAddress.loopbackIPv4.address,
        server.actionPort!,
        '/manifest',
      );
      manifestRequest.headers.set('x-lumiakeys-token', server.token);
      final manifestResponse = await manifestRequest.close();
      final manifestBody = await utf8.decoder.bind(manifestResponse).join();
      expect(manifestResponse.statusCode, HttpStatus.ok);
      final manifest = DesktopManifest.fromJson(
        (jsonDecode(manifestBody) as Map).map(
          (key, value) => MapEntry(key.toString(), value),
        ),
      );
      expect(manifest.layoutById('codex')!.buttons, hasLength(15));

      final actionRequest = await client.post(
        InternetAddress.loopbackIPv4.address,
        server.actionPort!,
        '/action',
      );
      actionRequest.headers.contentType = ContentType.json;
      actionRequest.headers.set('x-lumiakeys-token', server.token);
      actionRequest.write(
        jsonEncode(const RemoteActionRequest.switchProfile('default').toJson()),
      );
      final actionResponse = await actionRequest.close();
      await actionResponse.drain<void>();

      expect(actionResponse.statusCode, HttpStatus.ok);
      expect(controller.manifest.currentProfileId, 'default');
      expect(controller.connectedPhone, isNotNull);
    },
  );

  test(
    'server rejects manifest requests without its ephemeral token',
    () async {
      final controller = DesktopController(
        store: MemoryDesktopConfigStore(),
        discovery: _NoopDiscovery(),
      );
      await controller.initialize();
      final server = CompanionServer(
        controller: controller,
        discoveryPort: 45840,
      );
      addTearDown(server.dispose);
      await server.start();

      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final request = await client.get(
        InternetAddress.loopbackIPv4.address,
        server.actionPort!,
        '/manifest',
      );
      final response = await request.close();
      await response.drain<void>();
      expect(response.statusCode, HttpStatus.forbidden);
    },
  );

  test('pointer endpoint authenticates, validates, and preserves event order', () async {
    if (!Platform.isWindows && !Platform.isMacOS) return;
    final pointer = _RecordingPointerInput();
    final controller = DesktopController(
      store: MemoryDesktopConfigStore(),
      discovery: _NoopDiscovery(),
      actions: DesktopActions(pointerInput: pointer),
    );
    await controller.initialize();
    final server = CompanionServer(controller: controller, discoveryPort: 45841);
    addTearDown(server.dispose);
    await server.start();

    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    Future<HttpClientResponse> postPointer(Object body, {String? token}) async {
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

    final unauthorized = await postPointer({'inputs': []});
    await unauthorized.drain<void>();
    expect(unauthorized.statusCode, HttpStatus.forbidden);

    final invalid = await postPointer(
      {'inputs': [{'kind': 'move', 'x': 1000, 'y': 0}]},
      token: server.token,
    );
    await invalid.drain<void>();
    expect(invalid.statusCode, HttpStatus.badRequest);
    expect(pointer.inputs, isEmpty);

    final accepted = await postPointer(
      {
        'inputs': [
          const PointerInput.move(7, -2).toJson(),
          const PointerInput.button(secondary: true).toJson(),
          const PointerInput.scroll(3).toJson(),
        ],
      },
      token: server.token,
    );
    await accepted.drain<void>();
    expect(accepted.statusCode, HttpStatus.ok);
    expect(pointer.inputs.map((input) => input.kind), [
      PointerInputKind.move,
      PointerInputKind.button,
      PointerInputKind.scroll,
    ]);
    expect(pointer.inputs[1].secondary, isTrue);
  });
}
