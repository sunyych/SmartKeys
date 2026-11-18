import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lumiakey_bluetooth_lite/lite_controller.dart';
import 'package:lumiakey_bluetooth_lite/local_profiles.dart';
import 'package:lumiakey_bluetooth_lite/offline_touchpad.dart';

const channel = MethodChannel('smart_keys/hid');
const connected = {
  'status': 'connected',
  'activeHost': {'id': 'pc', 'address': 'AA:BB:CC:DD:EE:FF', 'name': 'Test PC'},
  'pairedHosts': [],
};

class FailingStore implements LocalProfileStore {
  @override
  Future<List<LocalProfile>> load() async => defaultLocalProfiles();
  @override
  Future<void> save(List<LocalProfile> profiles) async =>
      throw StateError('storage unavailable');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <MethodCall>[];
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return call.method == 'refreshPairedHosts' ? connected : null;
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );
  Future<LiteController> ready({LocalProfileStore? store}) async {
    final controller = LiteController(profileStore: store);
    addTearDown(controller.dispose);
    await controller.initialize();
    controller.setLandscape(true);
    controller.setControlsVisible(true);
    return controller;
  }

  test(
    'Shift cannot send a phantom letter or become a sticky modifier',
    () async {
      final controller = await ready();
      expect(
        await controller.executeShortcut(
          const LocalShortcut(
            title: 'Shift',
            keyCode: 'LEFT_SHIFT',
            modifiers: [],
          ),
        ),
        false,
      );
      expect(calls.where((call) => call.method == 'sendStep'), isEmpty);
      expect(
        await controller.executeShortcut(
          const LocalShortcut(
            title: 'Shift Q',
            keyCode: 'Q',
            modifiers: ['LEFT_SHIFT'],
          ),
        ),
        true,
      );
      expect(
        await controller.executeShortcut(
          const LocalShortcut(title: 'Q', keyCode: 'Q', modifiers: []),
        ),
        true,
      );
      final actions = calls.where((call) => call.method == 'sendStep').toList();
      expect(actions, hasLength(2));
      expect((actions.first.arguments as Map)['modifiers'], ['LEFT_SHIFT']);
      expect((actions.last.arguments as Map)['modifiers'], isEmpty);
    },
  );
  test(
    'backgrounding releases input and invalidates old pointer callbacks',
    () async {
      final controller = await ready();
      final epoch = controller.inputEpoch;
      controller.handleLifecycle(AppLifecycleState.paused);
      expect(calls.any((call) => call.method == 'releaseAllKeys'), true);
      expect(await controller.primaryClick(epoch: epoch), false);
      controller.handleLifecycle(AppLifecycleState.resumed);
      expect(await controller.primaryClick(epoch: epoch), false);
      expect(
        await controller.executeShortcut(
          const LocalShortcut(title: 'Q', keyCode: 'Q', modifiers: []),
        ),
        true,
      );
      final action =
          calls.lastWhere((call) => call.method == 'sendStep').arguments as Map;
      expect(action['modifiers'], isEmpty);
    },
  );
  test('failed local save keeps the last durable shortcuts', () async {
    final controller = await ready(store: FailingStore());
    final before = controller.profiles.first;
    await expectLater(
      controller.saveProfile(
        before.withShortcuts([
          ...before.shortcuts,
          const LocalShortcut(
            title: 'Unsaved key',
            keyCode: 'Q',
            modifiers: [],
          ),
        ]),
      ),
      throwsStateError,
    );
    expect(
      controller.profiles.first.shortcuts.any((s) => s.title == 'Unsaved key'),
      false,
    );
    expect(controller.profiles.first.shortcuts.first.title, 'Copy');
    expect(controller.error, contains('Could not save'));
  });
  test(
    'media dispatch uses consumer reports and captured Bluetooth host only',
    () async {
      final controller = await ready();
      expect(await controller.sendConsumer('PLAY_PAUSE'), true);
      expect(calls.lastWhere((call) => call.method == 'sendStep').arguments, {
        'type': 'consumerControl',
        'value': 'PLAY_PAUSE',
        'expectedHostAddress': 'AA:BB:CC:DD:EE:FF',
      });
    },
  );
  testWidgets(
    'two-finger gestures scroll and right-click without pointer clicks',
    (tester) async {
      final controller = await ready();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 600,
              height: 300,
              child: OfflineTouchpad(
                inputEpoch: controller.inputEpoch,
                onMove: controller.movePointer,
                onScroll: controller.scrollPointer,
                onPrimaryTap: controller.primaryClick,
                onSecondaryTap: controller.secondaryClick,
              ),
            ),
          ),
        ),
      );
      final center = tester.getCenter(find.byType(OfflineTouchpad));
      final first = await tester.createGesture(pointer: 1);
      final second = await tester.createGesture(pointer: 2);
      await first.down(center - const Offset(20, 0));
      await second.down(center + const Offset(20, 0));
      await first.moveBy(const Offset(0, 80));
      await second.moveBy(const Offset(0, 80));
      await first.up();
      await second.up();
      await tester.pumpAndSettle();
      expect(
        calls.where(
          (c) =>
              c.method == 'sendStep' &&
              (c.arguments as Map)['type'] == 'mouseWheel',
        ),
        isNotEmpty,
      );
      expect(
        calls.where(
          (c) =>
              c.method == 'sendStep' &&
              (c.arguments as Map)['type'] == 'mouseButton',
        ),
        isEmpty,
      );
      await first.down(center - const Offset(20, 0));
      await second.down(center + const Offset(20, 0));
      await first.up();
      await second.up();
      await tester.pumpAndSettle();
      expect(
        (calls.lastWhere((c) => c.method == 'sendStep').arguments
            as Map)['value'],
        'RIGHT',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    },
  );
}
