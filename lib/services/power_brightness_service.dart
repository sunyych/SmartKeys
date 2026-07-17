import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

abstract interface class PowerBrightnessService {
  ValueListenable<bool?> get isPluggedIn;

  Future<void> initialize();
  Future<void> refreshPowerState();
  Future<void> setAppBrightness(double? brightness);
  void dispose();
}

class MethodChannelPowerBrightnessService implements PowerBrightnessService {
  MethodChannelPowerBrightnessService({
    this.channel = const MethodChannel('smart_keys/power'),
  });

  final MethodChannel channel;
  final ValueNotifier<bool?> _isPluggedIn = ValueNotifier(null);
  bool _disposed = false;

  @override
  ValueListenable<bool?> get isPluggedIn => _isPluggedIn;

  @override
  Future<void> initialize() async {
    channel.setMethodCallHandler(_handleNativeCall);
    await refreshPowerState();
  }

  Future<void> _handleNativeCall(MethodCall call) async {
    if (call.method == 'powerStateChanged' && !_disposed) {
      _isPluggedIn.value = call.arguments as bool?;
    }
  }

  @override
  Future<void> refreshPowerState() async {
    try {
      final value = await channel.invokeMethod<bool>('isPluggedIn');
      if (!_disposed) _isPluggedIn.value = value;
    } on MissingPluginException {
      if (!_disposed) _isPluggedIn.value = null;
    }
  }

  @override
  Future<void> setAppBrightness(double? brightness) async {
    try {
      await channel.invokeMethod<void>('setAppBrightness', {
        'brightness': brightness,
      });
    } on MissingPluginException {
      // Widget tests and non-Android hosts have no native implementation.
    }
  }

  @override
  void dispose() {
    _disposed = true;
    channel.setMethodCallHandler(null);
    _isPluggedIn.dispose();
  }
}

class RecordingPowerBrightnessService implements PowerBrightnessService {
  RecordingPowerBrightnessService({bool? pluggedIn = false})
    : state = ValueNotifier(pluggedIn);

  final ValueNotifier<bool?> state;
  final List<double?> appliedBrightness = [];
  int refreshCount = 0;

  @override
  ValueListenable<bool?> get isPluggedIn => state;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> refreshPowerState() async => refreshCount++;

  @override
  Future<void> setAppBrightness(double? brightness) async {
    appliedBrightness.add(brightness);
  }

  @override
  void dispose() => state.dispose();
}
