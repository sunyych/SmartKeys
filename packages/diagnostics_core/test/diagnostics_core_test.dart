import 'dart:convert';
import 'package:diagnostics_core/diagnostics_core.dart';
import 'package:test/test.dart';

DiagnosticMetadata meta({
  String? version = '1.6.0',
  int? build = 8,
  DiagnosticEdition edition = DiagnosticEdition.full,
}) => DiagnosticMetadata(
  appVersion: version,
  appBuild: build,
  edition: edition,
  platform: DiagnosticPlatform.android,
);
void main() {
  var now = DateTime.utc(2026, 11, 17);
  setUp(() => now = DateTime.utc(2026, 11, 17));
  test('fixed registry exposes only safe diagnostic descriptions', () {
    expect(DiagnosticCode.values.length, 20);
    final journal = ErrorJournal(metadata: meta(), clock: () => now);
    final hostile = StateError(
      'Bearer private-token C:/Users/person/secret CTRL+C clipboard 192.168.1.4 transcript',
    );
    expect(hostile, isA<StateError>());
    journal.capture(DiagnosticCode.shortcutDeliveryFailed);
    final raw = jsonEncode(journal.toLocalJson());
    for (final value in [
      'private-token',
      'C:/Users',
      'CTRL+C',
      'clipboard',
      '192.168',
      'transcript',
    ]) {
      expect(raw, isNot(contains(value)));
    }
    expect(journal.events.single.message, 'A shortcut could not be delivered.');
  });
  test(
    'metadata rejects free text and permits explicit unverified local records',
    () {
      expect(() => meta(version: 'Bearer secret'), throwsFormatException);
      expect(() => meta(build: -1), throwsFormatException);
      expect(() => meta(version: null), throwsFormatException);
      final journal = ErrorJournal(
        metadata: meta(version: null, build: null),
        clock: () => now,
      );
      journal.capture(DiagnosticCode.runtimeFailure, consentEpoch: 1);
      expect(journal.events.single.metadata.verified, isFalse);
      expect(() => journal.events.single.toUploadJson(), throwsStateError);
      expect(journal.pendingForEpoch(1, {}), isEmpty);
    },
  );
  test(
    'fresh UUIDs and immutable count snapshots prevent lost inflight increments',
    () {
      final journal = ErrorJournal(metadata: meta(), clock: () => now);
      journal.capture(DiagnosticCode.connectionTimeout, consentEpoch: 2);
      final snapshot = journal.pendingForEpoch(2, {});
      expect(validDiagnosticId(snapshot.single.id), isTrue);
      journal.capture(DiagnosticCode.connectionTimeout, consentEpoch: 2);
      final acknowledged = ErrorJournal.snapshotCounts(snapshot);
      expect(snapshot.single.repeatCount, 1);
      expect(journal.pendingForEpoch(2, acknowledged).single.repeatCount, 2);
      expect(
        journal.events.single.toUploadJson().containsKey('consentEpoch'),
        isFalse,
      );
      expect(() => journal.events.clear(), throwsUnsupportedError);
    },
  );
  test(
    'deduplication never crosses epochs or the five-minute first-event window',
    () {
      final journal = ErrorJournal(metadata: meta(), clock: () => now);
      journal.capture(DiagnosticCode.runtimeFailure);
      journal.capture(DiagnosticCode.runtimeFailure, consentEpoch: 1);
      journal.capture(DiagnosticCode.runtimeFailure, consentEpoch: 2);
      expect(journal.events.length, 3);
      now = now.add(const Duration(minutes: 4));
      journal.capture(DiagnosticCode.runtimeFailure, consentEpoch: 2);
      expect(journal.events.last.repeatCount, 2);
      now = now.add(const Duration(minutes: 2));
      journal.capture(DiagnosticCode.runtimeFailure, consentEpoch: 2);
      expect(journal.events.length, 4);
      expect(journal.pendingForEpoch(3, {}), isEmpty);
    },
  );
  test('strict restoration is atomic and rejects hostile extra fields', () {
    final journal = ErrorJournal(metadata: meta(), clock: () => now)
      ..capture(DiagnosticCode.iconDataInvalid);
    final original = jsonEncode(journal.toLocalJson());
    final raw = jsonDecode(original) as Map<String, dynamic>;
    (raw['events'] as List).single['message'] = 'token CTRL+C /private/path';
    expect(() => journal.restoreLocalJson(raw), throwsFormatException);
    expect(jsonEncode(journal.toLocalJson()), original);
    final restored = ErrorJournal(metadata: meta(), clock: () => now)
      ..restoreLocalJson(jsonDecode(original));
    expect(jsonEncode(restored.toLocalJson()), original);
    for (final field in ['id', 'code', 'appVersion', 'platform']) {
      final poisoned = jsonDecode(original) as Map<String, dynamic>;
      (poisoned['events'] as List).single[field] = 'Bearer token /private/path';
      expect(() => restored.restoreLocalJson(poisoned), throwsFormatException);
    }
  });
  test('count, byte and retention limits evict oldest records', () {
    final journal = ErrorJournal(
      metadata: meta(),
      clock: () => now,
      maxEntries: 2,
    );
    for (final code in DiagnosticCode.values.take(3)) {
      journal.capture(code);
      now = now.add(const Duration(seconds: 1));
    }
    expect(journal.events.length, 2);
    expect(journal.events.first.code, DiagnosticCode.connectionTimeout);
    now = now.add(const Duration(days: 8));
    journal.setRetention(const Duration(days: 7));
    expect(journal.events, isEmpty);
    final bytes = ErrorJournal(
      metadata: meta(),
      clock: () => now,
      maxBytes: 500,
    );
    for (final code in DiagnosticCode.values) {
      bytes.capture(code);
    }
    expect(
      utf8.encode(jsonEncode(bytes.toLocalJson())).length,
      lessThanOrEqualTo(500),
    );
    expect(
      () => ErrorJournal(metadata: meta(), maxEntries: 1001),
      throwsArgumentError,
    );
    expect(
      () => ErrorJournal(metadata: meta(), maxBytes: 5 * 1024 * 1024 + 1),
      throwsArgumentError,
    );
    expect(
      () => ErrorJournal(metadata: meta(), retention: const Duration(days: 31)),
      throwsArgumentError,
    );
  });
  test('reads and pending snapshots expire records without new captures', () {
    final view = ErrorJournal(metadata: meta(), clock: () => now)
      ..capture(DiagnosticCode.runtimeFailure, consentEpoch: 1);
    final upload = ErrorJournal(metadata: meta(), clock: () => now)
      ..capture(DiagnosticCode.runtimeFailure, consentEpoch: 1);
    now = now.add(const Duration(days: 31));
    expect(view.events, isEmpty);
    expect(upload.pendingForEpoch(1, {}), isEmpty);
    expect((upload.toLocalJson()['events'] as List), isEmpty);
  });
  test('Lite records never serialize for upload', () {
    final journal = ErrorJournal(
      metadata: meta(edition: DiagnosticEdition.lite),
      clock: () => now,
    )..capture(DiagnosticCode.bluetoothInputFailed);
    expect(() => journal.events.single.toUploadJson(), throwsStateError);
    expect(journal.pendingForEpoch(1, {}), isEmpty);
  });
}
