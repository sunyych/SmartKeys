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
  testWidgets(
    'KVM directly lists Desktop computers and ignores Bluetooth hosts',
    (tester) async {
      final companion = _SwitchableCompanion()
        ..choices.value = const [
          CompanionComputerChoice(
            id: 'desktop-b',
            name: 'Studio Mac',
            platform: 'windows',
            address: '192.168.1.20',
          ),
          CompanionComputerChoice(
            id: 'desktop-a',
            name: 'Studio Mac',
            platform: 'macos',
            address: '192.168.1.21',
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
          'Choose a Desktop computer. Current: Studio Mac · macos · 192.168.1.21.',
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('computer-kvm-switch')));
      await tester.pumpAndSettle();
      expect(find.text('Studio Mac · macos · 192.168.1.21'), findsOneWidget);
      expect(find.text('Studio Mac · windows · 192.168.1.20'), findsOneWidget);
      expect(find.text('Windows PC'), findsNothing);
      expect(find.text('Wireless Headphones'), findsNothing);
      await tester.tap(find.text('Studio Mac · windows · 192.168.1.20'));
      await tester.pumpAndSettle();
      expect(companion.selections, ['desktop-b']);

      await tester.pumpWidget(const SizedBox());
      await harness.dispose();
    },
  );

  testWidgets(
    'Bluetooth-only hosts do not show KVM; first setup offers Desktop pairing',
    (tester) async {
      final companion = _SwitchableCompanion();
      final hid = RecordingHidService()
        ..status.value = HidConnectionStatus.disconnected
        ..selectedHost.value = null;
      final harness = await TestHarness.create(
        companionService: companion,
        hidService: hid,
        platformOverride: TargetPlatform.android,
      );
      hid.hosts.value = const [
        HidHost(id: 'pc', name: 'Windows PC', address: '11:22:33:44:55:66'),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ComputerSwitcher(controller: harness.controller),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Choose or manage computers'));
      await tester.pumpAndSettle();
      expect(find.text('No paired computers yet'), findsOneWidget);
      expect(find.text('Pair or manage Bluetooth computers'), findsNothing);
      expect(find.text('Pair or manage LumiaKey Desktop'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await harness.dispose();
    },
  );

  testWidgets(
    'a single disconnected Desktop choice requires explicit selection',
    (tester) async {
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
      expect(find.text('Alpha workstation'), findsOneWidget);
      await tester.tap(find.text('Alpha workstation'));
      await tester.pumpAndSettle();
      expect(companion.selections, ['desktop-a']);

      await tester.pumpWidget(const SizedBox());
      await harness.dispose();
    },
  );

  testWidgets(
    'active computer disconnect is confirmed and stays target bound',
    (tester) async {
      final companion = _SwitchableCompanion()
        ..choices.value = const [
          CompanionComputerChoice(
            id: 'desktop-a',
            name: 'Alpha workstation',
            platform: 'windows',
          ),
          CompanionComputerChoice(
            id: 'desktop-b',
            name: 'Beta workstation',
            platform: 'macos',
          ),
        ];
      final harness = await TestHarness.create(companionService: companion);
      companion.connectInitial('desktop-a');

      await tester.pumpWidget(_widget(harness));
      await tester.tap(find.byKey(const ValueKey('computer-kvm-switch')));
      await tester.pumpAndSettle();
      final activeRow = tester.widget<Card>(
        find.byKey(const ValueKey('computer-choice-desktop:desktop-a')),
      );
      expect(
        activeRow.color,
        Theme.of(
          tester.element(find.text('Switch computer')),
        ).colorScheme.primaryContainer,
      );
      expect(find.byIcon(Icons.check_circle), findsNothing);
      expect(
        find.byKey(const ValueKey('disconnect-desktop:desktop-a')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey('disconnect-desktop:desktop-a')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('cancel-computer-disconnect')),
      );
      await tester.pumpAndSettle();
      expect(companion.selectedId, 'desktop-a');
      expect(companion.host.value, isNotNull);

      await tester.tap(
        find.byKey(const ValueKey('disconnect-desktop:desktop-a')),
      );
      await tester.pumpAndSettle();
      companion.connectInitial('desktop-b');
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('confirm-computer-disconnect')),
      );
      await tester.pumpAndSettle();
      expect(companion.selectedId, 'desktop-b');
      expect(companion.host.value?.name, 'Beta workstation');

      await tester.tap(
        find.byKey(const ValueKey('disconnect-desktop:desktop-b')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('confirm-computer-disconnect')),
      );
      await tester.pumpAndSettle();
      expect(companion.host.value, isNull);
      expect(companion.choices.value, hasLength(2));
      await tester.tap(find.byKey(const ValueKey('computer-kvm-switch')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Alpha workstation'));
      await tester.pumpAndSettle();
      expect(companion.host.value?.name, 'Alpha workstation');

      await tester.pumpWidget(const SizedBox());
      await harness.dispose();
    },
  );

  testWidgets('manage opens focused connection settings and manual pairing', (
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
    final harness = await TestHarness.create(companionService: companion);
    companion.connectInitial('desktop-a');

    await tester.pumpWidget(_widget(harness));
    await tester.tap(find.byKey(const ValueKey('computer-kvm-switch')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pair or manage LumiaKey Desktop'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.text('LumiaKey Desktop'),
      ),
      findsOneWidget,
    );
    expect(
      find.text('Connected to Alpha workstation (127.0.0.1)'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('add-desktop-computer')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('add-desktop-computer')));
    await tester.pumpAndSettle();
    expect(find.text('Or enter the connection code manually.'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('scan-desktop-pairing-code')),
      findsOneWidget,
    );
    expect(find.byType(TextField), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).obscureText,
      isTrue,
    );

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
}

Widget _widget(TestHarness harness) => MaterialApp(
  home: Scaffold(
    body: Center(
      child: ComputerSwitcher(controller: harness.controller, compact: true),
    ),
  ),
);

class _SwitchableCompanion extends RecordingCompanionService
    implements SwitchableCompanionConnection, ManualCompanionConnection {
  final ValueNotifier<List<CompanionComputerChoice>> choices = ValueNotifier(
    const [],
  );
  final List<String> selections = [];
  String? selectedId;
  bool selectionPinned = false;
  final List<String> manualCodes = [];

  @override
  ValueListenable<List<CompanionComputerChoice>> get computerChoices => choices;
  @override
  String? get selectedComputerChoiceId => selectedId;
  @override
  bool get isComputerSelectionPinned => selectionPinned;

  @override
  Future<void> selectComputer(String id) async {
    selections.add(id);
    selectionPinned = true;
    connectInitial(id);
  }

  @override
  Future<void> suspendComputerSelection() async {
    selectionPinned = false;
    selectedId = null;
    host.value = null;
    status.value = CompanionSyncStatus.disconnected;
    syncedManifest.value = null;
  }

  @override
  Future<void> connectManually(String code) async => manualCodes.add(code);

  @override
  Future<void> disconnect() => suspendComputerSelection();

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
