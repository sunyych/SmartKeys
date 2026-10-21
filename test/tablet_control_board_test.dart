import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_keys/app.dart';
import 'package:smart_keys/controllers/app_controller.dart';
import 'package:smart_keys/data/config_repository.dart';
import 'package:smart_keys/data/private_image_store.dart';
import 'package:smart_keys/data/profile_template_repository.dart';
import 'package:smart_keys/data/shortcut_usage_repository.dart';
import 'package:smart_keys/models/config.dart';
import 'package:smart_keys/services/companion_service.dart';
import 'package:smart_keys/services/ios_companion_hid_service.dart';
import 'package:smart_keys/services/orientation_service.dart';
import 'package:smart_keys/services/power_brightness_service.dart';
import 'package:smart_keys/ui/button_editor_screen.dart';
import 'package:smart_keys/ui/desktop_connection_panel.dart';
import 'package:smart_keys/ui/home_screen.dart';
import 'package:smart_keys/ui/widgets/mouse_touchpad.dart';

import 'screenshot_support.dart';
import 'test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(ScreenshotSupport.prepareFonts);

  testWidgets(
    'automatic board selects tablet windows and fits every page size',
    (tester) async {
      final harness = await TestHarness.create();
      addTearDown(harness.dispose);
      await _setSize(tester, const Size(768, 1024));
      await tester.pumpWidget(_app(harness, const HomeScreen()));
      expect(
        find.byKey(const ValueKey('shortcut-board-layout')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('wheel-region')), findsNothing);
      expect(find.byKey(const ValueKey('control-button-39')), findsOneWidget);
      harness.hid.errors.value =
          'This shortcut is unsupported on the selected iPad connection. '
          'Choose a local keyboard shortcut or connect to a compatible target.';
      await tester.pumpAndSettle();
      final errorRect = tester.getRect(
        find.byKey(const ValueKey('control-surface-error')),
      );
      final tabRect = tester.getRect(
        find.byKey(const ValueKey('profile-quick-profile_general')),
      );
      final boardKeyRect = tester.getRect(
        find.byKey(const ValueKey('control-button-0')),
      );
      expect(errorRect.top, greaterThanOrEqualTo(tabRect.bottom));
      expect(boardKeyRect.top, greaterThanOrEqualTo(errorRect.bottom));
      expect(tester.takeException(), isNull);
      harness.hid.errors.value = null;
      await tester.pumpAndSettle();

      for (final pageSize in [24, 60]) {
        await harness.controller.updateTabletKeysPerPage(pageSize);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('shortcut-board-layout')),
          findsOneWidget,
        );
        expect(
          find.byKey(ValueKey('control-button-${pageSize - 1}')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      }

      for (final pageSize in [32, 48, 59]) {
        await harness.controller.updateTabletKeysPerPage(pageSize);
        await tester.pumpAndSettle();
        expect(
          find.byKey(ValueKey('control-button-${pageSize - 1}')),
          findsOneWidget,
        );
        final firstTile = tester.getSize(
          find.byKey(ValueKey('control-button-${pageSize - 1}')),
        );
        await tester.tap(find.byKey(const ValueKey('board-bank-next')));
        await tester.pumpAndSettle();
        final lastBankButton = find.byKey(const ValueKey('control-button-59'));
        expect(lastBankButton, findsOneWidget);
        expect(tester.getSize(lastBankButton), firstTile);
        expect(find.byKey(const ValueKey('control-button-60')), findsNothing);
        await tester.tap(find.byKey(const ValueKey('board-bank-previous')));
        await tester.pumpAndSettle();
      }

      await harness.controller.pressButton(
        harness.controller.activeProfile.buttons.first,
      );
      await tester.pumpAndSettle();
      expect(harness.controller.pressedPositions, contains(0));
      await _setSize(tester, const Size(500, 1024));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('portrait-layout')), findsOneWidget);
      expect(find.byKey(const ValueKey('shortcut-board-layout')), findsNothing);
      expect(harness.controller.pressedPositions, isEmpty);
      expect(harness.hid.calls, contains('releaseAllKeys'));

      await _setSize(tester, const Size(915, 412));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('landscape-layout')), findsOneWidget);

      await harness.controller.updateControlSurfaceLayout(
        ControlSurfaceLayout.shortcutBoard,
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('shortcut-board-layout')),
        findsOneWidget,
      );
      await harness.controller.updateControlSurfaceLayout(
        ControlSurfaceLayout.phone,
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('landscape-layout')), findsOneWidget);
    },
  );

  testWidgets('board executes keys, navigates banks, and saves virtual slots', (
    tester,
  ) async {
    final harness = await TestHarness.create(
      config: testConfig(
        profiles: [
          profile(),
          profile(id: 'profile_other', name: 'Other'),
        ],
      ),
    );
    addTearDown(harness.dispose);
    await harness.controller.updateControlSurfaceLayout(
      ControlSurfaceLayout.shortcutBoard,
    );
    await _setSize(tester, const Size(768, 1024));
    await tester.pumpWidget(_app(harness, const HomeScreen()));

    await tester.tap(find.byKey(const ValueKey('control-button-0')));
    await tester.pumpAndSettle();
    expect(harness.hid.pressedActions, isNotEmpty);
    expect(harness.hid.releasedActions, isNotEmpty);

    await tester.tap(find.byKey(const ValueKey('board-bank-next')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('board-bank-label')), findsOneWidget);
    expect(find.text('Bank 2 of 2'), findsOneWidget);
    expect(find.byKey(const ValueKey('control-button-40')), findsOneWidget);
    expect(harness.hid.calls, contains('releaseAllKeys'));

    await harness.controller.switchProfile('profile_other');
    await tester.pumpAndSettle();
    expect(find.text('Bank 1 of 2'), findsOneWidget);
    expect(find.byKey(const ValueKey('control-button-0')), findsOneWidget);
    await harness.controller.switchProfile('profile_general');
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('board-edit-toggle')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('control-button-39')));
    await tester.pumpAndSettle();
    expect(find.byType(ButtonEditorScreen), findsOneWidget);
    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.labelText == 'Label',
      ),
      'Tablet slot',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final savedProfile = harness.repository.value.profiles.firstWhere(
      (profile) => profile.id == 'profile_general',
    );
    expect(savedProfile.buttons, hasLength(40));
    expect(savedProfile.buttons[39].label, 'Tablet slot');
  });

  testWidgets('iPad Home routes pairing to Desktop and hides Bluetooth mouse UI', (
    tester,
  ) async {
    final mouseProfile = profile().copyWith(
      wheel: const WheelConfig(controlType: WheelControlType.mousePad),
    );
    final fixture = await _IosFixture.create(
      testConfig(profiles: [mouseProfile]),
    );
    final shots = ScreenshotSupport(tester);
    final boundaryKey = GlobalKey();
    addTearDown(() async {
      await shots.unmount();
      shots.resetViewport();
      tester.view.resetViewInsets();
      await fixture.dispose();
    });
    await shots.setViewport(const Size(768, 1024));
    await tester.pumpWidget(
      _appWithController(fixture.controller, boundaryKey: boundaryKey),
    );

    expect(
      find.byKey(const ValueKey('status-mode-desktop-offline')),
      findsOneWidget,
    );
    expect(find.byTooltip('LumiaKey Desktop · Not connected'), findsWidgets);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('status-mode-desktop-offline')),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Icon && widget.icon == Icons.desktop_windows_outlined,
        ),
      ),
      findsOneWidget,
    );
    expect(find.text('Desktop'), findsWidgets);
    expect(find.byKey(const ValueKey('shortcut-board-layout')), findsOneWidget);

    await shots.capture(
      id: 'ipad-desktop-offline-home',
      title: 'iPad Desktop offline · Home shortcut board',
      orientation: 'portrait',
      notes:
          'Default tablet board with an injected iPad companion HID adapter and manual fake companion; widget-rendered view, not a physical iPad capture.',
      boundaryKey: boundaryKey,
    );

    await fixture.controller.updateControlSurfaceLayout(
      ControlSurfaceLayout.phone,
    );
    await tester.pumpAndSettle();
    expect(find.byType(MouseTouchpad), findsNothing);
    expect(
      find.byKey(const ValueKey('desktop-keyboard-only-hint')),
      findsOneWidget,
    );
    await fixture.controller.updateControlSurfaceLayout(
      ControlSurfaceLayout.automatic,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('control-menu')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('menu-desktop-connection')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('menu-bluetooth-connection')),
      findsNothing,
    );
    expect(find.textContaining('Bluetooth ·'), findsNothing);
    await tester.tap(find.text('Desktop connection'));
    await tester.pumpAndSettle();
    expect(find.byType(DesktopConnectionPanel), findsOneWidget);
    expect(find.text('Desktop connection code'), findsOneWidget);
    await shots.capture(
      id: 'ipad-desktop-pairing-panel',
      title: 'iPad Desktop connection · pairing code',
      orientation: 'portrait',
      notes:
          'Pairing sheet shown with an empty code field using injected test services; widget-rendered view, not a physical iPad capture.',
      boundaryKey: boundaryKey,
    );
    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    await tester.pumpAndSettle();
    final connectionCode = find.byType(TextField);
    await tester.ensureVisible(connectionCode);
    await tester.pumpAndSettle();
    expect(
      tester.getRect(connectionCode).bottom,
      lessThanOrEqualTo(tester.view.physicalSize.height - 320),
    );
    final connectButton = find.text('Connect');
    await tester.ensureVisible(connectButton);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '192.168.1.2:45832 token');
    await tester.tap(connectButton);
    await tester.pumpAndSettle();
    expect(fixture.companion.lastConnectionCode, '192.168.1.2:45832 token');
  });
}

Future<void> _setSize(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  await tester.pumpAndSettle();
}

Widget _app(TestHarness harness, Widget page) => SmartKeysScope(
  controller: harness.controller,
  child: MaterialApp(theme: ThemeData.dark(useMaterial3: true), home: page),
);

Widget _appWithController(AppController controller, {GlobalKey? boundaryKey}) {
  final app = SmartKeysScope(
    controller: controller,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: const HomeScreen(),
    ),
  );
  return boundaryKey == null ? app : screenshotBoundary(boundaryKey, app);
}

class _IosFixture {
  _IosFixture({
    required this.controller,
    required this.companion,
    required this.hid,
    required this.power,
    required this.directory,
  });

  final AppController controller;
  final _ManualRecordingCompanion companion;
  final IosCompanionHidService hid;
  final RecordingPowerBrightnessService power;
  final Directory directory;

  static Future<_IosFixture> create(AppConfig config) async {
    final directory = Directory.systemTemp.createTempSync('smart_keys_ios_');
    final repository = MemoryConfigRepository(config);
    final companion = _ManualRecordingCompanion();
    final hid = IosCompanionHidService(companion);
    final power = RecordingPowerBrightnessService();
    final controller = AppController(
      repository: repository,
      templates: ProfileTemplateRepository(),
      hid: hid,
      companion: companion,
      orientationService: RecordingOrientationService(),
      imageStore: PrivateImageStore(documentsDirectory: () async => directory),
      powerBrightnessService: power,
      shortcutUsage: MemoryShortcutUsageRepository(),
    );
    await controller.initialize();
    return _IosFixture(
      controller: controller,
      companion: companion,
      hid: hid,
      power: power,
      directory: directory,
    );
  }

  Future<void> dispose() async {
    controller.dispose();
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  }
}

class _ManualRecordingCompanion extends RecordingCompanionService
    implements ManualCompanionConnection {
  String? lastConnectionCode;

  @override
  Future<void> connectManually(String code) async {
    lastConnectionCode = code;
  }

  @override
  Future<void> disconnect() async {}
}
