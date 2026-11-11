import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_keys/app.dart';
import 'package:smart_keys/models/computer_setup.dart';
import 'package:smart_keys/services/companion_service.dart';
import 'package:smart_keys/services/hid_service.dart';

import 'test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Vibe Coding sits before Custom without using a profile slot', (
    tester,
  ) async {
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

    await tester.pumpWidget(SmartKeysApp(controller: harness.controller));
    await tester.pump();

    final vibe = find.byKey(const ValueKey('home-tab-vibe-coding'));
    final custom = find.byKey(const ValueKey('profile-quick-profile_custom'));
    await _showHomeItem(tester, custom);
    expect(tester.getRect(vibe).left, lessThan(tester.getRect(custom).left));

    final profileCount = harness.controller.config.profiles.length;
    await tester.tap(vibe);
    await tester.pump();
    expect(
      find.byKey(const ValueKey('vibe-app-required-title')),
      findsOneWidget,
    );
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
      await _showHomeItem(
        tester,
        find.byKey(const ValueKey('home-tab-vibe-coding')),
      );
      await tester.tap(find.byKey(const ValueKey('home-tab-vibe-coding')));
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
      expect(find.byKey(const ValueKey('vibe-coding-title')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('workspace-app-cursor')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(const ValueKey('workspace-app-claude')));
      await tester.pumpAndSettle();
      expect(harness.companion.remoteActions.last.applicationId, 'claude');
      expect(
        find.byKey(const ValueKey('home-tab-vibe-coding')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('workspace-app-claude')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('vibe-app-choices')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Vibe states explain unavailable Desktop and missing apps', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final harness = await TestHarness.create();
    addTearDown(() => _dispose(tester, harness));
    harness.hid.selectedHost.value = null;
    harness.hid.status.value = HidConnectionStatus.disconnected;
    await tester.pumpWidget(SmartKeysApp(controller: harness.controller));
    await tester.pump();
    await tester.drag(
      find.byKey(const ValueKey('profile-quick-switch-bar')),
      const Offset(-180, 0),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('home-tab-vibe-coding')));
    await tester.pump();
    expect(
      find.text('Connect to a computer to use Vibe Coding shortcuts.'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('vibe-dictation-start')), findsNothing);

    await _setDesktop(harness, installed: const {});
    await tester.pump();
    expect(
      find.text(
        'Install or enable app sync for Codex, Claude or Cursor on LumiaKey Desktop.',
      ),
      findsOneWidget,
    );
    expect(harness.companion.remoteActions, isEmpty);
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
    await tester.drag(
      find.byKey(const ValueKey('profile-quick-switch-bar')),
      const Offset(-180, 0),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('home-tab-vibe-coding')));
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
    await tester.tap(find.byKey(const ValueKey('home-tab-vibe-coding')));
    await tester.pump();

    expect(
      find.byKey(const ValueKey('vibe-project-setup-hint')),
      findsOneWidget,
    );
    expect(
      find.textContaining('Desktop → Shortcut Layout → Vibe Coding · Codex'),
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

Future<void> _showHomeItem(WidgetTester tester, Finder item) async {
  final scrollable = find.descendant(
    of: find.byKey(const ValueKey('profile-quick-switch-bar')),
    matching: find.byType(Scrollable),
  );
  await tester.scrollUntilVisible(item, 120, scrollable: scrollable);
}
