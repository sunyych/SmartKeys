import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_dictation/local_dictation.dart';

const _modelDirEnv = 'LOCAL_DICTATION_MODEL_DIR';
const _zhWavEnv = 'LOCAL_DICTATION_ZH_WAV';
const _enWavEnv = 'LOCAL_DICTATION_EN_WAV';
const _nativeDirEnv = 'LOCAL_DICTATION_NATIVE_DIR';

String? _skipReason() {
  final missing = [
    _modelDirEnv,
    _zhWavEnv,
    _enWavEnv,
    _nativeDirEnv,
  ].where((name) => (Platform.environment[name] ?? '').isEmpty).toList();
  return missing.isEmpty
      ? null
      : 'Set ${missing.join(', ')} to run the real SenseVoice FFI regression; no model or audio fixtures are bundled.';
}

void main() {
  test(
    'SenseVoice language changes match fresh recognizers and worker closes',
    () async {
      final environment = Platform.environment;
      final modelDirectory = Directory(environment[_modelDirEnv]!);
      final modelPath =
          '${modelDirectory.path}${Platform.pathSeparator}model.int8.onnx';
      final tokensPath =
          '${modelDirectory.path}${Platform.pathSeparator}tokens.txt';
      final zh = await _readPcm16Wave(File(environment[_zhWavEnv]!));
      final en = await _readPcm16Wave(File(environment[_enWavEnv]!));
      expect(zh.sampleRate, 16000);
      expect(en.sampleRate, 16000);
      final model = LocalAsrModelFiles(
        model: LocalAsrModel.senseVoice,
        modelPath: modelPath,
        tokensPath: tokensPath,
      );
      final clips = {
        DictationLanguage.chinese: zh.samples,
        DictationLanguage.english: en.samples,
      };
      final sequence = [
        DictationLanguage.chinese,
        DictationLanguage.english,
        DictationLanguage.chinese,
        DictationLanguage.english,
        DictationLanguage.english,
      ];
      final outputs = <DictationLanguage, List<String>>{};
      final worker = await LocalAsrWorker.start(
        model: model,
        language: DictationLanguage.chinese,
        numThreads: 2,
        nativeDirectory: environment[_nativeDirEnv],
      );
      try {
        for (final language in sequence) {
          final text = await worker.transcribe(
            clips[language]!,
            language: language,
          );
          outputs.putIfAbsent(language, () => []).add(text);
          expect(
            text.trim(),
            isNotEmpty,
            reason: '${language.code} returned empty recognition text',
          );
        }
      } finally {
        await worker.dispose(flush: true);
      }

      final references = <DictationLanguage, String>{};
      for (final language in [
        DictationLanguage.english,
        DictationLanguage.chinese,
      ]) {
        final reference = await LocalAsrWorker.start(
          model: model,
          language: language,
          numThreads: 2,
          nativeDirectory: environment[_nativeDirEnv],
        );
        try {
          references[language] = await reference.transcribe(clips[language]!);
        } finally {
          await reference.dispose(flush: true);
        }
      }
      for (final language in [
        DictationLanguage.chinese,
        DictationLanguage.english,
      ]) {
        expect(outputs[language], everyElement(references[language]));
      }
    },
    skip: _skipReason(),
    timeout: const Timeout(Duration(seconds: 90)),
  );
}

Future<_PcmAudio> _readPcm16Wave(File file) async {
  if (!await file.exists()) {
    throw FileSystemException('Missing WAV fixture', file.path);
  }
  final bytes = await file.readAsBytes();
  if (bytes.length < 44 ||
      String.fromCharCodes(bytes.sublist(0, 4)) != 'RIFF' ||
      String.fromCharCodes(bytes.sublist(8, 12)) != 'WAVE') {
    throw FormatException('Expected RIFF/WAVE: ${file.path}');
  }
  final data = ByteData.sublistView(bytes);
  var format = 0, channels = 0, sampleRate = 0, bits = 0;
  var pcmOffset = -1, pcmLength = 0;
  var offset = 12;
  while (offset + 8 <= bytes.length) {
    final chunkName = String.fromCharCodes(bytes.sublist(offset, offset + 4));
    final chunkLength = data.getUint32(offset + 4, Endian.little);
    final chunkStart = offset + 8;
    if (chunkStart + chunkLength > bytes.length) {
      throw const FormatException('Truncated WAV chunk.');
    }
    if (chunkName == 'fmt ' && chunkLength >= 16) {
      format = data.getUint16(chunkStart, Endian.little);
      channels = data.getUint16(chunkStart + 2, Endian.little);
      sampleRate = data.getUint32(chunkStart + 4, Endian.little);
      bits = data.getUint16(chunkStart + 14, Endian.little);
    } else if (chunkName == 'data') {
      pcmOffset = chunkStart;
      pcmLength = chunkLength;
    }
    offset = chunkStart + chunkLength + (chunkLength.isOdd ? 1 : 0);
  }
  if (format != 1 ||
      bits != 16 ||
      channels < 1 ||
      sampleRate < 1 ||
      pcmOffset < 0) {
    throw const FormatException('Expected uncompressed PCM16 WAV audio.');
  }
  final samples = Float32List(pcmLength ~/ (channels * 2));
  for (var frame = 0; frame < samples.length; frame++) {
    var sum = 0.0;
    for (var channel = 0; channel < channels; channel++) {
      sum +=
          data.getInt16(
            pcmOffset + (frame * channels + channel) * 2,
            Endian.little,
          ) /
          32768;
    }
    samples[frame] = sum / channels;
  }
  return _PcmAudio(samples, sampleRate);
}

class _PcmAudio {
  const _PcmAudio(this.samples, this.sampleRate);
  final Float32List samples;
  final int sampleRate;
}
