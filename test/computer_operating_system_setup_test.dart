import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_keys/app.dart';
import 'package:smart_keys/ui/settings_screen.dart';

import 'test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Beginner mode setting persists and explains OS precedence', (
    tester,
  ) async {
    final harness = await TestHarness.create();
    addTearDown(harness.dispose);
    await tester.pumpWidget(
      SmartKeysScope(
        controller: harness.controller,
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );

    final setting = find.byKey(const ValueKey('beginner-mode-setting'));
    await tester.scrollUntilVisible(
      setting,
      180,
      scrollable: _settingsScrollable(),
    );
    expect(harness.controller.config.preferences.beginnerMode, isTrue);
    await tester.tap(setting);
    await tester.pumpAndSettle();

    expect(harness.controller.config.preferences.beginnerMode, isFalse);
    expect(harness.repository.value.preferences.beginnerMode, isFalse);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('current-computer-shortcut-system')),
      180,
      scrollable: _settingsScrollable(),
    );
    expect(
      find.textContaining('takes priority'),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('current-computer-shortcut-system')),
      findsOneWidget,
    );
  });
}

Finder _settingsScrollable() => find.descendant(
  of: find.byKey(const ValueKey('settings-list')),
  matching: find.byType(Scrollable),
).first;
