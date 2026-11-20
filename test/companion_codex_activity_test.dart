import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumiakeys_protocol/codex_activity.dart';
import 'package:lumiakeys_protocol/lumiakeys_protocol.dart';
import 'package:smart_keys/services/companion_service.dart';

class _DesktopPeer {
  _DesktopPeer({
    required this.server,
    required this.status,
    required this.supportsActivity,
    this.heldResponse,
  }) {
    server.listen(_handleRequest);
  }

  static const token = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  final HttpServer server;
  final String status;
  final bool supportsActivity;
  final Completer<void>? heldResponse;
  final requested = Completer<void>();
  int statusRequests = 0;

  String get code => '127.0.0.1:${server.port} $token';

  Future<void> _handleRequest(HttpRequest request) async {
    if (request.headers.value('x-lumiakeys-token') != token) {
      request.response.statusCode = HttpStatus.forbidden;
      await request.response.close();
      return;
    }
    request.response.headers.contentType = ContentType.json;
    switch (request.uri.path) {
      case '/info':
        request.response.write(
          jsonEncode({
            'name': 'Test Desktop',
            'platform': 'windows',
            'version': 2,
            'revision': 1,
            'capabilities': [
              'manifest',
              if (supportsActivity) codexActivityCapability,
            ],
          }),
        );
      case '/manifest':
        request.response.write(
          jsonEncode(
            DesktopManifest.starter()
                .copyWith(revision: 1)
                .toJson(forSync: true),
          ),
        );
      case codexActivityPath:
        statusRequests++;
        if (!requested.isCompleted) requested.complete();
        await heldResponse?.future;
        request.response.write(jsonEncode({'status': status}));
      default:
        request.response.statusCode = HttpStatus.notFound;
    }
    await request.response.close();
  }
}

Future<_DesktopPeer> _peer({
  required String status,
  bool supportsActivity = true,
  Completer<void>? heldResponse,
}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  addTearDown(() => server.close(force: true));
  return _DesktopPeer(
    server: server,
    status: status,
    supportsActivity: supportsActivity,
    heldResponse: heldResponse,
  );
}

Future<void> _waitFor(
  LanCompanionService service,
  CodexActivityStatus status,
) async {
  if (service.codexActivity.value == status) return;
  final completer = Completer<void>();
  void changed() {
    if (service.codexActivity.value == status && !completer.isCompleted) {
      completer.complete();
    }
  }

  service.codexActivity.addListener(changed);
  try {
    await completer.future.timeout(const Duration(seconds: 4));
  } finally {
    service.codexActivity.removeListener(changed);
  }
}

void main() {
  test('switching paired hosts rejects any late old status response', () async {
    final held = Completer<void>();
    final first = await _peer(status: 'error', heldResponse: held);
    final second = await _peer(status: 'thinking');
    final service = LanCompanionService(enableDiscovery: false);
    addTearDown(service.dispose);

    await service.connectManually(first.code);
    await first.requested.future.timeout(const Duration(seconds: 4));
    expect(service.codexActivity.value, isNull);
    await service.connectManually(second.code);
    await _waitFor(service, CodexActivityStatus.thinking);
    held.complete();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(service.codexActivity.value, CodexActivityStatus.thinking);
    await service.disconnect();
    expect(service.codexActivity.value, isNull);
  });

  test('older paired desktops receive no activity requests', () async {
    final old = await _peer(status: 'needsInput', supportsActivity: false);
    final service = LanCompanionService(
      enableDiscovery: false,
      expiryPollInterval: const Duration(milliseconds: 30),
    );
    addTearDown(service.dispose);

    await service.connectManually(old.code);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(service.syncStatus.value, CompanionSyncStatus.ready);
    expect(service.codexActivity.value, isNull);
    expect(old.statusRequests, 0);
  });
}
