import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumiakeys_protocol/lumiakeys_protocol.dart';
import 'package:lumiakeys_companion/companion_server.dart';
import 'package:lumiakeys_companion/desktop_controller.dart';
import 'package:lumiakeys_companion/dictation_receiver.dart';

class _NoopDiscovery implements ApplicationDiscovery {
  @override
  Future<List<RemoteApplication>> refresh(List<RemoteApplication> apps) async =>
      apps;
}

class _Sink implements DictationTextSink {
  final texts = <String>[];
  bool fail = false;
  bool busy = false;
  Completer<void>? gate;

  @override
  Future<void> insertText(String text) async {
    if (gate != null) await gate!.future;
    if (busy) {
      throw const DictationInputBusyException('modifier_key_held');
    }
    if (fail) throw StateError('rejected');
    texts.add(text);
  }
}

void main() {
  late CompanionServer server;
  late _Sink sink;
  late HttpClient client;

  setUp(() async {
    sink = _Sink();
    final controller = DesktopController(
      store: MemoryDesktopConfigStore(),
      discovery: _NoopDiscovery(),
    );
    await controller.initialize();
    server = CompanionServer(controller: controller, dictationSink: sink);
    await server.start();
    client = HttpClient();
  });

  tearDown(() {
    client.close(force: true);
    server.dispose();
  });

  Future<HttpClientResponse> post(Object body, {String? token}) async {
    final request = await client.post(
      InternetAddress.loopbackIPv4.address,
      server.actionPort!,
      '/dictation',
    );
    request.headers.contentType = ContentType.json;
    if (token != null) request.headers.set('x-lumiakeys-token', token);
    request.write(body is String ? body : jsonEncode(body));
    return request.close();
  }

  Map<String, Object> payload({String text = '你好 👋', int sequence = 1}) => {
    'sessionId': 'session-1',
    'sequence': sequence,
    'text': text,
  };

  test('authenticates requests and advertises receiver capability', () async {
    expect(server.capabilities, contains('local-dictation-v1'));
    final discovery = HttpClient();
    final req = await discovery.get(
      InternetAddress.loopbackIPv4.address,
      server.actionPort!,
      '/manifest',
    );
    req.headers.set('x-lumiakeys-token', server.token);
    final response = await req.close();
    expect(response.statusCode, HttpStatus.ok);
    await response.drain<void>();

    final rejected = await post(payload());
    expect(rejected.statusCode, HttpStatus.forbidden);
    await rejected.drain<void>();
    discovery.close(force: true);
  });

  test(
    'accepts one complete insertion and acknowledges duplicate without reinserting',
    () async {
      final first = await post(payload(), token: server.token);
      expect(first.statusCode, HttpStatus.ok);
      expect(jsonDecode(await first.transform(utf8.decoder).join()), {
        'ok': true,
      });
      final duplicate = await post(payload(), token: server.token);
      expect(duplicate.statusCode, HttpStatus.ok);
      await duplicate.drain<void>();
      expect(sink.texts, ['你好 👋']);
    },
  );

  test(
    'preserves accented and multilingual text exactly at the sink',
    () async {
      const transcript = 'Ça va — café e\u0301; 東京; Ελληνικά; مرحبا';
      final response = await post(
        payload(text: transcript),
        token: server.token,
      );

      expect(response.statusCode, HttpStatus.ok);
      await response.drain<void>();
      expect(sink.texts, [transcript]);
    },
  );

  test(
    'input busy is reported once and never replays the tombstoned phrase',
    () async {
      sink.busy = true;
      final busy = await post(payload(sequence: 8), token: server.token);
      expect(busy.statusCode, HttpStatus.conflict);
      expect(jsonDecode(await busy.transform(utf8.decoder).join()), {
        'error': 'input_busy',
      });

      final duplicate = await post(payload(sequence: 8), token: server.token);
      expect(duplicate.statusCode, HttpStatus.conflict);
      expect(jsonDecode(await duplicate.transform(utf8.decoder).join()), {
        'error': 'previous_insertion_failed',
      });
      expect(sink.texts, isEmpty);

      sink.busy = false;
      final next = await post(
        payload(sequence: 9, text: '下一个短语'),
        token: server.token,
      );
      expect(next.statusCode, HttpStatus.ok);
      await next.drain<void>();
      expect(sink.texts, ['下一个短语']);
    },
  );

  test(
    'rejects malformed, oversized, control-bearing and oversized text',
    () async {
      final invalid = await post('{', token: server.token);
      expect(invalid.statusCode, HttpStatus.badRequest);
      await invalid.drain<void>();
      final control = await post(
        payload(text: 'safe\nenter'),
        token: server.token,
      );
      expect(control.statusCode, HttpStatus.badRequest);
      await control.drain<void>();
      final tooLong = await post(
        payload(text: 'a' * 8001),
        token: server.token,
      );
      expect(tooLong.statusCode, HttpStatus.badRequest);
      await tooLong.drain<void>();
      final oversized = await post({
        'sessionId': 's',
        'sequence': 0,
        'text': 'a' * 70000,
      }, token: server.token);
      expect(oversized.statusCode, HttpStatus.requestEntityTooLarge);
      await oversized.drain<void>();
      expect(sink.texts, isEmpty);
    },
  );

  test(
    'serializes concurrent delivery and never acknowledges sink failure',
    () async {
      sink.gate = Completer<void>();
      final firstFuture = post(payload(sequence: 1), token: server.token);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final secondFuture = post(payload(sequence: 2), token: server.token);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(sink.texts, isEmpty);
      sink.gate!.complete();
      final first = await firstFuture;
      final second = await secondFuture;
      expect(first.statusCode, HttpStatus.ok);
      expect(second.statusCode, HttpStatus.ok);
      expect(sink.texts, ['你好 👋', '你好 👋']);

      sink.fail = true;
      final failed = await post(payload(sequence: 3), token: server.token);
      expect(failed.statusCode, HttpStatus.conflict);
      await failed.drain<void>();
      final failedDuplicate = await post(
        payload(sequence: 3),
        token: server.token,
      );
      expect(failedDuplicate.statusCode, HttpStatus.conflict);
      await failedDuplicate.drain<void>();
      final conflict = await post(
        payload(text: 'different', sequence: 1),
        token: server.token,
      );
      expect(conflict.statusCode, HttpStatus.conflict);
      await conflict.drain<void>();
      expect(sink.texts, hasLength(2));
    },
  );
}
