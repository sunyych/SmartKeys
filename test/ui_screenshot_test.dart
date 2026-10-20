import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_dictation/local_dictation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_keys/app.dart';
import 'package:smart_keys/models/config.dart';
import 'package:smart_keys/services/hid_service.dart';
import 'package:smart_keys/ui/bluetooth_connection_sheet.dart';
import 'package:smart_keys/ui/button_editor_screen.dart';
import 'package:smart_keys/ui/dictation_entry_consent.dart';
import 'package:smart_keys/ui/home_screen.dart';
import 'package:smart_keys/ui/icon_picker_screen.dart';
import 'package:smart_keys/ui/local_dictation_panel.dart';
import 'package:smart_keys/ui/profile_editor_screen.dart';
import 'package:smart_keys/ui/profile_import_flow.dart';
import 'package:smart_keys/ui/profile_management_screen.dart';
import 'package:smart_keys/ui/settings_screen.dart';
import 'package:smart_keys/ui/shortcut_community_screen.dart';
import 'package:smart_keys/ui/wheel_editor_screen.dart';

import 'screenshot_support.dart';
import 'test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(ScreenshotSupport.prepareFonts);

  testWidgets('home screenshots cover portrait, landscape, and edit mode', (
    tester,
  ) async {
    final shots = ScreenshotSupport(tester);
    final harness = await TestHarness.create();
    addTearDown(() async {
      await shots.unmount();
      shots.resetViewport();
      await harness.dispose();
    });
    await shots.setViewport(const Size(390, 844));
    final key = GlobalKey();
    await tester.pumpWidget(_app(harness, key, const HomeScreen()));
    expect(find.byKey(const ValueKey('portrait-layout')), findsOneWidget);
    expect(find.byKey(const ValueKey('local-quick-output')), findsOneWidget);
    await shots.capture(
      id: 'phone-home-portrait',
      title: 'Home control surface · portrait',
      orientation: 'portrait',
      notes: 'Full home screen at 390×844 logical pixels.',
      boundaryKey: key,
    );

    await shots.setViewport(const Size(844, 390));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('landscape-layout')), findsOneWidget);
    await shots.capture(
      id: 'phone-home-landscape',
      title: 'Home control surface · landscape',
      orientation: 'landscape',
      notes: 'Responsive home layout at 844×390 logical pixels.',
      boundaryKey: key,
    );

    await tester.tap(find.byKey(const ValueKey('control-menu')));
    await tester.pumpAndSettle();
    expect(find.text('Edit buttons'), findsOneWidget);
    await tester.tap(find.text('Edit buttons'));
    await tester.pumpAndSettle();
    expect(find.text('Editing'), findsOneWidget);
    await shots.capture(
      id: 'phone-home-editing',
      title: 'Home control surface · editing',
      orientation: 'landscape',
      notes: 'Landscape home with button editing enabled.',
      boundaryKey: key,
    );
  });

  testWidgets('public mobile pages render as screenshot gallery entries', (
    tester,
  ) async {
    final shots = ScreenshotSupport(tester);
    final harness = await TestHarness.create();
    addTearDown(() async {
      await shots.unmount();
      shots.resetViewport();
      await harness.dispose();
    });
    await shots.setViewport(const Size(412, 915));

    Future<void> page({
      required String id,
      required String title,
      required String note,
      required Widget child,
      Finder? expected,
    }) async {
      final key = GlobalKey();
      await tester.pumpWidget(_app(harness, key, child));
      await tester.pumpAndSettle();
      if (expected != null) expect(expected, findsWidgets);
      await shots.capture(
        id: id,
        title: title,
        orientation: 'portrait',
        notes: note,
        boundaryKey: key,
      );
    }

    final bluetoothKey = GlobalKey();
    await tester.pumpWidget(
      _app(
        harness,
        bluetoothKey,
        Scaffold(
          body: Center(
            child: Builder(
              builder: (context) => FilledButton(
                key: const ValueKey('open-bluetooth-sheet'),
                onPressed: () =>
                    showBluetoothConnectionSheet(context, harness.hid),
                child: const Text('Open Bluetooth settings'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('open-bluetooth-sheet')));
    await tester.pumpAndSettle();
    expect(find.text('Bluetooth HID connection'), findsOneWidget);
    await shots.capture(
      id: 'phone-bluetooth',
      title: 'Bluetooth HID connection',
      orientation: 'portrait',
      notes:
          'Actual modal sheet over a phone route; disconnected pairing guidance.',
      boundaryKey: bluetoothKey,
    );
    await page(
      id: 'phone-settings',
      title: 'Settings',
      note:
          'Settings list, including connection, orientation, and charging controls.',
      child: const SettingsScreen(),
      expected: find.text('SHORTCUT PLATFORM'),
    );
    final settingsMidKey = GlobalKey();
    await tester.pumpWidget(
      _app(harness, settingsMidKey, const SettingsScreen()),
    );
    await tester.pumpAndSettle();
    final settingsScrollable = find
        .descendant(
          of: find.byType(ListView).first,
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      find.text('SCREEN ORIENTATION'),
      240,
      scrollable: settingsScrollable,
      maxScrolls: 20,
    );
    await tester.pumpAndSettle();
    expect(find.text('SCREEN ORIENTATION'), findsOneWidget);
    await shots.capture(
      id: 'phone-settings-orientation-charging',
      title: 'Settings · orientation and charging display',
      orientation: 'portrait',
      notes: 'Scrolled middle section showing screen orientation controls.',
      boundaryKey: settingsMidKey,
    );
    await tester.scrollUntilVisible(
      find.text('Fixed while charging'),
      240,
      scrollable: settingsScrollable,
      maxScrolls: 20,
    );
    await tester.pumpAndSettle();
    expect(find.text('Fixed while charging'), findsOneWidget);
    await shots.capture(
      id: 'phone-settings-charging-display',
      title: 'Settings · charging display',
      orientation: 'portrait',
      notes: 'Scrolled to the charging display controls.',
      boundaryKey: settingsMidKey,
    );
    for (
      var attempt = 0;
      attempt < 6 &&
          find
              .byKey(const ValueKey('charging-brightness-slider'))
              .evaluate()
              .isEmpty;
      attempt++
    ) {
      await tester.drag(find.byType(ListView).first, const Offset(0, -250));
      await tester.pumpAndSettle();
    }
    expect(
      find.byKey(const ValueKey('charging-brightness-slider')),
      findsOneWidget,
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('charging-brightness-slider')),
    );
    await tester.pumpAndSettle();
    await shots.capture(
      id: 'phone-settings-charging-controls',
      title: 'Settings · charging brightness controls',
      orientation: 'portrait',
      notes:
          'Scrolled charging section with brightness slider and keep-screen-awake switch.',
      boundaryKey: settingsMidKey,
    );
    final settingsKey = GlobalKey();
    await tester.pumpWidget(_app(harness, settingsKey, const SettingsScreen()));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).first, const Offset(0, -1800));
    await tester.pumpAndSettle();
    expect(find.text('BUILT-IN TEMPLATES'), findsOneWidget);
    await shots.capture(
      id: 'phone-settings-lower-sections',
      title: 'Settings · lower sections',
      orientation: 'portrait',
      notes:
          'Scrolled to on-device shortcut usage, default templates, and restore controls.',
      boundaryKey: settingsKey,
    );
    await page(
      id: 'phone-profile-management',
      title: 'Profiles',
      note: 'Profile list with active/default state and edit actions.',
      child: const ProfileManagementScreen(),
      expected: find.text('General'),
    );
    await page(
      id: 'phone-profile-editor',
      title: 'Edit profile',
      note: 'Profile name, target application, icon, and accent editor.',
      child: const ProfileEditorScreen(profileId: 'profile_general'),
      expected: find.text('Profile name'),
    );
    await page(
      id: 'phone-button-editor',
      title: 'Edit button',
      note: 'Button label, subtitle, action, and modifier editor.',
      child: const ButtonEditorScreen(position: 0),
      expected: find.text('Label'),
    );
    final actionEditorKey = GlobalKey();
    await tester.pumpWidget(
      _app(harness, actionEditorKey, const ButtonEditorScreen(position: 0)),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).first, const Offset(0, -1000));
    await tester.pumpAndSettle();
    expect(find.text('Action type'), findsOneWidget);
    await shots.capture(
      id: 'phone-button-editor-action',
      title: 'Edit button · action controls',
      orientation: 'portrait',
      notes:
          'Scrolled button editor exposing action type, key/value, and modifiers.',
      boundaryKey: actionEditorKey,
    );
    await page(
      id: 'phone-wheel-editor',
      title: 'Navigation control editor',
      note: 'Wheel mode and directional action configuration.',
      child: const WheelEditorScreen(),
      expected: find.text('Control label'),
    );
    await page(
      id: 'phone-icon-picker',
      title: 'Built-in icon picker',
      note: 'Search and category controls with the semantic icon catalog.',
      child: const IconPickerScreen(selectedId: 'edit.copy'),
      expected: find.text('Built-in Icons'),
    );
    await page(
      id: 'phone-shortcut-community',
      title: 'Shortcut Community',
      note: 'Community packs and profile JSON import/export actions.',
      child: const ShortcutCommunityScreen(),
      expected: find.byKey(const ValueKey('community-paste-json')),
    );
  });

  testWidgets('profile import replacement dialog is included', (tester) async {
    final shots = ScreenshotSupport(tester);
    final profiles = List<ProfileConfig>.generate(
      freeProfileLimit,
      (index) => profile(id: 'profile_$index', name: 'Profile ${index + 1}'),
    );
    final harness = await TestHarness.create(
      config: testConfig(profiles: profiles),
    );
    addTearDown(() async {
      await shots.unmount();
      shots.resetViewport();
      await harness.dispose();
    });
    await shots.setViewport(const Size(412, 915));
    final key = GlobalKey();
    await tester.pumpWidget(
      _app(
        harness,
        key,
        Builder(
          builder: (context) => Scaffold(
            appBar: AppBar(title: const Text('Import profile preview')),
            body: Center(
              child: FilledButton(
                key: const ValueKey('open-replacement-picker'),
                onPressed: () => installSharedProfile(
                  context,
                  profile(id: 'community_import', name: 'Community profile'),
                ),
                child: const Text('Choose replacement slot'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('open-replacement-picker')));
    await tester.pumpAndSettle();
    expect(find.text('Replace a profile'), findsOneWidget);
    expect(find.text('Profile 1'), findsOneWidget);
    await shots.capture(
      id: 'phone-profile-import-replacement',
      title: 'Import profile · choose replacement slot',
      orientation: 'portrait',
      notes: 'The full free-profile limit opens the replace-slot import sheet.',
      boundaryKey: key,
    );
  });

  testWidgets('first-use voice explanation dialog is captured', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final shots = ScreenshotSupport(tester);
    final harness = await TestHarness.create();
    addTearDown(() async {
      await shots.unmount();
      shots.resetViewport();
      await harness.dispose();
    });
    await shots.setViewport(const Size(412, 915));
    final key = GlobalKey();
    await tester.pumpWidget(
      _app(
        harness,
        key,
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => ensureDictationEntryExplained(context),
                child: const Text('Open voice input'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open voice input'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('dictation-entry-explanation')),
      findsOneWidget,
    );
    expect(find.text('Local quick dictation'), findsOneWidget);
    await shots.capture(
      id: 'phone-voice-first-use',
      title: 'Voice input · first-use explanation',
      orientation: 'portrait',
      notes:
          'First-use explanation distinguishes application voice input from on-device dictation.',
      boundaryKey: key,
    );
  });

  testWidgets('local dictation panel covers model, language, listening and error states', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final shots = ScreenshotSupport(tester);
    final harness = await TestHarness.create();
    final capture = _ScreenshotCapture();
    final manager = _ScreenshotModelManager();
    addTearDown(() async {
      await shots.unmount();
      await capture.dispose();
      shots.resetViewport();
      await harness.dispose();
    });
    harness.hid.status.value = HidConnectionStatus.disconnected;
    await shots.setViewport(const Size(412, 915));

    Future<GlobalKey> mountPanel({bool allowed = true}) async {
      final key = GlobalKey();
      capture.permitted = allowed;
      await tester.pumpWidget(
        _app(
          harness,
          key,
          Scaffold(
            body: Center(
              child: LocalDictationPanel(
                hid: harness.hid,
                modelManager: manager,
                capture: capture,
                recognizerFactory: (_, _) async => _ScreenshotRecognizer(),
                enableWakeLock: () async {},
                disableWakeLock: () async {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('local-dictation-panel')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      return key;
    }

    var key = await mountPanel();
    expect(find.textContaining('Not installed'), findsOneWidget);
    await shots.capture(
      id: 'phone-dictation-model-missing',
      title: 'Local dictation · model not installed',
      orientation: 'portrait',
      notes:
          'Explicit download/import controls shown; no download is started automatically.',
      boundaryKey: key,
    );
    await shots.capture(
      id: 'phone-dictation-bluetooth-disconnected',
      title: 'Local dictation · Bluetooth disconnected',
      orientation: 'portrait',
      notes:
          'Shows that local dictation needs a connected Bluetooth HID computer before microphone capture.',
      boundaryKey: key,
    );

    await tester.tap(find.byKey(const ValueKey('download-dictation-model')));
    await tester.pumpAndSettle();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    await shots.capture(
      id: 'phone-dictation-download-progress',
      title: 'Local dictation · downloading model',
      orientation: 'portrait',
      notes:
          'Deterministic fake download reports partial byte progress; no network is used.',
      boundaryKey: key,
    );
    manager.completeDownload();
    await tester.pumpAndSettle();
    expect(find.textContaining('Installed'), findsOneWidget);
    await shots.capture(
      id: 'phone-dictation-model-controls',
      title: 'Local dictation · installed model controls',
      orientation: 'portrait',
      notes:
          'Installed local model with explicit recheck, import, and delete controls.',
      boundaryKey: key,
    );

    await tester.tap(find.byKey(const ValueKey('dictation-language')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('English').last);
    await tester.pumpAndSettle();
    expect(find.text('English'), findsOneWidget);
    await shots.capture(
      id: 'phone-dictation-english-language',
      title: 'Local dictation · English recognition language',
      orientation: 'portrait',
      notes:
          'Recognition language selector is independent from app display language.',
      boundaryKey: key,
    );

    await tester.tap(find.byKey(const ValueKey('dictation-model')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cohere Transcribe').last);
    await tester.pumpAndSettle();
    expect(find.text('Cohere Transcribe'), findsOneWidget);
    await shots.capture(
      id: 'phone-dictation-cohere-model',
      title: 'Local dictation · Cohere model choice',
      orientation: 'portrait',
      notes: 'Second pinned model selection with its not-installed state.',
      boundaryKey: key,
    );
    await shots.unmount();

    harness.hid.status.value = HidConnectionStatus.connected;
    manager.readyModels.add(LocalAsrModel.cohere);
    key = await mountPanel();
    final asciiHelp = find.textContaining('printable ASCII key presses');
    await tester.ensureVisible(asciiHelp);
    await tester.pumpAndSettle();
    await shots.capture(
      id: 'phone-dictation-ascii-help',
      title: 'Local dictation · Bluetooth text limits',
      orientation: 'portrait',
      notes:
          'Connected local dictation explains whole-phrase rejection for non-ASCII output and the US keyboard/English input requirement.',
      boundaryKey: key,
    );
    await tester.ensureVisible(find.byKey(const ValueKey('start-dictation')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('dictation-text-profile')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Windows Unicode HexNumpad').last);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('windows-unicode-profile-consent')),
      findsOneWidget,
    );
    await shots.capture(
      id: 'phone-dictation-windows-unicode-consent',
      title: 'Local dictation · Windows Unicode profile setup',
      orientation: 'portrait',
      notes:
          'Explicit opt-in explains manual Windows HexNumpad setup, Num Lock, app compatibility, and whole-phrase rejection boundaries.',
      boundaryKey: key,
    );
    await tester.tap(
      find.byKey(const ValueKey('windows-unicode-consent-confirm')),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('dictation-text-profile')),
    );
    await tester.pumpAndSettle();
    await shots.capture(
      id: 'phone-dictation-windows-unicode-selected',
      title: 'Local dictation · Windows Unicode profile selected',
      orientation: 'portrait',
      notes:
          'User explicitly accepted the profile guidance; selected output mode and manual setup requirements are visible.',
      boundaryKey: key,
    );
    await tester.tap(find.byKey(const ValueKey('start-dictation')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('stop-dictation')), findsOneWidget);
    await shots.capture(
      id: 'phone-dictation-listening',
      title: 'Local dictation · listening',
      orientation: 'portrait',
      notes:
          'Listening state with an in-memory fake audio stream; no microphone hardware is used.',
      boundaryKey: key,
    );
    await tester.tap(find.byKey(const ValueKey('stop-dictation')));
    await tester.pumpAndSettle();
    await shots.unmount();

    key = await mountPanel(allowed: false);
    await tester.tap(find.byKey(const ValueKey('start-dictation')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('dictation-error')), findsOneWidget);
    await shots.capture(
      id: 'phone-dictation-microphone-error',
      title: 'Local dictation · microphone permission error',
      orientation: 'portrait',
      notes:
          'Permission-denied error state rendered with fake capture permission.',
      boundaryKey: key,
    );
  });
}

Widget _app(TestHarness harness, GlobalKey boundaryKey, Widget page) =>
    screenshotBoundary(
      boundaryKey,
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          fontFamilyFallback: ScreenshotSupport.fontFamilyFallback,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF67E8F9),
            brightness: Brightness.dark,
            surface: const Color(0xFF10151D),
          ),
          scaffoldBackgroundColor: const Color(0xFF090D12),
          useMaterial3: true,
        ),
        home: SmartKeysScope(controller: harness.controller, child: page),
      ),
    );

class _ScreenshotModelManager extends ModelManager {
  final Set<LocalAsrModel> readyModels = {};
  Completer<LocalAsrModelFiles>? download;
  LocalAsrModel? downloadingModel;

  @override
  Future<bool> areModelsAvailable({
    LocalAsrModel model = LocalAsrModel.senseVoice,
  }) async => readyModels.contains(model);

  @override
  Future<LocalAsrModelFiles> installedModel(LocalAsrModel model) async =>
      LocalAsrModelFiles(
        model: model,
        modelPath: 'managed/${model.name}/model.onnx',
        tokensPath: 'managed/${model.name}/tokens.txt',
      );

  @override
  Future<LocalAsrModelFiles> prepareModel(
    LocalAsrModel model, {
    void Function(ModelDownloadProgress progress)? onProgress,
  }) {
    downloadingModel = model;
    onProgress?.call(
      ModelDownloadProgress(
        model: model,
        fileName: descriptor(model).primaryModelFile,
        bytesReceived: 64 * 1024 * 1024,
        totalBytes: 200 * 1024 * 1024,
      ),
    );
    download = Completer<LocalAsrModelFiles>();
    return download!.future;
  }

  void completeDownload() {
    final pending = download;
    final model = downloadingModel;
    if (pending == null || pending.isCompleted || model == null) {
      throw StateError('There is no pending screenshot model download.');
    }
    readyModels.add(model);
    pending.complete(
      LocalAsrModelFiles(
        model: model,
        modelPath: 'managed/${model.name}/model.onnx',
        tokensPath: 'managed/${model.name}/tokens.txt',
      ),
    );
  }
}

class _ScreenshotCapture implements DictationCapture {
  StreamController<List<int>> _audio = StreamController<List<int>>.broadcast();
  bool permitted = true;

  @override
  Future<bool> hasPermission() async => permitted;

  @override
  Future<Stream<List<int>>> start() async {
    if (_audio.isClosed) _audio = StreamController<List<int>>.broadcast();
    return _audio.stream;
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {
    if (!_audio.isClosed) await _audio.close();
  }
}

class _ScreenshotRecognizer implements DictationRecognizer {
  @override
  Future<String> transcribe(
    Float32List samples, {
    DictationLanguage? language,
  }) async => 'Screenshot test phrase';

  @override
  Future<void> dispose({bool flush = true}) async {}
}
