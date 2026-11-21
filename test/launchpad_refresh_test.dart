import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:lumiakeys_protocol/lumiakeys_protocol.dart';
import 'package:smart_keys/icons/app_icon_catalog.dart';
import 'package:smart_keys/services/companion_service.dart';

import 'regular_home_test_support.dart';
import 'test_support.dart';

Uint8List _png(int red) => Uint8List.fromList(
  image.encodePng(
    image.Image(width: 2, height: 2)..setPixelRgb(0, 0, red, 20, 30),
  ),
);

const _nativeAppId = 'installed.0123456789abcdef0123456789abcdef';
const _nativeIconId = 'custom-browser';

class _NativeIcons extends RecordingCompanionService
    implements CompanionIconConnection {
  final requests = <String>[];
  Uint8List png = _png(30);
  @override
  Future<Uint8List?> fetchApplicationIcon(String id) async {
    requests.add(id);
    return png;
  }
}

Future<TestHarness> _mount(WidgetTester tester, _NativeIcons service) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(844, 390);
  late TestHarness harness;
  await tester.runAsync(() async {
    harness = await TestHarness.create(companionService: service);
    final starter = DesktopManifest.starter();
    const app = RemoteApplication(
      id: _nativeAppId,
      name: 'Custom browser',
      icon: _nativeIconId,
      executable: 'Desktop-managed',
      layoutId: installedLaunchOnlyLayoutId,
      detected: true,
      launchOnly: true,
    );
    connectRegularHarness(
      harness,
      manifest: starter.copyWith(
        layouts: [...starter.layouts, installedLaunchOnlyLayout],
        applications: [...starter.applications, app],
        launcherApplicationIds: [app.id, ...List<String?>.filled(11, null)],
      ),
      installed: const {_nativeAppId},
      launcherSlots: [_nativeAppId, ...List<String?>.filled(11, null)],
    );
    service.host.value = _host('first');
    await harness.controller.loadDesktopApplicationIcon(_nativeAppId);
  });
  await tester.pumpWidget(regularTestApp(harness));
  await tester.pumpAndSettle();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    await harness.dispose();
  });
  return harness;
}

CompanionHost _host(String computer) => CompanionHost(
  name: computer,
  computerId: computer,
  platform: 'windows',
  address: computer == 'first' ? '192.168.1.20' : '192.168.1.21',
  port: 45833,
  token: 'fixture-$computer',
  capabilities: const {'manifest', 'app-icons-v1', 'mouse-control-v1'},
);

Finder _artwork() => find.descendant(
  of: find.byKey(const ValueKey('regular-launch-$_nativeAppId')),
  matching: find.byType(AppArtwork),
);
Finder _future() => find
    .ancestor(
      of: _artwork(),
      matching: find.byWidgetPredicate(
        (widget) => widget is FutureBuilder<Uint8List?>,
      ),
    )
    .first;

Future<void> _waitForNativeImage(
  WidgetTester tester,
  Uint8List expected,
) async {
  final elapsed = Stopwatch()..start();
  while (!listEquals(
    tester.widget<AppArtwork>(_artwork()).pngBytes,
    expected,
  )) {
    if (elapsed.elapsed > const Duration(seconds: 5)) {
      fail('The actual Launchpad widget did not receive its native image.');
    }
    // File I/O finishes in the real event loop; its widget completion needs a
    // fake-async frame. Do not await that widget Future inside runAsync.
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'duplicate sync, runtime revisions and clock keep loaded Launchpad image in every frame',
    (tester) async {
      final service = _NativeIcons();
      final harness = await _mount(tester, service);
      final firstImage = tester.widget<AppArtwork>(_artwork()).pngBytes;
      final firstFutureState = tester.state(_future());
      final gridElement = tester.element(
        find.byKey(const ValueKey('regular-twelve-key-grid')),
      );
      final padElement = tester.element(
        find.byKey(const ValueKey('regular-touchpad')),
      );
      expect(firstImage, service.png);
      expect(service.requests, [_nativeAppId]);
      final original = service.syncedManifest.value!;
      for (var iteration = 0; iteration < 3; iteration++) {
        service.status.value = CompanionSyncStatus.syncing;
        await tester.pump();
        expect(
          tester.element(find.byKey(const ValueKey('regular-twelve-key-grid'))),
          same(gridElement),
        );
        expect(
          tester.element(find.byKey(const ValueKey('regular-touchpad'))),
          same(padElement),
        );
        service.syncedManifest.value = original.copyWith(
          revision: original.revision + iteration + 1,
          applications: [
            for (final app in original.applications)
              app.copyWith(
                running: iteration.isEven,
                foreground: iteration.isOdd,
              ),
          ],
        );
        service.status.value = CompanionSyncStatus.ready;
        // Inspect the first frame, before a replacement Future can complete.
        await tester.pump();
        expect(tester.state(_future()), same(firstFutureState));
        expect(
          tester.widget<AppArtwork>(_artwork()).pngBytes,
          same(firstImage),
        );
        await tester.pump(const Duration(seconds: 1));
        expect(
          tester.widget<AppArtwork>(_artwork()).pngBytes,
          same(firstImage),
        );
      }
      expect(service.requests, [_nativeAppId]);
      expect(harness.companion.remoteActions, isEmpty);
    },
  );

  testWidgets(
    'actual per-App artwork identity change refreshes even at the same revision',
    (tester) async {
      final service = _NativeIcons();
      await _mount(tester, service);
      final previousState = tester.state(_future());
      final manifest = service.syncedManifest.value!;
      service.png = _png(90);
      service.syncedManifest.value = manifest.copyWith(
        applications: [
          for (final app in manifest.applications)
            app.id == _nativeAppId
                ? app.copyWith(
                    icon: 'custom-browser-v2',
                    executable: 'fixture-new-identity',
                  )
                : app,
        ],
      );
      await tester.pump();
      expect(tester.state(_future()), isNot(same(previousState)));
      await _waitForNativeImage(tester, service.png);
      expect(tester.widget<AppArtwork>(_artwork()).pngBytes, service.png);
      expect(service.requests, [_nativeAppId, _nativeAppId]);
    },
  );

  testWidgets(
    'actual saved slot changes update without another native request',
    (tester) async {
      final service = _NativeIcons();
      final harness = await _mount(tester, service);
      final previousRect = tester.getRect(
        find.byKey(const ValueKey('regular-launch-$_nativeAppId')),
      );
      final manifest = service.syncedManifest.value!;
      service.syncedManifest.value = manifest.copyWith(
        launcherApplicationIds: [
          null,
          null,
          null,
          _nativeAppId,
          ...List<String?>.filled(8, null),
        ],
      );
      await tester.pumpAndSettle();
      final nextRect = tester.getRect(
        find.byKey(const ValueKey('regular-launch-$_nativeAppId')),
      );
      expect(nextRect.left, greaterThan(previousRect.left));
      expect(tester.widget<AppArtwork>(_artwork()).pngBytes, service.png);
      expect(service.requests, [_nativeAppId]);
      expect(harness.companion.remoteActions, isEmpty);
    },
  );

  testWidgets(
    'new host cannot display old native image or bypass initial synchronization',
    (tester) async {
      final service = _NativeIcons();
      final harness = await _mount(tester, service);
      final firstPng = service.png;
      final manifest = service.syncedManifest.value!;
      service.status.value = CompanionSyncStatus.syncing;
      service.host.value = null;
      service.syncedManifest.value = null;
      await tester.pump();
      expect(
        find.byKey(const ValueKey('regular-twelve-key-grid')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('regular-touchpad')), findsNothing);
      service.png = _png(120);
      service.host.value = _host('second');
      service.syncedManifest.value = manifest.copyWith(computerId: 'second');
      await tester.pump();
      expect(
        find.byKey(const ValueKey('regular-twelve-key-grid')),
        findsNothing,
      );
      service.status.value = CompanionSyncStatus.ready;
      await tester.pump();
      expect(tester.widget<AppArtwork>(_artwork()).pngBytes, isNot(firstPng));
      expect(tester.widget<AppArtwork>(_artwork()).pngBytes, isNull);
      await _waitForNativeImage(tester, service.png);
      expect(service.requests, [_nativeAppId, _nativeAppId]);
      expect(harness.companion.remoteActions, isEmpty);
    },
  );

  testWidgets(
    'turning off icon sync immediately removes native artwork and stops requests',
    (tester) async {
      final service = _NativeIcons();
      await _mount(tester, service);
      final manifest = service.syncedManifest.value!;
      service.syncedManifest.value = manifest.copyWith(
        settings: manifest.settings.copyWith(syncIcons: false),
      );
      await tester.pump();
      expect(tester.widget<AppArtwork>(_artwork()).pngBytes, isNull);
      await tester.pump(const Duration(seconds: 2));
      expect(tester.widget<AppArtwork>(_artwork()).pngBytes, isNull);
      expect(service.requests, [_nativeAppId]);
    },
  );
}
