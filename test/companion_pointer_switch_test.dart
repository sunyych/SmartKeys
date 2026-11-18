import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumiakeys_protocol/lumiakeys_protocol.dart';
import 'package:smart_keys/services/companion_service.dart';

void main() {
  test(
    'switching away from an in-flight mouse request immediately delivers to the new host',
    () async {
      final gate = Completer<void>();
      final first = await _PointerPeer.start('first', gate: gate);
      final second = await _PointerPeer.start('second');
      final service = LanCompanionService(enableDiscovery: false);
      addTearDown(() async {
        service.dispose();
        if (!gate.isCompleted) gate.complete();
        await first.close();
        await second.close();
      });
      await service.connectManually(first.code);
      await service.sendPointerInputs([const PointerInput.move(10, 20)]);
      await first.received.future.timeout(const Duration(seconds: 3));
      await service.sendPointerInputs([const PointerInput.move(30, 40)]);
      service.discardPendingPointerInputs();
      await service.connectManually(second.code);
      await service.sendPointerInputs([
        const PointerInput.move(50, 60),
        const PointerInput.button(secondary: false),
        const PointerInput.scroll(2),
      ]);
      await second.received.future.timeout(const Duration(seconds: 2));
      expect(first.inputs, hasLength(1));
      expect(second.inputs.map((input) => input['kind']), [
        'move',
        'button',
        'scroll',
      ]);
      expect(second.inputs.first['x'], 50);
      expect(service.pointerError.value, isNull);
    },
  );
}

class _PointerPeer {
  _PointerPeer(this.server, this.id, this.gate);
  final HttpServer server;
  final String id;
  final Completer<void>? gate;
  late StreamSubscription<HttpRequest> subscription;
  final received = Completer<void>();
  final inputs = <Map<String, dynamic>>[];
  String get code =>
      '127.0.0.1:${server.port} 0123456789abcdef0123456789abcdef';
  static Future<_PointerPeer> start(String id, {Completer<void>? gate}) async {
    final peer = _PointerPeer(
      await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
      id,
      gate,
    );
    peer.subscription = peer.server.listen(peer.handle);
    return peer;
  }

  Future<void> handle(HttpRequest request) async {
    try {
      request.response.headers.contentType = ContentType.json;
      expect(
        request.headers.value('x-lumiakeys-token'),
        '0123456789abcdef0123456789abcdef',
      );
      switch (request.uri.path) {
        case '/info':
          request.response.write(
            jsonEncode({
              'name': id,
              'computerId': id,
              'platform': 'windows',
              'version': 2,
              'revision': 1,
              'capabilities': ['manifest', 'mouse-control-v1'],
            }),
          );
        case '/manifest':
          request.response.write(
            jsonEncode(
              DesktopManifest.starter()
                  .copyWith(computerId: id, revision: 1)
                  .toJson(forSync: true),
            ),
          );
        case '/pointer':
          final body =
              jsonDecode(await utf8.decoder.bind(request).join())
                  as Map<String, dynamic>;
          inputs.addAll((body['inputs'] as List).cast<Map<String, dynamic>>());
          if (!received.isCompleted) received.complete();
          if (gate != null) await gate!.future;
          request.response.write('{}');
        default:
          request.response.statusCode = 404;
      }
      await request.response.close();
    } on HttpException catch (_) {
      // Switching hosts intentionally aborts the previous connection.
    } on SocketException catch (_) {
      // Switching hosts intentionally aborts the previous connection.
    }
  }

  Future<void> close() async {
    await subscription.cancel();
    await server.close(force: true);
  }
}
