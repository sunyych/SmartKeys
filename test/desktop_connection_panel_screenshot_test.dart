import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_keys/services/companion_service.dart';
import 'package:smart_keys/ui/desktop_connection_panel.dart';

import 'screenshot_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(ScreenshotSupport.prepareFonts);

  testWidgets('pairing sheet and camera fallback screenshots use fixtures', (
    tester,
  ) async {
    final shots = ScreenshotSupport(tester);
    final companion = _FakeCompanion();
    final boundaryKey = GlobalKey();
    addTearDown(() async {
      await shots.unmount();
      shots.resetViewport();
      tester.view.resetViewInsets();
      companion.dispose();
    });

    await shots.setViewport(const Size(390, 844));
    await tester.pumpWidget(
      screenshotBoundary(
        boundaryKey,
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: FilledButton(
                  onPressed: () =>
                      showDesktopConnectionSheet(context, companion),
                  child: const Text('Open pairing'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open pairing'));
    await tester.pumpAndSettle();
    await shots.capture(
      id: 'phone-desktop-pairing-panel',
      title: 'Phone Desktop pairing panel',
      orientation: 'portrait',
      notes: 'Pairing UI with no connection code entered.',
      boundaryKey: boundaryKey,
    );

    await shots.setViewport(const Size(844, 390));
    await tester.pumpAndSettle();
    final field = find.byType(TextField);
    await tester.ensureVisible(field);
    await tester.tap(field);
    tester.view.viewInsets = const FakeViewPadding(bottom: 230);
    await tester.pumpAndSettle();
    await tester.ensureVisible(field);
    await tester.pumpAndSettle();
    await shots.capture(
      id: 'phone-desktop-pairing-keyboard-landscape',
      title: 'Phone Desktop pairing with keyboard inset',
      orientation: 'landscape',
      notes:
          'Modal layout after applying a simulated 230px software-keyboard inset; the screenshot contains no credentials.',
      boundaryKey: boundaryKey,
    );

    tester.view.resetViewInsets();
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      screenshotBoundary(
        boundaryKey,
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => DesktopConnectionScannerScreen(
                        cameraPreviewBuilder: (_) =>
                            const ConnectionScannerUnavailable(),
                      ),
                    ),
                  ),
                  child: const Text('Open scanner fallback'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open scanner fallback'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Camera unavailable'), findsOneWidget);
    await shots.capture(
      id: 'phone-desktop-camera-unavailable',
      title: 'Phone scanner camera unavailable',
      orientation: 'landscape',
      notes:
          'Scanner fallback rendered through an injected placeholder; no camera permission prompt or live camera is used.',
      boundaryKey: boundaryKey,
    );
  });
}

class _FakeCompanion extends ChangeNotifier
    implements CompanionService, ManualCompanionConnection {
  @override
  final activeHost = ValueNotifier<CompanionHost?>(null);
  @override
  final syncStatus = ValueNotifier(CompanionSyncStatus.discovering);
  @override
  final errorMessage = ValueNotifier<String?>(null);

  @override
  Future<void> connectManually(String code) async {}

  @override
  Future<void> disconnect() async {}

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
