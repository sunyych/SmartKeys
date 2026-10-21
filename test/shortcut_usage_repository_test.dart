import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'package:smart_keys/data/shortcut_usage_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'usage counters persist only in their private phone storage key',
    () async {
      SharedPreferences.setMockInitialValues({});
      final repository = SharedPreferencesShortcutUsageRepository();
      await repository.load();
      await repository.record('local:general:copy', 'General · Copy');
      await repository.record('local:general:copy', 'General · Copy');

      final restored = SharedPreferencesShortcutUsageRepository();
      await restored.load();
      final preferences = await SharedPreferences.getInstance();

      expect(restored.countFor('local:general:copy'), 2);
      expect(preferences.getKeys(), {
        SharedPreferencesShortcutUsageRepository.storageKey,
      });

      await restored.clear();
      expect(restored.records, isEmpty);
      expect(preferences.getKeys(), isEmpty);
    },
  );

  test(
    'file journal recovers complete records and drops a partial final line',
    () async {
      final directory = await Directory.systemTemp.createTemp('usage_journal_');
      addTearDown(() => directory.delete(recursive: true));
      final first = FileShortcutUsageRepository(
        directoryProvider: () async => directory,
      );
      await first.load();
      await first.record('one', 'One');
      await first.record('two', 'Two');
      await first.flush();
      final journal = File(
        '${directory.path}${Platform.pathSeparator}events.jsonl',
      );
      await journal.writeAsString('{"partial":', mode: FileMode.append);

      final restored = FileShortcutUsageRepository(
        directoryProvider: () async => directory,
      );
      await restored.load();
      expect(restored.events, hasLength(2));
      expect(restored.events.map((event) => event.id).toSet(), hasLength(2));
      expect(
        restored.events,
        orderedEquals(
          [...restored.events]..sort((a, b) => a.usedAt.compareTo(b.usedAt)),
        ),
      );
      expect((await journal.readAsString()).endsWith('\n'), isTrue);
    },
  );

  test('legacy counts migrate without creating dated click events', () async {
    final directory = await Directory.systemTemp.createTemp('usage_migration_');
    addTearDown(() => directory.delete(recursive: true));
    SharedPreferences.setMockInitialValues({
      FileShortcutUsageRepository.legacyStorageKey:
          '[{"key":"old","label":"Old","count":4,"lastUsedAt":123}]',
    });
    final repository = FileShortcutUsageRepository(
      directoryProvider: () async => directory,
    );
    await repository.load();
    final preferences = await SharedPreferences.getInstance();
    expect(repository.countFor('old'), 4);
    expect(repository.hasLegacyCounts, isTrue);
    expect(repository.events, isEmpty);
    expect(repository.recordsForPeriod(), isEmpty);
    expect(
      preferences.getString(FileShortcutUsageRepository.legacyStorageKey),
      isNull,
    );
  });

  test(
    'period includes start and excludes end, and clear follows queued writes',
    () async {
      final directory = await Directory.systemTemp.createTemp('usage_period_');
      addTearDown(() => directory.delete(recursive: true));
      final repository = FileShortcutUsageRepository(
        directoryProvider: () async => directory,
      );
      await repository.load();
      await repository.record('key', 'Key');
      final start = DateTime.fromMillisecondsSinceEpoch(
        repository.events.single.usedAt,
      );
      while (DateTime.now().millisecondsSinceEpoch <=
          start.millisecondsSinceEpoch) {}
      await repository.record('key', 'Key');
      final end = DateTime.fromMillisecondsSinceEpoch(
        repository.events.last.usedAt,
      );
      expect(
        repository.recordsForPeriod(start: start, end: end).single.count,
        1,
      );
      final writes = List.generate(
        20,
        (index) => repository.record('key$index', 'Key $index'),
      );
      final clearing = repository.clear();
      await Future.wait([...writes, clearing]);
      await repository.flush();
      expect(repository.records, isEmpty);
      final restored = FileShortcutUsageRepository(
        directoryProvider: () async => directory,
      );
      await restored.load();
      expect(restored.records, isEmpty);
    },
  );

  test(
    'interrupted clear marker retains only later complete journal rows',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'usage_clear_recovery_',
      );
      addTearDown(() => directory.delete(recursive: true));
      final repository = FileShortcutUsageRepository(
        directoryProvider: () async => directory,
      );
      await repository.load();
      await repository.record('before', 'Before');
      final journal = File(
        '${directory.path}${Platform.pathSeparator}events.jsonl',
      );
      final clearOffset = await journal.length();
      await repository.record('after', 'After');
      await File(
        '${directory.path}${Platform.pathSeparator}clear.marker',
      ).writeAsString('$clearOffset');

      final restored = FileShortcutUsageRepository(
        directoryProvider: () async => directory,
      );
      await restored.load();
      expect(restored.events.map((event) => event.key), ['after']);
      expect(
        await File(
          '${directory.path}${Platform.pathSeparator}clear.marker',
        ).exists(),
        isFalse,
      );
    },
  );

  test(
    'clear reports disk failure and preserves recoverable counters',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'usage_clear_failure_',
      );
      addTearDown(() => directory.delete(recursive: true));
      final repository = FileShortcutUsageRepository(
        directoryProvider: () async => directory,
      );
      await repository.load();
      await repository.record('keep', 'Keep');
      await Directory(
        '${directory.path}${Platform.pathSeparator}clear.marker.next',
      ).create();

      await expectLater(repository.clear(), throwsA(anything));
      expect(repository.lastError, isNotNull);
      expect(repository.countFor('keep'), 1);
      final restored = FileShortcutUsageRepository(
        directoryProvider: () async => directory,
      );
      await restored.load();
      expect(restored.countFor('keep'), 1);
    },
  );

  test('clearing an empty repository is idempotent across restart', () async {
    final directory = await Directory.systemTemp.createTemp(
      'usage_empty_clear_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final repository = FileShortcutUsageRepository(
      directoryProvider: () async => directory,
    );
    await repository.load();
    await repository.clear();
    final restored = FileShortcutUsageRepository(
      directoryProvider: () async => directory,
    );
    await restored.load();
    expect(restored.events, isEmpty);
    expect(restored.records, isEmpty);
    await restored.clear();
  });
}
