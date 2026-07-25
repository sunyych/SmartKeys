import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image_lib;
import 'package:path/path.dart' as path;
import 'package:smart_keys/app.dart';
import 'package:smart_keys/models/config.dart';
import 'package:smart_keys/services/companion_service.dart';
import 'package:smart_keys/services/hid_service.dart';
import 'package:smart_keys/ui/widgets/button_face.dart';

import 'test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('portrait uses a 3 by 5 button grid', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final harness = await TestHarness.create();
    addTearDown(() => _disposeHarness(tester, harness));

    await tester.pumpWidget(SmartKeysApp(controller: harness.controller));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byKey(const ValueKey('portrait-layout')), findsOneWidget);
    expect(find.byKey(const ValueKey('button-grid-3x5')), findsOneWidget);
    expect(find.byKey(const ValueKey('control-button-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('control-button-14')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('profile-quick-switch-bar')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('control-surface-status-bar')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('status-mode-hid')), findsOneWidget);
    expect(find.text('HID'), findsOneWidget);
    expect(find.byKey(const ValueKey('control-menu')), findsOneWidget);
  });

  testWidgets(
    'keeps HID, Desktop sync, and foreground app states independent',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final harness = await TestHarness.create();
      addTearDown(() => _disposeHarness(tester, harness));

      await tester.pumpWidget(SmartKeysApp(controller: harness.controller));
      await tester.pump();
      expect(find.byKey(const ValueKey('button-grid-3x5')), findsOneWidget);
      expect(find.byKey(const ValueKey('status-mode-hid')), findsOneWidget);

      harness.companion.syncedManifest.value = desktopManifest(
        installed: const {'vscode'},
      );
      harness.companion.host.value = connectedCompanionHost;
      harness.companion.status.value = CompanionSyncStatus.ready;
      await tester.pump();

      expect(find.byKey(const ValueKey('status-mode-desktop')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('remote-layout-keyboard')),
        findsOneWidget,
      );

      harness.companion.syncedManifest.value = desktopManifest(
        installed: const {'vscode'},
        running: const {'vscode'},
        foreground: 'vscode',
      );
      await tester.pump();

      expect(find.byKey(const ValueKey('status-mode-app')), findsOneWidget);
      expect(find.text('VSCode'), findsWidgets);
      expect(
        find.byKey(const ValueKey('remote-layout-app.vscode')),
        findsOneWidget,
      );

      harness.companion.host.value = null;
      harness.companion.status.value = CompanionSyncStatus.discovering;
      await tester.pump();

      expect(find.byKey(const ValueKey('status-mode-hid')), findsOneWidget);
      expect(find.byKey(const ValueKey('button-grid-3x5')), findsOneWidget);
    },
  );

  testWidgets('desktop manifest reveals Apps and executes synced ids', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final harness = await TestHarness.create();
    addTearDown(() => _disposeHarness(tester, harness));
    harness.companion.syncedManifest.value = desktopManifest(
      installed: const {'vscode', 'codex'},
      running: const {'vscode'},
    );
    harness.companion.host.value = connectedCompanionHost;
    harness.companion.status.value = CompanionSyncStatus.ready;

    await tester.pumpWidget(SmartKeysApp(controller: harness.controller));
    await tester.pump();

    await tester.drag(
      find.byKey(const ValueKey('profile-quick-switch-bar')),
      const Offset(-600, 0),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('home-tab-apps')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-tab-codex')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('profile-quick-profile_general')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('desktop-profile-default')), findsNothing);
    expect(find.byKey(const ValueKey('workspace-app-vscode')), findsOneWidget);
    expect(find.byKey(const ValueKey('workspace-app-codex')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('home-tab-apps')));
    await tester.pump();

    expect(find.byKey(const ValueKey('remote-app-vscode')), findsOneWidget);
    final appButtonSize = tester.getSize(
      find.byKey(const ValueKey('remote-app-vscode')),
    );
    expect(appButtonSize.width / appButtonSize.height, closeTo(1, 0.05));
    final appIcon = tester.widget<Image>(
      find.descendant(
        of: find.byKey(const ValueKey('remote-app-vscode')),
        matching: find.byType(Image),
      ),
    );
    expect(
      (appIcon.image as AssetImage).assetName,
      'assets/app_icons/vscode.png',
    );
    await tester.tap(find.byKey(const ValueKey('remote-app-vscode')));
    await tester.pump();

    expect(harness.companion.remoteActions.single.applicationId, 'vscode');
    expect(find.byKey(const ValueKey('apps-grid')), findsNothing);
    expect(
      find.byKey(const ValueKey('remote-layout-app.vscode')),
      findsOneWidget,
    );

    expect(find.byKey(const ValueKey('wheel-region')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('remote-button-vscode.save')));
    await tester.pump();
    expect(harness.companion.remoteActions.last.buttonId, 'vscode.save');

    await tester.drag(
      find.byKey(const ValueKey('profile-quick-switch-bar')),
      const Offset(-120, 0),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('home-tab-codex')));
    await tester.pump();
    expect(find.byKey(const ValueKey('remote-layout-codex')), findsOneWidget);
    expect(find.byKey(const ValueKey('wheel-region')), findsOneWidget);
  });

  testWidgets('opening an installed Chrome app enters its shortcut layout', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final harness = await TestHarness.create();
    addTearDown(() => _disposeHarness(tester, harness));
    harness.companion.syncedManifest.value = desktopManifest(
      installed: const {'chrome'},
    );
    harness.companion.host.value = connectedCompanionHost;
    harness.companion.status.value = CompanionSyncStatus.ready;

    await tester.pumpWidget(SmartKeysApp(controller: harness.controller));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('home-tab-apps')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('remote-app-chrome')));
    await tester.pump();

    expect(harness.companion.remoteActions.single.applicationId, 'chrome');
    expect(
      find.byKey(const ValueKey('remote-layout-app.chrome')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('remote-button-chrome.bookmark')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('remote-button-chrome.passwordManager')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('remote-button-chrome.mute')),
      findsOneWidget,
    );
  });

  testWidgets('landscape uses 5 by 3 and a two-thirds/one-third split', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(844, 390);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final harness = await TestHarness.create(
      config: testConfig(
        profiles: [
          profile(),
          profile(id: 'profile_web', name: 'Web'),
          profile(id: 'profile_teams', name: 'Teams'),
        ],
      ),
    );
    addTearDown(() => _disposeHarness(tester, harness));

    await tester.pumpWidget(SmartKeysApp(controller: harness.controller));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byKey(const ValueKey('landscape-layout')), findsOneWidget);
    expect(find.byKey(const ValueKey('button-grid-5x3')), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.byType(NavigationBar), findsNothing);
    final navigation = find.byKey(const ValueKey('profile-quick-switch-bar'));
    for (final label in ['General', 'Web', 'Teams']) {
      expect(
        find.descendant(of: navigation, matching: find.text(label)),
        findsWidgets,
      );
    }
    expect(
      find.descendant(of: navigation, matching: find.text('Settings')),
      findsNothing,
    );
    final keyWidth = tester
        .getSize(find.byKey(const ValueKey('key-region')))
        .width;
    final wheelWidth = tester
        .getSize(find.byKey(const ValueKey('wheel-region')))
        .width;
    expect(keyWidth / wheelWidth, closeTo(2, 0.05));

    harness.companion.syncedManifest.value = desktopManifest(
      installed: const {'codex'},
    );
    harness.companion.host.value = connectedCompanionHost;
    harness.companion.status.value = CompanionSyncStatus.ready;
    await tester.pump();
    expect(
      find.descendant(of: navigation, matching: find.text('Web')),
      findsNothing,
    );
    expect(
      find.descendant(of: navigation, matching: find.text('Teams')),
      findsNothing,
    );
    await tester.tap(find.byKey(const ValueKey('home-tab-codex')));
    await tester.pump();
    expect(find.byKey(const ValueKey('remote-layout-codex')), findsOneWidget);
    expect(find.byKey(const ValueKey('landscape-layout')), findsOneWidget);
    expect(find.byKey(const ValueKey('wheel-region')), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('profile-quick-profile_general')),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('landscape-layout')), findsOneWidget);
  });

  testWidgets('quick profile bar switches and menu opens the selector', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(844, 390);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final harness = await TestHarness.create(
      config: testConfig(
        profiles: [
          profile(),
          profile(id: 'profile_web', name: 'Web'),
          profile(id: 'profile_meetings', name: 'Zoom / Teams'),
        ],
      ),
    );
    addTearDown(() => _disposeHarness(tester, harness));
    await tester.pumpWidget(SmartKeysApp(controller: harness.controller));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('profile-quick-profile_web')));
    await tester.pumpAndSettle();
    expect(harness.controller.activeProfile.id, 'profile_web');

    await _openControlMenu(tester);
    await tester.tap(find.text('Profiles · Web'));
    await tester.pumpAndSettle();
    expect(find.text('Profiles'), findsOneWidget);
    expect(find.text('Zoom / Teams'), findsAtLeast(1));
  });

  testWidgets('touchpad moves, left-clicks, and two-finger right-clicks', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(844, 390);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final mouseProfile = profile().copyWith(
      wheel: const WheelConfig(
        controlType: WheelControlType.mousePad,
        modeLabel: 'Touchpad',
        up: HidAction(type: ActionType.mouseMove, value: 'UP'),
        down: HidAction(type: ActionType.mouseMove, value: 'DOWN'),
        left: HidAction(type: ActionType.mouseMove, value: 'LEFT'),
        right: HidAction(type: ActionType.mouseMove, value: 'RIGHT'),
      ),
    );
    final harness = await TestHarness.create(
      config: testConfig(profiles: [mouseProfile]),
    );
    addTearDown(() => _disposeHarness(tester, harness));
    await tester.pumpWidget(SmartKeysApp(controller: harness.controller));
    await tester.pumpAndSettle();

    final touchpad = find.byKey(const ValueKey('mouse-touchpad'));
    expect(touchpad, findsOneWidget);
    expect(find.byKey(const ValueKey('jog-wheel-gesture')), findsNothing);
    expect(
      tester.getSize(touchpad).width,
      greaterThan(
        tester.getSize(find.byKey(const ValueKey('wheel-region'))).width * 0.9,
      ),
    );
    final center = tester.getCenter(touchpad);
    final gesture = await tester.startGesture(center);
    await gesture.moveBy(const Offset(15, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(10, -5));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(harness.hid.pressedActions.last.type, ActionType.mouseMove);
    expect(harness.hid.pressedActions.last.value, '17,-8');

    await tester.tapAt(center);
    await tester.pump();
    expect(harness.hid.steppedActions.last.type, ActionType.mouseButton);
    expect(harness.hid.steppedActions.last.value, 'LEFT');

    final firstFinger = await tester.startGesture(center, pointer: 11);
    final secondFinger = await tester.startGesture(
      center + const Offset(20, 0),
      pointer: 12,
    );
    await firstFinger.up();
    await secondFinger.up();
    await tester.pump();
    expect(harness.hid.steppedActions.last.type, ActionType.mouseButton);
    expect(harness.hid.steppedActions.last.value, 'RIGHT');

    final scrollFirst = await tester.startGesture(
      center - const Offset(10, 0),
      pointer: 21,
    );
    final scrollSecond = await tester.startGesture(
      center + const Offset(10, 0),
      pointer: 22,
    );
    await scrollFirst.moveBy(const Offset(0, -20));
    await scrollSecond.moveBy(const Offset(0, -20));
    await scrollFirst.moveBy(const Offset(0, -20));
    await scrollSecond.moveBy(const Offset(0, -20));
    await tester.pump();
    await scrollFirst.up();
    await scrollSecond.up();
    await tester.pump();
    final scrollActions = harness.hid.steppedActions.where(
      (action) => action.type == ActionType.mouseWheel,
    );
    expect(scrollActions, isNotEmpty);
    expect(scrollActions.last.value, '1');
  });

  testWidgets('edit mode long-press drag swaps two button positions', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final harness = await TestHarness.create();
    addTearDown(() => _disposeHarness(tester, harness));
    await tester.pumpWidget(SmartKeysApp(controller: harness.controller));
    await tester.pumpAndSettle();

    await _openControlMenu(tester);
    await tester.tap(find.text('Edit buttons'));
    await tester.pump();
    final source = find.byKey(const ValueKey('control-button-0'));
    final target = find.byKey(const ValueKey('control-button-1'));
    final targetCenter = tester.getCenter(target);
    final gesture = await tester.startGesture(tester.getCenter(source));
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byKey(const ValueKey('button-drag-feedback')), findsOneWidget);

    await gesture.moveTo(targetCenter);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(harness.controller.activeProfile.buttons[0].label, 'Button 2');
    expect(harness.controller.activeProfile.buttons[1].label, 'Copy');
    expect(harness.repository.value.profiles.first.buttons[1].label, 'Copy');
  });

  testWidgets('button editor Save persists changes and returns home', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(844, 390);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final harness = await TestHarness.create();
    addTearDown(() => _disposeHarness(tester, harness));
    await tester.pumpWidget(SmartKeysApp(controller: harness.controller));
    await tester.pumpAndSettle();

    await _openControlMenu(tester);
    await tester.tap(find.text('Edit buttons'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('control-button-0')));
    await tester.pumpAndSettle();
    expect(find.text('Button 1'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'Label'),
      'Edited Copy',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Button 1'), findsNothing);
    expect(harness.controller.activeProfile.buttons.first.label, 'Edited Copy');
    expect(
      harness.repository.value.profiles.first.buttons.first.label,
      'Edited Copy',
    );
  });

  testWidgets(
    'rotation keeps button order and profile while releasing held key',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final harness = await TestHarness.create();
      addTearDown(() => _disposeHarness(tester, harness));
      await tester.pumpWidget(SmartKeysApp(controller: harness.controller));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('control-button-0'))),
      );
      await tester.pump();
      expect(harness.controller.pressedPositions, contains(0));

      tester.view.physicalSize = const Size(844, 390);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.byKey(const ValueKey('button-grid-5x3')), findsOneWidget);
      expect(harness.controller.activeProfile.id, 'profile_general');
      expect(harness.controller.activeProfile.buttons.first.label, 'Copy');
      expect(harness.controller.pressedPositions, isEmpty);
      expect(harness.hid.calls, contains('releaseAllKeys'));
      await gesture.up();
    },
  );

  testWidgets('built-in icon renders from semantic id', (tester) async {
    final harness = await TestHarness.create();
    addTearDown(() => _disposeHarness(tester, harness));
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 120,
          height: 90,
          child: ButtonFace(
            button: harness.controller.activeProfile.buttons.first,
            imageStore: harness.controller.imageStore,
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.content_copy), findsOneWidget);
  });

  testWidgets('custom image renders and missing image uses placeholder', (
    tester,
  ) async {
    final harness = await TestHarness.create();
    addTearDown(() => _disposeHarness(tester, harness));
    final imageDirectory = Directory(
      path.join(harness.directory.path, 'images', 'profile_general'),
    );
    imageDirectory.createSync(recursive: true);
    final imageFile = File(path.join(imageDirectory.path, 'button.png'));
    imageFile.writeAsBytesSync(
      image_lib.encodePng(image_lib.Image(width: 2, height: 2)),
    );
    final button = ButtonConfig.empty(0).copyWith(
      visual: const ButtonVisual(
        type: VisualType.customImage,
        value: 'images/profile_general/button.png',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 120,
          height: 90,
          child: ButtonFace(
            button: button,
            imageStore: harness.controller.imageStore,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(Image), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 120,
          height: 90,
          child: ButtonFace(
            button: button.copyWith(
              visual: button.visual.copyWith(value: 'images/missing.webp'),
            ),
            imageStore: harness.controller.imageStore,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      find.byKey(const ValueKey('missing-image-placeholder')),
      findsOneWidget,
    );
  });

  testWidgets('Bluetooth sheet requests permission from a visible state', (
    tester,
  ) async {
    final harness = await TestHarness.create();
    harness.hid.status.value = HidConnectionStatus.permissionRequired;
    addTearDown(() => _disposeHarness(tester, harness));
    await tester.pumpWidget(SmartKeysApp(controller: harness.controller));
    await tester.pump();

    await _openControlMenu(tester);
    await tester.tap(find.text('Bluetooth · Permission required'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.byKey(const ValueKey('bluetooth-status-permissionRequired')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('grant-bluetooth-access')));
    await tester.pump();
    expect(harness.hid.calls, contains('requestAccess'));
  });

  testWidgets('Bluetooth sheet connects a selected paired host', (
    tester,
  ) async {
    final harness = await TestHarness.create();
    harness.hid.status.value = HidConnectionStatus.disconnected;
    harness.hid.selectedHost.value = null;
    harness.hid.hosts.value = const [
      HidHost(id: 'windows-pc', name: 'Steven-PC', address: 'AA:BB'),
    ];
    addTearDown(() => _disposeHarness(tester, harness));
    await tester.pumpWidget(SmartKeysApp(controller: harness.controller));
    await tester.pump();

    await _openControlMenu(tester);
    await tester.tap(find.text('Bluetooth · Disconnected'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Steven-PC'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('connect-host-windows-pc')));
    await tester.pump();
    expect(harness.hid.calls, contains('connect:windows-pc'));
  });

  testWidgets('community install replaces a selected slot at the free limit', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final harness = await TestHarness.create(
      config: testConfig(
        profiles: [
          profile(),
          profile(id: 'profile_web', name: 'Web'),
          profile(id: 'profile_meetings', name: 'Zoom / Teams'),
          profile(id: 'profile_custom', name: 'Custom'),
        ],
      ),
    );
    addTearDown(() => _disposeHarness(tester, harness));
    await tester.pumpWidget(SmartKeysApp(controller: harness.controller));
    await tester.pumpAndSettle();

    await _openControlMenu(tester);
    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Shortcut Community'));
    await tester.pumpAndSettle();
    expect(find.text('4/$freeProfileLimit'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('install-community-community_presentation')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Replace a profile'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('replace-profile-profile_custom')),
    );
    await tester.pumpAndSettle();

    expect(harness.controller.config.profiles, hasLength(freeProfileLimit));
    final replacement = harness.controller.config.profiles.firstWhere(
      (item) => item.id == 'profile_custom',
    );
    expect(replacement.name, 'Presentation Remote');
    expect(replacement.isBuiltInTemplate, isFalse);
  });

  testWidgets('Settings shows the automatically resolved primary modifier', (
    tester,
  ) async {
    final harness = await TestHarness.create();
    harness.hid.selectedHost.value = const HidHost(
      id: 'mac',
      name: 'Yuchen’s MacBook Pro',
      address: 'AA:BB',
    );
    addTearDown(() => _disposeHarness(tester, harness));
    await tester.pumpWidget(SmartKeysApp(controller: harness.controller));
    await tester.pump();

    await _openControlMenu(tester);
    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();

    expect(find.text('SHORTCUT PLATFORM'), findsOneWidget);
    expect(find.text('Command for Yuchen’s MacBook Pro'), findsOneWidget);
    expect(find.text('PRIMARY sends Command (⌘)'), findsOneWidget);
  });

  testWidgets('power indicator reacts to charger connection', (tester) async {
    final harness = await TestHarness.create(pluggedIn: false);
    addTearDown(() => _disposeHarness(tester, harness));
    await tester.pumpWidget(SmartKeysApp(controller: harness.controller));
    await tester.pump();

    expect(find.byKey(const ValueKey('power-indicator-false')), findsOneWidget);

    harness.power.state.value = true;
    await tester.pump();

    expect(find.byKey(const ValueKey('power-indicator-true')), findsOneWidget);
    expect(find.byTooltip('External power connected'), findsOneWidget);
  });

  testWidgets('Settings exposes fixed and dynamic charging brightness', (
    tester,
  ) async {
    final harness = await TestHarness.create(pluggedIn: true);
    addTearDown(() => _disposeHarness(tester, harness));
    await tester.pumpWidget(SmartKeysApp(controller: harness.controller));
    await tester.pump();

    await _openControlMenu(tester);
    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('CHARGING DISPLAY'),
      300,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text('CHARGING DISPLAY'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Charging brightness 80%'),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Charging brightness 80%'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Keep screen awake while charging'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Keep screen awake while charging'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('charging-brightness-slider')),
      findsOneWidget,
    );

    await tester.ensureVisible(find.text('Dynamic / system controlled'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dynamic / system controlled'));
    await tester.pumpAndSettle();

    expect(
      harness.repository.value.preferences.chargingBrightnessMode,
      ChargingBrightnessMode.dynamic,
    );
    expect(
      find.byKey(const ValueKey('charging-brightness-slider')),
      findsNothing,
    );
    expect(harness.power.appliedBrightness.last, isNull);
  });

  testWidgets('Settings states shortcut usage privacy and shows local counts', (
    tester,
  ) async {
    final harness = await TestHarness.create();
    addTearDown(() => _disposeHarness(tester, harness));
    final button = harness.controller.activeProfile.buttons.first;
    await harness.controller.pressButton(button);
    await harness.controller.releaseButton(button);
    await tester.pumpWidget(SmartKeysApp(controller: harness.controller));
    await tester.pump();

    await _openControlMenu(tester);
    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('SHORTCUT USAGE'),
      300,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text('SHORTCUT USAGE'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Private, on-device data'),
      160,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.textContaining('Shortcut usage never leaves this phone'),
      findsOneWidget,
    );
    expect(find.text('Most used'), findsOneWidget);
    expect(find.text('1×'), findsWidgets);
  });
}

Future<void> _openControlMenu(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('control-menu')));
  await tester.pumpAndSettle();
}

Future<void> _disposeHarness(WidgetTester tester, TestHarness harness) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await harness.dispose();
}
