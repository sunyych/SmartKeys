import 'package:flutter/services.dart';

import '../models/config.dart';

abstract interface class OrientationService {
  Future<void> apply(OrientationMode mode);
}

class SystemOrientationService implements OrientationService {
  @override
  Future<void> apply(OrientationMode mode) {
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
