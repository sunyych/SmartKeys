import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_keys/app.dart';
import 'package:smart_keys/app_edition.dart';
import 'package:smart_keys/data/profile_template_repository.dart';

import 'screenshot_support.dart';
import 'test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(ScreenshotSupport.prepareFonts);
  testWidgets('renders the Lite Bluetooth controller in landscape', (
    tester,
  ) async {
    final shots = ScreenshotSupport(tester);
    final profiles = (await tester.runAsync(
      () => ProfileTemplateRepository(edition: AppEdition.lite).loadAll(),
    ))!;
    final harness = await TestHarness.create(
      config: testConfig(profiles: profiles),
    );
    addTearDown(() async {
      await shots.unmount();
      shots.resetViewport();
      await harness.dispose();
    });
    await shots.setViewport(const Size(900, 420));
    final key = GlobalKey();
    await tester.pumpWidget(
      screenshotBoundary(
        key,
        SmartKeysApp(controller: harness.controller, edition: AppEdition.lite),
      ),
    );
    await tester.pumpAndSettle();
    await shots.capture(
      id: 'lite-general',
      title: 'LumiaKey Lite Bluetooth controls',
      orientation: 'landscape',
      notes:
          'Existing fifteen-key Bluetooth surface with local General, ChatGPT and Chrome profiles.',
      boundaryKey: key,
    );
  });
}
