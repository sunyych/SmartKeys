import 'dart:io';

import 'package:smart_keys/controllers/app_controller.dart';
import 'package:smart_keys/data/config_repository.dart';
import 'package:smart_keys/data/private_image_store.dart';
import 'package:smart_keys/data/profile_template_repository.dart';
import 'package:smart_keys/data/shortcut_usage_repository.dart';
import 'package:smart_keys/models/config.dart';
import 'package:smart_keys/services/hid_service.dart';
import 'package:smart_keys/services/companion_service.dart';
import 'package:smart_keys/services/orientation_service.dart';
import 'package:smart_keys/services/power_brightness_service.dart';
import 'package:lumiakeys_protocol/lumiakeys_protocol.dart';

DesktopManifest desktopManifest({
  Set<String> installed = const {},
  Set<String> running = const {},
}) {
  final starter = DesktopManifest.starter();
  return starter.copyWith(
    applications: starter.applications
        .map(
          (application) => application.copyWith(
            detected: installed.contains(application.id),
            running: running.contains(application.id),
          ),
        )
        .toList(growable: false),
  );
}

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
    required this.companion,
    required this.orientation,
    required this.directory,
    required this.power,
    required this.shortcutUsage,
  });

  final AppController controller;
  final MemoryConfigRepository repository;
  final RecordingHidService hid;
  final RecordingCompanionService companion;
  final RecordingOrientationService orientation;
  final Directory directory;
  final RecordingPowerBrightnessService power;
  final MemoryShortcutUsageRepository shortcutUsage;

  static Future<TestHarness> create({
    AppConfig? config,
    bool? pluggedIn = false,
  }) async {
    final directory = Directory.systemTemp.createTempSync('smart_keys_test_');
    final repository = MemoryConfigRepository(config ?? testConfig());
    final hid = RecordingHidService();
    final companion = RecordingCompanionService();
    final orientation = RecordingOrientationService();
    final power = RecordingPowerBrightnessService(pluggedIn: pluggedIn);
    final shortcutUsage = MemoryShortcutUsageRepository();
    final controller = AppController(
      repository: repository,
      templates: ProfileTemplateRepository(),
      hid: hid,
      companion: companion,
      orientationService: orientation,
      imageStore: PrivateImageStore(documentsDirectory: () async => directory),
      powerBrightnessService: power,
      shortcutUsage: shortcutUsage,
    );
    await controller.initialize();
    return TestHarness(
      controller: controller,
      repository: repository,
      hid: hid,
      companion: companion,
      orientation: orientation,
      directory: directory,
      power: power,
      shortcutUsage: shortcutUsage,
    );
  }

  Future<void> dispose() async {
    controller.dispose();
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  }
}
