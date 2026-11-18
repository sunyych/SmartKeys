import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumiakeys_protocol/lumiakeys_protocol.dart';
import 'package:smart_keys/services/companion_service.dart';

import 'regular_home_test_support.dart';
import 'test_support.dart';

const _profileId = 'received.chrome';
const _buttonId = 'received.chrome.save';

DesktopManifest _manifest({String? boundApp}) {
  final starter = DesktopManifest.regularStarter();
  return starter.copyWith(
    profiles: [
      ...starter.profiles,
      RemoteProfile(
        id: _profileId,
        name: 'Chrome library',
        layoutId: _profileId,
        platform: 'windows',
        applicationId: boundApp,
        sourceAppId: 'chrome',
        sourceIconId: 'chrome',
        sourceLibraryId: 'chrome.windowsLinux',
        sourceLibraryVersion: '1',
      ),
    ],
    layouts: [
      ...starter.layouts,
      const RemoteShortcutLayout(
        id: _profileId,
        name: 'Chrome library',
        kind: RemoteLayoutKind.application,
        buttons: [
          RemoteShortcutButton(
            id: _buttonId,
            name: 'Save',
            icon: 'save',
            targetType: RemoteTargetType.keyboardShortcut,
            shortcut: ['CTRL', 'S'],
          ),
        ],
      ),
    ],
  );
}

Future<TestHarness> _mount(
  WidgetTester tester, {
  String? boundApp,
  DesktopManifest? manifest,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(844, 390);
  final harness = await TestHarness.create(
    companionService: ActivatingRegularCompanion(),
  );
  connectRegularHarness(
    harness,
    manifest: manifest ?? _manifest(boundApp: boundApp),
    installed: const {'chrome'},
  );
  await tester.pumpWidget(regularTestApp(harness));
  await tester.pumpAndSettle();
  final nav = find.byKey(
    const ValueKey('regular-nav-library-profile-$_profileId'),
  );
  await tester.ensureVisible(nav);
  await tester.tap(nav);
  await tester.pumpAndSettle();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    await harness.dispose();
  });
  return harness;
}

void main() {
  testWidgets(
    'received libraries follow the selected host OS without implicit input',
    (tester) async {
      final starter = _manifest();
      final harness = await _mount(
        tester,
        manifest: starter.copyWith(
          profiles: [
            ...starter.profiles,
            const RemoteProfile(
              id: 'received.safari',
              name: 'Safari library',
              layoutId: 'received.safari',
              platform: 'macos',
              sourceAppId: 'safari',
              sourceIconId: 'safari',
              sourceLibraryId: 'safari.macos',
              sourceLibraryVersion: '1',
            ),
          ],
          layouts: [
            ...starter.layouts,
            const RemoteShortcutLayout(
              id: 'received.safari',
              name: 'Safari library',
              kind: RemoteLayoutKind.application,
              buttons: [
                RemoteShortcutButton(
                  id: 'received.safari.new-tab',
                  name: 'New tab',
                  icon: 'add',
                  targetType: RemoteTargetType.keyboardShortcut,
                  shortcut: ['META', 'T'],
                ),
              ],
            ),
          ],
        ),
      );
      final chrome = find.byKey(
        const ValueKey('regular-nav-library-profile-$_profileId'),
      );
      final safari = find.byKey(
        const ValueKey('regular-nav-library-profile-received.safari'),
      );
      expect(chrome, findsOneWidget);
      expect(safari, findsNothing);
      harness.companion.host.value = const CompanionHost(
        name: 'Mac fixture',
        computerId: 'mac-fixture',
        platform: 'macos',
        address: '192.168.1.22',
        port: 45833,
        token: 'mac-fixture',
        capabilities: {'manifest', 'mouse-control-v1'},
      );
      await tester.pumpAndSettle();
      expect(chrome, findsNothing);
      expect(safari, findsOneWidget);
      await tester.ensureVisible(safari);
      await tester.tap(safari);
      await tester.pumpAndSettle();
      expect(find.text('New tab'), findsOneWidget);
      expect(harness.companion.remoteActions, isEmpty);
      expect(harness.hid.pressedActions, isEmpty);
      expect(harness.hid.steppedActions, isEmpty);
    },
  );

  testWidgets(
    'received app-bound library never launches and follows foreground authority',
    (tester) async {
      final harness = await _mount(tester, boundApp: 'chrome');
      final button = find.byKey(const ValueKey('regular-button-$_buttonId'));
      expect(harness.companion.remoteActions, isEmpty);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(harness.companion.remoteActions, isEmpty);
      void foreground(bool active) {
        final current = harness.companion.syncedManifest.value!;
        harness.companion.syncedManifest.value = current.copyWith(
          applications: [
            for (final app in current.applications)
              app.copyWith(foreground: app.id == 'chrome' && active),
          ],
        );
      }

      foreground(true);
      await tester.pumpAndSettle();
      expect(harness.companion.remoteActions, isEmpty);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(
        harness.companion.remoteActions.single.kind,
        RemoteActionKind.button,
      );
      expect(harness.companion.remoteActions.single.buttonId, _buttonId);
      foreground(false);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(harness.companion.remoteActions, hasLength(1));
      expect(harness.hid.pressedActions, isEmpty);
      expect(harness.hid.steppedActions, isEmpty);
    },
  );

  for (final surface in ['library', 'general', 'app', 'launcher', 'app-nav']) {
    for (final transition in ['host', 'epoch']) {
      // The three keyboard surfaces share one grid; the two application launch
      // entrances must independently retain their rendered host authority.
      if (transition == 'epoch' &&
          (surface == 'launcher' || surface == 'app-nav')) {
        continue;
      }
      testWidgets(
        '$surface old pointer cannot cross $transition before repaint; fresh input works',
        (tester) async {
          final harness = await _mount(tester);
          Future<Finder> target() async {
            final navId = switch (surface) {
              'general' => 'general',
              'app' => 'chrome',
              'launcher' || 'app-nav' => 'launchpad',
              _ => 'library-profile-$_profileId',
            };
            final nav = find.byKey(ValueKey('regular-nav-$navId'));
            await tester.ensureVisible(nav);
            await tester.tap(nav);
            await tester.pumpAndSettle();
            harness.companion.remoteActions.clear();
            return find.byKey(
              ValueKey(switch (surface) {
                'general' => 'regular-button-keyboard.copy',
                'app' => 'regular-button-chrome.newTab',
                'launcher' => 'regular-launch-chrome',
                'app-nav' => 'regular-nav-chrome',
                _ => 'regular-button-$_buttonId',
              }),
            );
          }

          final button = await target();
          await tester.ensureVisible(button);
          final finger = await tester.startGesture(tester.getCenter(button));
          if (transition == 'epoch') {
            await harness.controller.prepareForContextChange();
          } else {
            final oldManifest = harness.companion.syncedManifest.value!;
            harness.companion.status.value = CompanionSyncStatus.syncing;
            harness.companion.host.value = null;
            harness.companion.syncedManifest.value = null;
            harness.companion.host.value = const CompanionHost(
              name: 'Other PC',
              computerId: 'other-pc',
              platform: 'windows',
              address: '192.168.1.21',
              port: 45833,
              token: 'other-session',
              capabilities: {'manifest', 'mouse-control-v1'},
            );
            harness.companion.syncedManifest.value = oldManifest.copyWith(
              computerId: 'other-pc',
            );
            harness.companion.status.value = CompanionSyncStatus.ready;
          }
          // Deliberately release before the next frame: a previous InkWell remains in
          // the pointer route even though connection state has already changed.
          await finger.up();
          await tester.pumpAndSettle();
          expect(harness.companion.remoteActions, isEmpty);
          expect(harness.hid.pressedActions, isEmpty);
          expect(harness.hid.steppedActions, isEmpty);
          final fresh = await target();
          await tester.ensureVisible(fresh);
          await tester.tap(fresh);
          await tester.pumpAndSettle();
          expect(harness.companion.remoteActions, hasLength(1));
          expect(
            harness.companion.remoteActions.single.kind,
            surface == 'launcher' || surface == 'app-nav'
                ? RemoteActionKind.launchApplication
                : RemoteActionKind.button,
          );
        },
      );
    }
  }
}
