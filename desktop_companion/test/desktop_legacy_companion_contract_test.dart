import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:lumiakeys_companion/companion_server.dart';
import 'package:lumiakeys_companion/desktop_actions.dart';
import 'package:lumiakeys_companion/desktop_controller.dart';
import 'package:lumiakeys_companion/installed_app_registry.dart';
import 'package:lumiakeys_protocol/lumiakeys_protocol.dart';

class _DetectedApps implements ApplicationDiscovery {
  @override
  Future<List<RemoteApplication>> refresh(List<RemoteApplication> apps) async =>
      apps.map((app) => app.copyWith(detected: true)).toList();
}

class _DesktopActions extends DesktopActions {
  _DesktopActions({
    required TargetPlatform platform,
    this.pointerSupported = true,
  }) : super(platformOverride: platform, environment: const {});

  final bool pointerSupported;
  final launches = <String>[];
  final pointerBatches = <List<PointerInput>>[];
  final imageBytes = Uint8List.fromList(
    image.encodePng(image.Image(width: 2, height: 2)),
  );
  bool failLaunch = false;
  bool failPointer = false;
  Completer<Uint8List?>? iconResult;
  final iconStarted = Completer<void>();

  @override
  Future<void> activateApplication(RemoteApplication app) async {
    launches.add(app.id);
    if (failLaunch) throw StateError('Synthetic launch failure');
  }

  @override
  Future<bool> probePointerSupport() async => pointerSupported;

  @override
  Future<void> applyPointerInputs(List<PointerInput> inputs) async {
    pointerBatches.add(List.of(inputs));
    if (failPointer) throw StateError('Synthetic pointer failure');
  }

  @override
  Future<Uint8List?> getApplicationIcon(RemoteApplication app) async {
    if (!iconStarted.isCompleted) iconStarted.complete();
    final pending = iconResult;
    if (pending != null) return pending.future;
    return imageBytes;
  }
}

typedef _Fixture = ({
  CompanionServer server,
  DesktopController controller,
  _DesktopActions actions,
  HttpClient client,
});

Future<_Fixture> _start({
  TargetPlatform platform = TargetPlatform.windows,
  bool pointerSupported = true,
  InstalledAppRegistry? installedRegistry,
}) async {
  final actions = _DesktopActions(
    platform: platform,
    pointerSupported: pointerSupported,
  );
  final controller = DesktopController(
    store: MemoryDesktopConfigStore(),
    discovery: _DetectedApps(),
    actions: actions,
    installedRegistry: installedRegistry,
  );
  addTearDown(controller.dispose);
  await controller.initialize();
  final server = CompanionServer(controller: controller, discoveryPort: 0);
  addTearDown(server.dispose);
  await server.start();
  expect(server.running, isTrue);
  final client = HttpClient();
  addTearDown(() => client.close(force: true));
  return (
    server: server,
    controller: controller,
    actions: actions,
    client: client,
  );
}

Future<HttpClientResponse> _request(
  _Fixture fixture,
  String method,
  String path, {
  Object? body,
  String? rawBody,
  String? token,
  String? ifNoneMatch,
}) async {
  final request = await fixture.client.open(
    method,
    InternetAddress.loopbackIPv4.address,
    fixture.server.actionPort!,
    path,
  );
  request.headers.set('x-lumiakeys-token', token ?? fixture.server.token);
  if (ifNoneMatch != null) {
    request.headers.set(HttpHeaders.ifNoneMatchHeader, ifNoneMatch);
  }
  if (body != null || rawBody != null) {
    request.headers.contentType = ContentType.json;
    request.write(rawBody ?? jsonEncode(body));
  }
  return request.close();
}

Future<Map<String, Object?>> _json(HttpClientResponse response) async =>
    (jsonDecode(await utf8.decoder.bind(response).join()) as Map)
        .cast<String, Object?>();

void main() {
  test(
    'starting a running server preserves its listener and session',
    () async {
      final fixture = await _start();
      final server = fixture.server;
      final originalPort = server.actionPort;
      final originalToken = server.token;

      await server.start();
      expect(server.actionPort, originalPort);
      expect(server.token == originalToken, isTrue);

      final other = await _start();
      expect(other.server.token == originalToken, isFalse);
      final crossHost = await _request(
        other,
        'GET',
        '/info',
        token: originalToken,
      );
      expect(crossHost.statusCode, HttpStatus.forbidden);
      expect(await _json(crossHost), {'error': 'forbidden'});

      final info = await _json(await _request(fixture, 'GET', '/info'));
      final manifestPublished = Completer<void>();
      void onManifestPublished() {
        if (!manifestPublished.isCompleted) manifestPublished.complete();
      }

      server.addListener(onManifestPublished);
      late final Map<String, Object?> manifest;
      try {
        manifest = await _json(await _request(fixture, 'GET', '/manifest'));
        await manifestPublished.future.timeout(const Duration(seconds: 2));
      } finally {
        server.removeListener(onManifestPublished);
      }
      expect(info.containsKey('token'), isFalse);
      expect(manifest.containsKey('token'), isFalse);
      expect(info['computerId'], fixture.controller.manifest.computerId);
      expect(manifest['computerId'], info['computerId']);
      expect(manifest['revision'], info['revision']);
    },
  );

  test(
    'action body byte limit accepts 16 KiB and rejects the next byte',
    () async {
      final fixture = await _start();
      final initialRevision = fixture.controller.manifest.revision;
      final profile = fixture.controller.manifest.profiles.first.id;
      final action = jsonEncode(
        RemoteActionRequest.switchProfile(profile).toJson(),
      );
      final atLimit = action.padRight(16 * 1024);
      final oversized = await _request(
        fixture,
        'POST',
        '/action',
        rawBody: '$atLimit ',
      );
      expect(oversized.statusCode, HttpStatus.requestEntityTooLarge);
      expect(await _json(oversized), {'error': 'action too large'});
      expect(fixture.controller.manifest.revision, initialRevision);
      expect(fixture.controller.connectedPhone, isNull);

      final accepted = await _request(
        fixture,
        'POST',
        '/action',
        rawBody: atLimit,
      );
      expect(accepted.statusCode, HttpStatus.ok);
      expect(await _json(accepted), {
        'ok': true,
        'revision': initialRevision + 1,
      });
      expect(fixture.controller.connectedPhone, isNotNull);
    },
  );

  test(
    'launch response publishes only successful enabled host actions',
    () async {
      final fixture = await _start();
      final launch = const RemoteActionRequest.launchApplication(
        'chrome',
      ).toJson();
      final initial = fixture.controller.manifest;

      fixture.actions.failLaunch = true;
      final failed = await _request(fixture, 'POST', '/action', body: launch);
      expect(failed.statusCode, HttpStatus.badRequest);
      expect(
        (await _json(failed))['error'],
        contains('Synthetic launch failure'),
      );
      expect(
        fixture.controller.manifest.applicationActivationSequence,
        initial.applicationActivationSequence,
      );
      expect(fixture.controller.manifest.revision, initial.revision);
      expect(fixture.controller.connectedPhone, isNull);

      fixture.actions.failLaunch = false;
      final success = await _request(fixture, 'POST', '/action', body: launch);
      expect(success.statusCode, HttpStatus.ok);
      expect(await _json(success), {
        'ok': true,
        'revision': initial.revision + 1,
      });
      expect(fixture.controller.manifest.activatedApplicationId, 'chrome');
      expect(
        fixture.controller.manifest.applicationActivationSequence,
        initial.applicationActivationSequence + 1,
      );

      await fixture.controller.updateSettings(
        fixture.controller.manifest.settings.copyWith(autoLaunchApps: false),
      );
      final disabled = await _request(fixture, 'POST', '/action', body: launch);
      expect(disabled.statusCode, HttpStatus.badRequest);
      expect(
        (await _json(disabled))['error'],
        contains('Automatic app launching is disabled'),
      );
      expect(fixture.actions.launches, ['chrome', 'chrome']);
    },
  );

  test(
    'pointer batch limit and element validation reject the entire batch',
    () async {
      final fixture = await _start();
      final move = const PointerInput.move(1, -1).toJson();
      final invalidPayloads = [
        {'inputs': List.filled(33, move)},
        {
          'inputs': [
            move,
            {'kind': 'move', 'x': 128, 'y': 0},
          ],
        },
      ];
      for (final payload in invalidPayloads) {
        final rejected = await _request(
          fixture,
          'POST',
          '/pointer',
          body: payload,
        );
        expect(rejected.statusCode, HttpStatus.badRequest);
        await rejected.drain<void>();
      }
      expect(fixture.actions.pointerBatches, isEmpty);
      expect(fixture.controller.connectedPhone, isNull);

      final atLimit = {'inputs': List.filled(32, move)};
      fixture.actions.failPointer = true;
      final failed = await _request(fixture, 'POST', '/pointer', body: atLimit);
      expect(failed.statusCode, HttpStatus.badRequest);
      await failed.drain<void>();
      expect(fixture.actions.pointerBatches, hasLength(1));
      expect(fixture.controller.connectedPhone, isNull);

      fixture.actions.failPointer = false;
      final accepted = await _request(
        fixture,
        'POST',
        '/pointer',
        body: atLimit,
      );
      expect(accepted.statusCode, HttpStatus.ok);
      expect(await _json(accepted), {'ok': true});
      expect(fixture.actions.pointerBatches.map((batch) => batch.length), [
        32,
        32,
      ]);
      expect(fixture.controller.connectedPhone, isNotNull);
    },
  );

  test(
    'unsupported desktop input capabilities return 501 without dispatch',
    () async {
      final fixture = await _start(
        platform: TargetPlatform.linux,
        pointerSupported: false,
      );
      expect(fixture.server.capabilities, isNot(contains('mouse-control-v1')));
      expect(
        fixture.server.capabilities,
        isNot(contains('local-dictation-v1')),
      );
      final pointer = await _request(fixture, 'POST', '/pointer', rawBody: '{');
      expect(pointer.statusCode, HttpStatus.notImplemented);
      expect(await _json(pointer), {'error': 'pointer unsupported'});
      final dictation = await _request(
        fixture,
        'POST',
        '/dictation',
        rawBody: '{',
      );
      expect(dictation.statusCode, HttpStatus.notImplemented);
      expect(await _json(dictation), {
        'error': 'dictation unsupported on this platform',
      });
      expect(fixture.actions.pointerBatches, isEmpty);
      expect(fixture.controller.connectedPhone, isNull);
    },
  );

  test(
    'icons keep authenticated cache headers and support weak tag lists',
    () async {
      final fixture = await _start();
      final icon = await _request(fixture, 'GET', '/icons/chrome');
      expect(icon.statusCode, HttpStatus.ok);
      expect(
        icon.headers.value(HttpHeaders.cacheControlHeader),
        'private, max-age=300',
      );
      expect(icon.headers.value(HttpHeaders.varyHeader), 'x-lumiakeys-token');
      expect(icon.headers.value('x-content-type-options'), 'nosniff');
      final tag = icon.headers.value(HttpHeaders.etagHeader)!;
      await icon.drain<void>();

      final revalidation = await _request(
        fixture,
        'GET',
        '/icons/chrome',
        ifNoneMatch: '"different", W/$tag',
      );
      expect(revalidation.statusCode, HttpStatus.notModified);
      expect(revalidation.headers.value(HttpHeaders.etagHeader), tag);
      expect(
        await revalidation.fold<int>(
          0,
          (length, bytes) => length + bytes.length,
        ),
        0,
      );
    },
  );

  test(
    'an icon extraction completing after sync is revoked returns no image',
    () async {
      final fixture = await _start();
      final pending = Completer<Uint8List?>();
      fixture.actions.iconResult = pending;
      final request = _request(fixture, 'GET', '/icons/chrome');
      try {
        await fixture.actions.iconStarted.future.timeout(
          const Duration(seconds: 2),
        );
        await fixture.controller.updateSettings(
          fixture.controller.manifest.settings.copyWith(syncIcons: false),
        );
      } finally {
        pending.complete(fixture.actions.imageBytes);
      }
      final response = await request;
      expect(response.statusCode, HttpStatus.notFound);
      expect(await _json(response), {'error': 'icon not found'});
    },
  );

  test(
    'clearing the last launch slot revokes an in-flight registered icon',
    () async {
      final target = InstalledLaunchTarget.discovered(
        name: 'Fixture App',
        kind: InstalledLaunchKind.windowsAppId,
        identity: 'FixtureApp!Main',
        locator: 'FixtureApp!Main',
      );
      final fixture = await _start(
        installedRegistry: InstalledAppRegistry(
          discover: () async => [target],
          validate: (_) async => true,
        ),
      );
      await fixture.controller.assignLauncherApp(0, target.id);
      final pending = Completer<Uint8List?>();
      fixture.actions.iconResult = pending;
      final request = _request(fixture, 'GET', '/icons/${target.id}');
      try {
        await fixture.actions.iconStarted.future.timeout(
          const Duration(seconds: 2),
        );
        await fixture.controller.assignLauncherApp(0, null);
      } finally {
        pending.complete(fixture.actions.imageBytes);
      }
      final response = await request;
      expect(response.statusCode, HttpStatus.notFound);
      expect(await _json(response), {'error': 'icon not found'});
      expect(
        fixture.controller.installedRegistry.resolve(target.id),
        isNotNull,
      );
    },
  );
}
