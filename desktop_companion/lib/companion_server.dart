import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import 'package:lumiakeys_protocol/codex_activity.dart';
import 'package:lumiakeys_protocol/lumiakeys_protocol.dart';

import 'codex_activity.dart';
import 'desktop_controller.dart';
import 'dictation_receiver.dart';

class CompanionServer extends ChangeNotifier {
  CompanionServer({
    required this.controller,
    this.discoveryPort = 45832,
    DictationTextSink? dictationSink,
    CodexActivityMonitor? codexActivity,
  }) : codexActivity = codexActivity ?? CodexActivityMonitor(),
       _hasProvidedDictationSink =
           dictationSink != null &&
           dictationSink is! MethodChannelDictationTextSink,
       dictationSink = dictationSink ?? MethodChannelDictationTextSink();

  final DesktopController controller;
  final CodexActivityMonitor codexActivity;
  final int discoveryPort;
  final DictationTextSink dictationSink;
  final bool _hasProvidedDictationSink;
  bool _pointerReady = false;
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

  String get platform => controller.actions.platformName;

  List<String> get capabilities => [
    'manifest',
    'apps',
    'codex',
    'chatgpt-platform-layout-v1',
    'icons',
    'app-icons-v1',
    'foreground-app',
    'app-activation',
    'launcher-pad-v1',
    codexActivityCapability,
    if (controller.actions.supportsInstalledLauncher) 'installed-launcher-v1',
    if (controller.actions.supportsNativeDictation || _hasProvidedDictationSink)
      'local-dictation-v1',
    if (_pointerReady) 'mouse-control-v1',
  ];

  late final DictationReceiver _dictationReceiver = DictationReceiver(
    token: token,
    sink: dictationSink,
  );

  Future<void> start() async {
    if (_http != null) return;
    unawaited(codexActivity.start());
    try {
      _pointerReady = await controller.actions.probePointerSupport();
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
        'computerId': controller.manifest.computerId,
        'port': http.port,
        'token': token,
        'revision': controller.manifest.revision,
        'capabilities': capabilities,
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
    if (request.method == 'GET' && request.uri.path == codexActivityPath) {
      request.response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
      request.response.write(
        jsonEncode({'status': codexActivity.status?.name}),
      );
      await request.response.close();
      return;
    }
    final iconPath = request.uri.pathSegments;
    if (request.method == 'GET' &&
        iconPath.length == 2 &&
        iconPath[0] == 'icons') {
      final appId = iconPath[1];
      if (!remoteApplicationIconAppIds.contains(appId) &&
          !isInstalledApplicationId(appId)) {
        await _reject(request, HttpStatus.notFound, 'icon not found');
        return;
      }
      final bytes = await controller.applicationIcon(appId);
      if (bytes == null) {
        await _reject(request, HttpStatus.notFound, 'icon not found');
        return;
      }
      final etag = '"${sha256.convert(bytes)}"';
      request.response.headers
        ..set(HttpHeaders.etagHeader, etag)
        ..set(HttpHeaders.cacheControlHeader, 'private, max-age=300')
        ..set(HttpHeaders.varyHeader, 'x-lumiakeys-token')
        ..set('x-content-type-options', 'nosniff');
      final matches =
          request.headers
              .value(HttpHeaders.ifNoneMatchHeader)
              ?.split(',')
              .map((value) => value.trim().replaceFirst(RegExp(r'^W/'), ''))
              .contains(etag) ??
          false;
      if (matches) {
        request.response.statusCode = HttpStatus.notModified;
        await request.response.close();
        return;
      }
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType('image', 'png')
        ..add(bytes);
      await request.response.close();
      return;
    }
    if (request.method == 'GET' && request.uri.path == '/info') {
      request.response.write(
        jsonEncode({
          'name': Platform.localHostname,
          'platform': platform,
          'computerId': controller.manifest.computerId,
          'version': 2,
          'capabilities': capabilities,
          'revision': controller.manifest.revision,
        }),
      );
      await request.response.close();
      return;
    }
    if (request.method == 'POST' && request.uri.path == '/dictation') {
      if (!capabilities.contains('local-dictation-v1')) {
        await _reject(
          request,
          HttpStatus.notImplemented,
          'dictation unsupported on this platform',
        );
        return;
      }
      try {
        await _dictationReceiver.handle(request);
        controller.recordConnectedPhone(
          request.connectionInfo?.remoteAddress.address ?? 'Android phone',
        );
        request.response.write(jsonEncode({'ok': true}));
        notifyListeners();
      } on DictationInputBusyException {
        request.response.statusCode = HttpStatus.conflict;
        request.response.write(jsonEncode({'error': 'input_busy'}));
      } on DictationRequestException catch (caught) {
        request.response.statusCode = caught.statusCode;
        request.response.write(jsonEncode({'error': caught.message}));
      } catch (caught) {
        request.response.statusCode = HttpStatus.conflict;
        request.response.write(jsonEncode({'error': 'insertion_failed'}));
      }
      await request.response.close();
      return;
    }
    if (request.method == 'POST' && request.uri.path == '/pointer') {
      if (!capabilities.contains('mouse-control-v1')) {
        await _reject(
          request,
          HttpStatus.notImplemented,
          'pointer unsupported',
        );
        return;
      }
      try {
        final bytes = BytesBuilder(copy: false);
        await for (final chunk in request.timeout(const Duration(seconds: 3))) {
          if (bytes.length + chunk.length > 16 * 1024) {
            throw const FormatException('pointer request too large');
          }
          bytes.add(chunk);
        }
        final raw = utf8.decode(bytes.takeBytes());
        final decoded = jsonDecode(raw);
        if (decoded is! Map || decoded['inputs'] is! List) {
          throw const FormatException('invalid pointer request');
        }
        final values = decoded['inputs'] as List;
        if (values.isEmpty || values.length > 32) {
          throw const FormatException('invalid pointer batch size');
        }
        final inputs = values
            .map((value) {
              if (value is! Map) {
                throw const FormatException('invalid pointer input');
              }
              return PointerInput.fromJson(
                value.map((key, value) => MapEntry(key.toString(), value)),
              );
            })
            .toList(growable: false);
        await controller.applyPointerInputs(inputs);
        controller.recordConnectedPhone(
          request.connectionInfo?.remoteAddress.address ?? 'Android phone',
        );
        request.response.write(jsonEncode({'ok': true}));
      } catch (caught) {
        request.response.statusCode = HttpStatus.badRequest;
        request.response.write(jsonEncode({'error': '$caught'}));
      }
      await request.response.close();
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
      final actionBytes = BytesBuilder(copy: false);
      await for (final chunk in request.timeout(const Duration(seconds: 3))) {
        if (actionBytes.length + chunk.length > 16 * 1024) {
          request.response.persistentConnection = false;
          await _reject(
            request,
            HttpStatus.requestEntityTooLarge,
            'action too large',
          );
          return;
        }
        actionBytes.add(chunk);
      }
      final raw = utf8.decode(actionBytes.takeBytes());
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
    codexActivity.dispose();
    super.dispose();
  }
}
