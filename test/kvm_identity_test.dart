import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumiakeys_protocol/lumiakeys_protocol.dart';
import 'package:smart_keys/services/companion_service.dart';

void main() {
  test(
    'stable identity survives a changed advertised port and restart',
    () async {
      final sender = await RawDatagramSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final first = LanCompanionService(discoveryPort: 0);
      addTearDown(sender.close);
      var firstDisposed = false;
      addTearDown(() {
        if (!firstDisposed) first.dispose();
      });
      await first.start();
      await first.suspendComputerSelection();
      final discoveryPort = first.boundDiscoveryPort!;
      _advertise(
        sender,
        discoveryPort: discoveryPort,
        name: 'Studio',
        port: 41001,
        token: 'token-a',
        computerId: 'machine-a',
      );
      await _waitUntil(() => first.computerChoices.value.length == 1);
      final originalId = first.computerChoices.value.single.id;

      await _observeAdvertisement(
        first,
        () => _advertise(
          sender,
          discoveryPort: discoveryPort,
          name: 'Studio',
          port: 41002,
          token: 'token-a',
          computerId: 'machine-a',
        ),
      );
      expect(first.computerChoices.value.single.id, originalId);
      _advertise(
        sender,
        discoveryPort: discoveryPort,
        name: 'Studio',
        port: 41004,
        token: 'token-b',
        computerId: 'machine-b',
      );
      await _waitUntil(
        () => first.computerChoices.value.any(
          (choice) => choice.id == 'id:machine-b',
        ),
      );
      expect(
        first.computerChoices.value.map((choice) => choice.id),
        unorderedEquals([originalId, 'id:machine-b']),
      );
      first.dispose();
      firstDisposed = true;

      final restarted = LanCompanionService(discoveryPort: 0);
      addTearDown(restarted.dispose);
      await restarted.start();
      await restarted.suspendComputerSelection();
      _advertise(
        sender,
        discoveryPort: restarted.boundDiscoveryPort!,
        name: 'Studio',
        port: 41003,
        token: 'token-a',
        computerId: 'machine-a',
      );
      await _waitUntil(() => restarted.computerChoices.value.length == 1);
      expect(restarted.computerChoices.value.single.id, originalId);
    },
  );

  test(
    'manual and legacy discovery records merge by manifest identity',
    () async {
      const token = '0123456789abcdef0123456789abcdef';
      final server = await _IdentityServer.start(
        token: token,
        id: 'legacy-box',
      );
      final sender = await RawDatagramSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final companion = LanCompanionService(discoveryPort: 0);
      addTearDown(() async {
        companion.dispose();
        sender.close();
        await server.close();
      });
      await companion.start();
      await companion.connectManually('127.0.0.1:${server.port} $token');
      expect(companion.syncStatus.value, CompanionSyncStatus.ready);
      expect(companion.manifest.value?.revision, 13);
      await _observeAdvertisement(
        companion,
        () => _advertise(
          sender,
          discoveryPort: companion.boundDiscoveryPort!,
          platform: 'windows',
          name: 'Identity Test Desktop',
          port: server.port,
          token: token,
          revision: 13,
        ),
      );
      expect(companion.computerChoices.value.map((choice) => choice.id), [
        'id:legacy-box',
      ]);
      expect(companion.selectedComputerChoiceId, 'id:legacy-box');
    },
  );

  test(
    'selected discovered computer remains active during rediscovery',
    () async {
      const tokenA = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
      const tokenB = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
      final serverA = await _IdentityServer.start(
        token: tokenA,
        id: 'computer-a',
        name: 'Computer A',
      );
      final serverB = await _IdentityServer.start(
        token: tokenB,
        id: 'computer-b',
        name: 'Computer B',
      );
      final sender = await RawDatagramSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final companion = LanCompanionService(discoveryPort: 0);
      addTearDown(() async {
        companion.dispose();
        sender.close();
        await serverA.close();
        await serverB.close();
      });
      await companion.start();
      final discoveryPort = companion.boundDiscoveryPort!;
      await _waitUntil(
        () => companion.activeHost.value?.port == serverA.port,
        advertise: () => _advertise(
          sender,
          discoveryPort: discoveryPort,
          platform: 'windows',
          name: 'Computer A',
          port: serverA.port,
          token: tokenA,
        ),
      );
      await _waitUntil(
        () => companion.computerChoices.value.any(
          (choice) => choice.name == 'Computer B',
        ),
        advertise: () => _advertise(
          sender,
          discoveryPort: discoveryPort,
          platform: 'windows',
          name: 'Computer B',
          port: serverB.port,
          token: tokenB,
        ),
      );
      final choiceB = companion.computerChoices.value.singleWhere(
        (choice) => choice.name == 'Computer B',
      );
      expect(choiceB.id, isNot(contains(tokenB)));
      await companion.selectComputer(choiceB.id);
      expect(companion.activeHost.value?.port, serverB.port);
      expect(companion.selectedComputerChoiceId, 'id:computer-b');
      await _observeAdvertisement(
        companion,
        () => _advertise(
          sender,
          discoveryPort: discoveryPort,
          platform: 'windows',
          name: 'Computer A',
          port: serverA.port,
          token: tokenA,
        ),
      );
      expect(companion.activeHost.value?.port, serverB.port);
      expect(companion.computerChoices.value, hasLength(2));
    },
  );
}

Future<void> _observeAdvertisement(
  LanCompanionService companion,
  void Function() advertise,
) async {
  final choices = companion.computerChoices;
  final observed = Completer<void>();
  void onChoicesChanged() {
    if (!observed.isCompleted) observed.complete();
  }

  choices.addListener(onChoicesChanged);
  try {
    advertise();
    await observed.future.timeout(const Duration(seconds: 2));
  } finally {
    choices.removeListener(onChoicesChanged);
  }
}

void _advertise(
  RawDatagramSocket sender, {
  required int discoveryPort,
  String platform = 'macos',
  required String name,
  required int port,
  required String token,
  int revision = 1,
  String? computerId,
}) {
  final payload = utf8.encode(
    jsonEncode({
      'service': 'lumiakeys-companion',
      'version': 2,
      'name': name,
      'platform': platform,
      'computerId': ?computerId,
      'port': port,
      'token': token,
      'revision': revision,
      'capabilities': ['manifest'],
    }),
  );
  sender.send(payload, InternetAddress.loopbackIPv4, discoveryPort);
}

Future<void> _waitUntil(
  bool Function() condition, {
  void Function()? advertise,
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('Condition was not met');
    }
    advertise?.call();
    await Future<void>.delayed(
      Duration(milliseconds: advertise == null ? 20 : 100),
    );
  }
}

class _IdentityServer {
  _IdentityServer(this._server);
  final HttpServer _server;
  late final StreamSubscription<HttpRequest> _subscription;
  int get port => _server.port;

  static Future<_IdentityServer> start({
    required String token,
    required String id,
    String name = 'Identity Test Desktop',
  }) async {
    final http = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fixture = _IdentityServer(http);
    fixture._subscription = http.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      if (request.headers.value('x-lumiakeys-token') != token) {
        request.response.statusCode = HttpStatus.forbidden;
      } else if (request.uri.path == '/info') {
        request.response.write(
          jsonEncode({
            'name': name,
            'platform': 'windows',
            'version': 2,
            'capabilities': ['manifest'],
            'revision': 13,
          }),
        );
      } else if (request.uri.path == '/manifest') {
        request.response.write(
          jsonEncode(
            DesktopManifest.starter()
                .copyWith(revision: 13, computerId: id)
                .toJson(forSync: true),
          ),
        );
      } else {
        request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });
    return fixture;
  }

  Future<void> close() async {
    await _subscription.cancel();
    await _server.close(force: true);
  }
}
