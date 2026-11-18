import 'dart:async';

import 'package:diagnostics_core/diagnostics_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'diagnostics_store.dart';
import 'diagnostics_uploader.dart';

enum DiagnosticChoice { undecided, localOnly, allowSharing }

class DiagnosticsService extends ChangeNotifier {
  DiagnosticsService({
    required this.metadata,
    DiagnosticsStore? store,
    DiagnosticsUploader? uploader,
    DateTime Function()? clock,
    this.maintenanceInterval = const Duration(hours: 1),
    this.retryDelays = const [
      Duration(seconds: 5),
      Duration(seconds: 30),
      Duration(minutes: 2),
    ],
  }) : store = store ?? FileDiagnosticsStore(),
       uploader = uploader ?? DiagnosticsUploader(),
       journal = ErrorJournal(metadata: metadata, clock: clock);
  final DiagnosticMetadata metadata;
  final DiagnosticsStore store;
  final DiagnosticsUploader uploader;
  final ErrorJournal journal;
  final List<Duration> retryDelays;
  final Duration maintenanceInterval;
  DiagnosticChoice choice = DiagnosticChoice.undecided;
  int epoch = 0;
  bool loaded = false, sending = false, _disposed = false;
  String? storageError, uploadError;
  final Map<String, int> _uploadedCounts = {};
  final Map<String, int> _durableCounts = {};
  int _generation = 0, _attempts = 0;
  bool _storageHealthy = true;
  Timer? _retry;
  Timer? _maintenance;
  Future<void> _writes = Future.value(), _permissions = Future.value();
  bool get sharing =>
      !_disposed &&
      loaded &&
      _storageHealthy &&
      choice == DiagnosticChoice.allowSharing &&
      metadata.verified;
  List<DiagnosticEvent> get events =>
      journal.events.reversed.toList(growable: false);
  int get retentionDays => journal.retention.inDays;
  String get status =>
      storageError ??
      (sending
          ? 'Sharing error diagnostics…'
          : uploadError ??
                (!metadata.verified
                    ? 'App version could not be verified. Errors stay on this device.'
                    : sharing
                    ? uploader.configured
                          ? 'Error sharing is allowed.'
                          : 'Sharing is unavailable. Errors stay on this device.'
                    : 'Errors are saved only on this device.'));

  static Future<DiagnosticMetadata> actualMetadata() async {
    final platform = defaultTargetPlatform == TargetPlatform.iOS
        ? DiagnosticPlatform.ios
        : DiagnosticPlatform.android;
    try {
      final info = await PackageInfo.fromPlatform();
      return DiagnosticMetadata(
        appVersion: info.version,
        appBuild: int.tryParse(info.buildNumber),
        edition: DiagnosticEdition.full,
        platform: platform,
      );
    } catch (_) {
      return DiagnosticMetadata(
        appVersion: null,
        appBuild: null,
        edition: DiagnosticEdition.full,
        platform: platform,
      );
    }
  }

  Future<void> initialize() async {
    if (loaded) return;
    var restoredJournal = false;
    try {
      final raw = await store.readConsent();
      if (raw != null) {
        if (raw is! Map ||
            raw.length != 4 ||
            raw['schemaVersion'] != 1 ||
            raw['epoch'] is! int ||
            raw['epoch'] < 0 ||
            raw['epoch'] > 2147483646 ||
            ![7, 30].contains(raw['retentionDays']) ||
            !DiagnosticChoice.values.any(
              (choice) => choice.name == raw['choice'],
            )) {
          throw const FormatException('Invalid consent');
        }
        choice = DiagnosticChoice.values.firstWhere(
          (choice) => choice.name == raw['choice'],
        );
        epoch = raw['epoch'] as int;
        journal.setRetention(Duration(days: raw['retentionDays'] as int));
      }
      if (await store.isRevoked()) choice = DiagnosticChoice.localOnly;
    } catch (_) {
      choice = DiagnosticChoice.localOnly;
      storageError =
          'Sharing preferences could not be read. Errors stay on this device.';
    }
    try {
      final raw = await store.readJournal();
      if (raw != null) {
        if (raw is! Map ||
            raw.length != 3 ||
            raw['schemaVersion'] != 1 ||
            raw['uploadedCounts'] is! Map) {
          throw const FormatException('Invalid journal store');
        }
        journal.restoreLocalJson(raw['journal']);
        final counts = raw['uploadedCounts'] as Map;
        if (counts.length > 1000 ||
            counts.entries.any(
              (entry) =>
                  entry.key is! String ||
                  !validDiagnosticId(entry.key) ||
                  entry.value is! int ||
                  entry.value < 0 ||
                  entry.value > 1000000,
            )) {
          throw const FormatException('Invalid journal acknowledgements');
        }
        _uploadedCounts.addAll(counts.cast<String, int>());
        _durableCounts.addAll(ErrorJournal.snapshotCounts(journal.events));
        restoredJournal = true;
      }
    } catch (_) {
      journal.clear();
      _storageHealthy = false;
      choice = DiagnosticChoice.localOnly;
      storageError =
          'Saved error logs could not be read. New errors remain local.';
    }
    loaded = true;
    if (restoredJournal) {
      // Expiration happens during strict restore. Remove expired disk records
      // even when the user only opens the app and creates no further errors.
      try {
        await _persist();
      } catch (_) {
        /* _persist already fails closed. */
      }
    }
    if (!_disposed && maintenanceInterval > Duration.zero) {
      _maintenance = Timer.periodic(maintenanceInterval, (_) {
        journal.prune();
        if (journal.events.length != _durableCounts.length) {
          _notify();
          unawaited(_persist().catchError((Object _) {}));
        }
      });
    }
    _notify();
    // Pending records are not uploaded at startup. A later eligible error or
    // an explicit retry can start this consent epoch's bounded queue.
  }

  void record(DiagnosticCode code) {
    if (_disposed) return;
    try {
      journal.capture(code, consentEpoch: sharing ? epoch : null);
    } catch (_) {
      return;
    }
    unawaited(_persist().then((_) => _schedule(), onError: (Object _) {}));
    _notify();
  }

  Future<void> _persist() {
    final operation = _writes.then((_) async {
      final snapshot = journal.events;
      final ids = snapshot.map((event) => event.id).toSet();
      _uploadedCounts.removeWhere((id, _) => !ids.contains(id));
      await store.writeJournal({
        'schemaVersion': 1,
        'journal': journal.toLocalJson(),
        'uploadedCounts': Map<String, int>.from(_uploadedCounts),
      });
      _durableCounts
        ..clear()
        ..addAll(ErrorJournal.snapshotCounts(snapshot));
    });
    _writes = operation.catchError((Object _) {
      _storageHealthy = false;
      _cancel();
      storageError =
          'Error logs could not be saved. Sharing is off for this session.';
      _notify();
    });
    return operation;
  }

  Map<String, Object?> _consent(DiagnosticChoice value, int newEpoch) => {
    'schemaVersion': 1,
    'choice': value.name,
    'epoch': newEpoch,
    'retentionDays': retentionDays,
  };
  void _cancel() {
    _generation++;
    _retry?.cancel();
    _retry = null;
    uploader.cancel();
    sending = false;
  }

  Future<bool> setSharing(bool allow) async {
    _cancel();
    final generation = _generation;
    choice = DiagnosticChoice.localOnly;
    _notify();
    var result = false;
    final operation = _permissions.then((_) async {
      if (generation != _generation) return;
      final newEpoch = epoch + 1;
      try {
        if (allow && !metadata.verified) {
          uploadError = 'App version is unavailable. Sharing remains off.';
          return;
        }
        var durableRevoke = false;
        if (allow) {
          // Keep a durable deny marker until the entire grant transaction has
          // saved both its new epoch and a usable journal.
          await store.markRevoked();
        }
        if (!allow) {
          try {
            await store.markRevoked();
            durableRevoke = true;
          } catch (_) {
            /* Try the independent consent record. */
          }
        }
        final newChoice = allow
            ? DiagnosticChoice.allowSharing
            : DiagnosticChoice.localOnly;
        try {
          await store.writeConsent(_consent(newChoice, newEpoch));
        } catch (_) {
          if (!allow && durableRevoke) {
            if (generation == _generation) {
              epoch = newEpoch;
              storageError =
                  'Sharing is off and the revocation is saved. Other preferences could not be saved.';
              result = true;
            }
            return;
          }
          rethrow;
        }
        if (generation != _generation) return;
        if (allow) {
          await _persist();
          if (generation != _generation) return;
          await store.clearRevocation();
        }
        if (generation != _generation) return;
        epoch = newEpoch;
        choice = newChoice;
        _storageHealthy = true;
        storageError = null;
        uploadError = null;
        _attempts = 0;
        result = true;
      } catch (_) {
        choice = DiagnosticChoice.localOnly;
        storageError =
            'Your choice could not be saved. Sharing is off for this session.';
      }
    });
    _permissions = operation.catchError((Object _) {});
    await operation;
    _notify();
    return result;
  }

  Future<void> setRetentionDays(int days) async {
    if (![7, 30].contains(days)) return;
    _cancel();
    final generation = _generation;
    final operation = _permissions.then((_) async {
      if (generation != _generation) return;
      journal.setRetention(Duration(days: days));
      try {
        await store.writeConsent(_consent(choice, epoch));
        await _persist();
      } catch (_) {
        storageError =
            'Retention settings could not be saved. Sharing is off for this session.';
        _storageHealthy = false;
      }
    });
    _permissions = operation.catchError((Object _) {});
    await operation;
    _notify();
  }

  Future<void> clear() async {
    final wasSharing = sharing;
    _cancel();
    final generation = _generation;
    choice = DiagnosticChoice.localOnly;
    final operation = _permissions.then((_) async {
      if (generation != _generation) return;
      epoch++;
      try {
        await store.markRevoked();
        await store.writeConsent(
          _consent(wasSharing ? DiagnosticChoice.allowSharing : choice, epoch),
        );
        journal.clear();
        _uploadedCounts.clear();
        _durableCounts.clear();
        await _persist();
        if (generation != _generation) return;
        if (wasSharing) {
          await store.clearRevocation();
          if (generation == _generation) choice = DiagnosticChoice.allowSharing;
        }
      } catch (_) {
        storageError =
            'Logs could not be fully cleared. Sharing is off for this session.';
      }
    });
    _permissions = operation.catchError((Object _) {});
    await operation;
    _notify();
  }

  void _schedule() {
    if (!sharing ||
        !uploader.configured ||
        sending ||
        _retry != null ||
        _attempts > retryDelays.length) {
      return;
    }
    _retry = Timer(Duration.zero, () {
      _retry = null;
      unawaited(flush());
    });
  }

  Future<void> retrySharing() async {
    _attempts = 0;
    _retry?.cancel();
    _retry = null;
    await flush();
  }

  Future<void> flush() async {
    final waitingGeneration = _generation;
    await _writes;
    if (waitingGeneration != _generation) return;
    if (!sharing ||
        !uploader.configured ||
        sending ||
        _attempts > retryDelays.length) {
      return;
    }
    final batch = journal
        .pendingForEpoch(epoch, _uploadedCounts)
        .where((event) => _durableCounts[event.id] == event.repeatCount)
        .toList(growable: false);
    if (batch.isEmpty) return;
    final generation = _generation, activeEpoch = epoch;
    final counts = ErrorJournal.snapshotCounts(batch);
    sending = true;
    _notify();
    try {
      final accepted = await uploader.send(batch);
      if (generation != _generation || !sharing || epoch != activeEpoch) return;
      for (final id in accepted) {
        _uploadedCounts[id] = counts[id]!;
      }
      uploadError = null;
      _attempts = 0;
      await _persist();
    } catch (_) {
      if (generation != _generation || !sharing) return;
      uploadError = 'Sharing could not finish. Errors are kept on this device.';
      if (_attempts < retryDelays.length) {
        final delay = retryDelays[_attempts++];
        _retry = Timer(delay, () {
          _retry = null;
          unawaited(flush());
        });
      } else {
        _attempts = retryDelays.length + 1;
      }
    } finally {
      if (generation == _generation) {
        sending = false;
        _notify();
      }
    }
    if (generation == _generation && uploadError == null) _schedule();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _maintenance?.cancel();
    _cancel();
    super.dispose();
  }
}

class DiagnosticsScope extends InheritedNotifier<DiagnosticsService> {
  const DiagnosticsScope({
    super.key,
    required DiagnosticsService diagnostics,
    required super.child,
  }) : super(notifier: diagnostics);
  static DiagnosticsService? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DiagnosticsScope>()?.notifier;
}
