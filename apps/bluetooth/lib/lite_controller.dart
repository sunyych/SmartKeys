import 'dart:async';
import 'dart:convert';

import 'package:diagnostics_core/diagnostics_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'local_diagnostics.dart';
import 'local_launcher.dart';
import 'local_profiles.dart';

class LiteHost {
  const LiteHost(this.id, this.name, this.address);
  final String id, name, address;
  factory LiteHost.fromMap(Map<Object?, Object?> map) => LiteHost(
    map['id'] is String ? map['id'] as String : '',
    map['name'] is String ? map['name'] as String : 'Paired device',
    map['address'] is String ? map['address'] as String : '',
  );
}

class _InputStamp {
  const _InputStamp(this.epoch, this.address);
  final int epoch;
  final String address;
}

/// Owns only local configuration and the existing Android Bluetooth HID channel.
/// Launchpad emits a saved keyboard chord; it never claims OS app activation.
class LiteController extends ChangeNotifier {
  LiteController({
    LocalProfileStore? profileStore,
    LocalLauncherStore? launcherStore,
    LiteDiagnostics? diagnostics,
    MethodChannel? channel,
  }) : profileStore = profileStore ?? const SharedPreferencesProfileStore(),
       launcherStore = launcherStore ?? const SharedPreferencesLauncherStore(),
       diagnostics = diagnostics ?? LiteDiagnostics(),
       channel = channel ?? const MethodChannel('smart_keys/hid'),
       _ownsDiagnostics = diagnostics == null;

  final LocalProfileStore profileStore;
  final LocalLauncherStore launcherStore;
  final LiteDiagnostics diagnostics;
  final MethodChannel channel;
  final bool _ownsDiagnostics;
  List<LocalProfile> _profiles = List.unmodifiable(
    defaultLocalProfiles().map(
      (profile) => LocalProfile.fromJson(profile.toJson()),
    ),
  );
  List<LocalLaunchSlot> _launcherSlots = validateLocalLauncherSlots(
    defaultLocalLauncherSlots(),
  );
  List<LiteHost> _pairedHosts = [];
  LiteHost? _activeHost;
  String _status = 'registering';
  String? _error, _selectedProfileId;
  bool _loading = true, _profilesLoaded = false, _launcherLoaded = false;
  bool _landscape = false, _controlsVisible = false, _disposed = false;
  AppLifecycleState _lifecycle = AppLifecycleState.resumed;
  int _inputEpoch = 0, _eventSerial = 0, _snapshotGeneration = 0;
  int _pendingSaves = 0, _nativeCommandsInFlight = 0;
  bool _snapshotErrorActive = false, _snapshotErrorPending = false;
  bool _notificationPending = false;
  bool _switchingHost = false;
  int? _pendingLaunchSlot;
  double _scrollRemainder = 0;
  Future<void>? _initializing;
  Future<void> _writes = Future.value();

  List<LocalProfile> get profiles => List.unmodifiable(_profiles);
  List<LocalLaunchSlot> get launcherSlots => List.unmodifiable(_launcherSlots);
  String? get selectedProfileId => _selectedProfileId;
  LocalProfile? get selectedProfile {
    for (final profile in _profiles) {
      if (profile.id == _selectedProfileId) return profile;
    }
    return null;
  }

  String get status => _status;
  String? get error => _error;
  LiteHost? get activeHost => _activeHost;
  List<LiteHost> get pairedHosts => List.unmodifiable(_pairedHosts);
  bool get connected =>
      _status == 'connected' && (_activeHost?.address.isNotEmpty ?? false);
  bool get loading => _loading;
  bool get saving => _pendingSaves > 0;
  int get inputEpoch => _inputEpoch;
  int? get pendingLaunchSlot => _pendingLaunchSlot;
  bool get canSendInput =>
      !_disposed &&
      !_loading &&
      !saving &&
      !_switchingHost &&
      connected &&
      _landscape &&
      _controlsVisible &&
      _lifecycle == AppLifecycleState.resumed;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _notifySoon() {
    if (_disposed || _notificationPending) return;
    _notificationPending = true;
    scheduleMicrotask(() {
      _notificationPending = false;
      _notify();
    });
  }

  void clearError() {
    _error = null;
    _notify();
  }

  Future<void> initialize() async {
    if (_disposed) return;
    if (_initializing != null) return _initializing!;
    if (_profilesLoaded && _launcherLoaded) return;
    final pending = _initialize();
    _initializing = pending;
    try {
      await pending;
    } finally {
      _initializing = null;
    }
  }

  Future<void> _initialize() async {
    channel.setMethodCallHandler(_nativeUpdate);
    unawaited(diagnostics.initialize());
    await Future.wait([_loadProfiles(), _loadLauncher(), refreshPairedHosts()]);
    _loading = false;
    _notify();
  }

  Future<void> _loadProfiles() async {
    if (_profilesLoaded) return;
    try {
      final values = await profileStore.load();
      final safe = _validatedProfiles(values);
      if (_disposed) return;
      _profiles = safe;
      _profilesLoaded = true;
    } catch (_) {
      unawaited(diagnostics.capture(DiagnosticCode.configurationLoadFailed));
      _error =
          'Could not load saved shortcuts. Existing data has not been replaced.';
    }
  }

  Future<void> _loadLauncher() async {
    if (_launcherLoaded) return;
    try {
      final values = validateLocalLauncherSlots(await launcherStore.load());
      if (_disposed) return;
      _launcherSlots = values;
      _launcherLoaded = true;
    } catch (_) {
      unawaited(diagnostics.capture(DiagnosticCode.configurationLoadFailed));
      _error =
          'Could not load saved launch shortcuts. Existing data has not been replaced.';
    }
  }

  List<LocalProfile> _validatedProfiles(List<LocalProfile> values) {
    if (values.isEmpty ||
        values.map((p) => p.id).toSet().length != values.length) {
      throw const FormatException('Invalid local profile list.');
    }
    return List.unmodifiable(
      values.map((p) => LocalProfile.fromJson(p.toJson())),
    );
  }

  Future<void> _nativeUpdate(MethodCall call) async {
    if (_disposed ||
        call.method != 'connectionSnapshotChanged' ||
        call.arguments is! Map) {
      return;
    }
    ++_eventSerial;
    _applySnapshot(call.arguments);
  }

  void _applySnapshot(Object? value) {
    if (_disposed || value is! Map) return;
    final hasError = value['error'] != null;
    if (hasError && !_snapshotErrorActive) {
      if (_nativeCommandsInFlight > 0) {
        _snapshotErrorPending = true;
      } else {
        unawaited(
          diagnostics.capture(DiagnosticCode.bluetoothConnectionFailed),
        );
      }
    }
    if (!hasError) _snapshotErrorPending = false;
    _snapshotErrorActive = hasError;
    final rawHost = value['activeHost'];
    final nextHost = rawHost is Map
        ? LiteHost.fromMap(rawHost.cast<Object?, Object?>())
        : null;
    final nextStatus = value['status'] is String
        ? value['status'] as String
        : 'unavailable';
    final changed =
        nextHost?.address != _activeHost?.address ||
        nextHost?.id != _activeHost?.id ||
        nextStatus != _status;
    _activeHost = nextHost;
    _status = nextStatus;
    _pairedHosts = value['pairedHosts'] is List
        ? (value['pairedHosts'] as List)
              .whereType<Map>()
              .map((v) => LiteHost.fromMap(v.cast<Object?, Object?>()))
              .toList()
        : [];
    if (hasError) {
      _error =
          'Bluetooth could not complete this operation. Check the connection and try again.';
    }
    if (changed) unawaited(releaseInput());
    _notify();
  }

  void _recordNativeFailure(DiagnosticCode code) {
    _snapshotErrorActive = true;
    _snapshotErrorPending = false;
    unawaited(diagnostics.capture(code));
  }

  void _finishNativeCommand() {
    --_nativeCommandsInFlight;
    if (_nativeCommandsInFlight == 0 && _snapshotErrorPending) {
      _snapshotErrorPending = false;
      unawaited(diagnostics.capture(DiagnosticCode.bluetoothConnectionFailed));
    }
  }

  bool _validStamp(_InputStamp stamp) =>
      canSendInput &&
      stamp.epoch == _inputEpoch &&
      stamp.address == _activeHost?.address;
  _InputStamp? _stamp(int? epoch) =>
      canSendInput && (epoch == null || epoch == _inputEpoch)
      ? _InputStamp(_inputEpoch, _activeHost!.address)
      : null;

  Future<bool> _command(
    String method, {
    Map<String, Object?>? args,
    _InputStamp? input,
    bool connectionCommand = false,
  }) async {
    if (_disposed || input != null && !_validStamp(input)) return false;
    final serial = _eventSerial;
    final generation = connectionCommand
        ? ++_snapshotGeneration
        : _snapshotGeneration;
    ++_nativeCommandsInFlight;
    try {
      final result = await channel.invokeMethod<Object?>(
        method,
        method == 'sendStep'
            ? {...?args, 'expectedHostAddress': input!.address}
            : args,
      );
      if (_disposed || input != null && !_validStamp(input)) return false;
      if (connectionCommand && generation != _snapshotGeneration) return false;
      // New native events and newer connection requests are authoritative.
      // An old input reply must never reconnect a previous host in Dart state.
      if (serial == _eventSerial && generation == _snapshotGeneration) {
        _applySnapshot(result);
      }
      if (input != null && !_validStamp(input)) return false;
      return result is! Map || result['error'] == null;
    } catch (failure) {
      if (_disposed ||
          input != null && !_validStamp(input) ||
          connectionCommand && generation != _snapshotGeneration) {
        return false;
      }
      _recordNativeFailure(
        failure is MissingPluginException
            ? DiagnosticCode.platformUnavailable
            : method == 'sendStep'
            ? DiagnosticCode.bluetoothInputFailed
            : method == 'requestBluetoothAccess'
            ? DiagnosticCode.bluetoothPermissionDenied
            : DiagnosticCode.bluetoothConnectionFailed,
      );
      if (!_disposed) {
        _error = method == 'sendStep'
            ? 'Bluetooth could not send this input. Check the connection and try again.'
            : 'Bluetooth could not complete this operation. Check Android Bluetooth settings.';
        _notify();
      }
      return false;
    } finally {
      _finishNativeCommand();
    }
  }

  Future<bool> refreshPairedHosts() =>
      _command('refreshPairedHosts', connectionCommand: true);
  Future<bool> requestBluetoothAccess() =>
      _command('requestBluetoothAccess', connectionCommand: true);
  Future<bool> makeDiscoverable() =>
      _command('makeDiscoverable', connectionCommand: true);
  Future<bool> connect(String address) async {
    if (_switchingHost ||
        !_pairedHosts.any((host) => host.address == address)) {
      return false;
    }
    _switchingHost = true;
    unawaited(releaseInput());
    try {
      return await _command(
        'connect',
        args: {'address': address},
        connectionCommand: true,
      );
    } finally {
      _switchingHost = false;
      _notify();
    }
  }

  Future<bool> disconnect() async {
    if (_switchingHost) return false;
    _switchingHost = true;
    unawaited(releaseInput());
    try {
      return await _command('disconnect', connectionCommand: true);
    } finally {
      _switchingHost = false;
      _notify();
    }
  }

  void selectProfile(String? id) {
    if (id != null && !_profiles.any((profile) => profile.id == id)) {
      throw const FormatException('Unknown local profile.');
    }
    if (id == _selectedProfileId) return;
    _selectedProfileId = id;
    unawaited(releaseInput());
    _notify();
  }

  void setLandscape(bool value) {
    if (_landscape == value || _disposed) return;
    _landscape = value;
    unawaited(releaseInput());
  }

  void setControlsVisible(bool value) {
    if (_controlsVisible == value || _disposed) return;
    _controlsVisible = value;
    unawaited(releaseInput());
  }

  void handleLifecycle(AppLifecycleState state) {
    if (_disposed || _lifecycle == state) return;
    _lifecycle = state;
    unawaited(releaseInput());
    if (state == AppLifecycleState.resumed) unawaited(refreshPairedHosts());
  }

  Future<bool> releaseInput() {
    ++_inputEpoch;
    _scrollRemainder = 0;
    _notifySoon();
    // Release has no authority to update host/configuration state.
    return _releaseNative();
  }

  Future<bool> _releaseNative() async {
    try {
      await channel.invokeMethod<Object?>('releaseAllKeys');
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _send(Map<String, Object?> action, {int? epoch}) {
    final stamp = _stamp(epoch);
    if (stamp == null) return Future.value(false);
    return _command('sendStep', args: action, input: stamp);
  }

  Future<bool> executeShortcut(LocalShortcut shortcut) {
    try {
      final safe = LocalShortcut.fromJson(shortcut.toJson());
      return _send(safe.toHidAction());
    } catch (_) {
      return Future.value(false);
    }
  }

  Future<bool> sendConsumer(String usage) =>
      executeShortcut(LocalShortcut.consumer(title: 'Media', usage: usage));
  Future<bool> movePointer(Offset delta, {int? epoch}) {
    if (!delta.dx.isFinite || !delta.dy.isFinite) return Future.value(false);
    return _send({
      'type': 'mouseMove',
      'value':
          '${(delta.dx * 1.5).round().clamp(-127, 127)},${(delta.dy * 1.5).round().clamp(-127, 127)}',
    }, epoch: epoch);
  }

  Future<bool> scrollPointer(double delta, {int? epoch}) {
    if (!delta.isFinite || _stamp(epoch) == null) return Future.value(false);
    _scrollRemainder -= delta / 24;
    final steps = _scrollRemainder.truncate().clamp(-127, 127);
    if (steps == 0) return Future.value(true);
    _scrollRemainder -= steps;
    return _send({'type': 'mouseWheel', 'value': '$steps'}, epoch: epoch);
  }

  Future<bool> primaryClick({int? epoch}) =>
      _send({'type': 'mouseButton', 'value': 'LEFT'}, epoch: epoch);
  Future<bool> secondaryClick({int? epoch}) =>
      _send({'type': 'mouseButton', 'value': 'RIGHT'}, epoch: epoch);

  Future<bool> launchSlot(int index) async {
    if (index < 0 ||
        index >= localLauncherSlotCount ||
        _pendingLaunchSlot != null ||
        !_launcherLoaded) {
      return false;
    }
    final stamp = _stamp(null), slot = _launcherSlots[index];
    if (stamp == null || !slot.configured) return false;
    final binding = jsonEncode(slot.toJson());
    _pendingLaunchSlot = index;
    _notify();
    try {
      // A notification listener may have changed the slot/context. No await
      // separates this final check from the existing keyboard HID invocation.
      if (!_validStamp(stamp) ||
          binding != jsonEncode(_launcherSlots[index].toJson())) {
        return false;
      }
      final sent = await _command(
        'sendStep',
        args: slot.launchShortcut!.toHidAction(),
        input: stamp,
      );
      if (!sent ||
          !_validStamp(stamp) ||
          binding != jsonEncode(_launcherSlots[index].toJson())) {
        return false;
      }
      if (slot.profileId != null &&
          _profiles.any((profile) => profile.id == slot.profileId)) {
        selectProfile(slot.profileId);
      }
      return true;
    } finally {
      _pendingLaunchSlot = null;
      _notify();
    }
  }

  Future<void> _save(Future<void> Function() change) {
    if (_disposed) {
      return Future.error(StateError('The control surface is closed.'));
    }
    ++_pendingSaves;
    unawaited(releaseInput());
    _notify();
    final operation = _writes.then((_) async {
      if (_disposed) throw StateError('The control surface is closed.');
      try {
        await change();
      } catch (_) {
        unawaited(diagnostics.capture(DiagnosticCode.configurationSaveFailed));
        _error =
            'Could not save these settings on the phone. Previous settings are unchanged.';
        rethrow;
      } finally {
        --_pendingSaves;
        _notify();
      }
    });
    _writes = operation.catchError((Object _) {});
    return operation;
  }

  Future<void> saveProfile(LocalProfile profile) {
    final safe = LocalProfile.fromJson(profile.toJson());
    return _save(() async {
      if (!_profilesLoaded) {
        throw StateError('Saved shortcuts could not be loaded.');
      }
      final exists = _profiles.any((p) => p.id == safe.id);
      final next = _validatedProfiles([
        for (final p in _profiles) p.id == safe.id ? safe : p,
        if (!exists) safe,
      ]);
      await profileStore.save(next);
      if (!_disposed) _profiles = next;
    });
  }

  Future<void> deleteProfile(String id) => _save(() async {
    if (!_profilesLoaded) {
      throw StateError('Saved shortcuts could not be loaded.');
    }
    if (_profiles.length == 1 || id == 'general') {
      throw const FormatException('Keep the General profile.');
    }
    final next = _profiles.where((p) => p.id != id).toList();
    await profileStore.save(next);
    if (!_disposed) {
      _profiles = next;
      if (_selectedProfileId == id) _selectedProfileId = null;
    }
  });
  Future<void> saveLaunchSlot(int index, LocalLaunchSlot slot) {
    if (index < 0 || index >= localLauncherSlotCount) {
      return Future.error(RangeError.index(index, _launcherSlots));
    }
    final safe = LocalLaunchSlot.fromJson(slot.toJson());
    return _save(() async {
      if (!_launcherLoaded) {
        throw StateError('Saved launch shortcuts could not be loaded.');
      }
      if (safe.profileId != null &&
          !_profiles.any((p) => p.id == safe.profileId)) {
        throw const FormatException('Unknown linked local profile.');
      }
      final next = validateLocalLauncherSlots([
        for (var i = 0; i < localLauncherSlotCount; i++)
          i == index ? safe : _launcherSlots[i],
      ]);
      await launcherStore.save(next);
      if (!_disposed) _launcherSlots = next;
    });
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    ++_inputEpoch;
    channel.setMethodCallHandler(null);
    unawaited(_releaseNative());
    if (_ownsDiagnostics) diagnostics.dispose();
    super.dispose();
  }
}
