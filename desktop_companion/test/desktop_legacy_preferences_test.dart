import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumiakeys_companion/desktop_controller.dart';
import 'package:lumiakeys_companion/installed_app_registry.dart';
import 'package:lumiakeys_protocol/lumiakeys_protocol.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Preferences implements SharedPreferencesAsync {
  final values = <String, Object>{};
  final writes = <String>[];
  final failNextWrite = <String>{};

  @override
  Future<String?> getString(String key) async => values[key] as String?;

  @override
  Future<List<String>?> getStringList(String key) async {
    final value = values[key] as List<String>?;
    return value == null ? null : List.of(value);
  }

  @override
  Future<void> setString(String key, String value) async {
    if (failNextWrite.remove(key)) throw StateError('Synthetic write failure');
    writes.add(key);
    values[key] = value;
  }

  @override
  Future<void> setStringList(String key, List<String> value) async {
    writes.add(key);
    values[key] = List.of(value);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Discovery implements ApplicationDiscovery {
  @override
  Future<List<RemoteApplication>> refresh(List<RemoteApplication> apps) async =>
      apps;
}

const _manifestKey = SharedPreferencesDesktopConfigStore.storageKey;
const _launcherKey = SharedPreferencesLauncherKeyStore.storageKey;
const _identity = '0123456789abcdef0123456789abcdef';

DesktopController _controller(_Preferences preferences) {
  final controller = DesktopController(
    store: SharedPreferencesDesktopConfigStore(preferences: preferences),
    launcherKeyStore: SharedPreferencesLauncherKeyStore(
      preferences: preferences,
    ),
    installedRegistry: InstalledAppRegistry(),
    discovery: _Discovery(),
  );
  addTearDown(controller.dispose);
  return controller;
}

void main() {
  test(
    'desktop manifest persists as one versioned preference JSON record',
    () async {
      final preferences = _Preferences()
        ..values['unrelated.feature'] = 'retained';
      final store = SharedPreferencesDesktopConfigStore(
        preferences: preferences,
      );
      expect(await store.load(), isNull);

      final manifest = DesktopManifest.regularStarter().copyWith(
        computerId: _identity,
        revision: 13,
        settings: const RemoteSettings(syncIcons: false),
        launcherApplicationIds: ['chrome', ...List<String?>.filled(11, null)],
      );
      await store.save(manifest);
      expect(preferences.writes, [_manifestKey]);
      final raw = jsonDecode(preferences.values[_manifestKey] as String) as Map;
      expect(raw['schemaVersion'], 1);
      expect(raw['computerId'], _identity);
      expect(raw['revision'], 13);
      expect(raw['launcherApplicationIds'], manifest.launcherApplicationIds);
      expect((await store.load())!.toJson(), manifest.toJson());
      expect(preferences.values['unrelated.feature'], 'retained');
    },
  );

  test(
    'invalid preference bytes block edits until a fresh load succeeds',
    () async {
      final preferences = _Preferences()
        ..values[_manifestKey] = '["wrong shape"]';
      final controller = _controller(preferences);
      await controller.initialize();
      expect(controller.error, contains('Invalid desktop config'));
      await expectLater(
        controller.updateSettings(const RemoteSettings(syncIcons: false)),
        throwsStateError,
      );
      expect(preferences.writes, isEmpty);
      expect(preferences.values[_manifestKey], '["wrong shape"]');

      final recoveredManifest = DesktopManifest.regularStarter().copyWith(
        computerId: _identity,
        settings: const RemoteSettings(autoLaunchApps: false),
      );
      preferences.values[_manifestKey] = jsonEncode(recoveredManifest.toJson());
      final recovered = _controller(preferences);
      await recovered.initialize();
      expect(recovered.error, isNull);
      expect(recovered.manifest.computerId, _identity);
      expect(recovered.manifest.settings.autoLaunchApps, isFalse);
      await recovered.updateSettings(
        recovered.manifest.settings.copyWith(syncIcons: false),
      );
      expect(recovered.manifest.settings.syncIcons, isFalse);
      expect(preferences.writes, [_manifestKey, _manifestKey]);
    },
  );

  test(
    'legacy launcher preferences decode eight keys and save twelve',
    () async {
      final preferences = _Preferences()
        ..values[_launcherKey] = <String>[
          'chrome',
          '',
          'codex',
          '',
          '',
          '',
          '',
          'edge',
        ];
      final launcher = SharedPreferencesLauncherKeyStore(
        preferences: preferences,
      );
      final decoded = await launcher.load();
      expect(decoded, [
        'chrome',
        null,
        'codex',
        null,
        null,
        null,
        null,
        'edge',
        null,
        null,
        null,
        null,
      ]);
      await expectLater(
        launcher.save(decoded.take(8).toList()),
        throwsFormatException,
      );
      expect(preferences.writes, isEmpty);
      await launcher.save(decoded);
      expect(preferences.values[_launcherKey], [
        'chrome',
        '',
        'codex',
        '',
        '',
        '',
        '',
        'edge',
        '',
        '',
        '',
        '',
      ]);
      expect(await launcher.load(), decoded);

      preferences.values[_launcherKey] = <String>['chrome'];
      expect(await launcher.load(), List<String?>.filled(12, null));
    },
  );

  test(
    'queued launcher save survives an earlier rejected settings write',
    () async {
      final preferences = _Preferences();
      final controller = _controller(preferences);
      await controller.initialize();
      final previous = controller.manifest.revision;
      preferences.failNextWrite.add(_manifestKey);

      final rejected = expectLater(
        controller.updateSettings(
          controller.manifest.settings.copyWith(syncIcons: false),
        ),
        throwsStateError,
      );
      final launcher = controller.assignLauncherApp(0, 'chrome');
      await rejected;
      await launcher;

      final saved = await SharedPreferencesDesktopConfigStore(
        preferences: preferences,
      ).load();
      expect(saved!.revision, previous + 1);
      expect(saved.settings.syncIcons, isTrue);
      expect(saved.launcherApplicationIds.first, 'chrome');
      expect(controller.manifest.revision, saved.revision);
      expect(controller.manifest.settings.toJson(), saved.settings.toJson());
      expect(
        controller.manifest.launcherApplicationIds,
        saved.launcherApplicationIds,
      );
      expect(controller.manifest.computerId, saved.computerId);
      expect(controller.error, isNull);
      expect(preferences.writes, [_manifestKey, _manifestKey]);
    },
  );

  test('a mixed valid and invalid layout import writes nothing', () async {
    final preferences = _Preferences();
    final controller = _controller(preferences);
    await controller.initialize();
    await controller.assignLauncherApp(0, 'chrome');
    await controller.updateSettings(
      controller.manifest.settings.copyWith(syncIcons: false),
    );
    final before = controller.manifest;
    final savedRecord = preferences.values[_manifestKey];
    final writeCount = preferences.writes.length;
    const importedName = 'Fixture import';
    final keyboard = before
        .layoutById('keyboard')!
        .copyWith(name: importedName);
    const unknown = RemoteShortcutLayout(
      id: 'fixture.unknown',
      name: 'Unknown layout',
      kind: RemoteLayoutKind.application,
      buttons: [],
    );

    await expectLater(
      controller.importShortcutLayouts([keyboard, unknown]),
      throwsFormatException,
    );
    expect(controller.manifest.toJson(), before.toJson());
    expect(preferences.values[_manifestKey], savedRecord);
    expect(preferences.writes, hasLength(writeCount));

    await controller.importShortcutLayouts([keyboard]);
    final stored = (await SharedPreferencesDesktopConfigStore(
      preferences: preferences,
    ).load())!;
    expect(stored.layoutById('keyboard')!.name, importedName);
    expect(stored.revision, before.revision + 1);
    expect(stored.computerId, before.computerId);
    expect(stored.settings.toJson(), before.settings.toJson());
    expect(stored.launcherApplicationIds, before.launcherApplicationIds);
    expect(preferences.writes, hasLength(writeCount + 1));
  });
}
