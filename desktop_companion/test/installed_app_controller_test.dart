import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumiakeys_protocol/lumiakeys_protocol.dart';
import 'package:lumiakeys_companion/desktop_actions.dart';
import 'package:lumiakeys_companion/desktop_controller.dart';
import 'package:lumiakeys_companion/installed_app_registry.dart';
import 'package:lumiakeys_companion/installed_app_launcher.dart';

class _DelayedActions extends DesktopActions {
  _DelayedActions(this.checked, this.started, this.channel);
  final Completer<bool> checked;
  final Completer<void> started;
  final MethodChannel channel;
  @override
  Future<void> activateInstalledApplication(String id) =>
      InstalledApplicationLauncher(
        resolve: (id) => registeredTargetResolver?.call(id),
        channel: channel,
        platformOverride: TargetPlatform.linux,
        targetExists: (_) {
          started.complete();
          return checked.future;
        },
      ).launch(id, authorize: installedLaunchAuthorizer);
}

class _Discovery implements ApplicationDiscovery {
  @override
  Future<List<RemoteApplication>> refresh(List<RemoteApplication> apps) async =>
      apps.map((app) => app.copyWith(detected: true)).toList();
}

class _Actions extends DesktopActions {
  final installed = <String>[];
  @override
  Future<void> activateInstalledApplication(String id) async {
    installed.add(id);
  }
}

InstalledLaunchTarget target(String key) => InstalledLaunchTarget.discovered(
  name: 'Installed $key',
  kind: InstalledLaunchKind.linuxDesktopEntry,
  identity: key,
  locator: '/usr/share/applications/$key.desktop',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'only selected missing labels persist and local GIcon paths never synchronize',
    () async {
      var found = [
        InstalledLaunchTarget.discovered(
          name: 'Private icon',
          kind: InstalledLaunchKind.linuxDesktopEntry,
          identity: 'private-icon',
          locator: '/usr/share/applications/private.desktop',
          iconKey: '/private/local/icons/product.svg',
        ),
        target('unselected'),
      ];
      final first = found.first.id;
      final dropped = found.last.id;
      final controller = DesktopController(
        store: MemoryDesktopConfigStore(),
        discovery: _Discovery(),
        installedRegistry: InstalledAppRegistry(
          discover: () async => found,
          validate: (_) async => true,
        ),
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      await controller.assignLauncherApp(0, first);
      expect(controller.manifest.applicationById(first)!.icon, 'apps');
      expect(
        controller.manifest.toJson(forSync: true).toString(),
        isNot(contains('/private/local/icons')),
      );
      found = [];
      await controller.refreshApplications();
      expect(controller.manifest.applicationById(first), isNotNull);
      expect(controller.manifest.applicationById(dropped), isNull);
      expect(
        controller.manifest.applications.where((app) => app.launchOnly),
        hasLength(1),
      );
    },
  );
  for (final revokeSlot in [true, false]) {
    test(
      'pending installed launch rechecks ${revokeSlot ? 'slot removal' : 'auto-launch disable'} before native handoff',
      () async {
        const channel = MethodChannel('test/controller-installed-race');
        var nativeCalls = 0;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (_) async {
              nativeCalls++;
              return true;
            });
        addTearDown(
          () => TestDefaultBinaryMessengerBinding
              .instance
              .defaultBinaryMessenger
              .setMockMethodCallHandler(channel, null),
        );
        final checked = Completer<bool>(), started = Completer<void>();
        final item = target('race');
        final controller = DesktopController(
          store: MemoryDesktopConfigStore(),
          discovery: _Discovery(),
          actions: _DelayedActions(checked, started, channel),
          installedRegistry: InstalledAppRegistry(
            discover: () async => [item],
            validate: (_) async => true,
          ),
        );
        addTearDown(controller.dispose);
        await controller.initialize();
        await controller.assignLauncherApp(0, item.id);
        final pending = controller.launchLauncherApp(0);
        final rejected = expectLater(pending, throwsStateError);
        await started.future;
        if (revokeSlot) {
          await controller.assignLauncherApp(0, null);
        } else {
          await controller.updateSettings(
            controller.manifest.settings.copyWith(autoLaunchApps: false),
          );
        }
        checked.complete(true);
        await rejected;
        expect(nativeCalls, 0);
      },
    );
  }
  test(
    'only assigned installed IDs sync and launch without faking foreground or granting shortcuts',
    () async {
      final entries = [target('one'), target('two')];
      final actions = _Actions();
      final registry = InstalledAppRegistry(
        discover: () async => entries,
        validate: (_) async => true,
      );
      final controller = DesktopController(
        store: MemoryDesktopConfigStore(),
        discovery: _Discovery(),
        actions: actions,
        installedRegistry: registry,
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      expect(
        controller.manifest.applications.where((app) => app.launchOnly),
        hasLength(2),
      );
      expect(
        controller.applicationsForCurrentPlatform.any((app) => app.launchOnly),
        false,
      );
      await expectLater(
        controller.executeRemote(
          RemoteActionRequest.launchApplication(entries.first.id),
        ),
        throwsFormatException,
      );
      await controller.assignLauncherApp(0, entries.first.id);
      final before = controller.manifest.applicationActivationSequence;
      await controller.executeRemote(
        RemoteActionRequest.launchApplication(entries.first.id),
      );
      expect(actions.installed, [entries.first.id]);
      expect(controller.manifest.applicationActivationSequence, before);
      expect(
        controller.manifest.applicationById(entries.first.id)!.foreground,
        false,
      );
      final sync = controller.manifest.toJson(forSync: true);
      final rows = sync['applications'] as List;
      expect(
        rows
            .where((row) => (row as Map)['launchOnly'] == true)
            .map((row) => (row as Map)['id']),
        [entries.first.id],
      );
      expect(sync.toString(), isNot(contains('/usr/share/applications')));
      await expectLater(
        controller.updateApplication(
          controller.manifest
              .applicationById(entries.first.id)!
              .copyWith(executable: '/unsafe'),
        ),
        throwsFormatException,
      );
    },
  );
  test(
    'uninstall preserves a saved slot through refresh and restart and refuses its launch',
    () async {
      var found = [target('one')];
      final id = found.single.id;
      final store = MemoryDesktopConfigStore();
      final actions = _Actions();
      final registry = InstalledAppRegistry(
        discover: () async => found,
        validate: (_) async => true,
      );
      final controller = DesktopController(
        store: store,
        discovery: _Discovery(),
        actions: actions,
        installedRegistry: registry,
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      await controller.assignLauncherApp(0, id);
      found = [];
      await controller.refreshApplications();
      expect(controller.launcherAppIds.first, id);
      expect(controller.manifest.applicationById(id)!.detected, false);
      await expectLater(controller.launchLauncherApp(0), throwsFormatException);
      expect(actions.installed, isEmpty);
      final restarted = DesktopController(
        store: store,
        discovery: _Discovery(),
        installedRegistry: InstalledAppRegistry(),
      );
      addTearDown(restarted.dispose);
      await restarted.initialize();
      expect(restarted.launcherAppIds.first, id);
      expect(restarted.manifest.applicationById(id)!.detected, false);
    },
  );
  test(
    'legacy raw paths commands and launch arguments are rejected before any native invocation',
    () async {
      final actions = _Actions();
      final controller = DesktopController(
        store: MemoryDesktopConfigStore(),
        discovery: _Discovery(),
        actions: actions,
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      for (final payload in [
        {'kind': 'launch', 'target': '/usr/bin/anything'},
        {'kind': 'launch', 'target': 'cmd.exe'},
        {'kind': 'launch', 'target': 'chrome', 'args': '--unsafe'},
      ]) {
        await expectLater(
          Future.sync(() => controller.executeLegacy(payload)),
          throwsFormatException,
        );
      }
      expect(actions.installed, isEmpty);
    },
  );
}
