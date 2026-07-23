import 'package:flutter_test/flutter_test.dart';
import 'package:lumiakeys_protocol/lumiakeys_protocol.dart';
import 'package:smart_keys/controllers/app_controller.dart';
import 'package:smart_keys/models/config.dart';
import 'package:smart_keys/services/hid_service.dart';
import 'package:smart_keys/services/companion_service.dart';

import 'test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'profile switch releases input before retaining the HID connection',
    () async {
      final harness = await TestHarness.create(
        config: testConfig(
          profiles: [
            profile(),
            profile(id: 'profile_design', name: 'Design', firstLabel: 'Brush'),
          ],
        ),
      );
      addTearDown(harness.dispose);

      await harness.controller.pressButton(
        harness.controller.activeProfile.buttons.first,
      );
      await harness.controller.switchProfile('profile_design');

      expect(
        harness.hid.calls,
        containsAllInOrder(['press:KEY_C', 'releaseAllKeys']),
      );
      expect(harness.controller.activeProfile.name, 'Design');
      expect(harness.controller.pressedPositions, isEmpty);
      expect(harness.hid.connectionStatus.value.name, 'connected');
    },
  );

  test(
    'orientation change clears pressed keys and cancels wheel epoch',
    () async {
      final harness = await TestHarness.create();
      addTearDown(harness.dispose);
      harness.controller.registerLayoutOrientation(false);
      await harness.controller.pressButton(
        harness.controller.activeProfile.buttons.first,
      );
      final initialEpoch = harness.controller.inputEpoch;

      harness.controller.registerLayoutOrientation(true);
      await Future<void>.delayed(Duration.zero);

      expect(harness.controller.pressedPositions, isEmpty);
      expect(harness.controller.inputEpoch, initialEpoch + 1);
      expect(harness.hid.calls.last, 'releaseAllKeys');
      expect(harness.controller.activeProfile.id, 'profile_general');
    },
  );

  test(
    'profile create, duplicate, reorder and delete preserve invariants',
    () async {
      final harness = await TestHarness.create();
      addTearDown(harness.dispose);

      final created = await harness.controller.createProfile(
        name: 'Video Editing',
      );
      final duplicate = await harness.controller.duplicateProfile(created);
      await harness.controller.setDefaultProfile(created.id);
      await harness.controller.switchProfile(duplicate.id);
      await harness.controller.reorderProfiles(2, 0);
      await harness.controller.deleteProfile(duplicate.id);

      expect(harness.controller.config.profiles, hasLength(2));
      expect(harness.controller.config.defaultProfileId, created.id);
      expect(harness.controller.config.activeProfileId, created.id);
      expect(
        harness.controller.config.profiles.every(
          (item) => item.buttons.length == controlButtonCount,
        ),
        isTrue,
      );
    },
  );

  test('swapping buttons moves the complete control and persists it', () async {
    final harness = await TestHarness.create();
    addTearDown(harness.dispose);
    final before = harness.controller.activeProfile.buttons;
    final source = before[0];
    final target = before[1];

    await harness.controller.swapButtons(0, 1);

    final after = harness.controller.activeProfile.buttons;
    expect(after[0].label, target.label);
    expect(after[0].position, 0);
    expect(after[0].id, 'button_01');
    expect(after[1].label, source.label);
    expect(after[1].action.keyCode, source.action.keyCode);
    expect(after[1].position, 1);
    expect(after[1].id, 'button_02');
    expect(
      harness.repository.value.profiles.first.buttons[1].label,
      source.label,
    );
  });

  test('touchpad movement and mouse clicks emit HID actions', () async {
    final harness = await TestHarness.create();
    addTearDown(harness.dispose);

    harness.controller.sendTouchpadMove(8, -4);
    harness.controller.sendMouseClick(secondary: false);
    harness.controller.sendMouseClick(secondary: true);
    harness.controller.sendTouchpadScroll(-18);
    await Future<void>.delayed(Duration.zero);

    expect(harness.hid.pressedActions.single.type, ActionType.mouseMove);
    expect(harness.hid.pressedActions.single.value, '13,-7');
    expect(harness.hid.steppedActions.map((action) => action.type), [
      ActionType.mouseButton,
      ActionType.mouseButton,
      ActionType.mouseWheel,
    ]);
    expect(harness.hid.steppedActions.map((action) => action.value), [
      'LEFT',
      'RIGHT',
      '1',
    ]);
  });

  test('cannot delete the final profile', () async {
    final harness = await TestHarness.create();
    addTearDown(harness.dispose);

    expect(
      () => harness.controller.deleteProfile('profile_general'),
      throwsA(isA<StateError>()),
    );
  });

  test('orientation preference is applied and persisted', () async {
    final harness = await TestHarness.create();
    addTearDown(harness.dispose);

    await harness.controller.updateOrientationMode(OrientationMode.landscape);

    expect(harness.orientation.applied.last, OrientationMode.landscape);
    expect(
      harness.repository.value.preferences.orientationMode,
      OrientationMode.landscape,
    );
  });

  test('new configurations apply landscape by default', () async {
    final harness = await TestHarness.create();
    addTearDown(harness.dispose);

    expect(harness.orientation.applied.single, OrientationMode.landscape);
    expect(
      harness.repository.value.preferences.orientationMode,
      OrientationMode.landscape,
    );
  });

  test(
    'charging applies and persists the configured fixed brightness',
    () async {
      final harness = await TestHarness.create(pluggedIn: true);
      addTearDown(harness.dispose);

      expect(harness.power.appliedBrightness.last, 0.8);
      expect(harness.power.keepScreenOnValues.last, isTrue);

      await harness.controller.updateChargingBrightness(brightness: 0.65);

      expect(harness.power.appliedBrightness.last, 0.65);
      expect(harness.repository.value.preferences.chargingBrightness, 0.65);
    },
  );

  test(
    'Dark always dims the phone and uses every available host channel',
    () async {
      final darkButton = ButtonConfig.empty(9).copyWith(
        label: 'Dark',
        action: const HidAction(
          type: ActionType.companion,
          value: '{"kind":"dark"}',
        ),
      );
      final general = profile().copyWith(
        buttons: [
          for (final button in profile().buttons)
            button.position == 9 ? darkButton : button,
        ],
      );
      final harness = await TestHarness.create(
        config: testConfig(profiles: [general]),
      );
      addTearDown(harness.dispose);
      harness.companion.host.value = const CompanionHost(
        name: 'Studio Mac',
        platform: 'macos',
        address: '192.168.1.10',
        port: 45678,
        token: 'test',
      );

      await harness.controller.pressButton(darkButton);

      expect(harness.controller.isDarkModeActive, isTrue);
      expect(harness.power.appliedBrightness.last, 0.1);
      expect(harness.companion.commands, ['{"kind":"dark","enabled":true}']);
      expect(
        harness.hid.steppedActions.where(
          (action) => action.value == 'BRIGHTNESS_DOWN',
        ),
        hasLength(20),
      );
      expect(
        harness.hid.steppedActions.where(
          (action) => action.value == 'KEYBOARD_BACKLIGHT_MINIMUM',
        ),
        hasLength(1),
      );
      expect(
        harness.hid.steppedActions.where(
          (action) => action.value == 'KEYBOARD_BRIGHTNESS_DOWN',
        ),
        hasLength(16),
      );

      await harness.controller.handleAppResumed();
      expect(harness.power.appliedBrightness.last, 0.1);

      await harness.controller.pressButton(darkButton);

      expect(harness.controller.isDarkModeActive, isFalse);
      expect(harness.power.appliedBrightness.last, isNull);
      expect(
        harness.companion.commands.last,
        '{"kind":"dark","enabled":false}',
      );
      expect(
        harness.hid.steppedActions.where(
          (action) => action.value == 'BRIGHTNESS_UP',
        ),
        hasLength(20),
      );
      expect(
        harness.hid.steppedActions.where(
          (action) => action.value == 'KEYBOARD_BACKLIGHT_MAXIMUM',
        ),
        hasLength(1),
      );
      expect(
        harness.hid.steppedActions.where(
          (action) => action.value == 'KEYBOARD_BRIGHTNESS_UP',
        ),
        hasLength(16),
      );
    },
  );

  test(
    'Dark still dims the phone when neither host channel is connected',
    () async {
      final harness = await TestHarness.create();
      addTearDown(harness.dispose);
      harness.hid.status.value = HidConnectionStatus.disconnected;
      harness.hid.selectedHost.value = null;
      final darkButton = ButtonConfig.empty(9).copyWith(
        label: 'Dark',
        action: const HidAction(
          type: ActionType.companion,
          value: '{"kind":"dark"}',
        ),
      );

      await harness.controller.pressButton(darkButton);

      expect(harness.power.appliedBrightness.last, 0.1);
      expect(harness.hid.steppedActions, isEmpty);
      expect(harness.companion.commands, isEmpty);

      await harness.controller.pressButton(darkButton);
      expect(harness.power.appliedBrightness.last, isNull);
      expect(harness.controller.isDarkModeActive, isFalse);
    },
  );

  test(
    'unplugging restores system brightness and dynamic mode stays system controlled',
    () async {
      final harness = await TestHarness.create(pluggedIn: true);
      addTearDown(harness.dispose);

      harness.power.state.value = false;
      await Future<void>.delayed(Duration.zero);
      expect(harness.power.appliedBrightness.last, isNull);
      expect(harness.power.keepScreenOnValues.last, isFalse);

      harness.power.state.value = true;
      await harness.controller.updateChargingBrightness(
        mode: ChargingBrightnessMode.dynamic,
      );
      expect(harness.power.appliedBrightness.last, isNull);
    },
  );

  test('resuming refreshes power and reapplies brightness', () async {
    final harness = await TestHarness.create(pluggedIn: true);
    addTearDown(harness.dispose);

    await harness.controller.handleAppResumed();

    expect(harness.power.refreshCount, 1);
    expect(harness.power.appliedBrightness.last, 0.8);
    expect(harness.power.keepScreenOnValues.last, isTrue);
  });

  test(
    'screen awake preference defaults on and can restore automatic timeout',
    () async {
      final harness = await TestHarness.create(pluggedIn: true);
      addTearDown(harness.dispose);

      expect(
        harness.controller.config.preferences.keepScreenOnWhileCharging,
        isTrue,
      );
      expect(harness.power.keepScreenOnValues.last, isTrue);

      await harness.controller.updateChargingBrightness(keepScreenOn: false);

      expect(harness.power.keepScreenOnValues.last, isFalse);
      expect(
        harness.repository.value.preferences.keepScreenOnWhileCharging,
        isFalse,
      );
    },
  );

  test('adjacent profile switching wraps in both directions', () async {
    final harness = await TestHarness.create(
      config: testConfig(
        profiles: [
          profile(),
          profile(id: 'profile_web', name: 'Web'),
          profile(id: 'profile_meetings', name: 'Zoom / Teams'),
        ],
      ),
    );
    addTearDown(harness.dispose);

    await harness.controller.switchProfileByOffset(1);
    expect(harness.controller.activeProfile.name, 'Web');
    await harness.controller.switchProfileByOffset(-1);
    expect(harness.controller.activeProfile.name, 'General');
    await harness.controller.switchProfileByOffset(-1);
    expect(harness.controller.activeProfile.name, 'Zoom / Teams');
    expect(
      harness.hid.calls.where((call) => call == 'releaseAllKeys'),
      hasLength(3),
    );
  });

  test(
    'free tier blocks a fifth profile but supports slot replacement',
    () async {
      final harness = await TestHarness.create(
        config: testConfig(
          profiles: [
            profile(),
            profile(id: 'profile_web', name: 'Web'),
            profile(id: 'profile_meetings', name: 'Zoom / Teams'),
            profile(id: 'profile_custom', name: 'Custom'),
          ],
        ),
      );
      addTearDown(harness.dispose);

      await expectLater(
        harness.controller.createProfile(),
        throwsA(isA<ProfileLimitException>()),
      );
      await expectLater(
        harness.controller.duplicateProfile(harness.controller.activeProfile),
        throwsA(isA<ProfileLimitException>()),
      );
      await expectLater(
        harness.controller.importProfile(
          profile(id: 'shared', name: 'Shared Editing'),
        ),
        throwsA(isA<ProfileLimitException>()),
      );

      await harness.controller.importProfile(
        profile(id: 'shared', name: 'Shared Editing'),
        replaceProfileId: 'profile_general',
      );

      expect(harness.controller.config.profiles, hasLength(freeProfileLimit));
      expect(harness.controller.activeProfile.id, 'profile_general');
      expect(harness.controller.activeProfile.name, 'Shared Editing');
      expect(harness.controller.activeProfile.isBuiltInTemplate, isFalse);
      expect(harness.hid.calls, contains('releaseAllKeys'));
    },
  );

  test('automatic PRIMARY uses Command for an Apple host', () async {
    final harness = await TestHarness.create();
    addTearDown(harness.dispose);
    harness.hid.selectedHost.value = const HidHost(
      id: 'mac',
      name: 'Yuchen’s MacBook Pro',
      address: 'AA:BB',
    );

    final button = harness.controller.activeProfile.buttons.first;
    await harness.controller.pressButton(button);
    await harness.controller.releaseButton(button);

    expect(harness.hid.pressedActions.single.modifiers, contains('LEFT_META'));
    expect(harness.hid.releasedActions.single.modifiers, contains('LEFT_META'));
    expect(harness.controller.resolveShortcutLabel(button), '⌘+C');
  });

  test('automatic PRIMARY uses Ctrl for a Windows host', () async {
    final harness = await TestHarness.create();
    addTearDown(harness.dispose);
    harness.hid.selectedHost.value = const HidHost(
      id: 'windows',
      name: 'STEVEN-PC',
      address: 'CC:DD',
    );

    final button = harness.controller.activeProfile.buttons.first;
    await harness.controller.pressButton(button);

    expect(harness.hid.pressedActions.single.modifiers, contains('LEFT_CTRL'));
    expect(harness.controller.resolveShortcutLabel(button), 'Ctrl+C');
  });

  test(
    'desktop companion provides authoritative OS and receives actions',
    () async {
      final harness = await TestHarness.create();
      addTearDown(harness.dispose);
      harness.hid.selectedHost.value = const HidHost(
        id: 'ambiguous',
        name: 'Work Computer',
        address: 'CC:DD',
      );
      harness.companion.host.value = const CompanionHost(
        name: 'Studio Mac',
        platform: 'macos',
        address: '192.168.1.10',
        port: 45678,
        token: 'test',
      );

      expect(
        harness.controller.effectiveShortcutPlatform,
        ShortcutPlatform.apple,
      );

      const command = '{"kind":"launch","target":"ChatGPT"}';
      final button = ButtonConfig.empty(1).copyWith(
        action: const HidAction(type: ActionType.companion, value: command),
      );
      await harness.controller.pressButton(button);
      await harness.controller.releaseButton(button);

      expect(harness.companion.commands, [command]);
      expect(harness.hid.pressedActions, isEmpty);
    },
  );

  test(
    'desktop manifest drives apps, layouts, and identifier actions',
    () async {
      final harness = await TestHarness.create();
      addTearDown(harness.dispose);
      final manifest = desktopManifest(
        installed: const {'vscode', 'codex'},
        running: const {'vscode'},
      );
      harness.companion.syncedManifest.value = manifest;
      harness.companion.status.value = CompanionSyncStatus.ready;

      expect(harness.controller.isDesktopDriven, isTrue);
      expect(harness.controller.remoteCurrentLayout?.id, 'keyboard');
      expect(harness.controller.remoteCodexLayout?.id, 'codex');
      expect(harness.controller.syncedApplications, hasLength(2));
      expect(harness.controller.runningApplications.single.id, 'vscode');

      final vscode = manifest.applicationById('vscode')!;
      final save = manifest.buttonById('vscode.save')!;
      await harness.controller.launchRemoteApplication(vscode);
      await harness.controller.executeRemoteButton(save);

      expect(harness.companion.remoteActions.map((action) => action.kind), [
        RemoteActionKind.launchApplication,
        RemoteActionKind.button,
      ]);
      expect(harness.companion.remoteActions[1].buttonId, 'vscode.save');
      expect(harness.shortcutUsage.records, hasLength(2));
    },
  );

  test(
    'shortcut usage remains local and can reorder the active Profile',
    () async {
      final first = profile();
      final buttons = [...first.buttons];
      buttons[1] = buttons[1].copyWith(
        label: 'Paste',
        action: const HidAction(
          type: ActionType.keyboard,
          keyCode: 'KEY_V',
          modifiers: [primaryShortcutModifier],
        ),
      );
      final harness = await TestHarness.create(
        config: testConfig(profiles: [first.copyWith(buttons: buttons)]),
      );
      addTearDown(harness.dispose);

      await harness.controller.pressButton(buttons[1]);
      await harness.controller.releaseButton(buttons[1]);
      await harness.controller.pressButton(buttons[1]);
      await harness.controller.releaseButton(buttons[1]);
      await harness.controller.pressButton(buttons[0]);
      await harness.controller.releaseButton(buttons[0]);
      await harness.controller.reorderActiveProfileByUsage();

      expect(harness.controller.activeProfile.buttons.first.label, 'Paste');
      expect(harness.shortcutUsage.records.first.count, 2);
      expect(harness.repository.value.toJson(), isNot(contains('usage')));
      expect(harness.companion.remoteActions, isEmpty);
    },
  );

  test(
    'manual shortcut platform override persists and wins over host name',
    () async {
      final harness = await TestHarness.create();
      addTearDown(harness.dispose);
      harness.hid.selectedHost.value = const HidHost(
        id: 'windows',
        name: 'STEVEN-PC',
        address: 'CC:DD',
      );

      await harness.controller.updateShortcutPlatform(ShortcutPlatform.apple);
      await harness.controller.pressButton(
        harness.controller.activeProfile.buttons.first,
      );

      expect(
        harness.repository.value.preferences.shortcutPlatform,
        ShortcutPlatform.apple,
      );
      expect(
        harness.hid.pressedActions.single.modifiers,
        contains('LEFT_META'),
      );
    },
  );
}
