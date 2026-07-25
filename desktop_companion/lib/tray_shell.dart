import 'dart:async';
import 'dart:io';

import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'desktop_controller.dart';

const desktopBrandAsset = 'assets/tray_icon.png';

class DesktopTrayShell with TrayListener, WindowListener {
  DesktopTrayShell({required this.controller});

  final DesktopController controller;
  bool _disposed = false;

  Future<void> initialize() async {
    trayManager.addListener(this);
    windowManager.addListener(this);
    controller.addListener(_controllerChanged);
    await trayManager.setIcon(
      Platform.isWindows ? 'assets/tray_icon.ico' : desktopBrandAsset,
      // The LumiaKeys artwork is a full-color mark. Treating it as a macOS
      // template image collapses its opaque circular background into a mask.
      isTemplate: false,
      iconSize: 20,
    );
    await trayManager.setToolTip('LumiaKeys');
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
          MenuItem(key: 'settings', label: 'Open Settings'),
          MenuItem(
            key: 'phone',
            label: controller.connectedPhone == null
                ? 'Connected Phone · None'
                : 'Connected Phone · ${controller.connectedPhone}',
            disabled: true,
          ),
          MenuItem.submenu(label: 'Shortcut Profiles', submenu: profiles),
          MenuItem(key: 'about', label: 'About'),
          MenuItem.separator(),
          MenuItem(key: 'quit', label: 'Quit'),
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
    } else if (key == 'about') {
      unawaited(showSection(5));
    } else if (key.startsWith('profile:')) {
      unawaited(controller.switchProfile(key.substring('profile:'.length)));
    } else if (key == 'quit') {
      unawaited(_quit());
    }
  }

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
    trayManager.removeListener(this);
    windowManager.removeListener(this);
  }
}
