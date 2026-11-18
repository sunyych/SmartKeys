import 'dart:async';
import 'dart:convert';
import 'package:diagnostics_core/diagnostics_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Local persistence only. This class has no transport or sharing entry point.
class LiteDiagnostics extends ChangeNotifier {
  LiteDiagnostics({
    this.preferences,
    this.metadataLoader,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;
  final DateTime Function() _clock;
  final Future<SharedPreferences> Function()? preferences;
  final Future<Map<Object?, Object?>?> Function()? metadataLoader;
  static const storageKey = 'lite.errorDiagnostics.v1';
  static const channel = MethodChannel('smart_keys/hid');
  ErrorJournal _journal = ErrorJournal(
    metadata: DiagnosticMetadata(
      appVersion: null,
      appBuild: null,
      edition: DiagnosticEdition.lite,
      platform: DiagnosticPlatform.android,
    ),
  );
  ErrorJournal get journal => _journal;
  bool storageFailed = false;
  Future<void> get settled => _queue;
  Future<void>? _ready;
  Future<void> _queue = Future.value();
  bool _disposed = false;
  Timer? _cleanupTimer;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<SharedPreferences> _prefs() =>
      preferences?.call() ?? SharedPreferences.getInstance();
  Future<void> initialize() => _ready ??= _initialize();
  Future<void> _initialize() async {
    DiagnosticMetadata metadata = _journal.metadata;
    try {
      final raw =
          await (metadataLoader?.call() ??
              channel.invokeMapMethod<Object?, Object?>('getAppMetadata'));
      final version = raw?['appVersion'], build = raw?['appBuild'];
      if (version is String && build is int) {
        metadata = DiagnosticMetadata(
          appVersion: version,
          appBuild: build,
          edition: DiagnosticEdition.lite,
          platform: DiagnosticPlatform.android,
        );
      }
    } catch (_) {
      /* Unverified metadata remains local and is shown accurately. */
    }
    _journal = ErrorJournal(metadata: metadata, clock: _clock);
    try {
      final stored = (await _prefs()).getString(storageKey);
      if (stored != null) {
        if (utf8.encode(stored).length > 5 * 1024 * 1024 + 1024) {
          throw const FormatException('Invalid local diagnostics.');
        }
        final raw = jsonDecode(stored);
        if (raw is! Map ||
            raw.length != 2 ||
            raw['retentionDays'] is! int ||
            ![7, 30].contains(raw['retentionDays'])) {
          throw const FormatException('Invalid local diagnostics.');
        }
        _journal.restoreLocalJson(raw['journal']);
        _journal.setRetention(Duration(days: raw['retentionDays'] as int));
        // Persist expiry immediately; do not await _mutate while initializing.
        await _persistSnapshot();
      }
    } catch (_) {
      storageFailed = true;
    }
    if (!_disposed) {
      _cleanupTimer = Timer.periodic(const Duration(hours: 1), (_) {
        unawaited(pruneExpired());
      });
    }
    _notify();
  }

  Future<void> _persistSnapshot() async {
    try {
      final saved = await (await _prefs()).setString(
        storageKey,
        jsonEncode({
          'retentionDays': _journal.retention.inDays,
          'journal': _journal.toLocalJson(),
        }),
      );
      if (!saved) throw StateError('Local diagnostic persistence failed.');
      storageFailed = false;
    } catch (_) {
      storageFailed = true;
    }
  }

  Future<void> _mutate(void Function() change) {
    final operation = _queue.then((_) async {
      await initialize();
      change();
      _notify();
      await _persistSnapshot();
      _notify();
    });
    _queue = operation.catchError((Object _) {});
    return _queue;
  }

  Future<void> capture(DiagnosticCode code) =>
      _mutate(() => _journal.capture(code));
  Future<void> clear() => _mutate(() => _journal.clear());
  Future<void> pruneExpired() => _mutate(() => _journal.prune());
  Future<void> setRetentionDays(int days) {
    if (![7, 30].contains(days)) {
      throw ArgumentError('Invalid local retention.');
    }
    return _mutate(() => _journal.setRetention(Duration(days: days)));
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _cleanupTimer?.cancel();
    super.dispose();
  }
}
