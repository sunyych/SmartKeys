import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumiakeys_protocol/lumiakeys_protocol.dart';
import 'package:smart_keys/services/companion_service.dart';

void main() {
  test(
    'manual connection authenticates info and manifest without UDP discovery',
    () async {
      const token = '0123456789abcdef0123456789abcdef';
      final server = await _ManualServer.start(token: token);
      final companion = LanCompanionService(enableDiscovery: false);
      addTearDown(() async {
        companion.dispose();
        await server.close();
      });

      await companion.start();
      expect(companion.boundDiscoveryPort, isNull);
      await companion.connectManually('127.0.0.1:${server.port} $token');

      expect(companion.syncStatus.value, CompanionSyncStatus.ready);
      expect(companion.activeHost.value?.name, 'Test Desktop');
      expect(companion.manifest.value?.revision, 12);
      expect(server.authenticatedPaths, containsAll(['/info', '/manifest']));
    },
  );

  test(
    'manual pairing rejects malformed and public network codes visibly',
    () async {
      final companion = LanCompanionService(enableDiscovery: false);
      addTearDown(companion.dispose);

      await companion.connectManually('https://example.com/?token=secret');
      expect(companion.activeHost.value, isNull);
      expect(companion.syncStatus.value, CompanionSyncStatus.error);
      expect(companion.errorMessage.value, contains('address:port'));

      await companion.connectManually(
        '8.8.8.8:1234 0123456789abcdef0123456789abcdef',
      );
      expect(companion.activeHost.value, isNull);
      expect(companion.errorMessage.value, contains('private IPv4'));
    },
  );

  test(
    'a late manual handshake cannot replace the newly selected Desktop',
    () async {
      const token = '0123456789abcdef0123456789abcdef';
      final gate = Completer<void>();
      final first = await _ManualServer.start(token: token, infoGate: gate);
      final second = await _ManualServer.start(token: token);
      final companion = LanCompanionService(enableDiscovery: false);
      addTearDown(() async {
        companion.dispose();
        await first.close();
        await second.close();
      });

      final firstHandshake = companion.connectManually(
        '127.0.0.1:${first.port} $token',
      );
      await first.infoRequestReceived.future;
      await companion.connectManually('127.0.0.1:${second.port} $token');
      gate.complete();
      await firstHandshake;

      expect(companion.activeHost.value?.port, second.port);
      expect(companion.syncStatus.value, CompanionSyncStatus.ready);
    },
  );

  test('manual pairing refuses redirects', () async {
    const token = '0123456789abcdef0123456789abcdef';
    final destination = await _ManualServer.start(token: token);
    final redirect = await _ManualServer.start(
      token: token,
      redirectInfoTo: 'http://127.0.0.1:${destination.port}/info',
    );
    final companion = LanCompanionService(enableDiscovery: false);
    addTearDown(() async {
      companion.dispose();
      await redirect.close();
      await destination.close();
    });

    await companion.connectManually('127.0.0.1:${redirect.port} $token');

    expect(companion.activeHost.value, isNull);
    expect(companion.syncStatus.value, CompanionSyncStatus.error);
    expect(destination.infoRequestReceived.isCompleted, isFalse);
  });

  test('manual heartbeat clears expired connection state', () async {
    const token = '0123456789abcdef0123456789abcdef';
    final server = await _ManualServer.start(token: token);
    final companion = LanCompanionService(
      enableDiscovery: false,
      expiryPollInterval: const Duration(milliseconds: 20),
    );
    addTearDown(() async {
      companion.dispose();
      await server.close();
    });
    await companion.connectManually('127.0.0.1:${server.port} $token');
    server.rejectInfo = true;
    await _waitUntil(() => companion.activeHost.value == null);
    expect(companion.syncStatus.value, CompanionSyncStatus.disconnected);
    expect(companion.manifest.value, isNull);
  });

  test(
    'a stale manifest refresh cannot overwrite a rediscovered host',
    () async {
      final discoveryPort = await _unusedUdpPort();
      final firstManifest = DesktopManifest.starter().copyWith(revision: 10);
      final rediscoveredManifest = DesktopManifest.starter().copyWith(
        revision: 20,
      );
      final gate = Completer<void>();
      final server = await _ManifestServer.start(
        firstManifest,
        laterManifest: rediscoveredManifest,
        firstManifestGate: gate,
      );
      final sender = await RawDatagramSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final companion = LanCompanionService(
        discoveryPort: discoveryPort,
        hostExpiry: const Duration(milliseconds: 60),
        expiryPollInterval: const Duration(milliseconds: 10),
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
        revision: firstManifest.revision,
      );
      await server.firstManifestRequestReceived.future;
      await _waitUntil(() => companion.activeHost.value == null);
      _advertise(
        sender,
        discoveryPort: discoveryPort,
        name: 'Desktop A',
        port: server.port,
        token: 'token-a',
        revision: rediscoveredManifest.revision,
      );
      await _waitUntil(() => companion.activeHost.value?.revision == 20);

      gate.complete();
      await _waitUntil(
        () =>
            companion.manifest.value?.revision == rediscoveredManifest.revision,
      );

      expect(server.manifestRequests, 2);
      expect(companion.activeHost.value?.revision, 20);
      expect(companion.syncStatus.value, CompanionSyncStatus.ready);
    },
  );

  test(
    'dispose prevents a pending manifest refresh from being retried',
    () async {
      final discoveryPort = await _unusedUdpPort();
      final gate = Completer<void>();
      final server = await _ManifestServer.start(
        DesktopManifest.starter(),
        firstManifestGate: gate,
      );
      final sender = await RawDatagramSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final companion = LanCompanionService(discoveryPort: discoveryPort);
      addTearDown(() async {
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
        revision: 10,
      );
      await server.firstManifestRequestReceived.future;
      companion.dispose();
      gate.complete();
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(server.manifestRequests, 1);
    },
  );

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

class _ManualServer {
  _ManualServer(this.server, {this.infoGate, this.redirectInfoTo});

  final HttpServer server;
  late final StreamSubscription<HttpRequest> subscription;
  final List<String> authenticatedPaths = [];
  bool rejectInfo = false;
  final Completer<void> infoRequestReceived = Completer<void>();
  final Completer<void>? infoGate;
  final String? redirectInfoTo;
  int get port => server.port;

  static Future<_ManualServer> start({
    required String token,
    Completer<void>? infoGate,
    String? redirectInfoTo,
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final helper = _ManualServer(
      server,
      infoGate: infoGate,
      redirectInfoTo: redirectInfoTo,
    );
    helper.subscription = server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      if (request.headers.value('x-lumiakeys-token') != token ||
          request.uri.hasQuery) {
        request.response.statusCode = HttpStatus.forbidden;
        await request.response.close();
        return;
      }
      helper.authenticatedPaths.add(request.uri.path);
      if (request.uri.path == '/info') {
        if (!helper.infoRequestReceived.isCompleted) {
          helper.infoRequestReceived.complete();
        }
        if (helper.rejectInfo) {
          request.response.statusCode = HttpStatus.serviceUnavailable;
          await request.response.close();
          return;
        }
        if (helper.infoGate case final gate?) await gate.future;
        if (helper.redirectInfoTo case final location?) {
          request.response.statusCode = HttpStatus.found;
          request.response.headers.set(HttpHeaders.locationHeader, location);
          await request.response.close();
          return;
        }
        request.response.write(
          jsonEncode({
            'name': 'Test Desktop',
            'platform': 'windows',
            'version': 2,
            'capabilities': ['manifest'],
            'revision': 12,
          }),
        );
      } else if (request.uri.path == '/manifest') {
        request.response.write(
          jsonEncode(
            DesktopManifest.starter()
                .copyWith(revision: 12)
                .toJson(forSync: true),
          ),
        );
      } else {
        request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });
    return helper;
  }

  Future<void> close() async {
    await subscription.cancel();
    await server.close(force: true);
  }
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
  _ManifestServer(this._server, {this.laterManifest, this.firstManifestGate});

  final HttpServer _server;
  late final StreamSubscription<HttpRequest> _subscription;
  final DesktopManifest? laterManifest;
  final Completer<void>? firstManifestGate;
  final Completer<void> firstManifestRequestReceived = Completer<void>();
  int manifestRequests = 0;

  int get port => _server.port;

  static Future<_ManifestServer> start(
    DesktopManifest manifest, {
    DesktopManifest? laterManifest,
    Completer<void>? firstManifestGate,
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final helper = _ManifestServer(
      server,
      laterManifest: laterManifest,
      firstManifestGate: firstManifestGate,
    );
    helper._subscription = server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      helper.manifestRequests++;
      final requestNumber = helper.manifestRequests;
      if (!helper.firstManifestRequestReceived.isCompleted) {
        helper.firstManifestRequestReceived.complete();
      }
      final gate = helper.firstManifestGate;
      if (requestNumber == 1 && gate != null) {
        await gate.future;
      }
      final responseManifest = requestNumber == 1
          ? manifest
          : helper.laterManifest ?? manifest;
      request.response.write(
        jsonEncode(responseManifest.toJson(forSync: true)),
      );
      await request.response.close();
    });
    return helper;
  }

  Future<void> close() async {
    await _subscription.cancel();
    await _server.close(force: true);
  }
}
