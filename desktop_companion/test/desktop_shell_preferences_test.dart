import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumiakeys_companion/desktop_ui.dart';
import 'package:lumiakeys_companion/main.dart';
import 'package:lumiakeys_protocol/lumiakeys_protocol.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _NoopDiscovery implements ApplicationDiscovery {
  @override
  Future<List<RemoteApplication>> refresh(List<RemoteApplication> apps) async =>
      apps;
}

class _MemoryPreferences implements DesktopAppPreferencesStore {
  DesktopAppPreferences value = const DesktopAppPreferences();
  bool fail = false;

  @override
  Future<DesktopAppPreferences> load() async => value;

  @override
  Future<void> save(DesktopAppPreferences preferences) async {
    if (fail) throw StateError('Cannot save test preferences');
    value = preferences;
  }
}

class _SharedPreferences implements SharedPreferencesAsync {
  final values = <String, String>{};

  @override
  Future<String?> getString(String key) async => values[key];

  @override
  Future<void> setString(String key, String value) async {
    values[key] = value;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void _largeWindow(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1080, 720);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

Future<DesktopController> _controller() async {
  final controller = DesktopController(
    store: MemoryDesktopConfigStore(),
    actions: DesktopActions(environment: const {}),
    discovery: _NoopDiscovery(),
  );
  addTearDown(controller.dispose);
  await controller.initialize();
  return controller;
}

Future<void> _select(WidgetTester tester, int section) async {
  tester
      .widget<NavigationRail>(find.byType(NavigationRail))
      .onDestinationSelected!(
    DesktopSettingsHome.navigationOrder.indexOf(section),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'default Desktop shell shows an English Launcher and About last',
    (tester) async {
      _largeWindow(tester);
      tester.platformDispatcher.localeTestValue = const Locale('zh', 'CN');
      addTearDown(tester.platformDispatcher.clearLocaleTestValue);
      final controller = await _controller();
      await tester.pumpWidget(
        CompanionApp(controller: controller, startServer: false),
      );
      await tester.pumpAndSettle();

      final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
      expect(
        rail.destinations
            .map((destination) => (destination.label as Text).data)
            .where((label) => label != 'App Bar'),
        [
          'General',
          'Connections',
          'Shortcut Layout',
          'Apps',
          'Profiles',
          'Local Dictation',
          'Launcher',
          'Settings',
          'About',
        ],
      );
      await _select(tester, 7);
      expect(controller.selectedSection, 7);
      expect(find.text('Edit Keys'), findsOneWidget);
      expect(find.text('Add App'), findsWidgets);
      expect(find.text('编辑按键'), findsNothing);

      await _select(tester, 5);
      expect(controller.selectedSection, 5);
      expect(find.text('LumiaKey Desktop'), findsOneWidget);
    },
  );

  testWidgets(
    'desktop settings apply appearance now and stage Rust for restart',
    (tester) async {
      _largeWindow(tester);
      final store = _MemoryPreferences();
      final controller = await _controller();
      await tester.pumpWidget(
        CompanionApp(
          controller: controller,
          preferencesStore: store,
          startServer: false,
        ),
      );
      await tester.pumpAndSettle();
      await _select(tester, 8);

      tester
          .widget<DropdownButton<DesktopAppLanguage>>(
            find.byKey(const ValueKey('desktop-settings-language')),
          )
          .onChanged!(DesktopAppLanguage.simplifiedChinese);
      await tester.pumpAndSettle();
      expect(find.text('语言'), findsOneWidget);
      expect(store.value.language, DesktopAppLanguage.simplifiedChinese);

      final theme = find.byKey(const ValueKey('desktop-settings-theme'));
      tester.widget<DropdownButton<ThemeMode>>(theme).onChanged!(
        ThemeMode.dark,
      );
      await tester.pumpAndSettle();
      expect(Theme.of(tester.element(theme)).brightness, Brightness.dark);
      expect(store.value.themeMode, ThemeMode.dark);

      final rust = find.byKey(const ValueKey('desktop-settings-rust'));
      tester.widget<SwitchListTile>(rust).onChanged!(true);
      await tester.pumpAndSettle();
      expect(store.value.rustEnabled, isTrue);
      expect(tester.widget<SwitchListTile>(rust).value, isTrue);
      expect(find.text('重启 LumiaKey Desktop 后，Rust 后端设置生效。'), findsOneWidget);
      await _select(tester, 5);
      expect(find.text('输入后端：标准'), findsOneWidget);
      await _select(tester, 7);
      expect(find.text('编辑按键'), findsOneWidget);

      final reopened = await _controller();
      await tester.pumpWidget(
        CompanionApp(
          key: UniqueKey(),
          controller: reopened,
          preferencesStore: store,
          startServer: false,
        ),
      );
      await tester.pumpAndSettle();
      await _select(tester, 8);
      expect(find.text('语言'), findsOneWidget);
      expect(Theme.of(tester.element(theme)).brightness, Brightness.dark);
      expect(tester.widget<SwitchListTile>(rust).value, isTrue);

      store.fail = true;
      tester.widget<DropdownButton<ThemeMode>>(theme).onChanged!(
        ThemeMode.light,
      );
      await tester.pumpAndSettle();
      expect(Theme.of(tester.element(theme)).brightness, Brightness.dark);
      expect(find.text('无法保存桌面设置，请重试。'), findsOneWidget);
    },
  );

  test(
    'desktop preferences persist independently of shortcut manifests',
    () async {
      final preferences = _SharedPreferences();
      final store = SharedPreferencesDesktopAppPreferencesStore(
        preferences: preferences,
      );
      final defaults = await store.load();
      expect(defaults.language, DesktopAppLanguage.english);
      expect(defaults.themeMode, ThemeMode.system);
      expect(defaults.rustEnabled, isNull);

      await store.save(
        const DesktopAppPreferences(
          language: DesktopAppLanguage.simplifiedChinese,
          themeMode: ThemeMode.light,
          rustEnabled: false,
        ),
      );
      final loaded = await store.load();
      expect(loaded.language, DesktopAppLanguage.simplifiedChinese);
      expect(loaded.themeMode, ThemeMode.light);
      expect(loaded.rustEnabled, isFalse);
      expect(preferences.values.keys, [
        SharedPreferencesDesktopAppPreferencesStore.storageKey,
      ]);
    },
  );

  test(
    'explicit Rust settings override inherited Windows and shared flags',
    () {
      const inherited = {
        'DISPLAY': ':1',
        'LUMIAKEY_DESKTOP_BACKEND': 'rust',
        'LUMIAKEY_WINDOWS_DESKTOP_BACKEND': 'rust',
        'lumiakey_windows_shortcut_backend': 'rust',
      };
      expect(resolveDesktopBackendEnvironment(inherited, null), inherited);
      expect(resolveDesktopBackendEnvironment(inherited, false), {
        'DISPLAY': ':1',
      });
      expect(resolveDesktopBackendEnvironment(inherited, true), {
        'DISPLAY': ':1',
        'LUMIAKEY_DESKTOP_BACKEND': 'rust',
      });
    },
  );
}
