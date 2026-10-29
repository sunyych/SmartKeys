import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_keys/app.dart';
import 'package:smart_keys/data/profile_template_repository.dart';
import 'package:smart_keys/models/config.dart';
import 'package:smart_keys/services/companion_service.dart';
import 'package:smart_keys/ui/home_screen.dart';

import 'screenshot_support.dart';
import 'test_support.dart';

/// Rebuilds a small, curated gallery from the shipped Profiles and the real
/// HomeScreen widget tree. Hardware and LAN services are the test fakes from
/// test_support.dart; no product widgets or profile assets are mocked.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(ScreenshotSupport.prepareFonts);

  testWidgets('manual documentation home and Desktop workspace screenshots', (
    tester,
  ) async {
    final shots = ScreenshotSupport(tester);
    final profiles = await ProfileTemplateRepository().loadAll();
    final phoneConfig = testConfig(profiles: profiles);
    final boardConfig = phoneConfig.copyWith(
      preferences: phoneConfig.preferences.copyWith(
        controlSurfaceLayout: ControlSurfaceLayout.shortcutBoard,
        tabletKeysPerPage: 40,
      ),
    );
    final harness = await TestHarness.create(config: phoneConfig);
    addTearDown(() async {
      await shots.unmount();
      shots.resetViewport();
      await harness.dispose();
    });

    Future<GlobalKey> mountHome(Size size, {bool desktop = false}) async {
      await shots.setViewport(size);
      if (desktop) {
        harness.companion.syncedManifest.value = desktopManifest(
          installed: const {'codex', 'chrome', 'vscode'},
          running: const {'codex'},
        );
        harness.companion.host.value = connectedCompanionHost;
        harness.companion.status.value = CompanionSyncStatus.ready;
      }
      final key = GlobalKey();
      await tester.pumpWidget(
        screenshotBoundary(
          key,
          SmartKeysScope(
            controller: harness.controller,
            child: MaterialApp(
              title: 'LumiaKey',
              debugShowCheckedModeBanner: false,
              theme: ThemeData(
                brightness: Brightness.dark,
                fontFamilyFallback: ScreenshotSupport.fontFamilyFallback,
                colorScheme: ColorScheme.fromSeed(
                  seedColor: const Color(0xFF67E8F9),
                  brightness: Brightness.dark,
                  surface: const Color(0xFF10151D),
                ),
                scaffoldBackgroundColor: const Color(0xFF090D12),
                useMaterial3: true,
              ),
              home: const HomeScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      return key;
    }

    var key = await mountHome(const Size(844, 390));
    expect(find.byKey(const ValueKey('landscape-layout')), findsOneWidget);
    await shots.capture(
      id: 'manual-home-landscape',
      title: 'LumiaKey home · landscape',
      orientation: 'landscape',
      notes:
          'Real bundled General Profile at 844×390; test fakes only supply device services.',
      boundaryKey: key,
    );

    key = await mountHome(const Size(390, 844));
    expect(find.byKey(const ValueKey('portrait-layout')), findsOneWidget);
    await shots.capture(
      id: 'manual-home-portrait',
      title: 'LumiaKey home · portrait',
      orientation: 'portrait',
      notes:
          'Real bundled General Profile at 390×844; test fakes only supply device services.',
      boundaryKey: key,
    );

    final boardHarness = await TestHarness.create(config: boardConfig);
    addTearDown(boardHarness.dispose);
    await shots.setViewport(const Size(1024, 768));
    key = GlobalKey();
    await tester.pumpWidget(
      screenshotBoundary(
        key,
        SmartKeysScope(
          controller: boardHarness.controller,
          child: MaterialApp(
            title: 'LumiaKey',
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              brightness: Brightness.dark,
              fontFamilyFallback: ScreenshotSupport.fontFamilyFallback,
              colorScheme: ColorScheme.fromSeed(
                seedColor: const Color(0xFF67E8F9),
                brightness: Brightness.dark,
                surface: const Color(0xFF10151D),
              ),
              scaffoldBackgroundColor: const Color(0xFF090D12),
              useMaterial3: true,
            ),
            home: const HomeScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('shortcut-board-layout')), findsOneWidget);
    expect(find.byKey(const ValueKey('control-button-39')), findsOneWidget);
    await shots.capture(
      id: 'manual-tablet-board',
      title: 'LumiaKey shortcut board · 40 keys',
      orientation: 'landscape',
      notes:
          'Real bundled General Profile at 1024×768 with the configured 40-key board.',
      boundaryKey: key,
    );
    await shots.unmount();

    key = await mountHome(const Size(844, 390), desktop: true);
    final tabs = find.byKey(const ValueKey('profile-quick-switch-bar'));
    await tester.drag(tabs, const Offset(-900, 0));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('home-tab-apps')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('home-tab-apps')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('apps-grid')), findsOneWidget);
    expect(find.byKey(const ValueKey('remote-app-codex')), findsOneWidget);
    final appIconContext = tester.element(
      find.byKey(const ValueKey('apps-grid')),
    );
    await tester.runAsync(() async {
      await Future.wait<void>([
        for (final asset in [
          'assets/app_icons/openai.png',
          'assets/app_icons/chrome.png',
          'assets/app_icons/vscode.png',
        ])
          precacheImage(AssetImage(asset), appIconContext),
      ]);
    });
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    for (final id in ['codex', 'vscode', 'chrome']) {
      final rawIcon = tester.widget<RawImage>(
        find.descendant(
          of: find.byKey(ValueKey('remote-app-$id')),
          matching: find.byType(RawImage),
        ),
      );
      expect(rawIcon.image, isNotNull, reason: '$id brand icon must decode');
    }
    await shots.capture(
      id: 'manual-apps',
      title: 'Desktop Apps workspace',
      orientation: 'landscape',
      notes:
          'Real HomeScreen with a fixture manifest advertising installed Codex, Chrome, and VSCode; no live Desktop connection.',
      boundaryKey: key,
    );

    await tester.drag(tabs, const Offset(-900, 0));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('home-tab-codex')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('home-tab-codex')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('remote-layout-codex')), findsOneWidget);
    await shots.capture(
      id: 'manual-codex',
      title: 'Codex workspace',
      orientation: 'landscape',
      notes:
          'Real HomeScreen and bundled Codex shortcut layout with a fixture Desktop manifest; actions are not sent to a host.',
      boundaryKey: key,
    );
  });
}
