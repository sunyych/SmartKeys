import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_keys/models/computer_setup.dart';
import 'package:smart_keys/ui/computer_setup_wizard.dart';

import 'test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('key picker produces a Windows shortcut chord', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(844, 390);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final harness = await TestHarness.create(seedComputerSetup: false);
    addTearDown(harness.dispose);
    final target = harness.controller.activeComputer!;
    await harness.controller.saveComputerOperatingSystem(
      target,
      ComputerOperatingSystem.windows,
    );
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

    final chooseChatGpt = find.byKey(
      const ValueKey('computer-app-select-chatgpt'),
    );
    await tester.scrollUntilVisible(
      chooseChatGpt,
      180,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('computer-wizard-scroll')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(chooseChatGpt);
    await tester.pumpAndSettle();

    final chooseKeys = find.byKey(
      const ValueKey('computer-key-picker-chatgpt-launch'),
    );
    await tester.scrollUntilVisible(
      chooseKeys,
      180,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('computer-wizard-scroll')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(chooseKeys);
    await tester.pumpAndSettle();

    final controlModifier = find.byKey(
      const ValueKey('shortcut-modifier-Ctrl'),
    );
    await tester.ensureVisible(controlModifier);
    await tester.pumpAndSettle();
    await tester.tap(controlModifier);
    final altModifier = find.byKey(const ValueKey('shortcut-modifier-Alt'));
    await tester.ensureVisible(altModifier);
    await tester.pumpAndSettle();
    await tester.tap(altModifier);
    await tester.pumpAndSettle();
    final finalKey = find.byKey(const ValueKey('shortcut-final-key'));
    await tester.ensureVisible(finalKey);
    await tester.pumpAndSettle();
    await tester.tap(finalKey);
    await tester.pumpAndSettle();
    final keyOne = find.text('1').hitTestable();
    await tester.scrollUntilVisible(
      keyOne,
      80,
      scrollable: find.byType(Scrollable).last,
      maxScrolls: 20,
    );
    await tester.pumpAndSettle();
    await tester.tap(keyOne);
    await tester.pumpAndSettle();
    expect(find.text('Ctrl+Alt+1'), findsOneWidget);

    // On short landscape screens, leave the nested menu transition time to
    // finish before removing its containing dialog.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const ValueKey('shortcut-picker-confirm')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('computer-key-chatgpt-launch')),
          )
          .controller
          ?.text,
      'Ctrl+Alt+1',
    );
  });
}
