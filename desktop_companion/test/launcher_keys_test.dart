import 'package:flutter_test/flutter_test.dart';
import 'package:lumiakeys_protocol/lumiakeys_protocol.dart';
import 'package:lumiakeys_companion/desktop_controller.dart';

class _Discovery implements ApplicationDiscovery {
  @override
  Future<List<RemoteApplication>> refresh(List<RemoteApplication> apps) async =>
      apps;
}

void main() {
  test(
    'launcher slots remain exactly eight, ordered, local, and race-safe',
    () async {
      final config = MemoryDesktopConfigStore();
      final launcher = MemoryLauncherKeyStore();
      final controller = DesktopController(
        store: config,
        launcherKeyStore: launcher,
        discovery: _Discovery(),
      );
      await controller.initialize();
      final appIds = controller.manifest.applications
          .map((app) => app.id)
          .toList();
      expect(appIds.length, greaterThanOrEqualTo(8));
      await Future.wait([
        for (var index = 0; index < 8; index++)
          controller.assignLauncherApp(index, appIds[index]),
      ]);
      expect(controller.launcherAppIds, appIds.take(8).toList());
      expect(launcher.value, appIds.take(8).toList());
      final published = DesktopManifest.fromJson(
        controller.manifest.toJson(forSync: true),
      );
      expect(published.launcherApplicationIds, appIds.take(8).toList());

      final reloaded = DesktopController(
        store: config,
        launcherKeyStore: launcher,
        discovery: _Discovery(),
      );
      await reloaded.initialize();
      expect(reloaded.launcherAppIds, appIds.take(8).toList());
      expect(reloaded.manifest.revision, controller.manifest.revision);
      await expectLater(
        reloaded.assignLauncherApp(8, appIds.first),
        throwsRangeError,
      );
      await expectLater(
        reloaded.assignLauncherApp(0, 'arbitrary-command'),
        throwsFormatException,
      );
      controller.dispose();
      reloaded.dispose();
    },
  );

  test(
    'failed manifest revision save rolls back the local slot assignment',
    () async {
      final store = _FailNextSaveStore();
      final launcher = MemoryLauncherKeyStore();
      final controller = DesktopController(
        store: store,
        launcherKeyStore: launcher,
        discovery: _Discovery(),
      );
      await controller.initialize();
      final before = List<String?>.from(controller.launcherAppIds);
      store.failNextSave = true;

      await expectLater(
        controller.assignLauncherApp(
          0,
          controller.manifest.applications.first.id,
        ),
        throwsStateError,
      );
      expect(controller.launcherAppIds, before);
      expect(launcher.value, before);
      controller.dispose();
    },
  );

  test('migrates the previous Codex launcher slot to ChatGPT', () async {
    final launcher = MemoryLauncherKeyStore()
      ..value = ['codex', null, null, null, null, null, null, null];
    final controller = DesktopController(
      store: MemoryDesktopConfigStore(),
      launcherKeyStore: launcher,
      discovery: _Discovery(),
    );
    await controller.initialize();
    expect(controller.launcherAppIds.first, 'chatgpt');
    controller.dispose();
  });
}

class _FailNextSaveStore implements DesktopConfigStore {
  final MemoryDesktopConfigStore inner = MemoryDesktopConfigStore();
  bool failNextSave = false;

  @override
  Future<DesktopManifest?> load() => inner.load();

  @override
  Future<void> save(DesktopManifest manifest) {
    if (failNextSave) {
      failNextSave = false;
      throw StateError('simulated manifest storage failure');
    }
    return inner.save(manifest);
  }
}
