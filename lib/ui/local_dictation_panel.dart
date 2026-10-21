import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_dictation/local_dictation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../services/companion_service.dart';
import '../services/hid_service.dart';
import '../services/hid_text_output_service.dart';
import 'dictation_entry_consent.dart';
import 'local_dictation_route_observer.dart';

const _modelPreferenceKey = 'dictation.model.v1';
const _languagePreferenceKey = 'dictation.language.v1';
const _legacyTextProfilePreferenceKey = 'dictation.text_profile.v1';
const _desktopLanguagePreferenceKey = 'dictation.desktop_language.v1';
const _outputModePreferenceKey = 'dictation.output_mode.v1';

enum DictationOutputMode { bluetoothEnglish, desktopMultilingual }

const _desktopDictationCapability = 'local-dictation-v1';
int _nextDictationSession = 0;

class LocalDictationEntryButton extends StatefulWidget {
  const LocalDictationEntryButton({
    super.key,
    required this.hid,
    this.companion,
    this.modelManager,
    this.capture,
    this.recognizerFactory,
    this.enableWakeLock = WakelockPlus.enable,
    this.disableWakeLock = WakelockPlus.disable,
  });

  final HidService hid;
  final CompanionService? companion;
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
  State<LocalDictationEntryButton> createState() =>
      _LocalDictationEntryButtonState();
}

class _LocalDictationEntryButtonState extends State<LocalDictationEntryButton>
    with RouteAware {
  LocalHistoryEntry? _historyEntry;
  PageRoute<dynamic>? _route;
  bool _opening = false;
  bool _entryVisible = false;
  bool _autoStartCurrentEntry = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (identical(route, _route)) return;
    if (_route != null) localDictationRouteObserver.unsubscribe(this);
    _route = route is PageRoute<dynamic> ? route : null;
    if (_route case final route?) {
      localDictationRouteObserver.subscribe(this, route);
    }
  }

  @override
  void didPushNext() {
    _removeEntry();
  }

  Future<void> _open({required bool autoStart}) async {
    if (_opening || _entryVisible) return;
    _opening = true;
    try {
      if (!await ensureDictationEntryExplained(context) ||
          !mounted ||
          (_route != null && !_route!.isCurrent)) {
        return;
      }
      final route = _route;
      if (route != null) {
        late final LocalHistoryEntry historyEntry;
        historyEntry = LocalHistoryEntry(
          onRemove: () => _handleHistoryRemoval(historyEntry),
        );
        _historyEntry = historyEntry;
        route.addLocalHistoryEntry(historyEntry);
      }
      setState(() {
        _entryVisible = true;
        _autoStartCurrentEntry = autoStart;
      });
    } finally {
      _opening = false;
    }
  }

  void _dismissEntry() {
    if (!_entryVisible && _historyEntry == null) return;
    _entryVisible = false;
    final historyEntry = _historyEntry;
    _historyEntry = null;
    historyEntry?.remove();
    if (mounted) setState(() {});
  }

  void _handleHistoryRemoval(LocalHistoryEntry? historyEntry) {
    if (!identical(_historyEntry, historyEntry)) return;
    _historyEntry = null;
    _entryVisible = false;
    if (mounted) setState(() {});
  }

  void _removeEntry() {
    _dismissEntry();
  }

  @override
  void dispose() {
    localDictationRouteObserver.unsubscribe(this);
    _route = null;
    final historyEntry = _historyEntry;
    _historyEntry = null;
    _entryVisible = false;
    historyEntry?.remove();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      Positioned(
        top: 7,
        right: 142,
        child: Tooltip(
          triggerMode: TooltipTriggerMode.manual,
          message:
              'Tap to quick-start with the selected output · hold for output and language options',
          child: Semantics(
            button: true,
            label: 'Local quick dictation',
            hint:
                'Tap to quick-start with the selected output; hold to choose Bluetooth English or multilingual LumiaKey Desktop output. Speech stays on this phone.',
            child: IconButton.filledTonal(
              key: const ValueKey('local-quick-output'),
              tooltip: null,
              visualDensity: VisualDensity.compact,
              onPressed: () => _open(autoStart: true),
              onLongPress: () => _open(autoStart: false),
              icon: const Icon(Icons.mic_external_on),
            ),
          ),
        ),
      ),
      if (_entryVisible)
        Positioned.fill(
          child: LocalDictationPanel(
            hid: widget.hid,
            companion: widget.companion,
            autoStartWhenReady: _autoStartCurrentEntry,
            autoCollapseWhileListening: true,
            modelManager: widget.modelManager,
            capture: widget.capture,
            recognizerFactory: widget.recognizerFactory,
            enableWakeLock: widget.enableWakeLock,
            disableWakeLock: widget.disableWakeLock,
            onDismiss: _dismissEntry,
          ),
        ),
    ],
  );
}

class LocalDictationPanel extends StatefulWidget {
  const LocalDictationPanel({
    super.key,
    required this.hid,
    this.companion,
    this.autoStartWhenReady = false,
    this.autoCollapseWhileListening = false,
    this.onDismiss,
    this.modelManager,
    this.capture,
    this.textOutput,
    this.recognizerFactory,
    this.enableWakeLock = WakelockPlus.enable,
    this.disableWakeLock = WakelockPlus.disable,
  });

  final HidService hid;
  final CompanionService? companion;
  final bool autoStartWhenReady;
  final bool autoCollapseWhileListening;
  final VoidCallback? onDismiss;
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
  DictationOutputMode _outputMode = DictationOutputMode.bluetoothEnglish;
  DictationLanguage _language = DictationLanguage.english;
  DictationLanguage _desktopLanguage = DictationLanguage.chinese;
  bool _initialized = false;
  bool _modelReady = false;
  bool _permissionGranted = false;
  bool _downloading = false;
  bool _appResumed = true;
  bool _starting = false;
  bool _stopping = false;
  bool _cancelling = false;
  bool _configuring = false;
  bool _wakeLockHeld = false;
  int _startGeneration = 0;
  ModelDownloadProgress? _progress;
  HidTextOutputSession? _textSession;
  HidHost? _sessionHost;
  CompanionHost? _sessionCompanionHost;
  int _sessionCompanionEpoch = 0;
  int _companionHostEpoch = 0;
  CompanionHost? _lastCompanionHost;
  String? _desktopSessionId;
  int _desktopSequence = 0;
  String? _panelError;

  bool get _hidReady {
    final host = widget.hid.activeHost.value;
    return widget.hid.connectionStatus.value == HidConnectionStatus.connected &&
        host != null &&
        host.address.isNotEmpty;
  }

  CompanionHost? get _currentCompanionHost =>
      widget.companion?.activeHost.value;

  bool get _desktopReady {
    final host = _currentCompanionHost;
    return host != null &&
        host.capabilities.contains(_desktopDictationCapability);
  }

  bool get _outputReady => _outputMode == DictationOutputMode.bluetoothEnglish
      ? _hidReady
      : _desktopReady;

  bool get _sessionHostValid {
    final host = _currentHost;
    return widget.hid.connectionStatus.value == HidConnectionStatus.connected &&
        host != null &&
        _sameHostIdentity(_sessionHost, host);
  }

  bool get _sessionCompanionValid {
    final host = _currentCompanionHost;
    final pinned = _sessionCompanionHost;
    return widget.companion != null &&
        host != null &&
        pinned != null &&
        _sessionCompanionEpoch == _companionHostEpoch &&
        _sameCompanionHostIdentity(pinned, host) &&
        host.capabilities.contains(_desktopDictationCapability);
  }

  bool get _sessionOutputValid =>
      _outputMode == DictationOutputMode.bluetoothEnglish
      ? _sessionHostValid
      : _sessionCompanionValid;

  bool get _hasOutputSession =>
      _textSession != null || _desktopSessionId != null;

  bool get _sessionInProgress =>
      _starting ||
      _stopping ||
      _cancelling ||
      _dictation.listening ||
      _dictation.busy;

  bool get _controlsBusy => _sessionInProgress || _configuring || _cancelling;

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
    _lastCompanionHost = _currentCompanionHost;
    widget.hid.activeHost.addListener(_handleConnectionChanged);
    widget.hid.connectionStatus.addListener(_handleConnectionChanged);
    widget.companion?.activeHost.addListener(_handleCompanionHostChanged);
    _dictation.addListener(_handleDictationChanged);
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final modelName = preferences.getString(_modelPreferenceKey);
      final languageName = preferences.getString(_languagePreferenceKey);
      final desktopLanguageName = preferences.getString(
        _desktopLanguagePreferenceKey,
      );
      final outputModeName = preferences.getString(_outputModePreferenceKey);
      final model = LocalAsrModel.values.firstWhere(
        (value) => value.name == modelName,
        orElse: () => LocalAsrModel.senseVoice,
      );
      final desktopLanguage = DictationLanguage.values.firstWhere(
        (value) => value.name == (desktopLanguageName ?? languageName),
        orElse: () => DictationLanguage.chinese,
      );
      final outputMode = DictationOutputMode.values.firstWhere(
        (value) => value.name == outputModeName,
        orElse: () => DictationOutputMode.bluetoothEnglish,
      );
      final effectiveOutputMode = Platform.isIOS
          ? DictationOutputMode.desktopMultilingual
          : outputMode;
      final language =
          effectiveOutputMode == DictationOutputMode.bluetoothEnglish
          ? DictationLanguage.english
          : desktopLanguage;
      await _dictation.configure(model: model, language: language);
      await preferences.setString(_languagePreferenceKey, 'english');
      await preferences.setString(_legacyTextProfilePreferenceKey, 'usAscii');
      await preferences.setString(
        _desktopLanguagePreferenceKey,
        desktopLanguage.name,
      );
      await preferences.setString(
        _outputModePreferenceKey,
        effectiveOutputMode.name,
      );
      final permission = await _capture.hasPermission();
      final ready = await _models.areModelsAvailable(model: model);
      if (!mounted) return;
      setState(() {
        _model = model;
        _outputMode = effectiveOutputMode;
        _language = language;
        _desktopLanguage = desktopLanguage;
        _permissionGranted = permission;
        _modelReady = ready;
        _initialized = true;
      });
      if (widget.autoStartWhenReady && ready && _outputReady && _appResumed) {
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
    if (_outputMode == DictationOutputMode.bluetoothEnglish) {
      final session = _textSession;
      if (session == null || !_sessionHostValid) {
        throw StateError(
          'Dictation session has ended or its Bluetooth host changed.',
        );
      }
      try {
        await _textOutput.sendText(session, text);
      } on PlatformException catch (error) {
        final recoverableInterruption =
            error.code == 'NAVIGATION_INTERRUPTED' ||
            error.code == 'INPUT_BUSY';
        if (recoverableInterruption &&
            identical(_textSession, session) &&
            _sessionHostValid) {
          if (mounted) {
            setState(
              () => _panelError =
                  'Bluetooth text was interrupted by manual input. This phrase was skipped; dictation continues.',
            );
          }
          return;
        }
        _invalidateBluetoothSessionAfterDeliveryFailure(session, error);
      } catch (error) {
        _invalidateBluetoothSessionAfterDeliveryFailure(session, error);
      }
      return;
    }
    final companion = widget.companion;
    final sessionId = _desktopSessionId;
    if (companion == null || sessionId == null || !_sessionCompanionValid) {
      throw StateError(
        'Desktop dictation session has ended or its PC changed.',
      );
    }
    final sequence = _desktopSequence++;
    try {
      await companion.sendDictation(
        sessionId: sessionId,
        sequence: sequence,
        text: text,
      );
    } on CompanionInputBusyException catch (error) {
      if (_desktopSessionId == sessionId && _sessionCompanionValid) {
        if (mounted) {
          setState(
            () => _panelError =
                'Manual keyboard shortcut is active. This phrase was skipped; dictation continues.',
          );
        }
        return;
      }
      _invalidateDesktopSessionAfterDeliveryFailure(sessionId, error);
      rethrow;
    } catch (error) {
      _invalidateDesktopSessionAfterDeliveryFailure(sessionId, error);
      rethrow;
    }
  }

  void _invalidateBluetoothSessionAfterDeliveryFailure(
    HidTextOutputSession session,
    Object error,
  ) {
    if (!identical(_textSession, session)) return;
    _textSession = null;
    ++_startGeneration;
    _starting = false;
    _cancelling = true;
    _panelError = 'Bluetooth text delivery failed; dictation stopped: $error';
    if (mounted) setState(() {});
    unawaited(_stopAfterBluetoothDeliveryFailure(session));
  }

  Future<void> _stopAfterBluetoothDeliveryFailure(
    HidTextOutputSession session,
  ) async {
    Object? stopError;
    try {
      await _dictation.cancel();
    } catch (error) {
      stopError = error;
    }
    _sessionHost = null;
    _wakeLockHeld = false;
    try {
      await _textOutput.cancelSession(session);
    } catch (error) {
      stopError ??= error;
    }
    try {
      await widget.disableWakeLock?.call();
    } catch (error) {
      stopError ??= error;
    }
    if (mounted) {
      setState(() {
        _sessionHost = null;
        _cancelling = false;
        if (stopError != null) {
          _panelError = '$_panelError (stop failed: $stopError)';
        }
      });
    } else {
      _sessionHost = null;
      _cancelling = false;
    }
  }

  void _invalidateDesktopSessionAfterDeliveryFailure(
    String sessionId,
    Object error,
  ) {
    if (_desktopSessionId != sessionId) return;
    _desktopSessionId = null;
    ++_startGeneration;
    _starting = false;
    _cancelling = true;
    _panelError = 'Desktop text delivery failed; dictation stopped: $error';
    if (mounted) setState(() {});
    unawaited(_stopAfterDesktopDeliveryFailure());
  }

  Future<void> _stopAfterDesktopDeliveryFailure() async {
    Object? stopError;
    try {
      await _dictation.cancel();
    } catch (error) {
      stopError = error;
    }
    _sessionCompanionHost = null;
    _wakeLockHeld = false;
    try {
      await widget.disableWakeLock?.call();
    } catch (error) {
      stopError ??= error;
    }
    if (mounted) {
      setState(() {
        _sessionCompanionHost = null;
        _cancelling = false;
        if (stopError != null) {
          _panelError = '$_panelError (stop failed: $stopError)';
        }
      });
    } else {
      _sessionCompanionHost = null;
      _cancelling = false;
    }
  }

  void _handleConnectionChanged() {
    if (_outputMode == DictationOutputMode.bluetoothEnglish &&
        _sessionHost != null &&
        _sessionInProgress &&
        !_sessionHostValid) {
      unawaited(_cancelForLostConnection());
    }
    if (mounted) setState(() {});
  }

  void _handleCompanionHostChanged() {
    final host = _currentCompanionHost;
    if (!_sameCompanionHostIdentity(_lastCompanionHost, host)) {
      _companionHostEpoch++;
      _lastCompanionHost = host;
    }
    if (_outputMode == DictationOutputMode.desktopMultilingual &&
        _sessionCompanionHost != null &&
        _sessionInProgress &&
        !_sessionCompanionValid) {
      unawaited(_cancelForLostDesktopConnection());
    }
    if (mounted) setState(() {});
  }

  Future<void> _cancelForLostDesktopConnection() async {
    await _cancelCurrentSession();
    if (mounted) {
      setState(
        () => _panelError =
            'PC companion changed or disconnected. Dictation stopped.',
      );
    }
  }

  HidHost? get _currentHost => widget.hid.activeHost.value;

  bool _sameHostIdentity(HidHost? first, HidHost? second) =>
      first != null && second != null && first.address == second.address;

  bool _sameCompanionHostIdentity(
    CompanionHost? first,
    CompanionHost? second,
  ) =>
      first != null &&
      second != null &&
      first.address == second.address &&
      first.port == second.port &&
      first.token == second.token &&
      first.capabilities.length == second.capabilities.length &&
      first.capabilities.every(second.capabilities.contains);

  void _handleDictationChanged() {
    if (mounted) setState(() {});
    if (_hasOutputSession &&
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
    if (!_hasOutputSession ||
        _starting ||
        _stopping ||
        _dictation.listening ||
        _dictation.busy) {
      return;
    }
    _textSession = null;
    _desktopSessionId = null;
    _sessionHost = null;
    _sessionCompanionHost = null;
    _cancelling = true;
    try {
      final cleanupError = await _cleanupSession(
        session: session,
        cancelCapture: false,
      );
      if (mounted && cleanupError != null) {
        setState(() => _panelError = '$cleanupError');
      }
    } finally {
      _cancelling = false;
      if (mounted) setState(() {});
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
    if (_cancelling) return;
    ++_startGeneration;
    _starting = false;
    _cancelling = true;
    final session = _textSession;
    _textSession = null;
    _desktopSessionId = null;
    _sessionHost = null;
    _sessionCompanionHost = null;
    try {
      final cleanupError = await _cleanupSession(
        session: session,
        cancelCapture: true,
      );
      if (cleanupError != null && mounted) {
        setState(() => _panelError = '$cleanupError');
      }
    } finally {
      _cancelling = false;
      if (mounted) setState(() {});
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
    if (_controlsBusy || _downloading) return;
    setState(() => _panelError = null);
    if (!_outputReady) {
      setState(
        () => _panelError = _outputMode == DictationOutputMode.bluetoothEnglish
            ? 'Connect this phone to a computer over Bluetooth HID first.'
            : 'Connect to a PC companion with local dictation support first.',
      );
      return;
    }
    final generation = ++_startGeneration;
    _starting = true;
    if (_outputMode == DictationOutputMode.bluetoothEnglish) {
      _sessionHost = _currentHost;
      _sessionCompanionHost = null;
    } else {
      _sessionCompanionHost = _currentCompanionHost;
      _sessionCompanionEpoch = _companionHostEpoch;
      _sessionHost = null;
    }
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
      if (!_sessionOutputValid) {
        throw StateError(
          'The selected output host changed before dictation started.',
        );
      }
      if (_outputMode == DictationOutputMode.bluetoothEnglish) {
        _textSession = _textOutput.beginSession();
      } else {
        final host = _sessionCompanionHost!;
        if (!host.capabilities.contains(_desktopDictationCapability)) {
          throw StateError('This PC does not support multilingual dictation.');
        }
        _desktopSessionId =
            'phone-dictation-${DateTime.now().microsecondsSinceEpoch}-${_nextDictationSession++}';
        _desktopSequence = 0;
      }
      await _dictation.start();
      if (!_canStartGeneration(generation)) {
        final session = _textSession;
        _textSession = null;
        _desktopSessionId = null;
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
          _desktopSessionId = null;
          _sessionHost = null;
          _sessionCompanionHost = null;
          if (session != null) await _textOutput.cancelSession(session);
        }
        return;
      }
      _wakeLockHeld = true;
      if (mounted) setState(() {});
    } catch (error) {
      final session = _textSession;
      _textSession = null;
      _desktopSessionId = null;
      final cleanupError = await _cleanupSession(
        session: session,
        cancelCapture: true,
      );
      if (generation == _startGeneration) {
        _sessionHost = null;
        _sessionCompanionHost = null;
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
          _sessionCompanionHost = null;
        }
      }
      if (mounted) setState(() {});
    }
  }

  bool _canStartGeneration(int generation) =>
      mounted &&
      _appResumed &&
      _sessionOutputValid &&
      generation == _startGeneration;

  Future<bool> _stop() async {
    var succeeded = true;
    _stopping = true;
    try {
      await _dictation.stop();
    } catch (error) {
      succeeded = false;
      if (mounted) setState(() => _panelError = '$error');
    } finally {
      final session = _textSession;
      _textSession = null;
      _desktopSessionId = null;
      _sessionHost = null;
      _sessionCompanionHost = null;
      if (session != null) {
        try {
          await _textOutput.cancelSession(session);
        } catch (error) {
          succeeded = false;
          if (mounted) setState(() => _panelError = '$error');
        }
      }
      _wakeLockHeld = false;
      try {
        await widget.disableWakeLock?.call();
      } catch (error) {
        succeeded = false;
        if (mounted) setState(() => _panelError = '$error');
      } finally {
        _stopping = false;
      }
      if (mounted) setState(() {});
    }
    return succeeded;
  }

  Future<void> _stopAndDismiss() async {
    if (!_canStopLiveSession) return;
    final succeeded = await _stop();
    if (mounted && succeeded) widget.onDismiss?.call();
  }

  bool get _canStopLiveSession =>
      !_starting &&
      !_stopping &&
      !_cancelling &&
      !_configuring &&
      !_downloading &&
      !_dictation.busy;

  void _dismissPanel(BuildContext context) {
    final onDismiss = widget.onDismiss;
    if (onDismiss != null) {
      onDismiss();
    } else {
      Navigator.pop(context);
    }
  }

  Future<void> _selectModel(LocalAsrModel? model) async {
    if (model == null || model == _model || _controlsBusy || _downloading) {
      return;
    }
    setState(() => _configuring = true);
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
    } finally {
      if (mounted) setState(() => _configuring = false);
    }
  }

  Future<void> _selectLanguage(DictationLanguage? language) async {
    if (language == null ||
        language == _language ||
        _outputMode != DictationOutputMode.desktopMultilingual ||
        _controlsBusy ||
        _downloading) {
      return;
    }
    setState(() => _configuring = true);
    try {
      await _cancelOutputSession();
      await _dictation.configure(language: language);
      if (mounted) {
        setState(() {
          _language = language;
          _desktopLanguage = language;
        });
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_desktopLanguagePreferenceKey, language.name);
      await prefs.setString(_languagePreferenceKey, 'english');
    } catch (error) {
      if (mounted) setState(() => _panelError = '$error');
    } finally {
      if (mounted) setState(() => _configuring = false);
    }
  }

  Future<void> _selectOutputMode(DictationOutputMode? mode) async {
    if (mode == null || mode == _outputMode || _controlsBusy || _downloading) {
      return;
    }
    setState(() => _configuring = true);
    final language = mode == DictationOutputMode.bluetoothEnglish
        ? DictationLanguage.english
        : _desktopLanguage;
    try {
      await _cancelOutputSession();
      await _dictation.configure(language: language);
      if (mounted) {
        setState(() {
          _outputMode = mode;
          _language = language;
          _panelError = null;
        });
      }
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(_outputModePreferenceKey, mode.name);
      await preferences.setString(_languagePreferenceKey, 'english');
      await preferences.setString(
        _desktopLanguagePreferenceKey,
        _desktopLanguage.name,
      );
    } catch (error) {
      if (mounted) setState(() => _panelError = '$error');
    } finally {
      if (mounted) setState(() => _configuring = false);
    }
  }

  Future<void> _downloadModel() async {
    if (_controlsBusy || _downloading) return;
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
    if (_controlsBusy || _downloading) return;
    setState(() {
      _downloading = true;
      _panelError = null;
    });
    try {
      final path = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Choose the folder containing the model files',
      );
      if (path == null) return;
      if (_controlsBusy) return;
      await _dictation.releaseRecognizer();
      await _models.importModel(_model, Directory(path));
      if (mounted) setState(() => _modelReady = true);
    } catch (error) {
      if (mounted) setState(() => _panelError = 'Model import failed: $error');
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  Future<void> _deleteModel() async {
    if (_controlsBusy || _downloading || !_modelReady) return;
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
    if (_controlsBusy || _downloading) return;
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
    _desktopSessionId = null;
    if (session != null) await _textOutput.cancelSession(session);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.hid.activeHost.removeListener(_handleConnectionChanged);
    widget.hid.connectionStatus.removeListener(_handleConnectionChanged);
    widget.companion?.activeHost.removeListener(_handleCompanionHostChanged);
    _dictation.removeListener(_handleDictationChanged);
    _models.cancelDownload();
    final session = _textSession;
    _textSession = null;
    _desktopSessionId = null;
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
    final panel = Dialog(
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
                          onPressed: () => _dismissPanel(context),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _outputMode == DictationOutputMode.bluetoothEnglish
                          ? (_hidReady ||
                                    (_sessionInProgress && _sessionHostValid)
                                ? 'Bluetooth keyboard connected · English only'
                                : 'Bluetooth HID connection required')
                          : (_desktopReady ||
                                    (_sessionInProgress &&
                                        _sessionCompanionValid)
                                ? 'LumiaKey Desktop connected · text only'
                                : 'LumiaKey Desktop companion required'),
                      key: const ValueKey('dictation-connection-status'),
                      style: TextStyle(
                        color: _outputReady
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
                              _outputMode ==
                                      DictationOutputMode.bluetoothEnglish
                                  ? 'Bluetooth English recognizes English and types printable ASCII key presses. Use a US keyboard layout with English input active. Chinese and other languages use LumiaKey Desktop.'
                                  : 'LumiaKey Desktop recognizes speech on this phone and sends finalized text over the local network to the PC companion. Chinese and other supported languages are available; no audio is sent.',
                              key: const ValueKey('dictation-output-limit'),
                            ),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<DictationOutputMode>(
                              key: const ValueKey('dictation-output-mode'),
                              initialValue: _outputMode,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Output mode',
                              ),
                              items: [
                                if (!Platform.isIOS)
                                  DropdownMenuItem(
                                    key: ValueKey(
                                      'dictation-output-bluetoothEnglish',
                                    ),
                                    value: DictationOutputMode.bluetoothEnglish,
                                    child: Text(
                                      'Bluetooth English',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                DropdownMenuItem(
                                  key: ValueKey(
                                    'dictation-output-desktopMultilingual',
                                  ),
                                  value:
                                      DictationOutputMode.desktopMultilingual,
                                  child: Text(
                                    'LumiaKey Desktop · multilingual',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                              onChanged: _controlsBusy || _downloading
                                  ? null
                                  : _selectOutputMode,
                            ),
                            if (_outputMode ==
                                DictationOutputMode.bluetoothEnglish) ...[
                              const SizedBox(height: 8),
                              const InputDecorator(
                                decoration: InputDecoration(
                                  labelText: 'Recognition language',
                                ),
                                child: Text('English (fixed)'),
                              ),
                            ] else ...[
                              const SizedBox(height: 8),
                              DropdownButtonFormField<DictationLanguage>(
                                key: const ValueKey('dictation-language'),
                                initialValue: _language,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                  labelText: 'Recognition language',
                                ),
                                items: DictationLanguage.values
                                    .map(
                                      (language) => DropdownMenuItem(
                                        key: ValueKey(
                                          'dictation-language-${language.name}',
                                        ),
                                        value: language,
                                        child: Text(
                                          language.label,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    )
                                    .toList(),
                                onChanged: _controlsBusy || _downloading
                                    ? null
                                    : _selectLanguage,
                              ),
                            ],
                            const SizedBox(height: 8),
                            DropdownButtonFormField<LocalAsrModel>(
                              key: const ValueKey('dictation-model'),
                              initialValue: _model,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Local model',
                              ),
                              items: LocalAsrModel.values
                                  .map(
                                    (model) => DropdownMenuItem(
                                      value: model,
                                      child: Text(
                                        model.label,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: _controlsBusy || _downloading
                                  ? null
                                  : _selectModel,
                            ),
                            const SizedBox(height: 8),
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
                                  onPressed: _downloading || _controlsBusy
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
                                  onPressed: _downloading || _controlsBusy
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
                                          !_controlsBusy
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
                      onPressed: listening
                          ? (_dictation.busy ||
                                    _downloading ||
                                    _configuring ||
                                    _stopping ||
                                    _cancelling)
                                ? null
                                : _stop
                          : (_controlsBusy || _downloading || !_outputReady)
                          ? null
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
    if (!widget.autoCollapseWhileListening) return panel;
    if (listening || _stopping) {
      return Stack(
        key: const ValueKey('dictation-live-overlay'),
        children: [
          Positioned(
            top: MediaQuery.paddingOf(context).top + 7,
            right: MediaQuery.paddingOf(context).right + 142,
            child: _buildLiveLevelStopChip(),
          ),
        ],
      );
    }
    return Stack(
      key: const ValueKey('dictation-setup-overlay'),
      children: [
        const ModalBarrier(
          key: ValueKey('dictation-entry-barrier'),
          dismissible: false,
          color: Colors.black54,
        ),
        Center(child: panel),
      ],
    );
  }

  Widget _buildLiveLevelStopChip() => ValueListenableBuilder<double>(
    valueListenable: _dictation.audioLevel,
    builder: (context, level, _) {
      final percent = (level.clamp(0.0, 1.0) * 100).round();
      final warning = _panelError;
      return Tooltip(
        key: const ValueKey('dictation-live-tooltip'),
        message: warning == null
            ? 'Stop dictation · microphone level $percent%'
            : '$warning · microphone level $percent%',
        child: Semantics(
          key: const ValueKey('dictation-live-chip-semantics'),
          button: true,
          label: 'Stop dictation',
          value: warning == null
              ? 'Microphone level $percent percent'
              : '$warning; microphone level $percent percent',
          enabled: _canStopLiveSession,
          child: Material(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            elevation: 5,
            borderRadius: BorderRadius.circular(12),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              key: const ValueKey('stop-dictation-compact'),
              onTap: _canStopLiveSession ? _stopAndDismiss : null,
              child: SizedBox(
                width: 44,
                height: 40,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.stop_rounded, size: 19),
                    const SizedBox(height: 3),
                    SizedBox(
                      width: 30,
                      child: LinearProgressIndicator(
                        value: level.clamp(0.0, 1.0),
                        minHeight: 3,
                        semanticsLabel: 'Microphone input level',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
