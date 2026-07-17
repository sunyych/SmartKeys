import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_keys/models/config.dart';
import 'package:smart_keys/ui/widgets/jog_wheel.dart';

void main() {
  testWidgets('blue wheel control follows drag and springs back to center', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              height: 360,
              child: JogWheel(
                config: const WheelConfig(),
                inputEpoch: 0,
                onStep: (_) {},
                onCenterPress: () {},
                onCenterRelease: () {},
              ),
            ),
          ),
        ),
      ),
    );

    final centerControl = find.byKey(const ValueKey('jog-wheel-center'));
    final restingCenter = tester.getCenter(centerControl);
    final gesture = await tester.startGesture(restingCenter);
    await gesture.moveBy(const Offset(24, -16));
    await tester.pump();
    await gesture.moveBy(const Offset(48, -32));
    await tester.pump();

    final draggedCenter = tester.getCenter(centerControl);
    expect(draggedCenter.dx, closeTo(restingCenter.dx + 72, 1));
    expect(draggedCenter.dy, closeTo(restingCenter.dy - 48, 1));

    await gesture.up();
    await tester.pump();
    expect(tester.getCenter(centerControl), isNot(restingCenter));

    await tester.pump(const Duration(milliseconds: 60));
    final returningCenter = tester.getCenter(centerControl);
    await tester.tapAt(returningCenter);
    await tester.pumpAndSettle();
    expect(tester.getCenter(centerControl), restingCenter);
  });
}
