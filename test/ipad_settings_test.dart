import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_keys/app.dart';
import 'package:smart_keys/controllers/app_controller.dart';
import 'package:smart_keys/data/config_repository.dart';
import 'package:smart_keys/data/private_image_store.dart';
import 'package:smart_keys/data/profile_template_repository.dart';
import 'package:smart_keys/data/shortcut_usage_repository.dart';
import 'package:smart_keys/services/companion_service.dart';
import 'package:smart_keys/services/ios_companion_hid_service.dart';
import 'package:smart_keys/services/orientation_service.dart';
import 'package:smart_keys/services/power_brightness_service.dart';
import 'package:smart_keys/ui/settings_screen.dart';

import 'test_support.dart';

class _ManualCompanion extends RecordingCompanionService
    implements ManualCompanionConnection {
  @override
  Future<void> connectManually(String code) async {}

  @override
  Future<void> disconnect() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('iPad Settings uses Desktop pairing instead of Bluetooth HID', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync('ipad_settings_');
    addTearDown(() => directory.deleteSync(recursive: true));
    final repository = MemoryConfigRepository(testConfig());
    final companion = _ManualCompanion();
    final hid = IosCompanionHidService(companion);
    final power = RecordingPowerBrightnessService();
    final shortcutUsage = MemoryShortcutUsageRepository();
    final controller = AppController(
      repository: repository,
      templates: ProfileTemplateRepository(),
      hid: hid,
      companion: companion,
      orientationService: RecordingOrientationService(),
      imageStore: PrivateImageStore(documentsDirectory: () async => directory),
      powerBrightnessService: power,
      shortcutUsage: shortcutUsage,
    );
    await controller.initialize();
    addTearDown(() {
      controller.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: SmartKeysScope(
          controller: controller,
          child: const SettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('BLUETOOTH HID'), findsNothing);
    expect(find.text('Computer connection'), findsNothing);
    expect(find.text('Desktop connection code'), findsOneWidget);
    expect(find.text('Paste code'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('ipad-desktop-keyboard-explanation')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('ipad-desktop-keyboard-explanation')),
      findsOneWidget,
    );
    expect(
      find.text(
        'iPad sends supported keyboard shortcuts to LumiaKey Desktop over Wi-Fi; speech recognition stays on this device.',
      ),
      findsOneWidget,
    );
  });
}
