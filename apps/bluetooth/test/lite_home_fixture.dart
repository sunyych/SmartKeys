import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lumiakey_bluetooth_lite/lite_controller.dart';
import 'package:lumiakey_bluetooth_lite/lite_home_screen.dart';
import 'package:lumiakey_bluetooth_lite/local_launcher.dart';
import 'package:lumiakey_bluetooth_lite/local_profiles.dart';

class SurfaceProfiles implements LocalProfileStore {
  SurfaceProfiles([List<LocalProfile>? values])
    : values = values ?? defaultLocalProfiles();
  List<LocalProfile> values;
  @override
  Future<List<LocalProfile>> load() async => values;
  @override
  Future<void> save(List<LocalProfile> profiles) async => values = profiles;
}

/// All input ends in a mock Android channel. No physical HID device is used.
class LiteHomeFixture {
  static const channel = MethodChannel('smart_keys/hid');
  final calls = <MethodCall>[];
  late final LiteController controller;
  Map<String, Object?> snapshot = {
    'status': 'connected',
    'activeHost': {
      'id': 'studio',
      'name': 'Studio laptop',
      'address': 'AA:BB:CC:DD:EE:01',
    },
    'pairedHosts': [
      {'id': 'studio', 'name': 'Studio laptop', 'address': 'AA:BB:CC:DD:EE:01'},
    ],
  };
  bool failInput = false;
  List<MethodCall> get inputs =>
      calls.where((call) => call.method == 'sendStep').toList();

  Future<void> initialize({
    List<LocalProfile>? profiles,
    List<LocalLaunchSlot>? slots,
    bool connected = true,
  }) async {
    SharedPreferences.setMockInitialValues({});
    if (!connected) {
      snapshot = {...snapshot, 'status': 'disconnected', 'activeHost': null};
    }
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'getAppMetadata') {
            return {'appVersion': '1.2.0', 'appBuild': 3};
          }
          if (call.method == 'sendStep' && failInput) {
            throw PlatformException(code: 'fixture_failure');
          }
          if (call.method == 'refreshPairedHosts' ||
              call.method == 'sendStep') {
            return snapshot;
          }
          return null;
        });
    final launcher = MemoryLocalLauncherStore();
    if (slots != null) launcher.slots = slots;
    controller = LiteController(
      profileStore: SurfaceProfiles(profiles),
      launcherStore: launcher,
    );
    await controller.initialize();
    await controller.diagnostics.initialize();
  }

  Future<void> mount(
    WidgetTester tester, {
    Size size = const Size(844, 390),
    double textScale = 1,
    EdgeInsets padding = EdgeInsets.zero,
    GlobalKey? boundary,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: MaterialApp(
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
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(textScale),
              padding: padding,
            ),
            child: child!,
          ),
          home: LiteHomeScreen(controller: controller),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    await tester.pump();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  }
}

List<LocalLaunchSlot> configuredSurfaceSlots({bool linked = true}) {
  final slots = defaultLocalLauncherSlots();
  slots[0] = LocalLaunchSlot(
    title: 'ChatGPT',
    iconId: 'chatgpt',
    profileId: linked ? 'chatgpt' : null,
    launchShortcut: const LocalShortcut(
      title: 'Open ChatGPT',
      keyCode: 'G',
      modifiers: ['LEFT_CTRL', 'LEFT_ALT'],
    ),
  );
  slots[1] = const LocalLaunchSlot(
    title: 'Chrome',
    iconId: 'chrome',
    profileId: 'chrome',
    launchShortcut: LocalShortcut(
      title: 'Open Chrome',
      keyCode: 'C',
      modifiers: ['LEFT_CTRL', 'LEFT_ALT'],
    ),
  );
  return slots;
}
