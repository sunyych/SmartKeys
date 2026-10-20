import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_dictation/local_dictation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_keys/services/companion_service.dart';
import 'package:smart_keys/ui/dictation_entry_consent.dart';
import 'package:smart_keys/ui/local_dictation_panel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'first use explains both entries and does not open the microphone',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final companion = _readyCompanion();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                key: const ValueKey('open-local-dictation'),
                onPressed: () => ensureDictationEntryExplained(context),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('open-local-dictation')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('dictation-entry-explanation')),
        findsOneWidget,
      );
      expect(find.text('Application voice input'), findsOneWidget);
      expect(find.text('Local quick dictation'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('dictation-explanation-cancel')),
      );
      await tester.pumpAndSettle();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(dictationConsentPreferenceKey), isNot(true));
      companion.dispose();
    },
  );

  testWidgets(
    'acknowledgement persists and panel stays ready in both orientations',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final capture = _FakeCapture();
      final manager = _FakeModelManager();
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                key: const ValueKey('open'),
                onPressed: () => ensureDictationEntryExplained(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('open')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('dictation-explanation-accept')),
      );
      await tester.pumpAndSettle();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(dictationConsentPreferenceKey), isTrue);
      tester.view.resetPhysicalSize();
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      tester.view.physicalSize = const Size(915, 412);
      final companion = _readyCompanion();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LocalDictationPanel(
              companion: companion,
              modelManager: manager,
              capture: capture,
              recognizerFactory: (_, _) async => _FakeRecognizer(),
              enableWakeLock: () async {},
              disableWakeLock: () async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('local-dictation-panel')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('dictation-language')), findsOneWidget);
      expect(find.byKey(const ValueKey('dictation-model')), findsOneWidget);
      expect(find.byKey(const ValueKey('start-dictation')), findsOneWidget);
      expect(tester.takeException(), isNull);
      companion.dispose();
      tester.view.resetPhysicalSize();
    },
  );

  testWidgets('start holds wake lock and disconnect/background stop capture', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final capture = _FakeCapture();
    final manager = _FakeModelManager();
    final companion = _readyCompanion();
    var wakeCount = 0;
    var releaseCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LocalDictationPanel(
            companion: companion,
            modelManager: manager,
            capture: capture,
            recognizerFactory: (_, _) async => _FakeRecognizer(),
            enableWakeLock: () async {
              wakeCount++;
            },
            disableWakeLock: () async {
              releaseCount++;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('start-dictation')));
    await tester.pumpAndSettle();
    expect(capture.startCount, 1);
    expect(wakeCount, 1);
    expect(find.byKey(const ValueKey('stop-dictation')), findsOneWidget);

    companion.host.value = null;
    for (var frame = 0; frame < 20 && releaseCount == 0; frame++) {
      await tester.pump(const Duration(milliseconds: 20));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 1)),
      );
    }
    await tester.pumpAndSettle();
    expect(capture.stopCount, 1);
    expect(releaseCount, greaterThanOrEqualTo(1));
    expect(find.textContaining('Desktop disconnected'), findsOneWidget);

    companion.host.value = const CompanionHost(
      name: 'Desktop',
      platform: 'windows',
      address: '127.0.0.1',
      port: 1,
      token: 'token',
      protocolVersion: 2,
      capabilities: {'local-dictation-v1'},
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('start-dictation')));
    await tester.pumpAndSettle();
    expect(capture.startCount, 2);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    for (var frame = 0; frame < 20 && releaseCount < 2; frame++) {
      await tester.pump(const Duration(milliseconds: 20));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 1)),
      );
    }
    await tester.pumpAndSettle();
    expect(capture.stopCount, 2);
    expect(releaseCount, greaterThanOrEqualTo(2));
    companion.dispose();
  });

  testWidgets('dictation session stays pinned to its desktop identity', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final capture = _FakeCapture();
    final companion = _readyCompanion();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LocalDictationPanel(
            companion: companion,
            modelManager: _FakeModelManager(),
            capture: capture,
            recognizerFactory: (_, _) async => _FakeRecognizer(),
            enableWakeLock: () async {},
            disableWakeLock: () async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('start-dictation')));
    await tester.pumpAndSettle();

    companion.host.value = const CompanionHost(
      name: 'Desktop',
      platform: 'windows',
      address: '127.0.0.1',
      port: 1,
      token: 'token',
      protocolVersion: 2,
      revision: 4,
      capabilities: {'local-dictation-v1'},
    );
    companion.status.value = CompanionSyncStatus.syncing;
    await tester.pumpAndSettle();
    expect(
      capture.stopCount,
      0,
      reason: 'manifest refresh keeps the same selected host active',
    );
    companion.status.value = CompanionSyncStatus.ready;
    await tester.pumpAndSettle();

    companion.host.value = const CompanionHost(
      name: 'Other desktop',
      platform: 'windows',
      address: '127.0.0.2',
      port: 2,
      token: 'other-token',
      protocolVersion: 2,
      revision: 1,
      capabilities: {'local-dictation-v1'},
    );
    for (var frame = 0; frame < 20 && capture.stopCount == 0; frame++) {
      await tester.pump(const Duration(milliseconds: 20));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 1)),
      );
    }
    expect(capture.stopCount, 1);
    expect(companion.dictationRequests, isEmpty);
    companion.dispose();
  });

  testWidgets('wake-lock failure stops the microphone after capture starts', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final capture = _FakeCapture();
    final companion = _readyCompanion();
    var releaseCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LocalDictationPanel(
            companion: companion,
            modelManager: _FakeModelManager(),
            capture: capture,
            recognizerFactory: (_, _) async => _FakeRecognizer(),
            enableWakeLock: () async => throw StateError('wake lock failed'),
            disableWakeLock: () async {
              releaseCount++;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('start-dictation')));
    for (var frame = 0; frame < 20 && capture.stopCount == 0; frame++) {
      await tester.pump(const Duration(milliseconds: 20));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 1)),
      );
    }
    await tester.pumpAndSettle();
    expect(capture.startCount, 1);
    expect(capture.stopCount, 1);
    expect(releaseCount, 1);
    expect(find.textContaining('wake lock failed'), findsOneWidget);
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pumpAndSettle();
    companion.dispose();
  });

  testWidgets('unexpected capture failure releases the wake lock', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final capture = _FakeCapture();
    final companion = _readyCompanion();
    var releaseCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LocalDictationPanel(
            companion: companion,
            modelManager: _FakeModelManager(),
            capture: capture,
            recognizerFactory: (_, _) async => _FakeRecognizer(),
            enableWakeLock: () async {},
            disableWakeLock: () async {
              releaseCount++;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('start-dictation')));
    await tester.pumpAndSettle();
    capture.audio.addError(StateError('capture interrupted'));
    for (var frame = 0; frame < 20 && releaseCount == 0; frame++) {
      await tester.pump(const Duration(milliseconds: 20));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 1)),
      );
    }
    expect(capture.stopCount, 1);
    expect(releaseCount, 1);
    expect(find.textContaining('capture interrupted'), findsOneWidget);
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pumpAndSettle();
    companion.dispose();
  });

  testWidgets('Stop delivers each finalized phrase once to the desktop', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final capture = _FakeCapture();
    final companion = _readyCompanion();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LocalDictationPanel(
            companion: companion,
            modelManager: _FakeModelManager(),
            capture: capture,
            recognizerFactory: (_, _) async => _FakeRecognizer(),
            enableWakeLock: () async {},
            disableWakeLock: () async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('start-dictation')));
    await tester.pumpAndSettle();

    capture.audio.add(
      List<int>.generate(3200, (index) => index.isEven ? 16 : 39),
    );
    await tester.pump(const Duration(milliseconds: 20));
    await tester.tap(find.byKey(const ValueKey('stop-dictation')));
    for (
      var frame = 0;
      frame < 20 && companion.dictationRequests.isEmpty;
      frame++
    ) {
      await tester.pump(const Duration(milliseconds: 20));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 1)),
      );
    }
    expect(companion.dictationRequests, hasLength(1));
    expect(companion.dictationRequests.single.text, 'recognized phrase');
    expect(companion.dictationRequests.single.sequence, 1);

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pumpAndSettle();
    companion.dispose();
  });

  testWidgets(
    'quick entry auto-starts a warm model and never downloads implicitly',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final warmCapture = _FakeCapture();
      final warmManager = _FakeModelManager();
      final warmCompanion = _readyCompanion();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LocalDictationPanel(
              companion: warmCompanion,
              modelManager: warmManager,
              capture: warmCapture,
              recognizerFactory: (_, _) async => _FakeRecognizer(),
              autoStartWhenReady: true,
              enableWakeLock: () async {},
              disableWakeLock: () async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(warmCapture.startCount, 1);
      expect(warmManager.prepareCount, 0);
      expect(find.byKey(const ValueKey('stop-dictation')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('stop-dictation')));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pumpAndSettle();
      warmCompanion.dispose();

      final missingCapture = _FakeCapture();
      final missingManager = _FakeModelManager(ready: false);
      final missingCompanion = _readyCompanion();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LocalDictationPanel(
              companion: missingCompanion,
              modelManager: missingManager,
              capture: missingCapture,
              recognizerFactory: (_, _) async => _FakeRecognizer(),
              autoStartWhenReady: true,
              enableWakeLock: () async {},
              disableWakeLock: () async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(missingCapture.startCount, 0);
      expect(missingManager.prepareCount, 0);
      expect(
        find.byKey(const ValueKey('download-dictation-model')),
        findsOneWidget,
      );
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pumpAndSettle();
      missingCompanion.dispose();
    },
  );

  testWidgets(
    'model download and deletion are explicit and permission failure blocks capture',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final capture = _FakeCapture()..permitted = false;
      final manager = _FakeModelManager(ready: false);
      final companion = _readyCompanion();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LocalDictationPanel(
              companion: companion,
              modelManager: manager,
              capture: capture,
              recognizerFactory: (_, _) async => _FakeRecognizer(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('download-dictation-model')));
      await tester.pumpAndSettle();
      expect(manager.prepareCount, 1);
      expect(find.textContaining('Installed'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('start-dictation')));
      await tester.pumpAndSettle();
      expect(capture.startCount, 0);
      expect(
        find.textContaining('Microphone permission is needed'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('dictation-error')), findsOneWidget);

      capture.permitted = true;
      await tester.tap(find.byKey(const ValueKey('delete-dictation-model')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete').last);
      await tester.pumpAndSettle();
      expect(manager.deleteCount, 1);
      expect(find.textContaining('Not installed'), findsOneWidget);
      companion.dispose();
    },
  );
}

RecordingCompanionService _readyCompanion() {
  final service = RecordingCompanionService();
  service.host.value = const CompanionHost(
    name: 'Desktop',
    platform: 'windows',
    address: '127.0.0.1',
    port: 1,
    token: 'token',
    protocolVersion: 2,
    capabilities: {'local-dictation-v1'},
  );
  service.status.value = CompanionSyncStatus.ready;
  return service;
}

class _FakeModelManager extends ModelManager {
  _FakeModelManager({this.ready = true});
  bool ready;

  @override
  LocalAsrModelDescriptor descriptor(
    LocalAsrModel model,
  ) => LocalAsrModelDescriptor(
    model: model,
    directory: model.name,
    repository: 'test/models',
    revision: 'test-revision',
    primaryModelFile: 'model.onnx',
    files: const [
      LocalAsrFile(
        name: 'model.onnx',
        sizeBytes: 16,
        sha256:
            '0000000000000000000000000000000000000000000000000000000000000000',
      ),
    ],
  );

  int prepareCount = 0;
  int deleteCount = 0;

  @override
  Future<bool> areModelsAvailable({
    LocalAsrModel model = LocalAsrModel.senseVoice,
  }) async => ready;

  @override
  Future<LocalAsrModelFiles> installedModel(LocalAsrModel model) async =>
      LocalAsrModelFiles(
        model: model,
        modelPath: 'model.onnx',
        tokensPath: 'tokens.txt',
      );

  @override
  Future<LocalAsrModelFiles> prepareModel(
    LocalAsrModel model, {
    void Function(ModelDownloadProgress progress)? onProgress,
  }) async {
    prepareCount++;
    ready = true;
    return installedModel(model);
  }

  @override
  Future<LocalAsrModelFiles> importModel(
    LocalAsrModel model,
    Directory source,
  ) => installedModel(model);

  @override
  Future<void> deleteModel(LocalAsrModel model) async {
    deleteCount++;
    ready = false;
  }
}

class _FakeCapture implements DictationCapture {
  StreamController<List<int>> audio = StreamController<List<int>>.broadcast();
  int startCount = 0;
  int stopCount = 0;
  bool permitted = true;

  @override
  Future<bool> hasPermission() async => permitted;

  @override
  Future<Stream<List<int>>> start() async {
    if (startCount > 0) {
      audio = StreamController<List<int>>.broadcast();
    }
    startCount++;
    return audio.stream;
  }

  @override
  Future<void> stop() async {
    stopCount++;
  }

  @override
  Future<void> dispose() async {
    await audio.close();
  }
}

class _FakeRecognizer implements DictationRecognizer {
  @override
  Future<String> transcribe(
    Float32List samples, {
    DictationLanguage? language,
  }) async => 'recognized phrase';

  @override
  Future<void> dispose({bool flush = true}) async {}
}
