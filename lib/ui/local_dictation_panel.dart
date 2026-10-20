import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:local_dictation/local_dictation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../services/companion_service.dart';
import 'dictation_entry_consent.dart';

const _modelPreferenceKey = 'dictation.model.v1';
const _languagePreferenceKey = 'dictation.language.v1';

Future<void> showLocalDictationPanel(
  BuildContext context, {
  required CompanionService companion,
}) async {
  if (!await ensureDictationEntryExplained(context) || !context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (_) =>
        LocalDictationPanel(companion: companion, autoStartWhenReady: true),
  );
}

class LocalDictationPanel extends StatefulWidget {
  const LocalDictationPanel({
    super.key,
    required this.companion,
    this.autoStartWhenReady = false,
    this.modelManager,
    this.capture,
    this.recognizerFactory,
    this.enableWakeLock = WakelockPlus.enable,
    this.disableWakeLock = WakelockPlus.disable,
  });

  final CompanionService companion;
  final bool autoStartWhenReady;
  final ModelManager? modelManager;
  final DictationCapture? capture;
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
  LocalAsrModel _model = LocalAsrModel.senseVoice;
  DictationLanguage _language = DictationLanguage.chinese;
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
  String? _sessionId;
  CompanionHost? _sessionHost;
  int _sequence = 0;
  String? _panelError;

  bool get _desktopReady {
    final host = widget.companion.activeHost.value;
    return host != null &&
        host.capabilities.contains('local-dictation-v1') &&
        widget.companion.syncStatus.value == CompanionSyncStatus.ready;
  }

  bool get _sessionHostValid {
    final host = _currentHost;
    return host != null &&
        host.capabilities.contains('local-dictation-v1') &&
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
    _dictation = LocalDictationController(
      modelManager: _models,
      capture: _capture,
      recognizerFactory:
          widget.recognizerFactory ??
          (model, language) =>
              LocalAsrWorker.start(model: model, language: language),
      onText: _deliverText,
    );
    widget.companion.activeHost.addListener(_handleConnectionChanged);
    widget.companion.syncStatus.addListener(_handleConnectionChanged);
    _dictation.addListener(_handleDictationChanged);
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final modelName = preferences.getString(_modelPreferenceKey);
      final languageName = preferences.getString(_languagePreferenceKey);
      final model = LocalAsrModel.values.firstWhere(
        (value) => value.name == modelName,
        orElse: () => LocalAsrModel.senseVoice,
      );
      final language = DictationLanguage.values.firstWhere(
        (value) => value.name == languageName,
        orElse: () => DictationLanguage.chinese,
      );
      await _dictation.configure(model: model, language: language);
      final permission = await _capture.hasPermission();
      final ready = await _models.areModelsAvailable(model: model);
      if (!mounted) return;
      setState(() {
        _model = model;
        _language = language;
        _permissionGranted = permission;
        _modelReady = ready;
        _initialized = true;
      });
      if (widget.autoStartWhenReady && ready && _desktopReady && _appResumed) {
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
    final sessionId = _sessionId;
    final sessionHost = _sessionHost;
    if (sessionId == null || !_sameHostIdentity(sessionHost, _currentHost)) {
      throw StateError('Dictation session has ended or its desktop changed.');
    }
    await widget.companion.sendDictation(
      sessionId: sessionId,
      sequence: ++_sequence,
      text: text,
    );
  }

  void _handleConnectionChanged() {
    if (_sessionInProgress && !_sessionHostValid) {
      unawaited(_cancelForLostConnection());
    }
    if (mounted) setState(() {});
  }

  CompanionHost? get _currentHost => widget.companion.activeHost.value;

  bool _sameHostIdentity(CompanionHost? first, CompanionHost? second) =>
      first != null &&
      second != null &&
      first.address == second.address &&
      first.port == second.port &&
      first.token == second.token;

  void _handleDictationChanged() {
    if (mounted) setState(() {});
    if (_sessionId != null &&
        !_starting &&
        !_stopping &&
        !_dictation.listening &&
        !_dictation.busy &&
        _wakeLockHeld) {
      unawaited(_releaseAfterUnexpectedStop());
    }
  }

  Future<void> _releaseAfterUnexpectedStop() async {
    if (_sessionId == null ||
        _starting ||
        _stopping ||
        _dictation.listening ||
        _dictation.busy) {
      return;
    }
    _sessionId = null;
    _sessionHost = null;
    _wakeLockHeld = false;
    await widget.disableWakeLock?.call();
    if (mounted) setState(() {});
  }

  Future<void> _cancelForLostConnection() async {
    await _cancelCurrentSession();
    if (mounted) {
      setState(() => _panelError = 'Desktop disconnected. Dictation stopped.');
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
    _sessionId = null;
    _sessionHost = null;
    await _dictation.cancel();
    _wakeLockHeld = false;
    await widget.disableWakeLock?.call();
  }

  Future<void> _start() async {
    setState(() => _panelError = null);
    if (!_desktopReady) {
      setState(
        () => _panelError = 'Connect to a compatible LumiaKeys Desktop first.',
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
      _sessionId = _newSessionId();
      _sequence = 0;
      await _dictation.start();
      if (!_canStartGeneration(generation)) {
        await _dictation.cancel();
        return;
      }
      await widget.enableWakeLock?.call();
      if (!_canStartGeneration(generation) || !_dictation.listening) {
        await _dictation.cancel();
        await widget.disableWakeLock?.call();
        if (generation == _startGeneration) {
          _sessionId = null;
          _sessionHost = null;
        }
        return;
      }
      _wakeLockHeld = true;
      if (mounted) setState(() {});
    } catch (error) {
      await _dictation.cancel();
      if (generation == _startGeneration) {
        _sessionId = null;
        _sessionHost = null;
      }
      _wakeLockHeld = false;
      await widget.disableWakeLock?.call();
      if (mounted) setState(() => _panelError = '$error');
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

  String _newSessionId() {
    final bytes = List<int>.generate(24, (_) => Random.secure().nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  Future<void> _stop() async {
    _stopping = true;
    try {
      await _dictation.stop();
    } catch (error) {
      if (mounted) setState(() => _panelError = '$error');
    } finally {
      _sessionId = null;
      _sessionHost = null;
      _wakeLockHeld = false;
      await widget.disableWakeLock?.call();
      _stopping = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _selectModel(LocalAsrModel? model) async {
    if (model == null || model == _model) return;
    try {
      await _dictation.configure(model: model);
      _sessionId = null;
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
      await _dictation.configure(language: language);
      _sessionId = null;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_languagePreferenceKey, language.name);
      if (mounted) setState(() => _language = language);
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

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.companion.activeHost.removeListener(_handleConnectionChanged);
    widget.companion.syncStatus.removeListener(_handleConnectionChanged);
    _dictation.removeListener(_handleDictationChanged);
    _models.cancelDownload();
    unawaited(_dictation.close().whenComplete(_dictation.dispose));
    unawaited(widget.disableWakeLock?.call());
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
                      (_desktopReady ||
                              (_sessionInProgress && _sessionHostValid))
                          ? 'Connected desktop · text only'
                          : 'Compatible desktop required',
                      key: const ValueKey('dictation-connection-status'),
                      style: TextStyle(
                        color: _desktopReady
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
