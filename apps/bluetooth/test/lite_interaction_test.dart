import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lumiakey_bluetooth_lite/lite_controller.dart';
import 'package:lumiakey_bluetooth_lite/local_profiles.dart';

const hid = MethodChannel('smart_keys/hid');
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final sent = <MethodCall>[];
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    sent.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(hid, (call) async {
          if (call.method == 'refreshPairedHosts') {
            return {
              'status': 'connected',
              'activeHost': {
                'id': 'pc',
                'name': 'Test PC',
                'address': 'AA:BB:CC:DD:EE:01',
              },
              'pairedHosts': [],
            };
          }
          sent.add(call);
          return null;
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(hid, null),
  );
  test(
    'saved local shortcut survives restart and sends its exact keyboard combination',
    () async {
      final first = LiteController();
      addTearDown(first.dispose);
      await first.initialize();
      final original = first.profiles.first;
      const custom = LocalShortcut(
        title: 'Custom Copy',
        keyCode: 'C',
        modifiers: ['LEFT_CTRL'],
      );
      await first.saveProfile(
        original.withShortcuts([...original.shortcuts, custom]),
      );
      first.dispose();
      final restarted = LiteController();
      addTearDown(restarted.dispose);
      await restarted.initialize();
      restarted.setLandscape(true);
      restarted.setControlsVisible(true);
      expect(restarted.profiles.first.shortcuts.last.title, 'Custom Copy');
      expect(
        await restarted.executeShortcut(
          restarted.profiles.first.shortcuts.last,
        ),
        true,
      );
      final action =
          sent.lastWhere((call) => call.method == 'sendStep').arguments as Map;
      expect(action['keyCode'], 'C');
      expect(action['modifiers'], ['LEFT_CTRL']);
      expect(
        (await SharedPreferences.getInstance()).getString(
          SharedPreferencesProfileStore.storageKey,
        ),
        contains('Custom Copy'),
      );
    },
  );
}
