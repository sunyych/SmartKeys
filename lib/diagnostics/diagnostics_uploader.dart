import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:diagnostics_core/diagnostics_core.dart';

class DiagnosticsUploader {
  DiagnosticsUploader({
    Uri? endpoint,
    String configured = const String.fromEnvironment(
      'SMARTKEYS_DIAGNOSTICS_URL',
    ),
    bool allowLoopbackHttp = false,
    this.timeout = const Duration(seconds: 8),
    HttpClient Function()? clientFactory,
  }) : endpoint = _validate(endpoint, configured, allowLoopbackHttp),
       _clientFactory = clientFactory ?? HttpClient.new;
  final Uri? endpoint;
  final Duration timeout;
  final HttpClient Function() _clientFactory;
  HttpClient? _active;
  int _generation = 0;
  bool get configured => endpoint != null;
  static Uri? _validate(Uri? value, String configured, bool allowLocal) {
    value ??= configured.isEmpty ? null : Uri.tryParse(configured);
    if (value == null) return null;
    if (value.host.isEmpty ||
        value.userInfo.isNotEmpty ||
        value.query.isNotEmpty ||
        value.fragment.isNotEmpty ||
        value.path != '/v1/diagnostics/errors' ||
        (value.scheme != 'https' &&
            !(allowLocal &&
                value.scheme == 'http' &&
                ['127.0.0.1', 'localhost', '::1'].contains(value.host)))) {
      throw ArgumentError(
        'Diagnostics requires a dedicated HTTPS center endpoint',
      );
    }
    return value;
  }

  void cancel() {
    _generation++;
    _active?.close(force: true);
    _active = null;
  }

  Future<Set<String>> send(List<DiagnosticEvent> events) async {
    if (!configured ||
        _active != null ||
        events.isEmpty ||
        events.length > 20) {
      throw StateError('Diagnostic sharing is unavailable');
    }
    final body = utf8.encode(
      jsonEncode({
        'schemaVersion': 1,
        'events': events.map((event) => event.toUploadJson()).toList(),
      }),
    );
    if (body.length > 16 * 1024) {
      throw const FormatException('Diagnostic batch is too large');
    }
    final generation = _generation;
    final client = _clientFactory();
    _active = client;
    try {
      final request = await client.postUrl(endpoint!).timeout(timeout);
      request.followRedirects = false;
      request.headers.contentType = ContentType.json;
      request.add(body);
      final response = await request.close().timeout(timeout);
      if (response.statusCode != 200 ||
          response.headers.contentType?.mimeType != 'application/json') {
        throw const HttpException('Sharing failed');
      }
      Future<List<int>> read() async {
        final bytes = <int>[];
        await for (final chunk in response) {
          if (bytes.length + chunk.length > 4096) {
            throw const FormatException('Invalid acknowledgement');
          }
          bytes.addAll(chunk);
        }
        return bytes;
      }

      final decoded = jsonDecode(utf8.decode(await read().timeout(timeout)));
      if (generation != _generation ||
          decoded is! Map ||
          decoded.length != 1 ||
          decoded['acceptedIds'] is! List) {
        throw const FormatException('Invalid acknowledgement');
      }
      final allowed = events.map((event) => event.id).toSet();
      final accepted = decoded['acceptedIds'] as List;
      if (accepted.length != allowed.length ||
          accepted.toSet().length != allowed.length ||
          accepted.any((id) => id is! String || !allowed.contains(id))) {
        throw const FormatException('Invalid acknowledgement');
      }
      return accepted.cast<String>().toSet();
    } finally {
      client.close(force: true);
      if (identical(_active, client)) _active = null;
    }
  }
}
