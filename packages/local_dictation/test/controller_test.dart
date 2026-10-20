import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_dictation/local_dictation.dart';

class FakeCapture implements DictationCapture {
  final Completer<Stream<List<int>>>? delayedStream;
  FakeCapture({this.delayedStream});
  final StreamController<List<int>> controller =
      StreamController<List<int>>.broadcast(sync: true);
  bool permission = true;
  Completer<void>? stopGate;
  int startCalls = 0, stopCalls = 0, disposeCalls = 0;
  @override
  Future<bool> hasPermission() async => permission;
  @override
  Future<Stream<List<int>>> start() {
    startCalls++;
    return delayedStream?.future ?? Future.value(controller.stream);
  }

  @override
  Future<void> stop() async {
    stopCalls++;
    await stopGate?.future;
  }

  @override
  Future<void> dispose() async {
    disposeCalls++;
    await controller.close();
  }

  void add(List<int> bytes) => controller.add(bytes);
}

class FakeRecognizer implements DictationRecognizer {
  FakeRecognizer(this.next);
  final Future<String> Function(
    Float32List samples,
    DictationLanguage? language,
  )
  next;
  final List<DictationLanguage?> languages = [];
  int disposeCalls = 0;
  @override
  Future<String> transcribe(
    Float32List samples, {
    DictationLanguage? language,
  }) {
    languages.add(language);
    return next(samples, language);
  }

  @override
  Future<void> dispose({bool flush = true}) async {
    disposeCalls++;
  }
}

List<int> pcm(int count, int amplitude) {
  final out = Uint8List(count * 2);
  for (var i = 0; i < count; i++) {
    final s = amplitude & 0xffff;
    out[i * 2] = s & 255;
    out[i * 2 + 1] = (s >> 8) & 255;
  }
  return out;
}

Future<void> settle() async {
  await Future<void>.delayed(const Duration(milliseconds: 1));
}

void main() {
  late Directory temp;
  late ModelManager manager;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('local-dictation-controller-');
    final data = utf8.encode('controller fixture');
    final descriptor = LocalAsrModelDescriptor(
      model: LocalAsrModel.senseVoice,
      directory: 'fixture',
      repository: 'local/test',
      revision: 'pinned',
      primaryModelFile: 'model.onnx',
      files: [
        LocalAsrFile(
          name: 'model.onnx',
          sizeBytes: data.length,
          sha256: sha256.convert(data).toString(),
        ),
      ],
    );
    manager = ModelManager(
      modelRootProvider: () async => Directory('${temp.path}/models'),
      descriptorResolver: (_) => descriptor,
    );
    final source = Directory('${temp.path}/models/fixture')
      ..createSync(recursive: true);
    await File('${source.path}/model.onnx').writeAsBytes(data);
    await manager.installedModel(LocalAsrModel.senseVoice);
  });
  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test(
    'audio level is throttled normalized RMS across odd PCM chunks',
    () async {
      final capture = FakeCapture();
      final controller = LocalDictationController(
        modelManager: manager,
        capture: capture,
        recognizerFactory: (_, _) async => FakeRecognizer((_, _) async => ''),
        onText: (_) async {},
      );
      await controller.start();

      final quiet = pcm(4, 1600);
      capture.add([quiet[0]]);
      await Future<void>.delayed(const Duration(milliseconds: 45));
      expect(controller.audioLevel.value, 0);

      capture.add(quiet.sublist(1, 3));
      expect(controller.audioLevel.value, closeTo(1600 / 32768, 0.000001));
      capture.add(const <int>[]);
      capture.add(quiet.sublist(3));
      capture.add(pcm(4, 24000));
      expect(controller.audioLevel.value, closeTo(1600 / 32768, 0.000001));

      await Future<void>.delayed(const Duration(milliseconds: 45));
      capture.add(pcm(4, -24000));
      expect(controller.audioLevel.value, closeTo(24000 / 32768, 0.000001));

      await Future<void>.delayed(const Duration(milliseconds: 45));
      capture.add(pcm(4, 0));
      expect(controller.audioLevel.value, 0);
      await controller.close();
    },
  );

  test('audio level resets on stop, cancel, capture error and close', () async {
    final capture = FakeCapture();
    final controller = LocalDictationController(
      modelManager: manager,
      capture: capture,
      recognizerFactory: (_, _) async => FakeRecognizer((_, _) async => ''),
      onText: (_) async {},
    );

    await controller.start();
    await Future<void>.delayed(const Duration(milliseconds: 45));
    capture.add(pcm(4, 22000));
    expect(controller.audioLevel.value, greaterThan(0));
    await controller.stop();
    expect(controller.audioLevel.value, 0);

    await controller.start();
    await Future<void>.delayed(const Duration(milliseconds: 45));
    capture.add(pcm(4, 22000));
    expect(controller.audioLevel.value, greaterThan(0));
    await controller.cancel();
    expect(controller.audioLevel.value, 0);

    await controller.start();
    await Future<void>.delayed(const Duration(milliseconds: 45));
    capture.add(pcm(4, 22000));
    expect(controller.audioLevel.value, greaterThan(0));
    final updates = <double>[];
    controller.audioLevel.addListener(() {
      updates.add(controller.audioLevel.value);
    });
    capture.controller.addError(StateError('device disconnected'));
    for (var i = 0; i < 20 && controller.listening; i++) {
      await settle();
    }
    expect(controller.listening, isFalse);
    expect(controller.error, contains('device disconnected'));
    expect(controller.audioLevel.value, 0);

    await controller.start();
    await Future<void>.delayed(const Duration(milliseconds: 45));
    capture.add(pcm(4, 22000));
    expect(controller.audioLevel.value, greaterThan(0));
    await controller.close();
    expect(controller.audioLevel.value, 0);
    final updatesAfterClose = updates.length;
    expect(() => controller.start(), throwsStateError);
    expect(updates, hasLength(updatesAfterClose));
  });

  test(
    'late PCM cannot restore the meter while stop or cancel is pending',
    () async {
      final capture = FakeCapture();
      final controller = LocalDictationController(
        modelManager: manager,
        capture: capture,
        recognizerFactory: (_, _) async => FakeRecognizer((_, _) async => ''),
        onText: (_) async {},
      );

      await controller.start();
      await Future<void>.delayed(const Duration(milliseconds: 45));
      capture.add(pcm(4, 22000));
      expect(controller.audioLevel.value, greaterThan(0));

      final stopGate = Completer<void>();
      capture.stopGate = stopGate;
      final stopping = controller.stop();
      expect(controller.audioLevel.value, 0);
      await Future<void>.delayed(const Duration(milliseconds: 45));
      capture.add(pcm(4, 24000));
      expect(controller.audioLevel.value, 0);
      stopGate.complete();
      await stopping;

      capture.stopGate = null;
      await controller.start();
      await Future<void>.delayed(const Duration(milliseconds: 45));
      capture.add(pcm(4, 22000));
      expect(controller.audioLevel.value, greaterThan(0));

      final cancelGate = Completer<void>();
      capture.stopGate = cancelGate;
      final cancelling = controller.cancel();
      expect(controller.audioLevel.value, 0);
      await Future<void>.delayed(const Duration(milliseconds: 45));
      capture.add(pcm(4, 24000));
      expect(controller.audioLevel.value, 0);
      cancelGate.complete();
      await cancelling;
      await controller.close();
    },
  );

  test('start failure leaves audio level at zero', () async {
    final capture = FakeCapture()..permission = false;
    final controller = LocalDictationController(
      modelManager: manager,
      capture: capture,
      recognizerFactory: (_, _) async => FakeRecognizer((_, _) async => ''),
      onText: (_) async {},
    );

    await expectLater(controller.start(), throwsStateError);
    expect(controller.audioLevel.value, 0);
    expect(capture.startCalls, 0);
    await controller.close();
  });

  test('dispose resets the meter and prevents later notifications', () async {
    final capture = FakeCapture();
    final controller = LocalDictationController(
      modelManager: manager,
      capture: capture,
      recognizerFactory: (_, _) async => FakeRecognizer((_, _) async => ''),
      onText: (_) async {},
    );
    final updates = <double>[];
    controller.audioLevel.addListener(() {
      updates.add(controller.audioLevel.value);
    });

    await controller.start();
    await Future<void>.delayed(const Duration(milliseconds: 45));
    capture.add(pcm(4, 22000));
    expect(controller.audioLevel.value, greaterThan(0));
    controller.dispose();
    expect(controller.audioLevel.value, 0);
    await controller.close();
    final updatesAfterDispose = updates.length;
    await Future<void>.delayed(const Duration(milliseconds: 45));
    expect(updates, hasLength(updatesAfterDispose));
  });

  test(
    'stop flushes the current phrase and capture remains stoppable while decoding',
    () async {
      final capture = FakeCapture();
      final decoder = Completer<String>();
      final recognizer = FakeRecognizer((_, _) => decoder.future);
      final delivered = <String>[];
      final controller = LocalDictationController(
        modelManager: manager,
        capture: capture,
        recognizerFactory: (_, _) async => recognizer,
        onText: (text) async => delivered.add(text),
      );
      await controller.start();
      capture.add(pcm(3200, 12000));
      final stopping = controller.stop();
      expect(controller.busy, isTrue);
      expect(controller.listening, isTrue);
      expect(capture.stopCalls, 1);
      decoder.complete('recognized phrase');
      await stopping;
      expect(delivered, ['recognized phrase']);
      expect(controller.lastText, 'recognized phrase');
      await controller.close();
    },
  );

  test(
    'delivery failure for one phrase does not poison a later phrase or replay',
    () async {
      final capture = FakeCapture();
      var decoded = 0;
      final recognizer = FakeRecognizer((_, _) async => 'phrase ${++decoded}');
      final attempted = <String>[];
      final controller = LocalDictationController(
        modelManager: manager,
        capture: capture,
        recognizerFactory: (_, _) async => recognizer,
        onText: (text) async {
          attempted.add(text);
          if (attempted.length == 1) throw StateError('sink unavailable');
        },
      );
      await controller.start();
      capture.add([
        ...pcm(1600, 12000),
        ...pcm(16000, 0),
        ...pcm(1600, 12000),
        ...pcm(16000, 0),
      ]);
      await controller.stop();
      expect(attempted, ['phrase 1', 'phrase 2']);
      expect(controller.error, isNull);
      await controller.close();
    },
  );

  test('cancel invalidates in-flight recognition output', () async {
    final capture = FakeCapture();
    final decoded = Completer<String>();
    final recognizer = FakeRecognizer((_, _) => decoded.future);
    var deliveries = 0;
    final controller = LocalDictationController(
      modelManager: manager,
      capture: capture,
      recognizerFactory: (_, _) async => recognizer,
      onText: (_) async => deliveries++,
    );
    await controller.start();
    capture.add([...pcm(1600, 12000), ...pcm(16000, 0)]);
    for (var i = 0; i < 20 && recognizer.languages.isEmpty; i++) {
      await settle();
    }
    expect(recognizer.languages, hasLength(1));
    await controller.cancel();
    decoded.complete('must be discarded');
    await settle();
    expect(deliveries, 0);
    await controller.close();
  });

  test(
    'configure invalidates delayed recognizer initialization and disposes it',
    () async {
      final capture = FakeCapture();
      final ready = Completer<DictationRecognizer>();
      final requested = Completer<void>();
      final recognizer = FakeRecognizer((_, _) async => 'unexpected');
      final controller = LocalDictationController(
        modelManager: manager,
        capture: capture,
        recognizerFactory: (_, _) {
          requested.complete();
          return ready.future;
        },
        onText: (_) async {},
      );
      final starting = controller.start();
      await requested.future;
      final configuring = controller.configure(
        language: DictationLanguage.english,
      );
      ready.complete(recognizer);
      await configuring;
      await starting;
      expect(controller.language, DictationLanguage.english);
      expect(recognizer.disposeCalls, 1);
      expect(capture.startCalls, 0);
      expect(controller.listening, isFalse);
      await controller.close();
    },
  );

  test(
    'stop during delayed capture start waits then closes mic without listening',
    () async {
      final pending = Completer<Stream<List<int>>>();
      final capture = FakeCapture(delayedStream: pending);
      final controller = LocalDictationController(
        modelManager: manager,
        capture: capture,
        recognizerFactory: (_, _) async => FakeRecognizer((_, _) async => ''),
        onText: (_) async {},
      );
      final starting = controller.start();
      while (capture.startCalls == 0) {
        await settle();
      }
      final stopping = controller.stop();
      pending.complete(capture.controller.stream);
      await Future.wait([starting, stopping]);
      expect(capture.stopCalls, 1);
      expect(controller.listening, isFalse);
      await controller.close();
    },
  );

  test(
    'close waits for a pending capture start and disposes both resources',
    () async {
      final pending = Completer<Stream<List<int>>>();
      final capture = FakeCapture(delayedStream: pending);
      final recognizer = FakeRecognizer((_, _) async => '');
      final controller = LocalDictationController(
        modelManager: manager,
        capture: capture,
        recognizerFactory: (_, _) async => recognizer,
        onText: (_) async {},
      );
      final starting = controller.start();
      while (capture.startCalls == 0) {
        await settle();
      }
      final closing = controller.close();
      pending.complete(capture.controller.stream);
      await Future.wait([starting, closing]);
      expect(capture.stopCalls, 1);
      expect(capture.disposeCalls, 1);
      expect(recognizer.disposeCalls, 1);
    },
  );

  test('permission and missing-model failures never start capture', () async {
    final capture = FakeCapture()..permission = false;
    final controller = LocalDictationController(
      modelManager: manager,
      capture: capture,
      recognizerFactory: (_, _) async => FakeRecognizer((_, _) async => ''),
      onText: (_) async {},
    );
    await expectLater(controller.start(), throwsStateError);
    expect(capture.startCalls, 0);
    expect(controller.error, contains('permission'));
    await controller.close();
  });

  test('capture stream failure stops capture and is surfaced', () async {
    final capture = FakeCapture();
    final recognizer = FakeRecognizer((_, _) async => 'unused');
    final controller = LocalDictationController(
      modelManager: manager,
      capture: capture,
      recognizerFactory: (_, _) async => recognizer,
      onText: (_) async {},
    );
    await controller.start();
    capture.controller.addError(StateError('device disconnected'));
    await settle();
    expect(controller.listening, isFalse);
    expect(controller.error, contains('device disconnected'));
    expect(capture.stopCalls, 1);
    await controller.close();
  });

  test(
    'recognition queue enforces segment limit and cancels old session output',
    () async {
      final capture = FakeCapture();
      final decode = Completer<String>();
      final recognizer = FakeRecognizer((_, _) => decode.future);
      final controller = LocalDictationController(
        modelManager: manager,
        capture: capture,
        recognizerFactory: (_, _) async => recognizer,
        onText: (_) async {},
        maxQueuedSegments: 1,
        maxQueuedSamples: 16000 * 30,
      );
      await controller.start();
      final phrase = [...pcm(1600, 12000), ...pcm(16000, 0)];
      capture.add(phrase);
      for (var i = 0; i < 20 && recognizer.languages.isEmpty; i++) {
        await settle();
      }
      expect(recognizer.languages, hasLength(1));
      capture.add(phrase);
      await settle();
      expect(controller.error, contains('queue is full'));
      expect(controller.listening, isFalse);
      decode.complete('cancelled phrase');
      await controller.close();
    },
  );
}
