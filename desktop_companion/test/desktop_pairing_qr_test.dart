import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumiakeys_companion/desktop_ui.dart';

import 'screenshot_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(prepareScreenshotFonts);

  testWidgets('Desktop QR renders the existing manual code format', (
    tester,
  ) async {
    const code = '192.168.1.23:45832 aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    expect(desktopPairingCode('192.168.1.23', 45832, 'a' * 32), code);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(480, 480);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RepaintBoundary(
            key: screenshotBoundaryKey,
            child: SizedBox(
              width: 480,
              height: 480,
              child: Center(child: DesktopPairingQr(code: code)),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Scan with LumiaKey on your phone'), findsOneWidget);
    expect(find.byType(DesktopPairingQr), findsOneWidget);
    expect(tester.takeException(), isNull);
    await captureDesktopScreenshot(
      tester,
      id: 'desktop-pairing-qr-fixture',
      title: 'Desktop pairing QR',
      orientation: 'portrait',
      width: 480,
      height: 480,
      notes:
          'Rendered Desktop pairing code component with a synthetic private address and fixture token; contains no live credential.',
    );
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}
