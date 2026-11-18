import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_keys/services/companion_service.dart';
import 'package:smart_keys/ui/desktop_connection_panel.dart';

void main() {
  testWidgets('scanner cancellation and repeated taps never connect twice', (
    tester,
  ) async {
    final companion = _FakeCompanion();
    final result = Completer<String?>();
    var scannerCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: DesktopConnectionPanel(
              companion: companion,
              scanConnectionCode: (_) {
                scannerCalls++;
                return result.future;
              },
            ),
          ),
        ),
      ),
    );
    final scanButton = find.byKey(const ValueKey('scan-desktop-pairing-code'));
    await tester.tap(scanButton);
    await tester.pump();
    await tester.tap(scanButton);
    await tester.pump();
    expect(scannerCalls, 1);
    result.complete(null);
    await tester.pumpAndSettle();
    expect(companion.codes, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('scanned fixture uses the existing manual pairing path', (
    tester,
  ) async {
    final companion = _FakeCompanion();
    const fixtureCode = '192.168.1.23:45832 aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: DesktopConnectionPanel(
              companion: companion,
              scanConnectionCode: (_) async => fixtureCode,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('scan-desktop-pairing-code')));
    await tester.pumpAndSettle();
    expect(companion.codes, [fixtureCode]);
    expect(tester.takeException(), isNull);
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
  final codes = <String>[];

  @override
  Future<void> connectManually(String code) async => codes.add(code);

  @override
  Future<void> disconnect() async {}

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
