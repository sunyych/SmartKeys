import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_dictation/local_dictation.dart';

List<int> pcm(int count, int amplitude) {
  final bytes = Uint8List(count * 2);
  for (var i = 0; i < count; i++) {
    final sample = amplitude & 0xffff;
    bytes[i * 2] = sample & 255;
    bytes[i * 2 + 1] = (sample >> 8) & 255;
  }
  return bytes;
}

void main() {
  test('preserves odd byte boundaries and flushes a short utterance', () {
    final segmenter = PcmSpeechSegmenter();
    final voice = pcm(1600, 10000);
    segmenter.addPcm16(voice.sublist(0, 777));
    segmenter.addPcm16(voice.sublist(777));
    final result = segmenter.flush();
    expect(result, hasLength(1));
    expect(result.single.sampleRate, 16000);
    expect(result.single.samples.any((value) => value > 0.2), isTrue);
    expect(result.single.samples.length, lessThanOrEqualTo(16000 * 30));
  });

  test(
    'silence separates phrases and utterances never exceed configured bound',
    () {
      final segmenter = PcmSpeechSegmenter(
        maximumUtteranceDurationMs: 100,
        silenceDurationMs: 60,
        minimumSpeechDurationMs: 20,
        trailingPaddingMs: 0,
      );
      final emitted = <PcmSpeechSegment>[];
      emitted.addAll(segmenter.addPcm16(pcm(16000 * 2 ~/ 2, 12000)));
      emitted.addAll(segmenter.addPcm16(pcm(16000, 0)));
      emitted.addAll(segmenter.flush());
      expect(emitted.length, greaterThan(1));
      expect(emitted.every((segment) => segment.durationMs <= 100), isTrue);
    },
  );

  test('rejects an incomplete trailing PCM sample', () {
    final segmenter = PcmSpeechSegmenter();
    segmenter.addPcm16([1]);
    expect(segmenter.flush, throwsFormatException);
  });
}
