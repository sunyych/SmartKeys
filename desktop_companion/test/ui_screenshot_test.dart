import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_dictation/local_dictation.dart';
import 'package:lumiakeys_protocol/lumiakeys_protocol.dart';
import 'package:lumiakeys_companion/companion_server.dart';
import 'package:lumiakeys_companion/desktop_controller.dart';
import 'package:lumiakeys_companion/desktop_dictation.dart';
import 'package:lumiakeys_companion/desktop_ui.dart';
import 'package:lumiakeys_companion/dictation_receiver.dart';
import 'package:lumiakeys_companion/tray_shell.dart' show desktopBrandAsset;

import 'screenshot_support.dart';

class _Discovery implements ApplicationDiscovery {
  @override
  Future<List<RemoteApplication>> refresh(List<RemoteApplication> apps) async =>
      apps;
}

class _TextSink implements DictationTextSink {
  @override
  Future<void> insertText(String text) async {}
}

class _Window implements DesktopWindowControl {
  @override
  Future<void> hide() async {}

  @override
  Future<void> restore() async {}
}

class _Capture implements DictationCapture {
  final StreamController<List<int>> _samples = StreamController.broadcast();

  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<Stream<List<int>>> start() async => _samples.stream;

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {
    await _samples.close();
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

class _ScreenshotModelManager extends ModelManager {
  _ScreenshotModelManager(this.delegate, this.availability);

  final ModelManager delegate;
  final Map<LocalAsrModel, bool> availability;

  @override
  Future<bool> areModelsAvailable({
    LocalAsrModel model = LocalAsrModel.senseVoice,
  }) async => availability[model] ?? false;

  @override
  Future<LocalAsrModelFiles> installedModel(LocalAsrModel model) =>
      delegate.installedModel(model);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/desktop-screenshot-dictation');

  testWidgets('captures desktop settings and dictation states', (tester) async {
    await tester.runAsync(prepareScreenshotFonts);
    final temp = await tester.runAsync(
      () => Directory.systemTemp.createTemp('smartkeys-desktop-shots-'),
    );
    expect(temp, isNotNull);
    final fixtureRoot = temp!;
    final controller = DesktopController(
      store: MemoryDesktopConfigStore(),
      discovery: _Discovery(),
    );
    await controller.initialize();
    final server = CompanionServer(
      controller: controller,
      dictationSink: _TextSink(),
    );

    const modelBytes = 'verified screenshot model fixture';
    const tokenBytes = 'screenshot token fixture';
    final modelFile = LocalAsrFile(
      name: 'model.int8.onnx',
      sizeBytes: modelBytes.length,
      sha256: sha256.convert(modelBytes.codeUnits).toString(),
    );
    final tokenFile = LocalAsrFile(
      name: 'tokens.txt',
      sizeBytes: tokenBytes.length,
      sha256: sha256.convert(tokenBytes.codeUnits).toString(),
    );
    const modelDirectoryName = 'screenshot-sensevoice';
    final cohereModelFile = LocalAsrFile(
      name: 'cohere.model.onnx',
      sizeBytes: modelBytes.length,
      sha256: sha256.convert(modelBytes.codeUnits).toString(),
    );
    const cohereDirectoryName = 'screenshot-cohere';
    final descriptor = LocalAsrModelDescriptor(
      model: LocalAsrModel.senseVoice,
      directory: modelDirectoryName,
      repository: 'fixture/screenshot-model',
      revision: 'fixture',
      files: [modelFile, tokenFile],
      primaryModelFile: modelFile.name,
    );
    final cohereDescriptor = LocalAsrModelDescriptor(
      model: LocalAsrModel.cohere,
      directory: cohereDirectoryName,
      repository: 'fixture/screenshot-cohere',
      revision: 'fixture',
      files: [cohereModelFile, tokenFile],
      primaryModelFile: cohereModelFile.name,
    );
    final modelDirectory = Directory(
      '${fixtureRoot.path}${Platform.pathSeparator}$modelDirectoryName',
    );
    await tester.runAsync(() async {
      await modelDirectory.create();
      await File(
        '${modelDirectory.path}${Platform.pathSeparator}${modelFile.name}',
      ).writeAsString(modelBytes);
      await File(
        '${modelDirectory.path}${Platform.pathSeparator}${tokenFile.name}',
      ).writeAsString(tokenBytes);
      final cohereDirectory = Directory(
        '${fixtureRoot.path}${Platform.pathSeparator}$cohereDirectoryName',
      );
      await cohereDirectory.create();
      await File(
        '${cohereDirectory.path}${Platform.pathSeparator}${cohereModelFile.name}',
      ).writeAsString(modelBytes);
      await File(
        '${cohereDirectory.path}${Platform.pathSeparator}${tokenFile.name}',
      ).writeAsString(tokenBytes);
    });

    final verifiedModelManager = ModelManager(
      modelRootProvider: () async => fixtureRoot,
      descriptorResolver: (model) => switch (model) {
        LocalAsrModel.senseVoice => descriptor,
        LocalAsrModel.cohere => cohereDescriptor,
      },
    );
    final availability = await tester.runAsync(() async {
      return <LocalAsrModel, bool>{
        LocalAsrModel.senseVoice: await verifiedModelManager.areModelsAvailable(
          model: LocalAsrModel.senseVoice,
        ),
        LocalAsrModel.cohere: await verifiedModelManager.areModelsAvailable(
          model: LocalAsrModel.cohere,
        ),
      };
    });
    expect(availability, {
      LocalAsrModel.senseVoice: true,
      LocalAsrModel.cohere: true,
    });

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'validateTarget') return {'status': 'ready'};
          if (call.method == 'modifiersHeld') return false;
          return true;
        });
    final dictation = DesktopDictationService(
      textSink: _TextSink(),
      modelManager: _ScreenshotModelManager(
        verifiedModelManager,
        availability!,
      ),
      capture: _Capture(),
      recognizerFactory: (_, _) async => _Recognizer(),
      preferences: MemoryDictationSettingsStore(),
      channel: channel,
      windowControl: _Window(),
    );
    final home = RepaintBoundary(
      key: screenshotBoundaryKey,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(fontFamilyFallback: screenshotFontFamilyFallback),
        home: AnimatedBuilder(
          animation: controller,
          builder: (context, _) => DesktopSettingsHome(
            controller: controller,
            server: server,
            dictation: dictation,
            displayHost: 'Screenshot Desktop',
          ),
        ),
      ),
    );

    addTearDown(() async {
      await dictation.shutdown();
      dictation.dispose();
      server.dispose();
      controller.dispose();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      await tester.runAsync(() => fixtureRoot.delete(recursive: true));
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });

    Future<void> sizeTo(int width, int height) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width.toDouble(), height.toDouble());
      await tester.pumpWidget(home);
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => precacheImage(
          const AssetImage(desktopBrandAsset),
          tester.element(find.byType(MaterialApp)),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }

    Future<void> capture(
      String id,
      String title,
      int width,
      int height,
      String notes,
    ) async {
      await captureDesktopScreenshot(
        tester,
        id: id,
        title: title,
        orientation: width >= height ? 'landscape' : 'portrait',
        width: width,
        height: height,
        notes: notes,
      );
      expect(tester.takeException(), isNull);
    }

    const sections = <(int, String, String)>[
      (0, 'General', 'Current Shortcut Profile'),
      (1, 'Bluetooth', 'Bluetooth HID'),
      (2, 'Shortcut Layout', 'Import JSON'),
      (3, 'Apps', 'Managed Applications'),
      (4, 'Profiles', 'Profiles'),
      (5, 'About', 'LumiaKey'),
      (6, 'Local Dictation', 'Private microphone dictation'),
    ];

    for (final (width, height, sizeName) in [
      (1080, 760, 'normal'),
      (800, 700, 'narrow'),
    ]) {
      await sizeTo(width, height);
      for (final (section, title, expected) in sections) {
        final navigation = tester.widget<NavigationRail>(
          find.byType(NavigationRail),
        );
        navigation.onDestinationSelected?.call(section);
        await tester.pumpAndSettle();
        if (section == 6) {
          final modelReady = await tester.runAsync(dictation.modelAvailable);
          expect(modelReady, isTrue);
          await tester.pumpAndSettle();
          expect(
            find.text('Model verified and ready for offline use.'),
            findsOneWidget,
          );
        }
        expect(
          find.text(expected),
          findsWidgets,
          reason: '$title in $sizeName view',
        );
        expect(
          tester.takeException(),
          isNull,
          reason: '$title $sizeName layout',
        );
        await capture(
          'desktop-${title.toLowerCase().replaceAll(' ', '-')}-$sizeName',
          '$title settings · $sizeName',
          width,
          height,
          'Windows Flutter widget render of the $title desktop settings section at $sizeName width.${title == 'General' || title == 'Bluetooth' ? ' Sync service is deliberately offline in this isolated screenshot fixture.' : ''}',
        );
      }
    }

    await sizeTo(1080, 760);
    tester
        .widget<NavigationRail>(find.byType(NavigationRail))
        .onDestinationSelected
        ?.call(2);
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('desktop-button-keyboard.copy')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Edit Copy'), findsOneWidget);
    await capture(
      'desktop-shortcut-editor-dialog',
      'Shortcut editor dialog',
      1080,
      760,
      'Windows Flutter widget render with the shortcut button editor open.',
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    tester
        .widget<NavigationRail>(find.byType(NavigationRail))
        .onDestinationSelected
        ?.call(6);
    dictation.firstUseAcknowledged = false;
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('dictation-toggle')));
    await tester.pumpAndSettle();
    expect(find.text('I understand — continue'), findsOneWidget);
    await capture(
      'desktop-local-dictation-first-use-dialog',
      'Local dictation first-use explanation',
      1080,
      760,
      'Windows Flutter widget render of the explicit local microphone privacy explanation.',
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    dictation.progress = const ModelDownloadProgress(
      model: LocalAsrModel.senseVoice,
      fileName: 'model.int8.onnx',
      bytesReceived: 1024,
      totalBytes: 4096,
    );
    dictation.busy = true;
    dictation.notifyListeners();
    await tester.pump();
    expect(find.textContaining('Downloading model.int8.onnx'), findsOneWidget);
    await capture(
      'desktop-local-dictation-model-download',
      'Local model download progress',
      1080,
      760,
      'Windows Flutter widget render showing explicit model installation progress.',
    );

    dictation.progress = null;
    dictation.busy = false;
    dictation.hotkeyError =
        'That shortcut is already registered by another app.';
    dictation.notifyListeners();
    await tester.pump();
    expect(find.textContaining('already registered'), findsOneWidget);
    await capture(
      'desktop-local-dictation-hotkey-conflict',
      'Global shortcut registration conflict',
      1080,
      760,
      'Windows Flutter widget render with a visible global shortcut registration error.',
    );

    final languageFinder = find.byKey(const ValueKey('dictation-language'));
    await tester.tap(languageFinder);
    await tester.pumpAndSettle();
    expect(find.text('English'), findsWidgets);
    await capture(
      'desktop-local-dictation-language-selection',
      'Local recognition language selection',
      1080,
      760,
      'Windows Flutter widget render with the local recognition language selector open.',
    );
    await tester.tap(find.text('English').last);
    await tester.pumpAndSettle();
    expect(dictation.language, DictationLanguage.english);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey('dictation-language')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('中文').last);
    await tester.pumpAndSettle();
    expect(dictation.language, DictationLanguage.chinese);
    expect(tester.takeException(), isNull);

    final modelFinder = find.byKey(const ValueKey('dictation-model'));
    await tester.tap(modelFinder);
    await tester.pumpAndSettle();
    expect(find.textContaining('SenseVoice'), findsWidgets);
    expect(find.textContaining('Cohere'), findsWidgets);
    await capture(
      'desktop-local-dictation-model-selection',
      'Local recognition model selection',
      1080,
      760,
      'Windows Flutter widget render with the local recognition model selector open.',
    );
    await tester.tap(find.textContaining('Cohere').last);
    await tester.pumpAndSettle();
    expect(dictation.model, LocalAsrModel.cohere);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey('dictation-model')));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('SenseVoice').last);
    await tester.pumpAndSettle();
    expect(dictation.model, LocalAsrModel.senseVoice);
    expect(tester.takeException(), isNull);
    final installed = await tester.runAsync(dictation.modelAvailable);
    expect(installed, isTrue);
    await tester.pumpAndSettle();
    expect(
      find.text('Model verified and ready for offline use.'),
      findsOneWidget,
    );

    dictation.hotkeyError = null;
    dictation.firstUseAcknowledged = true;
    dictation.notifyListeners();
    await tester.runAsync(dictation.start);
    await tester.pumpAndSettle();
    expect(find.text('Listening on this computer'), findsOneWidget);
    await capture(
      'desktop-local-dictation-listening',
      'Local microphone listening state',
      1080,
      760,
      'Windows Flutter widget render with fake microphone capture and a verified fixture model; no audio is persisted.',
    );
    await tester.runAsync(dictation.stop);

    dictation.operationError = 'Microphone access was denied.';
    dictation.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.text('Microphone access was denied.'), findsOneWidget);
    await capture(
      'desktop-local-dictation-error',
      'Local microphone error state',
      1080,
      760,
      'Windows Flutter widget render showing a microphone permission/startup error.',
    );
  });
}
