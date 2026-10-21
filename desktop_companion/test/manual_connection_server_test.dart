import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumiakeys_protocol/lumiakeys_protocol.dart';
import 'package:lumiakeys_companion/companion_server.dart';
import 'package:lumiakeys_companion/desktop_controller.dart';

class _NoopDiscovery implements ApplicationDiscovery {
  @override
  Future<List<RemoteApplication>> refresh(List<RemoteApplication> apps) async =>
      apps;
}

void main() {
  late CompanionServer server;
  late DesktopController controller;
  late HttpClient client;

  setUp(() async {
    controller = DesktopController(
      store: MemoryDesktopConfigStore(),
      discovery: _NoopDiscovery(),
    );
    await controller.initialize();
    server = CompanionServer(controller: controller, discoveryPort: 0);
    await server.start();
    client = HttpClient();
  });

  tearDown(() {
    client.close(force: true);
    server.dispose();
  });

  Future<HttpClientResponse> get(String path, {String? token}) async {
    final request = await client.get(
      InternetAddress.loopbackIPv4.address,
      server.actionPort!,
      path,
    );
    if (token != null) request.headers.set('x-lumiakeys-token', token);
    return request.close();
  }

  test(
    'info requires the token header and returns token-free server details',
    () async {
      final unauthorized = await get('/info');
      expect(unauthorized.statusCode, HttpStatus.forbidden);
      await unauthorized.drain<void>();

      final response = await get('/info', token: server.token);
      final info = jsonDecode(await utf8.decoder.bind(response).join()) as Map;
      final leakedTokenField = info.containsKey('token');
      // Remove before assertions so a failing test never prints a credential.
      info.remove('token');

      expect(response.statusCode, HttpStatus.ok);
      expect(leakedTokenField, isFalse);
      expect(info['name'], isA<String>());
      expect(info['platform'], server.platform);
      expect(info['version'], 2);
      expect(info['revision'], controller.manifest.revision);
      expect(info['capabilities'], contains('manifest'));
    },
  );

  test('manifest and identifier-only action routes still work', () async {
    final manifestResponse = await get('/manifest', token: server.token);
    expect(manifestResponse.statusCode, HttpStatus.ok);
    final manifest = DesktopManifest.fromJson(
      (jsonDecode(await utf8.decoder.bind(manifestResponse).join()) as Map).map(
        (key, value) => MapEntry(key.toString(), value),
      ),
    );
    expect(manifest.layoutById('codex'), isNotNull);

    final request = await client.post(
      InternetAddress.loopbackIPv4.address,
      server.actionPort!,
      '/action',
    );
    request.headers.contentType = ContentType.json;
    request.headers.set('x-lumiakeys-token', server.token);
    request.write(
      jsonEncode(const RemoteActionRequest.switchProfile('default').toJson()),
    );
    final actionResponse = await request.close();
    await actionResponse.drain<void>();

    expect(actionResponse.statusCode, HttpStatus.ok);
    expect(controller.manifest.currentProfileId, 'default');
    expect(controller.connectedPhone, isNotNull);
  });
}
