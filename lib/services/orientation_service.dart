import 'package:flutter/services.dart';

import '../models/config.dart';

abstract interface class OrientationService {
  Future<void> apply(OrientationMode mode);
}

class SystemOrientationService implements OrientationService {
  const SystemOrientationService({this.followSystem = false});

  final bool followSystem;

  @override
  Future<void> apply(OrientationMode mode) {
    if (followSystem) return SystemChrome.setPreferredOrientations(const []);
    final orientations = switch (mode) {
      OrientationMode.auto => <DeviceOrientation>[],
      OrientationMode.portrait => [DeviceOrientation.portraitUp],
      OrientationMode.landscape => [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ],
    };
    return SystemChrome.setPreferredOrientations(orientations);
  }
}

class RecordingOrientationService implements OrientationService {
  final List<OrientationMode> applied = [];

  @override
  Future<void> apply(OrientationMode mode) async => applied.add(mode);
}
