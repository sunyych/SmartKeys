import 'package:flutter_test/flutter_test.dart';
import 'package:smart_keys/controllers/app_controller.dart';
import 'package:smart_keys/models/config.dart';
import 'package:smart_keys/services/hid_service.dart';

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

  test('holding a mouse direction repeats movement until release', () async {
    final harness = await TestHarness.create();
    addTearDown(harness.dispose);
    const action = HidAction(type: ActionType.mouseMove, value: 'UP');

    harness.controller.startMouseMove(action);
    await Future<void>.delayed(const Duration(milliseconds: 95));
    harness.controller.stopMouseMove();
    await Future<void>.delayed(Duration.zero);

    expect(
      harness.hid.pressedActions.where(
        (item) => item.type == ActionType.mouseMove,
      ),
      hasLength(greaterThanOrEqualTo(2)),
    );
    expect(harness.hid.releasedActions.last.value, 'UP');
    final countAfterRelease = harness.hid.pressedActions.length;
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(harness.hid.pressedActions, hasLength(countAfterRelease));
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
