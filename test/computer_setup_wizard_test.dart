import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_keys/models/computer_setup.dart';
import 'package:smart_keys/ui/computer_setup_wizard.dart';
import 'package:smart_keys/ui/standalone_app_panel.dart';

import 'test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Vibe setup requires both voice keys and a confirmed app launch',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      final harness = await TestHarness.create(seedComputerSetup: false);
      addTearDown(harness.dispose);
      final target = harness.controller.activeComputer!;
      var saved = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ComputerSetupWizard(
              controller: harness.controller,
              target: target,
              onSaved: () => saved = true,
            ),
          ),
        ),
      );

      final chooseCodex = find.byKey(
        const ValueKey('computer-app-select-codex'),
      );
      await _scrollWizardTo(tester, chooseCodex);
      await tester.tap(chooseCodex);
      await tester.pumpAndSettle();

      for (final action in [
        'launch',
        'voiceMode',
        'voiceInput',
        'cancelClear',
        'previousChat',
        'nextChat',
        'nextProject',
      ]) {
        final field = find.byKey(ValueKey('computer-key-codex-$action'));
        await _scrollWizardTo(tester, field);
        await tester.enterText(field, _validChord(action));
        await tester.pump();
      }

      await _scrollWizardTo(
        tester,
        find.byKey(const ValueKey('computer-wizard-save')),
      );
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('computer-wizard-save')),
            )
            .onPressed,
        isNull,
      );

      final launchTest = find.byKey(
        const ValueKey('computer-test-launch-codex'),
      );
      await _scrollWizardTo(tester, launchTest);
      await tester.tap(launchTest);
      await tester.pumpAndSettle();
      final confirmation = find.byKey(
        const ValueKey('computer-confirm-launch-codex'),
      );
      await _scrollWizardTo(tester, confirmation);
      expect(confirmation, findsOneWidget);

      await _scrollWizardTo(tester, confirmation);
      await tester.tap(confirmation);
      await tester.pumpAndSettle();
      await _scrollWizardTo(
        tester,
        find.byKey(const ValueKey('computer-wizard-save')),
      );
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('computer-wizard-save')),
            )
            .onPressed,
        isNotNull,
      );

      await _scrollWizardTo(
        tester,
        find.byKey(const ValueKey('computer-wizard-save')),
      );
      await tester.tap(find.byKey(const ValueKey('computer-wizard-save')));
      await tester.pumpAndSettle();
      expect(saved, isTrue);
      expect(harness.controller.activeComputerSetup!.applicationIds, ['codex']);
      expect(
        harness.controller.activeComputerSetup!.bindingFor(
          'codex',
          'voiceMode',
        ),
        'Ctrl+Shift+Alt+1',
      );
      expect(
        harness.controller.activeComputerSetup!.bindingFor(
          'codex',
          'voiceInput',
        ),
        'Ctrl+Shift+Alt+2',
      );
    },
  );

  testWidgets(
    'only the selected app has a shortcut panel, with no app submenu',
    (tester) async {
      final harness = await TestHarness.create(seedComputerSetup: false);
      addTearDown(harness.dispose);
      final target = harness.controller.activeComputer!;
      await harness.controller.saveComputerSetup(
        target,
        ComputerSetup(
          applicationIds: const ['codex'],
          bindings: const {
            'codex': {
              'launch': 'Ctrl+Alt+1',
              'voiceMode': 'Ctrl+Shift+Alt+1',
              'voiceInput': 'Ctrl+Shift+Alt+2',
              'cancelClear': 'Escape',
              'previousChat': 'Ctrl+Alt+Left',
              'nextChat': 'Ctrl+Alt+Right',
              'nextProject': 'Ctrl+Alt+P',
            },
          },
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StandaloneAppPanel(
              controller: harness.controller,
              target: target,
              application: computerApplicationById('codex')!,
            ),
          ),
        ),
      );

      expect(
        find.byKey(const ValueKey('standalone-app-title')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('vibe-app-choices')), findsNothing);
      final voiceInput = find.byKey(
        const ValueKey('standalone-action-codex-voiceInput'),
      );
      await tester.scrollUntilVisible(
        voiceInput,
        160,
        scrollable: find.descendant(
          of: find.byKey(const ValueKey('standalone-app-codex')),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.tap(voiceInput);
      await tester.pumpAndSettle();

      expect(harness.hid.steppedActions, hasLength(1));
      expect(harness.hid.steppedActions.single.keyCode, 'KEY_2');
      expect(harness.hid.steppedActions.single.modifiers, [
        'LEFT_CTRL',
        'LEFT_SHIFT',
        'LEFT_ALT',
      ]);
    },
  );

  testWidgets('General-only setup stores an explicit empty app list', (
    tester,
  ) async {
    final harness = await TestHarness.create(seedComputerSetup: false);
    addTearDown(harness.dispose);
    final target = harness.controller.activeComputer!;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ComputerSetupWizard(
            controller: harness.controller,
            target: target,
          ),
        ),
      ),
    );

    final finish = find.byKey(const ValueKey('computer-wizard-save'));
    await _scrollWizardTo(tester, finish);
    expect(tester.widget<FilledButton>(finish).onPressed, isNotNull);
    await tester.tap(finish);
    await tester.pumpAndSettle();
    expect(harness.controller.activeComputerSetup!.applicationIds, isEmpty);
  });
}

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

String _validChord(String action) => switch (action) {
  'launch' => 'Ctrl+Alt+1',
  'voiceMode' => 'Ctrl+Shift+Alt+1',
  'voiceInput' => 'Ctrl+Shift+Alt+2',
  'cancelClear' => 'Escape',
  'previousChat' => 'Ctrl+Alt+Left',
  'nextChat' => 'Ctrl+Alt+Right',
  'nextProject' => 'Ctrl+Alt+P',
  _ => throw ArgumentError.value(action),
};
