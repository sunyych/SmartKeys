import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:smart_keys/controllers/app_controller.dart';
import 'package:smart_keys/data/account_backup_codec.dart';
import 'package:smart_keys/data/config_repository.dart';
import 'package:smart_keys/data/private_image_store.dart';
import 'package:smart_keys/data/profile_template_repository.dart';
import 'package:smart_keys/data/shortcut_usage_repository.dart';
import 'package:smart_keys/models/config.dart';
import 'package:smart_keys/services/hid_service.dart';
import 'package:smart_keys/services/companion_service.dart';
import 'package:smart_keys/services/orientation_service.dart';
import 'package:smart_keys/services/power_brightness_service.dart';

import 'test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'restore merges selected Profiles and preferences without executing actions',
    () async {
      final harness = await TestHarness.create(
        config: testConfig().copyWith(
          device: const DeviceConfig(
            defaultHostAddress: '192.0.2.10',
            defaultHostName: 'Paired Desktop',
          ),
        ),
      );
      addTearDown(harness.dispose);
      final restored = profile().copyWith(name: 'Restored General');
      final backup = DecodedAccountBackup(
        selection: const BackupSelection(profileIds: ['profile_general']),
        preferences: const AppPreferences(
          orientationMode: OrientationMode.portrait,
        ),
        profiles: [restored],
        images: const {},
        updatedAt: 'now',
      );
      await harness.controller.pressButton(
        harness.controller.activeProfile.buttons.first,
      );
      harness.hid.calls.clear();
      await harness.controller.restoreAccountBackup(backup);

      expect(harness.controller.activeProfile.name, 'Restored General');
      expect(
        harness.controller.config.preferences.orientationMode,
        OrientationMode.portrait,
      );
      expect(harness.controller.config.device.defaultHostAddress, '192.0.2.10');
      expect(harness.hid.calls, ['releaseAllKeys']);
    },
  );

  test(
    'a failed config save leaves the previous in-memory config intact',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'backup_restore_test_',
      );
      final original = testConfig();
      final repository = _FailingSaveRepository(original);
      final hid = RecordingHidService();
      final companion = RecordingCompanionService();
      final orientation = RecordingOrientationService();
      final power = RecordingPowerBrightnessService();
      final usage = MemoryShortcutUsageRepository();
      final controller = AppController(
        repository: repository,
        templates: ProfileTemplateRepository(),
        hid: hid,
        companion: companion,
        orientationService: orientation,
        imageStore: PrivateImageStore(
          documentsDirectory: () async => directory,
        ),
        powerBrightnessService: power,
        shortcutUsage: usage,
      );
      addTearDown(() {
        controller.dispose();
        directory.deleteSync(recursive: true);
      });
      await controller.initialize();
      final backup = DecodedAccountBackup(
        selection: const BackupSelection(profileIds: ['profile_general']),
        preferences: null,
        profiles: [profile().copyWith(name: 'Cloud edit')],
        images: const {},
        updatedAt: 'now',
      );

      await expectLater(
        controller.restoreAccountBackup(backup),
        throwsStateError,
      );
      expect(controller.activeProfile.name, original.activeProfile.name);
      expect(repository.value.activeProfile.name, original.activeProfile.name);
    },
  );

  test(
    'failed image restore removes only newly written files and preserves existing files',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'backup_image_failure_',
      );
      final oldRelative = 'images/local/old.png';
      final oldFile = File('${directory.path}/$oldRelative')
        ..createSync(recursive: true);
      oldFile.writeAsBytesSync([1, 2, 3]);
      final local = profile().copyWith(
        buttons: [
          profile().buttons.first.copyWith(
            visual: const ButtonVisual(
              type: VisualType.customImage,
              value: 'images/local/old.png',
            ),
          ),
        ],
      );
      final original = testConfig(profiles: [local]);
      final repository = _FailingSaveRepository(original);
      final controller = AppController(
        repository: repository,
        templates: ProfileTemplateRepository(),
        hid: RecordingHidService(),
        companion: RecordingCompanionService(),
        orientationService: RecordingOrientationService(),
        imageStore: PrivateImageStore(
          documentsDirectory: () async => directory,
        ),
        powerBrightnessService: RecordingPowerBrightnessService(),
        shortcutUsage: MemoryShortcutUsageRepository(),
      );
      addTearDown(() {
        controller.dispose();
        directory.deleteSync(recursive: true);
      });
      await controller.initialize();
      final remote = profile().copyWith(
        buttons: [
          profile().buttons.first.copyWith(
            visual: const ButtonVisual(
              type: VisualType.customImage,
              value: 'images/cloud/new.png',
            ),
          ),
        ],
      );
      final backup = DecodedAccountBackup(
        selection: const BackupSelection(
          profileIds: ['profile_general'],
          images: true,
        ),
        preferences: null,
        profiles: [remote],
        images: {
          'images/cloud/new.png': Uint8List.fromList([8, 9]),
        },
        updatedAt: 'x',
      );
      await expectLater(
        controller.restoreAccountBackup(backup),
        throwsStateError,
      );
      expect(oldFile.readAsBytesSync(), [1, 2, 3]);
      expect(
        Directory('${directory.path}/images')
            .listSync(recursive: true)
            .whereType<File>()
            .map((file) => p.basename(file.path)),
        ['old.png'],
      );
      expect(controller.activeProfile.buttons.first.visual.value, oldRelative);
    },
  );

  test(
    'restore rejects a fifth merged Profile before changing local config',
    () async {
      final values = [
        profile(),
        profile(id: 'profile_web', name: 'Web'),
        profile(id: 'profile_meetings', name: 'Meetings'),
        profile(id: 'profile_custom', name: 'Custom'),
      ];
      final harness = await TestHarness.create(
        config: testConfig(profiles: values),
      );
      addTearDown(harness.dispose);
      final newProfile = profile(id: 'profile_cloud', name: 'Cloud');
      final backup = DecodedAccountBackup(
        selection: const BackupSelection(profileIds: ['profile_cloud']),
        preferences: null,
        profiles: [newProfile],
        images: const {},
        updatedAt: 'now',
      );
      final before = harness.controller.config;
      await expectLater(
        harness.controller.restoreAccountBackup(backup),
        throwsA(isA<ProfileLimitException>()),
      );
      expect(harness.controller.config, same(before));
    },
  );
}

class _FailingSaveRepository implements ConfigRepository {
  _FailingSaveRepository(this.value);
  AppConfig value;
  @override
  Future<AppConfig> load() async => value;
  @override
  Future<void> save(AppConfig config) async => throw StateError('disk full');
}
