import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lumiakey_bluetooth_lite/lite_controller.dart';
import 'package:lumiakey_bluetooth_lite/lite_editors.dart';
import 'package:lumiakey_bluetooth_lite/local_diagnostics.dart';
import 'package:lumiakey_bluetooth_lite/local_launcher.dart';
import 'package:lumiakey_bluetooth_lite/local_profiles.dart';
import 'package:lumiakey_bluetooth_lite/local_settings.dart';

class Profiles implements LocalProfileStore {
  List<LocalProfile> values = defaultLocalProfiles();
  bool fail = false;
  @override
  Future<List<LocalProfile>> load() async => List.of(values);
  @override
  Future<void> save(List<LocalProfile> profiles) async {
    if (fail) throw StateError('fixture save failed');
    values = List.of(profiles);
  }
}

class Slots extends MemoryLocalLauncherStore {
  Completer<void>? pending;
  @override
  Future<void> save(List<LocalLaunchSlot> slots) async {
    await pending?.future;
    await super.save(slots);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('smart_keys/hid');
  late Profiles profiles;
  late Slots slots;
  late LiteController controller;
  late LiteDiagnostics diagnostics;
  late List<MethodCall> calls;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    profiles = Profiles();
    slots = Slots();
    calls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return {
            'status': 'connected',
            'activeHost': {
              'id': 'fixture',
              'name': 'Fixture computer',
              'address': 'fixture-host',
            },
            'pairedHosts': [
              {
                'id': 'second',
                'name': 'Second computer',
                'address': 'second-host',
              },
            ],
          };
        });
    diagnostics = LiteDiagnostics(
      metadataLoader: () async => {'appVersion': '1.2.0', 'appBuild': 3},
    );
    await diagnostics.initialize();
    controller = LiteController(
      profileStore: profiles,
      launcherStore: slots,
      diagnostics: diagnostics,
    );
    await controller.initialize();
    controller.setLandscape(true);
    controller.setControlsVisible(false);
  });
  tearDown(() {
    controller.dispose();
    diagnostics.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
  Future<void> flush(WidgetTester tester) async {
    await tester.runAsync(() async {
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pumpAndSettle();
  }

  Future<void> show(WidgetTester tester, Widget screen) async {
    await tester.binding.setSurfaceSize(const Size(900, 500));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home: screen));
    await flush(tester);
  }

  testWidgets('settings exposes twelve local slots without sending input', (
    tester,
  ) async {
    await show(tester, LiteSettingsScreen(controller: controller));
    await tester.tap(find.byKey(const ValueKey('lite-launchpad-entry')));
    await flush(tester);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('lite-configure-slot-11')),
      250,
    );
    expect(
      find.byKey(const ValueKey('lite-configure-slot-11')),
      findsOneWidget,
    );
    expect(controller.launcherSlots, hasLength(12));
    expect(controller.launcherSlots.every((slot) => !slot.configured), isTrue);
    expect(calls.where((call) => call.method == 'sendStep'), isEmpty);
  });

  testWidgets(
    'launch binding is keyboard only and stays disabled until durable save',
    (tester) async {
      await show(
        tester,
        LiteLaunchSlotEditor(controller: controller, index: 0),
      );
      await tester.tap(find.byKey(const ValueKey('lite-slot-set-binding')));
      await flush(tester);
      expect(find.text('Media control'), findsNothing);
      await tester.enterText(
        find.byKey(const ValueKey('lite-shortcut-name')),
        'Launch ChatGPT',
      );
      await tester.enterText(
        find.byKey(const ValueKey('lite-shortcut-key')),
        'not-a-key',
      );
      await tester.tap(find.byKey(const ValueKey('lite-shortcut-apply')));
      await flush(tester);
      expect(find.text('Enter a supported keyboard key'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('lite-shortcut-key')),
        'G',
      );
      await tester.tap(find.text('CTRL'));
      await tester.tap(find.byKey(const ValueKey('lite-shortcut-apply')));
      await flush(tester);
      expect(controller.launcherSlots.first.configured, isFalse);
      slots.pending = Completer<void>();
      await tester.tap(find.byKey(const ValueKey('lite-slot-save')));
      await tester.pump();
      expect(controller.launcherSlots.first.configured, isFalse);
      expect(find.text('Saving…'), findsOneWidget);
      slots.pending!.complete();
      await flush(tester);
      expect(controller.launcherSlots.first.launchShortcut!.keyCode, 'G');
      expect(controller.launcherSlots.first.launchShortcut!.modifiers, [
        'LEFT_CTRL',
      ]);
      expect(calls.where((call) => call.method == 'sendStep'), isEmpty);
    },
  );

  testWidgets(
    'failed slot save keeps prior authority and exposes retry feedback',
    (tester) async {
      slots.failSave = true;
      await show(
        tester,
        LiteLaunchSlotEditor(controller: controller, index: 0),
      );
      await tester.enterText(
        find.byKey(const ValueKey('lite-slot-name')),
        'Draft name',
      );
      await tester.tap(find.byKey(const ValueKey('lite-slot-save')));
      await flush(tester);
      expect(find.byKey(const ValueKey('lite-editor-error')), findsOneWidget);
      expect(controller.launcherSlots.first.title, 'ChatGPT');
      expect(slots.slots.first.title, 'ChatGPT');
      expect(controller.launcherSlots.first.configured, isFalse);
      expect(find.byKey(const ValueKey('lite-slot-name')), findsOneWidget);
    },
  );

  testWidgets(
    'media editor preserves long saved profile and only publishes on save',
    (tester) async {
      final old = List.generate(
        15,
        (index) => LocalShortcut(
          title: 'Old $index',
          keyCode: 'A',
          modifiers: const [],
        ),
      );
      final profile = LocalProfile(
        id: 'long',
        name: 'Long profile',
        shortcuts: old,
      );
      await tester.runAsync(() => controller.saveProfile(profile));
      await show(
        tester,
        LiteProfileEditor(controller: controller, profile: profile),
      );
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('lite-add-shortcut')),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const ValueKey('lite-add-shortcut')));
      await flush(tester);
      await tester.enterText(
        find.byKey(const ValueKey('lite-shortcut-name')),
        'Play media',
      );
      await tester.tap(find.byType(Switch));
      await flush(tester);
      await tester.tap(find.byKey(const ValueKey('lite-shortcut-apply')));
      await flush(tester);
      expect(controller.profiles.last.shortcuts, hasLength(15));
      profiles.fail = true;
      await tester.tap(find.byKey(const ValueKey('lite-profile-save')));
      await flush(tester);
      expect(controller.profiles.last.shortcuts, hasLength(15));
      profiles.fail = false;
      await tester.tap(find.byKey(const ValueKey('lite-profile-save')));
      await flush(tester);
      final saved = controller.profiles.last.shortcuts;
      expect(saved, hasLength(16));
      expect(
        saved.take(15).map((value) => value.title),
        old.map((value) => value.title),
      );
      expect(saved.last.consumerUsage, 'PLAY_PAUSE');
      expect(calls.where((call) => call.method == 'sendStep'), isEmpty);
    },
  );

  testWidgets('manual Bluetooth management never sends shortcuts', (
    tester,
  ) async {
    await show(tester, LiteBluetoothScreen(controller: controller));
    await tester.tap(find.text('Connect'));
    await flush(tester);
    expect(calls.where((call) => call.method == 'connect').single.arguments, {
      'address': 'second-host',
    });
    await tester.tap(find.text('Disconnect'));
    await flush(tester);
    expect(calls.where((call) => call.method == 'disconnect'), hasLength(1));
    expect(calls.where((call) => call.method == 'sendStep'), isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'profile creation and deletion preserve durable data on failure',
    (tester) async {
      await show(tester, LiteProfilesScreen(controller: controller));
      await tester.tap(find.byKey(const ValueKey('lite-new-profile')));
      await flush(tester);
      await tester.tap(find.byKey(const ValueKey('lite-profile-save')));
      await flush(tester);
      expect(find.text('Enter a profile name'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('lite-profile-name')),
        'My profile',
      );
      await tester.tap(find.byKey(const ValueKey('lite-profile-save')));
      await flush(tester);
      final created = controller.profiles.last;
      expect(created.name, 'My profile');
      expect(profiles.values.last.id, created.id);
      profiles.fail = true;
      await tester.scrollUntilVisible(find.byTooltip('Delete My profile'), 200);
      await tester.tap(find.byTooltip('Delete My profile'));
      await flush(tester);
      await tester.tap(find.text('Delete').last);
      await flush(tester);
      expect(
        controller.profiles.any((profile) => profile.id == created.id),
        isTrue,
      );
      expect(find.byKey(const ValueKey('lite-settings-error')), findsOneWidget);
      profiles.fail = false;
      await tester.tap(find.byTooltip('Delete My profile'));
      await flush(tester);
      await tester.tap(find.text('Delete').last);
      await flush(tester);
      expect(
        controller.profiles.any((profile) => profile.id == created.id),
        isFalse,
      );
      expect(calls.where((call) => call.method == 'sendStep'), isEmpty);
    },
  );

  testWidgets(
    'deleted linked profile displays and saves Stay on Launchpad without reselection',
    (tester) async {
      await tester.runAsync(() => controller.deleteProfile('chatgpt'));
      expect(controller.launcherSlots.first.profileId, 'chatgpt');
      await show(
        tester,
        LiteLaunchSlotEditor(controller: controller, index: 0),
      );
      expect(find.text('Stay on Launchpad'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('lite-slot-name')),
        'Updated slot',
      );
      await tester.tap(find.byKey(const ValueKey('lite-slot-save')));
      await flush(tester);
      expect(controller.launcherSlots.first.title, 'Updated slot');
      expect(controller.launcherSlots.first.profileId, isNull);
      expect(find.byKey(const ValueKey('lite-editor-error')), findsNothing);
    },
  );
}
