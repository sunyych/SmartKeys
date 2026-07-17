import 'package:flutter/material.dart';

import 'controllers/app_controller.dart';
import 'data/config_repository.dart';
import 'data/private_image_store.dart';
import 'data/profile_template_repository.dart';
import 'services/hid_service.dart';
import 'services/orientation_service.dart';
import 'services/power_brightness_service.dart';
import 'ui/home_screen.dart';

class SmartKeysApp extends StatefulWidget {
  const SmartKeysApp({super.key, this.controller});

  final AppController? controller;

  @override
  State<SmartKeysApp> createState() => _SmartKeysAppState();
}

class _SmartKeysAppState extends State<SmartKeysApp>
    with WidgetsBindingObserver {
  late final AppController controller;
  late final bool ownsController;

  @override
  void initState() {
    super.initState();
    ownsController = widget.controller == null;
    final templates = ProfileTemplateRepository();
    controller =
        widget.controller ??
        AppController(
          repository: SharedPreferencesConfigRepository(templates: templates),
          templates: templates,
          hid: MethodChannelHidService(),
          orientationService: SystemOrientationService(),
          imageStore: PrivateImageStore(),
          powerBrightnessService: MethodChannelPowerBrightnessService(),
        );
    WidgetsBinding.instance.addObserver(this);
    if (widget.controller == null || controller.isLoading) {
      controller.initialize();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (ownsController) controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !controller.isLoading) {
      controller.handleAppResumed();
    }
  }

  @override
  Widget build(BuildContext context) {
    return SmartKeysScope(
      controller: controller,
      child: MaterialApp(
        title: 'SmartKeys',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF67E8F9),
            brightness: Brightness.dark,
            surface: const Color(0xFF10151D),
          ),
          scaffoldBackgroundColor: const Color(0xFF090D12),
          cardTheme: const CardThemeData(
            color: Color(0xFF151C26),
            elevation: 0,
            margin: EdgeInsets.zero,
          ),
          inputDecorationTheme: const InputDecorationTheme(
            border: OutlineInputBorder(),
          ),
          useMaterial3: true,
        ),
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
                        const Text(
                          'SmartKeys could not load its configuration.',
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${controller.error}',
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }
            return const HomeScreen();
          },
        ),
      ),
    );
  }
}

class SmartKeysScope extends InheritedNotifier<AppController> {
  const SmartKeysScope({
    super.key,
    required AppController controller,
    required super.child,
  }) : super(notifier: controller);

  static AppController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<SmartKeysScope>();
    assert(scope != null, 'SmartKeysScope is missing');
    return scope!.notifier!;
  }
}
