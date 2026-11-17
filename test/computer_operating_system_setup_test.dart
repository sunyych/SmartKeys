import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_keys/app.dart';
import 'package:smart_keys/app_edition.dart';
import 'package:smart_keys/models/config.dart';
import 'package:smart_keys/ui/settings_screen.dart';

import 'test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Lite shortcut platform persists and explains OS precedence', (
    tester,
  ) async {
    final harness = await TestHarness.create();
    addTearDown(harness.dispose);
    await tester.pumpWidget(
      SmartKeysScope(
        controller: harness.controller,
        edition: AppEdition.lite,
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );

    final setting = find.widgetWithText(
      RadioListTile<ShortcutPlatform>,
      'Apple',
    );
    await tester.scrollUntilVisible(
      setting,
      180,
      scrollable: _settingsScrollable(),
    );
    await tester.tap(setting);
    await tester.pumpAndSettle();

    expect(
      harness.controller.config.preferences.shortcutPlatform,
      ShortcutPlatform.apple,
    );
    expect(
      harness.repository.value.preferences.shortcutPlatform,
      ShortcutPlatform.apple,
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('current-computer-shortcut-system')),
      -180,
      scrollable: _settingsScrollable(),
    );
    expect(find.textContaining('takes priority'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('current-computer-shortcut-system')),
      findsOneWidget,
    );
  });
}

Finder _settingsScrollable() => find
    .descendant(
      of: find.byKey(const ValueKey('settings-list')),
      matching: find.byType(Scrollable),
    )
    .first;
