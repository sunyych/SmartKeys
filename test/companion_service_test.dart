import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumiakeys_protocol/lumiakeys_protocol.dart';
import 'package:smart_keys/services/companion_service.dart';

void main() {
  test(
    'a competing Desktop broadcast cannot replace the active host',
    () async {
      final discoveryPort = await _unusedUdpPort();
      final firstManifest = DesktopManifest.starter().copyWith(revision: 10);
      final secondManifest = DesktopManifest.starter().copyWith(revision: 20);
      final firstServer = await _ManifestServer.start(firstManifest);
      final secondServer = await _ManifestServer.start(secondManifest);
      final sender = await RawDatagramSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final companion = LanCompanionService(discoveryPort: discoveryPort);
      addTearDown(() async {
        companion.dispose();
        sender.close();
        await firstServer.close();
        await secondServer.close();
      });

      await companion.start();
      _advertise(
        sender,
        discoveryPort: discoveryPort,
        name: 'Desktop A',
        port: firstServer.port,
        token: 'token-a',
        revision: firstManifest.revision,
      );
      await _waitUntil(
        () => companion.manifest.value?.revision == firstManifest.revision,
      );

      _advertise(
        sender,
        discoveryPort: discoveryPort,
        name: 'Desktop B',
        port: secondServer.port,
        token: 'token-b',
        revision: secondManifest.revision,
      );
      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(companion.activeHost.value?.port, firstServer.port);
      expect(companion.manifest.value?.revision, firstManifest.revision);
    },
  );

  test('discovery timeout retains the last valid Desktop manifest', () async {
    final discoveryPort = await _unusedUdpPort();
    final manifest = DesktopManifest.starter().copyWith(revision: 30);
    final server = await _ManifestServer.start(manifest);
    final sender = await RawDatagramSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final companion = LanCompanionService(
      discoveryPort: discoveryPort,
      hostExpiry: const Duration(milliseconds: 80),
      expiryPollInterval: const Duration(milliseconds: 20),
    );
    addTearDown(() async {
      companion.dispose();
      sender.close();
      await server.close();
    });

    await companion.start();
    _advertise(
      sender,
      discoveryPort: discoveryPort,
      name: 'Desktop A',
      port: server.port,
      token: 'token-a',
      revision: manifest.revision,
    );
    await _waitUntil(
      () => companion.manifest.value?.revision == manifest.revision,
    );
    await _waitUntil(() => companion.activeHost.value == null);

    expect(companion.manifest.value?.revision, manifest.revision);
    expect(companion.syncStatus.value, CompanionSyncStatus.discovering);
  });
}

Future<int> _unusedUdpPort() async {
  final socket = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  socket.close();
  return port;
}

void _advertise(
  RawDatagramSocket sender, {
  required int discoveryPort,
  required String name,
  required int port,
  required String token,
  required int revision,
}) {
  final message = utf8.encode(
    jsonEncode({
      'service': 'lumiakeys-companion',
      'version': 2,
      'name': name,
      'platform': 'macos',
      'port': port,
      'token': token,
      'revision': revision,
      'capabilities': ['manifest'],
    }),
  );
  sender.send(message, InternetAddress.loopbackIPv4, discoveryPort);
}

Future<void> _waitUntil(
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('Condition was not met', timeout);
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

class _ManifestServer {
  _ManifestServer._(this._server, this._subscription);

  final HttpServer _server;
  final StreamSubscription<HttpRequest> _subscription;

  int get port => _server.port;

  static Future<_ManifestServer> start(DesktopManifest manifest) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final subscription = server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(manifest.toJson(forSync: true)));
      await request.response.close();
    });
    return _ManifestServer._(server, subscription);
  }

  Future<void> close() async {
    await _subscription.cancel();
    await _server.close(force: true);
  }
}
