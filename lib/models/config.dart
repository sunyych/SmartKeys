enum OrientationMode { auto, portrait, landscape }

enum ShortcutPlatform { automatic, apple, windowsLinux }

enum VisualType { none, builtinIcon, customImage }

enum VisualFit { contain, cover, centerCrop }

enum ActionType { keyboard, consumerControl, mouseWheel, mouseMove, none }

enum WheelControlType { jog, mousePad }

const controlButtonCount = 15;
const freeProfileLimit = 4;
const defaultFreeProfileIds = {
  'profile_general',
  'profile_web',
  'profile_meetings',
  'profile_custom',
};

T _enumValue<T extends Enum>(Iterable<T> values, Object? raw, T fallback) {
  final name = raw?.toString();
  return values.where((value) => value.name == name).firstOrNull ?? fallback;
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}

class ButtonVisual {
  const ButtonVisual({
    this.type = VisualType.none,
    this.value,
    this.fit = VisualFit.contain,
    this.tintColor,
    this.backgroundColor,
    this.iconSize = 32,
    this.imageScale = 1,
    this.alignmentX = 0,
    this.alignmentY = 0,
  });

  final VisualType type;
  final String? value;
  final VisualFit fit;
  final int? tintColor;
  final int? backgroundColor;
  final double iconSize;
  final double imageScale;
  final double alignmentX;
  final double alignmentY;

  factory ButtonVisual.fromJson(Map<String, dynamic>? json) {
    final data = json ?? const <String, dynamic>{};
    return ButtonVisual(
      type: _enumValue(VisualType.values, data['type'], VisualType.none),
      value: data['value'] as String?,
      fit: _enumValue(VisualFit.values, data['fit'], VisualFit.contain),
      tintColor: (data['tintColor'] as num?)?.toInt(),
      backgroundColor: (data['backgroundColor'] as num?)?.toInt(),
      iconSize: (data['iconSize'] as num?)?.toDouble() ?? 32,
      imageScale: (data['imageScale'] as num?)?.toDouble() ?? 1,
      alignmentX: (data['alignmentX'] as num?)?.toDouble() ?? 0,
      alignmentY: (data['alignmentY'] as num?)?.toDouble() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'type': type.name,
    'value': value,
    'fit': fit.name,
    'tintColor': tintColor,
    'backgroundColor': backgroundColor,
    'iconSize': iconSize,
    'imageScale': imageScale,
    'alignmentX': alignmentX,
    'alignmentY': alignmentY,
  };

  ButtonVisual copyWith({
    VisualType? type,
    String? value,
    bool clearValue = false,
    VisualFit? fit,
    int? tintColor,
    bool clearTintColor = false,
    int? backgroundColor,
    bool clearBackgroundColor = false,
    double? iconSize,
    double? imageScale,
    double? alignmentX,
    double? alignmentY,
  }) => ButtonVisual(
    type: type ?? this.type,
    value: clearValue ? null : value ?? this.value,
    fit: fit ?? this.fit,
    tintColor: clearTintColor ? null : tintColor ?? this.tintColor,
    backgroundColor: clearBackgroundColor
        ? null
        : backgroundColor ?? this.backgroundColor,
    iconSize: iconSize ?? this.iconSize,
    imageScale: imageScale ?? this.imageScale,
    alignmentX: alignmentX ?? this.alignmentX,
    alignmentY: alignmentY ?? this.alignmentY,
  );
}

class HidAction {
  const HidAction({
    this.type = ActionType.none,
    this.keyCode,
    this.modifiers = const [],
    this.value,
  });

  final ActionType type;
  final String? keyCode;
  final List<String> modifiers;
  final String? value;

  factory HidAction.fromJson(Map<String, dynamic>? json) {
    final data = json ?? const <String, dynamic>{};
    return HidAction(
      type: _enumValue(ActionType.values, data['type'], ActionType.none),
      keyCode: data['keyCode'] as String?,
      modifiers: (data['modifiers'] as List? ?? const [])
          .map((item) => item.toString())
          .toList(growable: false),
      value: data['value'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'type': type.name,
    'keyCode': keyCode,
    'modifiers': modifiers,
    'value': value,
  };

  HidAction copyWith({
    ActionType? type,
    String? keyCode,
    List<String>? modifiers,
    String? value,
  }) => HidAction(
    type: type ?? this.type,
    keyCode: keyCode ?? this.keyCode,
    modifiers: modifiers ?? this.modifiers,
    value: value ?? this.value,
  );
}

class ButtonConfig {
  const ButtonConfig({
    required this.id,
    required this.position,
    this.label = '',
    this.subtitle = '',
    this.showLabel = true,
    this.showShortcut = false,
    this.visual = const ButtonVisual(),
    this.action = const HidAction(),
    this.hapticEnabled = true,
    this.soundEnabled = false,
    this.textSize = 14,
  });

  final String id;
  final int position;
  final String label;
  final String subtitle;
  final bool showLabel;
  final bool showShortcut;
  final ButtonVisual visual;
  final HidAction action;
  final bool hapticEnabled;
  final bool soundEnabled;
  final double textSize;

  factory ButtonConfig.empty(int position) => ButtonConfig(
    id: 'button_${(position + 1).toString().padLeft(2, '0')}',
    position: position,
    label: 'Button ${position + 1}',
  );

  factory ButtonConfig.fromJson(Map<String, dynamic> json) => ButtonConfig(
    id: json['id'] as String? ?? 'button_01',
    position: (json['position'] as num?)?.toInt() ?? 0,
    label: json['label'] as String? ?? '',
    subtitle: json['subtitle'] as String? ?? '',
    showLabel: json['showLabel'] as bool? ?? true,
    showShortcut: json['showShortcut'] as bool? ?? false,
    visual: ButtonVisual.fromJson(json['visual'] as Map<String, dynamic>?),
    action: HidAction.fromJson(json['action'] as Map<String, dynamic>?),
    hapticEnabled: json['hapticEnabled'] as bool? ?? true,
    soundEnabled: json['soundEnabled'] as bool? ?? false,
    textSize: (json['textSize'] as num?)?.toDouble() ?? 14,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'position': position,
    'label': label,
    'subtitle': subtitle,
    'showLabel': showLabel,
    'showShortcut': showShortcut,
    'visual': visual.toJson(),
    'action': action.toJson(),
    'hapticEnabled': hapticEnabled,
    'soundEnabled': soundEnabled,
    'textSize': textSize,
  };

  ButtonConfig copyWith({
    String? id,
    int? position,
    String? label,
    String? subtitle,
    bool? showLabel,
    bool? showShortcut,
    ButtonVisual? visual,
    HidAction? action,
    bool? hapticEnabled,
    bool? soundEnabled,
    double? textSize,
  }) => ButtonConfig(
    id: id ?? this.id,
    position: position ?? this.position,
    label: label ?? this.label,
    subtitle: subtitle ?? this.subtitle,
    showLabel: showLabel ?? this.showLabel,
    showShortcut: showShortcut ?? this.showShortcut,
    visual: visual ?? this.visual,
    action: action ?? this.action,
    hapticEnabled: hapticEnabled ?? this.hapticEnabled,
    soundEnabled: soundEnabled ?? this.soundEnabled,
    textSize: textSize ?? this.textSize,
  );
}

class WheelConfig {
  const WheelConfig({
    this.controlType = WheelControlType.jog,
    this.clockwise = const HidAction(),
    this.counterClockwise = const HidAction(),
    this.center = const HidAction(),
    this.up = const HidAction(),
    this.down = const HidAction(),
    this.left = const HidAction(),
    this.right = const HidAction(),
    this.modeLabel = 'Navigate',
  });

  final WheelControlType controlType;
  final HidAction clockwise;
  final HidAction counterClockwise;
  final HidAction center;
  final HidAction up;
  final HidAction down;
  final HidAction left;
  final HidAction right;
  final String modeLabel;

  factory WheelConfig.fromJson(Map<String, dynamic>? json) {
    final data = json ?? const <String, dynamic>{};
    return WheelConfig(
      controlType: _enumValue(
        WheelControlType.values,
        data['controlType'],
        WheelControlType.jog,
      ),
      clockwise: HidAction.fromJson(data['clockwise'] as Map<String, dynamic>?),
      counterClockwise: HidAction.fromJson(
        data['counterClockwise'] as Map<String, dynamic>?,
      ),
      center: HidAction.fromJson(data['center'] as Map<String, dynamic>?),
      up: HidAction.fromJson(data['up'] as Map<String, dynamic>?),
      down: HidAction.fromJson(data['down'] as Map<String, dynamic>?),
      left: HidAction.fromJson(data['left'] as Map<String, dynamic>?),
      right: HidAction.fromJson(data['right'] as Map<String, dynamic>?),
      modeLabel: data['modeLabel'] as String? ?? 'Navigate',
    );
  }

  Map<String, dynamic> toJson() => {
    'controlType': controlType.name,
    'clockwise': clockwise.toJson(),
    'counterClockwise': counterClockwise.toJson(),
    'center': center.toJson(),
    'up': up.toJson(),
    'down': down.toJson(),
    'left': left.toJson(),
    'right': right.toJson(),
    'modeLabel': modeLabel,
  };
}

class ProfileConfig {
  const ProfileConfig({
    required this.id,
    required this.name,
    required this.buttons,
    required this.wheel,
    required this.createdAt,
    required this.updatedAt,
    this.targetApplication,
    this.profileIcon = const ButtonVisual(),
    this.accentColor,
    this.isBuiltInTemplate = false,
  });

  final String id;
  final String name;
  final String? targetApplication;
  final ButtonVisual profileIcon;
  final int? accentColor;
  final bool isBuiltInTemplate;
  final List<ButtonConfig> buttons;
  final WheelConfig wheel;
  final int createdAt;
  final int updatedAt;

  factory ProfileConfig.fromJson(Map<String, dynamic> json) {
    final parsed = (json['buttons'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => ButtonConfig.fromJson(item.cast<String, dynamic>()))
        .toList();
    final byPosition = {for (final button in parsed) button.position: button};
    final buttons = List.generate(
      controlButtonCount,
      (position) => byPosition[position] ?? ButtonConfig.empty(position),
    );
    buttons.sort((a, b) => a.position.compareTo(b.position));
    final now = DateTime.now().millisecondsSinceEpoch;
    return ProfileConfig(
      id: json['id'] as String? ?? 'profile_$now',
      name: json['name'] as String? ?? 'Profile',
      targetApplication: json['targetApplication'] as String?,
      profileIcon: ButtonVisual.fromJson(
        json['profileIcon'] as Map<String, dynamic>?,
      ),
      accentColor: (json['accentColor'] as num?)?.toInt(),
      isBuiltInTemplate: json['isBuiltInTemplate'] as bool? ?? false,
      buttons: buttons,
      wheel: WheelConfig.fromJson(json['wheel'] as Map<String, dynamic>?),
      createdAt: (json['createdAt'] as num?)?.toInt() ?? now,
      updatedAt: (json['updatedAt'] as num?)?.toInt() ?? now,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'targetApplication': targetApplication,
    'profileIcon': profileIcon.toJson(),
    'accentColor': accentColor,
    'isBuiltInTemplate': isBuiltInTemplate,
    'buttons': buttons.map((button) => button.toJson()).toList(),
    'wheel': wheel.toJson(),
    'createdAt': createdAt,
    'updatedAt': updatedAt,
  };

  ProfileConfig copyWith({
    String? id,
    String? name,
    String? targetApplication,
    bool clearTargetApplication = false,
    ButtonVisual? profileIcon,
    int? accentColor,
    bool? isBuiltInTemplate,
    List<ButtonConfig>? buttons,
    WheelConfig? wheel,
    int? createdAt,
    int? updatedAt,
  }) => ProfileConfig(
    id: id ?? this.id,
    name: name ?? this.name,
    targetApplication: clearTargetApplication
        ? null
        : targetApplication ?? this.targetApplication,
    profileIcon: profileIcon ?? this.profileIcon,
    accentColor: accentColor ?? this.accentColor,
    isBuiltInTemplate: isBuiltInTemplate ?? this.isBuiltInTemplate,
    buttons: buttons ?? this.buttons,
    wheel: wheel ?? this.wheel,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}

class DeviceConfig {
  const DeviceConfig({this.defaultHostAddress, this.defaultHostName});

  final String? defaultHostAddress;
  final String? defaultHostName;

  factory DeviceConfig.fromJson(Map<String, dynamic>? json) => DeviceConfig(
    defaultHostAddress: json?['defaultHostAddress'] as String?,
    defaultHostName: json?['defaultHostName'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'defaultHostAddress': defaultHostAddress,
    'defaultHostName': defaultHostName,
  };
}

class AppPreferences {
  const AppPreferences({
    this.hapticEnabled = true,
    this.soundEnabled = false,
    this.orientationMode = OrientationMode.landscape,
    this.shortcutPlatform = ShortcutPlatform.automatic,
  });

  final bool hapticEnabled;
  final bool soundEnabled;
  final OrientationMode orientationMode;
  final ShortcutPlatform shortcutPlatform;

  factory AppPreferences.fromJson(Map<String, dynamic>? json) => AppPreferences(
    hapticEnabled: json?['hapticEnabled'] as bool? ?? true,
    soundEnabled: json?['soundEnabled'] as bool? ?? false,
    orientationMode: _enumValue(
      OrientationMode.values,
      json?['orientationMode'],
      OrientationMode.landscape,
    ),
    shortcutPlatform: _enumValue(
      ShortcutPlatform.values,
      json?['shortcutPlatform'],
      ShortcutPlatform.automatic,
    ),
  );

  Map<String, dynamic> toJson() => {
    'hapticEnabled': hapticEnabled,
    'soundEnabled': soundEnabled,
    'orientationMode': orientationMode.name,
    'shortcutPlatform': shortcutPlatform.name,
  };

  AppPreferences copyWith({
    bool? hapticEnabled,
    bool? soundEnabled,
    OrientationMode? orientationMode,
    ShortcutPlatform? shortcutPlatform,
  }) => AppPreferences(
    hapticEnabled: hapticEnabled ?? this.hapticEnabled,
    soundEnabled: soundEnabled ?? this.soundEnabled,
    orientationMode: orientationMode ?? this.orientationMode,
    shortcutPlatform: shortcutPlatform ?? this.shortcutPlatform,
  );
}

class AppConfig {
  static const currentSchemaVersion = 6;

  const AppConfig({
    this.schemaVersion = currentSchemaVersion,
    required this.activeProfileId,
    required this.defaultProfileId,
    required this.profileOrder,
    required this.profiles,
    this.device = const DeviceConfig(),
    this.preferences = const AppPreferences(),
  });

  final int schemaVersion;
  final String activeProfileId;
  final String defaultProfileId;
  final List<String> profileOrder;
  final List<ProfileConfig> profiles;
  final DeviceConfig device;
  final AppPreferences preferences;

  ProfileConfig get activeProfile => profiles.firstWhere(
    (profile) => profile.id == activeProfileId,
    orElse: () => profiles.first,
  );

  factory AppConfig.fromJson(Map<String, dynamic> json) {
    final sourceSchemaVersion = (json['schemaVersion'] as num?)?.toInt() ?? 2;
    var profiles = (json['profiles'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => ProfileConfig.fromJson(item.cast<String, dynamic>()))
        .toList();
    if (sourceSchemaVersion < 3) {
      profiles = profiles.map(migrateLegacyPrimaryModifiers).toList();
    }
    if (profiles.isEmpty) {
      throw const FormatException('A configuration needs at least one profile');
    }
    var ids = profiles.map((profile) => profile.id).toSet();
    final rawOrder = (json['profileOrder'] as List? ?? const [])
        .map((item) => item.toString())
        .where(ids.contains)
        .toList();
    var order = [...rawOrder, ...ids.where((id) => !rawOrder.contains(id))];
    if (sourceSchemaVersion >= 6 && order.length > freeProfileLimit) {
      order = order.take(freeProfileLimit).toList(growable: false);
      final allowedIds = order.toSet();
      profiles = profiles
          .where((profile) => allowedIds.contains(profile.id))
          .toList(growable: false);
      ids = allowedIds;
    }
    final requestedActive = json['activeProfileId'] as String?;
    final requestedDefault = json['defaultProfileId'] as String?;
    return AppConfig(
      schemaVersion: currentSchemaVersion,
      activeProfileId: ids.contains(requestedActive)
          ? requestedActive!
          : order.first,
      defaultProfileId: ids.contains(requestedDefault)
          ? requestedDefault!
          : order.first,
      profileOrder: order,
      profiles: profiles,
      device: DeviceConfig.fromJson(json['device'] as Map<String, dynamic>?),
      preferences: AppPreferences.fromJson(
        json['preferences'] as Map<String, dynamic>?,
      ),
    );
  }

  Map<String, dynamic> toJson() => {
    'schemaVersion': schemaVersion,
    'activeProfileId': activeProfileId,
    'defaultProfileId': defaultProfileId,
    'profileOrder': profileOrder,
    'device': device.toJson(),
    'preferences': preferences.toJson(),
    'profiles': profiles.map((profile) => profile.toJson()).toList(),
  };

  AppConfig copyWith({
    String? activeProfileId,
    String? defaultProfileId,
    List<String>? profileOrder,
    List<ProfileConfig>? profiles,
    DeviceConfig? device,
    AppPreferences? preferences,
  }) => AppConfig(
    activeProfileId: activeProfileId ?? this.activeProfileId,
    defaultProfileId: defaultProfileId ?? this.defaultProfileId,
    profileOrder: profileOrder ?? this.profileOrder,
    profiles: profiles ?? this.profiles,
    device: device ?? this.device,
    preferences: preferences ?? this.preferences,
  );
}

const primaryShortcutModifier = 'PRIMARY';

ProfileConfig migrateLegacyPrimaryModifiers(ProfileConfig profile) =>
    profile.copyWith(
      buttons: profile.buttons
          .map(
            (button) => button.copyWith(
              action: _migrateLegacyPrimaryModifier(button.action),
            ),
          )
          .toList(),
      wheel: WheelConfig(
        modeLabel: profile.wheel.modeLabel,
        clockwise: _migrateLegacyPrimaryModifier(profile.wheel.clockwise),
        counterClockwise: _migrateLegacyPrimaryModifier(
          profile.wheel.counterClockwise,
        ),
        center: _migrateLegacyPrimaryModifier(profile.wheel.center),
      ),
    );

HidAction _migrateLegacyPrimaryModifier(HidAction action) {
  final migrated = <String>[];
  for (final modifier in action.modifiers) {
    final normalized = modifier.toUpperCase();
    final value =
        normalized == 'LEFT_CTRL' ||
            normalized == 'LEFT_META' ||
            normalized == 'LEFT_GUI'
        ? primaryShortcutModifier
        : modifier;
    if (!migrated.contains(value)) migrated.add(value);
  }
  return action.copyWith(modifiers: migrated);
}
