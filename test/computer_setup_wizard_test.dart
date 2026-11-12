import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_keys/models/computer_setup.dart';
import 'package:smart_keys/ui/computer_setup_wizard.dart';
import 'package:smart_keys/ui/standalone_app_panel.dart';

import 'test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Vibe setup can be saved without launch confirmation', (
    tester,
  ) async {
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

    await _chooseOperatingSystem(tester, ComputerOperatingSystem.windows);

    final chooseCodex = find.byKey(const ValueKey('computer-app-select-codex'));
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
    FocusManager.instance.primaryFocus?.unfocus();
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

    final launchTest = find.byKey(const ValueKey('computer-test-launch-codex'));
    await _scrollWizardTo(tester, launchTest);
    await tester.tap(launchTest);
    await tester.pumpAndSettle();
    final confirmation = find.byKey(
      const ValueKey('computer-confirm-launch-codex'),
    );
    await _scrollWizardTo(tester, confirmation);
    expect(confirmation, findsOneWidget);
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
      harness.controller.activeComputerSetup!.operatingSystem,
      ComputerOperatingSystem.windows,
    );
    expect(
      harness.controller.activeComputerSetup!.bindingFor('codex', 'voiceMode'),
      'Ctrl+Shift+Alt+1',
    );
    expect(
      harness.controller.activeComputerSetup!.bindingFor('codex', 'voiceInput'),
      'Ctrl+Shift+Alt+2',
    );
  });

  testWidgets('can save an incomplete app setup and edit it later', (
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

    await _chooseOperatingSystem(tester, ComputerOperatingSystem.windows);
    final chooseCodex = find.byKey(const ValueKey('computer-app-select-codex'));
    await _scrollWizardTo(tester, chooseCodex);
    await tester.tap(chooseCodex);
    await tester.pumpAndSettle();
    final finish = find.byKey(const ValueKey('computer-wizard-save'));
    await _scrollWizardTo(tester, finish);
    expect(tester.widget<FilledButton>(finish).onPressed, isNotNull);
    await tester.tap(finish);
    await tester.pumpAndSettle();

    final savedSetup = harness.controller.activeComputerSetup!;
    expect(savedSetup.applicationIds, ['codex']);
    expect(savedSetup.bindingFor('codex', 'launch'), isNull);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ComputerSetupWizard(
            key: const ValueKey('reopened-computer-wizard'),
            controller: harness.controller,
            target: target,
            initialSetup: savedSetup,
          ),
        ),
      ),
    );
    final codexCard = find.byKey(const ValueKey('computer-app-settings-codex'));
    await _scrollWizardTo(tester, codexCard);
    await tester.tap(
      find.descendant(of: codexCard, matching: find.byType(ListTile)).first,
    );
    await tester.pumpAndSettle();
    final launchField = find.byKey(const ValueKey('computer-key-codex-launch'));
    await _scrollWizardTo(tester, launchField);
    await tester.enterText(launchField, 'Ctrl+Alt+1');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await _scrollWizardTo(tester, finish);
    expect(tester.widget<FilledButton>(finish).onPressed, isNotNull);
    await tester.tap(finish);
    await tester.pumpAndSettle();
    expect(
      harness.controller.activeComputerSetup!.bindingFor('codex', 'launch'),
      'Ctrl+Alt+1',
    );
  });

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
    expect(tester.widget<FilledButton>(finish).onPressed, isNull);
    await _chooseOperatingSystem(tester, ComputerOperatingSystem.macos);
    await _scrollWizardTo(tester, finish);
    expect(tester.widget<FilledButton>(finish).onPressed, isNotNull);
    await tester.tap(finish);
    await tester.pumpAndSettle();
    expect(harness.controller.activeComputerSetup!.applicationIds, isEmpty);
    expect(
      harness.controller.activeComputerSetup!.operatingSystem,
      ComputerOperatingSystem.macos,
    );
    expect(harness.controller.activeComputer!.id, target.id);
  });

  testWidgets('Linux Beginner guide names GNOME Custom Shortcuts', (
    tester,
  ) async {
    final harness = await TestHarness.create(seedComputerSetup: false);
    addTearDown(harness.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ComputerSetupWizard(
            controller: harness.controller,
            target: harness.controller.activeComputer!,
          ),
        ),
      ),
    );

    await _chooseOperatingSystem(tester, ComputerOperatingSystem.linux);
    await _scrollWizardTo(
      tester,
      find.byKey(const ValueKey('computer-app-select-codex')),
    );
    await tester.tap(find.byKey(const ValueKey('computer-app-select-codex')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('computer-os-beginner-guide')),
      findsOneWidget,
    );
    expect(
      find.textContaining('On GNOME, open Settings → Keyboard'),
      findsOneWidget,
    );
    expect(find.textContaining('Custom Shortcuts'), findsOneWidget);
    expect(find.textContaining('firefox'), findsOneWidget);
  });

  testWidgets('Safari draft selection stays hidden until macOS is selected', (
    tester,
  ) async {
    final harness = await TestHarness.create(seedComputerSetup: false);
    addTearDown(harness.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ComputerSetupWizard(
            controller: harness.controller,
            target: harness.controller.activeComputer!,
          ),
        ),
      ),
    );

    await _chooseOperatingSystem(tester, ComputerOperatingSystem.macos);
    final safari = find.byKey(const ValueKey('computer-app-select-safari'));
    await tester.ensureVisible(safari);
    await tester.tap(safari);
    await tester.pumpAndSettle();
    expect(tester.widget<CheckboxListTile>(safari).value, isTrue);

    await _chooseOperatingSystem(tester, ComputerOperatingSystem.windows);
    expect(safari, findsNothing);

    await _chooseOperatingSystem(tester, ComputerOperatingSystem.macos);
    await tester.ensureVisible(safari);
    expect(tester.widget<CheckboxListTile>(safari).value, isTrue);
  });

  testWidgets('changing the OS clears launch proof but does not block saving', (
    tester,
  ) async {
    final harness = await TestHarness.create(seedComputerSetup: false);
    addTearDown(harness.dispose);
    final target = harness.controller.activeComputer!;
    final setup = ComputerSetup(
      applicationIds: const ['codex'],
      operatingSystem: ComputerOperatingSystem.windows,
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
    );
    await harness.controller.saveComputerSetup(target, setup);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ComputerSetupWizard(
            controller: harness.controller,
            target: target,
            initialSetup: setup,
          ),
        ),
      ),
    );

    expect(
      find.text('Saved for this computer. Change it if needed.'),
      findsOneWidget,
    );
    final finish = find.byKey(const ValueKey('computer-wizard-save'));
    await _scrollWizardTo(tester, finish);
    expect(tester.widget<FilledButton>(finish).onPressed, isNotNull);

    await _chooseOperatingSystem(tester, ComputerOperatingSystem.macos);
    expect(
      find.text('Saved for this computer. Change it if needed.'),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('computer-confirm-operating-system')),
      findsNothing,
    );
    expect(
      harness.controller.activeComputerSetup?.operatingSystem,
      ComputerOperatingSystem.macos,
    );
    await _scrollWizardTo(tester, finish);
    expect(tester.widget<FilledButton>(finish).onPressed, isNotNull);
  });
}

Future<void> _chooseOperatingSystem(
  WidgetTester tester,
  ComputerOperatingSystem operatingSystem,
) async {
  final selector = find.byKey(const ValueKey('computer-os-choice'));
  await _scrollWizardToTop(tester);
  await tester.ensureVisible(selector);
  await tester.tap(selector);
  await tester.pumpAndSettle();
  await tester.tap(find.text(operatingSystem.label).last);
  await tester.pumpAndSettle();
}

Future<void> _scrollWizardToTop(WidgetTester tester) async {
  final scrollable = find
      .descendant(
        of: find.byKey(const ValueKey('computer-wizard-scroll')),
        matching: find.byType(Scrollable),
      )
      .first;
  tester.state<ScrollableState>(scrollable).position.jumpTo(0);
  await tester.pumpAndSettle();
}

Future<void> _scrollWizardTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(finder, 220, scrollable: _wizardScrollable());
  await tester.pumpAndSettle();
}

Finder _wizardScrollable() => find
    .descendant(
      of: find.byKey(const ValueKey('computer-wizard-scroll')),
      matching: find.byType(Scrollable),
    )
    .first;

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
