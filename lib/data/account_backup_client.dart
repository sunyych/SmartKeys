import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import '../models/config.dart';
import '../services/google_account_auth_service.dart';
import 'account_backup_codec.dart';

class AccountBackupClient {
  AccountBackupClient({
    required this.auth,
    HttpClient? httpClient,
    this.endpoint = const String.fromEnvironment('SMARTKEYS_BACKUP_URL'),
    this.allowLoopbackHttp = false,
  }) : _httpClient = httpClient ?? HttpClient()
         ..connectionTimeout = const Duration(seconds: 10);

  final GoogleAccountAuthenticator auth;
  final HttpClient _httpClient;
  final String endpoint;
  final bool allowLoopbackHttp;
  static const requestTimeout = Duration(seconds: 20);
  static const maxResponseBytes = AccountBackupCodec.maxBodyBytes + 4096;
  bool get isConfigured => configurationError == null;
  String? get configurationError {
    if (endpoint.trim().isEmpty) {
      return 'Account backup is not configured: set SMARTKEYS_BACKUP_URL.';
    }
    try {
      _base;
      return null;
    } catch (error) {
      return '$error';
    }
  }

  Uri get _base {
    if (endpoint.trim().isEmpty) {
      throw StateError(
        'Account backup is not configured: set SMARTKEYS_BACKUP_URL.',
      );
    }
    final uri = Uri.tryParse(endpoint.trim());
    if (uri == null ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.query.isNotEmpty ||
        uri.fragment.isNotEmpty) {
      throw StateError('SMARTKEYS_BACKUP_URL is invalid.');
    }
    final loopback = const {'localhost', '127.0.0.1', '::1'}.contains(uri.host);
    if (uri.scheme != 'https' &&
        !(allowLoopbackHttp && uri.scheme == 'http' && loopback)) {
      throw StateError('Account backup requires HTTPS.');
    }
    return uri;
  }

  Uri get _backupUri {
    final base = _base;
    final basePath = base.path.endsWith('/') ? base.path : '${base.path}/';
    return base.replace(path: '${basePath}v1/account/backup');
  }

  void dispose() => _httpClient.close(force: true);

  Future<String> put(
    AppConfig config,
    BackupSelection selection,
    Map<String, Uint8List> images,
  ) async {
    return putEnvelope(
      await AccountBackupCodec.encodeAsync(config, selection, images),
    );
  }

  Future<String> putEnvelope(Map<String, Object?> envelope) async {
    final token = await _requireToken();
    final body = await Isolate.run(() => utf8.encode(jsonEncode(envelope)));
    if (body.length > AccountBackupCodec.maxBodyBytes) {
      throw const FormatException('Backup exceeds the 20 MiB request limit.');
    }
    final response = await _send('PUT', token, body: body);
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException(
        _errorMessage('Backup upload', response.statusCode),
        uri: _backupUri,
      );
    }
    final json = await Isolate.run(
      () => _object(jsonDecode(utf8.decode(response.bodyBytes))),
    );
    if (json.keys.toSet().difference(const {
          'schema_version',
          'updated_at',
        }).isNotEmpty ||
        json['schema_version'] != 1 ||
        json['updated_at'] is! String) {
      throw const FormatException('Unexpected backup upload response.');
    }
    return json['updated_at'] as String;
  }

  Future<DecodedAccountBackup?> get() async {
    final token = await _requireToken();
    final response = await _send('GET', token);
    if (response.statusCode == HttpStatus.notFound) return null;
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException(
        _errorMessage('Backup download', response.statusCode),
        uri: _backupUri,
      );
    }
    return Isolate.run(() {
      final json = _object(jsonDecode(utf8.decode(response.bodyBytes)));
      final updatedAt = json['updated_at'];
      if (updatedAt is! String) {
        throw const FormatException('Invalid backup timestamp.');
      }
      return AccountBackupCodec.decode(json, updatedAt: updatedAt);
    });
  }

  Future<void> delete() async {
    final token = await _requireToken();
    final response = await _send('DELETE', token);
    if (response.statusCode != HttpStatus.noContent) {
      throw HttpException(
        _errorMessage('Backup deletion', response.statusCode),
        uri: _backupUri,
      );
    }
  }

  Future<String> _requireToken() async =>
      auth.idToken ??
      (throw StateError('Sign in to Google before using account backup.'));

  Future<_BackupResponse> _send(
    String method,
    String token, {
    List<int>? body,
  }) async {
    final request = await _httpClient
        .openUrl(method, _backupUri)
        .timeout(requestTimeout);
    try {
      request.followRedirects = false;
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.contentLength = body.length;
        request.add(body);
      }
      final response = await request.close().timeout(requestTimeout);
      final bytes = await response
          .fold<List<int>>(<int>[], (buffer, chunk) {
            if (buffer.length + chunk.length > maxResponseBytes) {
              throw const FormatException(
                'Backup response exceeds the 20 MiB limit.',
              );
            }
            return buffer..addAll(chunk);
          })
          .timeout(requestTimeout);
      return _BackupResponse(response.statusCode, bytes);
    } catch (_) {
      request.abort();
      rethrow;
    }
  }

  static Map<String, dynamic> _object(Object? value) {
    if (value is! Map || value.keys.any((key) => key is! String)) {
      throw const FormatException('Expected a JSON object.');
    }
    return value.cast<String, dynamic>();
  }

  static String _errorMessage(String operation, int status) => switch (status) {
    HttpStatus.unauthorized => '$operation needs a fresh Google sign-in.',
    HttpStatus.serviceUnavailable =>
      'Account backup service is unavailable or not configured.',
    HttpStatus.requestEntityTooLarge => 'Backup exceeds the server size limit.',
    _ => '$operation failed (HTTP $status).',
  };
}

class _BackupResponse {
  const _BackupResponse(this.statusCode, this.bodyBytes);
  final int statusCode;
  final List<int> bodyBytes;
}
