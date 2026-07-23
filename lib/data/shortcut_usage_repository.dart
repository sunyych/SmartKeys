import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ShortcutUsageRecord {
  const ShortcutUsageRecord({
    required this.key,
    required this.label,
    required this.count,
    required this.lastUsedAt,
  });

  final String key;
  final String label;
  final int count;
  final int lastUsedAt;

  Map<String, Object?> toJson() => {
    'key': key,
    'label': label,
    'count': count,
    'lastUsedAt': lastUsedAt,
  };

  factory ShortcutUsageRecord.fromJson(Map<String, Object?> json) {
    return ShortcutUsageRecord(
      key: json['key']?.toString() ?? '',
      label: json['label']?.toString() ?? '',
      count: (json['count'] as num?)?.toInt() ?? 0,
      lastUsedAt: (json['lastUsedAt'] as num?)?.toInt() ?? 0,
    );
  }
}

abstract class ShortcutUsageRepository extends ChangeNotifier {
  Future<void> load();
  Future<void> record(String key, String label);
  Future<void> clear();
  int countFor(String key);
  List<ShortcutUsageRecord> get records;
}

class SharedPreferencesShortcutUsageRepository extends ShortcutUsageRepository {
  SharedPreferencesShortcutUsageRepository({
    Future<SharedPreferences>? preferences,
  }) : _preferences = preferences ?? SharedPreferences.getInstance();

  static const storageKey = 'lumiakeys.local_shortcut_usage.v1';

  final Future<SharedPreferences> _preferences;
  final Map<String, ShortcutUsageRecord> _records = {};

  @override
  List<ShortcutUsageRecord> get records {
    final result = _records.values.toList(growable: false);
    result.sort((a, b) {
      final byCount = b.count.compareTo(a.count);
      return byCount != 0 ? byCount : b.lastUsedAt.compareTo(a.lastUsedAt);
    });
    return result;
  }

  @override
  int countFor(String key) => _records[key]?.count ?? 0;

  @override
  Future<void> load() async {
    final raw = (await _preferences).getString(storageKey);
    if (raw == null) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      _records
        ..clear()
        ..addEntries(
          decoded
              .whereType<Map>()
              .map((item) {
                final record = ShortcutUsageRecord.fromJson(
                  item.map((key, value) => MapEntry(key.toString(), value)),
                );
                return MapEntry(record.key, record);
              })
              .where((entry) => entry.key.isNotEmpty),
        );
      notifyListeners();
    } on FormatException {
      // A corrupt private counter must never prevent LumiaKeys from starting.
    }
  }

  @override
  Future<void> record(String key, String label) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final previous = _records[key];
    _records[key] = ShortcutUsageRecord(
      key: key,
      label: label.trim().isEmpty
          ? previous?.label ?? 'Shortcut'
          : label.trim(),
      count: (previous?.count ?? 0) + 1,
      lastUsedAt: now,
    );
    notifyListeners();
    await _save();
  }

  @override
  Future<void> clear() async {
    _records.clear();
    notifyListeners();
    await (await _preferences).remove(storageKey);
  }

  Future<void> _save() async {
    await (await _preferences).setString(
      storageKey,
      jsonEncode(_records.values.map((record) => record.toJson()).toList()),
    );
  }
}

class MemoryShortcutUsageRepository extends ShortcutUsageRepository {
  final Map<String, ShortcutUsageRecord> _records = {};

  @override
  List<ShortcutUsageRecord> get records {
    final result = _records.values.toList(growable: false);
    result.sort((a, b) => b.count.compareTo(a.count));
    return result;
  }

  @override
  int countFor(String key) => _records[key]?.count ?? 0;

  @override
  Future<void> load() async {}

  @override
  Future<void> record(String key, String label) async {
    final previous = _records[key];
    _records[key] = ShortcutUsageRecord(
      key: key,
      label: label,
      count: (previous?.count ?? 0) + 1,
      lastUsedAt: DateTime.now().millisecondsSinceEpoch,
    );
    notifyListeners();
  }

  @override
  Future<void> clear() async {
    _records.clear();
    notifyListeners();
  }
}
