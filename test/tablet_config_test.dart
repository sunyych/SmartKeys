import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_keys/data/profile_transfer_service.dart';
import 'package:smart_keys/models/config.dart';

import 'test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('preferences default and round-trip tablet control settings', () {
    final legacy = AppPreferences.fromJson({});
    expect(legacy.controlSurfaceLayout, ControlSurfaceLayout.automatic);
    expect(legacy.tabletKeysPerPage, 40);

    final preferences = legacy.copyWith(
      controlSurfaceLayout: ControlSurfaceLayout.shortcutBoard,
      tabletKeysPerPage: 60,
    );
    final restored = AppPreferences.fromJson(preferences.toJson());
    expect(restored.controlSurfaceLayout, ControlSurfaceLayout.shortcutBoard);
    expect(restored.tabletKeysPerPage, 60);
    expect(
      AppPreferences.fromJson({
        'controlSurfaceLayout': 'unknown',
        'tabletKeysPerPage': 12,
      }).controlSurfaceLayout,
      ControlSurfaceLayout.automatic,
    );
    expect(
      AppPreferences.fromJson({'tabletKeysPerPage': 12}).tabletKeysPerPage,
      40,
    );
    expect(
      AppPreferences.fromJson({'tabletKeysPerPage': 23}).tabletKeysPerPage,
      40,
    );
    expect(
      AppPreferences.fromJson({'tabletKeysPerPage': 61}).tabletKeysPerPage,
      40,
    );
    expect(
      AppPreferences.fromJson({'tabletKeysPerPage': 24.5}).tabletKeysPerPage,
      40,
    );
    expect(
      AppPreferences.fromJson({
        'tabletKeysPerPage': double.infinity,
      }).tabletKeysPerPage,
      40,
    );
    expect(
      AppPreferences.fromJson({
        'tabletKeysPerPage': double.nan,
      }).tabletKeysPerPage,
      40,
    );
    for (final pageSize in [32, 48]) {
      expect(
        AppPreferences.fromJson({
          'tabletKeysPerPage': pageSize,
        }).tabletKeysPerPage,
        pageSize,
      );
      expect(
        AppPreferences.fromJson(
          legacy.copyWith(tabletKeysPerPage: pageSize).toJson(),
        ).tabletKeysPerPage,
        pageSize,
      );
    }
  });

  test('legacy 15-key profiles remain 15 entries after JSON decoding', () {
    final legacy = profile();
    final decoded = ProfileConfig.fromJson(
      jsonDecode(jsonEncode(legacy.toJson())),
    );
    expect(decoded.buttons, hasLength(controlButtonCount));
    expect(
      decoded.buttons.map((button) => button.position),
      List<int>.generate(controlButtonCount, (index) => index),
    );
  });

  test(
    'profile transfer round-trips position 59 and safely ignores invalid slots',
    () {
      const transfer = ProfileTransferService();
      final source = profile().copyWith(
        buttons: [
          ...profile().buttons,
          ButtonConfig.empty(59).copyWith(label: 'Last slot'),
        ],
      );
      final imported = transfer.decodeImportedProfile(
        transfer.encodeProfile(source),
      );
      final restored = ProfileConfig.fromJson(
        jsonDecode(transfer.encodeProfile(imported)),
      );
      expect(restored.buttons, hasLength(maxControlButtonCount));
      expect(restored.buttons[59].label, 'Last slot');

      final json = source.toJson();
      json['buttons'] = [
        ...source.buttons.map((button) => button.toJson()),
        ButtonConfig.empty(59).copyWith(label: 'First duplicate').toJson(),
        ButtonConfig.empty(60).copyWith(label: 'Too high').toJson(),
        ButtonConfig.empty(-1).copyWith(label: 'Negative').toJson(),
        ButtonConfig.empty(
            2,
          ).copyWith(position: 2, label: 'Fractional').toJson()
          ..['position'] = 2.5,
      ];
      final safe = ProfileConfig.fromJson(json);
      expect(safe.buttons, hasLength(maxControlButtonCount));
      expect(safe.buttons[59].label, 'Last slot');
      expect(
        safe.buttons.every(
          (button) =>
              button.position >= 0 && button.position < maxControlButtonCount,
        ),
        isTrue,
      );
      expect(
        () => transfer.decodeImportedProfile(jsonEncode(json)),
        throwsFormatException,
      );
    },
  );

  test(
    'controller updates presentation settings and can edit slot 59',
    () async {
      final harness = await TestHarness.create();
      addTearDown(harness.dispose);

      await harness.controller.updateControlSurfaceLayout(
        ControlSurfaceLayout.phone,
      );
      await harness.controller.updateTabletKeysPerPage(24);
      await harness.controller.updateTabletKeysPerPage(32);
      await harness.controller.updateTabletKeysPerPage(48);
      await harness.controller.updateButton(
        ButtonConfig.empty(59).copyWith(label: 'Last slot'),
      );

      expect(
        harness.controller.config.preferences.controlSurfaceLayout,
        ControlSurfaceLayout.phone,
      );
      expect(harness.controller.config.preferences.tabletKeysPerPage, 48);
      expect(harness.repository.value.preferences.tabletKeysPerPage, 48);
      await expectLater(
        harness.controller.updateTabletKeysPerPage(23),
        throwsArgumentError,
      );
      await expectLater(
        harness.controller.updateTabletKeysPerPage(61),
        throwsArgumentError,
      );
      expect(harness.controller.config.preferences.tabletKeysPerPage, 48);
      expect(
        harness.controller.activeProfile.buttons,
        hasLength(maxControlButtonCount),
      );
      expect(harness.controller.activeProfile.buttons[59].label, 'Last slot');
      expect(
        harness.repository.value.activeProfile.buttons[59].label,
        'Last slot',
      );
    },
  );

  test(
    'dragging position zero to 59 persists and reloads both positions',
    () async {
      final harness = await TestHarness.create();
      addTearDown(harness.dispose);

      await harness.controller.swapButtons(0, 59);

      final saved = harness.repository.value.activeProfile;
      expect(saved.buttons, hasLength(maxControlButtonCount));
      expect(saved.buttons[0].action.type, ActionType.none);
      expect(saved.buttons[59].label, 'Copy');
      final reloaded = ProfileConfig.fromJson(
        jsonDecode(jsonEncode(saved.toJson())),
      );
      expect(reloaded.buttons[0].action.type, ActionType.none);
      expect(reloaded.buttons[59].label, 'Copy');
      expect(reloaded.buttons[59].id, 'button_60');
    },
  );

  test(
    'dragging an empty tablet slot onto an existing button swaps them',
    () async {
      final harness = await TestHarness.create();
      addTearDown(harness.dispose);
      final targetLabel = harness.controller.activeProfile.buttons[4].label;

      await harness.controller.swapButtons(59, 4);

      final buttons = harness.controller.activeProfile.buttons;
      expect(buttons[4].action.type, ActionType.none);
      expect(buttons[4].id, 'button_05');
      expect(buttons[59].label, targetLabel);
      expect(buttons[59].id, 'button_60');
    },
  );
}
