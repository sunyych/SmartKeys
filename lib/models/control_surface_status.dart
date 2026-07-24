import 'package:flutter/foundation.dart';

/// The three independent availability signals shown on the phone.  A Desktop
/// sync must never be mistaken for an HID connection, and a running process
/// must never be mistaken for a usable application workspace.
enum ForegroundWorkspaceStatus {
  unavailable,
  unknown,
  unavailableActions,
  ready,
}

enum PreferredControlSurface {
  localGeneric,
  syncedGeneric,
  foregroundApplication,
}

@immutable
class ControlSurfaceStatus {
  const ControlSurfaceStatus({
    required this.hidConnected,
    required this.desktopDiscovered,
    required this.desktopSynced,
    required this.foregroundStatus,
    required this.preferredSurface,
    this.foregroundApplicationName,
  });

  final bool hidConnected;
  final bool desktopDiscovered;
  final bool desktopSynced;
  final ForegroundWorkspaceStatus foregroundStatus;
  final PreferredControlSurface preferredSurface;
  final String? foregroundApplicationName;
}
