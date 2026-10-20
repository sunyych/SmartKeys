/// Recognition language is independent from the app's display locale.
enum DictationLanguage { chinese, english }

extension DictationLanguageInfo on DictationLanguage {
  String get code => switch (this) {
    DictationLanguage.chinese => 'zh',
    DictationLanguage.english => 'en',
  };
  String get label => switch (this) {
    DictationLanguage.chinese => '中文',
    DictationLanguage.english => 'English',
  };
}

enum LocalAsrModel { senseVoice, cohere }

extension LocalAsrModelInfo on LocalAsrModel {
  String get label => switch (this) {
    LocalAsrModel.senseVoice => 'SenseVoice Small',
    LocalAsrModel.cohere => 'Cohere Transcribe',
  };
}

const defaultLocalAsrModel = LocalAsrModel.senseVoice;

class LocalAsrModelFiles {
  const LocalAsrModelFiles({
    required this.model,
    required this.modelPath,
    required this.tokensPath,
    this.encoderPath,
    this.decoderPath,
  });
  final LocalAsrModel model;
  final String modelPath;
  final String tokensPath;
  final String? encoderPath;
  final String? decoderPath;
}

class ModelDownloadProgress {
  const ModelDownloadProgress({
    required this.model,
    required this.fileName,
    required this.bytesReceived,
    required this.totalBytes,
  });
  final LocalAsrModel model;
  final String fileName;
  final int bytesReceived;
  final int totalBytes;
  double get fraction => totalBytes == 0 ? 0 : bytesReceived / totalBytes;
}

class LocalAsrFile {
  const LocalAsrFile({
    required this.name,
    required this.sizeBytes,
    required this.sha256,
  });
  final String name;
  final int sizeBytes;
  final String sha256;
}

/// Immutable upstream identity and checksums copied from mobile_transcribe.
class LocalAsrModelDescriptor {
  const LocalAsrModelDescriptor({
    required this.model,
    required this.directory,
    required this.repository,
    required this.revision,
    required this.files,
    required this.primaryModelFile,
    this.encoderFile,
    this.decoderFile,
  });
  final LocalAsrModel model;
  final String directory;
  final String repository;
  final String revision;
  final List<LocalAsrFile> files;
  final String primaryModelFile;
  final String? encoderFile;
  final String? decoderFile;
  Uri urlFor(LocalAsrFile file) => Uri.https(
    'huggingface.co',
    '/$repository/resolve/$revision/${file.name}',
  );

  static const senseVoice = LocalAsrModelDescriptor(
    model: LocalAsrModel.senseVoice,
    directory: 'sensevoice-zh-en-ja-ko-yue-int8',
    repository: 'csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17',
    revision: '2365baeacb507f821a0c8120fcee3d484dba7a07',
    primaryModelFile: 'model.int8.onnx',
    files: [
      LocalAsrFile(
        name: 'model.int8.onnx',
        sizeBytes: 239233841,
        sha256:
            'c71f0ce00bec95b07744e116345e33d8cbbe08cef896382cf907bf4b51a2cd51',
      ),
      LocalAsrFile(
        name: 'tokens.txt',
        sizeBytes: 315894,
        sha256:
            'f449eb28dc567533d7fa59be34e2abca8784f771850c78a47fb731a31429a1dc',
      ),
    ],
  );
  static const cohere = LocalAsrModelDescriptor(
    model: LocalAsrModel.cohere,
    directory: 'sherpa-onnx-cohere-transcribe-14-lang-int8-2026-04-01',
    repository:
        'csukuangfj2/sherpa-onnx-cohere-transcribe-14-lang-int8-2026-04-01',
    revision: '156a470cf08eefe706a0004f3c52d9ee567ca7a0',
    primaryModelFile: 'encoder.int8.onnx',
    encoderFile: 'encoder.int8.onnx',
    decoderFile: 'decoder.int8.onnx',
    files: [
      LocalAsrFile(
        name: 'encoder.int8.onnx',
        sizeBytes: 3090822,
        sha256:
            'cf704f8cfa90e3f0a76f9ffc05998bdf00ba9ae983192c14a85a3a5eb008b367',
      ),
      LocalAsrFile(
        name: 'encoder.int8.onnx.data',
        sizeBytes: 2731503072,
        sha256:
            'bcf1b7148c8518ae52df1ad2d2fc2b4e89261ea23e6c874eef1d9f55bcbaa4a3',
      ),
      LocalAsrFile(
        name: 'decoder.int8.onnx',
        sizeBytes: 153250705,
        sha256:
            '8372ca6c8ff4db8b916ca3592f5c757a715e691b9edec751ba19b29fc854baf9',
      ),
      LocalAsrFile(
        name: 'tokens.txt',
        sizeBytes: 207437,
        sha256:
            '013ede043ae2480e3a9205cc34550d9686100cc682bacc90f702facdfbb93035',
      ),
    ],
  );
  static LocalAsrModelDescriptor forModel(LocalAsrModel model) =>
      switch (model) {
        LocalAsrModel.senseVoice => senseVoice,
        LocalAsrModel.cohere => cohere,
      };
}
