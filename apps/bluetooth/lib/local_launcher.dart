import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'local_profiles.dart';

const localLauncherSlotCount = 12;

/// Display metadata alone never grants launch authority. Only a saved keyboard
/// chord can be sent, with its meaning arranged by the user on the computer.
class LocalLaunchSlot {
  const LocalLaunchSlot({
    required this.title,
    this.iconId,
    this.profileId,
    this.launchShortcut,
  });
  final String title;
  final String? iconId, profileId;
  final LocalShortcut? launchShortcut;
  bool get configured {
    final shortcut = launchShortcut;
    if (shortcut == null || !shortcut.isKeyboard || title.trim().isEmpty) {
      return false;
    }
    try {
      LocalShortcut.fromJson(shortcut.toJson());
      return true;
    } catch (_) {
      return false;
    }
  }

  Map<String, Object?> toJson() => {
    'title': title,
    'iconId': iconId,
    'profileId': profileId,
    'launchShortcut': launchShortcut?.toJson(),
  };
  factory LocalLaunchSlot.fromJson(Map<String, dynamic> json) {
    const allowed = {'title', 'iconId', 'profileId', 'launchShortcut'};
    final title = json['title'],
        icon = json['iconId'],
        profile = json['profileId'];
    bool id(Object? value) =>
        value == null ||
        value is String && RegExp(r'^[a-zA-Z0-9_-]{1,80}$').hasMatch(value);
    if (json.keys.any((key) => !allowed.contains(key)) ||
        title is! String ||
        title.length > 40 ||
        title.codeUnits.any((c) => c < 32 || c == 127) ||
        !id(icon) ||
        !id(profile)) {
      throw const FormatException('Invalid local launch slot.');
    }
    final raw = json['launchShortcut'];
    final shortcut = raw == null
        ? null
        : raw is Map
        ? LocalShortcut.fromJson(raw.cast<String, dynamic>())
        : throw const FormatException('Invalid local launch shortcut.');
    if (shortcut != null && (!shortcut.isKeyboard || title.trim().isEmpty)) {
      throw const FormatException(
        'Launching requires a keyboard combination and application name.',
      );
    }
    return LocalLaunchSlot(
      title: title.trim(),
      iconId: icon as String?,
      profileId: profile as String?,
      launchShortcut: shortcut,
    );
  }
}

List<LocalLaunchSlot> defaultLocalLauncherSlots() => [
  const LocalLaunchSlot(
    title: 'ChatGPT',
    iconId: 'chatgpt',
    profileId: 'chatgpt',
  ),
  const LocalLaunchSlot(title: 'Chrome', iconId: 'chrome', profileId: 'chrome'),
  for (var index = 2; index < localLauncherSlotCount; index++)
    const LocalLaunchSlot(title: ''),
];

List<LocalLaunchSlot> validateLocalLauncherSlots(List<LocalLaunchSlot> slots) {
  if (slots.length != localLauncherSlotCount) {
    throw const FormatException('Launchpad requires twelve slots.');
  }
  return List.unmodifiable(
    slots.map((slot) => LocalLaunchSlot.fromJson(slot.toJson())),
  );
}

abstract interface class LocalLauncherStore {
  Future<List<LocalLaunchSlot>> load();
  Future<void> save(List<LocalLaunchSlot> slots);
}

class SharedPreferencesLauncherStore implements LocalLauncherStore {
  const SharedPreferencesLauncherStore();
  static const storageKey = 'lite.launchpad.v1';
  @override
  Future<List<LocalLaunchSlot>> load() async {
    final raw = (await SharedPreferences.getInstance()).getString(storageKey);
    if (raw == null) return defaultLocalLauncherSlots();
    if (utf8.encode(raw).length > 128 * 1024) {
      throw const FormatException('Invalid local launchpad.');
    }
    final decoded = jsonDecode(raw);
    if (decoded is! Map ||
        decoded.length != 2 ||
        decoded['schemaVersion'] != 1 ||
        decoded['slots'] is! List) {
      throw const FormatException('Invalid local launchpad.');
    }
    return validateLocalLauncherSlots(
      (decoded['slots'] as List)
          .map(
            (slot) =>
                LocalLaunchSlot.fromJson((slot as Map).cast<String, dynamic>()),
          )
          .toList(),
    );
  }

  @override
  Future<void> save(List<LocalLaunchSlot> slots) async {
    final safe = validateLocalLauncherSlots(slots);
    final raw = jsonEncode({
      'schemaVersion': 1,
      'slots': safe.map((slot) => slot.toJson()).toList(),
    });
    if (utf8.encode(raw).length > 128 * 1024) {
      throw const FormatException('Invalid local launchpad.');
    }
    if (!await (await SharedPreferences.getInstance()).setString(
      storageKey,
      raw,
    )) {
      throw StateError('The launchpad could not be saved on the phone.');
    }
  }
}

class MemoryLocalLauncherStore implements LocalLauncherStore {
  List<LocalLaunchSlot> slots = defaultLocalLauncherSlots();
  bool failLoad = false, failSave = false;
  @override
  Future<List<LocalLaunchSlot>> load() async {
    if (failLoad) throw StateError('Local launchpad unavailable.');
    return validateLocalLauncherSlots(slots);
  }

  @override
  Future<void> save(List<LocalLaunchSlot> slots) async {
    if (failSave) throw StateError('Local launchpad unavailable.');
    this.slots = validateLocalLauncherSlots(slots);
  }
}
