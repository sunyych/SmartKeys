import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lumiakey_bluetooth_lite/main.dart';

// Production screenshots now live in lite_home_screenshot_test.dart. Preserve
// this suite's coverage of switching all default boards without the retired tabs.
void main() {
  const channel = MethodChannel('smart_keys/hid');
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );
  testWidgets(
    'all default local profiles share the twelve-cell landscape surface',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            channel,
            (call) async => call.method == 'refreshPairedHosts'
                ? {
                    'status': 'disconnected',
                    'activeHost': null,
                    'pairedHosts': [],
                  }
                : null,
          );
      tester.view.physicalSize = const Size(880, 420);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(const BluetoothLiteApp());
      await tester.pumpAndSettle();
      for (final profile in ['general', 'chatgpt', 'chrome']) {
        await tester.tap(
          find.byKey(
            ValueKey(
              'lite-nav-${profile == 'general' ? profile : 'profile-$profile'}',
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('lite-cell-11')), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox.shrink());
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    },
  );
}
