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

    test('ChatGPT and app defaults are prefilled only where documented', () {
      ComputerTarget target(ComputerOperatingSystem os) => ComputerTarget(
        id: 'desktop:${os.name}',
        name: os.label,
        mode: ComputerMode.standalone,
        isApple: os == ComputerOperatingSystem.macos,
        operatingSystem: os,
      );
      final chatgpt = computerApplicationById('chatgpt')!;

      expect(
        defaultComputerShortcut(
          target(ComputerOperatingSystem.windows),
          chatgpt,
          'chatView',
        ),
        'Alt+1',
      );
      expect(
        defaultComputerShortcut(
          target(ComputerOperatingSystem.windows),
          chatgpt,
          'startVoice',
        ),
        isNull,
      );
      expect(
        defaultComputerShortcut(
          target(ComputerOperatingSystem.macos),
          chatgpt,
          'launch',
        ),
        'Option+Space',
      );
      expect(
        defaultComputerShortcut(
          target(ComputerOperatingSystem.macos),
          chatgpt,
          'startVoice',
        ),
        'Ctrl+Shift+V',
      );
      expect(
        defaultComputerShortcut(
          target(ComputerOperatingSystem.macos),
          chatgpt,
          'stopVoice',
        ),
        isNull,
      );
      expect(
        defaultComputerShortcut(
          target(ComputerOperatingSystem.windows),
          computerApplicationById('teams')!,
          'mute',
        ),
        'Ctrl+Shift+M',
      );
      expect(
        defaultComputerShortcut(
          target(ComputerOperatingSystem.windows),
          computerApplicationById('cursor')!,
          'cancelClear',
        ),
        'Ctrl+Shift+Backspace',
      );
    });

    test('browser choices include Edge and show Safari only on macOS', () {
      final macApplications = computerApplicationsForOperatingSystem(
        ComputerOperatingSystem.macos,
      );
      final windowsApplications = computerApplicationsForOperatingSystem(
        ComputerOperatingSystem.windows,
      );
      final unknownApplications = computerApplicationsForOperatingSystem(null);

      expect(macApplications.map((app) => app.id), contains('safari'));
      expect(macApplications.map((app) => app.id), contains('edge'));
      expect(windowsApplications.map((app) => app.id), contains('edge'));
      expect(
        windowsApplications.map((app) => app.id),
        isNot(contains('safari')),
      );
      expect(unknownApplications.map((app) => app.id), contains('edge'));
      expect(
        unknownApplications.map((app) => app.id),
        isNot(contains('safari')),
      );
      expect(
        isComputerApplicationSupportedOn(
          computerApplicationById('safari')!,
          ComputerOperatingSystem.linux,
        ),
        isFalse,
      );
    });

    test('round-trips host setups and ignores invalid legacy data', () {
      final original = ComputerSetup(
        applicationIds: ['chrome', 'chrome', 'unknown app'],
        operatingSystem: ComputerOperatingSystem.linux,
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
      expect(decoded.operatingSystem, ComputerOperatingSystem.linux);
      expect(decoded.setupComplete, isTrue);
      expect(decoded.bindingFor('chrome', 'launch'), 'Ctrl+Alt+1');
      expect(
        ComputerSetup.fromJson({
          'applicationIds': {},
          'bindings': [],
        }).applicationIds,
        isEmpty,
      );
      expect(
        ComputerSetup.fromJson({
          'applicationIds': const [],
          'bindings': const {},
          'operatingSystem': 'windows',
          'setupComplete': false,
        }).setupComplete,
        isFalse,
      );
    });

    test('migrates legacy Codex setup into ChatGPT Codex mode controls', () {
      final migrated = ComputerSetup.fromJson({
        'applicationIds': ['codex', 'chatgpt', 'codex'],
        'bindings': {
          'codex': {
            'launch': 'Alt+Shift+1',
            'newChat': 'Ctrl+N',
            'voiceMode': 'Ctrl+Alt+V',
            'send': 'Enter',
            'focusInput': 'Escape',
            'project': 'Ctrl+Alt+Shift+O',
            'review': 'Ctrl+Shift+G',
            'sidebar': 'Ctrl+Shift+B',
          },
          'chatgpt': {'newChat': 'Alt+N', 'startVoice': 'Ctrl+Shift+V'},
        },
      });

      expect(migrated.applicationIds, ['chatgpt']);
      expect(migrated.bindingFor('chatgpt', 'codexMode'), 'Alt+Shift+1');
      expect(migrated.bindingFor('chatgpt', 'newChat'), 'Alt+N');
      expect(migrated.bindingFor('chatgpt', 'codex.voiceMode'), 'Ctrl+Alt+V');
      expect(migrated.bindingFor('chatgpt', 'codex.send'), 'Enter');
      expect(migrated.bindingFor('chatgpt', 'codex.focusInput'), 'Escape');
      expect(
        migrated.bindingFor('chatgpt', 'codex.project'),
        'Ctrl+Alt+Shift+O',
      );
      expect(migrated.bindingFor('chatgpt', 'codex.review'), 'Ctrl+Shift+G');
      expect(migrated.bindingFor('chatgpt', 'sidebar'), 'Ctrl+Shift+B');
      expect(
        computerShortcutsFor(
          ComputerAppCategory.chat,
        ).map((action) => action.id),
        contains('sidebar'),
      );
      expect(
        computerShortcutsFor(
          ComputerAppCategory.chat,
        ).map((action) => action.id),
        isNot(contains('codex.sidebar')),
      );
      expect(migrated.bindingFor('chatgpt', 'startVoice'), 'Ctrl+Shift+V');
      expect(
        ComputerSetup.fromJson(
          migrated.toJson(),
        ).bindingFor('chatgpt', 'codexMode'),
        'Alt+Shift+1',
      );
      expect(
        computerApplications.map((app) => app.id),
        isNot(contains('codex')),
      );
      expect(computerApplicationById('codex')?.id, 'chatgpt');
      expect(
        computerApplicationById('codex')?.category,
        ComputerAppCategory.chat,
      );
      expect(
        computerApplications.map((app) => app.id),
        containsAll(['claude', 'cursor']),
      );
      expect(
        computerShortcutsFor(
          ComputerAppCategory.chat,
        ).map((action) => action.id),
        isNot(contains('codex.newChat')),
      );
    });

    test(
      'OS-only setup persists per Bluetooth address and stays incomplete',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        final harness = await TestHarness.create(seedComputerSetup: false);
        addTearDown(harness.dispose);
        final controller = harness.controller;
        final firstTarget = controller.activeComputer!;

        await controller.saveComputerOperatingSystem(
          firstTarget,
          ComputerOperatingSystem.macos,
        );
        expect(
          controller.activeComputerSetup?.operatingSystem,
          ComputerOperatingSystem.macos,
        );
        expect(controller.activeComputerSetup?.setupComplete, isFalse);
        expect(controller.isActiveComputerSetupComplete, isFalse);

        harness.hid.selectedHost.value = const HidHost(
          id: 'secondary',
          name: 'Windows Computer',
          address: 'AA:BB:CC:DD:EE:FF',
        );
        final secondTarget = controller.activeComputer!;
        await controller.saveComputerOperatingSystem(
          secondTarget,
          ComputerOperatingSystem.windows,
        );
        expect(
          controller.activeComputerSetup?.operatingSystem,
          ComputerOperatingSystem.windows,
        );

        harness.hid.selectedHost.value = const HidHost(
          id: 'test-host',
          name: 'Test Computer',
          address: '00:11:22:33:44:55',
        );
        expect(controller.activeComputer!.id, firstTarget.id);
        expect(
          controller.activeComputerSetup?.operatingSystem,
          ComputerOperatingSystem.macos,
        );
        expect(controller.activeComputerSetup?.setupComplete, isFalse);
        expect(
          controller.config.computerSetups[secondTarget.id]?.operatingSystem,
          ComputerOperatingSystem.windows,
        );
      },
    );

    test('non-macOS filters but preserves an existing Safari setup', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final existingSafari = ComputerSetup(
        applicationIds: const ['safari'],
        operatingSystem: ComputerOperatingSystem.macos,
        bindings: const {
          'safari': {'launch': 'Command+Option+1'},
        },
      );
      final harness = await TestHarness.create(
        seedComputerSetup: false,
        config: testConfig().copyWith(
          computerSetups: {'bluetooth:00:11:22:33:44:55': existingSafari},
        ),
      );
      addTearDown(harness.dispose);
      final controller = harness.controller;
      await controller.saveComputerOperatingSystem(
        controller.activeComputer!,
        ComputerOperatingSystem.windows,
      );
      expect(controller.activeComputerSetup?.setupComplete, isTrue);
      expect(
        controller.computerApplicationsOnActiveComputer.map((app) => app.id),
        isNot(contains('safari')),
      );
      expect(controller.availableComputerApplications, isEmpty);

      await controller.saveComputerSetup(
        controller.activeComputer!,
        ComputerSetup(
          applicationIds: const ['edge'],
          operatingSystem: ComputerOperatingSystem.windows,
          bindings: const {
            'edge': {'launch': 'Ctrl+Alt+2'},
          },
        ),
      );
      expect(
        controller.activeComputerSetup?.applicationIds,
        containsAll(['edge', 'safari']),
      );
      expect(
        controller.activeComputerSetup?.bindingFor('safari', 'launch'),
        'Command+Option+1',
      );
      expect(controller.availableComputerApplications.map((app) => app.id), [
        'edge',
      ]);
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
          'chatgpt',
          'codex.voiceMode',
        ),
        'Ctrl+Alt+2',
      );
      final oldConfig = Map<String, dynamic>.of(original.toJson())
        ..remove('computerSetups')
        ..['schemaVersion'] = 7;
      expect(AppConfig.fromJson(oldConfig).computerSetups, isEmpty);
    });

    test('beginner mode defaults on and persists with computer OS', () async {
      expect(AppPreferences.fromJson(null).beginnerMode, isTrue);
      final original = testConfig().copyWith(
        preferences: const AppPreferences(beginnerMode: false),
        computerSetups: {
          'bluetooth:00:11:22:33:44:55': ComputerSetup(
            applicationIds: const [],
            operatingSystem: ComputerOperatingSystem.windows,
          ),
        },
      );
      final restored = AppConfig.fromJson(original.toJson());
      expect(restored.preferences.beginnerMode, isFalse);
      expect(
        restored.computerSetups['bluetooth:00:11:22:33:44:55']?.operatingSystem,
        ComputerOperatingSystem.windows,
      );

      final harness = await TestHarness.create(seedComputerSetup: false);
      addTearDown(harness.dispose);
      await harness.controller.setBeginnerMode(false);
      expect(harness.controller.config.preferences.beginnerMode, isFalse);
      expect(harness.repository.value.preferences.beginnerMode, isFalse);
    });

    test(
      'verified operating system beats the legacy shortcut preference',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        final config = testConfig().copyWith(
          preferences: const AppPreferences(
            shortcutPlatform: ShortcutPlatform.apple,
          ),
          computerSetups: {
            'bluetooth:00:11:22:33:44:55': ComputerSetup(
              applicationIds: const [],
              operatingSystem: ComputerOperatingSystem.linux,
            ),
          },
        );
        final harness = await TestHarness.create(
          config: config,
          seedComputerSetup: false,
        );
        addTearDown(harness.dispose);
        final target = harness.controller.activeComputer!;
        expect(target.operatingSystem, ComputerOperatingSystem.linux);
        expect(target.isApple, isFalse);
        expect(
          harness.controller.effectiveShortcutPlatform,
          ShortcutPlatform.windowsLinux,
        );

        await harness.controller.updateShortcutPlatform(
          ShortcutPlatform.windowsLinux,
        );
        harness.hid.selectedHost.value = const HidHost(
          id: 'hinted-mac',
          name: 'MacBook Pro',
          address: 'AA:BB:CC:DD:EE:FF',
        );
        final hintedTarget = harness.controller.activeComputer!;
        expect(hintedTarget.operatingSystem, ComputerOperatingSystem.macos);
        expect(hintedTarget.isApple, isFalse);
        expect(
          harness.controller.effectiveShortcutPlatform,
          ShortcutPlatform.windowsLinux,
        );

        final legacyTarget = const ComputerTarget(
          id: 'legacy',
          name: 'MacBook Pro',
          mode: ComputerMode.standalone,
          isApple: true,
        );
        expect(legacyTarget.isApple, isTrue);
        expect(legacyTarget.operatingSystem, isNull);
        final confirmed = legacyTarget.withOperatingSystem(
          ComputerOperatingSystem.windows,
        );
        expect(confirmed.operatingSystem, ComputerOperatingSystem.windows);
        expect(confirmed.isApple, isFalse);
      },
    );

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
          'chatgpt',
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
      'saves app selection before required shortcuts are configured',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        final harness = await TestHarness.create(seedComputerSetup: false);
        addTearDown(harness.dispose);
        final controller = harness.controller;
        final target = controller.activeComputer!;

        await controller.saveComputerSetup(
          target,
          ComputerSetup(
            applicationIds: const ['codex'],
            bindings: {
              'codex': {'voiceMode': 'Ctrl+Alt+2'},
            },
          ),
        );

        expect(controller.isActiveComputerSetupComplete, isTrue);
        expect(controller.activeComputerSetup?.applicationIds, ['chatgpt']);
        expect(
          harness.repository.value.computerSetups[target.id]?.bindingFor(
            'codex',
            'voiceInput',
          ),
          isNull,
        );

        // Explicit launch actions remain available to callers. An unset launch
        // binding is a no-op, while other missing actions are still rejected.
        await controller.executeStandaloneShortcut(target, 'codex', 'launch');
        expect(harness.hid.steppedActions, isEmpty);
        await expectLater(
          controller.executeStandaloneShortcut(target, 'codex', 'voiceInput'),
          throwsA(isA<StateError>()),
        );
        expect(harness.hid.steppedActions, isEmpty);
      },
    );

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
        await harness.controller.updateShortcutPlatform(
          ShortcutPlatform.windowsLinux,
        );
        expect(
          harness.controller.activeComputer!.operatingSystem,
          ComputerOperatingSystem.macos,
        );
        expect(
          harness.controller.effectiveShortcutPlatform,
          ShortcutPlatform.apple,
        );

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
              if (app.id == 'chatgpt') app.copyWith(detected: true),
            const RemoteApplication(
              id: 'codex',
              name: 'Codex / ChatGPT',
              icon: 'code',
              executable: 'ChatGPT',
              layoutId: 'chatgpt',
              detected: true,
            ),
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
          containsAll(['chatgpt', 'vscode']),
        );

        await controller.saveComputerSetup(
          target,
          ComputerSetup(
            applicationIds: const ['chatgpt', 'vscode'],
            operatingSystem: ComputerOperatingSystem.windows,
          ),
        );
        expect(controller.isActiveComputerSetupComplete, isTrue);
        expect(
          controller.activeComputerSetup?.operatingSystem,
          ComputerOperatingSystem.macos,
        );
        expect(controller.availableComputerApplications.map((app) => app.id), [
          'chatgpt',
          'vscode',
        ]);
        expect(
          AppConfig.fromJson(
            controller.config.toJson(),
          ).computerSetups[target.id]?.applicationIds,
          ['chatgpt', 'vscode'],
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
