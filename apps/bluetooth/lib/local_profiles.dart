import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class LocalShortcut {
  const LocalShortcut({
    required this.title,
    required this.keyCode,
    required this.modifiers,
  }) : consumerUsage = null;
  const LocalShortcut.consumer({required this.title, required String usage})
    : consumerUsage = usage,
      keyCode = '',
      modifiers = const [];
  final String title;
  final String keyCode;
  final List<String> modifiers;
  final String? consumerUsage;
  bool get isConsumer => consumerUsage != null;
  bool get isKeyboard => consumerUsage == null;
  static const consumerUsages = {
    'PLAY_PAUSE',
    'MUTE',
    'VOLUME_UP',
    'VOLUME_DOWN',
    'NEXT_TRACK',
    'PREVIOUS_TRACK',
    'STOP',
  };
  Map<String, Object> toHidAction() => isConsumer
      ? {'type': 'consumerControl', 'value': consumerUsage!}
      : {
          'type': 'keyboard',
          'keyCode': keyCode,
          'modifiers': List<String>.of(modifiers),
        };

  static const modifierNames = {
    'LEFT_CTRL',
    'LEFT_ALT',
    'LEFT_SHIFT',
    'LEFT_META',
  };
  static bool validKey(String key) => RegExp(
    r'^(?:[A-Z]|[0-9]|F(?:[1-9]|1[0-2])|ENTER|ESC|ESCAPE|BACKSPACE|TAB|SPACE|LEFT|RIGHT|UP|DOWN|DELETE|HOME|END|PAGE_UP|PAGE_DOWN)$',
  ).hasMatch(key);

  Map<String, Object> toJson() => {
    'title': title,
    if (isConsumer)
      'consumerUsage': consumerUsage!
    else ...{
      'keyCode': keyCode,
      'modifiers': modifiers,
    },
  };
  factory LocalShortcut.fromJson(Map<String, dynamic> json) {
    final title = json['title'];
    if (json.containsKey('consumerUsage')) {
      final usage = json['consumerUsage'];
      if (title is! String ||
          title.trim().isEmpty ||
          title.length > 40 ||
          usage is! String ||
          !consumerUsages.contains(usage) ||
          json.containsKey('keyCode') ||
          json.containsKey('modifiers')) {
        throw const FormatException('Invalid local Bluetooth media shortcut.');
      }
      return LocalShortcut.consumer(title: title.trim(), usage: usage);
    }
    final keyCode = json['keyCode'];
    final modifiers = json['modifiers'];
    if (title is! String ||
        title.trim().isEmpty ||
        title.length > 40 ||
        keyCode is! String ||
        !validKey(keyCode) ||
        modifiers is! List ||
        modifiers.length > 4 ||
        modifiers.any(
          (value) => value is! String || !modifierNames.contains(value),
        )) {
      throw const FormatException('Invalid local Bluetooth shortcut.');
    }
    return LocalShortcut(
      title: title.trim(),
      keyCode: keyCode,
      modifiers: List<String>.unmodifiable(modifiers.cast<String>()),
    );
  }
}

class LocalProfile {
  const LocalProfile({
    required this.id,
    required this.name,
    required this.shortcuts,
    this.iconId,
  });
  final String id;
  final String name;
  final List<LocalShortcut> shortcuts;
  final String? iconId;

  LocalProfile withShortcuts(List<LocalShortcut> values) =>
      LocalProfile(id: id, name: name, shortcuts: values, iconId: iconId);
  LocalProfile copyWith({
    String? name,
    String? iconId,
    List<LocalShortcut>? shortcuts,
    bool clearIcon = false,
  }) => LocalProfile(
    id: id,
    name: name ?? this.name,
    iconId: clearIcon ? null : iconId ?? this.iconId,
    shortcuts: shortcuts ?? this.shortcuts,
  );
  Map<String, Object> toJson() => {
    'id': id,
    'name': name,
    'shortcuts': shortcuts.map((value) => value.toJson()).toList(),
    'iconId': ?iconId,
  };
  factory LocalProfile.fromJson(Map<String, dynamic> json) {
    if (json['id'] is! String ||
        !RegExp(r'^[a-zA-Z0-9_-]{1,80}$').hasMatch(json['id'] as String) ||
        json['name'] is! String ||
        (json['name'] as String).trim().isEmpty ||
        (json['name'] as String).length > 40 ||
        json['shortcuts'] is! List ||
        (json['iconId'] != null &&
            (json['iconId'] is! String ||
                !RegExp(
                  r'^[a-zA-Z0-9_-]{1,80}$',
                ).hasMatch(json['iconId'] as String)))) {
      throw const FormatException('Invalid local shortcut profile.');
    }
    return LocalProfile(
      id: json['id'] as String,
      name: json['name'] as String,
      iconId: json['iconId'] as String?,
      shortcuts: List<LocalShortcut>.unmodifiable(
        (json['shortcuts'] as List)
            .map(
              (value) => LocalShortcut.fromJson(
                (value as Map).cast<String, dynamic>(),
              ),
            )
            .toList(),
      ),
    );
  }
}

abstract interface class LocalProfileStore {
  Future<List<LocalProfile>> load();
  Future<void> save(List<LocalProfile> profiles);
}

class SharedPreferencesProfileStore implements LocalProfileStore {
  const SharedPreferencesProfileStore();
  static const storageKey = 'lite.profiles.v1';
  static const legacyStorageKey = 'lite.shortcuts';

  @override
  Future<List<LocalProfile>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(storageKey);
    if (raw != null) {
      final values = (jsonDecode(raw) as List)
          .map(
            (value) =>
                LocalProfile.fromJson((value as Map).cast<String, dynamic>()),
          )
          .toList();
      if (values.isEmpty ||
          values.map((profile) => profile.id).toSet().length != values.length) {
        throw const FormatException('Invalid local profile list.');
      }
      return values;
    }
    final profiles = defaultLocalProfiles();
    final legacy = prefs.getString(legacyStorageKey);
    if (legacy != null) {
      final shortcuts = (jsonDecode(legacy) as List)
          .map(
            (value) =>
                LocalShortcut.fromJson((value as Map).cast<String, dynamic>()),
          )
          .toList();
      profiles.add(
        LocalProfile(id: 'custom', name: 'Custom', shortcuts: shortcuts),
      );
    }
    return profiles;
  }

  @override
  Future<void> save(List<LocalProfile> profiles) async {
    if (profiles.isEmpty ||
        profiles.map((p) => p.id).toSet().length != profiles.length) {
      throw const FormatException('Invalid local profile list.');
    }
    for (final profile in profiles) {
      LocalProfile.fromJson(profile.toJson());
    }
    final prefs = await SharedPreferences.getInstance();
    final saved = await prefs.setString(
      storageKey,
      jsonEncode(profiles.map((value) => value.toJson()).toList()),
    );
    if (!saved) {
      throw StateError('Android preferences did not save the shortcuts.');
    }
  }
}

List<LocalProfile> defaultLocalProfiles() {
  LocalShortcut key(
    String title,
    String code, [
    List<String> modifiers = const [],
  ]) => LocalShortcut(title: title, keyCode: code, modifiers: modifiers);
  const ctrl = ['LEFT_CTRL'];
  const ctrlShift = ['LEFT_CTRL', 'LEFT_SHIFT'];
  return [
    LocalProfile(
      id: 'general',
      name: 'General',
      shortcuts: [
        key('Copy', 'C', ctrl),
        key('Paste', 'V', ctrl),
        key('Cut', 'X', ctrl),
        key('Undo', 'Z', ctrl),
        key('Redo', 'Y', ctrl),
        key('Select all', 'A', ctrl),
        const LocalShortcut.consumer(
          title: 'Play / pause',
          usage: 'PLAY_PAUSE',
        ),
        const LocalShortcut.consumer(title: 'Mute', usage: 'MUTE'),
        const LocalShortcut.consumer(
          title: 'Volume down',
          usage: 'VOLUME_DOWN',
        ),
        const LocalShortcut.consumer(title: 'Volume up', usage: 'VOLUME_UP'),
        const LocalShortcut.consumer(
          title: 'Previous track',
          usage: 'PREVIOUS_TRACK',
        ),
        const LocalShortcut.consumer(title: 'Next track', usage: 'NEXT_TRACK'),
      ],
    ),
    LocalProfile(
      id: 'chatgpt',
      name: 'ChatGPT',
      iconId: 'chatgpt',
      shortcuts: [
        key('New chat', 'N', ctrl),
        key('Previous chat', 'TAB', ctrlShift),
        key('Next chat', 'TAB', ctrl),
        key('Find', 'F', ctrl),
        key('Sidebar', 'B', ctrl),
        key('Copy', 'C', ctrl),
        key('Paste', 'V', ctrl),
        key('Cut', 'X', ctrl),
        key('Undo', 'Z', ctrl),
        key('Select all', 'A', ctrl),
        key('Send', 'ENTER'),
        key('New line', 'ENTER', ['LEFT_SHIFT']),
      ],
    ),
    LocalProfile(
      id: 'chrome',
      name: 'Chrome',
      iconId: 'chrome',
      shortcuts: [
        key('New tab', 'T', ctrl),
        key('Close tab', 'W', ctrl),
        key('Reopen tab', 'T', ctrlShift),
        key('Previous tab', 'TAB', ctrlShift),
        key('Next tab', 'TAB', ctrl),
        key('Back', 'LEFT', ['LEFT_ALT']),
        key('Forward', 'RIGHT', ['LEFT_ALT']),
        key('Refresh', 'R', ctrl),
        key('Address bar', 'L', ctrl),
        key('Find', 'F', ctrl),
        key('Copy', 'C', ctrl),
        key('Paste', 'V', ctrl),
      ],
    ),
  ];
}
