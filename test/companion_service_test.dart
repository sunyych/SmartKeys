import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart' show Listenable;
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
    final disconnected = _waitForCompanionState(
      companion,
      () =>
          companion.activeHost.value == null &&
          companion.manifest.value == null &&
          companion.syncStatus.value == CompanionSyncStatus.disconnected,
      'rejected manual heartbeat clears connection',
    );
    server.rejectInfo = true;
    await disconnected;
    expect(companion.syncStatus.value, CompanionSyncStatus.disconnected);
    expect(companion.manifest.value, isNull);
  });

  test(
    'a stale manifest refresh cannot overwrite a rediscovered host',
    () async {
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
      var now = DateTime.utc(2026);
      final companion = LanCompanionService(
        discoveryPort: 0,
        hostExpiry: const Duration(milliseconds: 60),
        expiryPollInterval: const Duration(milliseconds: 10),
        now: () => now,
      );
      addTearDown(() async {
        companion.dispose();
        sender.close();
        await server.close();
      });
      await companion.start();
      await _advertiseAndWait(
        sender,
        companion: companion,
        name: 'Desktop A',
        port: server.port,
        token: 'token-a',
        revision: firstManifest.revision,
        predicate: () =>
            companion.activeHost.value?.revision == firstManifest.revision,
        phase: 'first host discovered while its manifest is held',
      );
      await server.firstManifestRequestReceived.future.timeout(
        const Duration(seconds: 8),
      );
      final expired = _waitForCompanionState(
        companion,
        () => companion.activeHost.value == null,
        'old host expires while first response is held',
      );
      now = now.add(const Duration(seconds: 1));
      await expired;
      await _advertiseAndWait(
        sender,
        companion: companion,
        name: 'Desktop A',
        port: server.port,
        token: 'token-a',
        revision: rediscoveredManifest.revision,
        predicate: () => companion.activeHost.value?.revision == 20,
        phase: 'new session rediscovered',
      );
      final synchronized = _waitForCompanionState(
        companion,
        () =>
            companion.manifest.value?.revision ==
                rediscoveredManifest.revision &&
            companion.syncStatus.value == CompanionSyncStatus.ready,
        'rediscovered manifest published',
      );
      gate.complete();
      await synchronized;
      expect(server.manifestRequests, 2);
      expect(companion.activeHost.value?.revision, 20);
      expect(companion.syncStatus.value, CompanionSyncStatus.ready);
    },
  );

  test(
    'dispose prevents a pending manifest refresh from being retried',
    () async {
      final gate = Completer<void>();
      final server = await _ManifestServer.start(
        DesktopManifest.starter(),
        firstManifestGate: gate,
      );
      final sender = await RawDatagramSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final companion = _discoveryCompanion();
      var disposed = false;
      addTearDown(() async {
        if (!disposed) companion.dispose();
        sender.close();
        await server.close();
      });
      await companion.start();
      await _advertiseAndWait(
        sender,
        companion: companion,
        name: 'Desktop A',
        port: server.port,
        token: 'token-a',
        revision: 10,
        predicate: () => companion.activeHost.value?.revision == 10,
        phase: 'host discovered before disposal',
      );
      await server.firstManifestRequestReceived.future.timeout(
        const Duration(seconds: 8),
      );
      companion.dispose();
      disposed = true;
      gate.complete();
      await server.firstManifestResponseSent.future.timeout(
        const Duration(seconds: 8),
      );
      // A bounded negative-observation window starts after the server has really
      // sent the held response; positive readiness never depends on a sleep.
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(server.manifestRequests, 1);
    },
  );

  test(
    'a competing Desktop broadcast cannot replace the active host',
    () async {
      final firstManifest = DesktopManifest.starter().copyWith(revision: 10),
          secondManifest = DesktopManifest.starter().copyWith(revision: 20);
      final firstServer = await _ManifestServer.start(firstManifest),
          secondServer = await _ManifestServer.start(secondManifest);
      final sender = await RawDatagramSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final companion = _discoveryCompanion();
      addTearDown(() async {
        companion.dispose();
        sender.close();
        await firstServer.close();
        await secondServer.close();
      });
      await companion.start();
      await _advertiseAndWait(
        sender,
        companion: companion,
        name: 'Desktop A',
        port: firstServer.port,
        token: 'token-a',
        revision: firstManifest.revision,
        predicate: () =>
            companion.manifest.value?.revision == firstManifest.revision &&
            companion.syncStatus.value == CompanionSyncStatus.ready,
        phase: 'active Desktop A fully synchronized',
      );
      await _advertiseAndWait(
        sender,
        companion: companion,
        name: 'Desktop B',
        port: secondServer.port,
        token: 'token-b',
        revision: secondManifest.revision,
        predicate: () => companion.computerChoices.value.length == 2,
        phase: 'competing Desktop B advertisement received',
      );
      expect(companion.activeHost.value?.port, firstServer.port);
      expect(companion.activeHost.value?.token, 'token-a');
      expect(companion.manifest.value?.revision, firstManifest.revision);
      expect(companion.computerChoices.value, hasLength(2));
      expect(companion.computerChoices.value.map((choice) => choice.name), [
        'Desktop A',
        'Desktop B',
      ]);
      expect(firstServer.manifestRequests, 1);
      expect(secondServer.manifestRequests, 0);
    },
  );

  test('rediscovery retries the same manifest after an action error', () async {
    final manifest = DesktopManifest.starter().copyWith(revision: 30);
    final server = await _ManifestServer.start(manifest);
    final sender = await RawDatagramSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final companion = _discoveryCompanion();
    addTearDown(() async {
      companion.dispose();
      sender.close();
      await server.close();
    });
    await companion.start();
    await _advertiseAndWait(
      sender,
      companion: companion,
      name: 'Desktop A',
      port: server.port,
      token: 'token-a',
      revision: manifest.revision,
      predicate: () => companion.syncStatus.value == CompanionSyncStatus.ready,
      phase: 'Desktop ready before action error',
    );
    server.rejectActions = true;
    await companion.executeRemote(
      const RemoteActionRequest.switchProfile('profile_general'),
    );
    expect(companion.syncStatus.value, CompanionSyncStatus.error);
    expect(server.manifestRequests, 1);
    server.rejectActions = false;
    await _advertiseAndWait(
      sender,
      companion: companion,
      name: 'Desktop A',
      port: server.port,
      token: 'token-a',
      revision: manifest.revision,
      predicate: () =>
          server.manifestRequests == 2 &&
          companion.syncStatus.value == CompanionSyncStatus.ready,
      phase: 'same-revision recovery completed',
    );
    expect(companion.manifest.value?.revision, manifest.revision);
    expect(server.manifestRequests, 2);
  });

  test(
    'Desktop app action errors reach the caller without breaking sync',
    () async {
      final manifest = DesktopManifest.starter().copyWith(revision: 31);
      final server = await _ManifestServer.start(manifest);
      final sender = await RawDatagramSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final companion = _discoveryCompanion();
      addTearDown(() async {
        companion.dispose();
        sender.close();
        await server.close();
      });
      await companion.start();
      await _advertiseAndWait(
        sender,
        companion: companion,
        name: 'Desktop A',
        port: server.port,
        token: 'token-a',
        revision: manifest.revision,
        predicate: () =>
            companion.syncStatus.value == CompanionSyncStatus.ready,
        phase: 'Desktop ready before rejected app actions',
      );
      await expectLater(
        companion.executeRemote(
          const RemoteActionRequest.launchApplication('codex'),
        ),
        throwsA(isA<HttpException>()),
      );
      await expectLater(
        companion.executeRemote(
          const RemoteActionRequest.button('chatgpt.newChat'),
        ),
        throwsA(isA<HttpException>()),
      );
      expect(companion.syncStatus.value, CompanionSyncStatus.ready);
      expect(companion.errorMessage.value, isNull);
      expect(server.manifestRequests, 1);
    },
  );

  for (final manifestRespondsFirst in [true, false]) {
    test(
      'app button response survives a same-session revision update${manifestRespondsFirst ? '' : ' (action response first)'}',
      () async {
        final firstManifest = DesktopManifest.starter().copyWith(revision: 40);
        final nextManifest = firstManifest.copyWith(revision: 41);
        final actionGate = Completer<void>(),
            laterManifestGate = Completer<void>();
        final server = await _ManifestServer.start(
          firstManifest,
          laterManifest: nextManifest,
          actionGate: actionGate,
          actionRevision: nextManifest.revision,
          laterManifestGate: laterManifestGate,
        );
        final sender = await RawDatagramSocket.bind(
          InternetAddress.loopbackIPv4,
          0,
        );
        // Bind atomically rather than reserving and releasing an ephemeral UDP
        // port that another test isolate could claim before Companion starts.
        final companion = LanCompanionService(
          discoveryPort: 0,
          now: () => DateTime.utc(2026),
        );
        addTearDown(() async {
          companion.dispose();
          sender.close();
          await server.close();
        });
        await companion.start();
        final discoveryPort = companion.boundDiscoveryPort!;
        final initiallyReady = _waitForCompanionState(
          companion,
          () =>
              companion.syncStatus.value == CompanionSyncStatus.ready &&
              companion.manifest.value?.revision == firstManifest.revision,
          'initial manifest ready',
        );
        _advertise(
          sender,
          discoveryPort: discoveryPort,
          name: 'Desktop A',
          port: server.port,
          token: 'token-a',
          revision: firstManifest.revision,
        );
        await initiallyReady;
        final action = companion.executeRemote(
          const RemoteActionRequest.button('chatgpt.codexMode'),
        );
        await server.actionRequestReceived.future.timeout(
          const Duration(seconds: 8),
        );
        final hostUpdated = _waitForCompanionState(
          companion,
          () => companion.activeHost.value?.revision == nextManifest.revision,
          'same-session advertisement received',
        );
        _advertise(
          sender,
          discoveryPort: discoveryPort,
          name: 'Desktop A',
          port: server.port,
          token: 'token-a',
          revision: nextManifest.revision,
        );
        await hostUpdated;
        await server.secondManifestRequestReceived.future.timeout(
          const Duration(seconds: 8),
        );
        if (manifestRespondsFirst) {
          final synchronized = _waitForCompanionState(
            companion,
            () =>
                companion.manifest.value?.revision == nextManifest.revision &&
                companion.syncStatus.value == CompanionSyncStatus.ready,
            'new manifest before action response',
          );
          laterManifestGate.complete();
          await synchronized;
          actionGate.complete();
          await action;
        } else {
          actionGate.complete();
          await action;
          expect(companion.manifest.value?.revision, firstManifest.revision);
          expect(companion.syncStatus.value, CompanionSyncStatus.syncing);
          final synchronized = _waitForCompanionState(
            companion,
            () =>
                companion.manifest.value?.revision == nextManifest.revision &&
                companion.syncStatus.value == CompanionSyncStatus.ready,
            'new manifest after action response',
          );
          laterManifestGate.complete();
          await synchronized;
        }
        expect(companion.manifest.value?.revision, nextManifest.revision);
        expect(companion.syncStatus.value, CompanionSyncStatus.ready);
        expect(companion.errorMessage.value, isNull);
        expect(server.manifestRequests, 2);
      },
    );
  }

  test(
    'manifest refresh keeps a newer revision queued during an in-flight fetch',
    () async {
      final firstManifest = DesktopManifest.starter().copyWith(revision: 50),
          nextManifest = DesktopManifest.starter().copyWith(revision: 51);
      final firstFetchGate = Completer<void>();
      final server = await _ManifestServer.start(
        firstManifest,
        laterManifest: nextManifest,
        firstManifestGate: firstFetchGate,
      );
      final sender = await RawDatagramSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final companion = _discoveryCompanion();
      addTearDown(() async {
        companion.dispose();
        sender.close();
        await server.close();
      });
      await companion.start();
      await _advertiseAndWait(
        sender,
        companion: companion,
        name: 'Desktop A',
        port: server.port,
        token: 'token-a',
        revision: firstManifest.revision,
        predicate: () =>
            companion.activeHost.value?.revision == firstManifest.revision,
        phase: 'initial host discovered before queued refresh',
      );
      await server.firstManifestRequestReceived.future.timeout(
        const Duration(seconds: 8),
      );
      await _advertiseAndWait(
        sender,
        companion: companion,
        name: 'Desktop A',
        port: server.port,
        token: 'token-a',
        revision: nextManifest.revision,
        predicate: () =>
            companion.activeHost.value?.revision == nextManifest.revision,
        phase: 'new revision queued during first HTTP response',
      );
      final synchronized = _waitForCompanionState(
        companion,
        () =>
            companion.manifest.value?.revision == nextManifest.revision &&
            companion.syncStatus.value == CompanionSyncStatus.ready,
        'queued newer manifest fully synchronized',
      );
      firstFetchGate.complete();
      await synchronized;
      expect(server.manifestRequests, 2);
    },
  );

  test('discovery timeout retains the last valid Desktop manifest', () async {
    final manifest = DesktopManifest.starter().copyWith(revision: 30);
    final server = await _ManifestServer.start(manifest);
    final sender = await RawDatagramSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    var now = DateTime.utc(2026);
    final companion = LanCompanionService(
      discoveryPort: 0,
      hostExpiry: const Duration(milliseconds: 80),
      expiryPollInterval: const Duration(milliseconds: 20),
      now: () => now,
    );
    addTearDown(() async {
      companion.dispose();
      sender.close();
      await server.close();
    });
    await companion.start();
    await _advertiseAndWait(
      sender,
      companion: companion,
      name: 'Desktop A',
      port: server.port,
      token: 'token-a',
      revision: manifest.revision,
      predicate: () =>
          companion.manifest.value?.revision == manifest.revision &&
          companion.syncStatus.value == CompanionSyncStatus.ready,
      phase: 'valid manifest synchronized before expiry',
    );
    final expired = _waitForCompanionState(
      companion,
      () =>
          companion.activeHost.value == null &&
          companion.syncStatus.value == CompanionSyncStatus.discovering,
      'discovery expiry after controlled clock advance',
    );
    now = now.add(const Duration(seconds: 1));
    await expired;
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

// Discovery tests own their socket for its full lifetime and freeze freshness
// unless clock-driven expiry is the behavior being tested.
LanCompanionService _discoveryCompanion() =>
    LanCompanionService(discoveryPort: 0, now: () => DateTime.utc(2026));

Future<void> _advertiseAndWait(
  RawDatagramSocket sender, {
  required LanCompanionService companion,
  required String name,
  required int port,
  required String token,
  required int revision,
  required bool Function() predicate,
  required String phase,
}) async {
  final observed = _waitForCompanionState(companion, predicate, phase);
  _advertise(
    sender,
    discoveryPort: companion.boundDiscoveryPort!,
    name: name,
    port: port,
    token: token,
    revision: revision,
  );
  await observed;
}

void _advertise(
  RawDatagramSocket sender, {
  required int discoveryPort,
  String platform = 'macos',
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
      'platform': platform,
      'port': port,
      'token': token,
      'revision': revision,
      'capabilities': ['manifest'],
    }),
  );
  sender.send(message, InternetAddress.loopbackIPv4, discoveryPort);
}

// Observe actual state transitions rather than polling every 20 ms against a
// two-second budget shorter than the production HTTP timeout on busy CI hosts.
Future<void> _waitForCompanionState(
  LanCompanionService companion,
  bool Function() predicate,
  String phase,
) async {
  final changes = Listenable.merge([
    companion.activeHost,
    companion.manifest,
    companion.syncStatus,
    companion.computerChoices,
  ]);
  final completed = Completer<void>();
  void check() {
    if (!completed.isCompleted && predicate()) completed.complete();
  }

  changes.addListener(check);
  try {
    check();
    await completed.future.timeout(
      const Duration(seconds: 8),
      onTimeout: () => throw TimeoutException(
        'Companion state did not reach: $phase',
        const Duration(seconds: 8),
      ),
    );
  } finally {
    changes.removeListener(check);
  }
}

class _ManifestServer {
  _ManifestServer(
    this._server, {
    this.laterManifest,
    this.firstManifestGate,
    this.actionGate,
    this.actionRevision,
    this.laterManifestGate,
  });

  final HttpServer _server;
  late final StreamSubscription<HttpRequest> _subscription;
  final DesktopManifest? laterManifest;
  final Completer<void>? firstManifestGate;
  final Completer<void>? actionGate;
  final int? actionRevision;
  final Completer<void>? laterManifestGate;
  final Completer<void> secondManifestRequestReceived = Completer<void>();
  final Completer<void> firstManifestRequestReceived = Completer<void>();
  final Completer<void> firstManifestResponseSent = Completer<void>();
  final Completer<void> actionRequestReceived = Completer<void>();
  int manifestRequests = 0;
  bool rejectActions = false;

  int get port => _server.port;

  static Future<_ManifestServer> start(
    DesktopManifest manifest, {
    DesktopManifest? laterManifest,
    Completer<void>? firstManifestGate,
    Completer<void>? actionGate,
    int? actionRevision,
    Completer<void>? laterManifestGate,
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final helper = _ManifestServer(
      server,
      laterManifest: laterManifest,
      firstManifestGate: firstManifestGate,
      actionGate: actionGate,
      actionRevision: actionRevision,
      laterManifestGate: laterManifestGate,
    );
    helper._subscription = server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      if (request.uri.path == '/action') {
        if (!helper.actionRequestReceived.isCompleted) {
          helper.actionRequestReceived.complete();
        }
        final actionGate = helper.actionGate;
        if (actionGate != null) await actionGate.future;
        if (helper.actionRevision != null) {
          request.response.statusCode = HttpStatus.ok;
          request.response.write(
            jsonEncode({'revision': helper.actionRevision}),
          );
          await request.response.close();
          return;
        }
        request.response.statusCode = helper.rejectActions
            ? 409
            : HttpStatus.notFound;
        request.response.write(jsonEncode({'error': 'action response'}));
        await request.response.close();
        return;
      }
      if (request.uri.path != '/manifest') {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }
      helper.manifestRequests++;
      final requestNumber = helper.manifestRequests;
      if (requestNumber == 2) helper.secondManifestRequestReceived.complete();
      if (requestNumber > 1 && helper.laterManifestGate != null) {
        await helper.laterManifestGate!.future;
      }
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
      if (requestNumber == 1) helper.firstManifestResponseSent.complete();
    });
    return helper;
  }

  Future<void> close() async {
    await _subscription.cancel();
    await _server.close(force: true);
  }
}
