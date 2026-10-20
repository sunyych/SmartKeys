import 'dart:io';
import 'dart:typed_data';

import 'package:local_dictation/src/model.dart';
import 'package:local_dictation/src/worker.dart';

/// Optional real-model regression. Inputs are supplied by the caller so model
/// and speech fixtures remain outside the repository.
Future<void> main(List<String> arguments) async {
  if (arguments.length < 3 || arguments.length > 4) {
    stderr.writeln(
      'Usage: dart run tool/local_asr_worker_smoke.dart <model-directory> <zh-wav-file> <en-wav-file> [sherpa-native-directory]',
    );
    exitCode = 64;
    return;
  }
  final modelDirectory = Directory(arguments[0]);
  final modelPath =
      '${modelDirectory.path}${Platform.pathSeparator}model.int8.onnx';
  final tokensPath =
      '${modelDirectory.path}${Platform.pathSeparator}tokens.txt';
  final zhFile = File(arguments[1]), enFile = File(arguments[2]);
  for (final file in [File(modelPath), File(tokensPath), zhFile, enFile]) {
    if (!await file.exists()) {
      stderr.writeln('Missing input file: ${file.path}');
      exitCode = 66;
      return;
    }
  }
  final zh = await _readPcm16Wave(zhFile), en = await _readPcm16Wave(enFile);
  if (zh.sampleRate != 16000 || en.sampleRate != 16000) {
    stderr.writeln('Expected both WAV files to use 16000 Hz PCM.');
    exitCode = 65;
    return;
  }
  final nativeDirectory = arguments.length == 4 ? arguments[3] : null;
  final model = LocalAsrModelFiles(
    model: LocalAsrModel.senseVoice,
    modelPath: modelPath,
    tokensPath: tokensPath,
  );
  final sequence = [
    DictationLanguage.chinese,
    DictationLanguage.english,
    DictationLanguage.chinese,
    DictationLanguage.english,
    DictationLanguage.english,
  ];
  final clips = {
    DictationLanguage.chinese: zh.samples,
    DictationLanguage.english: en.samples,
  };
  final outputs = <DictationLanguage, List<String>>{};
  final worker = await LocalAsrWorker.start(
    model: model,
    language: DictationLanguage.chinese,
    numThreads: 2,
    nativeDirectory: nativeDirectory,
  );
  try {
    for (final language in sequence) {
      final text = await worker.transcribe(
        clips[language]!,
        language: language,
      );
      outputs.putIfAbsent(language, () => []).add(text);
      stdout.writeln('${language.code}: $text');
      if (text.trim().isEmpty) exitCode = 1;
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
      nativeDirectory: nativeDirectory,
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
    final actual = outputs[language]!;
    if (actual.any((text) => text != references[language])) {
      stderr.writeln(
        '${language.code} switched output differs from a fresh recognizer: switched=$actual fresh=${references[language]}',
      );
      exitCode = 1;
    }
  }
}

Future<_PcmAudio> _readPcm16Wave(File file) async {
  final bytes = await file.readAsBytes();
  if (bytes.length < 44 ||
      String.fromCharCodes(bytes.sublist(0, 4)) != 'RIFF' ||
      String.fromCharCodes(bytes.sublist(8, 12)) != 'WAVE') {
    throw FormatException('Expected RIFF/WAVE: ${file.path}');
  }
  final data = ByteData.sublistView(bytes);
  var format = 0,
      channels = 0,
      sampleRate = 0,
      bits = 0,
      pcmOffset = -1,
      pcmLength = 0;
  var offset = 12;
  while (offset + 8 <= bytes.length) {
    final name = String.fromCharCodes(bytes.sublist(offset, offset + 4));
    final length = data.getUint32(offset + 4, Endian.little),
        start = offset + 8;
    if (start + length > bytes.length) {
      throw const FormatException('Truncated WAV chunk.');
    }
    if (name == 'fmt ' && length >= 16) {
      format = data.getUint16(start, Endian.little);
      channels = data.getUint16(start + 2, Endian.little);
      sampleRate = data.getUint32(start + 4, Endian.little);
      bits = data.getUint16(start + 14, Endian.little);
    } else if (name == 'data') {
      pcmOffset = start;
      pcmLength = length;
    }
    offset = start + length + (length.isOdd ? 1 : 0);
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
