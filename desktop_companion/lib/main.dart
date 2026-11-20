import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'codex_activity.dart';
import 'companion_server.dart';
import 'desktop_app_preferences.dart';
import 'desktop_controller.dart';
import 'desktop_dictation.dart';
import 'desktop_localizations.dart';
import 'desktop_ui.dart';
import 'dictation_receiver.dart';
import 'tray_shell.dart';

export 'companion_server.dart';
export 'desktop_actions.dart';
export 'desktop_app_preferences.dart';
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
      title: 'LumiaKey Desktop',
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
    this.preferencesStore,
    this.enableDesktopShell = false,
    this.startServer = true,
  });

  final DesktopController? controller;
  final DesktopAppPreferencesStore? preferencesStore;
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
  late final DesktopAppPreferencesStore? _preferencesStore;
  DesktopAppPreferences _preferences = const DesktopAppPreferences();
  bool _started = false;
  bool _savingPreferences = false;
  bool _saveFailed = false;
  DesktopTrayShell? trayShell;

  @override
  void initState() {
    super.initState();
    _preferencesStore =
        widget.preferencesStore ??
        (widget.controller == null
            ? SharedPreferencesDesktopAppPreferencesStore()
            : null);
    if (_preferencesStore case final store?) {
      unawaited(_loadAndStart(store));
    } else {
      _start();
    }
  }

  Future<void> _loadAndStart(DesktopAppPreferencesStore store) async {
    try {
      final loaded = await store.load();
      if (!mounted) return;
      _preferences = loaded;
    } catch (_) {
      if (!mounted) return;
    }
    _start();
    setState(() {});
  }

  void _start() {
    ownsController = widget.controller == null;
    controller =
        widget.controller ??
        DesktopController(
          store: SharedPreferencesDesktopConfigStore(),
          environment: resolveDesktopBackendEnvironment(
            Platform.environment,
            _preferences.rustEnabled,
          ),
        );
    final textSink = MethodChannelDictationTextSink();
    dictation = DesktopDictationService(textSink: textSink);
    controller.actions.confirmVoiceInputFirstUse = _confirmVoiceInputFirstUse;
    server = CompanionServer(
      controller: controller,
      dictationSink: textSink,
      codexActivity: ownsController
          ? CodexActivityMonitor(
              preferences: SharedPreferencesAsync(),
              bearerToken:
                  Platform.environment['LUMIAKEY_CODEX_ACTIVITY_TOKEN'],
            )
          : null,
    );
    controller.addListener(_changed);
    server.addListener(_changed);
    _started = true;
    unawaited(_initialize());
  }

  Future<void> _savePreferences(DesktopAppPreferences next) async {
    final store = _preferencesStore;
    if (store == null || _savingPreferences) return;
    setState(() {
      _savingPreferences = true;
      _saveFailed = false;
    });
    try {
      await store.save(next);
      if (!mounted) return;
      if (next.language != _preferences.language) {
        trayShell?.setLocale(next.language.locale);
      }
      _preferences = next;
    } catch (_) {
      _saveFailed = true;
    } finally {
      if (mounted) setState(() => _savingPreferences = false);
    }
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
        title: Text(desktopText(context, 'App Voice Input', '应用语音输入')),
        content: Text(
          desktopText(
            context,
            'App Voice Input uses the selected app’s microphone and privacy settings. Local Dictation uses this computer’s microphone and local model. Phone dictation sends final text only. Tap the shortcut again after closing this message.',
            '应用语音输入遵循所选应用的麦克风和隐私设置。本地听写使用此电脑的麦克风和本地模型。手机听写只发送最终文本。关闭此说明后，请再次点击快捷键。',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(desktopText(context, 'Cancel', '取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(desktopText(context, 'I understand', '我知道了')),
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
    if (!mounted) return;
    if (widget.startServer) await server.start();
    if (!mounted) return;
    if (widget.enableDesktopShell) {
      await dictation.initialize();
      if (!mounted) return;
      trayShell = DesktopTrayShell(
        controller: controller,
        dictation: dictation,
        locale: _preferences.language.locale,
      );
      await trayShell!.initialize();
      if (!mounted) return;
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
    if (_started) {
      trayShell?.dispose();
      controller.removeListener(_changed);
      server.removeListener(_changed);
      server.dispose();
      dictation.dispose();
      if (ownsController) controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    navigatorKey: _navigatorKey,
    title: 'LumiaKey Desktop',
    debugShowCheckedModeBanner: false,
    locale: _preferences.language.locale,
    supportedLocales: const [Locale('en'), Locale('zh', 'CN')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: _theme(Brightness.light),
    darkTheme: _theme(Brightness.dark),
    themeMode: _preferences.themeMode,
    home: !_started
        ? const Scaffold(body: Center(child: CircularProgressIndicator()))
        : DesktopSettingsHome(
            controller: controller,
            server: server,
            dictation: dictation,
            preferences: _preferences,
            onPreferencesChanged: _preferencesStore == null
                ? null
                : _savePreferences,
            savingPreferences: _savingPreferences,
            preferencesSaveFailed: _saveFailed,
          ),
  );

  ThemeData _theme(Brightness brightness) => ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF19B7C9),
      brightness: brightness,
    ),
    useMaterial3: true,
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(),
    ),
  );
}
