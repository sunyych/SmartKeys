import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumiakeys_protocol/lumiakeys_protocol.dart';
import 'package:lumiakeys_companion/app_library/app_library.dart';
import 'package:lumiakeys_companion/app_library_bundle.dart';
import 'package:lumiakeys_companion/desktop_controller.dart';
import 'package:lumiakeys_companion/desktop_actions.dart';

class Discovery implements ApplicationDiscovery {
  @override
  Future<List<RemoteApplication>> refresh(List<RemoteApplication> apps) async =>
      apps.map((a) => a.copyWith(detected: true)).toList();
}

class Store extends MemoryDesktopConfigStore {
  bool fail = false;
  @override
  Future<void> save(DesktopManifest value) async {
    if (fail) throw StateError('Fixture unavailable');
    await super.save(value);
  }
}

class Actions extends DesktopActions {
  final guards = <String?>[];
  @override
  Future<void> executeButton(
    RemoteShortcutButton button,
    DesktopManifest manifest, {
    String? expectedAppId,
  }) async => guards.add(expectedAppId);
}

void main() {
  Future<DesktopController> ready({
    String os = 'windows',
    Store? store,
    Actions? actions,
    bool foreground = false,
  }) async {
    final c = DesktopController(
      store: store ?? Store(),
      actions: actions ?? Actions(),
      discovery: Discovery(),
      libraryOperatingSystem: os,
      foregroundProbe: (_) async => foreground,
    );
    await c.initialize();
    addTearDown(c.dispose);
    return c;
  }

  String library(String app, String os) =>
      AppLibraryCatalog.builtin.appById(app)!.libraryForOS(os)!.id;
  test(
    'actual OS rejects mismatched library and Safari without altering persistence',
    () async {
      final c = await ready();
      final before = jsonEncode(c.manifest.toJson());
      await expectLater(
        c.installAppLibrary('chrome', library('chrome', 'macos')),
        throwsFormatException,
      );
      await expectLater(
        c.installAppLibrary('safari', library('safari', 'macos')),
        throwsFormatException,
      );
      await expectLater(
        c.installAppLibrary('codex', 'codex.windowsLinux'),
        throwsFormatException,
      );
      expect(jsonEncode(c.manifest.toJson()), before);
    },
  );
  test(
    'add-copy is independent and explicit replacement preserves edits and extra actions',
    () async {
      final c = await ready();
      final slots = c.launcherAppIds;
      final one = await c.installAppLibrary(
        'chrome',
        library('chrome', 'windows'),
      );
      final two = await c.installAppLibrary(
        'chrome',
        library('chrome', 'windows'),
      );
      expect(one, isNot(two));
      final p = c.manifest.profiles.singleWhere((p) => p.id == one);
      final old = c.manifest.layoutById(p.layoutId)!;
      await c.updateButton(
        old.id,
        old.buttons.first.copyWith(
          name: 'My custom name',
          shortcut: ['CTRL', 'Q'],
        ),
      );
      final customized = c.manifest.layoutById(old.id)!;
      await c.importShortcutLayouts([
        customized.copyWith(
          buttons: [
            ...customized.buttons,
            const RemoteShortcutButton(
              id: 'custom.extra',
              name: 'My extra',
              icon: 'keyboard',
              targetType: RemoteTargetType.keyboardShortcut,
              shortcut: ['ALT', 'X'],
            ),
          ],
        ),
      ]);
      await c.installAppLibrary(
        'chrome',
        library('chrome', 'windows'),
        replaceProfileId: one,
      );
      final after = c.manifest.layoutById(p.layoutId)!;
      expect(after.buttons.first.name, 'My custom name');
      expect(after.buttons.first.shortcut, ['CTRL', 'Q']);
      expect(after.buttons.last.id, 'custom.extra');
      expect(c.launcherAppIds, slots);
      expect(
        c.manifest.profiles.where((p) => p.sourceAppId == 'chrome'),
        hasLength(2),
      );
      await expectLater(
        c.installAppLibrary(
          'chatgpt',
          library('chatgpt', 'windows'),
          replaceProfileId: one,
        ),
        throwsFormatException,
      );
    },
  );
  test(
    'failed install leaves no partial layout profile icon or slots',
    () async {
      final store = Store();
      final c = await ready(store: store);
      final before = jsonEncode(c.manifest.toJson());
      final durableBefore = jsonEncode(store.value!.toJson());
      store.fail = true;
      await expectLater(
        c.installAppLibrary('chrome', library('chrome', 'windows')),
        throwsStateError,
      );
      expect(jsonEncode(c.manifest.toJson()), before);
      expect(jsonEncode(store.value!.toJson()), durableBefore);
    },
  );
  for (final app in ['chrome', 'claude', 'cursor']) {
    test('$app library namespace cannot bypass foreground guard', () async {
      final actions = Actions();
      final c = await ready(actions: actions);
      final id = await c.installAppLibrary(app, library(app, 'windows'));
      final p = c.manifest.profiles.singleWhere((p) => p.id == id);
      expect(p.applicationId, app);
      var b = c.manifest.layoutById(p.layoutId)!.buttons.first;
      if (!b.enabled) {
        b = b.copyWith(enabled: true, shortcut: ['CTRL', 'F']);
        await c.updateButton(p.layoutId, b);
      }
      await expectLater(
        c.executeRemote(RemoteActionRequest.button(b.id)),
        throwsStateError,
      );
      expect(actions.guards, isEmpty);
    });
  }
  test(
    'known active app retains native expectedApp guard while unknown App is manual only',
    () async {
      final actions = Actions();
      final c = await ready(actions: actions, foreground: true);
      final id = await c.installAppLibrary(
        'chrome',
        library('chrome', 'windows'),
      );
      final p = c.manifest.profiles.singleWhere((p) => p.id == id);
      await c.executeRemote(
        RemoteActionRequest.button(
          c.manifest.layoutById(p.layoutId)!.buttons.first.id,
        ),
      );
      expect(actions.guards, ['chrome']);
      final manualId = await c.installAppLibrary(
        'word',
        library('word', 'windows'),
      );
      final manual = c.manifest.profiles.singleWhere((p) => p.id == manualId);
      expect(manual.applicationId, isNull);
      final button = c.manifest.layoutById(manual.layoutId)!.buttons.first;
      await c.executeRemote(RemoteActionRequest.button(button.id));
      expect(actions.guards.last, isNull);
      expect(c.manifest.applications.any((a) => a.id == 'word'), false);
    },
  );
  test('explicit replacement preserves user deletion and ordering', () async {
    final c = await ready();
    final id = await c.installAppLibrary(
      'chrome',
      library('chrome', 'windows'),
    );
    final p = c.manifest.profiles.singleWhere((p) => p.id == id);
    final old = c.manifest.layoutById(p.layoutId)!;
    final changed = old.copyWith(
      buttons: old.buttons.skip(1).toList().reversed.toList(),
    );
    await c.importShortcutLayouts([changed]);
    await c.installAppLibrary(
      'chrome',
      library('chrome', 'windows'),
      replaceProfileId: id,
    );
    expect(
      c.manifest.layoutById(p.layoutId)!.buttons.map((b) => b.id),
      changed.buttons.map((b) => b.id),
    );
  });
  test(
    'library editor rejects other action types and enables explicit keyboard assignment',
    () async {
      final c = await ready();
      final id = await c.installAppLibrary(
        'claude',
        library('claude', 'windows'),
      );
      final p = c.manifest.profiles.singleWhere((p) => p.id == id);
      final first = c.manifest.layoutById(p.layoutId)!.buttons.first;
      await expectLater(
        c.updateButton(
          p.layoutId,
          first.copyWith(targetType: RemoteTargetType.voiceInput),
        ),
        throwsFormatException,
      );
      await expectLater(
        c.updateButton(p.layoutId, first.copyWith(enabled: true, shortcut: [])),
        throwsFormatException,
      );
      await c.updateButton(
        p.layoutId,
        first.copyWith(shortcut: ['CTRL', 'K'], enabled: true),
      );
      expect(c.manifest.buttonById(first.id)!.shortcut, ['CTRL', 'K']);
      await expectLater(
        c.executeRemote(RemoteActionRequest.button(first.id)),
        throwsStateError,
      );
    },
  );
  test(
    'online extra requires a verified icon bundle and installs atomically',
    () async {
      final c = await ready();
      final app = AppLibraryCatalog.builtin.appById('7zip')!;
      await expectLater(
        c.installAppLibrary(app.id, library(app.id, 'windows')),
        throwsFormatException,
      );
      final png = File(
        '../packages/app_icon_catalog/png/7zip.png',
      ).readAsBytesSync();
      final bundle = AppLibraryBundle.decode(
        utf8.encode(
          jsonEncode({
            'schemaVersion': 1,
            'app': app.toJson(),
            'icon': {
              'id': app.iconId,
              'sha256': registeredAppIconHash(app.iconId),
              'pngBase64': base64Encode(png),
            },
          }),
        ),
      );
      final id = await c.installAppLibrary(
        app.id,
        library(app.id, 'windows'),
        bundle: bundle,
      );
      final p = c.manifest.profiles.singleWhere((p) => p.id == id);
      expect(p.sourceIconSha256, registeredAppIconHash('7zip'));
      expect(p.applicationId, isNull);
      expect(
        c.manifest.layoutById(p.layoutId)!.buttons.every((b) => !b.enabled),
        true,
      );
      final next = await c.installAppLibrary(
        app.id,
        library(app.id, 'windows'),
      );
      expect(
        c.manifest.profiles
            .singleWhere((p) => p.id == next)
            .sourceIconPngBase64,
        p.sourceIconPngBase64,
      );
    },
  );
  test(
    'bundle strict codec imports registered PNG and survives manifest roundtrip',
    () async {
      final app = AppLibraryCatalog.builtin.appById('chrome')!;
      final png = File('assets/app_icons/chrome.png').readAsBytesSync();
      Map<String, Object> envelope() => {
        'schemaVersion': 1,
        'app': app.toJson(),
        'icon': {
          'id': app.iconId,
          'sha256': registeredAppIconHash(app.iconId)!,
          'pngBase64': base64Encode(png),
        },
      };
      final bundle = AppLibraryBundle.decode(
        utf8.encode(jsonEncode(envelope())),
      );
      expect(() => bundle.pngBytes[0] = 0, throwsUnsupportedError);
      final c = await ready();
      final id = await c.installAppLibrary(
        app.id,
        library('chrome', 'windows'),
        bundle: bundle,
      );
      final wire = DesktopManifest.fromJson(c.manifest.toJson(forSync: true));
      final p = wire.profiles.singleWhere((p) => p.id == id);
      expect(p.sourceIconSha256, registeredAppIconHash('chrome'));
      expect(base64Decode(p.sourceIconPngBase64!), png);
      for (final mutation in [
        (Map<String, dynamic> x) => x['command'] = 'raw command',
        (Map<String, dynamic> x) => x['schemaVersion'] = 1.0,
        (Map<String, dynamic> x) => (x['icon'] as Map)['pngBase64'] =
            '%69${(x['icon']['pngBase64'] as String).substring(1)}',
        (Map<String, dynamic> x) => (x['icon'] as Map)['id'] = 'word',
        (Map<String, dynamic> x) => (x['icon'] as Map)['sha256'] = '0' * 64,
        (Map<String, dynamic> x) => (x['app'] as Map)['name'] = 'Different app',
        (Map<String, dynamic> x) =>
            (x['icon'] as Map)['pngBase64'] = base64Encode([1, 2, 3]),
      ]) {
        final raw = jsonDecode(jsonEncode(envelope())) as Map<String, dynamic>;
        mutation(raw);
        expect(
          () => AppLibraryBundle.decode(utf8.encode(jsonEncode(raw))),
          throwsFormatException,
        );
      }
      expect(
        () => AppLibraryBundle.decode(
          List.filled(AppLibraryBundle.maxBytes + 1, 32),
        ),
        throwsFormatException,
      );
    },
  );
}
