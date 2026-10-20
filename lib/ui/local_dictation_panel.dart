import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:local_dictation/local_dictation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../services/hid_service.dart';
import '../services/hid_text_output_service.dart';
import 'dictation_entry_consent.dart';

const _modelPreferenceKey = 'dictation.model.v1';
const _languagePreferenceKey = 'dictation.language.v1';
const _textProfilePreferenceKey = 'dictation.text_profile.v1';

Future<void> showLocalDictationPanel(
  BuildContext context, {
  required HidService hid,
}) async {
  if (!await ensureDictationEntryExplained(context) || !context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (_) => LocalDictationPanel(hid: hid, autoStartWhenReady: true),
  );
}

class LocalDictationPanel extends StatefulWidget {
  const LocalDictationPanel({
    super.key,
    required this.hid,
    this.autoStartWhenReady = false,
    this.modelManager,
    this.capture,
    this.textOutput,
    this.recognizerFactory,
    this.enableWakeLock = WakelockPlus.enable,
    this.disableWakeLock = WakelockPlus.disable,
  });

  final HidService hid;
  final bool autoStartWhenReady;
  final ModelManager? modelManager;
  final DictationCapture? capture;
  final HidTextOutputService? textOutput;
  final Future<DictationRecognizer> Function(
    LocalAsrModelFiles,
    DictationLanguage,
  )?
  recognizerFactory;
  final Future<void> Function()? enableWakeLock;
  final Future<void> Function()? disableWakeLock;

  @override
  State<LocalDictationPanel> createState() => _LocalDictationPanelState();
}

class _LocalDictationPanelState extends State<LocalDictationPanel>
    with WidgetsBindingObserver {
  late final ModelManager _models;
  late final LocalDictationController _dictation;
  late final DictationCapture _capture;
  late final HidTextOutputService _textOutput;
  late final bool _ownsTextOutput;
  LocalAsrModel _model = LocalAsrModel.senseVoice;
  DictationLanguage _language = DictationLanguage.chinese;
  HidTextProfile _textProfile = HidTextProfile.usAscii;
  bool _initialized = false;
  bool _modelReady = false;
  bool _permissionGranted = false;
  bool _downloading = false;
  bool _appResumed = true;
  bool _starting = false;
  bool _stopping = false;
  bool _wakeLockHeld = false;
  int _startGeneration = 0;
  ModelDownloadProgress? _progress;
  HidTextOutputSession? _textSession;
  HidHost? _sessionHost;
  String? _panelError;

  bool get _hidReady {
    final host = widget.hid.activeHost.value;
    return widget.hid.connectionStatus.value == HidConnectionStatus.connected &&
        host != null &&
        host.address.isNotEmpty;
  }

  bool get _sessionHostValid {
    final host = _currentHost;
    return widget.hid.connectionStatus.value == HidConnectionStatus.connected &&
        host != null &&
        _sameHostIdentity(_sessionHost, host);
  }

  bool get _sessionInProgress =>
      _starting || _stopping || _dictation.listening || _dictation.busy;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _models = widget.modelManager ?? ModelManager();
    _capture = widget.capture ?? RecordDictationCapture();
    _ownsTextOutput = widget.textOutput == null;
    _textOutput = widget.textOutput ?? HidTextOutputService(hid: widget.hid);
    _dictation = LocalDictationController(
      modelManager: _models,
      capture: _capture,
      recognizerFactory:
          widget.recognizerFactory ??
          (model, language) =>
              LocalAsrWorker.start(model: model, language: language),
      onText: _deliverText,
    );
    widget.hid.activeHost.addListener(_handleConnectionChanged);
    widget.hid.connectionStatus.addListener(_handleConnectionChanged);
    _dictation.addListener(_handleDictationChanged);
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final modelName = preferences.getString(_modelPreferenceKey);
      final languageName = preferences.getString(_languagePreferenceKey);
      final profileName = preferences.getString(_textProfilePreferenceKey);
      final model = LocalAsrModel.values.firstWhere(
        (value) => value.name == modelName,
        orElse: () => LocalAsrModel.senseVoice,
      );
      final language = DictationLanguage.values.firstWhere(
        (value) => value.name == languageName,
        orElse: () => DictationLanguage.chinese,
      );
      final profile = HidTextProfile.values.firstWhere(
        (value) => value.wireName == profileName,
        orElse: () => HidTextProfile.usAscii,
      );
      await _dictation.configure(model: model, language: language);
      final permission = await _capture.hasPermission();
      final ready = await _models.areModelsAvailable(model: model);
      if (!mounted) return;
      setState(() {
        _model = model;
        _language = language;
        _textProfile = profile;
        _permissionGranted = permission;
        _modelReady = ready;
        _initialized = true;
      });
      if (widget.autoStartWhenReady && ready && _hidReady && _appResumed) {
        unawaited(_start());
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _initialized = true;
        _panelError = 'Dictation could not initialize: $error';
      });
    }
  }

  Future<void> _deliverText(String text) async {
    final session = _textSession;
    if (session == null || !_sessionHostValid) {
      throw StateError(
        'Dictation session has ended or its Bluetooth host changed.',
      );
    }
    await _textOutput.sendText(session, text);
  }

  void _handleConnectionChanged() {
    if (_sessionHost != null && _sessionInProgress && !_sessionHostValid) {
      unawaited(_cancelForLostConnection());
    }
    if (mounted) setState(() {});
  }

  HidHost? get _currentHost => widget.hid.activeHost.value;

  bool _sameHostIdentity(HidHost? first, HidHost? second) =>
      first != null && second != null && first.address == second.address;

  void _handleDictationChanged() {
    if (mounted) setState(() {});
    if (_textSession != null &&
        !_starting &&
        !_stopping &&
        !_dictation.listening &&
        !_dictation.busy &&
        _wakeLockHeld) {
      unawaited(_releaseAfterUnexpectedStop());
    }
  }

  Future<void> _releaseAfterUnexpectedStop() async {
    final session = _textSession;
    if (session == null ||
        _starting ||
        _stopping ||
        _dictation.listening ||
        _dictation.busy) {
      return;
    }
    _textSession = null;
    _sessionHost = null;
    final cleanupError = await _cleanupSession(
      session: session,
      cancelCapture: false,
    );
    if (mounted) {
      setState(() {
        if (cleanupError != null) _panelError = '$cleanupError';
      });
    }
  }

  Future<void> _cancelForLostConnection() async {
    await _cancelCurrentSession();
    if (mounted) {
      setState(
        () => _panelError = 'Bluetooth host disconnected. Dictation stopped.',
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appResumed = state == AppLifecycleState.resumed;
    if (!_appResumed && _sessionInProgress) {
      unawaited(_cancelForBackground());
    }
  }

  Future<void> _cancelForBackground() async {
    await _cancelCurrentSession();
  }

  Future<void> _cancelCurrentSession() async {
    ++_startGeneration;
    _starting = false;
    final session = _textSession;
    _textSession = null;
    _sessionHost = null;
    final cleanupError = await _cleanupSession(
      session: session,
      cancelCapture: true,
    );
    if (cleanupError != null && mounted) {
      setState(() => _panelError = '$cleanupError');
    }
  }

  Future<Object?> _cleanupSession({
    required HidTextOutputSession? session,
    required bool cancelCapture,
  }) async {
    Object? cleanupError;
    if (session != null) {
      try {
        await _textOutput.cancelSession(session);
      } catch (error) {
        cleanupError = error;
      }
    }
    if (cancelCapture) {
      try {
        await _dictation.cancel();
      } catch (error) {
        cleanupError ??= error;
      }
    }
    _wakeLockHeld = false;
    try {
      await widget.disableWakeLock?.call();
    } catch (error) {
      cleanupError ??= error;
    }
    return cleanupError;
  }

  Future<void> _start() async {
    setState(() => _panelError = null);
    if (!_hidReady) {
      setState(
        () => _panelError =
            'Connect this phone to a computer over Bluetooth HID first.',
      );
      return;
    }
    final generation = ++_startGeneration;
    _starting = true;
    _sessionHost = _currentHost;
    try {
      final permitted = await _capture.hasPermission();
      if (!_canStartGeneration(generation)) return;
      if (!permitted) {
        setState(() {
          _permissionGranted = false;
          _panelError = 'Microphone permission is needed for local dictation.';
        });
        return;
      }
      _permissionGranted = true;
      if (!_modelReady) {
        setState(
          () => _panelError = 'Download or import this model before starting.',
        );
        return;
      }
      _textSession = _textOutput.beginSession(profile: _textProfile);
      await _dictation.start();
      if (!_canStartGeneration(generation)) {
        final session = _textSession;
        _textSession = null;
        if (session != null) await _textOutput.cancelSession(session);
        await _dictation.cancel();
        return;
      }
      await widget.enableWakeLock?.call();
      if (!_canStartGeneration(generation) || !_dictation.listening) {
        await _dictation.cancel();
        await widget.disableWakeLock?.call();
        if (generation == _startGeneration) {
          final session = _textSession;
          _textSession = null;
          _sessionHost = null;
          if (session != null) await _textOutput.cancelSession(session);
        }
        return;
      }
      _wakeLockHeld = true;
      if (mounted) setState(() {});
    } catch (error) {
      final session = _textSession;
      _textSession = null;
      final cleanupError = await _cleanupSession(
        session: session,
        cancelCapture: true,
      );
      if (generation == _startGeneration) {
        _sessionHost = null;
      }
      if (mounted) {
        setState(
          () => _panelError = cleanupError == null
              ? '$error'
              : '$error (cleanup failed: $cleanupError)',
        );
      }
    } finally {
      if (generation == _startGeneration) {
        _starting = false;
        if (!_dictation.listening && !_dictation.busy) {
          _sessionHost = null;
        }
      }
      if (mounted) setState(() {});
    }
  }

  bool _canStartGeneration(int generation) =>
      mounted &&
      _appResumed &&
      _sessionHostValid &&
      generation == _startGeneration;

  Future<void> _stop() async {
    _stopping = true;
    try {
      await _dictation.stop();
    } catch (error) {
      if (mounted) setState(() => _panelError = '$error');
    } finally {
      final session = _textSession;
      _textSession = null;
      _sessionHost = null;
      if (session != null) {
        try {
          await _textOutput.cancelSession(session);
        } catch (error) {
          if (mounted) setState(() => _panelError = '$error');
        }
      }
      _wakeLockHeld = false;
      try {
        await widget.disableWakeLock?.call();
      } catch (error) {
        if (mounted) setState(() => _panelError = '$error');
      } finally {
        _stopping = false;
      }
      if (mounted) setState(() {});
    }
  }

  Future<void> _selectModel(LocalAsrModel? model) async {
    if (model == null || model == _model) return;
    try {
      await _cancelOutputSession();
      await _dictation.configure(model: model);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_modelPreferenceKey, model.name);
      final ready = await _models.areModelsAvailable(model: model);
      if (!mounted) return;
      setState(() {
        _model = model;
        _modelReady = ready;
        _panelError = null;
      });
    } catch (error) {
      if (mounted) setState(() => _panelError = '$error');
    }
  }

  Future<void> _selectLanguage(DictationLanguage? language) async {
    if (language == null || language == _language) return;
    try {
      await _cancelOutputSession();
      await _dictation.configure(language: language);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_languagePreferenceKey, language.name);
      if (mounted) setState(() => _language = language);
    } catch (error) {
      if (mounted) setState(() => _panelError = '$error');
    }
  }

  Future<void> _selectTextProfile(HidTextProfile? profile) async {
    if (profile == null || profile == _textProfile) return;
    if (profile == HidTextProfile.windowsHexNumpad) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          key: const ValueKey('windows-unicode-profile-consent'),
          title: const Text('Use Windows Unicode HexNumpad'),
          content: const SingleChildScrollView(
            child: Text(
              'This profile types printable BMP text, including Chinese, Japanese, Korean, and ASCII, through Bluetooth HID. It does not change Windows settings. Before use, enable HKCU\\Control Panel\\Input Method\\EnableHexNumpad as a REG_SZ value of 1, then sign out and back in or restart Windows. Keep Num Lock on and use a tested-compatible foreground app. Emoji, controls, and non-BMP characters are rejected as a whole phrase.',
            ),
          ),
          actions: [
            TextButton(
              key: const ValueKey('windows-unicode-consent-cancel'),
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const ValueKey('windows-unicode-consent-confirm'),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Use Windows Unicode'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    try {
      await _cancelOutputSession();
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(_textProfilePreferenceKey, profile.wireName);
      if (mounted) {
        setState(() {
          _textProfile = profile;
          _panelError = null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _panelError = '$error');
    }
  }

  Future<void> _downloadModel() async {
    setState(() {
      _downloading = true;
      _progress = null;
      _panelError = null;
    });
    try {
      await _dictation.releaseRecognizer();
      await _models.prepareModel(
        _model,
        onProgress: (value) {
          if (mounted) setState(() => _progress = value);
        },
      );
      if (mounted) setState(() => _modelReady = true);
    } catch (error) {
      if (mounted) {
        setState(() => _panelError = 'Model download failed: $error');
      }
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  Future<void> _importModel() async {
    try {
      final path = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Choose the folder containing the model files',
      );
      if (path == null) return;
      await _dictation.releaseRecognizer();
      await _models.importModel(_model, Directory(path));
      if (mounted) setState(() => _modelReady = true);
    } catch (error) {
      if (mounted) setState(() => _panelError = 'Model import failed: $error');
    }
  }

  Future<void> _deleteModel() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete local model?'),
        content: Text('Delete ${_model.label} files from this phone?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      if (_dictation.listening) await _stop();
      await _dictation.cancel();
      await _dictation.deleteModel(_model);
      if (mounted) setState(() => _modelReady = false);
    } catch (error) {
      if (mounted) {
        setState(() => _panelError = 'Model could not be deleted: $error');
      }
    }
  }

  Future<void> _cancelOutputSession() async {
    final session = _textSession;
    _textSession = null;
    if (session != null) await _textOutput.cancelSession(session);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.hid.activeHost.removeListener(_handleConnectionChanged);
    widget.hid.connectionStatus.removeListener(_handleConnectionChanged);
    _dictation.removeListener(_handleDictationChanged);
    _models.cancelDownload();
    final session = _textSession;
    _textSession = null;
    if (session != null) {
      unawaited(_textOutput.cancelSession(session).catchError((Object _) {}));
    }
    if (_ownsTextOutput) _textOutput.dispose();
    unawaited(
      _dictation
          .close()
          .whenComplete(_dictation.dispose)
          .catchError((Object _) {}),
    );
    unawaited(widget.disableWakeLock?.call().catchError((Object _) {}));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final listening = _dictation.listening;
    final descriptor = _models.descriptor(_model);
    final modelBytes = descriptor.files.fold<int>(
      0,
      (sum, file) => sum + file.sizeBytes,
    );
    return Dialog(
      key: const ValueKey('local-dictation-panel'),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 660),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: !_initialized
              ? const SizedBox(
                  height: 180,
                  child: Center(child: CircularProgressIndicator()),
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.mic_external_on),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'Local quick dictation',
                            style: TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        IconButton(
                          key: const ValueKey('close-dictation-panel'),
                          tooltip: 'Close dictation panel',
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      (_hidReady || (_sessionInProgress && _sessionHostValid))
                          ? 'Connected by Bluetooth · text only'
                          : 'Bluetooth HID connection required',
                      key: const ValueKey('dictation-connection-status'),
                      style: TextStyle(
                        color: _hidReady
                            ? Colors.lightGreenAccent
                            : Colors.amberAccent,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Flexible(
                      fit: FlexFit.loose,
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              _textProfile == HidTextProfile.usAscii
                                  ? 'Text is typed as printable ASCII key presses over Bluetooth HID. Chinese and other non-ASCII results are rejected as a whole phrase. Keep the target computer on a US keyboard layout with English input active.'
                                  : 'Windows Unicode HexNumpad types printable BMP text, including Chinese, Japanese, Korean, and ASCII. Enable the Windows HexNumpad setting shown below, keep Num Lock on, and use a tested-compatible foreground app. Unsupported text is rejected as a whole phrase.',
                              key: const ValueKey('dictation-output-limit'),
                            ),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<DictationLanguage>(
                              key: const ValueKey('dictation-language'),
                              initialValue: _language,
                              decoration: const InputDecoration(
                                labelText: 'Recognition language',
                              ),
                              items: DictationLanguage.values
                                  .map(
                                    (language) => DropdownMenuItem(
                                      value: language,
                                      child: Text(language.label),
                                    ),
                                  )
                                  .toList(),
                              onChanged: listening || _dictation.busy
                                  ? null
                                  : _selectLanguage,
                            ),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<LocalAsrModel>(
                              key: const ValueKey('dictation-model'),
                              initialValue: _model,
                              decoration: const InputDecoration(
                                labelText: 'Local model',
                              ),
                              items: LocalAsrModel.values
                                  .map(
                                    (model) => DropdownMenuItem(
                                      value: model,
                                      child: Text(model.label),
                                    ),
                                  )
                                  .toList(),
                              onChanged:
                                  listening || _dictation.busy || _downloading
                                  ? null
                                  : _selectModel,
                            ),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<HidTextProfile>(
                              key: const ValueKey('dictation-text-profile'),
                              initialValue: _textProfile,
                              decoration: const InputDecoration(
                                labelText: 'Text output profile',
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: HidTextProfile.usAscii,
                                  child: Text('US ASCII (default)'),
                                ),
                                DropdownMenuItem(
                                  value: HidTextProfile.windowsHexNumpad,
                                  child: Text('Windows Unicode HexNumpad'),
                                ),
                              ],
                              onChanged:
                                  listening || _dictation.busy || _downloading
                                  ? null
                                  : _selectTextProfile,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _textProfile == HidTextProfile.usAscii
                                  ? 'Printable ASCII only. Use a US keyboard layout with English input active.'
                                  : 'Printable BMP text, including Chinese. Windows HexNumpad must be enabled; Num Lock must be on.',
                              key: const ValueKey(
                                'dictation-text-profile-help',
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '${_modelReady ? 'Installed' : 'Not installed'} · ${(modelBytes / (1024 * 1024)).ceil()} MB',
                            ),
                            if (_downloading) ...[
                              const SizedBox(height: 8),
                              LinearProgressIndicator(
                                value: _progress?.fraction,
                              ),
                              if (_progress case final progress?)
                                Text(
                                  '${progress.fileName} · ${(progress.bytesReceived / (1024 * 1024)).toStringAsFixed(1)} MB',
                                ),
                            ],
                            Wrap(
                              spacing: 8,
                              children: [
                                TextButton.icon(
                                  key: const ValueKey(
                                    'download-dictation-model',
                                  ),
                                  onPressed:
                                      _downloading ||
                                          listening ||
                                          _dictation.busy
                                      ? null
                                      : _downloadModel,
                                  icon: const Icon(Icons.download),
                                  label: Text(
                                    _modelReady
                                        ? 'Check / download'
                                        : 'Download',
                                  ),
                                ),
                                TextButton.icon(
                                  key: const ValueKey('import-dictation-model'),
                                  onPressed:
                                      _downloading ||
                                          listening ||
                                          _dictation.busy
                                      ? null
                                      : _importModel,
                                  icon: const Icon(Icons.folder_open),
                                  label: const Text('Import'),
                                ),
                                TextButton.icon(
                                  key: const ValueKey('delete-dictation-model'),
                                  onPressed:
                                      _modelReady &&
                                          !_downloading &&
                                          !listening &&
                                          !_dictation.busy
                                      ? _deleteModel
                                      : null,
                                  icon: const Icon(Icons.delete_outline),
                                  label: const Text('Delete'),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Icon(
                                  _permissionGranted
                                      ? Icons.mic
                                      : Icons.mic_off,
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _permissionGranted
                                        ? 'Microphone permission available'
                                        : 'Microphone permission required',
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            if (_panelError != null || _dictation.error != null)
                              Text(
                                _panelError ?? _dictation.error!,
                                key: const ValueKey('dictation-error'),
                                style: const TextStyle(color: Colors.redAccent),
                              ),
                            if (_dictation.lastText.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxHeight: 90,
                                ),
                                child: SingleChildScrollView(
                                  child: SelectableText(
                                    _dictation.lastText,
                                    key: const ValueKey('dictation-last-text'),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      key: ValueKey(
                        listening ? 'stop-dictation' : 'start-dictation',
                      ),
                      onPressed: _dictation.busy || _downloading || _starting
                          ? null
                          : listening
                          ? _stop
                          : _start,
                      icon: Icon(
                        listening
                            ? Icons.stop_circle_outlined
                            : Icons.mic_external_on,
                      ),
                      label: Text(
                        listening ? 'Stop dictation' : 'Start dictation',
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Audio is processed on this phone and is never sent or saved.',
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
