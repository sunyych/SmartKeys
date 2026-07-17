import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image_lib;
import 'package:path/path.dart' as path;
import 'package:smart_keys/app.dart';
import 'package:smart_keys/models/config.dart';
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
  });

  testWidgets('landscape uses 5 by 3 and a two-thirds/one-third split', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(844, 390);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final harness = await TestHarness.create();
    addTearDown(() => _disposeHarness(tester, harness));

    await tester.pumpWidget(SmartKeysApp(controller: harness.controller));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byKey(const ValueKey('landscape-layout')), findsOneWidget);
    expect(find.byKey(const ValueKey('button-grid-5x3')), findsOneWidget);
    final keyWidth = tester
        .getSize(find.byKey(const ValueKey('key-region')))
        .width;
    final wheelWidth = tester
        .getSize(find.byKey(const ValueKey('wheel-region')))
        .width;
    expect(keyWidth / wheelWidth, closeTo(2, 0.05));
  });

  testWidgets('profile selector swipes quickly and still opens on tap', (
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

    await tester.drag(
      find.byKey(const ValueKey('profile-swipe-area')),
      const Offset(-100, 0),
    );
    await tester.pumpAndSettle();

    expect(harness.controller.activeProfile.id, 'profile_web');
    expect(find.text('Web'), findsOneWidget);
    expect(find.text('Profiles'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('profile-selector')));
    await tester.pumpAndSettle();
    expect(find.text('Profiles'), findsOneWidget);
    expect(find.text('Zoom / Teams'), findsOneWidget);
  });

  testWidgets('mouse direction pad repeats while held and stops on release', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(844, 390);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final mouseProfile = profile().copyWith(
      wheel: const WheelConfig(
        controlType: WheelControlType.mousePad,
        modeLabel: 'Mouse',
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

    expect(find.byKey(const ValueKey('mouse-move-up')), findsOneWidget);
    expect(find.byKey(const ValueKey('jog-wheel-gesture')), findsNothing);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('mouse-move-up'))),
    );
    await tester.pump(const Duration(milliseconds: 95));

    expect(
      harness.hid.pressedActions.where(
        (action) => action.type == ActionType.mouseMove,
      ),
      hasLength(greaterThanOrEqualTo(2)),
    );
    await gesture.up();
    await tester.pump();
    expect(harness.hid.releasedActions.last.value, 'UP');
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

    await tester.tap(find.byTooltip('Edit buttons'));
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

    await tester.tap(
      find.byKey(const ValueKey('connection-permissionRequired')),
    );
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

    await tester.tap(find.byKey(const ValueKey('connection-disconnected')));
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

    await tester.tap(find.byTooltip('Settings'));
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

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();

    expect(find.text('SHORTCUT PLATFORM'), findsOneWidget);
    expect(find.text('Command for Yuchen’s MacBook Pro'), findsOneWidget);
    expect(find.text('PRIMARY sends Command (⌘)'), findsOneWidget);
  });
}

Future<void> _disposeHarness(WidgetTester tester, TestHarness harness) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await harness.dispose();
}
