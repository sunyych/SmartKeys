import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import 'model.dart';

abstract interface class DictationRecognizer {
  Future<String> transcribe(Float32List samples, {DictationLanguage? language});
  Future<void> dispose({bool flush = true});
}

final _nativeLibraries = <DynamicLibrary>[];

/// Owns sherpa handles on a worker isolate. Samples are mono 16 kHz float PCM.
class LocalAsrWorker implements DictationRecognizer {
  LocalAsrWorker._(
    this._isolate,
    this._commands,
    this._events,
    this._errors,
    this._exits,
    this._subscription,
    this._failureSubscriptions,
  ) : _language = DictationLanguage.chinese;
  static const _startupTimeout = Duration(minutes: 2);
  final Isolate _isolate;
  final SendPort _commands;
  final ReceivePort _events, _errors, _exits;
  final StreamSubscription<Object?> _subscription;
  final List<StreamSubscription<Object?>> _failureSubscriptions;
  final Map<int, Completer<String>> _pending = {};
  DictationLanguage _language;
  int _id = 0;
  bool _disposed = false, _portsClosed = false;
  Object? _terminalError;
  Completer<void>? _closing;
  Timer? _shutdownTimer;

  static Future<DictationRecognizer> start({
    required LocalAsrModelFiles model,
    required DictationLanguage language,
    int numThreads = 2,
    String? nativeDirectory,
  }) async {
    final ready = Completer<SendPort>();
    final events = ReceivePort(), errors = ReceivePort(), exits = ReceivePort();
    late Isolate isolate;
    try {
      isolate = await Isolate.spawn<Map<String, Object?>>(
        _worker,
        {
          'owner': events.sendPort,
          'model': model.model.index,
          'modelPath': model.modelPath,
          'tokensPath': model.tokensPath,
          'encoderPath': model.encoderPath ?? '',
          'decoderPath': model.decoderPath ?? '',
          'language': language.code,
          'numThreads': numThreads,
          'nativeDirectory': nativeDirectory ?? '',
        },
        onError: errors.sendPort,
        onExit: exits.sendPort,
        errorsAreFatal: true,
      );
    } catch (_) {
      events.close();
      errors.close();
      exits.close();
      rethrow;
    }
    LocalAsrWorker? worker;
    final eventSub = events.listen((Object? message) {
      if (message is! Map) return;
      if (message['type'] == 'ready' && message['port'] is SendPort) {
        if (!ready.isCompleted) ready.complete(message['port'] as SendPort);
      } else if (message['type'] == 'startupError' && !ready.isCompleted) {
        ready.completeError(StateError(message['error'].toString()));
      } else if (ready.isCompleted) {
        worker?._onMessage(message);
      }
    });
    final errorSub = errors.listen((Object? value) {
      final message = value is List && value.length > 1 ? value[1] : value;
      final error = StateError('ASR worker failed: $message');
      if (!ready.isCompleted) ready.completeError(error);
      worker?._fail(error);
    });
    final exitSub = exits.listen((_) {
      if (!ready.isCompleted) {
        ready.completeError(
          StateError('ASR worker exited during initialization'),
        );
      }
      final active = worker;
      if (active == null) return;
      if (!active._disposed) {
        active._terminalError ??= StateError('ASR worker exited unexpectedly');
      }
      final closing = active._closing;
      if (closing != null && !closing.isCompleted) {
        if (active._terminalError == null) {
          closing.complete();
        } else {
          closing.completeError(active._terminalError!);
        }
      }
      active._disposed = true;
      unawaited(active._closePorts());
    });
    try {
      final port = await ready.future.timeout(_startupTimeout);
      worker = LocalAsrWorker._(
        isolate,
        port,
        events,
        errors,
        exits,
        eventSub,
        [errorSub, exitSub],
      ).._language = language;
      return worker;
    } catch (_) {
      isolate.kill(priority: Isolate.immediate);
      await eventSub.cancel();
      await errorSub.cancel();
      await exitSub.cancel();
      events.close();
      errors.close();
      exits.close();
      rethrow;
    }
  }

  @override
  Future<String> transcribe(
    Float32List samples, {
    DictationLanguage? language,
  }) {
    if (_disposed) return Future.error(StateError('ASR worker is disposed.'));
    if (_terminalError != null) return Future.error(_terminalError!);
    if (samples.isEmpty) return Future.value('');
    final id = _id++, result = Completer<String>();
    final selected = language ?? _language;
    _pending[id] = result;
    _commands.send({
      'type': 'transcribe',
      'id': id,
      'samples': samples,
      'language': selected.code,
    });
    return result.future;
  }

  @override
  Future<void> dispose({bool flush = true}) async {
    if (_closing != null) return _closing!.future;
    if (_disposed) return;
    _disposed = true;
    final closing = _closing = Completer<void>();
    if (!flush) {
      final error = StateError('ASR worker disposed.');
      for (final result in _pending.values) {
        if (!result.isCompleted) result.completeError(error);
      }
      _pending.clear();
    }
    _commands.send({'type': 'close'});
    _shutdownTimer = Timer(const Duration(seconds: 30), () {
      if (!closing.isCompleted) {
        _isolate.kill(priority: Isolate.immediate);
        _fail(TimeoutException('ASR worker did not stop.'));
      }
    });
    try {
      await closing.future;
    } finally {
      _shutdownTimer?.cancel();
      await _closePorts();
    }
  }

  void _onMessage(Map message) {
    if (message['type'] == 'closed') {
      final closing = _closing;
      if (closing != null && !closing.isCompleted) {
        _shutdownTimer?.cancel();
        closing.complete();
      }
      return;
    }
    final id = message['id'];
    if (id is! int) return;
    final completer = _pending.remove(id);
    if (completer == null || completer.isCompleted) return;
    if (message['type'] == 'error') {
      completer.completeError(StateError(message['error'].toString()));
    } else {
      completer.complete(message['text']?.toString() ?? '');
    }
  }

  void _fail(Object error) {
    _terminalError ??= error;
    for (final result in _pending.values) {
      if (!result.isCompleted) result.completeError(error);
    }
    _pending.clear();
    if (_closing case final c? when !c.isCompleted) c.completeError(error);
  }

  Future<void> _closePorts() async {
    if (_portsClosed) return;
    _portsClosed = true;
    _shutdownTimer?.cancel();
    await _subscription.cancel();
    for (final sub in _failureSubscriptions) {
      await sub.cancel();
    }
    _events.close();
    _errors.close();
    _exits.close();
  }
}

void _worker(Map<String, Object?> config) {
  final owner = config['owner']! as SendPort;
  final messages = ReceivePort();
  final kind = LocalAsrModel.values[config['model']! as int];
  final language = config['language']! as String;
  var currentLanguage = '';
  sherpa.OfflineRecognizer? recognizer;
  try {
    final nativeDir = config['nativeDirectory']! as String;
    if (Platform.isWindows && nativeDir.isNotEmpty) {
      _nativeLibraries.add(DynamicLibrary.open('$nativeDir\\onnxruntime.dll'));
      sherpa.initBindings(nativeDir);
    } else {
      sherpa.initBindings();
    }
    recognizer = _createRecognizer(config, kind, language);
    currentLanguage = language;
    owner.send({'type': 'ready', 'port': messages.sendPort});
  } catch (error, stack) {
    owner.send({'type': 'startupError', 'error': '$error\n$stack'});
    messages.close();
    recognizer?.free();
    return;
  }
  messages.listen((Object? message) {
    if (message is! Map) return;
    if (message['type'] == 'close') {
      recognizer?.free();
      recognizer = null;
      owner.send({'type': 'closed'});
      messages.close();
      return;
    }
    if (message['type'] != 'transcribe') return;
    final id = message['id']! as int;
    final audio = message['samples']! as Float32List;
    final requested = message['language']! as String;
    sherpa.OfflineStream? stream;
    try {
      if (kind == LocalAsrModel.senseVoice && currentLanguage != requested) {
        // SenseVoice stores language in its recognizer config: free before
        // recreating to avoid two large model allocations in memory.
        recognizer?.free();
        recognizer = null;
        currentLanguage = '';
        final replacement = _createRecognizer(config, kind, requested);
        recognizer = replacement;
        currentLanguage = requested;
      }
      stream = recognizer!.createStream();
      if (kind == LocalAsrModel.cohere) {
        stream.setOption(key: 'language', value: requested);
      }
      stream.acceptWaveform(samples: audio, sampleRate: 16000);
      recognizer!.decode(stream);
      owner.send({
        'type': 'result',
        'id': id,
        'text': recognizer!.getResult(stream).text.trim(),
      });
    } catch (error, stack) {
      owner.send({'type': 'error', 'id': id, 'error': '$error\n$stack'});
    } finally {
      stream?.free();
    }
  });
}

sherpa.OfflineRecognizer _createRecognizer(
  Map<String, Object?> c,
  LocalAsrModel kind,
  String language,
) {
  final model = sherpa.OfflineModelConfig(
    senseVoice: kind == LocalAsrModel.senseVoice
        ? sherpa.OfflineSenseVoiceModelConfig(
            model: c['modelPath']! as String,
            language: language,
            useInverseTextNormalization: true,
          )
        : const sherpa.OfflineSenseVoiceModelConfig(),
    cohereTranscribe: kind == LocalAsrModel.cohere
        ? sherpa.OfflineCohereTranscribeModelConfig(
            encoder: c['encoderPath']! as String,
            decoder: c['decoderPath']! as String,
          )
        : const sherpa.OfflineCohereTranscribeModelConfig(),
    tokens: c['tokensPath']! as String,
    numThreads: c['numThreads']! as int,
    debug: false,
    provider: 'cpu',
  );
  return sherpa.OfflineRecognizer(sherpa.OfflineRecognizerConfig(model: model));
}
