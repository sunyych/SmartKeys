import 'dart:async';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'companion_server.dart';
import 'desktop_controller.dart';
import 'desktop_dictation.dart';
import 'desktop_ui.dart';
import 'dictation_receiver.dart';
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
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  late final DesktopController controller;
  late final CompanionServer server;
  late final DesktopDictationService dictation;
  late final bool ownsController;
  DesktopTrayShell? trayShell;

  @override
  void initState() {
    super.initState();
    ownsController = widget.controller == null;
    controller =
        widget.controller ??
        DesktopController(store: SharedPreferencesDesktopConfigStore());
    final textSink = MethodChannelDictationTextSink();
    dictation = DesktopDictationService(textSink: textSink);
    controller.actions.confirmVoiceInputFirstUse = _confirmVoiceInputFirstUse;
    server = CompanionServer(controller: controller, dictationSink: textSink);
    controller.addListener(_changed);
    server.addListener(_changed);
    unawaited(_initialize());
  }

  Future<bool> _confirmVoiceInputFirstUse() async {
    if (dictation.firstUseAcknowledged) return true;
    final context = _navigatorKey.currentContext;
    if (context == null) return false;
    await trayShell?.showSection(6);
    if (!context.mounted) return false;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.graphic_eq),
        title: const Text('App Voice Input'),
        content: const Text(
          'App Voice Input runs the selected application’s own microphone and privacy behavior. Local Dictation uses this computer’s microphone and selected local model; phone dictation sends final text only. This shortcut will wait for a new tap after you close this explanation.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('I understand'),
          ),
        ],
      ),
    );
    if (accepted == true) await dictation.acknowledgeFirstUse();
    await windowManager.hide();
    return false;
  }

  Future<void> _initialize() async {
    await controller.initialize();
    if (widget.startServer) await server.start();
    if (widget.enableDesktopShell) {
      await dictation.initialize();
      trayShell = DesktopTrayShell(
        controller: controller,
        dictation: dictation,
      );
      await trayShell!.initialize();
      dictation.onToggleRequested = () => trayShell?.toggleDictation();
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
    dictation.dispose();
    if (ownsController) controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    navigatorKey: _navigatorKey,
    title: 'LumiaKeys',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF19B7C9)),
      useMaterial3: true,
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
    ),
    home: DesktopSettingsHome(
      controller: controller,
      server: server,
      dictation: dictation,
    ),
  );
}
