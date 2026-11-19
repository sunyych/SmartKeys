import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'controllers/app_controller.dart';
import 'app_edition.dart';
import 'data/config_repository.dart';
import 'diagnostics/diagnostics_service.dart';
import 'package:diagnostics_core/diagnostics_core.dart';
import 'icons/icon_library.dart';
import 'data/private_image_store.dart';
import 'data/profile_template_repository.dart';
import 'data/shortcut_usage_repository.dart';
import 'services/hid_service.dart';
import 'services/ios_companion_hid_service.dart';
import 'services/companion_service.dart';
import 'services/disabled_companion_service.dart';
import 'services/orientation_service.dart';
import 'services/power_brightness_service.dart';
import 'mobile_appearance.dart';
import 'models/config.dart';
import 'ui/home_screen.dart';
import 'ui/diagnostics_consent_screen.dart';
import 'ui/local_dictation_route_observer.dart';
import 'ui/regular_home_screen.dart';

class SmartKeysApp extends StatefulWidget {
  const SmartKeysApp({
    super.key,
    this.controller,
    this.edition = buildEdition,
    this.homeOverride,
    this.diagnostics,
  });

  final AppController? controller;
  final AppEdition edition;

  /// An explicit alternate surface for embedding and component tests.
  /// Published entry points always use the edition's actual home screen.
  final Widget? homeOverride;
  final DiagnosticsService? diagnostics;

  @override
  State<SmartKeysApp> createState() => _SmartKeysAppState();
}

class _SmartKeysAppState extends State<SmartKeysApp>
    with WidgetsBindingObserver {
  late final AppController controller;
  late final bool ownsController;
  late final IconLibrary iconLibrary;
  late final MobileAppearance _appearance;
  bool get _unsupportedLite =>
      widget.edition == AppEdition.lite &&
      !Platform.isAndroid &&
      widget.controller == null;

  @override
  void initState() {
    super.initState();
    unawaited(_enterFullscreen());
    ownsController = widget.controller == null;
    if (_unsupportedLite) return;
    _appearance = MobileAppearance();
    iconLibrary = IconLibrary(
      onFailure: () =>
          widget.diagnostics?.record(DiagnosticCode.iconDownloadFailed),
    );
    if (ownsController) unawaited(iconLibrary.initialize());
    final templates = ProfileTemplateRepository(edition: widget.edition);
    final companion =
        widget.controller?.companion ??
        (widget.edition == AppEdition.lite
            ? DisabledCompanionService()
            : LanCompanionService(
                enableDiscovery: !Platform.isIOS,
                reportDiagnostic: widget.diagnostics?.record,
              ));
    controller =
        widget.controller ??
        AppController(
          repository: SharedPreferencesConfigRepository(templates: templates),
          templates: templates,
          hid: widget.edition == AppEdition.lite
              ? MethodChannelHidService()
              : IosCompanionHidService(companion),
          companion: companion,
          orientationService: _EditionOrientationService(widget.edition),
          imageStore: PrivateImageStore(
            reportDiagnostic: widget.diagnostics?.record,
          ),
          powerBrightnessService: MethodChannelPowerBrightnessService(),
          shortcutUsage: FileShortcutUsageRepository(),
          reportDiagnostic: widget.diagnostics?.record,
        );
    WidgetsBinding.instance.addObserver(this);
    if (widget.controller == null || controller.isLoading) {
      controller.initialize();
    }
  }

  @override
  void dispose() {
    if (_unsupportedLite) {
      super.dispose();
      return;
    }
    WidgetsBinding.instance.removeObserver(this);
    if (ownsController) controller.dispose();
    _appearance.dispose();
    iconLibrary.dispose();
    if (ownsController) widget.diagnostics?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_enterFullscreen());
      if (!_unsupportedLite && !controller.isLoading) {
        controller.handleAppResumed();
      }
    }
  }

  Future<void> _enterFullscreen() {
    return SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  Widget build(BuildContext context) {
    if (_unsupportedLite) {
      return const MaterialApp(
        home: Scaffold(
          body: Center(child: Text('LumiaKey Lite is available on Android.')),
        ),
      );
    }
    final app = IconLibraryScope(
      library: iconLibrary,
      child: SmartKeysScope(
        controller: controller,
        edition: widget.edition,
        child: MobileAppearanceScope(
          appearance: _appearance,
          child: ListenableBuilder(
            listenable: _appearance,
            builder: _buildMaterialApp,
          ),
        ),
      ),
    );
    return widget.diagnostics == null
        ? app
        : DiagnosticsScope(diagnostics: widget.diagnostics!, child: app);
  }

  Widget _buildMaterialApp(BuildContext context, Widget? child) => MaterialApp(
    title: widget.edition == AppEdition.lite ? 'LumiaKey Lite' : 'LumiaKey',
    navigatorObservers: [localDictationRouteObserver],
    debugShowCheckedModeBanner: false,
    locale: _appearance.language.locale,
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    supportedLocales: const [Locale('en'), Locale('zh', 'CN')],
    themeMode: _appearance.themeMode,
    theme: _theme(Brightness.light),
    darkTheme: _theme(Brightness.dark),
    home: AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        if (controller.isLoading) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (controller.error != null) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, size: 48),
                    const SizedBox(height: 16),
                    const MobileText(
                      'LumiaKey could not load its configuration.',
                      'LumiaKey 无法加载配置。',
                    ),
                    const SizedBox(height: 8),
                    Text('${controller.error}', textAlign: TextAlign.center),
                  ],
                ),
              ),
            ),
          );
        }
        final home =
            widget.homeOverride ??
            (widget.edition == AppEdition.lite
                ? const HomeScreen(liteMode: true)
                : const RegularHomeScreen());
        if (widget.diagnostics == null) return home;
        return DiagnosticsConsentGate(
          diagnostics: widget.diagnostics!,
          child: home,
        );
      },
    ),
  );

  static ThemeData _theme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final colors = ColorScheme.fromSeed(
      seedColor: const Color(0xFF67E8F9),
      brightness: brightness,
      surface: dark ? const Color(0xFF10151D) : null,
    );
    return ThemeData(
      colorScheme: colors,
      scaffoldBackgroundColor: dark ? const Color(0xFF090D12) : colors.surface,
      cardTheme: CardThemeData(
        color: dark ? const Color(0xFF151C26) : colors.surfaceContainerLow,
        elevation: 0,
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
      useMaterial3: true,
    );
  }
}

class SmartKeysScope extends InheritedNotifier<AppController> {
  const SmartKeysScope({
    super.key,
    required AppController controller,
    required super.child,
    this.edition = buildEdition,
  }) : super(notifier: controller);

  final AppEdition edition;

  static AppEdition editionOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SmartKeysScope>()?.edition ??
      buildEdition;

  static AppController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<SmartKeysScope>();
    assert(scope != null, 'SmartKeysScope is missing');
    return scope!.notifier!;
  }
}

class _EditionOrientationService implements OrientationService {
  const _EditionOrientationService(this.edition);

  final AppEdition edition;

  @override
  Future<void> apply(OrientationMode mode) => const SystemOrientationService()
      .apply(edition == AppEdition.regular ? OrientationMode.landscape : mode);
}
