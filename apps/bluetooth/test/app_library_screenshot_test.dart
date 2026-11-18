import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lumiakey_bluetooth_lite/lite_controller.dart';
import 'package:lumiakey_bluetooth_lite/lite_app_library_screen.dart';
import 'screenshot_support.dart';

void main() {
  testWidgets(
    'captures offline App association OS preview and unassigned library',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      const channel = MethodChannel('smart_keys/hid');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            channel,
            (call) async => call.method == 'refreshPairedHosts'
                ? {'status': 'disconnected', 'pairedHosts': []}
                : null,
          );
      await tester.runAsync(ScreenshotSupport.prepareFonts);
      final shots = ScreenshotSupport(tester);
      await shots.setViewport(const Size(960, 540));
      final controller = LiteController();
      await controller.initialize();
      final boundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: MaterialApp(
            theme: ThemeData.dark(useMaterial3: true),
            home: LiteAppLibraryScreen(controller: controller),
          ),
        ),
      );
      await tester.pumpAndSettle();
      Future<void> capture(String id, String title) => shots.capture(
        id: id,
        title: title,
        orientation: 'landscape',
        notes:
            'Offline App and OS-specific shortcuts. Unassigned entries are visibly marked and send no HID; no real app was launched.',
        boundaryKey: boundary,
      );
      await capture(
        'lite-app-library-os-choice',
        'Lite App library · choose controlled computer OS',
      );
      await tester.tap(find.byKey(const ValueKey('lite-app-library-os')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('macOS').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('lite-app-library-search')),
        'chrome',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('lite-app-library-chrome')));
      await tester.pumpAndSettle();
      await capture(
        'lite-app-library-macos-preview',
        'Lite Chrome · macOS icon and verified shortcut preview',
      );
      await tester.tap(find.byKey(const ValueKey('lite-app-library-os')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Linux').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('lite-app-library-search')),
        'obs',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('lite-app-library-obs')));
      await tester.pumpAndSettle();
      await capture(
        'lite-app-library-unassigned',
        'Lite OBS · Linux configuration template with no default keys',
      );
      await shots.unmount();
      controller.dispose();
      shots.resetViewport();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    },
  );
}
