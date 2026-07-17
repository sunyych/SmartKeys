import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/config.dart';
import 'profile_template_repository.dart';

abstract interface class ConfigRepository {
  Future<AppConfig> load();
  Future<void> save(AppConfig config);
}

class SharedPreferencesConfigRepository implements ConfigRepository {
  SharedPreferencesConfigRepository({
    required this.templates,
    Future<SharedPreferences>? preferences,
  }) : _preferences = preferences ?? SharedPreferences.getInstance();

  static const storageKey = 'smart_keys.configuration';

  final ProfileTemplateRepository templates;
  final Future<SharedPreferences> _preferences;

  @override
  Future<AppConfig> load() async {
    final prefs = await _preferences;
    final raw = prefs.getString(storageKey);
    final builtIns = await templates.loadAll();
    if (raw == null) {
      return _fromTemplates(builtIns);
    }
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    final schemaVersion = (decoded['schemaVersion'] as num?)?.toInt();
    if (schemaVersion != null && schemaVersion >= 2) {
      var config = AppConfig.fromJson(decoded);
      if (schemaVersion < 4) {
        config = migrateV3Layout(config, builtIns);
      }
      if (schemaVersion < 5) {
        config = migrateV4MouseControl(config, builtIns);
      }
      if (schemaVersion < 6) {
        config = migrateV5FreeProfiles(config, builtIns);
      }
      if (schemaVersion < AppConfig.currentSchemaVersion) await save(config);
      return config;
    }
    final migrated = migrateV5FreeProfiles(
      migrateV1(decoded, builtIns.first),
      builtIns,
    );
    await save(migrated);
    return migrated;
  }

  @override
  Future<void> save(AppConfig config) async {
    final prefs = await _preferences;
    await prefs.setString(storageKey, jsonEncode(config.toJson()));
  }

  AppConfig _fromTemplates(List<ProfileConfig> profiles) {
    final freeProfiles = profiles
        .take(freeProfileLimit)
        .toList(growable: false);
    return AppConfig(
      activeProfileId: freeProfiles.first.id,
      defaultProfileId: freeProfiles.first.id,
      profileOrder: freeProfiles.map((profile) => profile.id).toList(),
      profiles: freeProfiles,
      preferences: const AppPreferences(
        orientationMode: OrientationMode.landscape,
      ),
    );
  }

  static AppConfig migrateV1(
    Map<String, dynamic> legacy,
    ProfileConfig generalTemplate,
  ) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final legacyButtons = legacy['buttons'] as List?;
    final migratedButtons = legacyButtons == null
        ? generalTemplate.buttons
        : ProfileConfig.fromJson({
            'id': 'profile_general',
            'name': 'General',
            'buttons': legacyButtons,
            'wheel': legacy['wheel'] ?? legacy['jogWheel'],
          }).buttons;
    final profile = generalTemplate.copyWith(
      buttons: migratedButtons,
      wheel: legacy['wheel'] is Map<String, dynamic>
          ? WheelConfig.fromJson(legacy['wheel'] as Map<String, dynamic>)
          : legacy['jogWheel'] is Map<String, dynamic>
          ? WheelConfig.fromJson(legacy['jogWheel'] as Map<String, dynamic>)
          : generalTemplate.wheel,
      createdAt: now,
      updatedAt: now,
    );
    final legacyPreferences = legacy['preferences'] is Map<String, dynamic>
        ? legacy['preferences'] as Map<String, dynamic>
        : <String, dynamic>{
            'hapticEnabled': legacy['hapticEnabled'],
            'soundEnabled': legacy['soundEnabled'],
            'orientationMode': 'landscape',
          };
    final config = AppConfig(
      activeProfileId: profile.id,
      defaultProfileId: profile.id,
      profileOrder: [profile.id],
      profiles: [migrateLegacyPrimaryModifiers(profile)],
      device: DeviceConfig.fromJson(legacy['device'] as Map<String, dynamic>?),
      preferences: AppPreferences.fromJson(legacyPreferences),
    );
    return migrateV4MouseControl(migrateV3Layout(config, [generalTemplate]), [
      generalTemplate,
    ]);
  }

  static AppConfig migrateV3Layout(
    AppConfig config,
    List<ProfileConfig> builtIns,
  ) {
    final templatesById = {for (final profile in builtIns) profile.id: profile};
    final profiles = config.profiles.map((profile) {
      final template = templatesById[profile.id];
      if (profile.id == 'profile_general' &&
          profile.isBuiltInTemplate &&
          template != null) {
        const oldPositionByNewPosition = <int?>[
          null,
          10,
          11,
          3,
          4,
          6,
          7,
          8,
          null,
          null,
          2,
          0,
          1,
          null,
          9,
        ];
        final buttons = List.generate(controlButtonCount, (position) {
          final oldPosition = oldPositionByNewPosition[position];
          final oldButton = oldPosition == null
              ? null
              : profile.buttons[oldPosition];
          final source = oldButton == null || _isGeneratedEmptySlot(oldButton)
              ? template.buttons[position]
              : oldButton;
          return source.copyWith(
            id: 'button_${(position + 1).toString().padLeft(2, '0')}',
            position: position,
          );
        });
        return profile.copyWith(buttons: buttons);
      }

      final byPosition = {
        for (final button in profile.buttons) button.position: button,
      };
      return profile.copyWith(
        buttons: List.generate(
          controlButtonCount,
          (position) => byPosition[position] ?? ButtonConfig.empty(position),
        ),
      );
    }).toList();
    return config.copyWith(profiles: profiles);
  }

  static AppConfig migrateV4MouseControl(
    AppConfig config,
    List<ProfileConfig> builtIns,
  ) {
    final generalTemplate = builtIns
        .where((profile) => profile.id == 'profile_general')
        .firstOrNull;
    if (generalTemplate == null) return config;
    return config.copyWith(
      profiles: config.profiles
          .map(
            (profile) => profile.id == 'profile_general'
                ? profile.copyWith(wheel: generalTemplate.wheel)
                : profile,
          )
          .toList(growable: false),
    );
  }

  static AppConfig migrateV5FreeProfiles(
    AppConfig config,
    List<ProfileConfig> builtIns,
  ) {
    final templatesById = {for (final profile in builtIns) profile.id: profile};
    final general = config.profiles
        .where((profile) => profile.id == 'profile_general')
        .firstOrNull;
    final orderedExisting = [
      for (final id in config.profileOrder)
        ...config.profiles.where((profile) => profile.id == id),
      ...config.profiles.where(
        (profile) => !config.profileOrder.contains(profile.id),
      ),
    ];
    const retiredIds = {
      'profile_photoshop',
      'profile_solidworks',
      'profile_chatgpt',
    };
    final defaultIds = templatesById.keys.toSet();
    final customCandidates = orderedExisting
        .where(
          (profile) =>
              !retiredIds.contains(profile.id) &&
              !defaultIds.contains(profile.id),
        )
        .toList();
    final activeCustom = customCandidates
        .where((profile) => profile.id == config.activeProfileId)
        .firstOrNull;
    final custom = activeCustom ?? customCandidates.firstOrNull;
    final profiles = <ProfileConfig>[
      general ?? templatesById['profile_general']!,
      templatesById['profile_web']!,
      templatesById['profile_meetings']!,
      custom ?? templatesById['profile_custom']!,
    ].take(freeProfileLimit).toList(growable: false);
    final ids = profiles.map((profile) => profile.id).toSet();
    final fallbackId = profiles.first.id;
    return config.copyWith(
      profiles: profiles,
      profileOrder: profiles.map((profile) => profile.id).toList(),
      activeProfileId: ids.contains(config.activeProfileId)
          ? config.activeProfileId
          : fallbackId,
      defaultProfileId: ids.contains(config.defaultProfileId)
          ? config.defaultProfileId
          : fallbackId,
      preferences: config.preferences.orientationMode == OrientationMode.auto
          ? config.preferences.copyWith(
              orientationMode: OrientationMode.landscape,
            )
          : config.preferences,
    );
  }

  static bool _isGeneratedEmptySlot(ButtonConfig button) =>
      button.label == 'Button ${button.position + 1}' &&
      button.subtitle.isEmpty &&
      button.visual.type == VisualType.none &&
      button.action.type == ActionType.none;
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}

class MemoryConfigRepository implements ConfigRepository {
  MemoryConfigRepository(this.value);

  AppConfig value;
  int saveCount = 0;

  @override
  Future<AppConfig> load() async => value;

  @override
  Future<void> save(AppConfig config) async {
    value = config;
    saveCount++;
  }
}
