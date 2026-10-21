import 'package:flutter_test/flutter_test.dart';
import 'package:smart_keys/data/account_backup_client.dart';
import 'package:smart_keys/services/google_account_auth_service.dart';

class _NoTokenAuth implements GoogleAccountAuthenticator {
  @override
  String? get displayEmail => null;
  @override
  String? get idToken => null;
  int signInCalls = 0;
  @override
  Future<String?> signIn() async {
    signInCalls++;
    return null;
  }

  @override
  Future<void> signOut() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'client requires a prior explicit sign-in and never signs in by itself',
    () async {
      final auth = _NoTokenAuth();
      final client = AccountBackupClient(
        auth: auth,
        endpoint: 'https://backup.example.invalid',
      );
      addTearDown(client.dispose);
      await expectLater(client.get(), throwsStateError);
      expect(auth.signInCalls, 0);
    },
  );

  test('rejects missing and non-HTTPS endpoints before use', () async {
    final auth = _NoTokenAuth();
    final missing = AccountBackupClient(auth: auth, endpoint: '');
    final insecure = AccountBackupClient(
      auth: auth,
      endpoint: 'http://example.com',
    );
    addTearDown(missing.dispose);
    addTearDown(insecure.dispose);
    expect(missing.isConfigured, isFalse);
    expect(missing.configurationError, contains('SMARTKEYS_BACKUP_URL'));
    expect(insecure.isConfigured, isFalse);
    expect(insecure.configurationError, contains('HTTPS'));
  });
}
