import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumiakeys_protocol/lumiakeys_protocol.dart';
import 'package:smart_keys/models/config.dart';
import 'package:smart_keys/models/computer_setup.dart';
import 'package:smart_keys/services/companion_service.dart';
import 'package:smart_keys/services/hid_service.dart';

import 'test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('computer shortcut setup', () {
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test('parses common chords to Android keyboard HID actions', () {
      expect(
        parseComputerShortcut('Ctrl+Alt+F12')?.toJson(),
        const HidAction(
          type: ActionType.keyboard,
          keyCode: 'KEY_F12',
          modifiers: ['LEFT_CTRL', 'LEFT_ALT'],
        ).toJson(),
      );
      expect(
        parseComputerShortcut('Command+Shift+[')?.toJson(),
        const HidAction(
          type: ActionType.keyboard,
          keyCode: 'KEY_LEFT_BRACKET',
          modifiers: ['LEFT_META', 'LEFT_SHIFT'],
        ).toJson(),
      );
      expect(parseComputerShortcut('Control+Control+A'), isNull);
      expect(parseComputerShortcut('Ctrl+Paste'), isNull);
      expect(parseComputerShortcut('Ctrl++A'), isNull);
    });

    test('every built-in computer shortcut default parses', () {
      for (final target in [
        const ComputerTarget(
          id: 'desktop:windows',
          name: 'Windows',
          mode: ComputerMode.standalone,
          isApple: false,
        ),
        const ComputerTarget(
          id: 'desktop:macos',
          name: 'macOS',
          mode: ComputerMode.standalone,
          isApple: true,
        ),
      ]) {
        for (final application in computerApplications) {
          for (final shortcut in computerShortcutsFor(application.category)) {
            final chord = defaultComputerShortcut(
              target,
              application,
              shortcut.id,
            );
            if (chord != null) {
              expect(
                parseComputerShortcut(chord),
                isNotNull,
                reason:
                    '${target.name}/${application.id}/${shortcut.id}: $chord',
              );
            }
          }
        }
      }
    });

    test('round-trips host setups and ignores invalid legacy data', () {
      final original = ComputerSetup(
        applicationIds: ['chrome', 'chrome', 'unknown app'],
        bindings: const {
          'chrome': {'launch': 'Ctrl+Alt+1', 'noSuchAction': 'Ctrl+X'},
          'unknown': {'launch': 'Ctrl+Alt+2'},
        },
      );
      expect(original.applicationIds, ['chrome']);
      expect(original.bindingFor('chrome', 'launch'), 'Ctrl+Alt+1');
      expect(original.bindingFor('chrome', 'noSuchAction'), isNull);
      expect(original.bindingFor('unknown', 'launch'), isNull);
      final decoded = ComputerSetup.fromJson(original.toJson());
      expect(decoded.applicationIds, ['chrome']);
      expect(decoded.bindingFor('chrome', 'launch'), 'Ctrl+Alt+1');
      expect(
        ComputerSetup.fromJson({
          'applicationIds': {},
          'bindings': [],
        }).applicationIds,
        isEmpty,
      );
    });

    test('new configuration preserves per-computer shortcut setup', () {
      final original = testConfig().copyWith(
        computerSetups: {
          'bluetooth:00:11:22:33:44:55': ComputerSetup(
            applicationIds: const ['codex'],
            bindings: const {
              'codex': {'launch': 'Ctrl+Alt+1', 'voiceMode': 'Ctrl+Alt+2'},
            },
          ),
        },
      );
      final restored = AppConfig.fromJson(original.toJson());
      expect(restored.schemaVersion, AppConfig.currentSchemaVersion);
      expect(
        restored.computerSetups['bluetooth:00:11:22:33:44:55']?.bindingFor(
          'codex',
          'voiceMode',
        ),
        'Ctrl+Alt+2',
      );
      final oldConfig = Map<String, dynamic>.of(original.toJson())
        ..remove('computerSetups')
        ..['schemaVersion'] = 7;
      expect(AppConfig.fromJson(oldConfig).computerSetups, isEmpty);
    });

    test(
      'Android Bluetooth uses isolated per-host setup and emits exact keys',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        final harness = await TestHarness.create(seedComputerSetup: false);
        addTearDown(harness.dispose);
        final controller = harness.controller;
        expect(controller.computerMode, ComputerMode.standalone);
        final target = controller.activeComputer!;
        expect(target.id, 'bluetooth:00:11:22:33:44:55');

        final bindings = {
          for (final entry in {
            'launch': 'Ctrl+Alt+1',
            'voiceMode': 'Ctrl+Alt+2',
            'voiceInput': 'Ctrl+Alt+3',
            'cancelClear': 'Escape',
            'previousChat': 'Ctrl+Alt+4',
            'nextChat': 'Ctrl+Alt+5',
            'nextProject': 'Ctrl+Alt+6',
          }.entries)
            entry.key: entry.value,
        };
        await controller.saveComputerSetup(
          target,
          ComputerSetup(
            applicationIds: const ['codex'],
            bindings: {'codex': bindings},
          ),
        );
        expect(controller.isStandaloneSetupComplete, isTrue);
        expect(controller.availableComputerApplications.map((app) => app.id), [
          'codex',
        ]);

        await controller.testComputerLaunch(target, 'codex', 'Ctrl+Alt+1');
        expect(
          harness.hid.steppedActions.single.toJson(),
          const HidAction(
            type: ActionType.keyboard,
            keyCode: 'KEY_1',
            modifiers: ['LEFT_CTRL', 'LEFT_ALT'],
          ).toJson(),
        );
        await controller.executeStandaloneShortcut(target, 'codex', 'send');
        expect(
          harness.hid.steppedActions.last.toJson(),
          const HidAction(
            type: ActionType.keyboard,
            keyCode: 'KEY_ENTER',
          ).toJson(),
        );

        harness.hid.selectedHost.value = const HidHost(
          id: 'other-host',
          name: 'Other Computer',
          address: '00:AA:BB:CC:DD:EE',
        );
        expect(controller.activeComputer!.id, 'bluetooth:00:aa:bb:cc:dd:ee');
        expect(controller.availableComputerApplications, isEmpty);
        await expectLater(
          controller.executeStandaloneShortcut(target, 'codex', 'send'),
          throwsA(isA<StateError>()),
        );
      },
    );

    test('voice actions must use distinct, valid key combinations', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final harness = await TestHarness.create(seedComputerSetup: false);
      addTearDown(harness.dispose);
      final target = harness.controller.activeComputer!;
      final bindings = <String, String>{
        'launch': 'Ctrl+Alt+1',
        'voiceMode': 'Control+Alt+2',
        'voiceInput': 'Ctrl+Alt+2',
        'cancelClear': 'Escape',
        'previousChat': 'Ctrl+Alt+4',
        'nextChat': 'Ctrl+Alt+5',
        'nextProject': 'Ctrl+Alt+6',
      };
      await expectLater(
        harness.controller.saveComputerSetup(
          target,
          ComputerSetup(
            applicationIds: const ['codex'],
            bindings: {'codex': bindings},
          ),
        ),
        throwsA(isA<FormatException>()),
      );
      expect(harness.controller.activeComputerSetup, isNull);
    });

    test(
      'retains accepted Desktop mode during same-session sync errors',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        final harness = await TestHarness.create(seedComputerSetup: false);
        addTearDown(harness.dispose);
        final companion = harness.companion;
        companion.host.value = connectedCompanionHost;
        companion.syncedManifest.value = DesktopManifest.starter().copyWith(
          computerId: 'test-desktop-1',
        );
        companion.status.value = CompanionSyncStatus.ready;
        expect(harness.controller.computerMode, ComputerMode.advanced);
        expect(harness.controller.activeComputer!.id, 'desktop:test-desktop-1');

        companion.status.value = CompanionSyncStatus.syncing;
        companion.errors.value = 'Manifest refresh pending';
        expect(harness.controller.computerMode, ComputerMode.advanced);
        expect(harness.controller.activeComputer!.id, 'desktop:test-desktop-1');

        companion.host.value = const CompanionHost(
          name: 'Unpaired PC',
          platform: 'windows',
          address: '192.0.2.3',
          port: 45832,
          token: 'other-token',
          protocolVersion: 2,
          capabilities: {'manifest'},
        );
        expect(harness.controller.computerMode, ComputerMode.disconnected);
      },
    );

    test(
      'uses the newly selected Bluetooth computer after Desktop disconnect',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        final harness = await TestHarness.create(seedComputerSetup: false);
        addTearDown(harness.dispose);
        final companion = harness.companion;
        companion.host.value = connectedCompanionHost;
        companion.syncedManifest.value = DesktopManifest.starter().copyWith(
          computerId: 'desktop-first',
        );
        companion.status.value = CompanionSyncStatus.ready;
        expect(harness.controller.computerMode, ComputerMode.advanced);

        harness.hid.selectedHost.value = const HidHost(
          id: 'new-bluetooth-host',
          name: 'Second PC',
          address: '00:AA:BB:CC:DD:EE',
        );
        companion.host.value = null;
        companion.status.value = CompanionSyncStatus.discovering;

        expect(harness.controller.computerMode, ComputerMode.standalone);
        expect(
          harness.controller.activeComputer?.id,
          'bluetooth:00:aa:bb:cc:dd:ee',
        );
      },
    );

    test(
      'Desktop selection keeps detected app IDs and setup on that host',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        final harness = await TestHarness.create(seedComputerSetup: false);
        addTearDown(harness.dispose);
        final controller = harness.controller;
        final companion = harness.companion;
        final starter = DesktopManifest.starter();
        companion.host.value = connectedCompanionHost;
        companion.syncedManifest.value = starter.copyWith(
          computerId: 'desktop-selected-apps',
          applications: [
            for (final app in starter.applications)
              if (app.id == 'codex') app.copyWith(detected: true),
            const RemoteApplication(
              id: 'vscode',
              name: 'Visual Studio Code',
              icon: 'code',
              executable: 'Code',
              layoutId: 'app.vscode',
              detected: true,
            ),
          ],
        );
        companion.status.value = CompanionSyncStatus.ready;
        final target = controller.activeComputer!;
        expect(
          controller.computerApplicationsOnActiveComputer.map(
            (application) => application.id,
          ),
          containsAll(['codex', 'vscode']),
        );

        await controller.saveComputerSetup(
          target,
          ComputerSetup(applicationIds: const ['codex', 'vscode']),
        );
        expect(controller.isActiveComputerSetupComplete, isTrue);
        expect(controller.availableComputerApplications.map((app) => app.id), [
          'codex',
          'vscode',
        ]);
        expect(
          AppConfig.fromJson(
            controller.config.toJson(),
          ).computerSetups[target.id]?.applicationIds,
          ['codex', 'vscode'],
        );
        companion.syncedManifest.value = companion.syncedManifest.value!
            .copyWith(
              settings: companion.syncedManifest.value!.settings.copyWith(
                enableAppsSync: false,
              ),
            );
        expect(controller.isActiveComputerSetupComplete, isTrue);
        expect(controller.availableComputerApplications, isEmpty);
        await controller.saveComputerSetup(
          target,
          ComputerSetup(applicationIds: const []),
        );
        expect(controller.isActiveComputerSetupComplete, isTrue);
      },
    );

    test('iOS requires an authenticated Desktop connection', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final harness = await TestHarness.create(seedComputerSetup: false);
      addTearDown(harness.dispose);
      expect(harness.controller.computerMode, ComputerMode.disconnected);

      harness.companion.host.value = connectedCompanionHost;
      harness.companion.syncedManifest.value = DesktopManifest.starter();
      harness.companion.status.value = CompanionSyncStatus.ready;
      expect(harness.controller.computerMode, ComputerMode.advanced);
    });
  });
}
