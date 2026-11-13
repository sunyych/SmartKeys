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
    this.computerId,
    this.protocolVersion = 1,
    this.revision = 0,
    this.capabilities = const {},
  });

  final String name;
  final String platform;
  final String address;
  final int port;
  final String token;
  final String? computerId;
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
      other.computerId == computerId &&
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
    computerId,
    protocolVersion,
    revision,
    Object.hashAll(capabilities.toList()..sort()),
  );
}

enum CompanionSyncStatus { disconnected, discovering, syncing, ready, error }

@immutable
class CompanionComputerChoice {
  const CompanionComputerChoice({
    required this.id,
    required this.name,
    required this.platform,
    this.address = '',
  });

  final String id;
  final String name;
  final String platform;
  final String address;
}

abstract interface class SwitchableCompanionConnection {
  ValueListenable<List<CompanionComputerChoice>> get computerChoices;
  String? get selectedComputerChoiceId;
  bool get isComputerSelectionPinned;
  Future<void> selectComputer(String id);
  Future<void> suspendComputerSelection();
}

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

abstract interface class ManualCompanionConnection {
  Future<void> connectManually(String code);
  Future<void> disconnect();
}

abstract interface class CompanionPointerConnection {
  ValueListenable<String?> get pointerError;
  Future<void> sendPointerInputs(List<PointerInput> inputs);
  void discardPendingPointerInputs();
}

class LanCompanionService
    implements
        CompanionService,
        ManualCompanionConnection,
        CompanionPointerConnection,
        SwitchableCompanionConnection {
  LanCompanionService({
    this.discoveryPort = 45832,
    this.hostExpiry = const Duration(seconds: 8),
    this.expiryPollInterval = const Duration(seconds: 3),
    this.dictationTimeout = const Duration(seconds: 8),
    this.enableDiscovery = true,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final int discoveryPort;
  final Duration hostExpiry;
  final Duration expiryPollInterval;
  final Duration dictationTimeout;
  final bool enableDiscovery;
  final DateTime Function() _now;
  final ValueNotifier<CompanionHost?> _host = ValueNotifier(null);
  final ValueNotifier<DesktopManifest?> _manifest = ValueNotifier(null);
  final ValueNotifier<CompanionSyncStatus> _status = ValueNotifier(
    CompanionSyncStatus.disconnected,
  );
  final ValueNotifier<String?> _error = ValueNotifier(null);
  final ValueNotifier<String?> _pointerError = ValueNotifier(null);
  final ValueNotifier<List<CompanionComputerChoice>> _computerChoices =
      ValueNotifier(const []);
  final Map<String, _KnownCompanion> _knownComputers = {};
  final Map<String, List<CompanionHost>> _alternateHosts = {};
  RawDatagramSocket? _socket;
  Timer? _expiryTimer;
  Timer? _pointerFlushTimer;
  final List<PointerInput> _pointerQueue = [];
  CompanionHost? _pointerQueueHost;
  HttpClient? _pointerClient;
  bool _pointerFlushing = false;
  DateTime? _lastSeen;
  bool _fetchingManifest = false;
  bool _manualHeartbeatRunning = false;
  bool _manualConnectionSelected = false;
  String? _selectedComputerChoiceId;
  bool _selectionPinned = false;
  bool _selectionSuspended = false;
  int? _pendingRevision;
  CompanionHost? _pendingManifestHost;
  int? _pendingManifestEpoch;
  Timer? _manualHeartbeat;
  int _selectionEpoch = 0;
  bool _disposed = false;

  @override
  ValueListenable<String?> get pointerError => _pointerError;

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
  ValueListenable<List<CompanionComputerChoice>> get computerChoices =>
      _computerChoices;

  @override
  String? get selectedComputerChoiceId => _selectedComputerChoiceId;
  @override
  bool get isComputerSelectionPinned => _selectionPinned;

  @override
  Future<void> start() async {
    if (_disposed || _socket != null) return;
    if (!enableDiscovery) {
      _status.value = CompanionSyncStatus.disconnected;
      return;
    }
    _status.value = CompanionSyncStatus.discovering;
    try {
      final socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        discoveryPort,
        reuseAddress: true,
      );
      if (_disposed) {
        socket.close();
        return;
      }
      _socket = socket;
      socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        final packet = socket.receive();
        if (packet == null) return;
        _receive(packet);
      });
      _expiryTimer = Timer.periodic(expiryPollInterval, (_) {
        _pruneKnownComputers();
        final seen = _lastSeen;
        if (seen != null && _now().difference(seen) > hostExpiry) {
          _host.value = null;
          _lastSeen = null;
          _status.value = CompanionSyncStatus.discovering;
        }
      });
    } catch (error) {
      if (!_disposed) _setError('Companion discovery unavailable: $error');
    }
  }

  @override
  Future<void> connectManually(String code) async {
    if (_disposed) return;
    _selectionSuspended = false;
    final epoch = ++_selectionEpoch;
    _manualConnectionSelected = true;
    _clearPendingManifestRefresh();
    _manualHeartbeat?.cancel();
    _host.value = null;
    _manifest.value = null;
    _lastSeen = null;
    _status.value = CompanionSyncStatus.syncing;
    _error.value = null;
    try {
      final parsed = _parseConnectionCode(code);
      final info = await _getJson(
        parsed.address,
        parsed.port,
        '/info',
        parsed.token,
      );
      if (epoch != _selectionEpoch) return;
      final platform = info['platform'];
      final version = info['version'];
      final revision = info['revision'];
      final capabilities = info['capabilities'];
      final computerId = _validatedComputerId(info['computerId']);
      if (info['name'] is! String ||
          (info['name'] as String).isEmpty ||
          !['windows', 'macos', 'linux'].contains(platform) ||
          version is! int ||
          version < 2 ||
          revision is! int ||
          capabilities is! List ||
          !capabilities.map((value) => value.toString()).contains('manifest')) {
        throw const FormatException('This LumiaKey Desktop is not compatible.');
      }
      var host = CompanionHost(
        name: info['name'] as String,
        platform: platform as String,
        address: parsed.address,
        port: parsed.port,
        token: parsed.token,
        computerId: computerId,
        protocolVersion: version,
        revision: revision,
        capabilities: capabilities.map((value) => value.toString()).toSet(),
      );
      final manifestJson = await _getJson(
        host.address,
        host.port,
        '/manifest',
        host.token,
      );
      if (epoch != _selectionEpoch) return;
      final manifest = DesktopManifest.fromJson(
        manifestJson.map((key, value) => MapEntry(key.toString(), value)),
      );
      final manifestId = _validatedComputerId(manifest.computerId);
      if (computerId != null &&
          manifestId != null &&
          computerId != manifestId) {
        throw const FormatException(
          'Desktop identity changed during pairing. Retry connection.',
        );
      }
      host = CompanionHost(
        name: host.name,
        platform: host.platform,
        address: host.address,
        port: host.port,
        token: host.token,
        computerId: computerId ?? manifestId,
        protocolVersion: host.protocolVersion,
        revision: manifest.revision,
        capabilities: host.capabilities,
      );
      final choiceId = _choiceId(host);
      _removeAliasesFor(host, preserve: choiceId);
      _knownComputers[choiceId] = _KnownCompanion(
        host,
        _now(),
        manuallyPaired: true,
      );
      _selectedComputerChoiceId = choiceId;
      _selectionPinned = true;
      _selectionSuspended = false;
      _publishComputerChoices();
      _host.value = host;
      _manifest.value = manifest;
      _lastSeen = _now();
      _status.value = CompanionSyncStatus.ready;
      _manualHeartbeat = Timer.periodic(expiryPollInterval, (_) {
        final selected = _host.value;
        if (selected != null) unawaited(_checkManualHost(selected, epoch));
      });
    } catch (error) {
      if (epoch != _selectionEpoch) return;
      _host.value = null;
      _manifest.value = null;
      _setError('Desktop connection failed: $error');
    }
  }

  Future<void> _checkManualHost(CompanionHost host, int epoch) async {
    if (_disposed || _manualHeartbeatRunning) return;
    _manualHeartbeatRunning = true;
    try {
      final info = await _getJson(host.address, host.port, '/info', host.token);
      if (epoch != _selectionEpoch || _host.value != host) return;
      final revision = info['revision'];
      final computerId = _validatedComputerId(info['computerId']);
      if (revision is! int) {
        throw const FormatException('Invalid Desktop revision.');
      }
      var currentHost = host;
      if (revision != host.revision) {
        currentHost = CompanionHost(
          name: info['name'] is String ? info['name'] as String : host.name,
          platform: host.platform,
          address: host.address,
          port: host.port,
          token: host.token,
          computerId: computerId ?? host.computerId,
          protocolVersion: host.protocolVersion,
          revision: revision,
          capabilities: host.capabilities,
        );
        _host.value = currentHost;
        final manifestJson = await _getJson(
          host.address,
          host.port,
          '/manifest',
          host.token,
        );
        if (epoch != _selectionEpoch || _host.value != currentHost) return;
        final manifest = DesktopManifest.fromJson(
          manifestJson.map((key, value) => MapEntry(key.toString(), value)),
        );
        if (manifest.revision != revision) {
          throw const FormatException('Desktop layout did not synchronize.');
        }
        _manifest.value = manifest;
      }
      if (epoch == _selectionEpoch && _host.value == currentHost) {
        _lastSeen = _now();
        _status.value = CompanionSyncStatus.ready;
        _error.value = null;
      }
    } catch (_) {
      if (epoch != _selectionEpoch) return;
      _host.value = null;
      if (await _recoverAlternative(host, epoch)) return;
      _host.value = null;
      _manifest.value = null;
      _lastSeen = null;
      _status.value = CompanionSyncStatus.disconnected;
      _error.value =
          'LumiaKey Desktop connection expired. Reconnect using its code.';
    } finally {
      _manualHeartbeatRunning = false;
    }
  }

  Future<bool> _recoverAlternative(CompanionHost failedHost, int epoch) async {
    final id = failedHost.computerId;
    if (id == null || _disposed || epoch != _selectionEpoch) return false;
    final candidates = _alternateHosts['id:$id'] ?? const <CompanionHost>[];
    for (final candidate in candidates.reversed) {
      try {
        final info = await _getJson(
          candidate.address,
          candidate.port,
          '/info',
          candidate.token,
        );
        if (epoch != _selectionEpoch ||
            _disposed ||
            (_host.value != null && _host.value != failedHost)) {
          return false;
        }
        if (_validatedComputerId(info['computerId']) != id) continue;
        final revision = info['revision'];
        if (revision is! int) continue;
        final manifestJson = await _getJson(
          candidate.address,
          candidate.port,
          '/manifest',
          candidate.token,
        );
        if (epoch != _selectionEpoch || _disposed) return false;
        final manifest = DesktopManifest.fromJson(
          manifestJson.map((key, value) => MapEntry(key.toString(), value)),
        );
        if (manifest.computerId != id || manifest.revision != revision) {
          continue;
        }
        final current = CompanionHost(
          name: info['name'] is String
              ? info['name'] as String
              : candidate.name,
          platform: candidate.platform,
          address: candidate.address,
          port: candidate.port,
          token: candidate.token,
          computerId: id,
          protocolVersion: candidate.protocolVersion,
          revision: revision,
          capabilities: candidate.capabilities,
        );
        _host.value = current;
        _manifest.value = manifest;
        _knownComputers['id:$id'] = _KnownCompanion(
          current,
          _now(),
          manuallyPaired: true,
        );
        _lastSeen = _now();
        _status.value = CompanionSyncStatus.ready;
        _error.value = null;
        _publishComputerChoices();
        return true;
      } catch (_) {
        // Try another endpoint for this same authenticated desktop identity.
      }
    }
    return false;
  }

  @override
  Future<void> disconnect() async {
    if (_disposed) return;
    ++_selectionEpoch;
    _manualConnectionSelected = false;
    _selectionPinned = false;
    _selectedComputerChoiceId = null;
    _selectionSuspended = false;
    _clearPendingManifestRefresh();
    _manualHeartbeat?.cancel();
    _manualHeartbeat = null;
    _host.value = null;
    _manifest.value = null;
    _lastSeen = null;
    _status.value = enableDiscovery
        ? CompanionSyncStatus.discovering
        : CompanionSyncStatus.disconnected;
    _error.value = null;
  }

  @override
  Future<void> selectComputer(String id) async {
    if (_disposed) return;
    final known = _knownComputers[id];
    if (known == null) {
      throw ArgumentError.value(id, 'id', 'Unknown Desktop computer choice.');
    }
    final host = known.host;
    _selectedComputerChoiceId = id;
    _selectionPinned = true;
    _selectionSuspended = false;
    _manualConnectionSelected = known.manuallyPaired;
    await connectManually('${host.address}:${host.port} ${host.token}');
    _manualConnectionSelected = known.manuallyPaired;
    if (_disposed ||
        (host.computerId != null && _selectedComputerChoiceId != id) ||
        _host.value?.address != host.address ||
        _host.value?.port != host.port ||
        _status.value != CompanionSyncStatus.ready) {
      throw StateError(_error.value ?? 'Could not connect to that computer.');
    }
  }

  @override
  Future<void> suspendComputerSelection() async {
    if (_disposed) return;
    ++_selectionEpoch;
    _selectionSuspended = true;
    _manualConnectionSelected = false;
    _clearPendingManifestRefresh();
    _manualHeartbeat?.cancel();
    _manualHeartbeat = null;
    _host.value = null;
    _manifest.value = null;
    _lastSeen = null;
    _status.value = enableDiscovery
        ? CompanionSyncStatus.discovering
        : CompanionSyncStatus.disconnected;
    _error.value = null;
  }

  Future<Map<String, dynamic>> _getJson(
    String address,
    int port,
    String path,
    String token,
  ) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
    try {
      final request = await client
          .get(address, port, path)
          .timeout(const Duration(seconds: 4));
      request.followRedirects = false;
      request.headers.set('x-lumiakeys-token', token);
      final response = await request.close().timeout(
        const Duration(seconds: 4),
      );
      final body = await _readBoundedResponse(
        response,
        const Duration(seconds: 4),
        256 * 1024,
      );
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          'Desktop rejected the connection (${response.statusCode}).',
        );
      }
      final decoded = jsonDecode(body);
      if (decoded is! Map) {
        throw const FormatException('Invalid Desktop response.');
      }
      return decoded.map((key, value) => MapEntry(key.toString(), value));
    } finally {
      client.close(force: true);
    }
  }

  Future<String> _readBoundedResponse(
    HttpClientResponse response,
    Duration timeout,
    int maxBytes,
  ) async {
    Future<String> read() async {
      final bytes = <int>[];
      await for (final chunk in response) {
        if (bytes.length + chunk.length > maxBytes) {
          throw const FormatException('Desktop response is too large.');
        }
        bytes.addAll(chunk);
      }
      return utf8.decode(bytes);
    }

    return read().timeout(timeout);
  }

  static ({String address, int port, String token}) _parseConnectionCode(
    String code,
  ) {
    final match = RegExp(
      r'^((?:\d{1,3}\.){3}\d{1,3}):(\d{1,5})\s+([A-Fa-f0-9]{32,128})$',
    ).firstMatch(code.trim());
    if (match == null) {
      throw const FormatException(
        'Paste the Desktop code in address:port token format.',
      );
    }
    final address = InternetAddress.tryParse(match.group(1)!);
    final port = int.parse(match.group(2)!);
    if (address == null ||
        address.type != InternetAddressType.IPv4 ||
        port < 1 ||
        port > 65535 ||
        !_isPrivateAddress(address)) {
      throw const FormatException(
        'Only a private IPv4 Desktop address and valid port are allowed.',
      );
    }
    return (address: address.address, port: port, token: match.group(3)!);
  }

  static bool _isPrivateAddress(InternetAddress address) {
    final octets = address.rawAddress;
    return octets[0] == 10 ||
        octets[0] == 127 ||
        (octets[0] == 172 && octets[1] >= 16 && octets[1] <= 31) ||
        (octets[0] == 192 && octets[1] == 168);
  }

  void _receive(Datagram packet) {
    if (_disposed || !enableDiscovery) return;
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
      final address = packet.address.address;
      var computerId = _validatedComputerId(data['computerId']);
      if (computerId == null) {
        for (final known in _knownComputers.values) {
          final oldHost = known.host;
          if (oldHost.computerId != null &&
              oldHost.platform == platform &&
              oldHost.address == address &&
              oldHost.port == port &&
              oldHost.token == token) {
            computerId = oldHost.computerId;
            break;
          }
        }
      }
      final host = CompanionHost(
        name: data['name']?.toString() ?? address,
        platform: platform!,
        address: address,
        port: port,
        token: token,
        computerId: computerId,
        protocolVersion: version,
        revision: revision,
        capabilities: capabilities,
      );
      final choiceId = _choiceId(host);
      _removeAliasesFor(host, preserve: choiceId);
      final previous = _host.value;
      final sameActiveComputer =
          previous != null &&
          host.computerId != null &&
          previous.computerId == host.computerId;
      if (sameActiveComputer &&
          (previous.address != host.address ||
              previous.port != host.port ||
              previous.token != host.token)) {
        final alternatives = _alternateHosts.putIfAbsent(choiceId, () => []);
        alternatives.removeWhere(
          (candidate) =>
              candidate.address == host.address &&
              candidate.port == host.port &&
              candidate.token == host.token,
        );
        if (alternatives.length == 4) {
          alternatives.removeAt(0);
        }
        alternatives.add(host);
      }
      final retainedHost =
          sameActiveComputer &&
              (previous.address != host.address ||
                  previous.port != host.port ||
                  previous.token != host.token)
          ? previous
          : host;
      final oldChoice = _knownComputers[choiceId];
      _knownComputers[choiceId] = _KnownCompanion(
        retainedHost,
        _now(),
        manuallyPaired: oldChoice?.manuallyPaired ?? false,
      );
      _publishComputerChoices();
      if (_selectionSuspended) return;
      if (_selectionPinned && _selectedComputerChoiceId != choiceId) return;
      if (!_selectionPinned) _selectedComputerChoiceId = choiceId;
      final matchesCurrent =
          previous != null &&
          ((host.computerId != null &&
                  previous.computerId == host.computerId) ||
              (previous.address == address &&
                  previous.port == port &&
                  previous.token == token));
      if (_manualConnectionSelected && !matchesCurrent) return;
      if (previous != null && !matchesCurrent) return;
      final sameEndpoint =
          previous != null &&
          previous.address == address &&
          previous.port == port &&
          previous.token == token;
      final hostChanged = previous == null || !sameEndpoint;
      if (sameActiveComputer && !sameEndpoint) {
        if (_status.value == CompanionSyncStatus.error) {
          unawaited(_recoverAlternative(previous, _selectionEpoch));
        }
        return;
      }
      final recoverSession = _status.value == CompanionSyncStatus.error;
      if (hostChanged) {
        ++_selectionEpoch;
        _clearPendingManifestRefresh();
      }
      final revisionChanged = previous?.revision != revision;
      _lastSeen = _now();
      _host.value = host;
      _error.value = null;
      if (host.supportsManifest) {
        if (hostChanged ||
            revisionChanged ||
            _manifest.value == null ||
            recoverSession) {
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
    if (_disposed) return;
    final host = _host.value;
    if (host == null || !host.supportsManifest) return;
    final epoch = _selectionEpoch;
    if (_fetchingManifest) {
      _pendingManifestHost = host;
      _pendingManifestEpoch = epoch;
      return;
    }
    _pendingManifestHost = null;
    _pendingManifestEpoch = null;
    _fetchingManifest = true;
    _status.value = CompanionSyncStatus.syncing;
    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
      final request = await client
          .get(host.address, host.port, '/manifest')
          .timeout(const Duration(seconds: 4));
      request.followRedirects = false;
      request.headers.set('x-lumiakeys-token', host.token);
      final response = await request.close().timeout(
        const Duration(seconds: 4),
      );
      final body = await _readBoundedResponse(
        response,
        const Duration(seconds: 4),
        256 * 1024,
      );
      if (_disposed ||
          _selectionEpoch != epoch ||
          !_sameDesktopSession(_host.value, host)) {
        return;
      }
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          body.isEmpty ? 'Desktop rejected layout sync' : body,
        );
      }
      final decoded = jsonDecode(body);
      if (decoded is! Map) throw const FormatException('Invalid manifest');
      final manifest = DesktopManifest.fromJson(
        decoded.map((key, value) => MapEntry(key.toString(), value)),
      );
      _manifest.value = manifest;
      final manifestId = _validatedComputerId(manifest.computerId);
      final currentHost = _host.value!;
      if (currentHost.computerId == null &&
          manifestId != null &&
          _selectionEpoch == epoch &&
          _sameDesktopSession(_host.value, host)) {
        final identifiedHost = CompanionHost(
          name: currentHost.name,
          platform: currentHost.platform,
          address: currentHost.address,
          port: currentHost.port,
          token: currentHost.token,
          computerId: manifestId,
          protocolVersion: currentHost.protocolVersion,
          revision: currentHost.revision > manifest.revision
              ? currentHost.revision
              : manifest.revision,
          capabilities: currentHost.capabilities,
        );
        final oldId = _selectedComputerChoiceId;
        final newId = _choiceId(identifiedHost);
        final oldEntry = oldId == null ? null : _knownComputers.remove(oldId);
        _removeAliasesFor(identifiedHost, preserve: newId);
        _knownComputers[newId] = _KnownCompanion(
          identifiedHost,
          _now(),
          manuallyPaired: oldEntry?.manuallyPaired ?? true,
        );
        if (_selectionPinned || oldId != null) {
          _selectedComputerChoiceId = newId;
        }
        _host.value = identifiedHost;
        _publishComputerChoices();
      }
      if (_pendingRevision == manifest.revision) {
        _pendingRevision = null;
      }
      _error.value = null;
      _status.value = CompanionSyncStatus.ready;
    } catch (error) {
      if (!_disposed &&
          _selectionEpoch == epoch &&
          _sameDesktopSession(_host.value, host)) {
        _setError('Desktop sync failed: $error');
      }
    } finally {
      client?.close(force: true);
      _fetchingManifest = false;
      final pending = _pendingRevision;
      final pendingHost = _pendingManifestHost;
      final pendingEpoch = _pendingManifestEpoch;
      if (!_disposed &&
          pending != null &&
          pending != _manifest.value?.revision &&
          pendingEpoch == _selectionEpoch &&
          pendingHost != null &&
          _sameDesktopSession(pendingHost, _host.value)) {
        _pendingManifestHost = null;
        _pendingManifestEpoch = null;
        unawaited(refreshManifest());
      }
    }
  }

  @override
  Future<void> executeRemote(RemoteActionRequest request) => _post(
    jsonEncode(request.toJson()),
    surfaceFailure:
        request.kind == RemoteActionKind.launchApplication ||
        request.kind == RemoteActionKind.button,
  );

  @override
  Future<void> sendPointerInputs(List<PointerInput> inputs) async {
    if (_disposed || inputs.isEmpty) return;
    final host = _host.value;
    if (host == null || !host.capabilities.contains('mouse-control-v1')) {
      throw StateError('Selected Desktop does not support mouse control.');
    }
    if (!_sameDesktopSession(_pointerQueueHost, host)) {
      _pointerQueue.clear();
      _pointerClient?.close(force: true);
      _pointerClient = null;
      _pointerQueueHost = host;
    }
    for (final input in inputs) {
      if (input.kind == PointerInputKind.move &&
          _pointerQueue.isNotEmpty &&
          _pointerQueue.last.kind == PointerInputKind.move) {
        final previous = _pointerQueue.removeLast();
        _pointerQueue.add(
          PointerInput.move(
            (previous.x + input.x).clamp(-127, 127),
            (previous.y + input.y).clamp(-127, 127),
          ),
        );
      } else if (_pointerQueue.length < 64) {
        _pointerQueue.add(input);
      }
    }
    if (_pointerFlushTimer == null) {
      _schedulePointerFlush();
    }
  }

  @override
  void discardPendingPointerInputs() {
    _pointerFlushTimer?.cancel();
    _pointerFlushTimer = null;
    _pointerQueue.clear();
    _pointerQueueHost = null;
    _pointerClient?.close(force: true);
    _pointerClient = null;
    _pointerError.value = null;
  }

  void _schedulePointerFlush() {
    _pointerFlushTimer = Timer(const Duration(milliseconds: 16), () {
      _pointerFlushTimer = null;
      unawaited(_flushPointerQueue());
    });
  }

  Future<void> _flushPointerQueue() async {
    if (_pointerQueue.isEmpty || _disposed || _pointerFlushing) return;
    final queuedHost = _pointerQueueHost;
    if (queuedHost == null) return;
    if (!_sameDesktopSession(_host.value, queuedHost) ||
        !_sameDesktopSession(_pointerQueueHost, queuedHost)) {
      _pointerQueue.clear();
      _pointerQueueHost = null;
      return;
    }
    _pointerFlushing = true;
    final batch = _pointerQueue.take(32).toList(growable: false);
    _pointerQueue.removeRange(0, batch.length);
    try {
      if (!_sameDesktopSession(_host.value, queuedHost) || _disposed) return;
      final client = _pointerClient ??= (HttpClient()
        ..connectionTimeout = const Duration(seconds: 3));
      final request = await client
          .post(queuedHost.address, queuedHost.port, '/pointer')
          .timeout(const Duration(seconds: 3));
      if (!_sameDesktopSession(_host.value, queuedHost) || _disposed) return;
      request.followRedirects = false;
      request.headers.contentType = ContentType.json;
      request.headers.set('x-lumiakeys-token', queuedHost.token);
      request.write(
        jsonEncode({'inputs': batch.map((input) => input.toJson()).toList()}),
      );
      final response = await request.close().timeout(
        const Duration(seconds: 3),
      );
      final body = await _readBoundedResponse(
        response,
        const Duration(seconds: 3),
        4096,
      );
      if (!_sameDesktopSession(_host.value, queuedHost) || _disposed) return;
      if (response.statusCode != HttpStatus.ok) throw HttpException(body);
      _pointerError.value = null;
    } catch (error) {
      if (!_disposed &&
          _sameDesktopSession(_host.value, queuedHost) &&
          _sameDesktopSession(_pointerQueueHost, queuedHost)) {
        _pointerError.value = 'Desktop mouse input failed: $error';
      }
    } finally {
      _pointerFlushing = false;
      if (_pointerQueue.isNotEmpty &&
          _pointerFlushTimer == null &&
          _pointerQueueHost != null) {
        _schedulePointerFlush();
      }
    }
  }

  static bool _sameDesktopSession(
    CompanionHost? first,
    CompanionHost? second,
  ) =>
      first != null &&
      second != null &&
      first.address == second.address &&
      first.port == second.port &&
      first.token == second.token &&
      first.platform == second.platform;

  @override
  Future<void> sendDictation({
    required String sessionId,
    required int sequence,
    required String text,
  }) async {
    if (_disposed) {
      throw const CompanionDictationException(
        'LumiaKey Desktop connection is closed.',
      );
    }
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
      if (!_sameDesktopSession(_host.value, host)) {
        throw const CompanionDictationException(
          'Desktop connection changed before dictation delivery completed.',
        );
      }
      if (response.statusCode != HttpStatus.ok) {
        if (response.statusCode == HttpStatus.conflict &&
            _isInputBusyResponse(responseBody)) {
          throw const CompanionInputBusyException(
            'A manual keyboard shortcut is active. The dictated phrase was dropped.',
          );
        }
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

  Future<void> _post(String body, {bool surfaceFailure = false}) async {
    if (_disposed) return;
    final host = _host.value;
    if (host == null) {
      if (surfaceFailure) {
        throw StateError('No LumiaKey Desktop found on this network.');
      }
      _setError('No LumiaKey Desktop found on this network.');
      return;
    }
    final epoch = _selectionEpoch;
    final actionTimeout = surfaceFailure
        ? const Duration(seconds: 8)
        : const Duration(seconds: 4);
    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
      final request = await client
          .post(host.address, host.port, '/action')
          .timeout(actionTimeout);
      request.followRedirects = false;
      request.headers.contentType = ContentType.json;
      request.headers.set('x-lumiakeys-token', host.token);
      request.write(body);
      final response = await request.close().timeout(actionTimeout);
      final responseBody = await _readBoundedResponse(
        response,
        actionTimeout,
        64 * 1024,
      );
      if (_selectionEpoch != epoch || !_sameDesktopSession(_host.value, host)) {
        if (surfaceFailure) {
          throw StateError(
            'Selected Desktop changed while handling the action.',
          );
        }
        return;
      }
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
      if (!_fetchingManifest) _status.value = CompanionSyncStatus.ready;
    } catch (error, stackTrace) {
      if (_selectionEpoch == epoch && _sameDesktopSession(_host.value, host)) {
        if (surfaceFailure) Error.throwWithStackTrace(error, stackTrace);
        _setError('Desktop action failed: $error');
      }
    } finally {
      client?.close(force: true);
    }
  }

  void _setError(String message) {
    _error.value = message;
    _status.value = CompanionSyncStatus.error;
  }

  void _clearPendingManifestRefresh() {
    _pendingRevision = null;
    _pendingManifestHost = null;
    _pendingManifestEpoch = null;
  }

  void _pruneKnownComputers() {
    final cutoff = _now().subtract(hostExpiry);
    _knownComputers.removeWhere(
      (_, entry) => !entry.manuallyPaired && entry.lastSeen.isBefore(cutoff),
    );
    _alternateHosts.removeWhere((id, _) => !_knownComputers.containsKey(id));
    _publishComputerChoices();
  }

  void _publishComputerChoices() {
    final choices =
        _knownComputers.entries
            .map(
              (entry) => CompanionComputerChoice(
                id: entry.key,
                name: entry.value.host.name,
                platform: entry.value.host.platform,
                address: entry.value.host.address,
              ),
            )
            .toList()
          ..sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          );
    _computerChoices.value = List.unmodifiable(choices);
  }

  static String _choiceId(CompanionHost host) => host.computerId != null
      ? 'id:${host.computerId}'
      : base64Url.encode(
          utf8.encode('${host.platform}|${host.address}|${host.port}'),
        );

  static String? _validatedComputerId(Object? value) =>
      value is String && RegExp(r'^[A-Za-z0-9._:-]{1,128}$').hasMatch(value)
      ? value
      : null;

  void _removeAliasesFor(CompanionHost host, {String? preserve}) {
    final aliases = _knownComputers.entries
        .where(
          (entry) =>
              entry.key != preserve &&
              entry.value.host.platform == host.platform &&
              entry.value.host.token == host.token &&
              (entry.value.host.computerId == null ||
                  entry.value.host.computerId == host.computerId),
        )
        .map((entry) => entry.key)
        .toList();
    for (final alias in aliases) {
      final old = _knownComputers.remove(alias)!;
      final selected = _selectedComputerChoiceId == alias;
      _knownComputers[preserve ?? _choiceId(host)] = _KnownCompanion(
        host,
        _now(),
        manuallyPaired: old.manuallyPaired,
      );
      if (selected) _selectedComputerChoiceId = preserve ?? _choiceId(host);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    ++_selectionEpoch;
    _manualConnectionSelected = false;
    _clearPendingManifestRefresh();
    _manualHeartbeat?.cancel();
    _expiryTimer?.cancel();
    _pointerFlushTimer?.cancel();
    _pointerClient?.close(force: true);
    _socket?.close();
    _host.dispose();
    _manifest.dispose();
    _status.dispose();
    _error.dispose();
    _pointerError.dispose();
    _computerChoices.dispose();
  }
}

class _KnownCompanion {
  const _KnownCompanion(
    this.host,
    this.lastSeen, {
    this.manuallyPaired = false,
  });

  final CompanionHost host;
  final DateTime lastSeen;
  final bool manuallyPaired;
}

class RecordingCompanionService
    implements CompanionService, CompanionPointerConnection {
  final ValueNotifier<CompanionHost?> host = ValueNotifier(null);
  final ValueNotifier<DesktopManifest?> syncedManifest = ValueNotifier(null);
  final ValueNotifier<CompanionSyncStatus> status = ValueNotifier(
    CompanionSyncStatus.disconnected,
  );
  final ValueNotifier<String?> errors = ValueNotifier(null);
  final ValueNotifier<String?> pointerErrors = ValueNotifier(null);
  final List<String> commands = [];
  final List<RemoteActionRequest> remoteActions = [];
  final List<PointerInput> pointerInputs = [];
  final List<({String sessionId, int sequence, String text})>
  dictationRequests = [];
  String? dictationError;
  int refreshCount = 0;

  @override
  ValueListenable<String?> get pointerError => pointerErrors;
  @override
  Future<void> sendPointerInputs(List<PointerInput> inputs) async =>
      pointerInputs.addAll(inputs);
  @override
  void discardPendingPointerInputs() {}

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
    pointerErrors.dispose();
  }
}

class CompanionDictationException implements Exception {
  const CompanionDictationException(this.message);
  final String message;

  @override
  String toString() => message;
}

class CompanionInputBusyException extends CompanionDictationException {
  const CompanionInputBusyException(super.message);
}

bool _isInputBusyResponse(String body) {
  try {
    final decoded = jsonDecode(body);
    return decoded is Map &&
        decoded.length == 1 &&
        decoded['error'] == 'input_busy';
  } on FormatException {
    return false;
  }
}
