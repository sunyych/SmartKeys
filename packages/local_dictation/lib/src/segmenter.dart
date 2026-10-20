import 'dart:math' as math;
import 'dart:typed_data';

class PcmSpeechSegment {
  const PcmSpeechSegment({required this.samples, required this.sampleRate});
  final Float32List samples;
  final int sampleRate;
  int get durationMs => samples.length * 1000 ~/ sampleRate;
}

/// Turns arbitrary PCM16 chunks into bounded, silence-delimited utterances.
/// Silence is detected using RMS; 200 ms of pre-roll and short trailing padding
/// preserve word boundaries. No input is written to disk.
class PcmSpeechSegmenter {
  PcmSpeechSegmenter({
    this.sampleRate = 16000,
    this.frameDurationMs = 20,
    this.silenceDurationMs = 800,
    this.minimumSpeechDurationMs = 40,
    this.maximumUtteranceDurationMs = 30000,
    this.trailingPaddingMs = 120,
    this.voiceRmsThreshold = 0.012,
  }) : _frameSamples = sampleRate * frameDurationMs ~/ 1000,
       _maxSamples = sampleRate * maximumUtteranceDurationMs ~/ 1000,
       _silenceFrames =
           (silenceDurationMs + frameDurationMs - 1) ~/ frameDurationMs,
       _minimumSpeechSamples = sampleRate * minimumSpeechDurationMs ~/ 1000,
       _trailingPaddingSamples = sampleRate * trailingPaddingMs ~/ 1000,
       _preRollFrames = 200 ~/ frameDurationMs {
    if (sampleRate <= 0 ||
        frameDurationMs <= 0 ||
        silenceDurationMs < frameDurationMs ||
        maximumUtteranceDurationMs <= silenceDurationMs ||
        voiceRmsThreshold <= 0) {
      throw ArgumentError('Invalid PCM segmenter configuration.');
    }
  }
  final int sampleRate,
      frameDurationMs,
      silenceDurationMs,
      minimumSpeechDurationMs;
  final int maximumUtteranceDurationMs, trailingPaddingMs;
  final double voiceRmsThreshold;
  final int _frameSamples, _maxSamples, _silenceFrames, _minimumSpeechSamples;
  final int _trailingPaddingSamples, _preRollFrames;
  int? _odd;
  final List<double> _frame = [], _utterance = [];
  final List<List<double>> _preRoll = [];
  int _speechSamples = 0, _voiceEnd = 0, _silentFrames = 0;
  bool _active = false;

  List<PcmSpeechSegment> addPcm16(List<int> bytes) {
    final out = <PcmSpeechSegment>[];
    var i = 0;
    if (_odd != null && bytes.isNotEmpty) {
      _frame.add(_sample(_odd!, bytes[0]));
      _odd = null;
      i = 1;
    }
    while (i + 1 < bytes.length) {
      _frame.add(_sample(bytes[i], bytes[i + 1]));
      i += 2;
    }
    if (i < bytes.length) _odd = bytes[i];
    while (_frame.length >= _frameSamples) {
      out.addAll(_process(_frame.sublist(0, _frameSamples)));
      _frame.removeRange(0, _frameSamples);
    }
    return out;
  }

  List<PcmSpeechSegment> flush() {
    if (_odd != null) {
      _odd = null;
      throw const FormatException(
        'Audio ended with an incomplete PCM16 sample.',
      );
    }
    final out = <PcmSpeechSegment>[];
    if (_frame.isNotEmpty) {
      out.addAll(_process(List.of(_frame)));
      _frame.clear();
    }
    final tail = _finish();
    if (tail != null) out.add(tail);
    return out;
  }

  void reset() {
    _odd = null;
    _frame.clear();
    _utterance.clear();
    _preRoll.clear();
    _speechSamples = 0;
    _voiceEnd = 0;
    _silentFrames = 0;
    _active = false;
  }

  List<PcmSpeechSegment> _process(List<double> frame) {
    final out = <PcmSpeechSegment>[];
    if (_rms(frame) >= voiceRmsThreshold) {
      if (!_active) {
        _active = true;
        _utterance.clear();
        for (final f in _preRoll) {
          _utterance.addAll(f);
        }
        _preRoll.clear();
        _speechSamples = 0;
      }
      _silentFrames = 0;
      _utterance.addAll(frame);
      _speechSamples += frame.length;
      _voiceEnd = _utterance.length;
    } else if (_active) {
      _silentFrames++;
      _utterance.addAll(frame);
      if (_silentFrames >= _silenceFrames) {
        final value = _finish();
        if (value != null) out.add(value);
        return out;
      }
    } else {
      _preRoll.add(List.of(frame));
      if (_preRoll.length > _preRollFrames) _preRoll.removeAt(0);
      return out;
    }
    while (_active && _utterance.length >= _maxSamples) {
      final head = _utterance.sublist(0, _maxSamples),
          spill = _utterance.sublist(_maxSamples);
      final end = _voiceEnd.clamp(0, head.length);
      final value = _make(head, end);
      if (value != null) out.add(value);
      _utterance
        ..clear()
        ..addAll(spill);
      _speechSamples = _rms(spill) >= voiceRmsThreshold ? spill.length : 0;
      _active = _speechSamples > 0;
      _voiceEnd = _active ? spill.length : 0;
      _silentFrames = 0;
    }
    return out;
  }

  PcmSpeechSegment? _finish() {
    final value = _make(_utterance, _voiceEnd);
    _utterance.clear();
    _speechSamples = 0;
    _voiceEnd = 0;
    _silentFrames = 0;
    _active = false;
    return value;
  }

  PcmSpeechSegment? _make(List<double> samples, int end) {
    if (_speechSamples < _minimumSpeechSamples || end == 0) return null;
    final finish = (end + _trailingPaddingSamples).clamp(1, samples.length);
    return PcmSpeechSegment(
      samples: Float32List.fromList(samples.sublist(0, finish)),
      sampleRate: sampleRate,
    );
  }

  static double _sample(int lo, int hi) {
    final unsigned = (lo & 255) | ((hi & 255) << 8);
    return (unsigned >= 32768 ? unsigned - 65536 : unsigned) / 32768;
  }

  static double _rms(List<double> data) {
    if (data.isEmpty) return 0;
    var sum = 0.0;
    for (final v in data) {
      sum += v * v;
    }
    return math.sqrt(sum / data.length);
  }
}
