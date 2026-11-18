import 'dart:io';

import 'package:path/path.dart' as path;

import 'desktop_native_backend.dart';
import 'windows_shortcut_backend.dart';

const windowsDesktopBackendEnvironment = 'LUMIAKEY_WINDOWS_DESKTOP_BACKEND';

typedef WindowsProcessSnapshot = DesktopProcessSnapshot;

class WindowsRegisteredAppPath {
  const WindowsRegisteredAppPath({required this.name, required this.path});

  final String name;
  final String path;
}

class WindowsRegistryInventory {
  const WindowsRegistryInventory({
    required this.installedNames,
    required this.appPaths,
  });

  final List<String> installedNames;
  final List<WindowsRegisteredAppPath> appPaths;

  WindowsRegisteredAppPath? findExecutable(String name) {
    final executable = name.toLowerCase();
    for (final entry in appPaths) {
      if (entry.name.toLowerCase() == executable) return entry;
    }
    return null;
  }
}

abstract interface class WindowsDesktopBackend implements NativeDesktopBackend {
  Future<WindowsRegistryInventory> readRegistry();
}

WindowsDesktopBackend? selectWindowsDesktopBackend({
  required bool isWindows,
  required Map<String, String> environment,
}) {
  if (!isWindows ||
      (environment[windowsDesktopBackendEnvironment] != 'rust' &&
          environment[desktopBackendEnvironment] != 'rust')) {
    return null;
  }
  return RustWindowsDesktopBackend.fromPath(
    path.join(
      path.dirname(Platform.resolvedExecutable),
      windowsShortcutLibraryName,
    ),
  );
}

class RustWindowsDesktopBackend extends RustDesktopBackend
    implements WindowsDesktopBackend {
  RustWindowsDesktopBackend.fromPath(super.libraryPath) : super.fromPath();

  @override
  Future<WindowsRegistryInventory> readRegistry() async {
    final value = await readJson(3, 2 * 1024 * 1024);
    if (value is Map &&
        value['installedNames'] is List &&
        (value['installedNames'] as List).every((name) => name is String) &&
        value['appPaths'] is List) {
      final paths = <WindowsRegisteredAppPath>[];
      for (final entry in value['appPaths'] as List) {
        if (entry is! Map ||
            entry['name'] is! String ||
            entry['path'] is! String) {
          throw StateError('The Rust Windows registry response was invalid.');
        }
        paths.add(
          WindowsRegisteredAppPath(
            name: entry['name'] as String,
            path: entry['path'] as String,
          ),
        );
      }
      return WindowsRegistryInventory(
        installedNames: (value['installedNames'] as List).cast<String>(),
        appPaths: paths,
      );
    }
    throw StateError('The Rust Windows registry response was invalid.');
  }
}
