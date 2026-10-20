import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_dictation/local_dictation.dart';

import 'package:lumiakeys_companion/desktop_dictation.dart';
import 'package:lumiakeys_companion/dictation_receiver.dart';

class _Window implements DesktopWindowControl {
  final calls = <String>[];
  @override
  Future<void> hide() async => calls.add('hide');
  @override
  Future<void> restore() async => calls.add('restore');
}

class _Capture implements DictationCapture {
  final calls = <String>[];
  final stream = StreamController<List<int>>();
  @override
  Future<bool> hasPermission() async {
    calls.add('permission');
    return true;
  }

  @override
  Future<Stream<List<int>>> start() async {
    calls.add('start');
    return stream.stream;
  }

  @override
  Future<void> stop() async => calls.add('stop');
  @override
  Future<void> dispose() async {
    calls.add('dispose');
    stream.close();
  }
}

class _Recognizer implements DictationRecognizer {
  @override
  Future<String> transcribe(
    Float32List samples, {
    DictationLanguage? language,
  }) async => '';
  @override
  Future<void> dispose({bool flush = true}) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/local_dictation');
  late Directory root;
  late _Window window;
  late _Capture capture;
  late DesktopDictationService service;
  late MemoryDictationSettingsStore preferences;
  var targetReady = true;
  var modifierHeld = false;
  var rejectHotkeyRegistration = false;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('desktop-dictation-test-');
    const modelBytes = 'verified model fixture';
    const tokenBytes = 'token fixture';
    final modelFile = LocalAsrFile(
      name: 'model.int8.onnx',
      sizeBytes: modelBytes.length,
      sha256: sha256.convert(modelBytes.codeUnits).toString(),
    );
    final tokensFile = LocalAsrFile(
      name: 'tokens.txt',
      sizeBytes: tokenBytes.length,
      sha256: sha256.convert(tokenBytes.codeUnits).toString(),
    );
    final descriptor = LocalAsrModelDescriptor(
      model: LocalAsrModel.senseVoice,
      directory: 'sensevoice-fixture',
      repository: 'fixture/model',
      revision: 'fixture',
      files: [modelFile, tokensFile],
      primaryModelFile: 'model.int8.onnx',
    );
    final modelDirectory = Directory(
      '${root.path}${Platform.pathSeparator}${descriptor.directory}',
    );
    await modelDirectory.create();
    await File(
      '${modelDirectory.path}${Platform.pathSeparator}${modelFile.name}',
    ).writeAsString(modelBytes);
    await File(
      '${modelDirectory.path}${Platform.pathSeparator}${tokensFile.name}',
    ).writeAsString(tokenBytes);

    targetReady = true;
    modifierHeld = false;
    rejectHotkeyRegistration = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'modifiersHeld') return modifierHeld;
          if (call.method == 'registerToggleHotkey' &&
              rejectHotkeyRegistration) {
            throw PlatformException(
              code: 'hotkey_busy',
              message: 'That shortcut is already registered.',
            );
          }
          if (call.method == 'validateTarget') {
            return {
              'status': targetReady ? 'ready' : 'rejected',
              'reason': 'own_or_invalid_foreground',
            };
          }
          return true;
        });
    window = _Window();
    capture = _Capture();
    preferences = MemoryDictationSettingsStore();
    service = DesktopDictationService(
      textSink: _NoopSink(),
      modelManager: ModelManager(
        modelRootProvider: () async => root,
        descriptorResolver: (_) => descriptor,
      ),
      capture: capture,
      recognizerFactory: (_, _) async => _Recognizer(),
      preferences: preferences,
      channel: channel,
      windowControl: window,
    )..firstUseAcknowledged = true;
  });

  tearDown(() async {
    await service.shutdown();
    service.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await root.delete(recursive: true);
  });

  test(
    'hides before capture and stopping never refocuses the own window',
    () async {
      await service.start();
      expect(window.calls, ['hide']);
      expect(capture.calls, ['permission', 'start']);
      await service.stop();
      expect(capture.calls, ['permission', 'start', 'stop']);
      expect(window.calls, ['hide']);
    },
  );

  test('restores settings window after safe-target rejection', () async {
    targetReady = false;
    await expectLater(service.start(), throwsStateError);
    expect(window.calls, ['hide', 'restore']);
    expect(capture.calls, isEmpty);
  });

  test(
    'loads persisted language, model, first-use, and shortcut settings',
    () async {
      preferences.values.addAll({
        'lumiakeys.dictation.model.v1': LocalAsrModel.cohere.name,
        'lumiakeys.dictation.language.v1': DictationLanguage.english.name,
        'lumiakeys.dictation.firstUseAcknowledged.v1': true,
        'lumiakeys.dictation.hotkey.v1': 'ctrlAltSpace',
      });

      await service.initialize();

      expect(service.model, LocalAsrModel.cohere);
      expect(service.language, DictationLanguage.english);
      expect(service.firstUseAcknowledged, isTrue);
      expect(service.hotkey, 'ctrlAltSpace');
      expect(service.ready, isTrue);
    },
  );

  test('persists model and language selection', () async {
    await service.configure(
      model: LocalAsrModel.cohere,
      language: DictationLanguage.english,
    );

    expect(preferences.values['lumiakeys.dictation.model.v1'], 'cohere');
    expect(preferences.values['lumiakeys.dictation.language.v1'], 'english');
  });

  test(
    'hotkey registration errors remain visible and do not change selection',
    () async {
      rejectHotkeyRegistration = true;

      await service.setHotkey('ctrlAltSpace');

      expect(service.hotkey, 'ctrlShiftSpace');
      expect(service.hotkeyError, contains('already registered'));
      expect(
        preferences.values,
        isNot(contains('lumiakeys.dictation.hotkey.v1')),
      );
    },
  );

  test('acknowledges first-use explanation persistently', () async {
    await service.acknowledgeFirstUse();

    expect(service.firstUseAcknowledged, isTrue);
    expect(
      preferences.values['lumiakeys.dictation.firstUseAcknowledged.v1'],
      true,
    );
  });

  test('defers global toggle until shortcut modifiers are released', () async {
    await service.initialize();
    var toggled = false;
    service.onToggleRequested = () => toggled = true;
    modifierHeld = true;
    final waiting = service.handleToggleHotkeyPressed();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(toggled, isFalse);
    modifierHeld = false;
    await waiting;
    expect(toggled, isTrue);
  });

  test('shutdown during settings load suppresses late notifications', () async {
    final preferences = _DelayedPreferences();
    final delayed = DesktopDictationService(
      textSink: _NoopSink(),
      capture: _Capture(),
      preferences: preferences,
      channel: channel,
      windowControl: _Window(),
    );
    final initialization = delayed.initialize();
    await delayed.shutdown();
    delayed.dispose();
    preferences.firstRead.complete(null);
    await initialization;
  });
}

class _NoopSink implements DictationTextSink {
  @override
  Future<void> insertText(String text) async {}
}

class _DelayedPreferences implements DesktopDictationSettingsStore {
  final firstRead = Completer<String?>();
  @override
  Future<String?> getString(String key) => firstRead.future;
  @override
  Future<bool?> getBool(String key) async => null;
  @override
  Future<void> setString(String key, String value) async {}
  @override
  Future<void> setBool(String key, bool value) async {}
}
