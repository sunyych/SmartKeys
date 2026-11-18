import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumiakey_bluetooth_lite/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('smart_keys/hid');
  final uiCalls = <MethodCall>[];
  setUp(() {
    uiCalls.clear();
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          uiCalls.add(call);
          return null;
        });
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
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });
  testWidgets(
    'Lite opens its own landscape surface without companion account KVM or voice',
    (tester) async {
      tester.view.physicalSize = const Size(844, 390);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(const BluetoothLiteApp());
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('lite-brand-icon')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('lite-twelve-key-grid')),
        findsOneWidget,
      );
      expect(find.text('Desktop companion'), findsNothing);
      expect(find.text('Sign in'), findsNothing);
      expect(find.textContaining('KVM'), findsNothing);
      expect(find.byIcon(Icons.mic), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    },
  );
  testWidgets(
    'immersive fullscreen is entered initially and restored on resume without input',
    (tester) async {
      await tester.pumpWidget(const BluetoothLiteApp());
      await tester.pumpAndSettle();
      expect(
        uiCalls
            .where(
              (call) => call.method == 'SystemChrome.setEnabledSystemUIMode',
            )
            .map((call) => call.arguments),
        ['SystemUiMode.immersiveSticky'],
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(
        uiCalls
            .where(
              (call) => call.method == 'SystemChrome.setEnabledSystemUIMode',
            )
            .map((call) => call.arguments),
        ['SystemUiMode.immersiveSticky', 'SystemUiMode.immersiveSticky'],
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
