import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumiakeys_protocol/lumiakeys_protocol.dart';
import 'package:smart_keys/app_library/app_library.dart';
import 'package:smart_keys/icons/source_profile_icon.dart';
import 'regular_home_test_support.dart';
import 'test_support.dart';

RemoteProfile profile({String? applicationId, String? png, String? hash}) =>
    RemoteProfile(
      id: 'library.test',
      name: 'My Word shortcuts',
      layoutId: 'library.test',
      platform: 'windows',
      applicationId: applicationId,
      sourceAppId: applicationId ?? 'word',
      sourceIconId: applicationId ?? 'word',
      sourceLibraryId: 'word.windowsLinux',
      sourceLibraryVersion: '1',
      sourceIconPngBase64: png,
      sourceIconSha256: hash,
    );
void main() {
  testWidgets(
    'received manual library profile selects locally, sends only explicit keys, and resets across hosts',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(844, 390);
      final harness = await TestHarness.create();
      final starter = DesktopManifest.regularStarter();
      final layout = RemoteShortcutLayout(
        id: 'library.test',
        name: 'My Word shortcuts',
        kind: RemoteLayoutKind.application,
        buttons: [
          const RemoteShortcutButton(
            id: 'library.test.save',
            name: 'Save',
            icon: 'save',
            targetType: RemoteTargetType.keyboardShortcut,
            shortcut: ['CTRL', 'S'],
          ),
          const RemoteShortcutButton(
            id: 'library.test.unassigned',
            name: 'Configure me',
            icon: 'keyboard',
            targetType: RemoteTargetType.keyboardShortcut,
            shortcut: [],
            enabled: false,
          ),
        ],
      );
      connectRegularHarness(
        harness,
        manifest: starter.copyWith(
          profiles: [...starter.profiles, profile()],
          layouts: [...starter.layouts, layout],
        ),
        installed: const {'chrome'},
      );
      try {
        await tester.pumpWidget(regularTestApp(harness));
        await tester.pumpAndSettle();
        final nav = find.byKey(
          const ValueKey('regular-nav-library-profile-library.test'),
        );
        await tester.ensureVisible(nav);
        await tester.tap(nav);
        await tester.pumpAndSettle();
        expect(harness.companion.remoteActions, isEmpty);
        expect(find.textContaining('Manual keyboard profile'), findsOneWidget);
        await tester.tap(
          find.byKey(const ValueKey('regular-button-library.test.unassigned')),
        );
        await tester.pumpAndSettle();
        expect(harness.companion.remoteActions, isEmpty);
        await tester.tap(
          find.byKey(const ValueKey('regular-button-library.test.save')),
        );
        await tester.pumpAndSettle();
        expect(
          harness.companion.remoteActions.single.buttonId,
          'library.test.save',
        );
        expect(harness.hid.steppedActions, isEmpty);
        harness.companion.host.value = null;
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<Text>(
                find.byKey(const ValueKey('regular-workspace-title')),
              )
              .data,
          'Launchpad',
        );
      } finally {
        await tester.pumpWidget(const SizedBox());
        await harness.dispose();
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      }
    },
  );
  test(
    'received artwork validates registered hash and bounded PNG before display',
    () {
      final png = File(
        'packages/app_icon_catalog/png/gimp.png',
      ).readAsBytesSync();
      final p = RemoteProfile(
        id: 'library.gimp',
        name: 'Gimp',
        layoutId: 'library.gimp',
        platform: 'windows',
        sourceAppId: 'gimp',
        sourceIconId: 'gimp',
        sourceLibraryId: 'gimp.windowsLinux',
        sourceLibraryVersion: '1',
        sourceIconPngBase64: base64Encode(png),
        sourceIconSha256: registeredAppIconHash('gimp'),
      );
      expect(sourceProfileIcon(p), png);
      expect(
        sourceProfileIcon(profile(png: base64Encode(png), hash: '0' * 64)),
        isNull,
      );
      expect(
        sourceProfileIcon(
          profile(png: 'invalid', hash: registeredAppIconHash('word')),
        ),
        isNull,
      );
    },
  );
}
