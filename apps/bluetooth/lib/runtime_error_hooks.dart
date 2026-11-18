import 'dart:async';
import 'dart:ui';
import 'package:diagnostics_core/diagnostics_core.dart';
import 'package:flutter/foundation.dart';
import 'local_diagnostics.dart';

/// Captures a fixed category while preserving the existing error delegates.
/// Neither the exception nor its stack is forwarded to the journal.
class LiteRuntimeErrorHooks {
  LiteRuntimeErrorHooks(this.diagnostics);
  final LiteDiagnostics diagnostics;
  FlutterExceptionHandler? _previousFlutter;
  ErrorCallback? _previousPlatform;
  late FlutterExceptionHandler _flutter;
  late ErrorCallback _platform;
  bool _installed = false;
  bool _handling = false;
  void _capture() {
    if (_handling) return;
    _handling = true;
    unawaited(diagnostics.capture(DiagnosticCode.runtimeFailure));
    _handling = false;
  }

  void install() {
    if (_installed) return;
    _installed = true;
    _previousFlutter = FlutterError.onError;
    _previousPlatform = PlatformDispatcher.instance.onError;
    _flutter = (details) {
      _capture();
      _previousFlutter?.call(details);
    };
    _platform = (error, stack) {
      _capture();
      return _previousPlatform?.call(error, stack) ?? false;
    };
    FlutterError.onError = _flutter;
    PlatformDispatcher.instance.onError = _platform;
  }

  void restore() {
    if (!_installed) return;
    if (identical(FlutterError.onError, _flutter)) {
      FlutterError.onError = _previousFlutter;
    }
    if (identical(PlatformDispatcher.instance.onError, _platform)) {
      PlatformDispatcher.instance.onError = _previousPlatform;
    }
    _installed = false;
  }
}
