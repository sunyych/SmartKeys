import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class LocalShortcut {
  const LocalShortcut({
    required this.title,
    required this.keyCode,
    required this.modifiers,
  });
  final String title;
  final String keyCode;
  final List<String> modifiers;

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
    'keyCode': keyCode,
    'modifiers': modifiers,
  };
  factory LocalShortcut.fromJson(Map<String, dynamic> json) {
    final title = json['title'];
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
      modifiers: modifiers.cast<String>(),
    );
  }
}

class LocalProfile {
  const LocalProfile({
    required this.id,
    required this.name,
    required this.shortcuts,
  });
  final String id;
  final String name;
  final List<LocalShortcut> shortcuts;

  LocalProfile withShortcuts(List<LocalShortcut> values) =>
      LocalProfile(id: id, name: name, shortcuts: values);
  Map<String, Object> toJson() => {
    'id': id,
    'name': name,
    'shortcuts': shortcuts.map((value) => value.toJson()).toList(),
  };
  factory LocalProfile.fromJson(Map<String, dynamic> json) {
    if (json['id'] is! String ||
        !RegExp(r'^[a-zA-Z0-9_-]{1,80}$').hasMatch(json['id'] as String) ||
        json['name'] is! String ||
        (json['name'] as String).trim().isEmpty ||
        (json['name'] as String).length > 40 ||
        json['shortcuts'] is! List) {
      throw const FormatException('Invalid local shortcut profile.');
    }
    return LocalProfile(
      id: json['id'] as String,
      name: json['name'] as String,
      shortcuts: (json['shortcuts'] as List)
          .map(
            (value) =>
                LocalShortcut.fromJson((value as Map).cast<String, dynamic>()),
          )
          .toList(),
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
        key('Find', 'F', ctrl),
        key('Save', 'S', ctrl),
        key('Open', 'O', ctrl),
        key('Close', 'W', ctrl),
        key('Delete', 'DELETE'),
        key('Escape', 'ESC'),
        key('Enter', 'ENTER'),
        key('Tab', 'TAB'),
        key('Backspace', 'BACKSPACE'),
      ],
    ),
    LocalProfile(
      id: 'chatgpt',
      name: 'ChatGPT',
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
        key('Backspace', 'BACKSPACE'),
        key('Escape', 'ESC'),
        key('Delete', 'DELETE'),
      ],
    ),
    LocalProfile(
      id: 'chrome',
      name: 'Chrome',
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
        key('Bookmark', 'D', ctrl),
        key('Page top', 'HOME'),
        key('Page bottom', 'END'),
      ],
    ),
  ];
}
