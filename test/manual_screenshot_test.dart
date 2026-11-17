import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_keys/app.dart';
import 'package:smart_keys/data/profile_template_repository.dart';
import 'package:smart_keys/models/config.dart';
import 'package:smart_keys/models/computer_setup.dart';
import 'package:smart_keys/services/companion_service.dart';
import 'package:smart_keys/ui/home_screen.dart';
import 'package:smart_keys/ui/computer_setup_wizard.dart';

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
          installed: const {'chatgpt', 'claude', 'cursor'},
          running: const {'chatgpt'},
          foreground: 'chatgpt',
        ).copyWith(computerId: 'manual-desktop');
        harness.companion.host.value = connectedCompanionHost;
        harness.companion.status.value = CompanionSyncStatus.ready;
        await harness.controller.saveComputerSetup(
          harness.controller.activeComputer!,
          ComputerSetup(applicationIds: const ['chatgpt', 'claude', 'cursor']),
        );
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
    expect(find.byKey(const ValueKey('computer-app-row')), findsOneWidget);
    for (final id in ['chatgpt', 'claude', 'cursor']) {
      expect(find.byKey(ValueKey('workspace-app-$id')), findsOneWidget);
    }
    await tester.tap(find.byKey(const ValueKey('home-tab-general')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('remote-layout-keyboard')),
      findsOneWidget,
    );
    await shots.capture(
      id: 'manual-desktop-apps',
      title: 'Desktop app quick launch',
      orientation: 'landscape',
      notes:
          'Real HomeScreen with a fixture manifest and per-computer selected apps in the quick-launch row; no live Desktop connection.',
      boundaryKey: key,
    );

    await shots.setViewport(const Size(412, 915));
    await tester.pumpAndSettle();
    final desktopChatGpt = find.byKey(const ValueKey('workspace-app-chatgpt'));
    await tester.ensureVisible(desktopChatGpt);
    await tester.tap(desktopChatGpt);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('remote-layout-chatgpt')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('profile-quick-switch-bar')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('vibe-coding-title')), findsNothing);
    expect(find.byKey(const ValueKey('vibe-app-choices')), findsNothing);
    expect(find.byKey(const ValueKey('vibe-dictation-start')), findsNothing);
    expect(find.byKey(const ValueKey('vibe-dictation-stop')), findsNothing);
    expect(find.byKey(const ValueKey('local-quick-output')), findsOneWidget);
    await tester.pumpAndSettle();
    await shots.capture(
      id: 'manual-chatgpt-codex-controls',
      title: 'ChatGPT Codex controls',
      orientation: 'portrait',
      notes:
          'Portrait Advanced-mode fixture with ChatGPT in the foreground, ChatGPT/Claude/Cursor in the top app row, merged Codex shortcuts, and the compact Local Dictation entry; no live Desktop connection.',
      boundaryKey: key,
    );

    // Capture the Android standalone first-connection wizard using its real
    // HomeScreen child and fake HID transport. These screenshots are widget
    // fixtures, not captures from a physical Android device.
    final standalone = await TestHarness.create(
      config: phoneConfig,
      seedComputerSetup: false,
    );
    addTearDown(standalone.dispose);
    await shots.setViewport(const Size(412, 915));
    final wizardKey = GlobalKey();
    await tester.pumpWidget(
      screenshotBoundary(
        wizardKey,
        SmartKeysScope(
          controller: standalone.controller,
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
            home: Scaffold(
              body: ComputerSetupWizard(
                controller: standalone.controller,
                target: standalone.controller.activeComputer!,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final osChoice = find.byKey(const ValueKey('computer-os-choice'));
    await _scrollWizardToTop(tester);
    await tester.ensureVisible(osChoice);
    await tester.tap(osChoice);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Windows').last);
    await tester.pumpAndSettle();

    Future<void> selectApp(String id, {required bool selected}) async {
      final checkbox = find.byKey(ValueKey('computer-app-select-$id'));
      await _scrollWizardTo(tester, checkbox);
      final tile = tester.widget<CheckboxListTile>(checkbox);
      if (tile.value != selected) {
        await tester.tap(checkbox);
        await tester.pumpAndSettle();
      }
    }

    for (final id in ['chatgpt', 'claude', 'cursor']) {
      await selectApp(id, selected: true);
    }
    await _scrollWizardToTop(tester);
    await shots.capture(
      id: 'manual-computer-setup-choose',
      title: 'Choose computer apps',
      orientation: 'portrait',
      notes:
          'Real first-connection ComputerSetupWizard with ChatGPT, Claude, and Cursor selected on the standalone Android fixture.',
      boundaryKey: wizardKey,
    );

    await selectApp('claude', selected: false);
    await selectApp('cursor', selected: false);
    for (final action in [
      'launch',
      'codexMode',
      'codex.voiceMode',
      'codex.voiceInput',
      'codex.cancelClear',
      'codex.previousChat',
      'codex.nextChat',
      'codex.nextProject',
    ]) {
      final field = find.byKey(ValueKey('computer-key-chatgpt-$action'));
      await _scrollWizardTo(tester, field);
      await tester.enterText(field, _manualChord(action));
      await tester.pump();
    }
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await _alignWizardItem(
      tester,
      find.byKey(const ValueKey('computer-key-chatgpt-codex.voiceMode')),
      190,
    );
    expect(
      find
          .byKey(const ValueKey('computer-key-chatgpt-codex.voiceMode'))
          .hitTestable(),
      findsOneWidget,
    );
    expect(
      find
          .byKey(const ValueKey('computer-key-chatgpt-codex.voiceInput'))
          .hitTestable(),
      findsOneWidget,
    );
    await shots.capture(
      id: 'manual-computer-setup-shortcuts',
      title: 'Configure ChatGPT shortcuts',
      orientation: 'portrait',
      notes:
          'Real standalone setup wizard with ChatGPT selected and separate ChatGPT/Codex mode, voice, cancel, chat navigation, and project shortcuts configured in the fixture.',
      boundaryKey: wizardKey,
    );

    final launchTest = find.byKey(
      const ValueKey('computer-test-launch-chatgpt'),
    );
    FocusManager.instance.primaryFocus?.unfocus();
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    await _centerWizardItemInViewport(tester, launchTest);
    expect(launchTest, findsOneWidget);
    expect(launchTest.hitTestable(), findsOneWidget);
    await tester.tap(launchTest);
    await tester.pumpAndSettle();
    final launchConfirmation = find.byKey(
      const ValueKey('computer-confirm-launch-chatgpt'),
    );
    await _scrollWizardTo(tester, launchConfirmation);
    expect(launchConfirmation.hitTestable(), findsOneWidget);
    await tester.tap(launchConfirmation);
    await tester.pumpAndSettle();
    await shots.capture(
      id: 'manual-computer-setup-test-launch',
      title: 'Test and confirm app launch',
      orientation: 'portrait',
      notes:
          'Wizard state after the fixture sends the launch shortcut and the user confirms seeing ChatGPT open; no real computer was controlled.',
      boundaryKey: wizardKey,
    );

    final saveButton = find.byKey(const ValueKey('computer-wizard-save'));
    await _scrollWizardToBottom(tester);
    expect(saveButton.hitTestable(), findsOneWidget);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();
    await shots.unmount();
    key = GlobalKey();
    await tester.pumpWidget(
      screenshotBoundary(
        key,
        SmartKeysScope(
          controller: standalone.controller,
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
    final chatgptApp = find.byKey(const ValueKey('workspace-app-chatgpt'));
    await tester.ensureVisible(chatgptApp);
    await tester.tap(chatgptApp);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('standalone-app-title')), findsOneWidget);
    expect(find.byKey(const ValueKey('vibe-app-choices')), findsNothing);
    await shots.capture(
      id: 'manual-standalone-chatgpt-shortcuts',
      title: 'Standalone ChatGPT shortcuts',
      orientation: 'portrait',
      notes:
          'Real standalone ChatGPT shortcut panel with distinct Codex mode, voice-mode, and voice-input actions; generated from the first-connection setup fixture.',
      boundaryKey: key,
    );
  });
}

String _manualChord(String action) => switch (action) {
  'launch' => 'Ctrl+Alt+1',
  'codexMode' => 'Ctrl+Alt+3',
  'codex.voiceMode' => 'Ctrl+Shift+Alt+1',
  'codex.voiceInput' => 'Ctrl+Shift+Alt+2',
  'codex.cancelClear' => 'Escape',
  'codex.previousChat' => 'Ctrl+Alt+Left',
  'codex.nextChat' => 'Ctrl+Alt+Right',
  'codex.nextProject' => 'Ctrl+Alt+P',
  _ => throw ArgumentError.value(action),
};

Future<void> _scrollWizardTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    220,
    scrollable: find
        .descendant(
          of: find.byKey(const ValueKey('computer-wizard-scroll')),
          matching: find.byType(Scrollable),
        )
        .first,
  );
}

Future<void> _scrollWizardToTop(WidgetTester tester) async {
  final scrollable = _wizardScrollable(tester);
  scrollable.position.jumpTo(0);
  await tester.pumpAndSettle();
}

Future<void> _scrollWizardToBottom(WidgetTester tester) async {
  final scrollable = _wizardScrollable(tester);
  scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
  await tester.pumpAndSettle();
}

Future<void> _alignWizardItem(
  WidgetTester tester,
  Finder finder,
  double targetY,
) async {
  final scrollable = _wizardScrollable(tester);
  final currentY = tester.getTopLeft(finder).dy;
  final nextOffset = (scrollable.position.pixels + currentY - targetY)
      .clamp(0.0, scrollable.position.maxScrollExtent)
      .toDouble();
  scrollable.position.jumpTo(nextOffset);
  await tester.pumpAndSettle();
}

Future<void> _centerWizardItemInViewport(
  WidgetTester tester,
  Finder finder,
) async {
  final scrollable = _wizardScrollable(tester);
  final viewport = scrollable.context.findRenderObject()! as RenderBox;
  final item = tester.renderObject(finder) as RenderBox;
  final viewportTop = viewport.localToGlobal(Offset.zero).dy;
  final itemTop = item.localToGlobal(Offset.zero).dy;
  final targetTop = viewportTop + (viewport.size.height - item.size.height) / 2;
  scrollable.position.jumpTo(
    (scrollable.position.pixels + itemTop - targetTop)
        .clamp(
          scrollable.position.minScrollExtent,
          scrollable.position.maxScrollExtent,
        )
        .toDouble(),
  );
  await tester.pumpAndSettle();
}

ScrollableState _wizardScrollable(WidgetTester tester) =>
    tester.state<ScrollableState>(
      find
          .descendant(
            of: find.byKey(const ValueKey('computer-wizard-scroll')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
