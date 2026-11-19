import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumiakeys_companion/app_library/app_library.dart';
import 'package:lumiakeys_companion/desktop_controller.dart';
import 'package:lumiakeys_companion/desktop_profiles.dart';
import 'package:lumiakeys_protocol/lumiakeys_protocol.dart';

class _Discovery implements ApplicationDiscovery {
  @override
  Future<List<RemoteApplication>> refresh(List<RemoteApplication> apps) async =>
      apps;
}

class _Store extends MemoryDesktopConfigStore {
  bool fail = false;

  @override
  Future<void> save(DesktopManifest manifest) async {
    if (fail) throw StateError('Fixture write failure');
    await super.save(manifest);
  }
}

Future<DesktopController> _ready([MemoryDesktopConfigStore? store]) async {
  final controller = DesktopController(
    store: store ?? _Store(),
    discovery: _Discovery(),
    libraryOperatingSystem: 'windows',
  );
  addTearDown(controller.dispose);
  await controller.initialize();
  return controller;
}

Future<String> _installChrome(DesktopController controller) {
  final app = AppLibraryCatalog.builtin.appById('chrome')!;
  return controller.installAppLibrary(app.id, app.libraryForOS('windows')!.id);
}

void main() {
  test(
    'new profiles validate their names/layouts and persist their IDs',
    () async {
      final store = _Store();
      final controller = await _ready(store);
      final revision = controller.manifest.revision;

      final id = await controller.addProfile(
        name: '  Focus  ',
        layoutId: 'keyboard',
      );
      expect(id, isNot('default'));
      expect(controller.manifest.profiles.last.name, 'Focus');
      expect(controller.manifest.currentProfileId, 'default');
      expect(controller.manifest.revision, revision + 1);
      for (final name in ['', ' focus ', 'Some\nName', 'x' * 65]) {
        await expectLater(
          controller.addProfile(name: name, layoutId: 'keyboard'),
          throwsFormatException,
        );
      }
      await expectLater(
        controller.addProfile(name: 'Other', layoutId: 'missing'),
        throwsFormatException,
      );
      expect(controller.manifest.revision, revision + 1);

      final reopened = await _ready(store);
      final profile = reopened.manifest.profiles.singleWhere(
        (profile) => profile.id == id,
      );
      expect(profile.name, 'Focus');
      expect(profile.layoutId, 'keyboard');
    },
  );

  test(
    'deleting the active profile selects Default and retains its shared layout',
    () async {
      final store = _Store();
      final controller = await _ready(store);
      await expectLater(
        controller.deleteProfile('default'),
        throwsFormatException,
      );
      final id = await controller.addProfile(
        name: 'Focus',
        layoutId: 'keyboard',
      );
      await controller.switchProfile(id);
      final revision = controller.manifest.revision;
      await controller.deleteProfile(id);

      expect(controller.manifest.currentProfileId, 'default');
      expect(controller.manifest.profiles.map((profile) => profile.id), [
        'default',
      ]);
      expect(controller.manifest.layoutById('keyboard'), isNotNull);
      expect(store.value!.revision, revision + 1);
      await expectLater(controller.switchProfile(id), throwsFormatException);
    },
  );

  test(
    'a legacy config without Default keeps its profiles and protects the last one',
    () async {
      final store = _Store()
        ..value = DesktopManifest.regularStarter().copyWith(
          profiles: const [
            RemoteProfile(id: 'first', name: 'First', layoutId: 'keyboard'),
            RemoteProfile(id: 'second', name: 'Second', layoutId: 'keyboard'),
          ],
          currentProfileId: 'second',
        );
      final controller = await _ready(store);
      expect(controller.manifest.profiles.map((profile) => profile.id), [
        'first',
        'second',
      ]);
      await controller.deleteProfile('second');
      expect(controller.manifest.currentProfileId, 'first');
      await expectLater(
        controller.deleteProfile('first'),
        throwsFormatException,
      );
    },
  );

  test(
    'deleting a library profile removes its actions and sidebar entry in one save',
    () async {
      final store = _Store();
      final controller = await _ready(store);
      final id = await _installChrome(controller);
      final library = controller.manifest.profiles.singleWhere(
        (profile) => profile.id == id,
      );
      final libraryButton = controller.manifest
          .layoutById(library.layoutId)!
          .buttons
          .first
          .id;
      expect(
        controller.profileLayoutOptions.any(
          (layout) => layout.id == library.layoutId,
        ),
        isFalse,
      );
      await expectLater(
        controller.addProfile(name: 'Unsafe copy', layoutId: library.layoutId),
        throwsFormatException,
      );
      await controller.setSidebarVisible(RemoteSidebarItem.profile(id), false);
      await controller.setSidebarVisible(RemoteSidebarItem.profile(id), true);
      await controller.switchProfile(id);
      final writes = store.saveCount;

      store.fail = true;
      await expectLater(controller.deleteProfile(id), throwsStateError);
      expect(controller.manifest.currentProfileId, id);
      expect(controller.manifest.layoutById(library.layoutId), isNotNull);
      expect(
        controller.manifest.sidebarItems!.any((item) => item.id == id),
        isTrue,
      );

      store.fail = false;
      await controller.deleteProfile(id);
      expect(store.saveCount, writes + 1);
      expect(store.value!.currentProfileId, 'default');
      expect(store.value!.layoutById(library.layoutId), isNull);
      expect(store.value!.sidebarItems!.any((item) => item.id == id), isFalse);
      await expectLater(
        controller.executeRemote(RemoteActionRequest.button(libraryButton)),
        throwsFormatException,
      );
    },
  );

  testWidgets('Profiles adds a layout selection and asks before deleting', (
    tester,
  ) async {
    final controller = await _ready();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: DesktopProfilesPage(controller: controller)),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('desktop-add-profile')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('desktop-profile-name')),
      'Focus',
    );
    await tester.tap(find.byKey(const ValueKey('desktop-profile-add-confirm')));
    await tester.pumpAndSettle();
    final added = controller.manifest.profiles.singleWhere(
      (profile) => profile.name == 'Focus',
    );
    expect(added.layoutId, 'keyboard');
    expect(find.text('Focus'), findsOneWidget);

    final delete = find.byKey(ValueKey('desktop-delete-profile-${added.id}'));
    await tester.tap(delete);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(
      controller.manifest.profiles.any((profile) => profile.id == added.id),
      isTrue,
    );

    await tester.tap(delete);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('desktop-profile-delete-confirm')),
    );
    await tester.pumpAndSettle();
    expect(
      controller.manifest.profiles.any((profile) => profile.id == added.id),
      isFalse,
    );
    expect(
      find.byKey(const ValueKey('desktop-delete-profile-default')),
      findsNothing,
    );
  });
}
