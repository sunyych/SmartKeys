import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumiakeys_protocol/lumiakeys_protocol.dart';
import 'package:smart_keys/ui/regular_home_screen.dart';
import 'package:smart_keys/ui/settings_screen.dart';
import 'package:smart_keys/services/companion_service.dart';
import 'package:smart_keys/icons/app_icon_catalog.dart';

import 'regular_home_test_support.dart';
import 'screenshot_support.dart';
import 'test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(ScreenshotSupport.prepareFonts);
  testWidgets('renders Regular phone launcher General ChatGPT and iPad', (
    tester,
  ) async {
    final shots = ScreenshotSupport(tester);
    final harness = await TestHarness.create(
      companionService: ActivatingRegularCompanion(),
    );
    final starter = DesktopManifest.regularStarter();
    connectRegularHarness(
      harness,
      manifest: starter,
      installed: const {
        'chatgpt',
        'chrome',
        'cursor',
        'edge',
        'firefox',
        'illustrator',
        'photoshop',
        'premiere',
        'solidworks',
        'teams',
        'vscode',
        'zoom',
      },
    );
    final key = GlobalKey();
    addTearDown(() async {
      await shots.unmount();
      shots.resetViewport();
      await harness.dispose();
    });
    await shots.setViewport(const Size(844, 390));
    await tester.pumpWidget(
      regularTestApp(
        harness,
        child: screenshotBoundary(key, const RegularHomeScreen()),
      ),
    );
    final imageContext = tester.element(find.byType(RegularHomeScreen));
    await tester.runAsync(
      () => Future.wait([
        for (final asset in AppIconCatalog.assets.values.toSet())
          precacheImage(AssetImage(asset), imageContext),
      ]),
    );
    await tester.pumpAndSettle();
    await shots.capture(
      id: 'regular-launchpad',
      title: 'Regular phone Launchpad',
      orientation: 'landscape',
      notes:
          'Desktop-owned applications, 4 by 3 launcher and persistent touchpad.',
      boundaryKey: key,
    );
    await tester.tap(find.byKey(const ValueKey('regular-nav-general')));
    await tester.pumpAndSettle();
    await shots.capture(
      id: 'regular-general',
      title: 'Regular phone General controls',
      orientation: 'landscape',
      notes: 'Twelve Desktop General actions and persistent touchpad.',
      boundaryKey: key,
    );
    await tester.tap(find.byKey(const ValueKey('regular-nav-chatgpt')));
    await tester.pumpAndSettle();
    await shots.capture(
      id: 'regular-chatgpt',
      title: 'Regular phone ChatGPT shortcuts',
      orientation: 'landscape',
      notes: 'Desktop-owned compact application layout.',
      boundaryKey: key,
    );
    await shots.setViewport(const Size(1180, 820));
    await tester.pumpAndSettle();
    await shots.capture(
      id: 'regular-ipad',
      title: 'Regular iPad landscape controls',
      orientation: 'landscape',
      notes:
          'Twelve keys and touchpad at iPad size; Flutter render, no physical-device validation.',
      boundaryKey: key,
    );
    await shots.setViewport(const Size(844, 390));
    await tester.tap(find.byKey(const ValueKey('regular-nav-launchpad')));
    await tester.pumpAndSettle();
    final configured = harness.companion.syncedManifest.value!;
    harness.companion.syncedManifest.value = configured.copyWith(
      applications: [
        ...configured.applications,
        const RemoteApplication(
          id: 'custom-app',
          name: 'Custom App',
          icon: 'unknown',
          executable: 'CustomApp',
          layoutId: 'keyboard',
          detected: true,
        ),
      ],
      launcherApplicationIds: [
        'custom-app',
        'chrome',
        'chatgpt',
        ...List<String?>.filled(launcherSlotCount - 3, null),
      ],
    );
    await tester.pumpAndSettle();
    await shots.capture(
      id: 'full-icon-fallback',
      title: 'Full bundled and unknown-app icon fallback',
      orientation: 'landscape',
      notes:
          'Production Launchpad with a simulated unknown application ID and bundled known-brand artwork; no native extraction or physical installation is claimed.',
      boundaryKey: key,
    );
    harness.companion.syncedManifest.value = configured.copyWith(
      launcherApplicationIds: List<String?>.filled(launcherSlotCount, null),
    );
    await tester.pumpAndSettle();
    await shots.capture(
      id: 'full-launchpad-unconfigured',
      title: 'Full Launchpad awaiting Desktop configuration',
      orientation: 'landscape',
      notes:
          'The twelve empty slots remain empty and show the Desktop-only setup entry.',
      boundaryKey: key,
    );
    harness.companion.status.value = CompanionSyncStatus.disconnected;
    await tester.pumpAndSettle();
    await shots.capture(
      id: 'full-desktop-disconnected',
      title: 'Full Desktop connection recovery',
      orientation: 'landscape',
      notes:
          'Disconnected Full exposes a pairing entry and disables shortcuts and pointer input.',
      boundaryKey: key,
    );
    await tester.pumpWidget(
      regularTestApp(
        harness,
        child: screenshotBoundary(key, const SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await shots.capture(
      id: 'full-settings',
      title: 'Full phone settings',
      orientation: 'landscape',
      notes:
          'Regular/Full settings surface; local Bluetooth Lite profile editors are not this product’s configuration path.',
      boundaryKey: key,
    );
  });
}
