import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumiakeys_protocol/lumiakeys_protocol.dart';
import 'package:smart_keys/app.dart';
import 'package:smart_keys/models/config.dart';
import 'package:smart_keys/services/companion_service.dart';

import 'test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Advanced Desktop pointer uses its capability with no HID fallback',
    () async {
      final harness = await TestHarness.create(
        platformOverride: TargetPlatform.android,
      );
      addTearDown(harness.dispose);
      harness.companion.syncedManifest.value = desktopManifest();
      harness.companion.status.value = CompanionSyncStatus.ready;
      harness.companion.host.value = const CompanionHost(
        name: 'Studio Windows',
        platform: 'windows',
        address: '192.168.1.25',
        port: 45678,
        token: 'session',
        capabilities: {'manifest', 'mouse-control-v1'},
      );
      harness.controller.sendTouchpadMove(6, -3);
      harness.controller.sendMouseClick(secondary: true);
      harness.controller.sendTouchpadScroll(-12);
      expect(harness.companion.pointerInputs.map((input) => input.kind), [
        PointerInputKind.move,
        PointerInputKind.button,
        PointerInputKind.scroll,
      ]);
      expect(harness.companion.pointerInputs[0].x, 10);
      expect(harness.companion.pointerInputs[1].secondary, isTrue);
      expect(harness.hid.pressedActions, isEmpty);
      expect(harness.hid.steppedActions, isEmpty);
    },
  );

  test(
    'Bluetooth-only mode continues to route mouse gestures over HID',
    () async {
      final harness = await TestHarness.create(
        platformOverride: TargetPlatform.android,
      );
      addTearDown(harness.dispose);
      harness.controller.sendTouchpadMove(8, -4);
      harness.controller.sendMouseClick(secondary: false);
      harness.controller.sendMouseClick(secondary: true);
      harness.controller.sendTouchpadScroll(-18);
      await Future<void>.delayed(Duration.zero);
      expect(harness.companion.pointerInputs, isEmpty);
      expect(harness.hid.pressedActions.single.type, ActionType.mouseMove);
      expect(harness.hid.pressedActions.single.value, '13,-7');
      expect(harness.hid.steppedActions.map((a) => a.type), [
        ActionType.mouseButton,
        ActionType.mouseButton,
        ActionType.mouseWheel,
      ]);
      expect(harness.hid.steppedActions.map((a) => a.value), [
        'LEFT',
        'RIGHT',
        '1',
      ]);
    },
  );

  test(
    'Advanced Desktop without mouse capability never falls back to HID',
    () async {
      final harness = await TestHarness.create(
        platformOverride: TargetPlatform.android,
      );
      addTearDown(harness.dispose);
      harness.companion.syncedManifest.value = desktopManifest();
      harness.companion.status.value = CompanionSyncStatus.ready;
      harness.companion.host.value = const CompanionHost(
        name: 'Legacy Desktop',
        platform: 'windows',
        address: '192.168.1.25',
        port: 45678,
        token: 'session',
        capabilities: {'manifest'},
      );
      harness.controller.sendTouchpadMove(8, -4);
      harness.controller.sendMouseClick(secondary: false);
      harness.controller.sendTouchpadScroll(-18);
      expect(harness.controller.selectedDesktopMouseUnsupported, isTrue);
      expect(harness.companion.pointerInputs, isEmpty);
      expect(harness.hid.pressedActions, isEmpty);
      expect(harness.hid.steppedActions, isEmpty);
    },
  );
  testWidgets('touchpad moves, clicks, and supports two scroll gestures', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(844, 390);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final mouseProfile = profile().copyWith(
      wheel: const WheelConfig(
        controlType: WheelControlType.mousePad,
        modeLabel: 'Touchpad',
        up: HidAction(type: ActionType.mouseMove, value: 'UP'),
        down: HidAction(type: ActionType.mouseMove, value: 'DOWN'),
        left: HidAction(type: ActionType.mouseMove, value: 'LEFT'),
        right: HidAction(type: ActionType.mouseMove, value: 'RIGHT'),
      ),
    );
    final harness = await TestHarness.create(
      config: testConfig(profiles: [mouseProfile]),
    );
    addTearDown(() => _disposeHarness(tester, harness));
    await tester.pumpWidget(SmartKeysApp(controller: harness.controller));
    await tester.pumpAndSettle();

    final touchpad = find.byKey(const ValueKey('mouse-touchpad'));
    expect(touchpad, findsOneWidget);
    expect(find.text('Touchpad'), findsNothing);
    expect(find.byKey(const ValueKey('jog-wheel-gesture')), findsNothing);
    expect(
      tester.getSize(touchpad).width,
      greaterThan(
        tester.getSize(find.byKey(const ValueKey('wheel-region'))).width * 0.9,
      ),
    );
    final center = tester.getCenter(touchpad);
    final gesture = await tester.startGesture(center);
    await gesture.moveBy(const Offset(15, 0));
    await tester.pump();
    expect(harness.hid.pressedActions, hasLength(1));
    expect(harness.hid.pressedActions.single.type, ActionType.mouseMove);
    await gesture.moveBy(const Offset(10, -5));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(harness.hid.pressedActions.last.type, ActionType.mouseMove);
    expect(harness.hid.pressedActions.last.value, '17,-8');

    await tester.tapAt(center);
    await tester.pump();
    expect(harness.hid.steppedActions.last.type, ActionType.mouseButton);
    expect(harness.hid.steppedActions.last.value, 'LEFT');

    final firstFinger = await tester.startGesture(center, pointer: 11);
    final secondFinger = await tester.startGesture(
      center + const Offset(20, 0),
      pointer: 12,
    );
    await firstFinger.up();
    await secondFinger.up();
    await tester.pump();
    expect(harness.hid.steppedActions.last.type, ActionType.mouseButton);
    expect(harness.hid.steppedActions.last.value, 'RIGHT');

    final scrollFirst = await tester.startGesture(
      center - const Offset(10, 0),
      pointer: 21,
    );
    final scrollSecond = await tester.startGesture(
      center + const Offset(10, 0),
      pointer: 22,
    );
    await scrollFirst.moveBy(const Offset(0, -20));
    await scrollSecond.moveBy(const Offset(0, -20));
    await scrollFirst.moveBy(const Offset(0, -20));
    await scrollSecond.moveBy(const Offset(0, -20));
    await tester.pump();
    await scrollFirst.up();
    await scrollSecond.up();
    await tester.pump();
    final scrollActions = harness.hid.steppedActions.where(
      (action) => action.type == ActionType.mouseWheel,
    );
    expect(scrollActions, isNotEmpty);
    expect(scrollActions.last.value, '1');
    final scrollCountBeforeStrip = scrollActions.length;

    final moveCountBeforeStrip = harness.hid.pressedActions.length;
    final clickCountBeforeStrip = harness.hid.steppedActions
        .where((action) => action.type == ActionType.mouseButton)
        .length;
    final scrollStrip = find.byKey(const ValueKey('mouse-scroll-strip'));
    expect(scrollStrip, findsOneWidget);
    final stripRect = tester.getRect(scrollStrip);
    final touchpadRect = tester.getRect(touchpad);
    expect(stripRect.width, lessThanOrEqualTo(44));
    expect(stripRect.right, lessThanOrEqualTo(touchpadRect.right));
    expect(touchpadRect.right - stripRect.right, lessThanOrEqualTo(8));

    final stripGesture = await tester.startGesture(
      tester.getCenter(scrollStrip),
      pointer: 31,
    );
    await stripGesture.moveBy(const Offset(0, -24));
    await tester.pump();
    await stripGesture.up();
    await tester.pump();

    final directScrollActions = harness.hid.steppedActions.where(
      (action) => action.type == ActionType.mouseWheel,
    );
    expect(directScrollActions.length, greaterThan(scrollCountBeforeStrip));
    expect(directScrollActions.last.value, '2');
    expect(harness.hid.pressedActions, hasLength(moveCountBeforeStrip));
    expect(
      harness.hid.steppedActions
          .where((action) => action.type == ActionType.mouseButton)
          .length,
      clickCountBeforeStrip,
    );
  });
}

Future<void> _disposeHarness(WidgetTester tester, TestHarness harness) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await harness.dispose();
}
