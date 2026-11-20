import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'desktop_controller.dart';
import 'desktop_dictation.dart';
import 'desktop_localizations.dart';

const desktopBrandAsset = 'assets/tray_icon.png';

class DesktopTrayShell with TrayListener, WindowListener {
  DesktopTrayShell({
    required this.controller,
    required this.dictation,
    Locale? locale,
  }) : _locale = locale ?? const Locale('en');

  final DesktopController controller;
  final DesktopDictationService dictation;
  Locale _locale;
  bool _disposed = false;

  void setLocale(Locale locale) {
    if (_disposed || _locale == locale) return;
    _locale = locale;
    unawaited(_refreshMenu());
  }

  String _text(String english, String chinese) =>
      desktopLocaleText(_locale, english, chinese);

  Future<void> initialize() async {
    trayManager.addListener(this);
    windowManager.addListener(this);
    controller.addListener(_controllerChanged);
    dictation.addListener(_controllerChanged);
    await trayManager.setIcon(
      Platform.isWindows ? 'assets/tray_icon.ico' : desktopBrandAsset,
      // The LumiaKey artwork is a full-color mark. Treating it as a macOS
      // template image collapses its opaque circular background into a mask.
      isTemplate: false,
      iconSize: 20,
    );
    await trayManager.setToolTip('LumiaKey');
    await windowManager.setPreventClose(true);
    await _refreshMenu();
  }

  void _controllerChanged() => unawaited(_refreshMenu());

  Future<void> _refreshMenu() async {
    if (_disposed) return;
    final profiles = Menu(
      items: controller.manifest.profiles
          .map(
            (profile) => MenuItem.checkbox(
              key: 'profile:${profile.id}',
              label: profile.name,
              checked: profile.id == controller.manifest.currentProfileId,
            ),
          )
          .toList(growable: false),
    );
    await trayManager.setContextMenu(
      Menu(
        items: [
          MenuItem(key: 'settings', label: _text('Open Settings', '打开设置')),
          MenuItem(key: 'launcher', label: _text('Open Launcher', '打开启动台')),
          MenuItem(
            key: 'dictation',
            label: dictation.testFlightInput
                ? _text('Open Local Dictation', '打开本地听写')
                : dictation.listening
                ? _text('Stop Local Dictation', '停止本地听写')
                : _text('Start Local Dictation', '开始本地听写'),
          ),
          MenuItem(
            key: 'phone',
            label: controller.connectedPhone == null
                ? _text('Connected Phone · None', '已连接手机 · 无')
                : '${_text('Connected Phone', '已连接手机')} · ${controller.connectedPhone}',
            disabled: true,
          ),
          MenuItem.submenu(
            label: _text('Shortcut Profiles', '快捷键配置'),
            submenu: profiles,
          ),
          MenuItem(key: 'about', label: _text('About', '关于')),
          MenuItem.separator(),
          MenuItem(key: 'quit', label: _text('Quit', '退出')),
        ],
      ),
    );
  }

  Future<void> showSection(int section) async {
    controller.selectSection(section);
    await windowManager.setSkipTaskbar(false);
    await windowManager.show();
    await windowManager.focus();
  }

  @override
  void onTrayIconMouseDown() => unawaited(trayManager.popUpContextMenu());

  @override
  void onTrayIconRightMouseDown() => unawaited(trayManager.popUpContextMenu());

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    final key = menuItem.key ?? '';
    if (key == 'settings') {
      unawaited(showSection(0));
    } else if (key == 'launcher') {
      unawaited(showSection(7));
    } else if (key == 'dictation') {
      unawaited(toggleDictation());
    } else if (key == 'about') {
      unawaited(showSection(5));
    } else if (key.startsWith('profile:')) {
      unawaited(controller.switchProfile(key.substring('profile:'.length)));
    } else if (key == 'quit') {
      unawaited(_quit());
    }
  }

  Future<void> toggleDictation() async {
    if (dictation.testFlightInput) {
      await showSection(6);
      return;
    }
    if (!dictation.firstUseAcknowledged) {
      await showSection(6);
      return;
    }
    // Keep the target application focused while stopping or beginning capture.
    // start() hides the window itself and restores it only when setup fails.
    await dictation.toggle();
  }

  @override
  void onWindowFocus() => unawaited(dictation.refreshAccessibility());

  @override
  void onWindowClose() => unawaited(_hideWindow());

  Future<void> _hideWindow() async {
    await windowManager.hide();
    await windowManager.setSkipTaskbar(true);
  }

  Future<void> _quit() async {
    await windowManager.setPreventClose(false);
    await trayManager.destroy();
    await windowManager.destroy();
    exit(0);
  }

  void dispose() {
    _disposed = true;
    controller.removeListener(_controllerChanged);
    dictation.removeListener(_controllerChanged);
    trayManager.removeListener(this);
    windowManager.removeListener(this);
  }
}
