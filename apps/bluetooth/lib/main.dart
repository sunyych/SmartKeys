import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'lite_controller.dart';
import 'lite_home_screen.dart';
import 'local_diagnostics.dart';
import 'local_launcher.dart';
import 'local_profiles.dart';
import 'runtime_error_hooks.dart';
export 'lite_controller.dart';
export 'local_launcher.dart';
export 'local_profiles.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  final diagnostics = LiteDiagnostics();
  LiteRuntimeErrorHooks(diagnostics).install();
  runApp(BluetoothLiteApp(diagnostics: diagnostics));
}

class BluetoothLiteApp extends StatefulWidget {
  const BluetoothLiteApp({
    super.key,
    this.profileStore,
    this.launcherStore,
    this.diagnostics,
    this.controller,
  });
  final LocalProfileStore? profileStore;
  final LocalLauncherStore? launcherStore;
  final LiteDiagnostics? diagnostics;
  final LiteController? controller;
  @override
  State<BluetoothLiteApp> createState() => _BluetoothLiteAppState();
}

class _BluetoothLiteAppState extends State<BluetoothLiteApp>
    with WidgetsBindingObserver {
  late final LiteController controller;
  @override
  void initState() {
    super.initState();
    controller =
        widget.controller ??
        LiteController(
          profileStore: widget.profileStore,
          launcherStore: widget.launcherStore,
          diagnostics: widget.diagnostics,
        );
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null) controller.handleLifecycle(lifecycle);
    unawaited(controller.initialize());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      controller.handleLifecycle(state);
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (widget.controller == null) controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'LumiaKey Bluetooth Lite',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF67E8F9),
        brightness: Brightness.dark,
        surface: const Color(0xFF10151D),
      ),
      useMaterial3: true,
      scaffoldBackgroundColor: const Color(0xFF090D12),
      cardTheme: const CardThemeData(color: Color(0xFF151C26)),
    ),
    home: LiteHomeScreen(controller: controller),
  );
}
