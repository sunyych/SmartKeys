import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_keys/services/pointer_diagnostics.dart';

void main() {
  test('pointer diagnostics are opt-in, bounded and rate-limited', () {
    final previous = debugPrint;
    final messages = <String>[];
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) messages.add(message);
    };
    addTearDown(() => debugPrint = previous);

    void record() => PointerDiagnostics.record(
      PointerDiagnosticEvent.moveGate,
      synced: true,
      capability: true,
      pending: false,
      pinMatch: true,
      acceptedHost: true,
      routeDesktop: true,
      mode: 2,
      inputEpoch: 7,
      httpStatus: 999,
    );
    record();
    record();
    if (!pointerDiagnosticsEnabled) {
      expect(messages, isEmpty);
      return;
    }
    expect(messages, [
      'LUMIAKEY_POINTER event=moveGate synced=true capability=true '
          'pending=false pinMatch=true acceptedHost=true routeDesktop=true '
          'mode=advanced inputEpoch=7',
    ]);
  });
}
