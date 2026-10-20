import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:local_dictation/local_dictation.dart';

void main() {
  late Directory temp;
  late List<int> payload;
  late LocalAsrModelDescriptor descriptor;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('local-dictation-test-');
    payload = utf8.encode('deterministic model fixture');
    descriptor = LocalAsrModelDescriptor(
      model: LocalAsrModel.senseVoice,
      directory: 'fixture-model',
      repository: 'fixture/model',
      revision: 'fixed-revision',
      primaryModelFile: 'tiny.onnx',
      files: [
        LocalAsrFile(
          name: 'tiny.onnx',
          sizeBytes: payload.length,
          sha256: sha256.convert(payload).toString(),
        ),
      ],
    );
  });
  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  ModelManager manager({http.Client Function()? client}) => ModelManager(
    modelRootProvider: () async => Directory('${temp.path}/managed'),
    descriptorResolver: (_) => descriptor,
    urlResolver: (_, _) => Uri.https('fixture.invalid', '/tiny.onnx'),
    clientFactory: client,
  );

  test(
    'downloads only into a partial file, verifies hash, reports progress and reuses cache',
    () async {
      var requests = 0;
      final updates = <ModelDownloadProgress>[];
      final result = await manager(
        client: () => MockClient((request) async {
          requests++;
          expect(request.url.host, 'fixture.invalid');
          return http.Response.bytes(payload, 200);
        }),
      ).prepareModel(LocalAsrModel.senseVoice, onProgress: updates.add);
      expect(requests, 1);
      expect(updates.single.bytesReceived, payload.length);
      expect(updates.single.fraction, 1);
      expect(await manager().areModelsAvailable(), isTrue);
      expect(
        (await manager().installedModel(LocalAsrModel.senseVoice)).modelPath,
        result.modelPath,
      );
      await manager(
        client: () => MockClient((_) async {
          fail('verified cache should be reused');
        }),
      ).prepareModel(LocalAsrModel.senseVoice);
    },
  );

  test('rejects corrupt content and removes incomplete download', () async {
    final bad = utf8.encode('wrong bytes');
    final instance = manager(
      client: () => MockClient((_) async => http.Response.bytes(bad, 200)),
    );
    await expectLater(
      instance.prepareModel(LocalAsrModel.senseVoice),
      throwsA(isA<HttpException>()),
    );
    expect(await instance.areModelsAvailable(), isFalse);
    final files = Directory('${temp.path}/managed/fixture-model');
    expect(await files.list().toList(), isEmpty);
  });

  test(
    'replaces a corrupt cache only after a verified download completes',
    () async {
      final corrupt = Directory('${temp.path}/managed/fixture-model')
        ..createSync(recursive: true);
      await File('${corrupt.path}/tiny.onnx').writeAsString('corrupt');
      final instance = manager(
        client: () =>
            MockClient((_) async => http.Response.bytes(payload, 200)),
      );
      expect(await instance.areModelsAvailable(), isFalse);
      final repaired = await instance.prepareModel(LocalAsrModel.senseVoice);
      expect(await File(repaired.modelPath).readAsBytes(), payload);
      expect(await instance.areModelsAvailable(), isTrue);
    },
  );

  test(
    'cancellation discards partial data and never marks model installed',
    () async {
      final instance = manager(
        client: () =>
            MockClient((_) async => http.Response.bytes(payload, 200)),
      );
      await expectLater(
        instance.prepareModel(
          LocalAsrModel.senseVoice,
          onProgress: (_) => instance.cancelDownload(),
        ),
        throwsStateError,
      );
      expect(await instance.areModelsAvailable(), isFalse);
      expect(
        await Directory('${temp.path}/managed/fixture-model').list().toList(),
        isEmpty,
      );
    },
  );

  test(
    'rejects model descriptors that escape the managed cache root',
    () async {
      final unsafe = ModelManager(
        modelRootProvider: () async => Directory('${temp.path}/managed'),
        descriptorResolver: (_) => LocalAsrModelDescriptor(
          model: LocalAsrModel.senseVoice,
          directory: '..',
          repository: 'fixture/model',
          revision: 'fixed-revision',
          primaryModelFile: 'tiny.onnx',
          files: [
            LocalAsrFile(
              name: 'tiny.onnx',
              sizeBytes: payload.length,
              sha256: sha256.convert(payload).toString(),
            ),
          ],
        ),
      );
      expect(await unsafe.areModelsAvailable(), isFalse);
      await expectLater(
        unsafe.deleteModel(LocalAsrModel.senseVoice),
        throwsA(isA<FileSystemException>()),
      );
    },
  );

  test(
    'imports only a complete verified model and keeps cache if source is invalid',
    () async {
      final instance = manager(
        client: () =>
            MockClient((_) async => http.Response.bytes(payload, 200)),
      );
      await instance.prepareModel(LocalAsrModel.senseVoice);
      final source = Directory('${temp.path}/source')..createSync();
      await File('${source.path}/tiny.onnx').writeAsBytes(utf8.encode('bad'));
      await expectLater(
        instance.importModel(LocalAsrModel.senseVoice, source),
        throwsA(isA<FormatException>()),
      );
      expect(await instance.areModelsAvailable(), isTrue);
      await File('${source.path}/tiny.onnx').writeAsBytes(payload);
      final imported = await instance.importModel(
        LocalAsrModel.senseVoice,
        source,
      );
      expect(await File(imported.modelPath).readAsBytes(), payload);
    },
  );

  test(
    'delete removes only model cache and installedModel never performs network access',
    () async {
      final instance = manager(
        client: () =>
            MockClient((_) async => http.Response.bytes(payload, 200)),
      );
      await instance.prepareModel(LocalAsrModel.senseVoice);
      await instance.deleteModel(LocalAsrModel.senseVoice);
      expect(await instance.areModelsAvailable(), isFalse);
      await expectLater(
        instance.installedModel(LocalAsrModel.senseVoice),
        throwsStateError,
      );
    },
  );
}
