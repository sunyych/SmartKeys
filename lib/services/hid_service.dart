import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/config.dart';

enum HidConnectionStatus {
  unavailable,
  permissionRequired,
  bluetoothOff,
  registering,
  disconnected,
  connecting,
  connected,
}

@immutable
class HidHost {
  const HidHost({required this.id, required this.name, required this.address});

  final String id;
  final String name;
  final String address;

  factory HidHost.fromMap(Map<Object?, Object?> map) => HidHost(
    id: map['id']?.toString() ?? '',
    name: map['name']?.toString() ?? 'Paired device',
    address: map['address']?.toString() ?? '',
  );

  @override
  bool operator ==(Object other) =>
      other is HidHost &&
      other.id == id &&
      other.name == name &&
      other.address == address;

  @override
  int get hashCode => Object.hash(id, name, address);
}

abstract interface class HidService {
  ValueListenable<HidConnectionStatus> get connectionStatus;
  ValueListenable<List<HidHost>> get pairedHosts;
  ValueListenable<HidHost?> get activeHost;
  ValueListenable<String?> get errorMessage;

  Future<void> requestBluetoothAccess();
  Future<void> makeDiscoverable();
  Future<void> openBluetoothSettings();
  Future<void> refreshPairedHosts();
  Future<void> connectHost(String hostId);
  Future<void> disconnectHost();
  Future<void> sendPress(HidAction action);
  Future<void> sendRelease(HidAction action);
  Future<void> sendStep(HidAction action);
  Future<void> releaseAllKeys();
  void dispose();
}

class MethodChannelHidService implements HidService {
  MethodChannelHidService({
    this._channel = const MethodChannel('smart_keys/hid'),
  }) {
    _channel.setMethodCallHandler(_handleNativeCall);
    unawaited(_refreshSnapshot());
  }

  final MethodChannel _channel;
  final ValueNotifier<HidConnectionStatus> _status = ValueNotifier(
    HidConnectionStatus.registering,
  );
  final ValueNotifier<List<HidHost>> _hosts = ValueNotifier(const []);
  final ValueNotifier<HidHost?> _activeHost = ValueNotifier(null);
  final ValueNotifier<String?> _error = ValueNotifier(null);
  bool _disposed = false;

  @override
  ValueListenable<HidConnectionStatus> get connectionStatus => _status;

  @override
  ValueListenable<List<HidHost>> get pairedHosts => _hosts;

  @override
  ValueListenable<HidHost?> get activeHost => _activeHost;

  @override
  ValueListenable<String?> get errorMessage => _error;

  Future<void> _handleNativeCall(MethodCall call) async {
    switch (call.method) {
      case 'connectionSnapshotChanged':
        _applySnapshot(call.arguments);
      case 'connectionStatusChanged':
        if (call.arguments is Map) {
          _applySnapshot(call.arguments);
        } else {
          _setStatus(call.arguments?.toString());
        }
    }
  }

  Future<void> _refreshSnapshot() async {
    try {
      final snapshot = await _channel.invokeMethod<Object?>(
        'getConnectionSnapshot',
      );
      _applySnapshot(snapshot);
    } on MissingPluginException {
      _status.value = HidConnectionStatus.unavailable;
      _error.value =
          'Bluetooth HID Device mode is currently available on Android 9 or newer.';
    } on PlatformException catch (error) {
      _error.value = error.message ?? error.code;
      _status.value = HidConnectionStatus.unavailable;
    }
  }

  void _applySnapshot(Object? raw) {
    if (_disposed) return;
    if (raw is! Map) return;
    final map = raw.cast<Object?, Object?>();
    _setStatus(map['status']?.toString());
    final host = map['activeHost'];
    _activeHost.value = host is Map
        ? HidHost.fromMap(host.cast<Object?, Object?>())
        : null;
    final rawHosts = map['pairedHosts'];
    _hosts.value = rawHosts is List
        ? rawHosts
              .whereType<Map>()
              .map((item) => HidHost.fromMap(item.cast<Object?, Object?>()))
              .toList(growable: false)
        : const [];
    _error.value = map['error']?.toString();
  }

  void _setStatus(String? raw) {
    _status.value = HidConnectionStatus.values.firstWhere(
      (value) => value.name == raw,
      orElse: () => HidConnectionStatus.unavailable,
    );
  }

  Future<void> _command(
    String method, [
    Map<String, Object?>? arguments,
  ]) async {
    try {
      final response = await _channel.invokeMethod<Object?>(method, arguments);
      _applySnapshot(response);
      if (response is! Map) await _refreshSnapshot();
    } on MissingPluginException {
      _status.value = HidConnectionStatus.unavailable;
      _error.value = 'The native Bluetooth HID module is unavailable.';
      rethrow;
    } on PlatformException catch (error) {
      final message = error.message ?? error.code;
      _error.value = message;
      await _refreshSnapshot();
      if (!_disposed) _error.value = message;
      rethrow;
    }
  }

  Future<void> _input(String method, [HidAction? action]) async {
    try {
      await _channel.invokeMethod<void>(method, action?.toJson());
    } on MissingPluginException {
      _status.value = HidConnectionStatus.unavailable;
      _error.value = 'The native Bluetooth HID module is unavailable.';
    } on PlatformException catch (error) {
      _error.value = error.message ?? error.code;
      if (error.code == 'NOT_CONNECTED') {
        _status.value = HidConnectionStatus.disconnected;
      }
    }
  }

  @override
  Future<void> requestBluetoothAccess() => _command('requestBluetoothAccess');

  @override
  Future<void> makeDiscoverable() => _command('makeDiscoverable');

  @override
  Future<void> openBluetoothSettings() => _command('openBluetoothSettings');

  @override
  Future<void> refreshPairedHosts() => _command('refreshPairedHosts');

  @override
  Future<void> connectHost(String hostId) =>
      _command('connect', {'address': hostId});

  @override
  Future<void> disconnectHost() => _command('disconnect');

  @override
  Future<void> releaseAllKeys() => _input('releaseAllKeys');

  @override
  Future<void> sendPress(HidAction action) => _input('sendPress', action);

  @override
  Future<void> sendRelease(HidAction action) => _input('sendRelease', action);

  @override
  Future<void> sendStep(HidAction action) => _input('sendStep', action);

  @override
  void dispose() {
    _disposed = true;
    _channel.setMethodCallHandler(null);
    _status.dispose();
    _hosts.dispose();
    _activeHost.dispose();
    _error.dispose();
  }
}

class RecordingHidService implements HidService {
  final ValueNotifier<HidConnectionStatus> status = ValueNotifier(
    HidConnectionStatus.connected,
  );
  final ValueNotifier<List<HidHost>> hosts = ValueNotifier(const []);
  final ValueNotifier<HidHost?> selectedHost = ValueNotifier(
    const HidHost(id: 'test-host', name: 'Test Computer', address: '00:00'),
  );
  final ValueNotifier<String?> errors = ValueNotifier(null);
  final List<String> calls = [];
  final List<HidAction> pressedActions = [];
  final List<HidAction> releasedActions = [];
  final List<HidAction> steppedActions = [];

  @override
  ValueListenable<HidConnectionStatus> get connectionStatus => status;

  @override
  ValueListenable<List<HidHost>> get pairedHosts => hosts;

  @override
  ValueListenable<HidHost?> get activeHost => selectedHost;

  @override
  ValueListenable<String?> get errorMessage => errors;

  @override
  Future<void> requestBluetoothAccess() async => calls.add('requestAccess');

  @override
  Future<void> makeDiscoverable() async => calls.add('makeDiscoverable');

  @override
  Future<void> openBluetoothSettings() async => calls.add('openSettings');

  @override
  Future<void> refreshPairedHosts() async => calls.add('refreshHosts');

  @override
  Future<void> connectHost(String hostId) async => calls.add('connect:$hostId');

  @override
  Future<void> disconnectHost() async => calls.add('disconnect');

  @override
  Future<void> releaseAllKeys() async => calls.add('releaseAllKeys');

  @override
  Future<void> sendPress(HidAction action) async {
    pressedActions.add(action);
    calls.add('press:${action.keyCode ?? action.value}');
  }

  @override
  Future<void> sendRelease(HidAction action) async {
    releasedActions.add(action);
    calls.add('release:${action.keyCode ?? action.value}');
  }

  @override
  Future<void> sendStep(HidAction action) async {
    steppedActions.add(action);
    calls.add('step:${action.keyCode ?? action.value}');
  }

  @override
  void dispose() {
    status.dispose();
    hosts.dispose();
    selectedHost.dispose();
    errors.dispose();
  }
}
