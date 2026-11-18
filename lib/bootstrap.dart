import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'dart:ui';
import 'package:diagnostics_core/diagnostics_core.dart';

import 'app.dart';
import 'app_edition.dart';
import 'diagnostics/diagnostics_service.dart';

Future<void> bootstrap(AppEdition edition) async {
  WidgetsFlutterBinding.ensureInitialized();
  final diagnostics = DiagnosticsService(
    metadata: await DiagnosticsService.actualMetadata(),
  );
  await diagnostics.initialize();
  final previousFlutterError = FlutterError.onError;
  FlutterError.onError = (details) {
    diagnostics.record(DiagnosticCode.runtimeFailure);
    previousFlutterError?.call(details);
  };
  final previousPlatformError = PlatformDispatcher.instance.onError;
  PlatformDispatcher.instance.onError = (error, stack) {
    diagnostics.record(DiagnosticCode.runtimeFailure);
    return previousPlatformError?.call(error, stack) ?? false;
  };
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  runApp(SmartKeysApp(edition: edition, diagnostics: diagnostics));
}
