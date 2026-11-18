import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumiakeys_protocol/lumiakeys_protocol.dart';
import 'package:lumiakeys_companion/app_icon_service.dart';
import 'package:lumiakeys_companion/desktop_actions.dart';
import 'package:lumiakeys_companion/desktop_controller.dart';
import 'package:lumiakeys_companion/icons/builtin_icon_catalog.g.dart';
import 'package:lumiakeys_companion/installed_app_picker.dart';
import 'package:lumiakeys_companion/installed_app_registry.dart';
import 'screenshot_support.dart';

class _Discovery implements ApplicationDiscovery {
  @override
  Future<List<RemoteApplication>> refresh(List<RemoteApplication> apps) async =>
      apps.map((app) => app.copyWith(detected: false)).toList();
}

class _Icons extends NativeAppIconService {
  @override
  Future<Uint8List?> getNativeIcon(RemoteApplication application) async => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(prepareScreenshotFonts);
  testWidgets(
    'installed picker inventory search persistence error and retained unavailable app',
    (tester) async {
      tester.view.physicalSize = const Size(1120, 800);
      tester.view.devicePixelRatio = 1;
      var inventory = [
        for (final item in builtinIconCatalog)
          InstalledLaunchTarget.discovered(
            name: item.name,
            kind: InstalledLaunchKind.linuxDesktopEntry,
            identity: 'demo-${item.id}',
            locator: '/usr/share/applications/demo-${item.id}.desktop',
            iconKey: item.id,
          ),
      ];
      final manual = InstalledLaunchTarget.discovered(
        name: 'Local application',
        kind: InstalledLaunchKind.linuxDesktopEntry,
        identity: 'manual-demo',
        locator: '/home/demo/Applications/Local.desktop',
        manual: true,
      );
      final store = MemoryInstalledRegistryStore();
      final registry = InstalledAppRegistry(
        store: store,
        discover: () async => inventory,
        validate: (_) async => true,
      );
      final controller = DesktopController(
        store: MemoryDesktopConfigStore(),
        discovery: _Discovery(),
        actions: DesktopActions(appIconService: _Icons()),
        installedRegistry: registry,
      );
      await controller.initialize();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      Widget view(Key pickerKey) => RepaintBoundary(
        key: screenshotBoundaryKey,
        child: MaterialApp(
          theme: ThemeData(
            brightness: Brightness.dark,
            useMaterial3: true,
            fontFamily: 'Roboto',
            fontFamilyFallback: screenshotFontFamilyFallback,
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xff67e8f9),
              brightness: Brightness.dark,
            ),
          ),
          home: Scaffold(
            body: Center(
              child: InstalledAppPicker(
                key: pickerKey,
                controller: controller,
                index: 0,
                pickLocal: () async => manual,
              ),
            ),
          ),
        ),
      );
      Future<void> capture(String id, String title, String notes) async {
        expect(tester.takeException(), isNull);
        await captureDesktopScreenshot(
          tester,
          id: id,
          title: title,
          orientation: 'landscape',
          width: 1120,
          height: 800,
          notes:
              '$notes Mocked OS inventory and native artwork miss; no installed app is launched.',
        );
      }

      await tester.pumpWidget(view(const ValueKey('all')));
      await tester.pumpAndSettle();
      await capture(
        'desktop-installed-picker-all',
        'Searchable installed application picker',
        'A virtualized installed-app inventory with refresh and local application selection.',
      );
      await tester.enterText(
        find.byKey(const ValueKey('launcher-app-search')),
        'Firefox',
      );
      await tester.pumpAndSettle();
      await capture(
        'desktop-installed-picker-search',
        'Installed application search',
        'Search finds an OS-registered application beyond the old fixed launcher list.',
      );
      store.failSave = true;
      await tester.tap(find.byKey(const ValueKey('launcher-add-local-app')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('launcher-picker-error')),
        findsOneWidget,
      );
      await capture(
        'desktop-installed-picker-save-error',
        'Local registration save failure',
        'Injected manual-registry write failure; prior slot binding remains unchanged.',
      );
      final removed = inventory.firstWhere(
        (entry) => entry.iconKey == 'firefox',
      );
      await controller.assignLauncherApp(0, removed.id);
      inventory = inventory.where((entry) => entry.id != removed.id).toList();
      await controller.refreshApplications();
      await tester.pumpWidget(view(const ValueKey('unavailable')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('launcher-app-search')),
        'Firefox',
      );
      await tester.pumpAndSettle();
      expect(controller.manifest.applicationById(removed.id)!.detected, false);
      await capture(
        'desktop-installed-picker-unavailable',
        'Unavailable application binding retained',
        'An uninstalled target keeps its selected slot/name but cannot be launched.',
      );
    },
  );
}
