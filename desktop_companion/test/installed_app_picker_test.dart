import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumiakeys_protocol/lumiakeys_protocol.dart';
import 'package:lumiakeys_companion/desktop_controller.dart';
import 'package:lumiakeys_companion/desktop_actions.dart';
import 'package:lumiakeys_companion/app_icon_service.dart';
import 'package:lumiakeys_companion/installed_app_picker.dart';
import 'package:lumiakeys_companion/installed_app_registry.dart';

class _Discovery implements ApplicationDiscovery {
  @override
  Future<List<RemoteApplication>> refresh(List<RemoteApplication> apps) async =>
      apps.map((app) => app.copyWith(detected: true)).toList();
}

// Synthetic OS entries must never reach real host filesystem/native icon I/O
// inside a widget test's fake clock. Native extraction is covered separately.
class _Icons extends NativeAppIconService {
  final requestedIds = <String>[];
  @override
  Future<Uint8List?> getNativeIcon(RemoteApplication application) async {
    requestedIds.add(application.id);
    return null;
  }
}

InstalledLaunchTarget app(String id, {bool manual = false}) =>
    InstalledLaunchTarget.discovered(
      name: 'Installed application $id',
      kind: InstalledLaunchKind.linuxDesktopEntry,
      identity: id,
      locator: '/usr/share/applications/$id.desktop',
      manual: manual,
    );

void main() {
  testWidgets(
    'search reaches applications outside the old preset list and only saves selected ID',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 800);
      tester.view.devicePixelRatio = 1;
      final entries = List.generate(240, (index) => app('item-$index'));
      final icons = _Icons();
      final controller = DesktopController(
        store: MemoryDesktopConfigStore(),
        discovery: _Discovery(),
        actions: DesktopActions(appIconService: icons),
        installedRegistry: InstalledAppRegistry(
          discover: () async => entries,
          validate: (_) async => true,
        ),
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await controller.initialize();
      String? chosen;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                chosen = await showDialog<String>(
                  context: context,
                  builder: (_) =>
                      InstalledAppPicker(controller: controller, index: 0),
                );
              },
              child: const Text('Open picker'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open picker'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('launcher-app-picker')), findsOneWidget);
      expect(
        find.byType(ListTile).evaluate().length,
        lessThan(80),
        reason: 'The installed catalog is virtualized.',
      );
      await tester.enterText(
        find.byKey(const ValueKey('launcher-app-search')),
        'item-239',
      );
      await tester.pumpAndSettle();
      expect(icons.requestedIds, contains(entries.last.id));
      await tester.tap(
        find.byKey(ValueKey('launcher-picker-${entries.last.id}')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('launcher-picker-save')));
      await tester.pumpAndSettle();
      expect(chosen, entries.last.id);
      expect(
        controller.launcherAppIds.first,
        isNull,
        reason:
            'The dialog returns an ID; controller owns the atomic slot save.',
      );
      await controller.assignLauncherApp(0, chosen);
      expect(controller.launcherAppIds.first, entries.last.id);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'failed manual persistence shows feedback and cannot select or bind the unsaved target',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 800);
      tester.view.devicePixelRatio = 1;
      final store = MemoryInstalledRegistryStore()..failSave = true;
      final registry = InstalledAppRegistry(
        store: store,
        validate: (_) async => true,
      );
      final controller = DesktopController(
        store: MemoryDesktopConfigStore(),
        discovery: _Discovery(),
        installedRegistry: registry,
        actions: DesktopActions(appIconService: _Icons()),
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await controller.initialize();
      final manual = app('manual', manual: true);
      await tester.pumpWidget(
        MaterialApp(
          home: InstalledAppPicker(
            controller: controller,
            index: 0,
            pickLocal: () async => manual,
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('launcher-add-local-app')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('launcher-picker-error')),
        findsOneWidget,
      );
      expect(registry.resolve(manual.id), isNull);
      expect(controller.launcherAppIds.first, isNull);
      expect(store.value, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}
