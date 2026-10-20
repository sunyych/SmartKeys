import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:local_dictation/local_dictation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'dictation_receiver.dart';

abstract interface class DesktopWindowControl {
  Future<void> hide();
  Future<void> restore();
}

class WindowManagerDesktopWindowControl implements DesktopWindowControl {
  @override
  Future<void> hide() => windowManager.hide();

  @override
  Future<void> restore() async {
    await windowManager.show();
    await windowManager.focus();
  }
}

abstract interface class DesktopDictationSettingsStore {
  Future<String?> getString(String key);
  Future<bool?> getBool(String key);
  Future<void> setString(String key, String value);
  Future<void> setBool(String key, bool value);
}

class SharedPreferencesDictationSettingsStore
    implements DesktopDictationSettingsStore {
  SharedPreferencesDictationSettingsStore({SharedPreferencesAsync? preferences})
    : _providedPreferences = preferences;

  final SharedPreferencesAsync? _providedPreferences;
  late final SharedPreferencesAsync _preferences =
      _providedPreferences ?? SharedPreferencesAsync();

  @override
  Future<String?> getString(String key) => _preferences.getString(key);
  @override
  Future<bool?> getBool(String key) => _preferences.getBool(key);
  @override
  Future<void> setString(String key, String value) =>
      _preferences.setString(key, value);
  @override
  Future<void> setBool(String key, bool value) =>
      _preferences.setBool(key, value);
}

class MemoryDictationSettingsStore implements DesktopDictationSettingsStore {
  final Map<String, Object> values = {};
  @override
  Future<String?> getString(String key) async => values[key] as String?;
  @override
  Future<bool?> getBool(String key) async => values[key] as bool?;
  @override
  Future<void> setString(String key, String value) async => values[key] = value;
  @override
  Future<void> setBool(String key, bool value) async => values[key] = value;
}

/// Desktop preferences and lifecycle around the shared on-device recognizer.
class DesktopDictationService extends ChangeNotifier {
  DesktopDictationService({
    required this.textSink,
    ModelManager? modelManager,
    DictationCapture? capture,
    DictationRecognizerFactory? recognizerFactory,
    DesktopDictationSettingsStore? preferences,
    MethodChannel? channel,
    DesktopWindowControl? windowControl,
  }) : modelManager = modelManager ?? ModelManager(),
       preferences = preferences ?? SharedPreferencesDictationSettingsStore(),
       channel = channel ?? const MethodChannel('lumiakeys/dictation'),
       windowControl = windowControl ?? WindowManagerDesktopWindowControl() {
    controller = LocalDictationController(
      modelManager: this.modelManager,
      capture: capture ?? RecordDictationCapture(),
      recognizerFactory: recognizerFactory ?? _startRecognizer,
      onText: textSink.insertText,
    )..addListener(_changed);
  }

  static const _modelKey = 'lumiakeys.dictation.model.v1';
  static const _languageKey = 'lumiakeys.dictation.language.v1';
  static const _ackKey = 'lumiakeys.dictation.firstUseAcknowledged.v1';
  static const _hotkeyKey = 'lumiakeys.dictation.hotkey.v1';

  final DictationTextSink textSink;
  final ModelManager modelManager;
  final DesktopDictationSettingsStore preferences;
  final MethodChannel channel;
  final DesktopWindowControl windowControl;
  late final LocalDictationController controller;

  bool ready = false;
  bool firstUseAcknowledged = false;
  bool busy = false;
  bool starting = false;
  bool accessibilityGranted = false;
  String hotkey = 'ctrlShiftSpace';
  String? hotkeyError;
  String? operationError;
  ModelDownloadProgress? progress;
  void Function()? onToggleRequested;
  int _startGeneration = 0;
  bool _shutdownStarted = false;
  int _hotkeyGeneration = 0;

  bool get listening => controller.listening;
  String get lastText => controller.lastText;
  String? get error => operationError ?? controller.error;
  LocalAsrModel get model => controller.model;
  DictationLanguage get language => controller.language;

  Future<void> initialize() async {
    if (_shutdownStarted) return;
    final savedModel = await preferences.getString(_modelKey);
    final savedLanguage = await preferences.getString(_languageKey);
    if (_shutdownStarted) return;
    final modelMatches = LocalAsrModel.values.where(
      (v) => v.name == savedModel,
    );
    final languageMatches = DictationLanguage.values.where(
      (v) => v.name == savedLanguage,
    );
    final model = modelMatches.isEmpty ? null : modelMatches.first;
    final language = languageMatches.isEmpty ? null : languageMatches.first;
    if (model != null || language != null) {
      await controller.configure(model: model, language: language);
    }
    firstUseAcknowledged = await preferences.getBool(_ackKey) ?? false;
    hotkey = await preferences.getString(_hotkeyKey) ?? 'ctrlShiftSpace';
    if (_shutdownStarted) return;
    if (Platform.isMacOS || Platform.isWindows) {
      channel.setMethodCallHandler((call) async {
        if (!_shutdownStarted && call.method == 'toggleHotkeyPressed') {
          unawaited(handleToggleHotkeyPressed());
        }
      });
      try {
        await channel.invokeMethod<bool>('registerToggleHotkey', {
          'shortcut': hotkey,
        });
        hotkeyError = null;
      } on PlatformException catch (e) {
        hotkeyError = e.message ?? e.code;
      } catch (e) {
        hotkeyError = '$e';
      }
      if (Platform.isMacOS) await refreshAccessibility();
    }
    ready = true;
    _notify();
  }

  /// Waits for the native shortcut modifiers to be released before toggling.
  /// This keeps the final guarded insertion from seeing Ctrl/Shift still held.
  Future<void> handleToggleHotkeyPressed() async {
    if (_shutdownStarted) return;
    final generation = ++_hotkeyGeneration;
    for (var attempt = 0; attempt < 50; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 40));
      if (_shutdownStarted || generation != _hotkeyGeneration) return;
      try {
        final held = await channel.invokeMethod<bool>('modifiersHeld') ?? true;
        if (!held) {
          onToggleRequested?.call();
          return;
        }
      } catch (e) {
        hotkeyError = 'Could not read held keys: $e';
        _notify();
        return;
      }
    }
    if (!_shutdownStarted && generation == _hotkeyGeneration) {
      hotkeyError = 'Release the shortcut keys before dictation can toggle.';
      _notify();
    }
  }

  Future<void> acknowledgeFirstUse() async {
    if (_shutdownStarted) return;
    firstUseAcknowledged = true;
    await preferences.setBool(_ackKey, true);
    _notify();
  }

  Future<void> configure({
    LocalAsrModel? model,
    DictationLanguage? language,
  }) async {
    if (busy || _shutdownStarted) return;
    final nextModel = model ?? this.model;
    final nextLanguage = language ?? this.language;
    busy = true;
    operationError = null;
    _notify();
    try {
      await controller.configure(model: nextModel, language: nextLanguage);
      await preferences.setString(_modelKey, nextModel.name);
      await preferences.setString(_languageKey, nextLanguage.name);
    } catch (e) {
      operationError = '$e';
      rethrow;
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> start() async {
    if (_shutdownStarted) return;
    if (!firstUseAcknowledged) {
      throw StateError(
        'Review and acknowledge the local dictation explanation first.',
      );
    }
    if (starting || listening) return;
    final generation = ++_startGeneration;
    starting = true;
    busy = true;
    operationError = null;
    _notify();
    try {
      await windowControl.hide();
      final target = await channel.invokeMapMethod<String, Object?>(
        'validateTarget',
      );
      if (target?['status'] != 'ready') {
        throw StateError(
          'Cannot start dictation: ${target?['reason'] ?? 'no safe external target'}',
        );
      }
      if (generation != _startGeneration || _shutdownStarted) return;
      await controller.start();
    } catch (e) {
      operationError = '$e';
      await windowControl.restore();
      rethrow;
    } finally {
      starting = false;
      busy = false;
      _notify();
    }
  }

  Future<void> stop() async {
    if (_shutdownStarted) return;
    if (!listening && !starting) return;
    ++_startGeneration;
    busy = true;
    _notify();
    try {
      await controller.stop();
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> toggle() async {
    if (listening || starting) {
      await stop();
    } else if (firstUseAcknowledged) {
      try {
        await start();
      } catch (_) {
        // The error is retained for the settings screen and the window is
        // restored when microphone/model setup fails.
      }
    } else {
      onToggleRequested?.call();
    }
  }

  Future<void> installModel() async {
    if (busy || listening || _shutdownStarted) return;
    busy = true;
    operationError = null;
    progress = null;
    _notify();
    try {
      await controller.releaseRecognizer();
      await modelManager.prepareModel(
        model,
        onProgress: (value) {
          progress = value;
          _notify();
        },
      );
    } catch (e) {
      operationError = '$e';
      rethrow;
    } finally {
      progress = null;
      busy = false;
      _notify();
    }
  }

  Future<void> importModel() async {
    if (busy || listening || _shutdownStarted) return;
    final path = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Choose a folder containing the verified model files',
    );
    if (path == null) return;
    busy = true;
    operationError = null;
    _notify();
    try {
      await controller.releaseRecognizer();
      await modelManager.importModel(model, Directory(path));
    } catch (e) {
      operationError = '$e';
      rethrow;
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> deleteModel(LocalAsrModel target) async {
    if (busy || listening || _shutdownStarted) return;
    busy = true;
    operationError = null;
    _notify();
    try {
      await controller.deleteModel(target);
    } catch (e) {
      operationError = '$e';
      rethrow;
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<bool> modelAvailable([LocalAsrModel? target]) =>
      modelManager.areModelsAvailable(model: target ?? model);

  Future<void> setHotkey(String value) async {
    if (_shutdownStarted) return;
    hotkeyError = null;
    try {
      await channel.invokeMethod<bool>('registerToggleHotkey', {
        'shortcut': value,
      });
      hotkey = value;
      await preferences.setString(_hotkeyKey, value);
    } on PlatformException catch (e) {
      hotkeyError = e.message ?? e.code;
    } catch (e) {
      hotkeyError = '$e';
    }
    _notify();
  }

  Future<void> refreshAccessibility() async {
    if (!Platform.isMacOS || _shutdownStarted) return;
    try {
      accessibilityGranted =
          await channel.invokeMethod<bool>('accessibilityStatus') ?? false;
    } catch (_) {
      accessibilityGranted = false;
    }
    _notify();
  }

  Future<void> requestAccessibility() async {
    if (!Platform.isMacOS || _shutdownStarted) return;
    try {
      accessibilityGranted =
          await channel.invokeMethod<bool>('requestAccessibilityPermission') ??
          false;
    } catch (_) {
      accessibilityGranted = false;
    }
    _notify();
  }

  Future<void> openAccessibilitySettings() =>
      channel.invokeMethod<void>('openAccessibilitySettings');

  static Future<DictationRecognizer> _startRecognizer(
    LocalAsrModelFiles files,
    DictationLanguage language,
  ) => LocalAsrWorker.start(
    model: files,
    language: language,
    numThreads: 2,
    nativeDirectory: Platform.isWindows
        ? File(Platform.resolvedExecutable).parent.path
        : null,
  );

  void _changed() => _notify();

  void _notify() {
    if (!_shutdownStarted) notifyListeners();
  }

  Future<void> shutdown() async {
    if (_shutdownStarted) return;
    _shutdownStarted = true;
    ++_hotkeyGeneration;
    modelManager.cancelDownload();
    channel.setMethodCallHandler(null);
    try {
      await channel.invokeMethod<void>('unregisterToggleHotkey');
    } catch (_) {}
    controller.removeListener(_changed);
    await controller.close();
    controller.dispose();
  }

  @override
  void dispose() {
    unawaited(shutdown());
    super.dispose();
  }
}
