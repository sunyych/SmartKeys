import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumiakeys_protocol/lumiakeys_protocol.dart';
import 'package:smart_keys/models/computer_setup.dart';
import 'package:smart_keys/services/companion_service.dart';
import 'test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'authenticated choice rekey after switching preserves Desktop pointer routing',
    () async {
      final companion = _RekeyingCompanion();
      final harness = await TestHarness.create(
        companionService: companion,
        platformOverride: TargetPlatform.android,
      );
      addTearDown(harness.dispose);
      companion.accept('first');
      expect(
        await harness.controller.switchComputer('desktop:endpoint:second'),
        isTrue,
      );
      expect(harness.controller.isDesktopSynced, isTrue);
      expect(harness.controller.selectedDesktopSupportsMouse, isTrue);
      expect(harness.controller.computerMode, ComputerMode.advanced);
      harness.controller.sendTouchpadMove(8, 4);
      harness.controller.sendMouseClick(secondary: false);
      harness.controller.sendTouchpadScroll(24);
      expect(companion.pointerInputs.map((input) => input.kind), [
        PointerInputKind.move,
        PointerInputKind.button,
        PointerInputKind.scroll,
      ]);
      expect(harness.hid.pressedActions, isEmpty);
      expect(harness.hid.steppedActions, isEmpty);
    },
  );
}

class _RekeyingCompanion extends RecordingCompanionService
    implements SwitchableCompanionConnection {
  final choices = ValueNotifier<List<CompanionComputerChoice>>(const [
    CompanionComputerChoice(id: 'id:first', name: 'First', platform: 'windows'),
    CompanionComputerChoice(
      id: 'endpoint:second',
      name: 'Second',
      platform: 'windows',
    ),
  ]);
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
      capabilities: const {'manifest', 'mouse-control-v1'},
    );
    syncedManifest.value = DesktopManifest.starter().copyWith(computerId: id);
    status.value = CompanionSyncStatus.ready;
  }

  @override
  Future<void> selectComputer(String id) async {
    status.value = CompanionSyncStatus.syncing;
    host.value = null;
    syncedManifest.value = null;
    accept('second');
  }

  @override
  Future<void> suspendComputerSelection() async {}
  @override
  void dispose() {
    choices.dispose();
    super.dispose();
  }
}
