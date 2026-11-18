import 'dart:convert';
import 'dart:math';

/// This registry is the only capture vocabulary. No caller-controlled text.
enum DiagnosticCode {
  connectionUnavailable,
  connectionTimeout,
  connectionAuthenticationFailed,
  connectionProtocolInvalid,
  applicationActivationFailed,
  shortcutDeliveryFailed,
  pointerDeliveryFailed,
  iconDownloadFailed,
  iconDataInvalid,
  configurationLoadFailed,
  configurationInvalid,
  configurationSaveFailed,
  storageReadFailed,
  storageWriteFailed,
  bluetoothUnavailable,
  bluetoothPermissionDenied,
  bluetoothConnectionFailed,
  bluetoothInputFailed,
  platformUnavailable,
  runtimeFailure;

  String get module => switch (this) {
    connectionUnavailable ||
    connectionTimeout ||
    connectionAuthenticationFailed ||
    connectionProtocolInvalid => 'connection',
    applicationActivationFailed => 'application',
    shortcutDeliveryFailed || pointerDeliveryFailed => 'input',
    iconDownloadFailed || iconDataInvalid => 'icons',
    configurationLoadFailed ||
    configurationInvalid ||
    configurationSaveFailed => 'configuration',
    storageReadFailed || storageWriteFailed => 'storage',
    bluetoothUnavailable ||
    bluetoothPermissionDenied ||
    bluetoothConnectionFailed ||
    bluetoothInputFailed => 'bluetooth',
    platformUnavailable || runtimeFailure => 'runtime',
  };
  String get trigger => switch (this) {
    connectionUnavailable ||
    connectionTimeout ||
    bluetoothConnectionFailed => 'connect',
    connectionAuthenticationFailed => 'authenticate',
    connectionProtocolInvalid => 'synchronize',
    applicationActivationFailed => 'activate',
    shortcutDeliveryFailed ||
    pointerDeliveryFailed ||
    bluetoothInputFailed => 'deliver',
    iconDownloadFailed => 'download',
    iconDataInvalid || configurationInvalid => 'validate',
    configurationLoadFailed || storageReadFailed => 'load',
    configurationSaveFailed || storageWriteFailed => 'save',
    bluetoothUnavailable || platformUnavailable => 'initialize',
    bluetoothPermissionDenied => 'permission',
    runtimeFailure => 'unhandled',
  };
  String get severity => this == iconDownloadFailed || this == iconDataInvalid
      ? 'warning'
      : 'error';
  String get message => const [
    'The connection is unavailable.',
    'The connection timed out.',
    'Connection authentication failed.',
    'The connection response was invalid.',
    'The application could not be activated.',
    'A shortcut could not be delivered.',
    'Pointer input could not be delivered.',
    'An application icon could not be downloaded.',
    'Application icon data was invalid.',
    'Configuration could not be loaded.',
    'Configuration data was invalid.',
    'Configuration could not be saved.',
    'Local data could not be read.',
    'Local data could not be saved.',
    'Bluetooth is unavailable.',
    'Bluetooth permission was not granted.',
    'The Bluetooth connection failed.',
    'Bluetooth input could not be delivered.',
    'A platform service is unavailable.',
    'An application error occurred.',
  ][index];
}

enum DiagnosticEdition { full, lite }

enum DiagnosticPlatform { android, ios }

final class DiagnosticMetadata {
  DiagnosticMetadata({
    required this.appVersion,
    required this.appBuild,
    required this.edition,
    required this.platform,
  }) {
    if ((appVersion == null) != (appBuild == null) ||
        appVersion != null &&
            !RegExp(r'^\d{1,3}\.\d{1,3}\.\d{1,3}$').hasMatch(appVersion!) ||
        appBuild != null && (appBuild! < 0 || appBuild! > 1000000000)) {
      throw const FormatException('Invalid diagnostic metadata.');
    }
  }
  final String? appVersion;
  final int? appBuild;
  final DiagnosticEdition edition;
  final DiagnosticPlatform platform;
  bool get verified => appVersion != null && appBuild != null;
  bool sameAs(DiagnosticMetadata other) =>
      appVersion == other.appVersion &&
      appBuild == other.appBuild &&
      edition == other.edition &&
      platform == other.platform;
  Map<String, Object?> toJson() => {
    'appVersion': appVersion,
    'appBuild': appBuild,
    'edition': edition.name,
    'platform': platform.name,
  };
}

bool validDiagnosticId(String id) => RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
).hasMatch(id);
String newDiagnosticId() {
  final random = Random.secure();
  final bytes = List.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

final class DiagnosticEvent {
  const DiagnosticEvent._(
    this.id,
    this.occurredAtMs,
    this.lastOccurredAtMs,
    this.metadata,
    this.code,
    this.repeatCount,
    this.consentEpoch,
  );
  final String id;
  final int occurredAtMs, lastOccurredAtMs, repeatCount;
  final DiagnosticMetadata metadata;
  final DiagnosticCode code;

  /// Local eligibility only; this field is never part of upload serialization.
  final int? consentEpoch;
  DateTime get occurredAt =>
      DateTime.fromMillisecondsSinceEpoch(occurredAtMs, isUtc: true);
  DateTime get lastOccurredAt =>
      DateTime.fromMillisecondsSinceEpoch(lastOccurredAtMs, isUtc: true);
  String get module => code.module;
  String get trigger => code.trigger;
  String get severity => code.severity;
  String get message => code.message;
  Map<String, Object?> _base() => {
    'id': id,
    'occurredAtMs': occurredAtMs,
    'lastOccurredAtMs': lastOccurredAtMs,
    ...metadata.toJson(),
    'code': code.name,
    'repeatCount': repeatCount,
  };
  Map<String, Object?> toLocalJson() => {
    ..._base(),
    'consentEpoch': consentEpoch,
  };
  Map<String, Object?> toUploadJson() {
    if (!metadata.verified || metadata.edition != DiagnosticEdition.full) {
      throw StateError('This local diagnostic is not eligible for sharing.');
    }
    return _base();
  }

  factory DiagnosticEvent.fromLocalJson(Object? raw) {
    const keys = {
      'id',
      'occurredAtMs',
      'lastOccurredAtMs',
      'appVersion',
      'appBuild',
      'edition',
      'platform',
      'code',
      'repeatCount',
      'consentEpoch',
    };
    if (raw is! Map ||
        raw.length != keys.length ||
        raw.keys.any((key) => !keys.contains(key))) {
      throw const FormatException('Invalid diagnostic event fields.');
    }
    final id = raw['id'],
        first = raw['occurredAtMs'],
        last = raw['lastOccurredAtMs'],
        count = raw['repeatCount'],
        epoch = raw['consentEpoch'];
    if (id is! String ||
        !validDiagnosticId(id) ||
        first is! int ||
        first < 0 ||
        last is! int ||
        last < first ||
        last > 8640000000000000 ||
        count is! int ||
        count < 1 ||
        count > 1000000 ||
        epoch != null && (epoch is! int || epoch < 0 || epoch > 2147483647) ||
        raw['appVersion'] != null && raw['appVersion'] is! String ||
        raw['appBuild'] != null && raw['appBuild'] is! int) {
      throw const FormatException('Invalid diagnostic event.');
    }
    T fixed<T extends Enum>(List<T> values, Object? value) {
      for (final entry in values) {
        if (entry.name == value) return entry;
      }
      throw const FormatException('Invalid diagnostic classification.');
    }

    final metadata = DiagnosticMetadata(
      appVersion: raw['appVersion'] as String?,
      appBuild: raw['appBuild'] as int?,
      edition: fixed(DiagnosticEdition.values, raw['edition']),
      platform: fixed(DiagnosticPlatform.values, raw['platform']),
    );
    return DiagnosticEvent._(
      id,
      first,
      last,
      metadata,
      fixed(DiagnosticCode.values, raw['code']),
      count,
      epoch as int?,
    );
  }
}

/// In-memory policy only. Hosts own serialized/atomic persistence and consent.
final class ErrorJournal {
  ErrorJournal({
    required this.metadata,
    DateTime Function()? clock,
    String Function()? idFactory,
    Duration retention = const Duration(days: 30),
    this.maxEntries = 1000,
    this.maxBytes = 5 * 1024 * 1024,
  }) : _clock = clock ?? DateTime.now,
       _idFactory = idFactory ?? newDiagnosticId,
       _retention = retention {
    if (maxEntries < 1 ||
        maxEntries > 1000 ||
        maxBytes < 1 ||
        maxBytes > 5 * 1024 * 1024) {
      throw ArgumentError('Diagnostic capacity exceeds hard limits.');
    }
    _validateRetention(retention);
  }
  final DiagnosticMetadata metadata;
  final DateTime Function() _clock;
  final String Function() _idFactory;
  final int maxEntries, maxBytes;
  Duration _retention;
  final List<DiagnosticEvent> _events = [];
  List<DiagnosticEvent> get events {
    prune();
    return List.unmodifiable(_events);
  }

  Duration get retention => _retention;
  void setRetention(Duration value) {
    _validateRetention(value);
    _retention = value;
    prune();
  }

  static void _validateRetention(Duration value) {
    if (value <= Duration.zero || value > const Duration(days: 30)) {
      throw ArgumentError('Invalid diagnostic retention.');
    }
  }

  void capture(DiagnosticCode code, {int? consentEpoch}) {
    if (consentEpoch != null &&
        (consentEpoch < 0 || consentEpoch > 2147483647)) {
      throw ArgumentError('Invalid local epoch.');
    }
    prune();
    final now = _clock().toUtc().millisecondsSinceEpoch;
    final index = _events.lastIndexWhere(
      (e) =>
          e.code == code &&
          e.metadata.sameAs(metadata) &&
          e.consentEpoch == consentEpoch &&
          now >= e.lastOccurredAtMs &&
          now - e.occurredAtMs <= const Duration(minutes: 5).inMilliseconds &&
          e.repeatCount < 1000000,
    );
    if (index >= 0) {
      final old = _events.removeAt(index);
      _events.add(
        DiagnosticEvent._(
          old.id,
          old.occurredAtMs,
          now,
          metadata,
          code,
          old.repeatCount + 1,
          consentEpoch,
        ),
      );
    } else {
      final id = _idFactory();
      if (!validDiagnosticId(id) || _events.any((e) => e.id == id)) {
        throw StateError('Invalid diagnostic ID factory.');
      }
      _events.add(
        DiagnosticEvent._(id, now, now, metadata, code, 1, consentEpoch),
      );
    }
    prune();
  }

  void clear() => _events.clear();
  void prune() {
    final now = _clock().toUtc().millisecondsSinceEpoch;
    _events.removeWhere(
      (e) =>
          e.lastOccurredAtMs < now - _retention.inMilliseconds ||
          e.lastOccurredAtMs > now + const Duration(minutes: 5).inMilliseconds,
    );
    _events.sort((a, b) => a.lastOccurredAtMs.compareTo(b.lastOccurredAtMs));
    while (_events.length > maxEntries ||
        _events.isNotEmpty &&
            utf8.encode(jsonEncode(toLocalJson())).length > maxBytes) {
      _events.removeAt(0);
    }
  }

  Map<String, Object?> toLocalJson() => {
    'schemaVersion': 1,
    'events': _events.map((e) => e.toLocalJson()).toList(),
  };
  void restoreLocalJson(Object? raw) {
    if (raw is! Map ||
        raw.length != 2 ||
        raw['schemaVersion'] != 1 ||
        !raw.containsKey('events') ||
        raw['events'] is! List ||
        (raw['events'] as List).length > 1000 ||
        utf8.encode(jsonEncode(raw)).length > 5 * 1024 * 1024) {
      throw const FormatException('Invalid diagnostic journal.');
    }
    final parsed = (raw['events'] as List)
        .map(DiagnosticEvent.fromLocalJson)
        .toList();
    if (parsed.map((e) => e.id).toSet().length != parsed.length) {
      throw const FormatException('Duplicate diagnostic IDs.');
    }
    _events
      ..clear()
      ..addAll(parsed);
    prune();
  }

  List<DiagnosticEvent> pendingForEpoch(
    int epoch,
    Map<String, int> uploadedCounts, {
    int limit = 20,
  }) {
    prune();
    return List.unmodifiable(
      _events
          .where(
            (e) =>
                e.consentEpoch == epoch &&
                e.metadata.verified &&
                e.metadata.edition == DiagnosticEdition.full &&
                e.repeatCount > (uploadedCounts[e.id] ?? 0),
          )
          .take(limit.clamp(0, 20)),
    );
  }

  static Map<String, int> snapshotCounts(Iterable<DiagnosticEvent> events) => {
    for (final e in events) e.id: e.repeatCount,
  };
}
