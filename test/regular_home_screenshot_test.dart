import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumiakeys_protocol/lumiakeys_protocol.dart';
import 'package:smart_keys/ui/regular_home_screen.dart';

import 'regular_home_test_support.dart';
import 'screenshot_support.dart';
import 'test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(ScreenshotSupport.prepareFonts);
  testWidgets('renders Regular phone launcher General ChatGPT and iPad', (
    tester,
  ) async {
    final shots = ScreenshotSupport(tester);
    final harness = await TestHarness.create();
    final starter = DesktopManifest.regularStarter();
    connectRegularHarness(
      harness,
      manifest: starter,
      installed: const {
        'chatgpt',
        'chrome',
        'cursor',
        'edge',
        'firefox',
        'illustrator',
        'photoshop',
        'premiere',
        'solidworks',
        'teams',
        'vscode',
        'zoom',
      },
    );
    final key = GlobalKey();
    addTearDown(() async {
      await shots.unmount();
      shots.resetViewport();
      await harness.dispose();
    });
    await shots.setViewport(const Size(844, 390));
    await tester.pumpWidget(
      regularTestApp(
        harness,
        child: screenshotBoundary(key, const RegularHomeScreen()),
      ),
    );
    final imageContext = tester.element(find.byType(RegularHomeScreen));
    await tester.runAsync(
      () => Future.wait([
        for (final name in const [
          'openai',
          'chrome',
          'illustrator',
          'photoshop',
          'premiere',
          'solidworks',
          'vscode',
        ])
          precacheImage(AssetImage('assets/app_icons/$name.png'), imageContext),
      ]),
    );
    await tester.pumpAndSettle();
    await shots.capture(
      id: 'regular-launchpad',
      title: 'Regular phone Launchpad',
      orientation: 'landscape',
      notes:
          'Desktop-owned applications, 4 by 3 launcher and persistent touchpad.',
      boundaryKey: key,
    );
    await tester.tap(find.byKey(const ValueKey('regular-nav-general')));
    await tester.pumpAndSettle();
    await shots.capture(
      id: 'regular-general',
      title: 'Regular phone General controls',
      orientation: 'landscape',
      notes: 'Twelve Desktop General actions and persistent touchpad.',
      boundaryKey: key,
    );
    await tester.tap(find.byKey(const ValueKey('regular-nav-chatgpt')));
    await tester.pumpAndSettle();
    await shots.capture(
      id: 'regular-chatgpt',
      title: 'Regular phone ChatGPT shortcuts',
      orientation: 'landscape',
      notes: 'Desktop-owned compact application layout.',
      boundaryKey: key,
    );
    await shots.setViewport(const Size(1180, 820));
    await tester.pumpAndSettle();
    await shots.capture(
      id: 'regular-ipad',
      title: 'Regular iPad landscape controls',
      orientation: 'landscape',
      notes:
          'Twelve keys and touchpad at iPad size; Flutter render, no physical-device validation.',
      boundaryKey: key,
    );
  });
}
