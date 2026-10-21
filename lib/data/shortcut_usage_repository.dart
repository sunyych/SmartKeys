import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'private_usage_directory.dart';

class ShortcutUsageEvent {
  const ShortcutUsageEvent({
    required this.id,
    required this.key,
    required this.label,
    required this.usedAt,
    this.publicShortcutId,
  });

  final String id;
  final String key;
  final String label;
  final int usedAt;
  final String? publicShortcutId;

  Map<String, Object?> toJson() => {
    'id': id,
    'key': key,
    'label': label,
    'usedAt': usedAt,
    if (publicShortcutId != null) 'publicShortcutId': publicShortcutId,
  };

  factory ShortcutUsageEvent.fromJson(Map<String, Object?> json) =>
      ShortcutUsageEvent(
        id: json['id']?.toString() ?? '',
        key: json['key']?.toString() ?? '',
        label: json['label']?.toString() ?? '',
        usedAt: (json['usedAt'] as num?)?.toInt() ?? 0,
        publicShortcutId: json['publicShortcutId'] as String?,
      );
}

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
  Future<void> record(String key, String label, {String? publicShortcutId});
  Future<void> clear();
  int countFor(String key);
  List<ShortcutUsageRecord> get records;
  List<ShortcutUsageEvent> get events;
  bool get hasLegacyCounts;
  Object? get lastError;

  List<ShortcutUsageRecord> recordsForPeriod({DateTime? start, DateTime? end}) {
    final startMs = start?.millisecondsSinceEpoch;
    final endMs = end?.millisecondsSinceEpoch;
    final grouped = <String, ShortcutUsageRecord>{};
    for (final event in events) {
      if (startMs != null && event.usedAt < startMs) continue;
      if (endMs != null && event.usedAt >= endMs) continue;
      final previous = grouped[event.key];
      grouped[event.key] = ShortcutUsageRecord(
        key: event.key,
        label: event.label,
        count: (previous?.count ?? 0) + 1,
        lastUsedAt: event.usedAt > (previous?.lastUsedAt ?? 0)
            ? event.usedAt
            : (previous?.lastUsedAt ?? 0),
      );
    }
    final result = grouped.values.toList();
    result.sort((a, b) {
      final byCount = b.count.compareTo(a.count);
      return byCount != 0 ? byCount : b.lastUsedAt.compareTo(a.lastUsedAt);
    });
    return result;
  }

  Future<void> flush() async {}
}

/// Private, append-only mobile journal. Legacy aggregate records are retained
/// separately so no historical click timestamps are fabricated.
class FileShortcutUsageRepository extends ShortcutUsageRepository {
  FileShortcutUsageRepository({
    Future<Directory> Function()? directoryProvider,
    Future<SharedPreferences>? preferences,
  }) : _directoryProvider = directoryProvider ?? privateUsageDirectory,
       _preferences = preferences ?? SharedPreferences.getInstance();

  static const legacyStorageKey = 'lumiakeys.local_shortcut_usage.v1';
  final Future<Directory> Function() _directoryProvider;
  final Future<SharedPreferences> _preferences;
  final List<ShortcutUsageEvent> _events = [];
  final Map<String, ShortcutUsageRecord> _legacy = {};
  final Map<String, ShortcutUsageRecord> _recordsCache = {};
  Future<void> _tail = Future<void>.value();
  File? _journal;
  File? _legacyFile;
  File? _clearMarker;
  bool _loaded = false;
  Object? _lastError;

  @override
  List<ShortcutUsageEvent> get events => List.unmodifiable(_events);
  @override
  bool get hasLegacyCounts => _legacy.values.any((record) => record.count > 0);
  @override
  Object? get lastError => _lastError;

  @override
  List<ShortcutUsageRecord> get records {
    final result = _recordsCache.values.toList();
    result.sort((a, b) {
      final byCount = b.count.compareTo(a.count);
      return byCount != 0 ? byCount : b.lastUsedAt.compareTo(a.lastUsedAt);
    });
    return result;
  }

  @override
  int countFor(String key) {
    return _recordsCache[key]?.count ?? 0;
  }

  @override
  Future<void> load() async => _serialize(() async {
    _lastError = null;
    try {
      final directory = await _directoryProvider();
      await directory.create(recursive: true);
      _journal = File('${directory.path}${Platform.pathSeparator}events.jsonl');
      _legacyFile = File(
        '${directory.path}${Platform.pathSeparator}legacy.json',
      );
      _clearMarker = File(
        '${directory.path}${Platform.pathSeparator}clear.marker',
      );
      await _recoverReplacements();
      await _readLegacy();
      await _readJournal();
      await _recoverInterruptedClear();
      _rebuildRecordsCache();
      _loaded = true;
      notifyListeners();
    } catch (error) {
      _lastError = error;
      rethrow;
    }
  });

  Future<void> _readLegacy() async {
    final file = _legacyFile!;
    if (await file.exists()) {
      var valid = false;
      try {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is List) {
          valid = true;
          _legacy
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
                  .where(
                    (entry) => entry.key.isNotEmpty && entry.value.count > 0,
                  ),
            );
        }
      } on FormatException {
        valid = false;
      } on TypeError {
        valid = false;
      }
      if (valid) {
        await (await _preferences).remove(legacyStorageKey);
        return;
      }
      _legacy.clear();
    }
    final preferences = await _preferences;
    final raw = preferences.getString(legacyStorageKey);
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          _legacy.addEntries(
            decoded
                .whereType<Map>()
                .map((item) {
                  final record = ShortcutUsageRecord.fromJson(
                    item.map((key, value) => MapEntry(key.toString(), value)),
                  );
                  return MapEntry(record.key, record);
                })
                .where(
                  (entry) => entry.key.isNotEmpty && entry.value.count > 0,
                ),
          );
        }
      } on FormatException {
        // Ignore corrupt legacy counters.
      } on TypeError {
        _legacy.clear();
      }
    }
    if (_legacy.isNotEmpty) {
      await _atomicWrite(
        file,
        utf8.encode(jsonEncode(_legacy.values.map((r) => r.toJson()).toList())),
      );
    }
    await preferences.remove(legacyStorageKey);
  }

  Future<void> _readJournal() async {
    final file = _journal!;
    _events.clear();
    if (!await file.exists()) return;
    final bytes = await file.readAsBytes();
    final marker = await _readClearMarker();
    final beginning = marker ?? 0;
    if (beginning < 0 || beginning > bytes.length) return;
    final lastNewline = bytes.lastIndexOf(10);
    final validLength = lastNewline + 1;
    if (validLength < bytes.length) {
      await file.writeAsBytes(bytes.sublist(0, validLength), flush: true);
    }
    var lineStart = beginning;
    while (lineStart < validLength) {
      final lineEnd = bytes.indexOf(10, lineStart);
      if (lineEnd < 0 || lineEnd >= validLength) break;
      try {
        final decoded = jsonDecode(
          utf8.decode(bytes.sublist(lineStart, lineEnd)),
        );
        if (decoded is Map && _isValidEventMap(decoded)) {
          final event = ShortcutUsageEvent.fromJson(
            decoded.map((key, value) => MapEntry(key.toString(), value)),
          );
          _events.add(event);
        }
      } on FormatException {
        // Skip malformed complete lines and continue recovery.
      } on TypeError {
        // Skip malformed records without preventing later records from loading.
      }
      lineStart = lineEnd + 1;
    }
    _events.sort((a, b) => a.usedAt.compareTo(b.usedAt));
  }

  bool _isValidEventMap(Map value) =>
      value['id'] is String &&
      (value['id'] as String).isNotEmpty &&
      value['key'] is String &&
      (value['key'] as String).isNotEmpty &&
      value['label'] is String &&
      value['usedAt'] is int &&
      (value['publicShortcutId'] == null ||
          value['publicShortcutId'] is String);

  @override
  Future<void> record(String key, String label, {String? publicShortcutId}) {
    final event = ShortcutUsageEvent(
      id: _newEventId(),
      key: key,
      label: label.trim().isEmpty ? 'Shortcut' : label.trim(),
      usedAt: DateTime.now().millisecondsSinceEpoch,
      publicShortcutId: publicShortcutId,
    );
    return _serialize(() async {
      try {
        if (!_loaded) await _loadInsideQueue();
        await _journal!.writeAsString(
          '${jsonEncode(event.toJson())}\n',
          mode: FileMode.append,
          flush: true,
        );
        _lastError = null;
        _insertEvent(event);
        _addToRecordsCache(event);
        notifyListeners();
      } catch (error) {
        _lastError = error;
        // Recording failure must not interrupt the shortcut action.
        notifyListeners();
      }
    });
  }

  Future<void> _loadInsideQueue() async {
    final directory = await _directoryProvider();
    await directory.create(recursive: true);
    _journal = File('${directory.path}${Platform.pathSeparator}events.jsonl');
    _legacyFile = File('${directory.path}${Platform.pathSeparator}legacy.json');
    _clearMarker = File(
      '${directory.path}${Platform.pathSeparator}clear.marker',
    );
    await _recoverReplacements();
    await _readLegacy();
    await _readJournal();
    await _recoverInterruptedClear();
    _rebuildRecordsCache();
    _loaded = true;
  }

  @override
  Future<void> clear() => _serialize(() async {
    try {
      if (!_loaded) await _loadInsideQueue();
    } catch (error) {
      _lastError = error;
      notifyListeners();
      rethrow;
    }
    final currentMarker = await _readClearMarker();
    final offset =
        currentMarker ??
        (await _journal!.exists() ? await _journal!.length() : 0);
    try {
      await _atomicWrite(_clearMarker!, utf8.encode('$offset'));
      final journalBytes = await _journal!.exists()
          ? await _journal!.readAsBytes()
          : <int>[];
      final retained = journalBytes.sublist(
        offset.clamp(0, journalBytes.length),
      );
      final lastNewline = retained.lastIndexOf(10);
      final validRetained = lastNewline < 0
          ? <int>[]
          : retained.sublist(0, lastNewline + 1);
      await _atomicWrite(_journal!, validRetained);
      await _atomicWrite(_legacyFile!, utf8.encode('[]'));
      await _clearMarker!.delete();
    } catch (error) {
      _lastError = error;
      try {
        await _recoverInterruptedClear();
        _rebuildRecordsCache();
        notifyListeners();
      } catch (_) {
        // Preserve the error for the caller so the clear can be retried.
      }
      notifyListeners();
      rethrow;
    }
    _events.clear();
    _legacy.clear();
    _recordsCache.clear();
    _lastError = null;
    notifyListeners();
  });

  @override
  Future<void> flush() => _tail;

  void _rebuildRecordsCache() {
    _recordsCache
      ..clear()
      ..addAll(_legacy);
    for (final event in _events) {
      _addToRecordsCache(event);
    }
  }

  void _addToRecordsCache(ShortcutUsageEvent event) {
    final previous = _recordsCache[event.key];
    _recordsCache[event.key] = ShortcutUsageRecord(
      key: event.key,
      label: event.label,
      count: (previous?.count ?? 0) + 1,
      lastUsedAt: event.usedAt > (previous?.lastUsedAt ?? 0)
          ? event.usedAt
          : (previous?.lastUsedAt ?? 0),
    );
  }

  Future<int?> _readClearMarker() async {
    final marker = _clearMarker;
    if (marker == null || !await marker.exists()) return null;
    return int.tryParse(await marker.readAsString());
  }

  Future<void> _recoverInterruptedClear() async {
    final offset = await _readClearMarker();
    if (offset == null) return;
    final bytes = await _journal!.exists()
        ? await _journal!.readAsBytes()
        : <int>[];
    final tail = bytes.sublist(offset.clamp(0, bytes.length));
    final lastNewline = tail.lastIndexOf(10);
    final validTail = lastNewline < 0
        ? <int>[]
        : tail.sublist(0, lastNewline + 1);
    await _atomicWrite(_journal!, validTail);
    await _atomicWrite(_legacyFile!, utf8.encode('[]'));
    await _clearMarker!.delete();
    _legacy.clear();
    _events.clear();
    if (validTail.isNotEmpty) await _readJournal();
  }

  Future<void> _recoverReplacements() async {
    for (final file in [_journal!, _legacyFile!, _clearMarker!]) {
      final previous = File('${file.path}.previous');
      if (!await file.exists() && await previous.exists()) {
        await previous.rename(file.path);
      } else if (await file.exists() && await previous.exists()) {
        await previous.delete();
      }
      final temporary = File('${file.path}.next');
      if (await temporary.exists()) await temporary.delete();
    }
  }

  Future<void> _atomicWrite(File file, List<int> contents) async {
    final temporary = File('${file.path}.next');
    final previous = File('${file.path}.previous');
    await temporary.writeAsBytes(contents, flush: true);
    if (await previous.exists()) await previous.delete();
    if (await file.exists()) await file.rename(previous.path);
    try {
      await temporary.rename(file.path);
      if (await previous.exists()) await previous.delete();
    } catch (_) {
      if (!await file.exists() && await previous.exists()) {
        await previous.rename(file.path);
      }
      rethrow;
    }
  }

  void _insertEvent(ShortcutUsageEvent event) {
    if (_events.isEmpty || _events.last.usedAt <= event.usedAt) {
      _events.add(event);
      return;
    }
    var low = 0;
    var high = _events.length;
    while (low < high) {
      final middle = (low + high) >> 1;
      if (_events[middle].usedAt <= event.usedAt) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    _events.insert(low, event);
  }

  Future<void> _serialize(Future<void> Function() operation) {
    final next = _tail.then((_) => operation());
    _tail = next.catchError((Object _) {});
    return next;
  }

  static String _newEventId() {
    final random = Random.secure();
    return List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }
}

/// SharedPreferences adapter retained for existing tests and migration input.
class SharedPreferencesShortcutUsageRepository extends ShortcutUsageRepository {
  SharedPreferencesShortcutUsageRepository({
    Future<SharedPreferences>? preferences,
  }) : _preferences = preferences ?? SharedPreferences.getInstance();
  static const storageKey = FileShortcutUsageRepository.legacyStorageKey;
  final Future<SharedPreferences> _preferences;
  final Map<String, ShortcutUsageRecord> _records = {};
  final List<ShortcutUsageEvent> _events = [];
  @override
  List<ShortcutUsageEvent> get events => List.unmodifiable(_events);
  @override
  bool get hasLegacyCounts => _records.isNotEmpty;
  @override
  Object? get lastError => null;
  @override
  List<ShortcutUsageRecord> get records =>
      _records.values.toList()..sort((a, b) => b.count.compareTo(a.count));
  @override
  int countFor(String key) => _records[key]?.count ?? 0;
  @override
  Future<void> load() async {
    final raw = (await _preferences).getString(storageKey);
    if (raw == null) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        _records
          ..clear()
          ..addEntries(
            decoded
                .whereType<Map>()
                .map((item) {
                  final record = ShortcutUsageRecord.fromJson(
                    item.map((k, v) => MapEntry(k.toString(), v)),
                  );
                  return MapEntry(record.key, record);
                })
                .where((entry) => entry.key.isNotEmpty),
          );
        notifyListeners();
      }
    } on FormatException {
      // Ignore corrupt legacy counters.
    }
  }

  @override
  Future<void> record(
    String key,
    String label, {
    String? publicShortcutId,
  }) async {
    final previous = _records[key];
    _records[key] = ShortcutUsageRecord(
      key: key,
      label: label,
      count: (previous?.count ?? 0) + 1,
      lastUsedAt: DateTime.now().millisecondsSinceEpoch,
    );
    notifyListeners();
    await (await _preferences).setString(
      storageKey,
      jsonEncode(_records.values.map((r) => r.toJson()).toList()),
    );
  }

  @override
  Future<void> clear() async {
    _records.clear();
    _events.clear();
    notifyListeners();
    await (await _preferences).remove(storageKey);
  }
}

class MemoryShortcutUsageRepository extends ShortcutUsageRepository {
  final List<ShortcutUsageEvent> _events = [];
  final Map<String, ShortcutUsageRecord> _legacy = {};
  @override
  List<ShortcutUsageEvent> get events => List.unmodifiable(_events);
  @override
  bool get hasLegacyCounts => _legacy.values.any((record) => record.count > 0);
  @override
  Object? get lastError => null;
  @override
  List<ShortcutUsageRecord> get records {
    final grouped = <String, ShortcutUsageRecord>{..._legacy};
    for (final event in _events) {
      final old = grouped[event.key];
      grouped[event.key] = ShortcutUsageRecord(
        key: event.key,
        label: event.label,
        count: (old?.count ?? 0) + 1,
        lastUsedAt: event.usedAt,
      );
    }
    return grouped.values.toList()..sort((a, b) => b.count.compareTo(a.count));
  }

  @override
  int countFor(String key) =>
      (_legacy[key]?.count ?? 0) +
      _events.where((event) => event.key == key).length;
  @override
  Future<void> load() async {}
  @override
  Future<void> record(
    String key,
    String label, {
    String? publicShortcutId,
  }) async {
    _events.add(
      ShortcutUsageEvent(
        id: FileShortcutUsageRepository._newEventId(),
        key: key,
        label: label,
        usedAt: DateTime.now().millisecondsSinceEpoch,
        publicShortcutId: publicShortcutId,
      ),
    );
    _events.sort((a, b) => a.usedAt.compareTo(b.usedAt));
    notifyListeners();
  }

  @override
  Future<void> clear() async {
    _events.clear();
    _legacy.clear();
    notifyListeners();
  }
}
