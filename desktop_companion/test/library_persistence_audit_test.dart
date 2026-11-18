import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumiakeys_protocol/lumiakeys_protocol.dart';
import 'package:lumiakeys_companion/app_library/app_library.dart';
import 'package:lumiakeys_companion/app_library_bundle.dart';
import 'package:lumiakeys_companion/desktop_actions.dart';
import 'package:lumiakeys_companion/desktop_controller.dart';
import 'package:lumiakeys_companion/installed_app_registry.dart';

/// Serializes on every write and decodes a fresh object on every load, matching
/// the durable manifest boundary rather than sharing the controller's objects.
class JsonStore implements DesktopConfigStore {
  String? raw;
  bool failBeforeWrite = false;
  int writes = 0;
  @override
  Future<DesktopManifest?> load() async => raw == null
      ? null
      : DesktopManifest.fromJson(jsonDecode(raw!) as Map<String, Object?>);
  @override
  Future<void> save(DesktopManifest manifest) async {
    if (failBeforeWrite) throw StateError('Fixture atomic write rejected');
    raw = jsonEncode(manifest.toJson());
    writes++;
  }
}

class Discovery implements ApplicationDiscovery {
  @override
  Future<List<RemoteApplication>> refresh(List<RemoteApplication> apps) async =>
      apps.map((app) => app.copyWith(detected: true)).toList();
}

class NoInputActions extends DesktopActions {
  int commands = 0;
  @override
  Future<void> executeButton(
    RemoteShortcutButton button,
    DesktopManifest manifest, {
    String? expectedAppId,
  }) async => commands++;
  @override
  Future<void> activateApplication(RemoteApplication app) async => commands++;
}

AppLibraryBundle sevenZipBundle() {
  final app = AppLibraryCatalog.builtin.appById('7zip')!;
  final bytes = File(
    '../packages/app_icon_catalog/png/7zip.png',
  ).readAsBytesSync();
  return AppLibraryBundle.decode(
    utf8.encode(
      jsonEncode({
        'schemaVersion': 1,
        'app': app.toJson(),
        'icon': {
          'id': app.iconId,
          'sha256': registeredAppIconHash(app.iconId),
          'pngBase64': base64Encode(bytes),
        },
      }),
    ),
  );
}

void main() {
  Future<DesktopController> open(
    JsonStore store, {
    String os = 'windows',
    NoInputActions? actions,
    InstalledAppRegistry? registry,
  }) async {
    final controller = DesktopController(
      store: store,
      launcherKeyStore: MemoryLauncherKeyStore(),
      discovery: Discovery(),
      actions: actions ?? NoInputActions(),
      installedRegistry: registry ?? InstalledAppRegistry(),
      libraryOperatingSystem: os,
    );
    await controller.initialize();
    addTearDown(controller.dispose);
    expect(controller.error, isNull);
    return controller;
  }

  String library(String id, String os) =>
      AppLibraryCatalog.builtin.appById(id)!.libraryForOS(os)!.id;

  for (final os in ['macos', 'linux']) {
    test(
      '$os installs real native chords and preserves provenance after JSON reload',
      () async {
        final store = JsonStore();
        final actions = NoInputActions();
        final c = await open(store, os: os, actions: actions);
        final id = await c.installAppLibrary('chrome', library('chrome', os));
        final p = c.manifest.profiles.singleWhere((p) => p.id == id);
        final tab = c.manifest
            .layoutById(p.layoutId)!
            .buttons
            .singleWhere((b) => b.id.endsWith('.new-tab'));
        expect(tab.shortcut, [os == 'macos' ? 'META' : 'CTRL', 'T']);
        final reloaded = await open(store, os: os);
        final saved = reloaded.manifest.profiles.singleWhere((p) => p.id == id);
        expect(saved.platform, os);
        expect(saved.sourceIconId, 'chrome');
        expect(saved.sourceLibraryId, library('chrome', os));
        expect(saved.sourceActionHashes, p.sourceActionHashes);
        expect(reloaded.manifest.buttonById(tab.id)!.shortcut, tab.shortcut);
        if (os == 'macos') {
          final safari = await reloaded.installAppLibrary(
            'safari',
            library('safari', 'macos'),
          );
          expect(
            reloaded.manifest.profiles
                .singleWhere((p) => p.id == safari)
                .platform,
            'macos',
          );
        } else {
          final before = store.raw;
          await expectLater(
            reloaded.installAppLibrary('word', library('word', 'windows')),
            throwsFormatException,
          );
          await expectLater(
            reloaded.installAppLibrary('safari', library('safari', 'macos')),
            throwsFormatException,
          );
          expect(
            store.raw,
            before,
            reason:
                'A shared keyboard family does not grant Linux App availability',
          );
        }
        expect(actions.commands, 0);
      },
    );
  }

  test(
    'rejected extra-icon write cannot leave half an App across restart; retry is complete',
    () async {
      final store = JsonStore();
      final actions = NoInputActions();
      final c = await open(store, actions: actions);
      await c.assignLauncherApp(0, 'chrome');
      final before = store.raw;
      final bundle = sevenZipBundle();
      store.failBeforeWrite = true;
      await expectLater(
        c.installAppLibrary('7zip', library('7zip', 'windows'), bundle: bundle),
        throwsStateError,
      );
      expect(store.raw, before);
      expect(
        c.manifest.profiles.where((p) => p.sourceAppId == '7zip'),
        isEmpty,
      );
      store.failBeforeWrite = false;
      final retry = await open(store);
      expect(
        retry.manifest.profiles.where((p) => p.sourceAppId == '7zip'),
        isEmpty,
      );
      expect(store.raw, isNot(contains('sourceIconPngBase64')));
      final id = await retry.installAppLibrary(
        '7zip',
        library('7zip', 'windows'),
        bundle: bundle,
      );
      final reloaded = await open(store);
      final p = reloaded.manifest.profiles.singleWhere((p) => p.id == id);
      expect(p.sourceIconSha256, registeredAppIconHash('7zip'));
      expect(base64Decode(p.sourceIconPngBase64!), bundle.pngBytes);
      expect(reloaded.manifest.layoutById(p.layoutId), isNotNull);
      expect(reloaded.launcherAppIds[0], 'chrome');
      expect(actions.commands, 0);
    },
  );

  test(
    'restart and replace retain fifteen custom actions, deletion, order and sidebar preference',
    () async {
      final store = JsonStore();
      final c = await open(store);
      final id = await c.installAppLibrary(
        'chrome',
        library('chrome', 'windows'),
      );
      final p = c.manifest.profiles.singleWhere((p) => p.id == id);
      final old = c.manifest.layoutById(p.layoutId)!;
      final first = old.buttons.first.copyWith(
        name: 'My private shortcut',
        shortcut: ['ALT', 'Q'],
      );
      final custom = [
        first,
        ...old.buttons.skip(2),
        for (var i = 0; i < 4; i++)
          RemoteShortcutButton(
            id: 'custom.retained.$i',
            name: 'Extra $i',
            icon: 'keyboard',
            targetType: RemoteTargetType.keyboardShortcut,
            shortcut: ['CTRL', '$i'],
          ),
      ].reversed.toList();
      expect(custom, hasLength(15));
      await c.importShortcutLayouts([old.copyWith(buttons: custom)]);
      await c.setSidebarVisible(RemoteSidebarItem.profile(id), false);
      await c.setSidebarVisible(RemoteSidebarItem.profile(id), true);
      await c.moveSidebarItem(RemoteSidebarItem.profile(id), -1);
      final order = c.sidebarItems.map((item) => item.key).toList();
      final reloaded = await open(store);
      await reloaded.installAppLibrary(
        'chrome',
        library('chrome', 'windows'),
        replaceProfileId: id,
      );
      expect(
        reloaded.manifest
            .layoutById(p.layoutId)!
            .buttons
            .map((b) => b.toJson()),
        custom.map((b) => b.toJson()),
      );
      expect(reloaded.sidebarItems.map((item) => item.key), order);
      final twice = await open(store);
      expect(twice.manifest.layoutById(p.layoutId)!.buttons, hasLength(15));
      expect(twice.manifest.buttonById(first.id)!.shortcut, ['ALT', 'Q']);
      expect(twice.manifest.buttonById(old.buttons[1].id), isNull);
    },
  );

  test(
    'failed restore and empty sidebar survive JSON restart without reverting to defaults',
    () async {
      final store = JsonStore();
      final c = await open(store);
      await c.setSidebarVisible(
        const RemoteSidebarItem.application('chrome'),
        false,
      );
      final before = store.raw;
      store.failBeforeWrite = true;
      await expectLater(c.restoreSidebarDefaults(), throwsStateError);
      expect(store.raw, before);
      store.failBeforeWrite = false;
      final reloaded = await open(store);
      expect(reloaded.manifest.sidebarItems, isNotNull);
      expect(reloaded.sidebarItems.any((item) => item.id == 'chrome'), false);
      for (final item in reloaded.sidebarItems) {
        await reloaded.setSidebarVisible(item, false);
      }
      final empty = await open(store);
      expect(empty.manifest.sidebarItems, isEmpty);
      expect(empty.sidebarItems, isEmpty);
      await empty.restoreSidebarDefaults();
      final defaults = await open(store);
      expect(defaults.manifest.sidebarItems, isNull);
      expect(defaults.sidebarItems.any((item) => item.id == 'chrome'), true);
    },
  );

  test(
    'a present same-name installed launcher cannot enter sidebar or become a managed profile',
    () async {
      final target = InstalledLaunchTarget.discovered(
        name: 'Word',
        kind: InstalledLaunchKind.linuxDesktopEntry,
        identity: 'audit-word',
        locator: '/usr/share/applications/audit-word.desktop',
      );
      final registry = InstalledAppRegistry(
        discover: () async => [target],
        validate: (_) async => true,
      );
      final store = JsonStore();
      final c = await open(store, registry: registry);
      expect(c.manifest.applicationById(target.id)!.launchOnly, true);
      await c.assignLauncherApp(0, target.id);
      final before = store.raw, writes = store.writes;
      await expectLater(
        c.setSidebarVisible(RemoteSidebarItem.application(target.id), true),
        throwsFormatException,
      );
      expect(store.raw, before);
      expect(store.writes, writes);
      final id = await c.installAppLibrary('word', library('word', 'windows'));
      expect(
        c.manifest.profiles.singleWhere((p) => p.id == id).applicationId,
        isNull,
      );
      expect(
        c.manifest.applicationById(target.id)!.layoutId,
        installedLaunchOnlyLayoutId,
      );
      expect(c.manifest.applicationById(target.id)!.launchOnly, true);
      expect(c.launcherAppIds[0], target.id);
    },
  );
}
