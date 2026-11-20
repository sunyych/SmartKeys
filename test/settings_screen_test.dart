import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_keys/app.dart';
import 'package:smart_keys/app_edition.dart';
import 'package:smart_keys/models/config.dart';
import 'package:smart_keys/ui/settings_screen.dart';

import 'test_support.dart';

void main() {
  for (final edition in AppEdition.values) {
    testWidgets('${edition.name} Settings omits screen orientation', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(600, 2400);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final harness = await TestHarness.create();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await harness.dispose();
      });

      await tester.pumpWidget(
        SmartKeysScope(
          controller: harness.controller,
          edition: edition,
          child: const MaterialApp(home: SettingsScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('SCREEN ORIENTATION'), findsNothing);
      expect(find.text('Landscape only'), findsNothing);
      expect(find.byType(RadioGroup<OrientationMode>), findsNothing);
      expect(
        find.text(
          edition == AppEdition.lite
              ? 'Shortcut Community'
              : 'Desktop installers',
        ),
        findsOneWidget,
      );
      expect(find.text('CHARGING DISPLAY'), findsOneWidget);
      expect(find.text('Fixed while charging'), findsOneWidget);
      expect(find.text('Haptic feedback'), findsOneWidget);
    });
  }
}
