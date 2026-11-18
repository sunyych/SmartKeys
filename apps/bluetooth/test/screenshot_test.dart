import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lumiakey_bluetooth_lite/main.dart';
import 'screenshot_support.dart';

const _hid = MethodChannel('smart_keys/hid');

void main() {
  testWidgets('Capture every Bluetooth Lite screen and key connection state', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.runAsync(ScreenshotSupport.prepareFonts);
    final shots = ScreenshotSupport(tester);
    await shots.setViewport(const Size(420, 880));
    var showConnectionError = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          _hid,
          (call) async => {
            'status': showConnectionError
                ? 'permissionRequired'
                : 'disconnected',
            'registered': false,
            'bluetoothEnabled': true,
            'permissionsGranted': !showConnectionError,
            'activeHost': null,
            'pairedHosts': [
              {
                'id': 'AA:BB:CC:DD:EE:FF',
                'name': 'Studio laptop',
                'address': 'AA:BB:CC:DD:EE:FF',
              },
            ],
            'error': showConnectionError
                ? 'Nearby devices permission was denied.'
                : null,
          },
        );

    final boundary = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(key: boundary, child: const BluetoothLiteApp()),
    );
    await tester.pumpAndSettle();
    const tabs = ['Keys', 'Mouse', 'Media', 'Shortcuts'];
    const ids = [
      'lite-keyboard',
      'lite-touchpad',
      'lite-media',
      'lite-shortcuts',
    ];
    for (var i = 0; i < tabs.length; i++) {
      if (i > 0) {
        await tester.tap(find.text(tabs[i]).last);
        await tester.pumpAndSettle();
      }
      await shots.capture(
        id: ids[i],
        title: 'Bluetooth Lite ${tabs[i]}',
        orientation: 'portrait',
        notes: 'Standalone Bluetooth-only Lite interface.',
        boundaryKey: boundary,
      );
    }

    for (final profile in ['ChatGPT', 'Chrome']) {
      await tester.tap(find.byKey(const ValueKey('local-profile-picker')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(profile).last);
      await tester.pumpAndSettle();
      await shots.capture(
        id: 'lite-${profile.toLowerCase()}-shortcuts',
        title: 'Bluetooth Lite $profile local shortcuts',
        orientation: 'portrait',
        notes:
            'Editable local Bluetooth profile. Open the target computer app yourself.',
        boundaryKey: boundary,
      );
    }

    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    await shots.capture(
      id: 'lite-shortcut-editor',
      title: 'Bluetooth Lite shortcut editor',
      orientation: 'portrait',
      notes: 'Manually edit a shortcut stored on this phone.',
      boundaryKey: boundary,
    );
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();
    await shots.capture(
      id: 'lite-host-picker',
      title: 'Bluetooth Lite paired host picker',
      orientation: 'portrait',
      notes: 'Select an already paired computer for Bluetooth HID.',
      boundaryKey: boundary,
    );
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    await shots.setViewport(const Size(880, 420));
    await tester.tap(find.text('Keys').last);
    await tester.pumpAndSettle();
    await shots.capture(
      id: 'lite-keyboard-landscape',
      title: 'Bluetooth Lite keyboard landscape',
      orientation: 'landscape',
      notes: 'Keyboard layout at a wide landscape viewport.',
      boundaryKey: boundary,
    );

    showConnectionError = true;
    await tester.tap(find.byTooltip('Refresh paired devices'));
    await tester.pumpAndSettle();
    await shots.capture(
      id: 'lite-bluetooth-permission-error',
      title: 'Bluetooth Lite permission error',
      orientation: 'landscape',
      notes: 'Nearby devices permission error state.',
      boundaryKey: boundary,
    );

    await shots.unmount();
    shots.resetViewport();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_hid, null);
  });
}
