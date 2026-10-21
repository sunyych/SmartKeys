import 'dart:io';

import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';

abstract interface class GoogleAccountAuthenticator {
  Future<String?> signIn();
  Future<void> signOut();
  String? get displayEmail;
  String? get idToken;
}

class GoogleAccountAuthService implements GoogleAccountAuthenticator {
  static final GoogleAccountAuthService shared = GoogleAccountAuthService();

  GoogleAccountAuthService({
    GoogleSignIn? googleSignIn,
    MethodChannel? iosConfigurationChannel,
    this.webClientId = const String.fromEnvironment(
      'SMARTKEYS_GOOGLE_WEB_CLIENT_ID',
    ),
    this.iosClientId = const String.fromEnvironment(
      'SMARTKEYS_GOOGLE_IOS_CLIENT_ID',
    ),
  }) : _googleSignIn = googleSignIn ?? GoogleSignIn.instance,
       _iosConfigurationChannel =
           iosConfigurationChannel ??
           const MethodChannel('smart_keys/google_sign_in');

  final GoogleSignIn _googleSignIn;
  final MethodChannel _iosConfigurationChannel;
  final String webClientId;
  final String iosClientId;
  static final Map<String, Future<void>> _initializations = {};
  GoogleSignInAccount? _account;

  @override
  String? get displayEmail => _account?.email;
  String? _idToken;
  @override
  String? get idToken => _idToken;

  String? get configurationError {
    if (webClientId.trim().isEmpty) {
      return 'Google sign-in is not configured: set SMARTKEYS_GOOGLE_WEB_CLIENT_ID.';
    }
    if (Platform.isIOS && iosClientId.trim().isEmpty) {
      return 'Google sign-in is not configured: set SMARTKEYS_GOOGLE_IOS_CLIENT_ID.';
    }
    return null;
  }

  Future<void> _initialize() => _initializations.putIfAbsent(
    '${identityHashCode(_googleSignIn)}|${Platform.isIOS ? iosClientId : ''}|$webClientId',
    () => _googleSignIn.initialize(
      clientId: Platform.isIOS ? iosClientId : null,
      serverClientId: webClientId,
    ),
  );

  @override
  Future<String?> signIn() async {
    if (configurationError != null) throw StateError(configurationError!);
    if (Platform.isIOS) {
      final scheme = reversedSchemeForClientId(iosClientId);
      final registered = await _iosConfigurationChannel.invokeMethod<bool>(
        'isUrlSchemeRegistered',
        scheme,
      );
      if (registered != true) {
        throw StateError(
          'Google sign-in is unavailable: register the iOS URL scheme $scheme in Info.plist.',
        );
      }
    }
    await _initialize();
    final account = await _googleSignIn.authenticate();
    final token = account.authentication.idToken;
    if (token == null || token.isEmpty) {
      throw StateError(
        'Google did not return an ID token. Check OAuth client configuration.',
      );
    }
    _account = account;
    _idToken = token;
    return token;
  }

  @override
  Future<void> signOut() async {
    _account = null;
    _idToken = null;
    if (configurationError == null) {
      await _initialize();
      await _googleSignIn.signOut();
    }
  }

  static String reversedSchemeForClientId(String clientId) =>
      clientId.split('.').reversed.join('.');
}
