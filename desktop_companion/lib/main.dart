import 'dart:async';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'companion_server.dart';
import 'desktop_controller.dart';
import 'desktop_ui.dart';
import 'tray_shell.dart';

export 'companion_server.dart';
export 'desktop_actions.dart';
export 'desktop_controller.dart';
export 'shortcut_transfer_service.dart';
export 'tray_shell.dart' show desktopBrandAsset;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  await windowManager.waitUntilReadyToShow(
    const WindowOptions(
      size: Size(1080, 720),
      minimumSize: Size(760, 560),
      center: true,
      skipTaskbar: true,
      title: 'LumiaKeys',
    ),
    () async {
      await windowManager.setPreventClose(true);
      await windowManager.hide();
    },
  );
  runApp(const CompanionApp(enableDesktopShell: true));
}

class CompanionApp extends StatefulWidget {
  const CompanionApp({
    super.key,
    this.controller,
    this.enableDesktopShell = false,
    this.startServer = true,
  });

  final DesktopController? controller;
  final bool enableDesktopShell;
  final bool startServer;

  @override
  State<CompanionApp> createState() => _CompanionAppState();
}

class _CompanionAppState extends State<CompanionApp> {
  late final DesktopController controller;
  late final CompanionServer server;
  late final bool ownsController;
  DesktopTrayShell? trayShell;

  @override
  void initState() {
    super.initState();
    ownsController = widget.controller == null;
    controller =
        widget.controller ??
        DesktopController(store: SharedPreferencesDesktopConfigStore());
    server = CompanionServer(controller: controller);
    controller.addListener(_changed);
    server.addListener(_changed);
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    await controller.initialize();
    if (widget.startServer) await server.start();
    if (widget.enableDesktopShell) {
      trayShell = DesktopTrayShell(controller: controller);
      await trayShell!.initialize();
    }
    if (mounted) setState(() {});
  }

  void _changed() {
    server.broadcastNow();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    trayShell?.dispose();
    controller.removeListener(_changed);
    server.removeListener(_changed);
    server.dispose();
    if (ownsController) controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'LumiaKeys',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF19B7C9)),
      useMaterial3: true,
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
    ),
    home: DesktopSettingsHome(controller: controller, server: server),
  );
}
