import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumiakeys_companion/desktop_controller.dart';
import 'package:lumiakeys_companion/phone_sidebar_page.dart';
import 'package:lumiakeys_companion/app_library/app_library.dart';
import 'package:lumiakeys_protocol/lumiakeys_protocol.dart';

class Discovery implements ApplicationDiscovery {
  bool removeChrome = false;
  @override
  Future<List<RemoteApplication>> refresh(List<RemoteApplication> apps) async =>
      apps.where((a) => !removeChrome || a.id != 'chrome').toList();
}

class Store extends MemoryDesktopConfigStore {
  bool fail = false;
  Completer<void>? gate;
  Completer<void>? entered;
  @override
  Future<void> save(DesktopManifest value) async {
    if (fail) throw StateError('Fixture write failed');
    final pending = gate;
    if (pending != null) {
      gate = null;
      entered!.complete();
      await pending.future;
    }
    await super.save(value);
  }
}

void main() {
  Future<DesktopController> ready({Store? store, Discovery? discovery}) async {
    final c = DesktopController(
      store: store ?? Store(),
      discovery: discovery ?? Discovery(),
      libraryOperatingSystem: 'windows',
    );
    await c.initialize();
    addTearDown(c.dispose);
    return c;
  }

  test(
    'Desktop controls visibility order defaults and leaves Launchpad unchanged',
    () async {
      final c = await ready();
      final slots = c.launcherAppIds;
      await c.setSidebarVisible(
        const RemoteSidebarItem.application('chatgpt'),
        false,
      );
      expect(c.sidebarItems.any((i) => i.id == 'chatgpt'), false);
      expect(c.manifest.sidebarItems, isNotNull);
      await c.setSidebarVisible(
        const RemoteSidebarItem.application('chatgpt'),
        true,
      );
      expect(c.sidebarItems.last.id, 'chatgpt');
      await c.moveSidebarItem(c.sidebarItems.last, -1);
      expect(c.sidebarItems[c.sidebarItems.length - 2].id, 'chatgpt');
      for (final item in c.sidebarItems) {
        await c.setSidebarVisible(item, false);
      }
      expect(c.sidebarItems, isEmpty);
      expect(c.manifest.sidebarItems, isEmpty);
      expect(c.launcherAppIds, slots);
      await c.restoreSidebarDefaults();
      expect(c.manifest.sidebarItems, isNull);
      expect(c.sidebarItems.first.id, 'chatgpt');
    },
  );
  test(
    'custom sidebar only gains an installed library profile through explicit add',
    () async {
      final c = await ready();
      await c.setSidebarVisible(
        const RemoteSidebarItem.application('chatgpt'),
        false,
      );
      final app = AppLibraryCatalog.builtin.appById('word')!;
      final id = await c.installAppLibrary(
        app.id,
        app.libraryForOS('windows')!.id,
      );
      expect(c.sidebarItems.any((i) => i.id == id), false);
      await c.setSidebarVisible(RemoteSidebarItem.profile(id), true);
      expect(c.sidebarItems.last.key, 'profile:$id');
      await expectLater(
        c.setSidebarVisible(
          const RemoteSidebarItem.application(
            'installed.0123456789abcdef0123456789abcdef',
          ),
          true,
        ),
        throwsFormatException,
      );
    },
  );
  test(
    'failed sidebar writes keep durable list and parallel operations use latest state',
    () async {
      final store = Store();
      final c = await ready(store: store);
      final before = jsonEncode(c.manifestForExport.toJson());
      store.fail = true;
      await expectLater(
        c.setSidebarVisible(
          const RemoteSidebarItem.application('chrome'),
          false,
        ),
        throwsStateError,
      );
      expect(jsonEncode(c.manifestForExport.toJson()), before);
      store.fail = false;
      store.gate = Completer<void>();
      store.entered = Completer<void>();
      final gate = store.gate!;
      final first = c.setSidebarVisible(
        const RemoteSidebarItem.application('chrome'),
        false,
      );
      await store.entered!.future;
      final second = c.setSidebarVisible(
        const RemoteSidebarItem.application('chatgpt'),
        false,
      );
      gate.complete();
      await Future.wait([first, second]);
      expect(
        c.sidebarItems.where((i) => i.id == 'chrome' || i.id == 'chatgpt'),
        isEmpty,
      );
    },
  );
  test(
    'removing an App cleans sidebar references in the same manifest write',
    () async {
      final discovery = Discovery();
      final c = await ready(discovery: discovery);
      await c.setSidebarVisible(
        const RemoteSidebarItem.application('chatgpt'),
        false,
      );
      expect(c.manifest.sidebarItems!.any((i) => i.id == 'chrome'), true);
      discovery.removeChrome = true;
      await c.refreshApplications(forceInstalled: false);
      expect(c.manifest.sidebarItems!.any((i) => i.id == 'chrome'), false);
      expect(
        () => DesktopManifest.fromJson(c.manifestForExport.toJson()),
        returnsNormally,
      );
    },
  );
  testWidgets(
    'phone sidebar offers visible hide and add without changing execution',
    (tester) async {
      final c = await ready();
      await tester.pumpWidget(
        MaterialApp(home: PhoneSidebarPage(controller: c)),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('desktop-sidebar-hide-application:chatgpt')),
      );
      await tester.pumpAndSettle();
      expect(c.sidebarItems.any((i) => i.id == 'chatgpt'), false);
      final add = find.byKey(
        const ValueKey('desktop-sidebar-add-application:chatgpt'),
      );
      await tester.scrollUntilVisible(add, 300);
      await tester.tap(add);
      await tester.pumpAndSettle();
      expect(c.sidebarItems.last.id, 'chatgpt');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
