import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as path;

const windowsShortcutBackendEnvironment = 'LUMIAKEY_WINDOWS_SHORTCUT_BACKEND';
const windowsShortcutLibraryName = 'lumiakeys_windows_shortcuts.dll';

enum WindowsShortcutModifier { control, alt, shift }

class WindowsShortcut {
  const WindowsShortcut({
    required this.key,
    required this.modifiers,
    required this.allowedProcesses,
  });

  final String key;
  final List<WindowsShortcutModifier> modifiers;
  final List<String> allowedProcesses;
}

abstract interface class WindowsShortcutBackend {
  Future<void> send(WindowsShortcut shortcut);
}

typedef _SendNative = Int32 Function(Pointer<Utf8>, Uint32, Pointer<Utf8>);
typedef _SendDart = int Function(Pointer<Utf8>, int, Pointer<Utf8>);

class RustWindowsShortcutBackend implements WindowsShortcutBackend {
  const RustWindowsShortcutBackend.fromPath(this._libraryPath);

  static RustWindowsShortcutBackend load() {
    final directory = path.dirname(Platform.resolvedExecutable);
    return RustWindowsShortcutBackend.fromPath(
      path.join(directory, windowsShortcutLibraryName),
    );
  }

  static _SendDart _lookupSend(DynamicLibrary library) {
    final version = library.lookupFunction<Uint32 Function(), int Function()>(
      'lumiakeys_shortcut_abi_version',
    )();
    if (version != 1) throw StateError('Unsupported Windows shortcut ABI.');
    return library.lookupFunction<_SendNative, _SendDart>(
      'lumiakeys_send_shortcut_v1',
    );
  }

  final String _libraryPath;

  @override
  Future<void> send(WindowsShortcut shortcut) async {
    final libraryPath = _libraryPath;
    final status = await Isolate.run(() => _invoke(libraryPath, shortcut));
    if (status == 0) return;
    final message = switch (status) {
      1 => 'Invalid Windows shortcut request.',
      2 => 'Switch to the matching application before using this shortcut.',
      3 => 'Switch to the main ChatGPT window before using this shortcut.',
      4 => 'Release held modifier keys before using this shortcut.',
      5 => 'The foreground window changed before shortcut delivery.',
      6 => 'The active keyboard layout cannot produce this shortcut.',
      7 => 'Windows rejected shortcut delivery.',
      8 => 'Windows accepted only part of the shortcut.',
      9 => 'Windows accepted only part of the shortcut and key release failed.',
      _ => 'The Windows shortcut backend failed.',
    };
    throw StateError(message);
  }

  static int _invoke(String libraryPath, WindowsShortcut shortcut) {
    late final DynamicLibrary library;
    try {
      library = DynamicLibrary.open(libraryPath);
    } on ArgumentError {
      throw StateError('The Rust shortcut backend could not be loaded.');
    }
    try {
      late final _SendDart send;
      try {
        send = _lookupSend(library);
      } on ArgumentError {
        throw StateError('Unsupported Windows shortcut ABI.');
      }
      var modifiers = 0;
      for (final modifier in shortcut.modifiers) {
        modifiers |= switch (modifier) {
          WindowsShortcutModifier.control => 1,
          WindowsShortcutModifier.alt => 2,
          WindowsShortcutModifier.shift => 4,
        };
      }
      return using((arena) {
        final key = shortcut.key.toNativeUtf8(allocator: arena);
        final processes = shortcut.allowedProcesses
            .join(',')
            .toNativeUtf8(allocator: arena);
        return send(key, modifiers, processes);
      });
    } finally {
      library.close();
    }
  }
}
