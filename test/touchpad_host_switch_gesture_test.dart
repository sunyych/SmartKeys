import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumiakeys_protocol/lumiakeys_protocol.dart';
import 'package:smart_keys/models/config.dart';
import 'package:smart_keys/services/companion_service.dart';
import 'package:smart_keys/ui/widgets/mouse_touchpad.dart';

import 'regular_home_test_support.dart';
import 'test_support.dart';

class _SwitchGestureCompanion extends RecordingCompanionService
    implements SwitchableCompanionConnection {
  final choices = ValueNotifier<List<CompanionComputerChoice>>(const [
    CompanionComputerChoice(id: 'id:first', name: 'First', platform: 'windows'),
    CompanionComputerChoice(
      id: 'id:second',
      name: 'Second',
      platform: 'windows',
    ),
  ]);
  final routed = <({String? host, PointerInput input})>[];
  Completer<void>? switchGate;
  String? selected;
  @override
  bool get isComputerSelectionPinned => true;
  @override
  String? get selectedComputerChoiceId => selected;
  @override
  ValueListenable<List<CompanionComputerChoice>> get computerChoices => choices;
  void accept(String id) {
    selected = 'id:$id';
    host.value = CompanionHost(
      name: id,
      computerId: id,
      platform: 'windows',
      address: id == 'first' ? '192.168.1.20' : '192.168.1.21',
      port: 45833,
      token: id,
      capabilities: const {'manifest', 'apps', 'mouse-control-v1'},
    );
    syncedManifest.value = DesktopManifest.regularStarter().copyWith(
      computerId: id,
    );
    status.value = CompanionSyncStatus.ready;
  }

  @override
  Future<void> selectComputer(String id) async {
    status.value = CompanionSyncStatus.syncing;
    host.value = null;
    syncedManifest.value = null;
    if (switchGate != null) await switchGate!.future;
    accept('second');
  }

  @override
  Future<void> suspendComputerSelection() async {}
  @override
  Future<void> sendPointerInputs(List<PointerInput> inputs) async {
    for (final input in inputs) {
      routed.add((host: host.value?.computerId, input: input));
    }
    await super.sendPointerInputs(inputs);
  }

  @override
  void dispose() {
    choices.dispose();
    super.dispose();
  }
}

void main() {
  testWidgets(
    'a painted pending host switch discards the detached old touchpad gesture and restores new input',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(844, 390);
      final service = _SwitchGestureCompanion();
      final harness = await TestHarness.create(
        companionService: service,
        platformOverride: TargetPlatform.android,
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        tester.view.resetDevicePixelRatio();
        tester.view.resetPhysicalSize();
        await harness.dispose();
      });
      service.accept('first');
      await tester.pumpWidget(regularTestApp(harness));
      await tester.pumpAndSettle();
      final area = find.byKey(const ValueKey('mouse-touchpad'));
      final old = await tester.startGesture(
        tester.getCenter(area),
        pointer: 71,
      );
      final gate = Completer<void>();
      service.switchGate = gate;
      final switching = harness.controller.switchComputer('desktop:id:second');
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const ValueKey('regular-touchpad')), findsNothing);
      await old.moveBy(const Offset(24, 4));
      await old.up();
      await tester.pump();
      final pendingException = tester.takeException();
      expect(service.routed, isEmpty);
      gate.complete();
      await tester.pump();
      await switching;
      await tester.pumpAndSettle();
      final fresh = await tester.startGesture(
        tester.getCenter(area),
        pointer: 72,
      );
      await fresh.moveBy(const Offset(20, 0));
      await fresh.up();
      await tester.pump();
      expect(service.routed.single.host, 'second');
      expect(pendingException, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Full host switch discards held gesture and fresh moves clicks and scrolls route to the new host',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(844, 390);
      final service = _SwitchGestureCompanion();
      final harness = await TestHarness.create(
        companionService: service,
        platformOverride: TargetPlatform.android,
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        tester.view.resetDevicePixelRatio();
        tester.view.resetPhysicalSize();
        await harness.dispose();
      });
      service.accept('first');
      await tester.pumpWidget(regularTestApp(harness));
      await tester.pumpAndSettle();
      final area = find.byKey(const ValueKey('mouse-touchpad'));
      final old = await tester.startGesture(
        tester.getCenter(area),
        pointer: 31,
      );
      await old.moveBy(const Offset(18, 0));
      await tester.pump();
      expect(service.routed.single.host, 'first');
      final before = harness.controller.inputEpoch;
      await tester.runAsync(
        () => harness.controller.switchComputer('desktop:id:second'),
      );
      await tester.pumpAndSettle();
      expect(harness.controller.inputEpoch, greaterThan(before));
      expect(find.byKey(const ValueKey('regular-touchpad')), findsOneWidget);
      service.routed.clear();
      await old.moveBy(const Offset(20, 5));
      await old.up();
      await tester.pump();
      expect(service.routed, isEmpty);
      final fresh = await tester.startGesture(
        tester.getCenter(area),
        pointer: 32,
      );
      await fresh.moveBy(const Offset(17, 3));
      await fresh.up();
      await tester.pump();
      await tester.tapAt(tester.getCenter(area));
      await tester.pump();
      final strip = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('mouse-scroll-strip'))),
        pointer: 33,
      );
      await strip.moveBy(const Offset(0, -24));
      await strip.up();
      await tester.pump();
      expect(service.routed.map((event) => event.host).toSet(), {'second'});
      expect(
        service.routed.map((event) => event.input.kind),
        containsAll([
          PointerInputKind.move,
          PointerInputKind.button,
          PointerInputKind.scroll,
        ]),
      );
      expect(harness.hid.pressedActions, isEmpty);
      expect(harness.hid.steppedActions, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'stale pointer cancellation after an epoch change cannot suppress a fresh tap',
    (tester) async {
      var epoch = 0, taps = 0;
      Widget view() => MaterialApp(
        home: SizedBox(
          width: 400,
          height: 300,
          child: MouseTouchpad(
            config: const WheelConfig(controlType: WheelControlType.mousePad),
            inputEpoch: epoch,
            onMove: (_) {},
            onScroll: (_) {},
            onPrimaryTap: () => taps++,
            onSecondaryTap: () {},
          ),
        ),
      );
      await tester.pumpWidget(view());
      final area = find.byKey(const ValueKey('mouse-touchpad'));
      final old = await tester.startGesture(
        tester.getCenter(area),
        pointer: 51,
      );
      epoch++;
      await tester.pumpWidget(view());
      final fresh = await tester.startGesture(
        tester.getCenter(area),
        pointer: 52,
      );
      await old.cancel();
      await fresh.up();
      await tester.pump();
      expect(taps, 1);
    },
  );
}
