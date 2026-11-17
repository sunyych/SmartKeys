import 'package:flutter_test/flutter_test.dart';
import 'package:lumiakey_bluetooth_lite/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets('Lite app opens without companion setup or account screens', (tester) async {
    await tester.pumpWidget(const BluetoothLiteApp());
    await tester.pumpAndSettle();
    expect(find.text('BLUETOOTH LITE'), findsOneWidget);
    expect(find.text('Connect'), findsOneWidget);
    expect(find.text('Desktop companion'), findsNothing);
    expect(find.text('Sign in'), findsNothing);
  });
}
