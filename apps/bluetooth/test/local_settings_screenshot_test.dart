import 'package:diagnostics_core/diagnostics_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lumiakey_bluetooth_lite/local_diagnostics.dart';
import 'package:lumiakey_bluetooth_lite/local_settings.dart';
import 'screenshot_support.dart';

void main() {
  testWidgets(
    'captures local diagnostics and fifty-icon offline library states',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.runAsync(ScreenshotSupport.prepareFonts);
      final shots = ScreenshotSupport(tester);
      await shots.setViewport(const Size(390, 844));
      final diagnostics = LiteDiagnostics(
        metadataLoader: () async => {'appVersion': '1.1.0', 'appBuild': 2},
      );
      await diagnostics.initialize();
      final boundary = GlobalKey();
      Widget view(Widget screen) => RepaintBoundary(
        key: boundary,
        child: MaterialApp(
          theme: ThemeData(
            brightness: Brightness.dark,
            fontFamilyFallback: ScreenshotSupport.fontFamilyFallback,
          ),
          home: screen,
        ),
      );
      Future<void> show(Widget screen) async {
        await tester.pumpWidget(view(screen));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }

      Future<void> capture(String id, String title) async {
        await tester.pumpAndSettle();
        await shots.capture(
          id: id,
          title: title,
          orientation: 'portrait',
          notes:
              'Bluetooth Lite 1.1.0 local-only fixture at 390px. No real diagnostics were uploaded.',
          boundaryKey: boundary,
        );
      }

      await show(LiteSettingsScreen(diagnostics: diagnostics));
      await capture('lite-local-settings', 'Lite local settings');
      await show(LiteErrorLogScreen(diagnostics: diagnostics));
      expect(find.byKey(const ValueKey('lite-empty-errors')), findsOneWidget);
      await capture('lite-error-logs-empty', 'Lite empty error log');
      await diagnostics.capture(DiagnosticCode.bluetoothConnectionFailed);
      await diagnostics.capture(DiagnosticCode.bluetoothConnectionFailed);
      await tester.pumpAndSettle();
      await capture('lite-error-logs-list', 'Lite fixed-code error log');
      await tester.tap(
        find.text(DiagnosticCode.bluetoothConnectionFailed.message),
      );
      await tester.pumpAndSettle();
      await capture('lite-error-logs-detail', 'Lite error details');
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('lite-clear-errors')));
      await tester.pumpAndSettle();
      await capture(
        'lite-error-logs-clear-confirmation',
        'Lite clear log confirmation',
      );
      await tester.tap(find.text('Clear').last);
      await tester.pumpAndSettle();
      expect(diagnostics.journal.events, isEmpty);
      await diagnostics.setRetentionDays(7);
      await tester.pumpAndSettle();
      await capture(
        'lite-error-logs-seven-days',
        'Lite seven-day local retention',
      );
      final failing = LiteDiagnostics(
        metadataLoader: () async => {'appVersion': '1.1.0', 'appBuild': 2},
        preferences: () async =>
            throw StateError('fixture local storage unavailable'),
      );
      await failing.capture(DiagnosticCode.storageWriteFailed);
      await show(LiteErrorLogScreen(diagnostics: failing));
      expect(
        find.byKey(const ValueKey('lite-log-storage-error')),
        findsOneWidget,
      );
      await capture(
        'lite-error-logs-storage-failure',
        'Lite recoverable local log storage failure',
      );
      await show(const LiteIconLibraryScreen());
      await capture(
        'lite-icon-library-offline',
        'Lite fifty bundled icons offline',
      );
      await tester.enterText(
        find.byKey(const ValueKey('lite-icon-search')),
        'google-chrome',
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('lite-icon-chrome')), findsOneWidget);
      await capture('lite-icon-library-search', 'Lite offline alias search');
      await tester.tap(find.byKey(const ValueKey('lite-icon-chrome')));
      await tester.pumpAndSettle();
      await capture(
        'lite-icon-library-detail',
        'Lite original icon and sources',
      );
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('lite-icon-search')),
        'unregistered-example',
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('lite-icon-empty')), findsOneWidget);
      await capture('lite-icon-library-empty', 'Lite no matching icons');
      await tester.pumpWidget(const SizedBox());
      diagnostics.dispose();
      failing.dispose();
    },
  );
}
