import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumiakeys_protocol/lumiakeys_protocol.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_keys/app.dart';
import 'package:smart_keys/app_edition.dart';
import 'package:smart_keys/data/config_repository.dart';
import 'package:smart_keys/data/profile_template_repository.dart';
import 'package:smart_keys/models/config.dart';
import 'package:smart_keys/services/companion_service.dart';
import 'package:smart_keys/services/disabled_companion_service.dart';
import 'package:smart_keys/ui/desktop_connection_panel.dart';
import 'package:smart_keys/ui/home_screen.dart';
import 'package:smart_keys/ui/button_editor_screen.dart';
import 'package:smart_keys/ui/wheel_editor_screen.dart';

import 'test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Lite defaults and saved edits never replace existing regular data',
    () async {
      final regularRaw = jsonEncode(testConfig().toJson());
      SharedPreferences.setMockInitialValues({
        SharedPreferencesConfigRepository.storageKey: regularRaw,
      });
      final repository = SharedPreferencesConfigRepository(
        templates: ProfileTemplateRepository(edition: AppEdition.lite),
      );
      final config = await repository.load();
      expect(config.profiles.map((p) => p.name), [
        'General',
        'ChatGPT',
        'Chrome',
      ]);
      expect(config.profiles.every((p) => p.buttons.length == 15), isTrue);
      final edited = config.copyWith(
        profiles: [
          config.profiles.first.copyWith(name: 'My General'),
          ...config.profiles.skip(1),
        ],
      );
      await repository.save(edited);
      expect((await repository.load()).profiles.first.name, 'My General');
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString(SharedPreferencesConfigRepository.storageKey),
        regularRaw,
      );
      expect(
        prefs.getString(SharedPreferencesConfigRepository.liteStorageKey),
        isNotNull,
      );
    },
  );

  test(
    'Lite companion stays disconnected and rejects all Desktop execution',
    () async {
      final companion = DisabledCompanionService();
      addTearDown(companion.dispose);
      await companion.start();
      await companion.refreshManifest();
      expect(companion.activeHost.value, isNull);
      expect(companion.manifest.value, isNull);
      expect(companion.syncStatus.value, CompanionSyncStatus.disconnected);
      await expectLater(companion.execute('{}'), throwsUnsupportedError);
      await expectLater(
        companion.executeRemote(RemoteActionRequest.button('general.copy')),
        throwsUnsupportedError,
      );
      await expectLater(
        companion.sendDictation(sessionId: 'test', sequence: 0, text: 'hello'),
        throwsUnsupportedError,
      );
    },
  );

  testWidgets('Lite root keeps Bluetooth profiles without computer app setup', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(900, 420);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final profiles = (await tester.runAsync(
      () => ProfileTemplateRepository(edition: AppEdition.lite).loadAll(),
    ))!;
    final harness = await TestHarness.create(
      config: testConfig(profiles: profiles),
      seedComputerSetup: false,
      platformOverride: TargetPlatform.android,
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await harness.dispose();
    });
    await tester.pumpWidget(
      SmartKeysApp(controller: harness.controller, edition: AppEdition.lite),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<HomeScreen>(find.byType(HomeScreen)).liteMode, isTrue);
    expect(
      find.byKey(const ValueKey('profile-quick-profile_general')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('profile-quick-profile_chatgpt')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('profile-quick-profile_chrome')),
      findsOneWidget,
    );
    expect(find.byType(DesktopConnectionPanel), findsNothing);
    expect(find.text('Launchpad'), findsNothing);
    await tester.tap(
      find.byKey(const ValueKey('profile-quick-profile_chatgpt')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('control-button-0')));
    await tester.pump();
    expect(harness.hid.calls, contains('press:KEY_N'));
    expect(harness.companion.remoteActions, isEmpty);
  });

  testWidgets(
    'Lite settings edit a shortcut locally without Desktop configuration',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(900, 420);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final profiles = (await tester.runAsync(
        () => ProfileTemplateRepository(edition: AppEdition.lite).loadAll(),
      ))!;
      final harness = await TestHarness.create(
        config: testConfig(profiles: profiles),
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await harness.dispose();
      });
      await tester.pumpWidget(
        SmartKeysApp(controller: harness.controller, edition: AppEdition.lite),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('control-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      expect(find.byType(DesktopConnectionPanel), findsNothing);
      expect(
        find.byKey(const ValueKey('open-desktop-installers')),
        findsNothing,
      );
      await tester.tap(find.byKey(const ValueKey('lite-shortcut-settings')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('lite-shortcuts-profile_chatgpt')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('lite-edit-button-0')));
      await tester.pumpAndSettle();
      final label = find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.labelText == 'Label',
      );
      await tester.ensureVisible(label);
      await tester.enterText(label, 'My Chat');
      final actionType = find.byWidgetPredicate(
        (widget) => widget is DropdownButton<ActionType>,
      );
      await tester.scrollUntilVisible(
        actionType,
        250,
        scrollable: find.byType(Scrollable).first,
      );
      final actionOptions = tester
          .widget<DropdownButton<ActionType>>(actionType)
          .items!;
      expect(
        actionOptions.map((item) => item.value),
        isNot(contains(ActionType.companion)),
      );
      expect(find.text('Launch ChatGPT'), findsNothing);
      expect(find.text('Desktop action JSON'), findsNothing);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(
        harness.repository.value.activeProfile.buttons.first.label,
        'My Chat',
      );
      expect(harness.companion.remoteActions, isEmpty);
    },
  );

  testWidgets('Lite preserves the local Dark button without Desktop presets', (
    tester,
  ) async {
    final profiles = (await tester.runAsync(
      () => ProfileTemplateRepository(edition: AppEdition.lite).loadAll(),
    ))!;
    final harness = await TestHarness.create(
      config: testConfig(profiles: profiles),
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await harness.dispose();
    });
    await tester.pumpWidget(
      SmartKeysApp(controller: harness.controller, edition: AppEdition.lite),
    );
    await tester.pumpAndSettle();
    unawaited(
      tester
          .state<NavigatorState>(find.byType(Navigator))
          .push<void>(
            MaterialPageRoute<void>(
              builder: (_) => const ButtonEditorScreen(position: 9),
            ),
          ),
    );
    await tester.pumpAndSettle();
    final actionType = find.byWidgetPredicate(
      (widget) => widget is DropdownButton<ActionType>,
    );
    await tester.scrollUntilVisible(
      actionType,
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Display dimming'), findsOneWidget);
    expect(find.text('Desktop action JSON'), findsNothing);
    expect(find.text('Launch ChatGPT'), findsNothing);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    final dark = harness.controller.activeProfile.buttons[9];
    expect(dark.action.type, ActionType.companion);
    expect(jsonDecode(dark.action.value!)['kind'], 'dark');
    await harness.controller.pressButton(dark);
    expect(harness.power.appliedBrightness, contains(0.1));
    expect(
      harness.hid.steppedActions.any(
        (action) => action.value == 'BRIGHTNESS_DOWN',
      ),
      isTrue,
    );
    expect(harness.companion.commands, isEmpty);
    expect(harness.companion.remoteActions, isEmpty);
  });

  testWidgets('Lite navigation editor offers Bluetooth actions only', (
    tester,
  ) async {
    final harness = await TestHarness.create();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await harness.dispose();
    });
    await tester.pumpWidget(
      SmartKeysScope(
        controller: harness.controller,
        edition: AppEdition.lite,
        child: const MaterialApp(home: WheelEditorScreen()),
      ),
    );
    await tester.pumpAndSettle();
    final actionType = find
        .byWidgetPredicate((widget) => widget is DropdownButton<ActionType>)
        .first;
    await tester.scrollUntilVisible(
      actionType,
      250,
      scrollable: find.byType(Scrollable).first,
    );
    final options = tester
        .widget<DropdownButton<ActionType>>(actionType)
        .items!;
    expect(
      options.map((item) => item.value),
      isNot(contains(ActionType.companion)),
    );
  });
}
