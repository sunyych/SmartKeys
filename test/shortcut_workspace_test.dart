import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_keys/app.dart';
import 'package:smart_keys/models/computer_setup.dart';
import 'package:smart_keys/services/companion_service.dart';

import 'test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'ChatGPT Codex controls keep action names and chord labels readable',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final config = testConfig(
        profiles: [
          profile(),
          profile(id: 'profile_custom', name: 'Custom'),
        ],
      );
      final harness = await TestHarness.create(config: config);
      addTearDown(() => _dispose(tester, harness));
      await _setDesktop(
        harness,
        installed: const {'chatgpt'},
        running: const {'chatgpt'},
        foreground: 'chatgpt',
      );

      await tester.pumpWidget(SmartKeysApp(controller: harness.controller));
      await tester.pump();

      final profileCount = harness.controller.config.profiles.length;
      await tester.tap(find.byKey(const ValueKey('workspace-app-chatgpt')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('remote-layout-chatgpt')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('home-tab-vibe-coding')), findsNothing);
      expect(find.byKey(const ValueKey('home-tab-codex')), findsNothing);
      expect(harness.controller.activeProfile.id, 'profile_general');
      expect(harness.controller.config.profiles, hasLength(profileCount));
      expect(find.byKey(const ValueKey('vibe-dictation-start')), findsNothing);
      await tester.tap(find.byTooltip('Next bank'));
      await tester.pumpAndSettle();
      final send = find.byKey(
        const ValueKey('remote-button-chatgpt.codex.send'),
      );
      expect(send, findsOneWidget);
      expect(
        find.descendant(of: send, matching: find.text('Send')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: send, matching: find.text('ENTER')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: send, matching: find.textContaining('Hold for')),
        findsNothing,
      );
      final alternate = find.byKey(
        const ValueKey('remote-button-chatgpt.codex.alternateSend'),
      );
      expect(alternate, findsOneWidget);
      expect(
        find.descendant(
          of: alternate,
          matching: find.text('Alternate Send (app-defined)'),
        ),
        findsOneWidget,
      );
      expect(tester.getSize(send).width, greaterThan(80));
      expect(tester.getSize(send).height, greaterThan(70));

      expect(find.byKey(const ValueKey('vibe-dictation-stop')), findsNothing);
    },
  );

  testWidgets('another Desktop app opens its own shortcut layout', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final harness = await TestHarness.create();
    addTearDown(() => _dispose(tester, harness));
    await _setDesktop(
      harness,
      installed: const {'chrome'},
      running: const {'chrome'},
      foreground: 'chrome',
    );
    await tester.pumpWidget(SmartKeysApp(controller: harness.controller));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('workspace-app-chrome')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('remote-layout-app.chrome')),
      findsOneWidget,
    );
    final newTab = find.byKey(const ValueKey('remote-button-chrome.newTab'));
    expect(newTab, findsOneWidget);
    await tester.tap(newTab);
    await tester.pump();
    expect(harness.companion.remoteActions.last.buttonId, 'chrome.newTab');
  });

  testWidgets('ChatGPT New Chat routes through the linked Desktop', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final harness = await TestHarness.create();
    addTearDown(() => _dispose(tester, harness));
    await _setDesktop(
      harness,
      installed: const {'chatgpt'},
      running: const {'chatgpt'},
      foreground: 'chatgpt',
    );

    await tester.pumpWidget(SmartKeysApp(controller: harness.controller));
    await tester.pump();

    final chatgptApp = find.byKey(const ValueKey('workspace-app-chatgpt'));
    expect(chatgptApp, findsOneWidget);
    expect(find.byKey(const ValueKey('workspace-app-codex')), findsNothing);
    await tester.tap(chatgptApp);
    await tester.pumpAndSettle();

    expect(harness.companion.remoteActions.last.applicationId, 'chatgpt');
    expect(find.byKey(const ValueKey('remote-layout-chatgpt')), findsOneWidget);
    final newChat = find.byKey(const ValueKey('remote-button-chatgpt.newChat'));
    expect(newChat, findsOneWidget);
    await tester.tap(newChat);
    await tester.pump();

    expect(harness.companion.remoteActions.last.buttonId, 'chatgpt.newChat');
  });
}

Future<void> _setDesktop(
  TestHarness harness, {
  required Set<String> installed,
  Set<String> running = const {},
  String? foreground,
}) async {
  harness.companion.syncedManifest.value = desktopManifest(
    installed: installed,
    running: running,
    foreground: foreground,
  );
  harness.companion.host.value = connectedCompanionHost;
  harness.companion.status.value = CompanionSyncStatus.ready;
  await harness.controller.saveComputerSetup(
    harness.controller.activeComputer!,
    ComputerSetup(applicationIds: installed.toList(growable: false)),
  );
}

Future<void> _dispose(WidgetTester tester, TestHarness harness) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await harness.dispose();
}
