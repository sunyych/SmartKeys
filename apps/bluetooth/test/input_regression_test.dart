import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lumiakey_bluetooth_lite/main.dart';

const channel = MethodChannel('smart_keys/hid');

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
          if (call.method == 'refreshPairedHosts') {
            return {
              'status': 'connected',
              'activeHost': {
                'id': 'pc',
                'address': 'AA:BB:CC:DD:EE:FF',
                'name': 'Test PC',
              },
              'pairedHosts': [],
            };
          }
          calls.add(call);
          return null;
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );

  testWidgets(
    'Shift toggles only a modifier and never sends a phantom letter',
    (tester) async {
      await tester.pumpWidget(const BluetoothLiteApp());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Shift').last);
      await tester.pump();
      expect(calls.where((call) => call.method == 'sendStep'), isEmpty);
      await tester.tap(find.text('Q').last);
      await tester.pumpAndSettle();
      final actions = calls.where((call) => call.method == 'sendStep').toList();
      expect(actions, hasLength(1));
      expect((actions.single.arguments as Map)['keyCode'], 'Q');
      expect((actions.single.arguments as Map)['modifiers'], ['LEFT_SHIFT']);
      await tester.tap(find.text('Q').last);
      await tester.pumpAndSettle();
      expect(
        (calls.lastWhere((call) => call.method == 'sendStep').arguments
            as Map)['modifiers'],
        isEmpty,
      );
    },
  );

  testWidgets('backgrounding releases input and clears pending modifiers', (
    tester,
  ) async {
    await tester.pumpWidget(const BluetoothLiteApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Shift').last);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(calls.any((call) => call.method == 'releaseAllKeys'), isTrue);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Q').last);
    await tester.pumpAndSettle();
    expect(
      (calls.lastWhere((call) => call.method == 'sendStep').arguments
          as Map)['modifiers'],
      isEmpty,
    );
  });

  testWidgets('failed local save keeps prior shortcuts and shows an error', (
    tester,
  ) async {
    await tester.pumpWidget(BluetoothLiteApp(profileStore: FailingStore()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Shortcuts').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'Unsaved key');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(
      find.text('Could not save this shortcut on the phone.'),
      findsOneWidget,
    );
    expect(find.text('Unsaved key'), findsNothing);
    expect(find.text('Copy'), findsOneWidget);
  });

  testWidgets('media buttons dispatch consumer reports only', (tester) async {
    await tester.pumpWidget(const BluetoothLiteApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Media').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.play_arrow).last);
    await tester.pumpAndSettle();
    final report =
        calls.lastWhere((call) => call.method == 'sendStep').arguments as Map;
    expect(report['type'], 'consumerControl');
    expect(report['value'], 'PLAY_PAUSE');
  });

  testWidgets(
    'two-finger gestures scroll and right-click without pointer clicks',
    (tester) async {
      await tester.pumpWidget(const BluetoothLiteApp());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mouse').last);
      await tester.pumpAndSettle();
      final center = tester.getCenter(
        find.byKey(const ValueKey('lite-touchpad')),
      );
      final first = await tester.createGesture(pointer: 1);
      final second = await tester.createGesture(pointer: 2);
      await first.down(center - const Offset(20, 0));
      await second.down(center + const Offset(20, 0));
      await first.moveBy(const Offset(0, 80));
      await second.moveBy(const Offset(0, 80));
      await first.up();
      await second.up();
      await tester.pumpAndSettle();
      final scrolling = calls.where(
        (call) =>
            call.method == 'sendStep' &&
            (call.arguments as Map)['type'] == 'mouseWheel',
      );
      expect(scrolling, isNotEmpty);
      expect(
        calls.where(
          (call) =>
              call.method == 'sendStep' &&
              (call.arguments as Map)['type'] == 'mouseButton',
        ),
        isEmpty,
      );
      await first.down(center - const Offset(20, 0));
      await second.down(center + const Offset(20, 0));
      await first.up();
      await second.up();
      await tester.pumpAndSettle();
      expect(
        (calls.lastWhere((call) => call.method == 'sendStep').arguments
            as Map)['value'],
        'RIGHT',
      );
    },
  );
}
