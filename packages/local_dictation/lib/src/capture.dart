import 'package:record/record.dart';

abstract interface class DictationCapture {
  Future<bool> hasPermission();
  Future<Stream<List<int>>> start();
  Future<void> stop();
  Future<void> dispose();
}

/// Mono 16 kHz PCM16 capture; audio is exposed only as a stream in memory.
class RecordDictationCapture implements DictationCapture {
  RecordDictationCapture({AudioRecorder? recorder})
    : _recorder = recorder ?? AudioRecorder();
  final AudioRecorder _recorder;
  @override
  Future<bool> hasPermission() => _recorder.hasPermission();
  @override
  Future<Stream<List<int>>> start() => _recorder.startStream(
    const RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: 16000,
      numChannels: 1,
      autoGain: true,
      echoCancel: true,
      noiseSuppress: true,
    ),
  );
  @override
  Future<void> stop() async {
    await _recorder.stop();
  }

  @override
  Future<void> dispose() => _recorder.dispose();
}
