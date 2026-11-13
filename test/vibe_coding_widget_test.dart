import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_keys/app.dart';
import 'package:smart_keys/models/computer_setup.dart';
import 'package:smart_keys/services/companion_service.dart';

import 'test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Codex app chip opens Vibe Coding directly', (tester) async {
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
      installed: const {'codex'},
      running: const {'codex'},
      foreground: 'codex',
    );

    await tester.pumpWidget(SmartKeysApp(controller: harness.controller));
    await tester.pump();

    final profileCount = harness.controller.config.profiles.length;
    await tester.tap(find.byKey(const ValueKey('workspace-app-codex')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('vibe-shortcut-grid')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-tab-vibe-coding')), findsNothing);
    expect(find.byKey(const ValueKey('home-tab-codex')), findsNothing);
    expect(harness.controller.activeProfile.id, 'profile_general');
    expect(harness.controller.config.profiles, hasLength(profileCount));
    expect(find.byKey(const ValueKey('vibe-dictation-start')), findsNothing);
    expect(find.byKey(const ValueKey('vibe-dictation-stop')), findsNothing);
  });

  testWidgets(
    'synced Vibe routes Desktop IDs and stays selected on activation',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(844, 390);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final harness = await TestHarness.create();
      addTearDown(() => _dispose(tester, harness));
      await _setDesktop(
        harness,
        installed: const {'codex', 'claude', 'cursor'},
        running: const {'codex', 'cursor'},
        foreground: 'codex',
      );

      await tester.pumpWidget(SmartKeysApp(controller: harness.controller));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('workspace-app-codex')));
      await tester.pump();

      expect(
        find.byKey(const ValueKey('profile-quick-profile_custom')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('workspace-app-cursor')),
        findsOneWidget,
      );
      final codexSend = find.byKey(
        const ValueKey('vibe-button-vibe.codex.send'),
      );
      await tester.scrollUntilVisible(
        codexSend,
        100,
        scrollable: find.descendant(
          of: find.byKey(const ValueKey('vibe-shortcut-grid')),
          matching: find.byType(Scrollable),
        ),
      );
      expect(codexSend, findsOneWidget);
      expect(tester.takeException(), isNull);

      tester.view.physicalSize = const Size(390, 844);
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('vibe-button-vibe.codex.send')),
      );
      await tester.tap(
        find.byKey(const ValueKey('vibe-button-vibe.codex.send')),
      );
      await tester.pump();
      expect(harness.companion.remoteActions.last.buttonId, 'vibe.codex.send');
      expect(harness.hid.pressedActions, isEmpty);

      for (final buttonId in [
        'vibe.codex.alternateSend',
        'vibe.codex.deleteToStart',
        'vibe.codex.screenshot',
      ]) {
        final action = find.byKey(ValueKey('vibe-button-$buttonId'));
        await tester.scrollUntilVisible(
          action,
          180,
          scrollable: find.descendant(
            of: find.byKey(const ValueKey('vibe-shortcut-grid')),
            matching: find.byType(Scrollable),
          ),
        );
        expect(action, findsOneWidget);
      }

      await _setDesktop(
        harness,
        installed: const {'codex', 'claude', 'cursor'},
        running: const {'codex', 'cursor'},
        foreground: 'cursor',
        activationSequence: 1,
        activatedApplicationId: 'cursor',
      );
      await tester.pump();
      expect(find.byKey(const ValueKey('vibe-coding-title')), findsNothing);
      expect(
        find.byKey(const ValueKey('workspace-app-cursor')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(const ValueKey('workspace-app-claude')));
      await tester.pumpAndSettle();
      expect(harness.companion.remoteActions.last.applicationId, 'claude');
      expect(find.byKey(const ValueKey('home-tab-vibe-coding')), findsNothing);
      expect(
        find.byKey(const ValueKey('workspace-app-claude')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('vibe-app-choices')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Vibe shows actionable focus guidance only when blocked', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final harness = await TestHarness.create();
    addTearDown(() => _dispose(tester, harness));
    await _setDesktop(
      harness,
      installed: const {'codex', 'cursor'},
      running: const {'codex', 'cursor'},
      foreground: 'cursor',
    );
    await tester.pumpWidget(SmartKeysApp(controller: harness.controller));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('workspace-app-codex')));
    await tester.pump();
    expect(
      find.text('Tap Codex above to bring it to the front.'),
      findsOneWidget,
    );
    expect(find.textContaining('is ready'), findsNothing);
    harness.companion.syncedManifest.value = desktopManifest(
      installed: const {'codex', 'cursor'},
      running: const {'codex', 'cursor'},
      foreground: 'codex',
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Tap Codex above to bring it to the front.'),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('vibe-shortcut-grid')), findsOneWidget);
    expect(find.textContaining('is active'), findsNothing);
  });

  testWidgets('holding Backspace repeats only until release', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final harness = await TestHarness.create();
    addTearDown(() => _dispose(tester, harness));
    await _setDesktop(
      harness,
      installed: const {'codex'},
      running: const {'codex'},
      foreground: 'codex',
    );

    await tester.pumpWidget(SmartKeysApp(controller: harness.controller));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('workspace-app-codex')));
    await tester.pumpAndSettle();
    final backspace = find.byKey(
      const ValueKey('vibe-button-vibe.codex.backspace'),
    );
    await tester.scrollUntilVisible(
      backspace,
      100,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey('vibe-shortcut-grid')),
        matching: find.byType(Scrollable),
      ),
    );
    expect(tester.widget<InkWell>(backspace).onTap, isNotNull);
    await tester.tap(backspace);
    await tester.pump();
    expect(
      harness.companion.remoteActions.last.buttonId,
      'vibe.codex.backspace',
    );
    harness.companion.remoteActions.clear();
    final gesture = await tester.startGesture(tester.getCenter(backspace));
    await tester.pump(const Duration(milliseconds: 550));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pump();
    expect(
      harness.companion.remoteActions
          .where((action) => action.buttonId == 'vibe.codex.backspace')
          .length,
      greaterThanOrEqualTo(2),
    );

    await gesture.up();
    await tester.pump();
    final countAfterRelease = harness.companion.remoteActions
        .where((action) => action.buttonId == 'vibe.codex.backspace')
        .length;
    await tester.pump(const Duration(milliseconds: 500));
    expect(
      harness.companion.remoteActions
          .where((action) => action.buttonId == 'vibe.codex.backspace')
          .length,
      countAfterRelease,
    );
  });

  testWidgets('disabled project action shows Desktop setup path', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(844, 390);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final harness = await TestHarness.create();
    addTearDown(() => _dispose(tester, harness));
    final manifest = desktopManifest(
      installed: const {'codex'},
      running: const {'codex'},
      foreground: 'codex',
    );
    final layout = manifest.layoutById('vibe.codex')!;
    harness.companion.syncedManifest.value = manifest.copyWith(
      layouts: [
        ...manifest.layouts.where((candidate) => candidate.id != 'vibe.codex'),
        layout.copyWith(
          buttons: layout.buttons
              .map(
                (button) => button.id == 'vibe.codex.project'
                    ? button.copyWith(enabled: false)
                    : button,
              )
              .toList(growable: false),
        ),
      ],
    );
    harness.companion.host.value = connectedCompanionHost;
    harness.companion.status.value = CompanionSyncStatus.ready;
    final target = harness.controller.activeComputer;
    expect(target, isNotNull);
    await harness.controller.saveComputerSetup(
      target!,
      ComputerSetup(applicationIds: const ['codex']),
    );

    await tester.pumpWidget(SmartKeysApp(controller: harness.controller));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('workspace-app-codex')));
    await tester.pump();

    expect(
      find.byTooltip(
        'Project setup required · Desktop → Shortcut Layout → Vibe Coding · Codex',
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widget<InkWell>(
            find.byKey(const ValueKey('vibe-button-vibe.codex.project')),
          )
          .onTap,
      isNull,
    );
    harness.companion.remoteActions.clear();
    await tester.tap(
      find.byKey(const ValueKey('vibe-button-vibe.codex.project')),
      warnIfMissed: false,
    );
    await tester.pump();
    expect(harness.companion.remoteActions, isEmpty);
  });
}

Future<void> _setDesktop(
  TestHarness harness, {
  required Set<String> installed,
  Set<String> running = const {},
  String? foreground,
  int activationSequence = 0,
  String? activatedApplicationId,
}) async {
  harness.companion.syncedManifest.value = desktopManifest(
    installed: installed,
    running: running,
    foreground: foreground,
    activationSequence: activationSequence,
    activatedApplicationId: activatedApplicationId,
  );
  harness.companion.host.value = connectedCompanionHost;
  harness.companion.status.value = CompanionSyncStatus.ready;
  final target = harness.controller.activeComputer;
  if (target != null) {
    await harness.controller.saveComputerSetup(
      target,
      ComputerSetup(
        applicationIds: installed
            .where((id) => computerApplicationById(id) != null)
            .toList(growable: false),
      ),
    );
  }
}

Future<void> _dispose(WidgetTester tester, TestHarness harness) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await harness.dispose();
}
