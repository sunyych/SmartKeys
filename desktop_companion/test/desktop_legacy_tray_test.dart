import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_dictation/local_dictation.dart';
import 'package:lumiakeys_companion/desktop_controller.dart';
import 'package:lumiakeys_companion/desktop_dictation.dart';
import 'package:lumiakeys_companion/dictation_receiver.dart';
import 'package:lumiakeys_companion/tray_shell.dart';
import 'package:lumiakeys_protocol/lumiakeys_protocol.dart';
import 'package:tray_manager/tray_manager.dart';

const _tray = MethodChannel('tray_manager');
const _window = MethodChannel('window_manager');
const _dictationChannel = MethodChannel('test/legacy_tray_dictation');

class _Discovery implements ApplicationDiscovery {
  @override
  Future<List<RemoteApplication>> refresh(List<RemoteApplication> apps) async =>
      apps;
}

class _UnusedSink implements DictationTextSink {
  @override
  Future<void> insertText(String text) async =>
      throw StateError('Tray tests must not dispatch dictation text');
}

class _UnusedCapture implements DictationCapture {
  @override
  Future<bool> hasPermission() async => false;

  @override
  Future<Stream<List<int>>> start() async =>
      throw StateError('Tray tests must not start microphone capture');

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}

class _Dictation extends DesktopDictationService {
  _Dictation()
    : super(
        textSink: _UnusedSink(),
        capture: _UnusedCapture(),
        preferences: MemoryDictationSettingsStore(),
        channel: _dictationChannel,
      );

  int toggles = 0;
  bool _listening = false;

  @override
  bool get listening => _listening;

  @override
  Future<void> toggle() async {
    toggles++;
    _listening = !_listening;
    notifyListeners();
  }
}

List<Map<String, Object?>> _menuItems(Object? menu) =>
    ((menu as Map)['items'] as List)
        .map((item) => (item as Map).cast<String, Object?>())
        .toList();

Future<void> _flushTrayCallbacks() => Future<void>.delayed(Duration.zero);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late MemoryDesktopConfigStore store;
  late DesktopController controller;
  late _Dictation dictation;
  late DesktopTrayShell shell;
  late List<MethodCall> trayCalls;
  late List<MethodCall> windowCalls;
  late bool minimized;
  late bool disposed;

  setUp(() async {
    trayCalls = [];
    windowCalls = [];
    minimized = false;
    disposed = false;
    messenger.setMockMethodCallHandler(_tray, (call) async {
      trayCalls.add(call);
      return null;
    });
    messenger.setMockMethodCallHandler(_window, (call) async {
      windowCalls.add(call);
      return call.method == 'isMinimized' ? minimized : null;
    });
    messenger.setMockMethodCallHandler(_dictationChannel, (_) async => null);
    final manifest = DesktopManifest.regularStarter();
    store = MemoryDesktopConfigStore()
      ..value = manifest.copyWith(
        profiles: [
          ...manifest.profiles,
          const RemoteProfile(
            id: 'fixture-alt',
            name: 'Fixture Alternate',
            layoutId: 'keyboard',
          ),
        ],
      );
    controller = DesktopController(store: store, discovery: _Discovery());
    await controller.initialize();
    dictation = _Dictation();
    shell = DesktopTrayShell(controller: controller, dictation: dictation);
    await shell.initialize();
  });

  tearDown(() async {
    if (!disposed) shell.dispose();
    controller.dispose();
    await dictation.shutdown();
    dictation.dispose();
    messenger.setMockMethodCallHandler(_tray, null);
    messenger.setMockMethodCallHandler(_window, null);
    messenger.setMockMethodCallHandler(_dictationChannel, null);
  });

  List<Map<String, Object?>> latestMenu() {
    final call = trayCalls.lastWhere((call) => call.method == 'setContextMenu');
    return _menuItems((call.arguments as Map)['menu']);
  }

  List<Map<String, Object?>> profileItems() => _menuItems(
    latestMenu().singleWhere(
      (item) => item['label'] == 'Shortcut Profiles',
    )['submenu'],
  );

  void click(String key) => shell.onTrayMenuItemClick(MenuItem(key: key));

  test(
    'initializes the branded tray and publishes the connected phone',
    () async {
      expect(trayCalls.map((call) => call.method), [
        'setIcon',
        'setToolTip',
        'setContextMenu',
      ]);
      final icon = trayCalls.first.arguments as Map;
      expect(icon['isTemplate'], isFalse);
      expect(icon['iconSize'], 20);
      expect(
        (icon['iconPath'] as String).replaceAll('\\', '/'),
        endsWith(
          Platform.isWindows ? 'assets/tray_icon.ico' : desktopBrandAsset,
        ),
      );
      expect(trayCalls[1].arguments, {'toolTip': 'LumiaKey'});
      expect(windowCalls.single.method, 'setPreventClose');
      expect(windowCalls.single.arguments, {'isPreventClose': true});
      expect(
        latestMenu()
            .where((item) => item['key'] != null)
            .map((item) => item['key']),
        ['settings', 'launcher', 'dictation', 'phone', 'about', 'quit'],
      );
      Map<String, Object?> phone() =>
          latestMenu().singleWhere((item) => item['key'] == 'phone');
      expect(phone()['label'], 'Connected Phone · None');
      expect(phone()['disabled'], isTrue);
      expect(
        profileItems().singleWhere(
          (item) => item['key'] == 'profile:default',
        )['checked'],
        isTrue,
      );

      controller.recordConnectedPhone('192.0.2.5');
      await _flushTrayCallbacks();
      expect(phone()['label'], 'Connected Phone · 192.0.2.5');
      expect(phone()['disabled'], isTrue);
    },
  );

  test('tray navigation restores the window and close hides it', () async {
    windowCalls.clear();
    minimized = true;
    click('launcher');
    await _flushTrayCallbacks();
    expect(controller.selectedSection, 7);
    expect(windowCalls.map((call) => call.method), [
      'setSkipTaskbar',
      'isMinimized',
      'restore',
      'show',
      'focus',
    ]);
    expect(windowCalls.first.arguments, {'isSkipTaskbar': false});

    minimized = false;
    click('about');
    await _flushTrayCallbacks();
    expect(controller.selectedSection, 5);
    click('settings');
    await _flushTrayCallbacks();
    expect(controller.selectedSection, 0);

    windowCalls.clear();
    shell.onWindowClose();
    await _flushTrayCallbacks();
    expect(windowCalls.map((call) => call.method), ['hide', 'setSkipTaskbar']);
    expect(windowCalls.last.arguments, {'isSkipTaskbar': true});
  });

  test(
    'profile menu persists the selection and updates the checkmark',
    () async {
      final previous = controller.manifest.revision;
      click('profile:fixture-alt');
      await _flushTrayCallbacks();
      expect(store.value!.currentProfileId, 'fixture-alt');
      expect(store.value!.revision, previous + 1);
      expect(
        profileItems()
            .where((item) => item['checked'] == true)
            .map((item) => item['key']),
        ['profile:fixture-alt'],
      );
    },
  );

  test(
    'dictation opens consent settings before toggling and updates its menu',
    () async {
      windowCalls.clear();
      await shell.toggleDictation();
      expect(controller.selectedSection, 6);
      expect(dictation.toggles, 0);
      expect(windowCalls.map((call) => call.method), contains('focus'));

      await dictation.acknowledgeFirstUse();
      windowCalls.clear();
      await shell.toggleDictation();
      await _flushTrayCallbacks();
      expect(dictation.toggles, 1);
      expect(windowCalls, isEmpty);
      expect(
        latestMenu().singleWhere((item) => item['key'] == 'dictation')['label'],
        'Stop Local Dictation',
      );

      await shell.toggleDictation();
      await _flushTrayCallbacks();
      expect(dictation.toggles, 2);
      expect(
        latestMenu().singleWhere((item) => item['key'] == 'dictation')['label'],
        'Start Local Dictation',
      );
    },
  );

  test(
    'tray buttons open the context menu and disposal stops menu updates',
    () async {
      trayCalls.clear();
      shell.onTrayIconMouseDown();
      shell.onTrayIconRightMouseDown();
      await _flushTrayCallbacks();
      expect(trayCalls.map((call) => call.method), [
        'popUpContextMenu',
        'popUpContextMenu',
      ]);

      shell.dispose();
      disposed = true;
      trayCalls.clear();
      controller.recordConnectedPhone('192.0.2.8');
      await dictation.toggle();
      await _flushTrayCallbacks();
      expect(trayCalls, isEmpty);
    },
  );
}
