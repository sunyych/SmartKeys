import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumiakeys_protocol/lumiakeys_protocol.dart';
import 'package:smart_keys/ui/regular_home_screen.dart';
import 'package:smart_keys/services/companion_service.dart';
import 'package:smart_keys/icons/app_icon_catalog.dart';
import 'package:diagnostics_core/diagnostics_core.dart';
import 'package:smart_keys/diagnostics/diagnostics_service.dart';
import 'package:smart_keys/diagnostics/diagnostics_store.dart';

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
    final diagnostics = DiagnosticsService(
      metadata: DiagnosticMetadata(
        appVersion: '1.7.0',
        appBuild: 9,
        edition: DiagnosticEdition.full,
        platform: DiagnosticPlatform.android,
      ),
      store: MemoryDiagnosticsStore(),
      maintenanceInterval: Duration.zero,
    );
    await diagnostics.initialize();
    await diagnostics.setSharing(false);
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
      diagnostics.dispose();
    });
    await shots.setViewport(const Size(844, 390));
    await tester.pumpWidget(
      screenshotBoundary(
        key,
        DiagnosticsScope(
          diagnostics: diagnostics,
          child: regularTestApp(harness),
        ),
      ),
    );
    final imageContext = tester.element(find.byType(RegularHomeScreen));
    await tester.runAsync(
      () => Future.wait([
        for (final asset in AppIconCatalog.assets.values.toSet())
          precacheImage(AssetImage(asset), imageContext),
        precacheImage(
          tester
              .widget<Image>(find.byKey(const ValueKey('regular-brand-icon')))
              .image,
          imageContext,
        ),
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
    harness.companion.pointerErrors.value =
        'Desktop mouse input failed: pointer_permission_missing';
    await tester.pumpAndSettle();
    await shots.capture(
      id: 'regular-general-pointer-permission-error',
      title: 'Regular phone mouse permission error',
      orientation: 'landscape',
      notes:
          'Synthetic pointer permission failure displayed beside the touchpad; no private connection data.',
      boundaryKey: key,
    );
    harness.companion.pointerErrors.value = null;
    await tester.pumpAndSettle();
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
    const installedWord = RemoteApplication(
      id: 'installed.0123456789abcdef0123456789abcdef',
      name: 'Word',
      icon: 'word',
      executable: 'Desktop-managed',
      layoutId: installedLaunchOnlyLayoutId,
      detected: true,
      launchOnly: true,
    );
    harness.companion.syncedManifest.value = configured.copyWith(
      layouts: [...configured.layouts, installedLaunchOnlyLayout],
      applications: [...configured.applications, installedWord],
      launcherApplicationIds: [
        installedWord.id,
        'chrome',
        'chatgpt',
        ...List<String?>.filled(9, null),
      ],
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(ValueKey('regular-launch-${installedWord.id}')),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('regular-workspace-title')))
          .data,
      'Launchpad',
    );
    await shots.capture(
      id: 'full-installed-launch-only',
      title: 'Full installed application launcher',
      orientation: 'landscape',
      notes:
          'Current production widgets with a Desktop manifest fixture for an installed Word launch-only entry. It launches and stays on Launchpad without creating a shortcut profile; no physical Word installation is claimed.',
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
    await tester.tap(find.byKey(const ValueKey('regular-settings')));
    await tester.pumpAndSettle();
    await shots.capture(
      id: 'full-settings',
      title: 'Full phone settings',
      orientation: 'landscape',
      notes:
          'Regular/Full settings surface; local Bluetooth Lite profile editors are not this product’s configuration path.',
      boundaryKey: key,
    );
    await tester.tap(find.byKey(const ValueKey('open-app-icon-library')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('app-icon-library')), findsOneWidget);
    await shots.capture(
      id: 'full-icon-library-from-settings',
      title: 'Full icon library opened from Settings',
      orientation: 'landscape',
      notes:
          'The actual Regular Settings button opens Settings, then the App icon library route. No direct synthetic shortcut to this page was used.',
      boundaryKey: key,
    );
  });
}
