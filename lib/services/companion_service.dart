import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:lumiakeys_protocol/lumiakeys_protocol.dart';

void _validateDictationPayload(String sessionId, int sequence, String text) {
  if (sessionId.isEmpty ||
      sessionId.length > 128 ||
      !RegExp(r'^[A-Za-z0-9._:-]+$').hasMatch(sessionId) ||
      sequence < 0 ||
      text.isEmpty ||
      text.length > 8000 ||
      text.runes.any(
        (rune) => rune < 0x20 && rune != 0x09 && rune != 0x0a && rune != 0x0d,
      )) {
    throw const CompanionDictationException(
      'Dictation text or session data is invalid.',
    );
  }
  final body = jsonEncode({
    'sessionId': sessionId,
    'sequence': sequence,
    'text': text,
  });
  if (utf8.encode(body).length > 64 * 1024) {
    throw const CompanionDictationException('Dictation request is too large.');
  }
}

@immutable
class CompanionHost {
  const CompanionHost({
    required this.name,
    required this.platform,
    required this.address,
    required this.port,
    required this.token,
    this.protocolVersion = 1,
    this.revision = 0,
    this.capabilities = const {},
  });

  final String name;
  final String platform;
  final String address;
  final int port;
  final String token;
  final int protocolVersion;
  final int revision;
  final Set<String> capabilities;

  bool get isApple => platform == 'macos';
  bool get supportsManifest =>
      protocolVersion >= 2 && capabilities.contains('manifest');

  @override
  bool operator ==(Object other) =>
      other is CompanionHost &&
      other.name == name &&
      other.platform == platform &&
      other.address == address &&
      other.port == port &&
      other.token == token &&
      other.protocolVersion == protocolVersion &&
      other.revision == revision &&
      other.capabilities.length == capabilities.length &&
      other.capabilities.every(capabilities.contains);

  @override
  int get hashCode => Object.hash(
    name,
    platform,
    address,
    port,
    token,
    protocolVersion,
    revision,
    Object.hashAll(capabilities.toList()..sort()),
  );
}

enum CompanionSyncStatus { disconnected, discovering, syncing, ready, error }

abstract interface class CompanionService {
  ValueListenable<CompanionHost?> get activeHost;
  ValueListenable<DesktopManifest?> get manifest;
  ValueListenable<CompanionSyncStatus> get syncStatus;
  ValueListenable<String?> get errorMessage;
  Future<void> start();
  Future<void> refreshManifest();
  Future<void> executeRemote(RemoteActionRequest request);
  Future<void> sendDictation({
    required String sessionId,
    required int sequence,
    required String text,
  });
  Future<void> execute(String command);
  void dispose();
}

class LanCompanionService implements CompanionService {
  LanCompanionService({
    this.discoveryPort = 45832,
    this.hostExpiry = const Duration(seconds: 8),
    this.expiryPollInterval = const Duration(seconds: 3),
    this.dictationTimeout = const Duration(seconds: 8),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final int discoveryPort;
  final Duration hostExpiry;
  final Duration expiryPollInterval;
  final Duration dictationTimeout;
  final DateTime Function() _now;
  final ValueNotifier<CompanionHost?> _host = ValueNotifier(null);
  final ValueNotifier<DesktopManifest?> _manifest = ValueNotifier(null);
  final ValueNotifier<CompanionSyncStatus> _status = ValueNotifier(
    CompanionSyncStatus.disconnected,
  );
  final ValueNotifier<String?> _error = ValueNotifier(null);
  RawDatagramSocket? _socket;
  Timer? _expiryTimer;
  DateTime? _lastSeen;
  bool _fetchingManifest = false;
  int? _pendingRevision;

  /// Ephemeral listener port, also useful to bind an in-process loopback peer.
  int? get boundDiscoveryPort => _socket?.port;

  @override
  ValueListenable<CompanionHost?> get activeHost => _host;

  @override
  ValueListenable<DesktopManifest?> get manifest => _manifest;

  @override
  ValueListenable<CompanionSyncStatus> get syncStatus => _status;

  @override
  ValueListenable<String?> get errorMessage => _error;

  @override
  Future<void> start() async {
    if (_socket != null) return;
    _status.value = CompanionSyncStatus.discovering;
    try {
      final socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        discoveryPort,
        reuseAddress: true,
      );
      _socket = socket;
      socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        final packet = socket.receive();
        if (packet == null) return;
        _receive(packet);
      });
      _expiryTimer = Timer.periodic(expiryPollInterval, (_) {
        final seen = _lastSeen;
        if (seen != null && _now().difference(seen) > hostExpiry) {
          _host.value = null;
          _lastSeen = null;
          _status.value = CompanionSyncStatus.discovering;
        }
      });
    } catch (error) {
      _setError('Companion discovery unavailable: $error');
    }
  }

  void _receive(Datagram packet) {
    try {
      final data = jsonDecode(utf8.decode(packet.data));
      if (data is! Map || data['service'] != 'lumiakeys-companion') return;
      final platform = data['platform']?.toString();
      final port = data['port'];
      final token = data['token']?.toString();
      if ((platform != 'windows' &&
              platform != 'macos' &&
              platform != 'linux') ||
          port is! int ||
          token == null ||
          token.isEmpty) {
        return;
      }
      final version = data['version'] is int ? data['version']! as int : 1;
      final revision = data['revision'] is int ? data['revision']! as int : 0;
      final capabilities = (data['capabilities'] as List? ?? const [])
          .map((value) => value.toString())
          .toSet();
      final previous = _host.value;
      final address = packet.address.address;
      final isSelectedHost =
          previous == null ||
          (previous.address == address &&
              previous.port == port &&
              previous.token == token);
      if (!isSelectedHost) return;
      final hostChanged =
          previous == null ||
          previous.address != address ||
          previous.port != port ||
          previous.token != token;
      final revisionChanged = previous?.revision != revision;
      _lastSeen = _now();
      final host = CompanionHost(
        name: data['name']?.toString() ?? packet.address.address,
        platform: platform!,
        address: address,
        port: port,
        token: token,
        protocolVersion: version,
        revision: revision,
        capabilities: capabilities,
      );
      _host.value = host;
      _error.value = null;
      if (host.supportsManifest) {
        if (hostChanged || revisionChanged || _manifest.value == null) {
          _pendingRevision = revision;
          unawaited(refreshManifest());
        }
      } else {
        _manifest.value = null;
        _status.value = CompanionSyncStatus.ready;
      }
    } catch (_) {
      // Ignore unrelated UDP traffic on the discovery port.
    }
  }

  @override
  Future<void> refreshManifest() async {
    final host = _host.value;
    if (host == null || !host.supportsManifest) return;
    if (_fetchingManifest) return;
    _fetchingManifest = true;
    _status.value = CompanionSyncStatus.syncing;
    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 3);
      final request = await client.get(host.address, host.port, '/manifest');
      request.headers.set('x-lumiakeys-token', host.token);
      final response = await request.close();
      final body = await utf8.decoder.bind(response).join();
      client.close(force: true);
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          body.isEmpty ? 'Desktop rejected layout sync' : body,
        );
      }
      final decoded = jsonDecode(body);
      if (decoded is! Map) throw const FormatException('Invalid manifest');
      _manifest.value = DesktopManifest.fromJson(
        decoded.map((key, value) => MapEntry(key.toString(), value)),
      );
      _pendingRevision = null;
      _error.value = null;
      _status.value = CompanionSyncStatus.ready;
    } catch (error) {
      _setError('Desktop sync failed: $error');
    } finally {
      _fetchingManifest = false;
      final pending = _pendingRevision;
      if (pending != null && pending != _manifest.value?.revision) {
        unawaited(refreshManifest());
      }
    }
  }

  @override
  Future<void> executeRemote(RemoteActionRequest request) =>
      _post(jsonEncode(request.toJson()));

  @override
  Future<void> sendDictation({
    required String sessionId,
    required int sequence,
    required String text,
  }) async {
    final host = _host.value;
    if (host == null) {
      throw const CompanionDictationException(
        'Connect to a LumiaKey Desktop that supports local dictation.',
      );
    }
    if (!host.capabilities.contains('local-dictation-v1')) {
      throw const CompanionDictationException(
        'Update LumiaKey Desktop to enable local dictation.',
      );
    }
    _validateDictationPayload(sessionId, sequence, text);
    final body = jsonEncode({
      'sessionId': sessionId,
      'sequence': sequence,
      'text': text,
    });
    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
      final request = await client.post(host.address, host.port, '/dictation');
      request.headers.contentType = ContentType.json;
      request.headers.set('x-lumiakeys-token', host.token);
      request.write(body);
      final response = await request.close().timeout(dictationTimeout);
      final responseBody = await utf8.decoder
          .bind(response)
          .join()
          .timeout(dictationTimeout);
      if (_host.value != host) {
        throw const CompanionDictationException(
          'Desktop connection changed before dictation delivery completed.',
        );
      }
      if (response.statusCode != HttpStatus.ok) {
        throw CompanionDictationException(
          responseBody.isEmpty
              ? 'Desktop could not insert the dictated text.'
              : responseBody,
        );
      }
      final decoded = jsonDecode(responseBody);
      if (decoded is! Map || decoded['ok'] != true) {
        throw const CompanionDictationException(
          'Desktop did not confirm dictation insertion.',
        );
      }
    } on CompanionDictationException {
      rethrow;
    } catch (error) {
      final wrapped = CompanionDictationException(
        'Dictation delivery failed: $error',
      );
      throw wrapped;
    } finally {
      client?.close(force: true);
    }
  }

  @override
  Future<void> execute(String command) => _post(command);

  Future<void> _post(String body) async {
    final host = _host.value;
    if (host == null) {
      _setError('No LumiaKey Desktop found on this network.');
      return;
    }
    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 3);
      final request = await client.post(host.address, host.port, '/action');
      request.headers.contentType = ContentType.json;
      request.headers.set('x-lumiakeys-token', host.token);
      request.write(body);
      final response = await request.close();
      final responseBody = await utf8.decoder.bind(response).join();
      client.close(force: true);
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          responseBody.isEmpty ? 'Desktop rejected the action' : responseBody,
        );
      }
      final decoded = jsonDecode(responseBody);
      final revision = decoded is Map ? decoded['revision'] : null;
      if (revision is int && revision != _manifest.value?.revision) {
        _pendingRevision = revision;
        unawaited(refreshManifest());
      }
      _error.value = null;
      _status.value = CompanionSyncStatus.ready;
    } catch (error) {
      _setError('Desktop action failed: $error');
    }
  }

  void _setError(String message) {
    _error.value = message;
    _status.value = CompanionSyncStatus.error;
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    _socket?.close();
    _host.dispose();
    _manifest.dispose();
    _status.dispose();
    _error.dispose();
  }
}

class RecordingCompanionService implements CompanionService {
  final ValueNotifier<CompanionHost?> host = ValueNotifier(null);
  final ValueNotifier<DesktopManifest?> syncedManifest = ValueNotifier(null);
  final ValueNotifier<CompanionSyncStatus> status = ValueNotifier(
    CompanionSyncStatus.disconnected,
  );
  final ValueNotifier<String?> errors = ValueNotifier(null);
  final List<String> commands = [];
  final List<RemoteActionRequest> remoteActions = [];
  final List<({String sessionId, int sequence, String text})>
  dictationRequests = [];
  String? dictationError;
  int refreshCount = 0;

  @override
  ValueListenable<CompanionHost?> get activeHost => host;
  @override
  ValueListenable<DesktopManifest?> get manifest => syncedManifest;
  @override
  ValueListenable<CompanionSyncStatus> get syncStatus => status;
  @override
  ValueListenable<String?> get errorMessage => errors;
  @override
  Future<void> start() async {}
  @override
  Future<void> refreshManifest() async => refreshCount++;
  @override
  Future<void> executeRemote(RemoteActionRequest request) async =>
      remoteActions.add(request);
  @override
  Future<void> sendDictation({
    required String sessionId,
    required int sequence,
    required String text,
  }) async {
    _validateDictationPayload(sessionId, sequence, text);
    final currentHost = host.value;
    if (currentHost == null ||
        !currentHost.capabilities.contains('local-dictation-v1')) {
      throw const CompanionDictationException('Dictation is unavailable.');
    }
    if (dictationError != null) {
      throw CompanionDictationException(dictationError!);
    }
    dictationRequests.add((
      sessionId: sessionId,
      sequence: sequence,
      text: text,
    ));
  }

  @override
  Future<void> execute(String command) async => commands.add(command);
  @override
  void dispose() {
    host.dispose();
    syncedManifest.dispose();
    status.dispose();
    errors.dispose();
  }
}

class CompanionDictationException implements Exception {
  const CompanionDictationException(this.message);
  final String message;

  @override
  String toString() => message;
}
