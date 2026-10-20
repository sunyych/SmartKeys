import 'dart:async';

import 'package:flutter/foundation.dart';

import 'capture.dart';
import 'model.dart';
import 'model_manager.dart';
import 'segmenter.dart';
import 'worker.dart';

typedef DictationRecognizerFactory =
    Future<DictationRecognizer> Function(
      LocalAsrModelFiles model,
      DictationLanguage language,
    );
typedef DictationTextOutput = Future<void> Function(String text);

/// Foreground capture, bounded PCM segmentation and serial local recognition.
/// Final phrases are delivered once to [onText]; failures are surfaced and
/// never queued for replay.
class LocalDictationController extends ChangeNotifier {
  LocalDictationController({
    required this.modelManager,
    required this.capture,
    required this.recognizerFactory,
    required this.onText,
    this.model = LocalAsrModel.senseVoice,
    this.language = DictationLanguage.chinese,
    this.maxQueuedSegments = 8,
    this.maxQueuedSamples = 960000,
    this.decodeTimeout = const Duration(seconds: 60),
  }) {
    if (maxQueuedSegments < 1 || maxQueuedSamples < 16000) {
      throw ArgumentError(
        'Queue limits must allow at least one second of PCM.',
      );
    }
  }
  final ModelManager modelManager;
  final DictationCapture capture;
  final DictationRecognizerFactory recognizerFactory;
  final DictationTextOutput onText;
  final int maxQueuedSegments, maxQueuedSamples;
  final Duration decodeTimeout;
  LocalAsrModel model;
  DictationLanguage language;
  final PcmSpeechSegmenter _segmenter = PcmSpeechSegmenter();
  DictationRecognizer? _recognizer;
  StreamSubscription<List<int>>? _audioSub;
  Future<void> _tail = Future<void>.value();
  int _queuedSegments = 0, _queuedSamples = 0, _generation = 0;
  bool _listening = false, _busy = false, _disposed = false, _closing = false;
  Future<void>? _closeFuture, _stopFuture;
  Future<void>? _startFuture;
  String? _error;
  String _lastText = '';

  bool get listening => _listening;
  bool get busy => _busy;
  String? get error => _error;
  String get lastText => _lastText;
  int get queuedSamples => _queuedSamples;

  Future<void> configure({
    LocalAsrModel? model,
    DictationLanguage? language,
  }) async {
    if (_disposed || _closing) {
      throw StateError('Dictation controller is closed.');
    }
    if (_startFuture != null) {
      ++_generation;
      await _startFuture!.catchError((_) {});
    }
    if (_listening) await cancel();
    await _tail;
    final nextModel = model ?? this.model;
    final nextLanguage = language ?? this.language;
    if (nextModel == this.model && nextLanguage == this.language) return;
    final old = _recognizer;
    _recognizer = null;
    this.model = nextModel;
    this.language = nextLanguage;
    _error = null;
    _notify();
    await old?.dispose(flush: true);
  }

  /// Releases native handles before a cached model is removed from disk.
  Future<void> releaseRecognizer() async {
    if (_listening || _busy || _queuedSegments != 0) {
      throw StateError(
        'Stop dictation and wait for pending recognition before releasing the model.',
      );
    }
    final recognizer = _recognizer;
    _recognizer = null;
    await recognizer?.dispose(flush: true);
  }

  Future<void> deleteModel(LocalAsrModel target) async {
    if (target == model) await releaseRecognizer();
    await modelManager.deleteModel(target);
  }

  /// Starts capture using only an already-installed model. This method never
  /// downloads a model implicitly.
  Future<void> start() {
    if (_disposed || _closing) {
      throw StateError('Dictation controller is closed.');
    }
    if (_listening || _busy) return Future<void>.value();
    _busy = true;
    _error = null;
    _lastText = '';
    final startGeneration = ++_generation;
    _notify();
    final starting = _start(startGeneration);
    _startFuture = starting;
    return starting.whenComplete(() {
      if (identical(_startFuture, starting)) _startFuture = null;
    });
  }

  Future<void> _start(int startGeneration) async {
    try {
      if (!await capture.hasPermission()) {
        throw StateError('Microphone permission was not granted.');
      }
      final files = await modelManager.installedModel(model);
      if (startGeneration != _generation || _closing) return;
      var recognizer = _recognizer;
      if (recognizer == null) {
        recognizer = await recognizerFactory(files, language);
        if (startGeneration != _generation || _closing) {
          await recognizer.dispose(flush: false);
          return;
        }
        _recognizer = recognizer;
      }
      _segmenter.reset();
      final stream = await capture.start();
      if (startGeneration != _generation || _closing) {
        await capture.stop();
        return;
      }
      _audioSub = stream.listen(
        _onAudio,
        onError: (Object e, StackTrace _) {
          _error = 'Microphone capture failed: $e';
          _notify();
          unawaited(cancel());
        },
        onDone: () {
          if (_listening && !_closing) {
            _error = 'Microphone stream ended.';
            _notify();
            unawaited(stop());
          }
        },
      );
      _listening = true;
    } catch (e) {
      if (startGeneration == _generation && !_closing) _error = e.toString();
      rethrow;
    } finally {
      _busy = false;
      _notify();
    }
  }

  Future<void> stop() {
    if (_stopFuture != null) return _stopFuture!;
    if (_startFuture != null) {
      ++_generation;
      return _stopFuture = _startFuture!
          .catchError((_) {})
          .whenComplete(() {
            if (_listening) return _stop(flush: true);
          })
          .whenComplete(() => _stopFuture = null);
    }
    if (!_listening) return Future<void>.value();
    return _stopFuture = _stop(
      flush: true,
    ).whenComplete(() => _stopFuture = null);
  }

  Future<void> _stop({required bool flush}) async {
    _busy = true;
    _notify();
    Object? captureError;
    try {
      try {
        await capture.stop();
      } catch (error) {
        captureError = error;
      }
      try {
        await _audioSub?.cancel();
      } finally {
        _audioSub = null;
      }
      _listening = false;
      if (flush) {
        for (final segment in _segmenter.flush()) {
          _enqueue(segment, _generation);
        }
      } else {
        _segmenter.reset();
      }
      await _tail.timeout(decodeTimeout);
      if (captureError != null) throw captureError;
    } catch (e) {
      _error = 'Could not finish dictation: $e';
      rethrow;
    } finally {
      _listening = false;
      _busy = false;
      _notify();
    }
  }

  /// Cancels the current generation, releasing resources and dropping all
  /// unprocessed utterances. Any decode already in native code cannot deliver.
  Future<void> cancel() async {
    ++_generation;
    final starting = _startFuture;
    if (starting != null) await starting.catchError((_) {});
    if (_listening) {
      try {
        await capture.stop();
      } finally {
        await _audioSub?.cancel();
        _audioSub = null;
        _listening = false;
      }
    }
    _segmenter.reset();
    _busy = false;
    _notify();
  }

  void _onAudio(List<int> bytes) {
    if (!_listening || _closing || _disposed) return;
    try {
      for (final segment in _segmenter.addPcm16(bytes)) {
        _enqueue(segment, _generation);
      }
    } catch (e) {
      _error = 'Invalid microphone PCM data: $e';
      _notify();
      unawaited(cancel());
    }
  }

  void _enqueue(PcmSpeechSegment segment, int generation) {
    if (_queuedSegments >= maxQueuedSegments ||
        _queuedSamples + segment.samples.length > maxQueuedSamples) {
      _error = 'Recognition queue is full; stop and try a shorter phrase.';
      _notify();
      if (_listening) unawaited(cancel());
      return;
    }
    _queuedSegments++;
    _queuedSamples += segment.samples.length;
    _notify();
    _tail = _tail.then((_) async {
      try {
        await _decode(segment.samples, generation);
      } finally {
        _queuedSegments--;
        _queuedSamples -= segment.samples.length;
        _notify();
      }
    });
  }

  Future<void> _decode(Float32List samples, int generation) async {
    if (generation != _generation || _disposed || _closing) return;
    final recognizer = _recognizer;
    if (recognizer == null) {
      _error = 'Recognizer is unavailable.';
      return;
    }
    try {
      final text =
          (await recognizer
                  .transcribe(samples, language: language)
                  .timeout(decodeTimeout))
              .trim();
      if (generation != _generation ||
          _disposed ||
          _closing ||
          !_meaningful(text)) {
        return;
      }
      _lastText = text;
      _error = null;
      _notify();
      try {
        await onText(text);
      } catch (e) {
        if (generation == _generation) _error = 'Text delivery failed: $e';
      }
    } catch (e) {
      if (generation == _generation && !_closing) {
        _error = 'Local recognition failed: $e';
      }
      // Catch each phrase here: one failure must not poison later phrases.
    }
  }

  static bool _meaningful(String value) =>
      RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(value);

  Future<void> close() {
    if (_closeFuture != null) return _closeFuture!;
    _closing = true;
    _disposed = true;
    ++_generation;
    return _closeFuture = _close();
  }

  Future<void> _close() async {
    try {
      final starting = _startFuture;
      if (starting != null) await starting.catchError((_) {});
      if (_listening) await _stop(flush: false);
      await _audioSub?.cancel();
      _audioSub = null;
      await _tail.timeout(decodeTimeout).catchError((_) {});
    } finally {
      try {
        await capture.dispose();
      } catch (e) {
        _error ??= 'Microphone cleanup failed: $e';
      }
      try {
        await _recognizer?.dispose(flush: true);
      } catch (e) {
        _error ??= 'Recognizer cleanup failed: $e';
      }
      _recognizer = null;
      _listening = false;
      _busy = false;
    }
  }

  @override
  void dispose() {
    unawaited(close());
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }
}
