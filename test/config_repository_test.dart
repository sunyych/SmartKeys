import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_keys/data/config_repository.dart';
import 'package:smart_keys/data/profile_transfer_service.dart';
import 'package:smart_keys/data/profile_template_repository.dart';
import 'package:smart_keys/icons/icon_catalog.dart';
import 'package:smart_keys/models/config.dart';

import 'test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('schema v6 round-trips shortcut platform and profiles', () {
    final original =
        testConfig(
          profiles: [
            profile(),
            profile(id: 'profile_design', name: 'Design', firstLabel: 'Brush'),
          ],
        ).copyWith(
          activeProfileId: 'profile_design',
          preferences: const AppPreferences(
            orientationMode: OrientationMode.landscape,
            soundEnabled: true,
            shortcutPlatform: ShortcutPlatform.apple,
            chargingBrightnessMode: ChargingBrightnessMode.dynamic,
            chargingBrightness: 0.65,
          ),
        );

    final decoded = AppConfig.fromJson(
      jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>,
    );

    expect(decoded.schemaVersion, 6);
    expect(decoded.activeProfileId, 'profile_design');
    expect(decoded.profiles, hasLength(2));
    expect(decoded.activeProfile.buttons, hasLength(controlButtonCount));
    expect(decoded.activeProfile.buttons.first.label, 'Brush');
    expect(decoded.preferences.orientationMode, OrientationMode.landscape);
    expect(decoded.preferences.shortcutPlatform, ShortcutPlatform.apple);
    expect(
      decoded.preferences.chargingBrightnessMode,
      ChargingBrightnessMode.dynamic,
    );
    expect(decoded.preferences.chargingBrightness, 0.65);
  });

  test('schema v2 migrates Ctrl shortcuts to PRIMARY', () {
    final legacy =
        jsonDecode(jsonEncode(testConfig().toJson())) as Map<String, dynamic>;
    legacy['schemaVersion'] = 2;
    final profiles = legacy['profiles'] as List<dynamic>;
    final firstProfile = profiles.first as Map<String, dynamic>;
    final buttons = firstProfile['buttons'] as List<dynamic>;
    final firstButton = buttons.first as Map<String, dynamic>;
    final action = firstButton['action'] as Map<String, dynamic>;
    action['modifiers'] = ['LEFT_CTRL'];

    final migrated = AppConfig.fromJson(legacy);

    expect(migrated.schemaVersion, 6);
    expect(migrated.activeProfile.buttons.first.action.modifiers, [
      primaryShortcutModifier,
    ]);
  });

  test('schema v6 refuses to restore more than four free slots', () {
    final values = List.generate(
      5,
      (index) => profile(id: 'profile_$index', name: 'Profile $index'),
    );
    final encoded = testConfig(profiles: values).toJson();

    final decoded = AppConfig.fromJson(encoded);

    expect(decoded.profiles, hasLength(freeProfileLimit));
    expect(decoded.profileOrder, [
      'profile_0',
      'profile_1',
      'profile_2',
      'profile_3',
    ]);
  });

  test(
    'schema v1 migrates into one independent schema v6 General profile',
    () async {
      final general = (await ProfileTemplateRepository(
        bundle: rootBundle,
      ).loadAll()).first;
      final migrated = SharedPreferencesConfigRepository.migrateV1({
        'schemaVersion': 1,
        'buttons': [
          {
            'id': 'button_01',
            'position': 0,
            'label': 'Legacy Copy',
            'visual': {'type': 'builtinIcon', 'value': 'edit.copy'},
            'action': {
              'type': 'keyboard',
              'keyCode': 'KEY_C',
              'modifiers': ['LEFT_CTRL'],
            },
          },
        ],
        'hapticEnabled': false,
      }, general);

      expect(migrated.schemaVersion, 6);
      expect(migrated.profiles, hasLength(1));
      expect(migrated.profiles.single.buttons, hasLength(controlButtonCount));
      expect(migrated.profiles.single.buttons.first.label, 'Mute');
      expect(migrated.profiles.single.buttons[11].label, 'Legacy Copy');
      expect(migrated.preferences.hapticEnabled, isFalse);
      expect(migrated.preferences.orientationMode, OrientationMode.landscape);
      expect(migrated.profiles.single.buttons[11].action.modifiers, [
        primaryShortcutModifier,
      ]);
      expect(
        migrated.profiles.single.wheel.controlType,
        WheelControlType.mousePad,
      );
    },
  );

  test('all four free starter profiles load from JSON assets', () async {
    final profiles = await ProfileTemplateRepository(
      bundle: rootBundle,
    ).loadAll();

    expect(profiles.map((item) => item.id), [
      'profile_general',
      'profile_web',
      'profile_meetings',
      'profile_custom',
    ]);
    expect(
      profiles.every((item) => item.buttons.length == controlButtonCount),
      isTrue,
    );
    expect(profiles.every((item) => item.isBuiltInTemplate), isTrue);
    expect(profiles.first.buttons.map((button) => button.label), [
      'Mute',
      'Volume Down',
      'Volume Up',
      'Undo',
      'Redo',
      'Previous',
      'Play/Pause',
      'Next',
      'Open',
      'Favorite',
      'Cut',
      'Copy',
      'Paste',
      'Close',
      'Delete',
    ]);
    expect(
      [3, 4, 8, 9, 10, 11, 12, 13].every(
        (position) => profiles.first.buttons[position].action.modifiers
            .contains(primaryShortcutModifier),
      ),
      isTrue,
    );
    expect(profiles.first.wheel.controlType, WheelControlType.mousePad);
    expect(profiles.first.wheel.up.value, 'UP');
    expect(profiles.first.wheel.down.value, 'DOWN');
    expect(profiles.first.wheel.left.value, 'LEFT');
    expect(profiles.first.wheel.right.value, 'RIGHT');
    expect(profiles[1].name, 'Web');
    expect(profiles[2].name, 'Zoom / Teams');
    expect(profiles[2].buttons.first.label, 'Zoom Mic');
    expect(profiles[2].buttons[7].label, 'Teams Mic');
    expect(profiles.last.name, 'Custom');
  });

  test(
    'schema v5 migration retires old templates and preserves one custom',
    () async {
      final templates = await ProfileTemplateRepository(
        bundle: rootBundle,
      ).loadAll();
      final general = profile().copyWith(isBuiltInTemplate: true);
      final photoshop = profile(
        id: 'profile_photoshop',
        name: 'Photoshop Starter',
      ).copyWith(isBuiltInTemplate: true);
      final solidworks = profile(
        id: 'profile_solidworks',
        name: 'SolidWorks Starter',
      ).copyWith(isBuiltInTemplate: true);
      final custom = profile(
        id: 'profile_my_meetings',
        name: 'My Meetings',
        firstLabel: 'My Mute',
      );
      final migrated = SharedPreferencesConfigRepository.migrateV5FreeProfiles(
        AppConfig(
          activeProfileId: custom.id,
          defaultProfileId: photoshop.id,
          profileOrder: [general.id, photoshop.id, solidworks.id, custom.id],
          profiles: [general, photoshop, solidworks, custom],
          preferences: const AppPreferences(
            orientationMode: OrientationMode.auto,
          ),
        ),
        templates,
      );

      expect(migrated.profileOrder, [
        'profile_general',
        'profile_web',
        'profile_meetings',
        'profile_my_meetings',
      ]);
      expect(migrated.profiles, hasLength(freeProfileLimit));
      expect(migrated.activeProfileId, custom.id);
      expect(migrated.defaultProfileId, 'profile_general');
      expect(migrated.preferences.orientationMode, OrientationMode.landscape);
      expect(migrated.profiles.last.buttons.first.label, 'My Mute');
    },
  );

  test('shared profile JSON is validated and normalized for import', () {
    const transfer = ProfileTransferService();
    final imported = transfer.decodeImportedProfile(
      jsonEncode(profile(name: 'Shared Editing').toJson()),
    );

    expect(imported.name, 'Shared Editing (Imported)');
    expect(imported.isBuiltInTemplate, isFalse);
    expect(imported.id, startsWith('profile_imported_'));
    final fenced = transfer.decodeImportedProfile(
      '```json\n${jsonEncode(profile(name: 'From Chat').toJson())}\n```',
    );
    expect(fenced.name, 'From Chat (Imported)');
    expect(
      () => transfer.decodeImportedProfile('{"hello":"world"}'),
      throwsFormatException,
    );
  });

  test(
    'schema v3 General layout moves existing actions into the new default',
    () async {
      final template = (await ProfileTemplateRepository(
        bundle: rootBundle,
      ).loadAll()).first;
      final oldLabels = [
        'Copy',
        'Paste',
        'Cut',
        'Undo',
        'Redo',
        'Save',
        'Previous',
        'Play/Pause',
        'Next',
        'Delete',
        'Volume Down',
        'Volume Up',
      ];
      final oldGeneral = ProfileConfig.fromJson({
        'id': 'profile_general',
        'name': 'General',
        'isBuiltInTemplate': true,
        'buttons': [
          for (var position = 0; position < oldLabels.length; position++)
            {
              'id': 'button_${position + 1}',
              'position': position,
              'label': oldLabels[position],
              'action': {'type': 'none'},
            },
        ],
      });
      final config = AppConfig(
        activeProfileId: oldGeneral.id,
        defaultProfileId: oldGeneral.id,
        profileOrder: [oldGeneral.id],
        profiles: [oldGeneral],
      );

      final migrated = SharedPreferencesConfigRepository.migrateV3Layout(
        config,
        [template],
      );

      expect(migrated.activeProfile.buttons.map((button) => button.label), [
        'Mute',
        'Volume Down',
        'Volume Up',
        'Undo',
        'Redo',
        'Previous',
        'Play/Pause',
        'Next',
        'Open',
        'Favorite',
        'Cut',
        'Copy',
        'Paste',
        'Close',
        'Delete',
      ]);
    },
  );

  test('schema v4 migration keeps buttons and enables mouse control', () async {
    final template = (await ProfileTemplateRepository(
      bundle: rootBundle,
    ).loadAll()).first;
    final currentProfile = profile(firstLabel: 'My first control');
    final migrated = SharedPreferencesConfigRepository.migrateV4MouseControl(
      testConfig(profiles: [currentProfile]),
      [template],
    );

    expect(migrated.activeProfile.buttons.first.label, 'My first control');
    expect(migrated.activeProfile.wheel.controlType, WheelControlType.mousePad);
    expect(migrated.activeProfile.wheel.right.value, 'RIGHT');
  });

  test('semantic icon catalog includes required offline groups', () {
    expect(BuiltinIconCatalog.find('edit.copy'), isNotNull);
    expect(BuiltinIconCatalog.find('edit.paste'), isNotNull);
    expect(BuiltinIconCatalog.find('file.favorite'), isNotNull);
    expect(BuiltinIconCatalog.find('profile.web'), isNotNull);
    expect(BuiltinIconCatalog.find('profile.meetings'), isNotNull);
    expect(BuiltinIconCatalog.find('design.brush'), isNotNull);
    expect(BuiltinIconCatalog.find('cad.extrude'), isNotNull);
    expect(
      BuiltinIconCatalog.entries.map((item) => item.category).toSet(),
      containsAll([
        BuiltinIconCatalog.common,
        BuiltinIconCatalog.navigation,
        BuiltinIconCatalog.media,
        BuiltinIconCatalog.design,
        BuiltinIconCatalog.cad,
      ]),
    );
  });
}
