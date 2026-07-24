import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:lumiakeys_protocol/lumiakeys_protocol.dart';

import 'desktop_controller.dart';

class CompanionServer extends ChangeNotifier {
  CompanionServer({required this.controller, this.discoveryPort = 45832});

  final DesktopController controller;
  final int discoveryPort;
  final String token = List.generate(
    32,
    (_) => Random.secure().nextInt(16).toRadixString(16),
  ).join();
  HttpServer? _http;
  RawDatagramSocket? _udp;
  Timer? _broadcastTimer;
  bool running = false;
  String? error;

  int? get actionPort => _http?.port;
  String? get lastPhone => controller.connectedPhone;

  String get platform => Platform.isMacOS
      ? 'macos'
      : Platform.isWindows
      ? 'windows'
      : 'linux';

  Future<void> start() async {
    if (_http != null) return;
    try {
      _http = await HttpServer.bind(InternetAddress.anyIPv4, 0);
      _http!.listen(_handleRequest);
      _udp = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      _udp!.broadcastEnabled = true;
      _broadcastTimer = Timer.periodic(
        const Duration(seconds: 2),
        (_) => _broadcast(),
      );
      _broadcast();
      running = true;
      error = null;
    } catch (caught) {
      error = '$caught';
    }
    notifyListeners();
  }

  void broadcastNow() => _broadcast();

  void _broadcast() {
    final http = _http;
    final udp = _udp;
    if (http == null || udp == null) return;
    final message = utf8.encode(
      jsonEncode({
        'service': 'lumiakeys-companion',
        'version': 2,
        'name': Platform.localHostname,
        'platform': platform,
        'port': http.port,
        'token': token,
        'revision': controller.manifest.revision,
        'capabilities': [
          'manifest',
          'apps',
          'codex',
          'icons',
          'foreground-app',
        ],
      }),
    );
    udp.send(message, InternetAddress('255.255.255.255'), discoveryPort);
  }

  Future<void> _handleRequest(HttpRequest request) async {
    request.response.headers.contentType = ContentType.json;
    if (request.headers.value('x-lumiakeys-token') != token) {
      await _reject(request, HttpStatus.forbidden, 'forbidden');
      return;
    }
    if (request.method == 'GET' && request.uri.path == '/manifest') {
      request.response.write(
        jsonEncode(controller.manifest.toJson(forSync: true)),
      );
      controller.recordConnectedPhone(
        request.connectionInfo?.remoteAddress.address ?? 'Android phone',
      );
      await request.response.close();
      notifyListeners();
      return;
    }
    if (request.method != 'POST' || request.uri.path != '/action') {
      await _reject(request, HttpStatus.notFound, 'not found');
      return;
    }
    try {
      final raw = await utf8.decoder.bind(request).join();
      final decoded = jsonDecode(raw);
      if (decoded is! Map) throw const FormatException('invalid action');
      final action = decoded.map(
        (key, value) => MapEntry(key.toString(), value as Object?),
      );
      final kind = action['kind']?.toString();
      if (RemoteActionKind.values.any((value) => value.name == kind)) {
        await controller.executeRemote(RemoteActionRequest.fromJson(action));
      } else {
        await controller.executeLegacy(action);
      }
      controller.recordConnectedPhone(
        request.connectionInfo?.remoteAddress.address ?? 'Android phone',
      );
      request.response.write(
        jsonEncode({'ok': true, 'revision': controller.manifest.revision}),
      );
      notifyListeners();
    } catch (caught) {
      request.response.statusCode = HttpStatus.badRequest;
      request.response.write(jsonEncode({'error': '$caught'}));
    }
    await request.response.close();
  }

  Future<void> _reject(
    HttpRequest request,
    int statusCode,
    String message,
  ) async {
    request.response.statusCode = statusCode;
    request.response.write(jsonEncode({'error': message}));
    await request.response.close();
  }

  @override
  void dispose() {
    _broadcastTimer?.cancel();
    _udp?.close();
    unawaited(_http?.close(force: true));
    super.dispose();
  }
}
