import 'dart:io';

import 'package:smart_keys/controllers/app_controller.dart';
import 'package:smart_keys/data/config_repository.dart';
import 'package:smart_keys/data/private_image_store.dart';
import 'package:smart_keys/data/profile_template_repository.dart';
import 'package:smart_keys/models/config.dart';
import 'package:smart_keys/services/hid_service.dart';
import 'package:smart_keys/services/orientation_service.dart';

ProfileConfig profile({
  String id = 'profile_general',
  String name = 'General',
  String firstLabel = 'Copy',
}) {
  final buttons = List.generate(controlButtonCount, ButtonConfig.empty);
  buttons[0] = buttons[0].copyWith(
    label: firstLabel,
    subtitle: 'Primary+C',
    visual: const ButtonVisual(
      type: VisualType.builtinIcon,
      value: 'edit.copy',
    ),
    action: const HidAction(
      type: ActionType.keyboard,
      keyCode: 'KEY_C',
      modifiers: [primaryShortcutModifier],
    ),
  );
  return ProfileConfig(
    id: id,
    name: name,
    buttons: buttons,
    wheel: const WheelConfig(
      clockwise: HidAction(type: ActionType.keyboard, keyCode: 'KEY_RIGHT'),
      counterClockwise: HidAction(
        type: ActionType.keyboard,
        keyCode: 'KEY_LEFT',
      ),
      center: HidAction(type: ActionType.keyboard, keyCode: 'KEY_SPACE'),
    ),
    createdAt: 1,
    updatedAt: 1,
  );
}

AppConfig testConfig({List<ProfileConfig>? profiles}) {
  final values = profiles ?? [profile()];
  return AppConfig(
    activeProfileId: values.first.id,
    defaultProfileId: values.first.id,
    profileOrder: values.map((item) => item.id).toList(),
    profiles: values,
  );
}

class TestHarness {
  TestHarness({
    required this.controller,
    required this.repository,
    required this.hid,
    required this.orientation,
    required this.directory,
  });

  final AppController controller;
  final MemoryConfigRepository repository;
  final RecordingHidService hid;
  final RecordingOrientationService orientation;
  final Directory directory;

  static Future<TestHarness> create({AppConfig? config}) async {
    final directory = Directory.systemTemp.createTempSync('smart_keys_test_');
    final repository = MemoryConfigRepository(config ?? testConfig());
    final hid = RecordingHidService();
    final orientation = RecordingOrientationService();
    final controller = AppController(
      repository: repository,
      templates: ProfileTemplateRepository(),
      hid: hid,
      orientationService: orientation,
      imageStore: PrivateImageStore(documentsDirectory: () async => directory),
    );
    await controller.initialize();
    return TestHarness(
      controller: controller,
      repository: repository,
      hid: hid,
      orientation: orientation,
      directory: directory,
    );
  }

  Future<void> dispose() async {
    controller.dispose();
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  }
}
