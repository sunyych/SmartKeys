import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumiakeys_companion/installed_app_registry.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Preferences implements SharedPreferencesAsync {
  final _values = <String, String>{};
  String? get value => _values['value'];
  @override
  Future<String?> getString(String key) async => value;
  @override
  Future<void> setString(String key, String value) async =>
      _values['value'] = value;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

InstalledLaunchTarget entry(
  String identity, {
  String name = 'Example App',
  bool manual = false,
}) => InstalledLaunchTarget.discovered(
  name: name,
  kind: InstalledLaunchKind.linuxDesktopEntry,
  identity: identity,
  locator: '/usr/share/applications/$identity.desktop',
  manual: manual,
);

void main() {
  test(
    'oversize manual saves leave the durable registry readable after restart',
    () async {
      final preferences = _Preferences();
      final store = SharedPreferencesInstalledRegistryStore(
        preferences: preferences,
      );
      final original = entry('saved', manual: true);
      await store.save([original]);
      final savedBytes = preferences.value;
      final large = List.generate(
        1000,
        (index) => InstalledLaunchTarget.discovered(
          name: 'Local $index',
          kind: InstalledLaunchKind.linuxDesktopEntry,
          identity: 'manual-$index',
          locator: '/${List.filled(3000, '应').join()}/$index.desktop',
          manual: true,
        ),
      );
      await expectLater(store.save(large), throwsFormatException);
      await expectLater(
        store.save(List.filled(1001, original)),
        throwsFormatException,
      );
      expect(preferences.value, savedBytes);
      final restarted = InstalledAppRegistry(
        store: SharedPreferencesInstalledRegistryStore(
          preferences: preferences,
        ),
        validate: (_) async => true,
      );
      await restarted.initialize();
      expect(restarted.resolve(original.id), isNotNull);
    },
  );
  test(
    'a transient manual-store read error can be retried without erasing saved applications',
    () async {
      final saved = entry('manual', manual: true);
      final store = MemoryInstalledRegistryStore()
        ..value = [saved]
        ..failRead = true;
      final registry = InstalledAppRegistry(
        store: store,
        validate: (_) async => true,
      );
      await expectLater(registry.initialize(), throwsStateError);
      store.failRead = false;
      await registry.refresh(force: true);
      expect(registry.resolve(saved.id), isNotNull);
      expect(store.value.single.id, saved.id);
    },
  );

  test(
    'blocked validation times out without late publication or unsaved manual registration',
    () async {
      final late = Completer<bool>();
      final item = entry('blocked');
      final registry = InstalledAppRegistry(
        discover: () async => [item],
        validate: (_) => late.future,
        validationTimeout: const Duration(milliseconds: 10),
        scanTimeout: const Duration(milliseconds: 200),
      );
      await registry.refresh();
      expect(registry.resolve(item.id), isNull);
      late.complete(true);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(registry.resolve(item.id), isNull);
      final second = Completer<bool>();
      final store = MemoryInstalledRegistryStore();
      final manual = entry('manual', manual: true);
      final pending = InstalledAppRegistry(
        store: store,
        validate: (_) => second.future,
        validationTimeout: const Duration(milliseconds: 10),
      );
      await expectLater(pending.addManual(manual), throwsFormatException);
      second.complete(true);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(store.value, isEmpty);
      expect(pending.entries, isEmpty);
    },
  );

  test(
    'the total scan deadline rejects late discovery without starting validation',
    () async {
      final scan = Completer<List<InstalledLaunchTarget>>();
      var checks = 0;
      final registry = InstalledAppRegistry(
        discover: () => scan.future,
        validate: (_) async {
          checks++;
          return true;
        },
        scanTimeout: const Duration(milliseconds: 10),
      );
      await expectLater(registry.refresh(), throwsA(isA<TimeoutException>()));
      scan.complete([entry('late')]);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(registry.entries, isEmpty);
      expect(checks, 0);
    },
  );

  test(
    'repeated installs and removals cannot accumulate historical inventory entries',
    () async {
      var found = <InstalledLaunchTarget>[];
      final registry = InstalledAppRegistry(
        discover: () async => found,
        validate: (_) async => true,
      );
      for (var cycle = 0; cycle < 8; cycle++) {
        found = List.generate(100, (index) => entry('cycle-$cycle-$index'));
        await registry.refresh(force: true);
        expect(registry.entries, hasLength(100));
        found = [];
        await registry.refresh(force: true);
        expect(registry.entries, isEmpty);
      }
    },
  );

  test(
    'identities remain stable across renaming and duplicate display names stay distinct',
    () async {
      final a = entry('one'),
          b = entry('two'),
          renamed = entry('one', name: 'Renamed');
      expect(a.id, renamed.id);
      expect(a.id, isNot(b.id));
      final registry = InstalledAppRegistry(
        discover: () async => [a, b],
        validate: (_) async => true,
      );
      await registry.refresh();
      expect(registry.entries, hasLength(2));
      expect(registry.resolve(a.id)?.name, 'Example App');
    },
  );
  test(
    'a minute cache and single in-flight scan keep runtime polling cheap',
    () async {
      var now = DateTime.utc(2026);
      var calls = 0;
      final pending = Completer<List<InstalledLaunchTarget>>();
      final registry = InstalledAppRegistry(
        discover: () {
          calls++;
          return pending.future;
        },
        clock: () => now,
        validate: (_) async => true,
      );
      final a = registry.refresh();
      final b = registry.refresh();
      pending.complete([entry('one')]);
      await Future.wait([a, b]);
      expect(calls, 1);
      await registry.refresh();
      expect(calls, 1);
      now = now.add(const Duration(seconds: 61));
      await registry.refresh();
      expect(calls, 2);
      await registry.refresh(force: true);
      expect(calls, 3);
    },
  );
  test(
    'uninstall and failed scans retain identity but revoke resolution; reinstall restores it',
    () async {
      var found = [entry('one')];
      var fail = false;
      final registry = InstalledAppRegistry(
        discover: () async {
          if (fail) throw StateError('scan failed');
          return found;
        },
        validate: (_) async => true,
      );
      await registry.refresh();
      final id = found.single.id;
      expect(registry.resolve(id), isNotNull);
      found = [];
      await registry.refresh(force: true);
      expect(registry.entries, isEmpty);
      expect(registry.resolve(id), isNull);
      found = [entry('one', name: 'New name')];
      await registry.refresh(force: true);
      expect(registry.resolve(id)?.name, 'New name');
      fail = true;
      await expectLater(registry.refresh(force: true), throwsStateError);
      expect(registry.resolve(id), isNull);
      expect(registry.entries.single.id, id);
    },
  );
  test(
    'manual persistence failures do not publish an unsaved target or lose prior entries',
    () async {
      final store = MemoryInstalledRegistryStore();
      final registry = InstalledAppRegistry(
        store: store,
        validate: (_) async => true,
      );
      final first = entry('manual-one', manual: true),
          second = entry('manual-two', manual: true);
      await registry.addManual(first);
      store.failSave = true;
      await expectLater(registry.addManual(second), throwsStateError);
      expect(registry.resolve(first.id), isNotNull);
      expect(registry.resolve(second.id), isNull);
      expect(store.value.map((item) => item.id), [first.id]);
      await expectLater(registry.removeManual(first.id), throwsStateError);
      expect(registry.resolve(first.id), isNotNull);
      final restarted = InstalledAppRegistry(
        store: store,
        validate: (_) async => true,
      );
      await restarted.initialize();
      expect(restarted.resolve(first.id), isNotNull);
    },
  );
  test(
    'a pending OS scan cannot overwrite a newly saved manual target',
    () async {
      final scan = Completer<List<InstalledLaunchTarget>>();
      final registry = InstalledAppRegistry(
        discover: () => scan.future,
        validate: (_) async => true,
      );
      final refresh = registry.refresh();
      final manual = entry('manual', manual: true);
      await registry.addManual(manual);
      scan.complete([entry('os')]);
      await refresh;
      expect(registry.entries, hasLength(2));
      expect(registry.resolve(manual.id), isNotNull);
    },
  );
  test(
    'invalid IDs paths and tampered manual state fail closed without overwriting storage',
    () async {
      final valid = entry('one', manual: true);
      expect(
        () => validateInstalledTarget(
          InstalledLaunchTarget(
            id: 'chrome',
            name: valid.name,
            kind: valid.kind,
            identity: valid.identity,
            locator: valid.locator,
            manual: true,
          ),
        ),
        throwsFormatException,
      );
      expect(
        () => validateInstalledTarget(
          InstalledLaunchTarget.discovered(
            name: 'bad',
            kind: InstalledLaunchKind.linuxDesktopEntry,
            identity: 'bad',
            locator: 'https://example.com/app.desktop',
            manual: true,
          ),
        ),
        throwsFormatException,
      );
      expect(
        () => InstalledLaunchTarget.fromLocalJson({
          ...valid.toLocalJson(),
          'arguments': ['--unsafe'],
        }),
        throwsFormatException,
      );
      final store = MemoryInstalledRegistryStore()
        ..value = [valid]
        ..failRead = true;
      final registry = InstalledAppRegistry(
        store: store,
        validate: (_) async => true,
      );
      await expectLater(
        registry.addManual(entry('two', manual: true)),
        throwsStateError,
      );
      expect(store.value.single.id, valid.id);
    },
  );
}
