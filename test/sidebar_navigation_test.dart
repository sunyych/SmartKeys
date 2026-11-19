import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumiakeys_protocol/lumiakeys_protocol.dart';
import 'package:smart_keys/services/companion_service.dart';
import 'regular_home_test_support.dart';
import 'test_support.dart';

class DeferredSidebarCompanion extends RecordingCompanionService {
  final gate = Completer<void>();
  @override
  Future<void> executeRemote(RemoteActionRequest request) async {
    remoteActions.add(request);
    if (request.kind == RemoteActionKind.launchApplication) await gate.future;
  }
}

const libraryProfile = RemoteProfile(
  id: 'library.sidebar',
  name: 'My Word keys',
  layoutId: 'library.sidebar',
  platform: 'windows',
  sourceAppId: 'word',
  sourceIconId: 'word',
  sourceLibraryId: 'word.windowsLinux',
  sourceLibraryVersion: '1',
);
const libraryLayout = RemoteShortcutLayout(
  id: 'library.sidebar',
  name: 'My Word keys',
  kind: RemoteLayoutKind.application,
  buttons: [
    RemoteShortcutButton(
      id: 'library.sidebar.save',
      name: 'Save',
      icon: 'save',
      targetType: RemoteTargetType.keyboardShortcut,
      shortcut: ['CTRL', 'S'],
    ),
  ],
);
void main() {
  Future<TestHarness> mount(
    WidgetTester tester, {
    List<RemoteSidebarItem>? items,
    RecordingCompanionService? service,
    Set<String> shortcutOnlyApplicationIds = const {},
    bool autoLaunchApps = true,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(844, 390);
    final h = await TestHarness.create(
      companionService: service ?? ActivatingRegularCompanion(),
    );
    final base = DesktopManifest.regularStarter();
    connectRegularHarness(
      h,
      manifest: base.copyWith(
        settings: base.settings.copyWith(autoLaunchApps: autoLaunchApps),
        sidebarItems: items,
        sidebarShortcutOnlyApplicationIds: shortcutOnlyApplicationIds,
        profiles: [...base.profiles, libraryProfile],
        layouts: [...base.layouts, libraryLayout],
      ),
      installed: const {'chrome', 'chatgpt'},
      launcherSlots: ['chrome', ...List<String?>.filled(11, null)],
    );
    await tester.pumpWidget(regularTestApp(h));
    await tester.pumpAndSettle();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await h.dispose();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    return h;
  }

  Finder nav(String id) => find.byKey(ValueKey('regular-nav-$id'));
  String title(WidgetTester tester) => tester
      .widget<Text>(find.byKey(const ValueKey('regular-workspace-title')))
      .data!;
  testWidgets(
    'Desktop sidebar order interleaves profiles and Apps with fixed top entries',
    (tester) async {
      final h = await mount(
        tester,
        items: const [
          RemoteSidebarItem.profile('library.sidebar'),
          RemoteSidebarItem.application('chrome'),
          RemoteSidebarItem.application('chatgpt'),
        ],
      );
      expect(
        tester.getTopLeft(nav('launchpad')).dy,
        lessThan(tester.getTopLeft(nav('general')).dy),
      );
      expect(
        tester.getTopLeft(nav('library-profile-library.sidebar')).dy,
        lessThan(tester.getTopLeft(nav('chrome')).dy),
      );
      expect(
        tester.getTopLeft(nav('chrome')).dy,
        lessThan(tester.getTopLeft(nav('chatgpt')).dy),
      );
      await tester.ensureVisible(nav('library-profile-library.sidebar'));
      await tester.tap(nav('library-profile-library.sidebar'));
      await tester.pumpAndSettle();
      expect(title(tester), 'My Word keys');
      expect(h.companion.remoteActions, isEmpty);
      await tester.tap(
        find.byKey(const ValueKey('regular-button-library.sidebar.save')),
      );
      await tester.pumpAndSettle();
      expect(h.companion.remoteActions.single.buttonId, 'library.sidebar.save');
    },
  );
  testWidgets(
    'explicit empty sidebar keeps fixed entries and Launchpad launch behavior',
    (tester) async {
      final h = await mount(tester, items: const []);
      expect(nav('launchpad'), findsOneWidget);
      expect(nav('general'), findsOneWidget);
      expect(nav('chrome'), findsNothing);
      expect(nav('library-profile-library.sidebar'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('regular-launch-chrome')));
      await tester.pumpAndSettle();
      expect(h.companion.remoteActions.single.applicationId, 'chrome');
      expect(title(tester), 'Chrome');
    },
  );
  testWidgets(
    'legacy absence retains automatic App and installed profile navigation',
    (tester) async {
      await mount(tester);
      expect(nav('chatgpt'), findsOneWidget);
      expect(nav('chrome'), findsOneWidget);
      expect(nav('library-profile-library.sidebar'), findsOneWidget);
      expect(
        tester.getTopLeft(nav('chatgpt')).dy,
        lessThan(tester.getTopLeft(nav('chrome')).dy),
      );
    },
  );
  testWidgets(
    'shortcut-only App Bar entry waits for manual foreground and sends no launch',
    (tester) async {
      final h = await mount(
        tester,
        shortcutOnlyApplicationIds: const {'chrome'},
      );
      final shortcut = find.byKey(
        const ValueKey('regular-button-chrome.newTab'),
      );
      await tester.tap(nav('chrome'));
      await tester.pumpAndSettle();
      expect(title(tester), 'Chrome');
      expect(h.companion.remoteActions, isEmpty);
      expect(
        find.textContaining('Bring the application to the foreground'),
        findsOneWidget,
      );
      await tester.tap(shortcut);
      await tester.pumpAndSettle();
      expect(h.companion.remoteActions, isEmpty);

      void setForeground(String id) {
        final previous = h.companion.syncedManifest.value!;
        h.companion.syncedManifest.value = previous.copyWith(
          applications: [
            for (final app in previous.applications)
              app.copyWith(foreground: app.id == id),
          ],
        );
      }

      setForeground('chrome');
      await tester.pumpAndSettle();
      await tester.tap(shortcut);
      await tester.pumpAndSettle();
      expect(h.companion.remoteActions.single.buttonId, 'chrome.newTab');

      setForeground('chatgpt');
      await tester.pumpAndSettle();
      await tester.tap(shortcut);
      await tester.pumpAndSettle();
      expect(h.companion.remoteActions, hasLength(1));
      await tester.tap(nav('launchpad'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('regular-launch-chrome')));
      await tester.pumpAndSettle();
      expect(h.companion.remoteActions.last.applicationId, 'chrome');
      expect(title(tester), 'Chrome');
    },
  );
  testWidgets('disabling global launching opens the App Bar panel directly', (
    tester,
  ) async {
    final h = await mount(tester, autoLaunchApps: false);
    await tester.tap(nav('chrome'));
    await tester.pumpAndSettle();
    expect(title(tester), 'Chrome');
    expect(h.companion.remoteActions, isEmpty);
  });
  testWidgets(
    'hiding the selected App returns safely to Launchpad without another launch',
    (tester) async {
      final h = await mount(
        tester,
        items: const [RemoteSidebarItem.application('chrome')],
      );
      await tester.tap(nav('chrome'));
      await tester.pumpAndSettle();
      expect(title(tester), 'Chrome');
      h.companion.syncedManifest.value = h.companion.syncedManifest.value!
          .copyWith(sidebarItems: const []);
      await tester.pumpAndSettle();
      expect(title(tester), 'Launchpad');
      expect(nav('chrome'), findsNothing);
      expect(h.companion.remoteActions, hasLength(1));
    },
  );
  testWidgets('hiding pending sidebar activation cancels its late completion', (
    tester,
  ) async {
    final service = DeferredSidebarCompanion();
    final h = await mount(
      tester,
      items: const [RemoteSidebarItem.application('chrome')],
      service: service,
    );
    await tester.tap(nav('chrome'));
    await tester.pump();
    expect(service.remoteActions, hasLength(1));
    h.companion.syncedManifest.value = h.companion.syncedManifest.value!
        .copyWith(sidebarItems: const []);
    await tester.pumpAndSettle();
    service.gate.complete();
    await tester.pumpAndSettle();
    expect(title(tester), 'Launchpad');
    expect(nav('chrome'), findsNothing);
    expect(
      find.byKey(const ValueKey('regular-button-chrome.newTab')),
      findsNothing,
    );
    expect(service.remoteActions, hasLength(1));
  });
}
