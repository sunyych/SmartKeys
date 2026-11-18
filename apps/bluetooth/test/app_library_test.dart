import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lumiakey_bluetooth_lite/app_library/app_library.dart';
import 'package:lumiakey_bluetooth_lite/lite_controller.dart';
import 'package:lumiakey_bluetooth_lite/lite_app_library_screen.dart';
import 'package:lumiakey_bluetooth_lite/local_profiles.dart';
import 'package:lumiakey_bluetooth_lite/local_launcher.dart';

class _Profiles implements LocalProfileStore {
  List<LocalProfile> values = defaultLocalProfiles();
  bool failSave = false;
  @override
  Future<List<LocalProfile>> load() async => values;
  @override
  Future<void> save(List<LocalProfile> profiles) async {
    if (failSave) throw StateError('save failed');
    values = profiles;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('smart_keys/hid');
  final reports = <Map>[];
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    reports.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'sendStep') reports.add(call.arguments as Map);
          return call.method == 'refreshPairedHosts' ||
                  call.method == 'sendStep'
              ? {
                  'status': 'connected',
                  'activeHost': {
                    'id': 'test',
                    'name': 'Test',
                    'address': 'AA:BB:CC:DD:EE:01',
                  },
                  'pairedHosts': [],
                }
              : null;
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );
  Future<LiteController> ready({
    _Profiles? store,
    MemoryLocalLauncherStore? launcher,
  }) async {
    final controller = LiteController(
      profileStore: store ?? _Profiles(),
      launcherStore: launcher ?? MemoryLocalLauncherStore(),
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    controller.setLandscape(true);
    controller.setControlsVisible(true);
    return controller;
  }

  Map<String, dynamic> fresh() =>
      jsonDecode(jsonEncode(AppLibraryCatalog.builtin.toJson()))
          as Map<String, dynamic>;
  test(
    'display labels describe real OS keys without rewriting stored chords',
    () {
      final keys = AppLibraryCatalog.builtin
          .appById('chrome')!
          .libraryForOS('macos')!
          .actions
          .first
          .keys;
      expect(formatAppLibraryChord(keys, 'macos'), 'Command + T');
      expect(keys, ['META', 'T']);
      expect(
        formatAppLibraryChord(['META', 'ALT', 'LEFT_BRACKET'], 'macos'),
        'Command + Option + [',
      );
      expect(
        formatAppLibraryChord(['META', 'ALT', 'SLASH'], 'windows'),
        'Windows + Alt + /',
      );
      expect(
        formatAppLibraryChord(['META', 'CTRL', 'PAGE_UP'], 'linux'),
        'Super + Ctrl + Page Up',
      );
      expect(
        formatAppLibraryChord(['SHIFT', 'PAGE_DOWN'], 'windows'),
        'Shift + Page Down',
      );
      expect(formatAppLibraryChord([], 'macos'), 'Not configured');
      expect(appLibraryOSLabel('macos'), 'macOS');
      expect(appLibraryFamilyLabel('windowsLinux'), 'Windows / Linux');
      expect(appLibraryContextLabel('native'), 'Desktop app');
      expect(appLibraryContextLabel('web'), 'Web app');
      expect(appLibraryContextLabel('terminal'), 'Terminal');
    },
  );
  test(
    'all canonical Apps bind their icon and explicit supported family without legacy artwork alias',
    () {
      final catalog = AppLibraryCatalog.builtin;
      expect(catalog.apps, hasLength(60));
      expect(catalog.apps.where((a) => a.bundled), hasLength(50));
      expect(catalog.appById('codex'), isNull);
      expect(catalog.appById('google-chrome')!.id, 'chrome');
      expect(catalog.appById('safari')!.libraryForOS('windows'), isNull);
      expect(catalog.appById('github-desktop')!.libraryForOS('linux'), isNull);
      for (final app in catalog.apps) {
        expect(app.iconId, app.id);
        expect(registeredAppIconHash(app.id), matches(r'^[a-f0-9]{64}$'));
        for (final lib in app.libraries) {
          expect(lib.actions.length, lessThanOrEqualTo(12));
        }
      }
      expect(() => catalog.apps.clear(), throwsUnsupportedError);
      expect(
        () => catalog.apps.first.libraries.first.actions.first.keys.add('A'),
        throwsUnsupportedError,
      );
      expect(AppLibraryCatalog.fromJson(fresh()).toJson(), catalog.toJson());
    },
  );
  test(
    'public catalog rejects commands malformed booleans OS and punctuation',
    () {
      final cases = <void Function(Map<String, dynamic>)>[
        (d) => d['schemaVersion'] = 1.0,
        (d) => d['version'] = null,
        (d) => d['apps'][0]['libraries'][0]['context'] = null,
        (d) => d['apps'][0]['bundled'] = 1,
        (d) => d['apps'][0]['libraries'][0]['supportedOS'] = ['windows'],
        (d) => d['apps'][0]['libraries'][0]['actions'][0]['command'] = 'shell',
        (d) => d['apps'][0]['libraries'][0]['actions'][0]['keys'] = [
          'CTRL',
          '/private/app',
        ],
        (d) =>
            d['apps'][0]['libraries'][0]['actions'][0]['keys'] = ['CTRL', '['],
        (d) => d['apps'][0]['libraries'][0]['actions'][0]['keys'] = [
          'CTRL',
          'A',
          'B',
        ],
        (d) => d['apps'][0]['libraries'][0]['actions'][0]['keys'] = [
          'CTRL',
          'CTRL',
          'C',
        ],
        (d) => d['apps'][0]['libraries'][0]['sourceUrls'] = [
          'https://user@example.com',
        ],
        (d) => d['apps'][0]['id'] = 'codex',
      ];
      for (final change in cases) {
        final data = fresh();
        change(data);
        expect(() => AppLibraryCatalog.fromJson(data), throwsFormatException);
      }
    },
  );
  test(
    'offline installation atomically stores icon keys source and preserves old profiles and private launch keys',
    () async {
      final store = _Profiles();
      final launcher = MemoryLocalLauncherStore();
      final controller = await ready(store: store, launcher: launcher);
      await controller.saveLaunchSlot(
        0,
        const LocalLaunchSlot(
          title: 'Private launch',
          launchShortcut: LocalShortcut(
            title: 'Private',
            keyCode: 'F8',
            modifiers: ['LEFT_ALT'],
          ),
        ),
      );
      final before = jsonEncode(
        controller.launcherSlots.map((s) => s.toJson()).toList(),
      );
      final old = controller.profiles.map((p) => p.toJson()).toList();
      final installed = await controller.installAppLibrary('chrome', 'macos');
      expect(installed.iconId, 'chrome');
      expect(installed.sourceAppId, 'chrome');
      expect(installed.sourceOperatingSystem, 'macos');
      expect(installed.sourceActionHashes, hasLength(12));
      expect(installed.shortcuts.first.modifiers, ['LEFT_META']);
      expect(
        controller.profiles.take(old.length).map((p) => p.toJson()).toList(),
        old,
      );
      expect(
        jsonEncode(controller.launcherSlots.map((s) => s.toJson()).toList()),
        before,
      );
      expect(reports, isEmpty);
      final copied = await controller.installAppLibrary('chrome', 'windows');
      expect(copied.id, isNot(installed.id));
      expect(copied.shortcuts.first.modifiers, ['LEFT_CTRL']);
      expect(store.values.last.sourceAppId, 'chrome');
      final reload = LocalProfile.fromJson(installed.toJson());
      expect(reload.sourceLibraryId, installed.sourceLibraryId);
      expect(() => reload.sourceActionHashes.clear(), throwsUnsupportedError);
    },
  );
  test(
    'failed installation publishes neither profile nor icon and unsupported systems remain rejected',
    () async {
      final store = _Profiles();
      final controller = await ready(store: store);
      final before = controller.profiles.map((p) => p.toJson()).toList();
      store.failSave = true;
      await expectLater(
        controller.installAppLibrary('chrome', 'macos'),
        throwsStateError,
      );
      expect(controller.profiles.map((p) => p.toJson()).toList(), before);
      await expectLater(
        controller.installAppLibrary('safari', 'windows'),
        throwsFormatException,
      );
      await expectLater(
        controller.installAppLibrary('codex', 'macos'),
        throwsFormatException,
      );
      await expectLater(
        controller.installAppLibrary('gimp', 'linux'),
        throwsFormatException,
        reason: 'Web-only cohort is not bundled into Lite',
      );
      expect(reports, isEmpty);
    },
  );
  test(
    'unassigned actions never emit HID or grant application launch authority',
    () async {
      final controller = await ready();
      final profile = await controller.installAppLibrary('obs', 'linux');
      expect(profile.shortcuts.every((s) => s.requiresConfiguration), true);
      expect(await controller.executeShortcut(profile.shortcuts.first), false);
      expect(
        () => controller.saveLaunchSlot(
          0,
          LocalLaunchSlot(
            title: 'Unsafe',
            launchShortcut: profile.shortcuts.first,
          ),
        ),
        throwsFormatException,
      );
      expect(reports, isEmpty);
      expect(
        () => LocalShortcut.fromJson({
          'title': 'Unset',
          'requiresConfiguration': true,
          'keyCode': 'C',
        }),
        throwsFormatException,
      );
    },
  );
  test(
    'canonical named punctuation adapts to the Android HID vocabulary',
    () async {
      final controller = await ready();
      for (final item in {
        'EQUAL': 'EQUALS',
        'QUOTE': 'APOSTROPHE',
        'BACKTICK': 'GRAVE',
        'LEFT_BRACKET': 'LEFT_BRACKET',
      }.entries) {
        expect(
          await controller.executeShortcut(
            LocalShortcut(
              title: 'Punctuation',
              keyCode: item.key,
              modifiers: ['LEFT_CTRL'],
            ),
          ),
          true,
        );
        expect(reports.last['keyCode'], item.value);
      }
      expect(canonicalKeyToLiteral('LEFT_BRACKET'), '[');
      expect(canonicalKeyToLiteral('PAGE_UP'), 'PAGEUP');
    },
  );
  testWidgets(
    'offline App page requires explicit OS and filters Safari without network',
    (tester) async {
      final controller = await ready();
      tester.view.physicalSize = const Size(900, 500);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        MaterialApp(home: LiteAppLibraryScreen(controller: controller)),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('lite-app-library-catalog')),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const ValueKey('lite-app-library-search')),
        'Safari',
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('lite-app-library-safari')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('lite-app-library-os')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Windows').last);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('lite-app-library-safari')),
        findsNothing,
      );
      expect(reports, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    },
  );
  testWidgets(
    'App page installs the chosen icon and OS keys as a new profile without HID',
    (tester) async {
      final store = _Profiles();
      final controller = await ready(store: store);
      controller.setControlsVisible(false);
      tester.view.physicalSize = const Size(1000, 640);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        MaterialApp(home: LiteAppLibraryScreen(controller: controller)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('lite-app-library-os')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('macOS').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('lite-app-library-search')),
        'chrome',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('lite-app-library-chrome')));
      await tester.pumpAndSettle();
      expect(find.text('Command + T'), findsOneWidget);
      expect(find.text('META + T'), findsNothing);
      final button = find.byKey(const ValueKey('lite-install-app-chrome'));
      await tester.drag(
        find.byKey(const ValueKey('lite-app-library-list')),
        const Offset(0, -900),
      );
      await tester.pumpAndSettle();
      expect(button.hitTestable(), findsOneWidget);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(store.values, hasLength(4));
      expect(store.values.last.sourceAppId, 'chrome');
      expect(store.values.last.iconId, 'chrome');
      expect(store.values.last.shortcuts.first.modifiers, ['LEFT_META']);
      expect(reports, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    },
  );
}
