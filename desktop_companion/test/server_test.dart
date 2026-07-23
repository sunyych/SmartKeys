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
}
