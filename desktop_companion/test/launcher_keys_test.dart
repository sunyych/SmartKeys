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

      final reloaded = DesktopController(
        store: config,
        launcherKeyStore: launcher,
        discovery: _Discovery(),
      );
      await reloaded.initialize();
      expect(reloaded.launcherAppIds, appIds.take(8).toList());
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
}
