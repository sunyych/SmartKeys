import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_dictation/local_dictation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_keys/services/hid_service.dart';
import 'package:smart_keys/services/hid_text_output_service.dart';
import 'package:smart_keys/ui/dictation_entry_consent.dart';
import 'package:smart_keys/ui/local_dictation_panel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'first use explains both entries and does not open the microphone',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final hid = _readyHid();
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
      hid.dispose();
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
      final hid = _readyHid();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LocalDictationPanel(
              hid: hid,
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
      hid.dispose();
      tester.view.resetPhysicalSize();
    },
  );

  testWidgets('Windows Unicode profile requires explicit opt-in and persists', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final hid = _readyHid();
    final capture = _FakeCapture();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LocalDictationPanel(
            hid: hid,
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
    final profileField = find.byKey(const ValueKey('dictation-text-profile'));
    await tester.tap(profileField);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Windows Unicode HexNumpad').last);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('windows-unicode-profile-consent')),
      findsOneWidget,
    );
    expect(find.textContaining('EnableHexNumpad'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('windows-unicode-consent-cancel')),
    );
    await tester.pumpAndSettle();
    expect(
      (await SharedPreferences.getInstance()).getString(
        'dictation.text_profile.v1',
      ),
      isNull,
    );

    await tester.tap(profileField);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Windows Unicode HexNumpad').last);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('windows-unicode-consent-confirm')),
    );
    await tester.pumpAndSettle();
    expect(
      (await SharedPreferences.getInstance()).getString(
        'dictation.text_profile.v1',
      ),
      'windowsHexNumpad',
    );
    expect(
      find.textContaining('Windows Unicode HexNumpad types printable BMP text'),
      findsOneWidget,
    );
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pumpAndSettle();
    hid.dispose();
  });

  testWidgets('start holds wake lock and disconnect/background stop capture', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final capture = _FakeCapture();
    final manager = _FakeModelManager();
    final hid = _readyHid();
    var wakeCount = 0;
    var releaseCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LocalDictationPanel(
            hid: hid,
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

    hid.selectedHost.value = null;
    hid.status.value = HidConnectionStatus.disconnected;
    for (var frame = 0; frame < 20 && releaseCount == 0; frame++) {
      await tester.pump(const Duration(milliseconds: 20));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 1)),
      );
    }
    await tester.pumpAndSettle();
    expect(capture.stopCount, 1);
    expect(releaseCount, greaterThanOrEqualTo(1));
    expect(find.textContaining('Bluetooth host disconnected'), findsOneWidget);

    hid.selectedHost.value = const HidHost(
      id: 'test-host',
      name: 'Desktop',
      address: '00:11:22:33:44:55',
    );
    hid.status.value = HidConnectionStatus.connected;
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
    hid.dispose();
  });

  testWidgets('dictation session stays pinned to its Bluetooth address', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final capture = _FakeCapture();
    final hid = _readyHid();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LocalDictationPanel(
            hid: hid,
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

    hid.selectedHost.value = const HidHost(
      id: 'test-host',
      name: 'Renamed computer',
      address: '00:11:22:33:44:55',
    );
    await tester.pumpAndSettle();
    expect(
      capture.stopCount,
      0,
      reason: 'manifest refresh keeps the same selected host active',
    );
    hid.selectedHost.value = const HidHost(
      id: 'other-host',
      name: 'Other computer',
      address: '11:22:33:44:55:66',
    );
    for (var frame = 0; frame < 20 && capture.stopCount == 0; frame++) {
      await tester.pump(const Duration(milliseconds: 20));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 1)),
      );
    }
    expect(capture.stopCount, 1);
    expect(hid.textBatches, isEmpty);
    hid.dispose();
  });

  testWidgets('wake-lock failure stops the microphone after capture starts', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final capture = _FakeCapture();
    final hid = _readyHid();
    var releaseCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LocalDictationPanel(
            hid: hid,
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
    hid.dispose();
  });

  testWidgets('unexpected capture failure releases the wake lock', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final capture = _FakeCapture();
    final hid = _readyHid();
    var releaseCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LocalDictationPanel(
            hid: hid,
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
    hid.dispose();
  });

  testWidgets('Stop types each finalized ASCII phrase once over Bluetooth', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final capture = _FakeCapture();
    final hid = _readyHid();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LocalDictationPanel(
            hid: hid,
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
    for (var frame = 0; frame < 20 && hid.textBatches.isEmpty; frame++) {
      await tester.pump(const Duration(milliseconds: 20));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 1)),
      );
    }
    expect(hid.textBatches, hasLength(1));
    expect(hid.textBatches.single.expectedAddress, '00:11:22:33:44:55');
    expect(
      hid.textBatches.single.strokes,
      hasLength('recognized phrase'.length),
    );

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pumpAndSettle();
    hid.dispose();
  });

  testWidgets('Bluetooth report failure is visible and never retried', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final capture = _FakeCapture();
    final hid = _readyHid()
      ..textBatchError = StateError('Bluetooth rejected a keyboard report');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LocalDictationPanel(
            hid: hid,
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
    for (var frame = 0; frame < 20; frame++) {
      await tester.pump(const Duration(milliseconds: 20));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 1)),
      );
      if (find.byKey(const ValueKey('dictation-error')).evaluate().isNotEmpty) {
        break;
      }
    }
    expect(hid.textBatches, hasLength(1));
    expect(
      find.textContaining('Bluetooth rejected a keyboard report'),
      findsOneWidget,
    );
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pumpAndSettle();
    hid.dispose();
  });

  testWidgets(
    'disconnect cancels text output while Stop flushes its final phrase',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final capture = _FakeCapture();
      final hid = _readyHid();
      final batchStarted = Completer<void>();
      final batchCancelled = Completer<void>();
      final batchRelease = Completer<void>();
      hid.onTextBatch = () {
        if (!batchStarted.isCompleted) batchStarted.complete();
        return batchRelease.future;
      };
      hid.onCancelTextBatch = (_) async {
        if (!batchCancelled.isCompleted) batchCancelled.complete();
        if (!batchRelease.isCompleted) {
          batchRelease.completeError(
            const HidTextOutputException('Bluetooth dictation was cancelled.'),
          );
        }
      };
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LocalDictationPanel(
              hid: hid,
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
      for (var frame = 0; frame < 20 && !batchStarted.isCompleted; frame++) {
        await tester.pump(const Duration(milliseconds: 20));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 1)),
        );
      }
      expect(batchStarted.isCompleted, isTrue);

      hid.selectedHost.value = null;
      hid.status.value = HidConnectionStatus.disconnected;
      for (var frame = 0; frame < 20 && !batchCancelled.isCompleted; frame++) {
        await tester.pump(const Duration(milliseconds: 20));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 1)),
        );
      }
      expect(batchCancelled.isCompleted, isTrue);
      expect(hid.cancelledTextBatches, hasLength(1));
      expect(capture.stopCount, 1);
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pumpAndSettle();
      hid.dispose();
    },
  );

  testWidgets(
    'quick entry auto-starts a warm model and never downloads implicitly',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final warmCapture = _FakeCapture();
      final warmManager = _FakeModelManager();
      final warmHid = _readyHid();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LocalDictationPanel(
              hid: warmHid,
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
      warmHid.dispose();

      final missingCapture = _FakeCapture();
      final missingManager = _FakeModelManager(ready: false);
      final missingHid = _readyHid();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LocalDictationPanel(
              hid: missingHid,
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
      missingHid.dispose();
    },
  );

  testWidgets(
    'model download and deletion are explicit and permission failure blocks capture',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final capture = _FakeCapture()..permitted = false;
      final manager = _FakeModelManager(ready: false);
      final hid = _readyHid();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LocalDictationPanel(
              hid: hid,
              modelManager: manager,
              capture: capture,
              recognizerFactory: (_, _) async => _FakeRecognizer(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('download-dictation-model')),
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
      hid.dispose();
    },
  );
}

RecordingHidService _readyHid() {
  final service = RecordingHidService();
  service.selectedHost.value = const HidHost(
    id: 'test-host',
    name: 'Computer',
    address: '00:11:22:33:44:55',
  );
  service.status.value = HidConnectionStatus.connected;
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
