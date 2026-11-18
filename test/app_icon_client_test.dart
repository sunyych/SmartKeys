import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as images;
import 'package:lumiakeys_protocol/lumiakeys_protocol.dart';
import 'package:path/path.dart' as path;
import 'package:smart_keys/data/private_image_store.dart';
import 'package:smart_keys/icons/app_icon_catalog.dart';
import 'package:smart_keys/icons/app_icon_validation.dart';
import 'package:smart_keys/services/companion_service.dart';

import 'test_support.dart';

Uint8List _png(int color) => Uint8List.fromList(
  images.encodePng(
    images.Image(width: 2, height: 2)..setPixelRgb(0, 0, color, 0, 0),
  ),
);

class _Icons extends RecordingCompanionService
    implements CompanionIconConnection {
  final requests = <String>[];
  Future<Uint8List?> Function(String)? onIcon;
  Uint8List? bytes;
  @override
  Future<Uint8List?> fetchApplicationIcon(String appId) async {
    requests.add(appId);
    return onIcon == null ? bytes : onIcon!(appId);
  }
}

void _connect(
  TestHarness harness, {
  String computer = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  int port = 45833,
}) {
  harness.companion.syncedManifest.value = DesktopManifest.regularStarter()
      .copyWith(computerId: computer);
  harness.companion.host.value = CompanionHost(
    name: 'Icon PC',
    computerId: computer,
    platform: 'windows',
    address: '192.168.1.20',
    port: port,
    token: 'icon-test-token',
    protocolVersion: 2,
    capabilities: {'manifest', 'app-icons-v1'},
  );
  harness.companion.status.value = CompanionSyncStatus.ready;
}

void main() {
  test(
    'installed native icon permission requires current slot flags and safe cache identity',
    () async {
      const id = 'installed.0123456789abcdef0123456789abcdef';
      const app = RemoteApplication(
        id: id,
        name: 'Word',
        icon: 'word',
        executable: 'Desktop-managed',
        layoutId: installedLaunchOnlyLayoutId,
        detected: true,
        launchOnly: true,
      );
      final service = _Icons()..bytes = _png(31);
      final harness = await TestHarness.create(companionService: service);
      addTearDown(harness.dispose);
      _connect(harness);
      final base = service.syncedManifest.value!;
      final manifest = base.copyWith(
        layouts: [...base.layouts, installedLaunchOnlyLayout],
        applications: [...base.applications, app],
        launcherApplicationIds: [id, ...List<String?>.filled(11, null)],
      );
      service.syncedManifest.value = manifest;
      expect(
        await harness.controller.loadDesktopApplicationIcon(id),
        service.bytes,
      );
      expect(service.requests, [id]);
      final cached = await harness.directory
          .list(recursive: true)
          .where((file) => file.path.endsWith('.png'))
          .toList();
      expect(cached, hasLength(1));
      expect(path.basename(cached.single.path), startsWith('${id}_'));
      service.syncedManifest.value = manifest.copyWith(
        launcherApplicationIds: List<String?>.filled(12, null),
      );
      expect(await harness.controller.loadDesktopApplicationIcon(id), isNull);
      service.syncedManifest.value = manifest.copyWith(
        settings: manifest.settings.copyWith(enableAppsSync: false),
      );
      expect(await harness.controller.loadDesktopApplicationIcon(id), isNull);
      service.syncedManifest.value = manifest.copyWith(
        settings: manifest.settings.copyWith(syncIcons: false),
      );
      expect(await harness.controller.loadDesktopApplicationIcon(id), isNull);
      service.syncedManifest.value = manifest.copyWith(
        applications: [...base.applications, app.copyWith(detected: false)],
      );
      expect(await harness.controller.loadDesktopApplicationIcon(id), isNull);
      service.syncedManifest.value = manifest.copyWith(
        applications: [...base.applications, app.copyWith(launchOnly: false)],
      );
      expect(await harness.controller.loadDesktopApplicationIcon(id), isNull);
      expect(
        await harness.controller.loadDesktopApplicationIcon(
          'installed.0123456789abcdef0123456789abcdef/../secret',
        ),
        isNull,
      );
      expect(service.requests, [id]);
      service.syncedManifest.value = manifest;
      expect(
        await harness.controller.loadDesktopApplicationIcon(id),
        service.bytes,
      );
      expect(service.requests, [id]);
    },
  );
  test('late installed icon is discarded after its slot is removed', () async {
    const id = 'installed.0123456789abcdef0123456789abcdef';
    const app = RemoteApplication(
      id: id,
      name: 'Word',
      icon: 'word',
      executable: 'Desktop-managed',
      layoutId: installedLaunchOnlyLayoutId,
      detected: true,
      launchOnly: true,
    );
    final started = Completer<void>(), bytes = Completer<Uint8List?>();
    final service = _Icons()
      ..onIcon = (_) {
        started.complete();
        return bytes.future;
      };
    final harness = await TestHarness.create(companionService: service);
    addTearDown(harness.dispose);
    _connect(harness);
    final base = service.syncedManifest.value!;
    service.syncedManifest.value = base.copyWith(
      layouts: [...base.layouts, installedLaunchOnlyLayout],
      applications: [...base.applications, app],
      launcherApplicationIds: [id, ...List<String?>.filled(11, null)],
    );
    final pending = harness.controller.loadDesktopApplicationIcon(id);
    await started.future;
    service.syncedManifest.value = service.syncedManifest.value!.copyWith(
      launcherApplicationIds: List<String?>.filled(12, null),
    );
    bytes.complete(_png(21));
    expect(await pending, isNull);
    final cached = await harness.directory
        .list(recursive: true)
        .where((file) => file.path.endsWith('.png'))
        .toList();
    expect(cached, isEmpty);
  });
  test(
    'authenticated HTTP native endpoint accepts assigned installed IDs and hides unslotted apps',
    () async {
      const token = '0123456789abcdef0123456789abcdef',
          id = 'installed.0123456789abcdef0123456789abcdef';
      const app = RemoteApplication(
        id: id,
        name: 'Word',
        icon: 'word',
        executable: 'Desktop-managed',
        layoutId: installedLaunchOnlyLayoutId,
        detected: true,
        launchOnly: true,
      );
      final base = DesktopManifest.regularStarter();
      var manifest = base.copyWith(
        layouts: [...base.layouts, installedLaunchOnlyLayout],
        applications: [...base.applications, app],
        launcherApplicationIds: [id, ...List<String?>.filled(11, null)],
      );
      final requested = <String>[], tokens = <String?>[];
      Completer<void>? heldIcon;
      final iconEntered = Completer<void>();
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final companion = LanCompanionService(enableDiscovery: false);
      addTearDown(() async {
        companion.dispose();
        await server.close(force: true);
      });
      server.listen((request) async {
        if (request.uri.path.startsWith('/icons/')) {
          requested.add(request.uri.path);
          tokens.add(request.headers.value('x-lumiakeys-token'));
          if (heldIcon case final hold?) {
            iconEntered.complete();
            await hold.future;
          }
          request.response.headers.contentType = ContentType('image', 'png');
          request.response.add(_png(77));
        } else {
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode(
              request.uri.path == '/info'
                  ? {
                      'name': 'Apps',
                      'platform': 'windows',
                      'version': 2,
                      'revision': manifest.revision,
                      'capabilities': [
                        'manifest',
                        'app-icons-v1',
                        'installed-launcher-v1',
                      ],
                    }
                  : manifest.toJson(forSync: true),
            ),
          );
        }
        await request.response.close();
      });
      await companion.connectManually('127.0.0.1:${server.port} $token');
      expect(await companion.fetchApplicationIcon(id), _png(77));
      expect(tokens, [token]);
      expect(
        await companion.fetchApplicationIcon(
          'installed.0123456789abcdef0123456789abcdeZ',
        ),
        isNull,
      );
      expect(
        await companion.fetchApplicationIcon(
          'installed.0123456789abcdef0123456789abcdef/../../x',
        ),
        isNull,
      );
      heldIcon = Completer<void>();
      final pending = companion.fetchApplicationIcon(id);
      await iconEntered.future;
      manifest = manifest.copyWith(
        revision: 2,
        launcherApplicationIds: List<String?>.filled(12, null),
      );
      await companion.refreshManifest();
      heldIcon.complete();
      expect(await pending, isNull);
      expect(await companion.fetchApplicationIcon(id), isNull);
      expect(requested, ['/icons/$id', '/icons/$id']);
      manifest = manifest.copyWith(
        revision: 3,
        launcherApplicationIds: [id, ...List<String?>.filled(11, null)],
        settings: manifest.settings.copyWith(enableAppsSync: false),
      );
      await companion.refreshManifest();
      expect(await companion.fetchApplicationIcon(id), isNull);
      expect(requested, hasLength(2));
    },
  );
  test(
    'PNG validation rejects excessive dimensions, payloads and invalid decoders',
    () {
      final valid = _png(120);
      expect(AppIconValidation.isValidPng(valid), isTrue);
      final enormous = Uint8List.fromList(valid);
      ByteData.sublistView(enormous).setUint32(16, 1000000);
      expect(AppIconValidation.isValidPng(enormous), isFalse);
      expect(AppIconValidation.isValidPng(Uint8List(65537)), isFalse);
      expect(
        AppIconValidation.isValidPng(Uint8List.sublistView(valid, 0, 33)),
        isFalse,
      );
    },
  );

  test(
    'native icons persist, survive Desktop port restart and ignore unrelated revision changes',
    () async {
      final service = _Icons()..bytes = _png(80);
      final harness = await TestHarness.create(companionService: service);
      addTearDown(harness.dispose);
      _connect(harness);
      final scope = harness.controller.desktopIconScope;
      expect(
        await harness.controller.loadDesktopApplicationIcon('chrome'),
        service.bytes,
      );
      expect(service.requests, ['chrome']);
      service.syncedManifest.value = service.syncedManifest.value!.copyWith(
        revision: 30,
      );
      expect(
        await harness.controller.loadDesktopApplicationIcon('chrome'),
        service.bytes,
      );
      expect(service.requests, ['chrome']);
      _connect(harness, port: 45999);
      expect(harness.controller.desktopIconScope, scope);
      expect(
        await harness.controller.loadDesktopApplicationIcon('chrome'),
        service.bytes,
      );
      final files =
          await Directory(
                path.join(harness.directory.path, 'desktop_app_icons'),
              )
              .list(recursive: true)
              .where((entry) => entry is File && entry.path.endsWith('.png'))
              .cast<File>()
              .toList();
      expect(files, hasLength(1));
      final restartedStore = PrivateImageStore(
        documentsDirectory: () async => harness.directory,
      );
      expect(
        await restartedStore.readDesktopAppIcon(
          scope!,
          path.basenameWithoutExtension(files.single.path),
        ),
        service.bytes,
      );
    },
  );

  test(
    'application identity changes refresh native data while icon sync off hides cached bytes',
    () async {
      final service = _Icons()..bytes = _png(10);
      final harness = await TestHarness.create(companionService: service);
      addTearDown(harness.dispose);
      _connect(harness);
      await harness.controller.loadDesktopApplicationIcon('chrome');
      final manifest = service.syncedManifest.value!;
      service.bytes = _png(220);
      service.syncedManifest.value = manifest.copyWith(
        applications: [
          for (final app in manifest.applications)
            app.id == 'chrome'
                ? app.copyWith(executable: 'Updated Chrome')
                : app,
        ],
      );
      expect(
        await harness.controller.loadDesktopApplicationIcon('chrome'),
        service.bytes,
      );
      expect(service.requests, ['chrome', 'chrome']);
      final current = service.syncedManifest.value!;
      service.syncedManifest.value = current.copyWith(
        settings: current.settings.copyWith(syncIcons: false),
      );
      expect(
        await harness.controller.loadDesktopApplicationIcon('chrome'),
        isNull,
      );
      expect(harness.controller.desktopIconScope, isNull);
      expect(service.requests, hasLength(2));
      service.syncedManifest.value = current;
      expect(
        await harness.controller.loadDesktopApplicationIcon('chrome'),
        service.bytes,
      );
      expect(service.requests, hasLength(2));
      expect(
        await harness.controller.loadDesktopApplicationIcon('../unknown'),
        isNull,
      );
    },
  );

  test(
    'late native data from another computer is discarded rather than cached',
    () async {
      final gate = Completer<Uint8List?>();
      final requested = Completer<void>();
      final service = _Icons()
        ..onIcon = (_) {
          requested.complete();
          return gate.future;
        };
      final harness = await TestHarness.create(companionService: service);
      addTearDown(harness.dispose);
      _connect(harness);
      final loading = harness.controller.loadDesktopApplicationIcon('chrome');
      await requested.future;
      _connect(harness, computer: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb');
      gate.complete(_png(150));
      expect(await loading, isNull);
      final directory = Directory(
        path.join(harness.directory.path, 'desktop_app_icons'),
      );
      expect(await directory.exists(), isFalse);
    },
  );

  test('persistent native PNG expires after twenty-four hours', () async {
    final directory = await Directory.systemTemp.createTemp('icon-expiry-');
    addTearDown(() => directory.delete(recursive: true));
    final store = PrivateImageStore(documentsDirectory: () async => directory);
    const computer = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    await store.cacheDesktopAppIcon(computer, 'chrome', _png(55));
    final file = File(
      path.join(directory.path, 'desktop_app_icons', computer, 'chrome.png'),
    );
    await file.setLastModified(
      DateTime.now().subtract(const Duration(hours: 25)),
    );
    expect(await store.readDesktopAppIcon(computer, 'chrome'), isNull);
  });

  test(
    'central catalog only fetches registered IDs and refuses redirects and invalid PNG',
    () async {
      AppIconCache.clear();
      final claude = await File('assets/app_icons/claude.png').readAsBytes();
      final paths = <String>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        paths.add(request.uri.path);
        if (request.uri.path.endsWith('/chrome')) {
          request.response.statusCode = HttpStatus.found;
          request.response.headers.set(
            HttpHeaders.locationHeader,
            '/redirect-target',
          );
        } else {
          request.response.headers.contentType = ContentType('image', 'png');
          request.response.add(
            request.uri.path.endsWith('/claude')
                ? claude
                : request.uri.path.endsWith('/vscode')
                ? _png(200)
                : Uint8List(65537),
          );
        }
        await request.response.close();
      });
      final client = IconCatalogClient(
        baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
        allowLoopbackHttp: true,
      );
      expect(await client.downloadByAppId('../arbitrary'), isNull);
      expect(paths, isEmpty);
      expect(await client.downloadByAppId('chrome'), isNull);
      expect(await client.downloadByAppId('edge'), isNull);
      expect(await client.downloadByAppId('vscode'), isNull);
      expect(await client.downloadByAppId('claude'), claude);
      expect(paths, [
        '/v1/icons/chrome',
        '/v1/icons/edge',
        '/v1/icons/vscode',
        '/v1/icons/claude',
      ]);
      expect(await client.downloadByAppId('claude'), claude);
      expect(paths, hasLength(4));
      AppIconCache.clear();
    },
  );

  test(
    'native resource uses pairing authentication and obeys icon sync setting',
    () async {
      const token = '0123456789abcdef0123456789abcdef';
      var manifest = DesktopManifest.regularStarter();
      final iconRequests = <String?>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final companion = LanCompanionService(enableDiscovery: false);
      addTearDown(() async {
        companion.dispose();
        await server.close(force: true);
      });
      server.listen((request) async {
        if (request.uri.path == '/icons/chrome') {
          iconRequests.add(request.headers.value('x-lumiakeys-token'));
          request.response.headers.contentType = ContentType('image', 'png');
          request.response.add(_png(90));
        } else {
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode(
              request.uri.path == '/info'
                  ? {
                      'name': 'Icons',
                      'platform': 'windows',
                      'version': 2,
                      'revision': manifest.revision,
                      'capabilities': ['manifest', 'app-icons-v1'],
                    }
                  : manifest.toJson(forSync: true),
            ),
          );
        }
        await request.response.close();
      });
      // The app must be present in the synced manifest to request its resource.
      manifest = manifest.copyWith(
        applications: [
          for (final app in manifest.applications)
            app.copyWith(detected: app.id == 'chrome'),
        ],
      );
      await companion.connectManually('127.0.0.1:${server.port} $token');
      expect(await companion.fetchApplicationIcon('chrome'), _png(90));
      expect(iconRequests, [token]);
      manifest = manifest.copyWith(
        revision: 2,
        settings: manifest.settings.copyWith(syncIcons: false),
      );
      await companion.refreshManifest();
      expect(await companion.fetchApplicationIcon('chrome'), isNull);
      expect(iconRequests, hasLength(1));
    },
  );
}
