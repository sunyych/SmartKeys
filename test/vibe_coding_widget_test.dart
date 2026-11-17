import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_keys/app.dart';
import 'package:smart_keys/models/computer_setup.dart';
import 'package:smart_keys/services/companion_service.dart';

import 'test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
        installed: const {'claude', 'cursor'},
        running: const {'cursor'},
        foreground: 'cursor',
      );

      await tester.pumpWidget(SmartKeysApp(controller: harness.controller));
      await tester.pump();
      await _tapWorkspaceApp(tester, 'cursor');
      await tester.pump();

      expect(
        find.byKey(const ValueKey('profile-quick-profile_custom')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('workspace-app-cursor')),
        findsOneWidget,
      );
      final cursorSend = find.byKey(
        const ValueKey('vibe-button-vibe.cursor.send'),
      );
      await tester.scrollUntilVisible(
        cursorSend,
        100,
        scrollable: find.descendant(
          of: find.byKey(const ValueKey('vibe-shortcut-grid')),
          matching: find.byType(Scrollable),
        ),
      );
      expect(cursorSend, findsOneWidget);
      expect(tester.takeException(), isNull);

      tester.view.physicalSize = const Size(390, 844);
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('vibe-button-vibe.cursor.send')),
      );
      await tester.tap(
        find.byKey(const ValueKey('vibe-button-vibe.cursor.send')),
      );
      await tester.pump();
      expect(harness.companion.remoteActions.last.buttonId, 'vibe.cursor.send');
      expect(harness.hid.pressedActions, isEmpty);

      for (final buttonId in [
        'vibe.cursor.alternateSend',
        'vibe.cursor.deleteToStart',
        'vibe.cursor.screenshot',
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
        installed: const {'claude', 'cursor'},
        running: const {'cursor'},
        foreground: 'cursor',
        activationSequence: 1,
        activatedApplicationId: 'cursor',
      );
      await tester.pump();
      expect(find.byKey(const ValueKey('vibe-coding-title')), findsNothing);
      final appStrip = find.byKey(const ValueKey('computer-app-scroll-list'));
      final appScrollable = find.descendant(
        of: appStrip,
        matching: find.byType(Scrollable),
      );
      final cursorChip = find.byKey(const ValueKey('workspace-app-cursor'));
      await tester.scrollUntilVisible(
        cursorChip,
        120,
        scrollable: appScrollable,
      );
      await Scrollable.ensureVisible(
        tester.element(cursorChip),
        alignment: 0.5,
      );
      expect(cursorChip, findsOneWidget);
      expect(tester.takeException(), isNull);

      final claudeChip = find.byKey(const ValueKey('workspace-app-claude'));
      await tester.scrollUntilVisible(
        claudeChip,
        120,
        scrollable: appScrollable,
      );
      await Scrollable.ensureVisible(
        tester.element(claudeChip),
        alignment: 0.5,
      );
      await tester.tap(claudeChip);
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
      installed: const {'cursor', 'claude'},
      running: const {'cursor', 'claude'},
      foreground: 'claude',
    );
    await tester.pumpWidget(SmartKeysApp(controller: harness.controller));
    await tester.pump();
    await _tapWorkspaceApp(tester, 'cursor');
    await tester.pump();
    expect(
      find.text('Tap Cursor above to bring it to the front.'),
      findsOneWidget,
    );
    expect(find.textContaining('is ready'), findsNothing);
    harness.companion.syncedManifest.value = desktopManifest(
      installed: const {'cursor', 'claude'},
      running: const {'cursor', 'claude'},
      foreground: 'cursor',
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Tap Cursor above to bring it to the front.'),
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
      installed: const {'cursor'},
      running: const {'cursor'},
      foreground: 'cursor',
    );

    await tester.pumpWidget(SmartKeysApp(controller: harness.controller));
    await tester.pump();
    await _tapWorkspaceApp(tester, 'cursor');
    await tester.pumpAndSettle();
    final backspace = find.byKey(
      const ValueKey('vibe-button-vibe.cursor.backspace'),
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
      'vibe.cursor.backspace',
    );
    harness.companion.remoteActions.clear();
    final gesture = await tester.startGesture(tester.getCenter(backspace));
    await tester.pump(const Duration(milliseconds: 550));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pump();
    expect(
      harness.companion.remoteActions
          .where((action) => action.buttonId == 'vibe.cursor.backspace')
          .length,
      greaterThanOrEqualTo(2),
    );

    await gesture.up();
    await tester.pump();
    final countAfterRelease = harness.companion.remoteActions
        .where((action) => action.buttonId == 'vibe.cursor.backspace')
        .length;
    await tester.pump(const Duration(milliseconds: 500));
    expect(
      harness.companion.remoteActions
          .where((action) => action.buttonId == 'vibe.cursor.backspace')
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
      installed: const {'cursor'},
      running: const {'cursor'},
      foreground: 'cursor',
    );
    final layout = manifest.layoutById('vibe.cursor')!;
    harness.companion.syncedManifest.value = manifest.copyWith(
      layouts: [
        ...manifest.layouts.where((candidate) => candidate.id != 'vibe.cursor'),
        layout.copyWith(
          buttons: layout.buttons
              .map(
                (button) => button.id == 'vibe.cursor.project'
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
      ComputerSetup(applicationIds: const ['cursor']),
    );

    await tester.pumpWidget(SmartKeysApp(controller: harness.controller));
    await tester.pump();
    await _tapWorkspaceApp(tester, 'cursor');
    await tester.pump();

    expect(
      find.byTooltip(
        'Project setup required · Desktop → Shortcut Layout → Vibe Coding · Cursor',
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widget<InkWell>(
            find.byKey(const ValueKey('vibe-button-vibe.cursor.project')),
          )
          .onTap,
      isNull,
    );
    harness.companion.remoteActions.clear();
    await tester.tap(
      find.byKey(const ValueKey('vibe-button-vibe.cursor.project')),
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

Future<void> _tapWorkspaceApp(WidgetTester tester, String applicationId) async {
  final app = find.byKey(ValueKey('workspace-app-$applicationId'));
  final appList = find.byKey(const ValueKey('computer-app-scroll-list'));
  final scrollable = find
      .descendant(of: appList, matching: find.byType(Scrollable))
      .first;
  await tester.scrollUntilVisible(app, 100, scrollable: scrollable);
  await Scrollable.ensureVisible(tester.element(app), alignment: 0.5);
  await tester.drag(scrollable, const Offset(-120, 0));
  await tester.pumpAndSettle();
  final tapTarget = find.descendant(of: app, matching: find.byType(InkWell));
  await tester.tap(tapTarget);
}

Future<void> _dispose(WidgetTester tester, TestHarness harness) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await harness.dispose();
}
