import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_keys/app.dart';
import 'package:smart_keys/data/account_backup_client.dart';
import 'package:smart_keys/services/google_account_auth_service.dart';
import 'package:smart_keys/ui/account_backup_screen.dart';

import 'test_support.dart';

class _NoAccountAuth implements GoogleAccountAuthenticator {
  @override
  String? get displayEmail => null;
  @override
  String? get idToken => null;
  @override
  Future<String?> signIn() async =>
      throw StateError('Must not sign in automatically.');
  @override
  Future<void> signOut() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'unconfigured service explains state and never signs in automatically',
    (tester) async {
      final harness = await TestHarness.create();
      addTearDown(harness.dispose);
      final auth = _NoAccountAuth();
      final client = AccountBackupClient(auth: auth, endpoint: '');
      await tester.pumpWidget(
        MaterialApp(
          home: SmartKeysScope(
            controller: harness.controller,
            child: AccountBackupScreen(auth: auth, client: client),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Online backup service is not configured for this build.'),
        findsOneWidget,
      );
      expect(find.text('Preview and back up'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Preview and back up'),
            )
            .onPressed,
        isNull,
      );
      expect(auth.idToken, isNull);
      client.dispose();
    },
  );
}
