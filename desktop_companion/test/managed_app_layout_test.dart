import 'package:flutter_test/flutter_test.dart';
import 'dart:io';

import 'package:lumiakeys_protocol/lumiakeys_protocol.dart';
import 'package:lumiakeys_companion/desktop_actions.dart';
import 'package:lumiakeys_companion/desktop_controller.dart';

class _NoopDiscovery implements ApplicationDiscovery {
  @override
  Future<List<RemoteApplication>> refresh(List<RemoteApplication> apps) async =>
      apps;
}

class _RecordingActions extends DesktopActions {
  final activated = <String>[];
  final executed = <String>[];

  @override
  Future<void> activateApplication(RemoteApplication app) async {
    activated.add(app.id);
  }

  @override
  Future<void> executeButton(
    RemoteShortcutButton button,
    DesktopManifest manifest, {
    String? expectedAppId,
  }) async {
    executed.add('${button.id}:$expectedAppId');
  }
}

void main() {
  test('only exposes Safari in app pickers on macOS', () async {
    final manifest = DesktopManifest.starter().copyWith(
      applications: DesktopManifest.starter().applications
          .map((app) => app.id == 'safari' ? app.copyWith(detected: true) : app)
          .toList(growable: false),
    );
    final controller = DesktopController(
      store: MemoryDesktopConfigStore()..value = manifest,
      discovery: _NoopDiscovery(),
    );
    await controller.initialize();

    expect(
      controller.applicationsForCurrentPlatform.any(
        (app) => app.id == 'safari',
      ),
      Platform.isMacOS,
    );
    expect(controller.manifest.applicationById('safari')?.detected, isTrue);
    expect(
      controller.applicationsForCurrentPlatform.any((app) => app.id == 'edge'),
      isTrue,
    );
    final edgeLayout = controller.manifest.layoutById('app.edge')!;
    final edgeBack = edgeLayout.buttons.singleWhere(
      (button) => button.id == 'edge.back',
    );
    expect(
      edgeBack.shortcut,
      Platform.isMacOS ? ['PRIMARY', '['] : ['ALT', 'LEFT'],
    );
    controller.dispose();
  });

  test('Desktop computer identity is created once and persisted', () async {
    final store = MemoryDesktopConfigStore()..value = DesktopManifest.starter();
    final first = DesktopController(store: store, discovery: _NoopDiscovery());
    await first.initialize();
    final identity = first.manifest.computerId;
    expect(identity, matches(RegExp(r'^[0-9a-f]{32}$')));
    expect(store.value!.computerId, identity);
    first.dispose();

    final next = DesktopController(store: store, discovery: _NoopDiscovery());
    await next.initialize();
    expect(next.manifest.computerId, identity);
    next.dispose();
  });

  test(
    'invalid legacy computer identity is replaced during migration',
    () async {
      final store = MemoryDesktopConfigStore()
        ..value = DesktopManifest.starter().copyWith(computerId: 'old-host-id');
      final controller = DesktopController(
        store: store,
        discovery: _NoopDiscovery(),
      );
      await controller.initialize();
      expect(
        controller.manifest.computerId,
        matches(RegExp(r'^[0-9a-f]{32}$')),
      );
      expect(store.value!.computerId, controller.manifest.computerId);
      controller.dispose();
    },
  );

  test(
    'managed apps need a detected install and activate by fixed ID',
    () async {
      final starter = DesktopManifest.starter();
      final stored = starter.copyWith(
        applications: starter.applications
            .map(
              (app) => app.copyWith(
                detected: app.id == 'firefox' || app.id == 'safari',
              ),
            )
            .toList(growable: false),
      );
      final actions = _RecordingActions();
      final controller = DesktopController(
        store: MemoryDesktopConfigStore()..value = stored,
        actions: actions,
        discovery: _NoopDiscovery(),
      );
      await controller.initialize();

      await controller.executeRemote(
        const RemoteActionRequest.launchApplication('firefox'),
      );
      expect(actions.activated, ['firefox']);
      await expectLater(
        controller.executeRemote(
          const RemoteActionRequest.launchApplication('zoom'),
        ),
        throwsA(isA<StateError>()),
      );
      expect(actions.activated, ['firefox']);
      controller.dispose();
    },
  );

  test('Microsoft Edge has a managed browser layout and launch path', () async {
    final starter = DesktopManifest.starter();
    expect(starter.applicationById('edge')?.name, 'Microsoft Edge');
    expect(starter.layoutById('app.edge')?.buttons, isNotEmpty);
    final stored = starter.copyWith(
      applications: starter.applications
          .map((app) => app.copyWith(detected: app.id == 'edge'))
          .toList(growable: false),
    );
    final actions = _RecordingActions();
    final controller = DesktopController(
      store: MemoryDesktopConfigStore()..value = stored,
      actions: actions,
      discovery: _NoopDiscovery(),
    );
    await controller.initialize();
    await controller.executeRemote(
      const RemoteActionRequest.launchApplication('edge'),
    );
    expect(actions.activated, ['edge']);
    controller.dispose();
  });

  test('managed meeting shortcuts require their own foreground app', () async {
    final starter = DesktopManifest.starter();
    final stored = starter.copyWith(
      applications: starter.applications
          .map((app) => app.copyWith(detected: app.id == 'teams'))
          .toList(growable: false),
    );
    final actions = _RecordingActions();
    var isTeamsForeground = false;
    final controller = DesktopController(
      store: MemoryDesktopConfigStore()..value = stored,
      actions: actions,
      discovery: _NoopDiscovery(),
      foregroundProbe: (app) async => app.id == 'teams' && isTeamsForeground,
    );
    await controller.initialize();

    await expectLater(
      controller.executeRemote(const RemoteActionRequest.button('teams.mute')),
      throwsA(isA<StateError>()),
    );
    expect(actions.executed, isEmpty);
    isTeamsForeground = true;
    await controller.executeRemote(
      const RemoteActionRequest.button('teams.mute'),
    );
    expect(actions.executed, ['teams.mute:teams']);
    controller.dispose();
  });

  test(
    'legacy desktop shortcuts remain outside the new managed guard',
    () async {
      final actions = _RecordingActions();
      final controller = DesktopController(
        store: MemoryDesktopConfigStore(),
        actions: actions,
        discovery: _NoopDiscovery(),
        foregroundProbe: (_) async => false,
      );
      await controller.initialize();

      await controller.executeRemote(
        const RemoteActionRequest.button('vscode.run'),
      );
      await controller.executeRemote(
        const RemoteActionRequest.button('codex.voice'),
      );
      expect(actions.executed, ['vscode.run:null', 'codex.voice:null']);
      controller.dispose();
    },
  );

  test('Teams defaults do not include its destructive end-call shortcut', () {
    final teams = DesktopManifest.starter().layoutById('app.teams')!;
    expect(teams.buttons.map((button) => button.id), [
      'teams.mute',
      'teams.video',
      'teams.hand',
    ]);
  });
}
