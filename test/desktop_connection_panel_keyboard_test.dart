import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_keys/services/companion_service.dart';
import 'package:smart_keys/ui/desktop_connection_panel.dart';

void main() {
  for (final size in [const Size(390, 844), const Size(844, 390)]) {
    testWidgets('pairing sheet fits $size with keyboard open', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      tester.view.resetViewInsets();
      addTearDown(() {
        tester.view.resetViewInsets();
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final companion = _FakeCompanion();
      await tester.pumpWidget(
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
      );
      await tester.tap(find.text('Open pairing'));
      await tester.pumpAndSettle();
      final field = find.byType(TextField);
      await tester.tap(field);
      await tester.pumpAndSettle();

      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      await tester.pumpAndSettle();
      await tester.ensureVisible(field);
      await tester.pumpAndSettle();
      final visibleBottom = size.height - 280;
      expect(tester.getRect(field).bottom, lessThanOrEqualTo(visibleBottom));
      final connect = find.text('Connect');
      await tester.ensureVisible(connect);
      await tester.pumpAndSettle();
      expect(tester.getRect(connect).bottom, lessThanOrEqualTo(visibleBottom));
      expect(tester.takeException(), isNull);
    });
  }
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
