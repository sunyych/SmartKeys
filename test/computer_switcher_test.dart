import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumiakeys_protocol/lumiakeys_protocol.dart';
import 'package:smart_keys/models/config.dart';
import 'package:smart_keys/services/companion_service.dart';
import 'package:smart_keys/services/hid_service.dart';
import 'package:smart_keys/ui/computer_switcher.dart';

import 'test_support.dart';

void main() {
  testWidgets('KVM cycles sorted computers and filters Bluetooth accessories', (
    tester,
  ) async {
    final companion = _SwitchableCompanion()
      ..choices.value = const [
        CompanionComputerChoice(
          id: 'desktop-b',
          name: 'Beta workstation',
          platform: 'windows',
        ),
        CompanionComputerChoice(
          id: 'desktop-a',
          name: 'Alpha workstation',
          platform: 'macos',
        ),
      ];
    final hid = RecordingHidService()
      ..status.value = HidConnectionStatus.disconnected
      ..selectedHost.value = null
      ..hosts.value = const [
        HidHost(id: 'pc', name: 'Windows PC', address: '11:22:33:44:55:66'),
        HidHost(
          id: 'headphones',
          name: 'Wireless Headphones',
          address: '11:22:33:44:55:77',
          computerCandidate: false,
        ),
      ];
    final harness = await TestHarness.create(
      companionService: companion,
      hidService: hid,
      platformOverride: TargetPlatform.android,
    );
    companion.connectInitial('desktop-a');

    await tester.pumpWidget(_widget(harness));
    expect(find.text('KVM'), findsOneWidget);
    expect(
      find.byTooltip(
        'Switch computer. Current: Alpha workstation. Tap to cycle; press and hold to choose.',
      ),
      findsOneWidget,
    );

    await tester.longPress(find.byKey(const ValueKey('computer-kvm-switch')));
    await tester.pumpAndSettle();
    expect(find.text('Alpha workstation'), findsOneWidget);
    expect(find.text('Beta workstation'), findsOneWidget);
    expect(find.text('Windows PC'), findsOneWidget);
    expect(find.text('Wireless Headphones'), findsNothing);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('computer-kvm-switch')));
    await tester.pumpAndSettle();
    expect(companion.selections, ['desktop-b']);

    await tester.pumpWidget(const SizedBox());
    await harness.dispose();
  });

  testWidgets('disconnected KVM opens a picker with pairing routes', (
    tester,
  ) async {
    final companion = _SwitchableCompanion();
    final hid = RecordingHidService()
      ..status.value = HidConnectionStatus.disconnected
      ..selectedHost.value = null;
    final harness = await TestHarness.create(
      companionService: companion,
      hidService: hid,
      platformOverride: TargetPlatform.android,
    );
    expect(hid.hosts.value, isEmpty);

    await tester.pumpWidget(_widget(harness));
    await tester.tap(find.byKey(const ValueKey('computer-kvm-switch')));
    await tester.pumpAndSettle();
    expect(find.text('No paired computers yet'), findsOneWidget);
    expect(find.text('Pair or manage Bluetooth computers'), findsOneWidget);
    expect(find.text('Pair or manage LumiaKey Desktop'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await harness.dispose();
  });

  testWidgets('a single disconnected Desktop choice connects on one tap', (
    tester,
  ) async {
    final companion = _SwitchableCompanion()
      ..choices.value = const [
        CompanionComputerChoice(
          id: 'desktop-a',
          name: 'Alpha workstation',
          platform: 'windows',
        ),
      ];
    final hid = RecordingHidService()
      ..status.value = HidConnectionStatus.disconnected
      ..selectedHost.value = null;
    final harness = await TestHarness.create(
      companionService: companion,
      hidService: hid,
      platformOverride: TargetPlatform.android,
    );

    await tester.pumpWidget(_widget(harness));
    await tester.tap(find.byKey(const ValueKey('computer-kvm-switch')));
    await tester.pumpAndSettle();
    expect(companion.selections, ['desktop-a']);

    await tester.pumpWidget(const SizedBox());
    await harness.dispose();
  });

  test(
    'explicit Desktop selection routes keyboard only and blocks Bluetooth pointer input',
    () async {
      final companion = _SwitchableCompanion()
        ..choices.value = const [
          CompanionComputerChoice(
            id: 'desktop-a',
            name: 'Alpha workstation',
            platform: 'windows',
          ),
        ];
      final hid = RecordingHidService();
      final harness = await TestHarness.create(
        companionService: companion,
        hidService: hid,
        platformOverride: TargetPlatform.android,
      );
      companion.connectInitial('desktop-a');
      await harness.controller.switchComputer('desktop:desktop-a');

      await harness.controller.pressButton(
        const ButtonConfig(
          id: 'test-key',
          position: 0,
          action: HidAction(type: ActionType.keyboard, keyCode: 'KEY_A'),
        ),
      );
      harness.controller.sendTouchpadMove(20, 20);
      harness.controller.sendPrimaryMouseClick();

      expect(companion.commands, isNotEmpty);
      expect(hid.pressedActions, isEmpty);
      expect(hid.steppedActions, isEmpty);
      await harness.dispose();
    },
  );

  test('Bluetooth A to B stays pending until B reports connected', () async {
    final hid = _DelayedConnectHid()
      ..hosts.value = const [
        HidHost(id: 'A', name: 'Computer A', address: 'AA:00'),
        HidHost(id: 'B', name: 'Computer B', address: 'BB:00'),
      ]
      ..selectedHost.value = const HidHost(
        id: 'A',
        name: 'Computer A',
        address: 'AA:00',
      );
    final harness = await TestHarness.create(
      hidService: hid,
      platformOverride: TargetPlatform.android,
    );

    var completed = false;
    final switching = harness.controller
        .switchComputer('bluetooth:B')
        .then((result) {
          completed = true;
          return result;
        });
    await hid.connectRequested.future;

    expect(hid.calls, contains('releaseAllKeys'));
    expect(harness.controller.computerSwitchPendingId, 'bluetooth:B');
    expect(hid.activeHost.value?.id, 'A');
    expect(completed, isFalse);

    hid.selectedHost.value = const HidHost(
      id: 'B',
      name: 'Computer B',
      address: 'BB:00',
    );
    hid.status.value = HidConnectionStatus.connecting;
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(harness.controller.computerSwitchPendingId, 'bluetooth:B');
    expect(completed, isFalse);

    hid.status.value = HidConnectionStatus.connected;
    expect(await switching, isTrue);
    expect(harness.controller.computerSwitchPendingId, isNull);
    expect(harness.controller.selectedSwitchableComputerId, 'bluetooth:B');

    await harness.dispose();
  });
}

Widget _widget(TestHarness harness) => MaterialApp(
  home: Scaffold(
    body: Center(
      child: ComputerSwitcher(controller: harness.controller, compact: true),
    ),
  ),
);

class _SwitchableCompanion extends RecordingCompanionService
    implements SwitchableCompanionConnection {
  final ValueNotifier<List<CompanionComputerChoice>> choices = ValueNotifier(
    const [],
  );
  final List<String> selections = [];
  String? selectedId;

  @override
  ValueListenable<List<CompanionComputerChoice>> get computerChoices => choices;
  @override
  String? get selectedComputerChoiceId => selectedId;

  @override
  Future<void> selectComputer(String id) async {
    selections.add(id);
    connectInitial(id);
  }

  @override
  Future<void> suspendComputerSelection() async {
    selectedId = null;
    host.value = null;
    status.value = CompanionSyncStatus.disconnected;
    syncedManifest.value = null;
  }

  void connectInitial(String id) {
    selectedId = id;
    final selected = choices.value.firstWhere((choice) => choice.id == id);
    host.value = CompanionHost(
      name: selected.name,
      platform: selected.platform,
      address: '127.0.0.1',
      port: 45678,
      token: 'test-token',
      protocolVersion: 2,
      capabilities: const {'manifest'},
    );
    syncedManifest.value = DesktopManifest.starter();
    status.value = CompanionSyncStatus.ready;
  }

  @override
  void dispose() {
    choices.dispose();
    super.dispose();
  }
}
class _DelayedConnectHid extends RecordingHidService {
  final Completer<void> connectRequested = Completer<void>();

  @override
  Future<void> connectHost(String hostId) async {
    calls.add('connect:$hostId');
    if (!connectRequested.isCompleted) connectRequested.complete();
  }
}
