import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumiakeys_protocol/lumiakeys_protocol.dart';
import 'package:lumiakeys_companion/desktop_controller.dart';
import 'package:lumiakeys_companion/desktop_actions.dart';

class _Discovery implements ApplicationDiscovery {
  @override
  Future<List<RemoteApplication>> refresh(List<RemoteApplication> apps) async =>
      apps.map((app) => app.copyWith(detected: true)).toList();
}

class _Legacy implements LauncherKeyStore {
  int reads = 0;
  @override
  Future<List<String?>> load() async {
    reads++;
    return ['chrome', ...List<String?>.filled(7, null)];
  }

  @override
  Future<void> save(List<String?> slots) async =>
      throw StateError('Legacy storage must not be a second writer.');
}

class _AmbiguousStore extends MemoryDesktopConfigStore {
  bool failAfterWrite = false;
  @override
  Future<void> save(DesktopManifest manifest) async {
    await super.save(manifest);
    if (failAfterWrite) {
      failAfterWrite = false;
      throw StateError('Acknowledgement lost');
    }
  }
}

class _Actions extends DesktopActions {
  @override
  Future<void> activateApplication(RemoteApplication app) async {}
}

class _DeferredStore extends MemoryDesktopConfigStore {
  Completer<void>? blockNext;
  final entered = Completer<void>();
  @override
  Future<void> save(DesktopManifest manifest) async {
    final gate = blockNext;
    if (gate != null) {
      blockNext = null;
      entered.complete();
      await gate.future;
    }
    await super.save(manifest);
  }
}

class _FailingLegacy implements LauncherKeyStore {
  bool fail = true;
  int reads = 0;
  @override
  Future<List<String?>> load() async {
    reads++;
    if (fail) throw StateError('Temporary legacy preference read failure');
    return ['chrome', ...List<String?>.filled(7, null)];
  }

  @override
  Future<void> save(List<String?> slots) async =>
      throw StateError('Read-only migration source');
}

class _MonitorDiscovery extends PlatformApplicationDiscovery {
  int refreshes = 0;
  int installedRefreshes = 0;
  String? foregroundAppId;

  @override
  void invalidateInstalledCache() {
    super.invalidateInstalledCache();
    installedRefreshes++;
  }

  @override
  Future<List<RemoteApplication>> refresh(List<RemoteApplication> apps) async {
    refreshes++;
    return [
      for (final app in apps)
        app.copyWith(
          detected: true,
          running: app.id == foregroundAppId,
          foreground: app.id == foregroundAppId,
        ),
    ];
  }
}

void main() {
  testWidgets(
    'periodic refresh only revises the manifest when its content changes',
    (tester) async {
      final store = MemoryDesktopConfigStore();
      final discovery = _MonitorDiscovery();
      final controller = DesktopController(store: store, discovery: discovery);
      DesktopManifest wireManifest() =>
          DesktopManifest.fromJson(controller.manifest.toJson(forSync: true));

      try {
        await controller.initialize();
        final initial = wireManifest();
        final initialWrites = store.saveCount;

        for (var refresh = 1; refresh <= 2; refresh++) {
          await tester.pump(const Duration(seconds: 60));
          expect(discovery.installedRefreshes, refresh);
          expect(wireManifest().revision, initial.revision);
          expect(store.saveCount, initialWrites);
        }

        discovery.foregroundAppId = 'chrome';
        await tester.pump(const Duration(seconds: 3));
        final activated = wireManifest();
        expect(activated.revision, initial.revision + 1);
        expect(
          activated.applicationActivationSequence,
          initial.applicationActivationSequence + 1,
        );
        expect(activated.activatedApplicationId, 'chrome');
        expect(activated.applicationById('chrome')!.foreground, isTrue);
        expect(store.saveCount, initialWrites + 1);

        await controller.assignLauncherApp(0, 'chrome');
        final configured = wireManifest();
        expect(configured.revision, activated.revision + 1);
        expect(configured.launcherApplicationIds.first, 'chrome');
        expect(store.value!.revision, configured.revision);
        expect(store.saveCount, initialWrites + 2);

        await controller.assignLauncherApp(0, 'chrome');
        expect(wireManifest().revision, configured.revision);
        expect(store.saveCount, initialWrites + 2);
      } finally {
        controller.dispose();
      }
    },
  );

  test(
    'deferred saves retain independent buttons, settings and launcher edits',
    () async {
      final store = _DeferredStore();
      final controller = DesktopController(
        store: store,
        discovery: _Discovery(),
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      final before = controller.manifest;
      final gate = Completer<void>();
      store.blockNext = gate;
      final first = controller.updateButton(
        'keyboard',
        before.buttonById('keyboard.copy')!.copyWith(name: 'First saved copy'),
      );
      await store.entered.future;
      final second = controller.updateButton(
        'keyboard',
        before
            .buttonById('keyboard.paste')!
            .copyWith(name: 'Second saved paste'),
      );
      final settings = controller.updateSettings(
        before.settings.copyWith(syncIcons: false),
      );
      final slot = controller.assignLauncherApp(11, 'chrome');
      gate.complete();
      await Future.wait([first, second, settings, slot]);
      expect(
        store.value!.buttonById('keyboard.copy')!.name,
        'First saved copy',
      );
      expect(
        store.value!.buttonById('keyboard.paste')!.name,
        'Second saved paste',
      );
      expect(store.value!.settings.syncIcons, isFalse);
      expect(store.value!.launcherApplicationIds[11], 'chrome');
      expect(store.value!.revision, before.revision + 4);
    },
  );

  test(
    'independent settings fields merge against the latest committed manifest',
    () async {
      final store = _DeferredStore();
      final controller = DesktopController(
        store: store,
        discovery: _Discovery(),
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      final before = controller.manifest.settings;
      final gate = Completer<void>();
      store.blockNext = gate;
      final icons = controller.updateSettings(
        before.copyWith(syncIcons: false),
      );
      await store.entered.future;
      final launch = controller.updateSettings(
        before.copyWith(autoLaunchApps: false),
      );
      gate.complete();
      await Future.wait([icons, launch]);
      expect(store.value!.settings.syncIcons, isFalse);
      expect(store.value!.settings.autoLaunchApps, isFalse);
      expect(store.value!.settings.enableAppsSync, isTrue);
    },
  );

  testWidgets(
    'failed legacy reads never replace saved slots through edits or the app monitor',
    (tester) async {
      final original = DesktopManifest.regularStarter();
      final store = MemoryDesktopConfigStore()..value = original;
      final legacy = _FailingLegacy();
      final discovery = _MonitorDiscovery();
      final failed = DesktopController(
        store: store,
        launcherKeyStore: legacy,
        discovery: discovery,
      );
      addTearDown(failed.dispose);
      await failed.initialize();
      expect(failed.error, contains('previous launcher configuration'));
      expect(store.saveCount, 0);
      expect(store.value, same(original));
      await tester.pump(const Duration(seconds: 4));
      await failed.refreshApplications();
      await expectLater(
        failed.assignLauncherApp(0, 'chrome'),
        throwsStateError,
      );
      await expectLater(
        failed.updateSettings(
          failed.manifest.settings.copyWith(syncIcons: false),
        ),
        throwsStateError,
      );
      expect(discovery.refreshes, 0);
      expect(store.saveCount, 0);
      expect(store.value, same(original));
      legacy.fail = false;
      final recovered = DesktopController(
        store: store,
        launcherKeyStore: legacy,
        discovery: _Discovery(),
      );
      addTearDown(recovered.dispose);
      await recovered.initialize();
      expect(recovered.error, isNull);
      expect(recovered.launcherAppIds[0], 'chrome');
      expect(store.saveCount, 1);
      expect(legacy.reads, 2);
    },
  );
  test(
    'migrates eight slots once, and clearing cannot resurrect the legacy store',
    () async {
      final store = MemoryDesktopConfigStore(), legacy = _Legacy();
      final controller = DesktopController(
        store: store,
        launcherKeyStore: legacy,
        discovery: _Discovery(),
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      expect(controller.launcherAppIds, [
        'chrome',
        ...List<String?>.filled(11, null),
      ]);
      await controller.assignLauncherApp(0, null);
      final revision = controller.manifest.revision;
      final reloaded = DesktopController(
        store: store,
        launcherKeyStore: legacy,
        discovery: _Discovery(),
      );
      addTearDown(reloaded.dispose);
      await reloaded.initialize();
      expect(
        reloaded.launcherAppIds,
        List<String?>.filled(launcherSlotCount, null),
      );
      expect(legacy.reads, 1);
      expect(reloaded.manifest.revision, revision);
    },
  );
  test(
    'slot and revision reconcile an atomic write whose acknowledgement failed',
    () async {
      final store = _AmbiguousStore();
      final controller = DesktopController(
        store: store,
        discovery: _Discovery(),
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      final before = controller.manifest.revision;
      store.failAfterWrite = true;
      await expectLater(
        controller.assignLauncherApp(11, 'chrome'),
        throwsStateError,
      );
      expect(controller.launcherAppIds, store.value!.launcherApplicationIds);
      expect(controller.launcherAppIds[11], 'chrome');
      expect(controller.manifest.revision, before + 1);
      await controller.assignLauncherApp(11, null);
      expect(store.value!.launcherApplicationIds[11], isNull);
      expect(controller.error, isNull);
    },
  );
  test(
    'parallel slot changes retain concurrently committed settings',
    () async {
      final store = MemoryDesktopConfigStore();
      final controller = DesktopController(
        store: store,
        discovery: _Discovery(),
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      final before = controller.manifest.revision;
      await Future.wait([
        for (var slot = 0; slot < launcherSlotCount; slot++)
          controller.assignLauncherApp(slot, 'chrome'),
        controller.updateSettings(
          controller.manifest.settings.copyWith(syncIcons: false),
        ),
      ]);
      expect(
        controller.launcherAppIds,
        List<String?>.filled(launcherSlotCount, 'chrome'),
      );
      expect(store.value!.settings.syncIcons, isFalse);
      expect(store.value!.revision, before + launcherSlotCount + 1);
    },
  );
  test(
    'same foreground app launches still publish fresh activation confirmations',
    () async {
      final controller = DesktopController(
        store: MemoryDesktopConfigStore(),
        discovery: _Discovery(),
        actions: _Actions(),
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      await controller.executeRemote(
        const RemoteActionRequest.launchApplication('chrome'),
      );
      final first = controller.manifest.applicationActivationSequence;
      await controller.executeRemote(
        const RemoteActionRequest.launchApplication('chrome'),
      );
      expect(controller.manifest.applicationActivationSequence, first + 1);
      expect(controller.manifest.activatedApplicationId, 'chrome');
      expect(
        controller.manifest.applications
            .where((app) => app.foreground)
            .single
            .id,
        'chrome',
      );
    },
  );
  test(
    'sync off hides configured slots on the wire without destroying Desktop configuration',
    () async {
      final controller = DesktopController(
        store: MemoryDesktopConfigStore(),
        discovery: _Discovery(),
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      await controller.assignLauncherApp(11, 'chrome');
      await controller.updateSettings(
        controller.manifest.settings.copyWith(enableAppsSync: false),
      );
      final wire = DesktopManifest.fromJson(
        controller.manifest.toJson(forSync: true),
      );
      expect(
        wire.launcherApplicationIds,
        List<String?>.filled(launcherSlotCount, null),
      );
      expect(controller.launcherAppIds[11], 'chrome');
    },
  );
}
