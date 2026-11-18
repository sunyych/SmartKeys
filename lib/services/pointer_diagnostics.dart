import 'package:flutter/foundation.dart';

/// Explicit opt-in build instrumentation. Never accepts free-form event data.
const pointerDiagnosticsEnabled = bool.fromEnvironment(
  'LUMIAKEY_POINTER_DIAGNOSTICS',
);

enum PointerDiagnosticEvent {
  moveGate,
  clickGate,
  scrollGate,
  queued,
  discarded,
  flushBusy,
  flushStarted,
  httpResponse,
  deliveryFailed,
}

enum PointerDiagnosticFailure { timeout, socket, http, other }

class PointerDiagnostics {
  static final _lastEvents = <PointerDiagnosticEvent, DateTime>{};

  static void record(
    PointerDiagnosticEvent event, {
    bool? synced,
    bool? capability,
    bool? pending,
    bool? pinMatch,
    bool? acceptedHost,
    bool? routeDesktop,
    int? mode,
    int? inputEpoch,
    int? httpStatus,
    PointerDiagnosticFailure? failure,
  }) {
    if (!pointerDiagnosticsEnabled) return;
    final now = DateTime.now();
    final previous = _lastEvents[event];
    if (previous != null && now.difference(previous).inMilliseconds < 1000) {
      return;
    }
    _lastEvents[event] = now;
    // Every value below is a boolean, a bounded enum, or a locally generated
    // counter/status. Host identity, credentials and input contents cannot enter.
    final fields = <String>[
      'event=${event.name}',
      if (synced != null) 'synced=$synced',
      if (capability != null) 'capability=$capability',
      if (pending != null) 'pending=$pending',
      if (pinMatch != null) 'pinMatch=$pinMatch',
      if (acceptedHost != null) 'acceptedHost=$acceptedHost',
      if (routeDesktop != null) 'routeDesktop=$routeDesktop',
      if (mode != null && mode >= 0 && mode < 3)
        'mode=${const ['disconnected', 'standalone', 'advanced'][mode]}',
      if (inputEpoch != null && inputEpoch >= 0) 'inputEpoch=$inputEpoch',
      if (httpStatus != null && httpStatus >= 100 && httpStatus <= 599)
        'httpStatus=$httpStatus',
      if (failure != null) 'failure=${failure.name}',
    ];
    debugPrint('LUMIAKEY_POINTER ${fields.join(' ')}');
  }
}
