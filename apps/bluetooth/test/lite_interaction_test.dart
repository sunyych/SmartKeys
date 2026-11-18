import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lumiakey_bluetooth_lite/main.dart';

const _hid = MethodChannel('smart_keys/hid');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final sent = <MethodCall>[];
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    sent.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_hid, (call) async {
          if (call.method == 'getConnectionSnapshot' ||
              call.method == 'refreshPairedHosts') {
            return {
              'status': 'disconnected',
              'pairedHosts': [],
              'activeHost': null,
              'error': null,
            };
          }
          sent.add(call);
          return null;
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_hid, null),
  );

  testWidgets('keyboard and touchpad send native HID input reports', (
    tester,
  ) async {
    await tester.pumpWidget(const BluetoothLiteApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Q').last);
    await tester.pumpAndSettle();
    expect(
      sent.any(
        (call) =>
            call.method == 'sendStep' &&
            (call.arguments as Map)['keyCode'] == 'Q',
      ),
      isTrue,
    );
    await tester.tap(find.text('Mouse').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Right click'));
    await tester.pumpAndSettle();
    expect(
      sent.any(
        (call) =>
            call.method == 'sendStep' &&
            (call.arguments as Map)['value'] == 'RIGHT',
      ),
      isTrue,
    );
  });

  testWidgets(
    'manual shortcut editor saves local shortcut and sends its key combination',
    (tester) async {
      await tester.pumpWidget(const BluetoothLiteApp());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Shortcuts').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(0), 'Custom Copy');
      await tester.enterText(find.byType(TextField).at(1), 'C');
      await tester.tap(find.text('Ctrl'));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      final saved = find.text('Custom Copy');
      await tester.scrollUntilVisible(
        saved,
        250,
        scrollable: find.byType(Scrollable).last,
      );
      expect(saved, findsOneWidget);
      await tester.tap(saved);
      await tester.pumpAndSettle();
      final action =
          sent.lastWhere((call) => call.method == 'sendStep').arguments as Map;
      expect(action['keyCode'], 'C');
      expect(action['modifiers'], contains('LEFT_CTRL'));
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString(SharedPreferencesProfileStore.storageKey),
        contains('Custom Copy'),
      );
    },
  );
}
