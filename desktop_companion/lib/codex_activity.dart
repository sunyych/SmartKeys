import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:lumiakeys_protocol/codex_activity.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _AppServerMethodNotFound implements Exception {
  const _AppServerMethodNotFound();
}

class CodexActivityTarget {
  CodexActivityTarget(String endpoint, String chat)
    : endpoint = _parseEndpoint(endpoint.trim()),
      threadId = _parseThreadId(chat.trim());

  final Uri endpoint;
  final String threadId;

  static Uri _parseEndpoint(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null ||
        uri.scheme != 'ws' ||
        !const {'127.0.0.1', '::1'}.contains(uri.host) ||
        !uri.hasPort ||
        uri.port < 1 ||
        uri.port > 65535 ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/')) {
      throw const FormatException('Invalid local App Server address');
    }
    return uri;
  }

  static String _parseThreadId(String value) {
    const prefix = 'codex://threads/';
    final id = value.startsWith(prefix)
        ? value.substring(prefix.length)
        : value;
    if (!RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(id)) {
      throw const FormatException('Invalid Codex chat ID or link');
    }
    return id;
  }
}

/// A read-only observer for a single chat on an existing local App Server.
class CodexActivityMonitor extends ChangeNotifier {
  CodexActivityMonitor({
    this.preferences,
    this.pollInterval = const Duration(seconds: 3),
    this.requestTimeout = const Duration(seconds: 4),
    this.bearerToken,
  });

  static const storageKey = 'lumiakeys.desktop.codex_activity.v1';

  final SharedPreferencesAsync? preferences;
  final Duration pollInterval;
  final Duration requestTimeout;
  final String? bearerToken;
  CodexActivityTarget? _target;
  CodexActivityStatus? _status;
  Timer? _timer;
  HttpClient? _client;
  WebSocket? _socket;
  int _generation = 0;
  bool _started = false;
  bool _saving = false;
  bool _disposed = false;

  CodexActivityTarget? get target => _target;
  CodexActivityStatus? get status => _status;

  Future<void> start() async {
    if (_started || _disposed) return;
    _started = true;
    final generation = _generation;
    try {
      final raw = await preferences?.getString(storageKey);
      if (raw != null && !_disposed && generation == _generation) {
        final decoded = jsonDecode(raw);
        if (decoded case {'endpoint': String endpoint, 'chat': String chat}) {
          _replaceTarget(CodexActivityTarget(endpoint, chat));
          return;
        }
      }
    } catch (_) {
      // Unreadable settings leave monitoring disabled.
    }
    if (!_disposed && generation == _generation && _target != null) {
      unawaited(_poll(generation, _target!));
    }
  }

  Future<void> setTarget(CodexActivityTarget? target) async {
    if (_saving || _disposed) throw StateError('Monitoring settings are busy');
    _saving = true;
    try {
      final store = preferences;
      if (store != null) {
        if (target == null) {
          await store.remove(storageKey);
        } else {
          await store.setString(
            storageKey,
            jsonEncode({
              'endpoint': target.endpoint.toString(),
              'chat': target.threadId,
            }),
          );
        }
      }
      if (!_disposed) _replaceTarget(target);
    } finally {
      _saving = false;
    }
  }

  void _replaceTarget(CodexActivityTarget? target) {
    final generation = ++_generation;
    _timer?.cancel();
    _client?.close(force: true);
    unawaited(_socket?.close());
    _target = target;
    _status = null;
    notifyListeners();
    if (_started && target != null) unawaited(_poll(generation, target));
  }

  Future<void> _poll(int generation, CodexActivityTarget target) async {
    final client = HttpClient()..connectionTimeout = requestTimeout;
    client.findProxy = (_) => 'DIRECT';
    _client = client;
    WebSocket? socket;
    StreamIterator<dynamic>? responses;
    CodexActivityStatus? next;
    try {
      socket = await _connect(client, target.endpoint);
      if (_disposed || generation != _generation) return;
      _socket = socket;
      responses = StreamIterator(socket);
      next = await _readStatus(
        socket,
        responses,
        target.threadId,
      ).timeout(requestTimeout);
    } catch (_) {
      // Connection errors do not describe the monitored chat.
    } finally {
      unawaited(responses?.cancel());
      unawaited(socket?.close());
      client.close(force: true);
      if (identical(_client, client)) _client = null;
      if (identical(_socket, socket)) _socket = null;
    }
    if (_disposed || generation != _generation) return;
    if (_status != next) {
      _status = next;
      notifyListeners();
    }
    if (!_disposed && generation == _generation) {
      _timer = Timer(pollInterval, () => unawaited(_poll(generation, target)));
    }
  }

  Future<WebSocket> _connect(HttpClient client, Uri endpoint) async {
    final random = Random.secure();
    final key = base64Encode(
      List<int>.generate(16, (_) => random.nextInt(256)),
    );
    final httpEndpoint = endpoint.replace(scheme: 'http');
    final request = await client.getUrl(httpEndpoint).timeout(requestTimeout);
    request.followRedirects = false;
    request.headers
      ..set(HttpHeaders.connectionHeader, 'Upgrade')
      ..set(HttpHeaders.upgradeHeader, 'websocket')
      ..set('Sec-WebSocket-Key', key)
      ..set('Sec-WebSocket-Version', '13');
    if (bearerToken case final String token when token.isNotEmpty) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    }
    final response = await request.close().timeout(requestTimeout);
    final expectedAccept = base64Encode(
      sha1
          .convert(ascii.encode('${key}258EAFA5-E914-47DA-95CA-C5AB0DC85B11'))
          .bytes,
    );
    if (response.statusCode != HttpStatus.switchingProtocols ||
        response.headers.value(HttpHeaders.upgradeHeader)?.toLowerCase() !=
            'websocket' ||
        response.headers.value('Sec-WebSocket-Accept') != expectedAccept) {
      throw const FormatException('App Server did not upgrade the connection');
    }
    return WebSocket.fromUpgradedSocket(
      await response.detachSocket(),
      serverSide: false,
    );
  }

  Future<CodexActivityStatus?> _readStatus(
    WebSocket socket,
    StreamIterator<dynamic> responses,
    String threadId,
  ) async {
    Future<Object?> call(
      int id,
      String method,
      Map<String, Object?> params,
    ) async {
      socket.add(jsonEncode({'id': id, 'method': method, 'params': params}));
      while (await responses.moveNext()) {
        final raw = responses.current;
        if (raw is! String || raw.length > 256 * 1024) continue;
        final decoded = jsonDecode(raw);
        if (decoded is! Map ||
            decoded['id'] != id ||
            decoded.containsKey('method')) {
          continue;
        }
        if (decoded['error'] case {'code': int code} when code == -32601) {
          throw const _AppServerMethodNotFound();
        }
        if (decoded.containsKey('error')) {
          throw const FormatException('App Server status request failed');
        }
        return decoded['result'];
      }
      throw const FormatException('App Server closed the connection');
    }

    await call(1, 'initialize', {
      'clientInfo': {
        'name': 'lumiakeys_status',
        'title': 'LumiaKey Chat Status',
        'version': '1.0.0',
      },
    });
    socket.add(jsonEncode({'method': 'initialized'}));
    final result = await call(2, 'thread/read', {
      'threadId': threadId,
      'includeTurns': false,
    });
    if (result case {
      'thread': {'id': String id, 'status': Map status},
    } when id == threadId) {
      switch (status['type']) {
        case 'active':
          final flags = status['activeFlags'];
          if (flags is! List) return null;
          return flags.contains('waitingOnApproval') ||
                  flags.contains('waitingOnUserInput')
              ? CodexActivityStatus.needsInput
              : CodexActivityStatus.thinking;
        case 'systemError':
          return CodexActivityStatus.error;
        case 'idle' || 'notLoaded':
          final Object? turns;
          try {
            turns = await call(3, 'thread/turns/list', {
              'threadId': threadId,
              'limit': 1,
              'sortDirection': 'desc',
              'itemsView': 'notLoaded',
            });
          } on _AppServerMethodNotFound {
            // Older servers can report live idle without exposing turn outcomes.
            return status['type'] == 'idle' ? CodexActivityStatus.idle : null;
          }
          if (turns case {'data': List data}) {
            if (data.isEmpty) return CodexActivityStatus.idle;
            return switch (data.first) {
              {'status': 'completed'} => CodexActivityStatus.complete,
              {'status': 'failed'} => CodexActivityStatus.error,
              {'status': 'interrupted', 'error': null} =>
                CodexActivityStatus.idle,
              {'status': 'interrupted', 'error': Map _} =>
                CodexActivityStatus.error,
              _ => null,
            };
          }
      }
    }
    return null;
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    _timer?.cancel();
    _client?.close(force: true);
    unawaited(_socket?.close());
    super.dispose();
  }
}
