import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_keys/app.dart';
import 'package:smart_keys/ui/regular_home_screen.dart';

import 'regular_home_test_support.dart';
import 'test_support.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'mobile theme and language apply immediately and survive restart',
    (tester) async {
      final harness = await _mount(tester, const Size(844, 390));

      expect(find.text('Launchpad'), findsWidgets);
      expect(_homeBrightness(tester), Brightness.dark);
      expect(_launchpadCellColor(tester).computeLuminance(), lessThan(0.2));
      await _openSettings(tester);
      expect(find.text('Language'), findsOneWidget);
      expect(find.text('Theme'), findsOneWidget);

      await _choose(tester, 'mobile-theme-selector', 'Light');
      await _choose(tester, 'mobile-language-selector', '简体中文');
      expect(find.text('语言'), findsOneWidget);
      expect(find.text('主题'), findsOneWidget);
      expect(_homeBrightness(tester), Brightness.light);
      expect(_launchpadCellColor(tester).computeLuminance(), greaterThan(0.6));
      await tester.tap(find.byKey(const ValueKey('open-app-icon-library')));
      await tester.pumpAndSettle();
      expect(find.text('应用库'), findsOneWidget);
      expect(find.text('搜索应用名称或 ID'), findsOneWidget);
      await tester.tap(find.byTooltip('返回'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('返回'));
      await tester.pumpAndSettle();
      expect(find.text('启动台'), findsWidgets);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(SmartKeysApp(controller: harness.controller));
      await tester.pumpAndSettle();
      expect(find.text('启动台'), findsWidgets);
      expect(_homeBrightness(tester), Brightness.light);
      await _openSettings(tester);
      await _choose(tester, 'mobile-language-selector', 'English');
      expect(find.text('Language'), findsOneWidget);
    },
  );

  testWidgets('system theme follows platform brightness on a tablet', (
    tester,
  ) async {
    tester.binding.platformDispatcher.platformBrightnessTestValue =
        Brightness.light;
    addTearDown(
      tester.binding.platformDispatcher.clearPlatformBrightnessTestValue,
    );
    await _mount(tester, const Size(1180, 820));
    await _openSettings(tester);
    await _choose(tester, 'mobile-theme-selector', 'Follow system');
    expect(_homeBrightness(tester), Brightness.light);
    tester.binding.platformDispatcher.platformBrightnessTestValue =
        Brightness.dark;
    await tester.pumpAndSettle();
    expect(_homeBrightness(tester), Brightness.dark);
  });
}

Future<TestHarness> _mount(WidgetTester tester, Size size) async {
  final harness = await TestHarness.create();
  connectRegularHarness(harness);
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
    await harness.dispose();
  });
  await tester.pumpWidget(SmartKeysApp(controller: harness.controller));
  await tester.pumpAndSettle();
  return harness;
}

Brightness _homeBrightness(WidgetTester tester) => Theme.of(
  tester.element(find.byType(RegularHomeScreen, skipOffstage: false)),
).brightness;

Color _launchpadCellColor(WidgetTester tester) => tester
    .widget<Material>(
      find.byKey(const ValueKey('regular-cell-0'), skipOffstage: false),
    )
    .color!;

Future<void> _openSettings(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('regular-settings')));
  await tester.pumpAndSettle();
}

Future<void> _choose(WidgetTester tester, String key, String value) async {
  await tester.tap(find.byKey(ValueKey(key)));
  await tester.pumpAndSettle();
  await tester.tap(find.text(value).last);
  await tester.pumpAndSettle();
}
