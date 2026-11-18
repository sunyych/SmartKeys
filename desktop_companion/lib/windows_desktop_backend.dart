import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:lumiakeys_protocol/lumiakeys_protocol.dart';
import 'package:path/path.dart' as path;

import 'windows_shortcut_backend.dart';

const windowsDesktopBackendEnvironment = 'LUMIAKEY_WINDOWS_DESKTOP_BACKEND';

class WindowsProcessSnapshot {
  const WindowsProcessSnapshot({
    required this.runningProcesses,
    required this.foregroundProcess,
  });

  final List<String> runningProcesses;
  final String? foregroundProcess;
}

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

abstract interface class WindowsDesktopBackend {
  Future<bool> supportsPointer();
  Future<void> applyPointerInputs(List<PointerInput> inputs);
  Future<WindowsProcessSnapshot> readProcesses();
  Future<String?> readForegroundProcess();
  Future<WindowsRegistryInventory> readRegistry();
}

WindowsDesktopBackend? selectWindowsDesktopBackend({
  required bool isWindows,
  required Map<String, String> environment,
}) {
  if (!isWindows || environment[windowsDesktopBackendEnvironment] != 'rust') {
    return null;
  }
  return RustWindowsDesktopBackend.fromPath(
    path.join(
      path.dirname(Platform.resolvedExecutable),
      windowsShortcutLibraryName,
    ),
  );
}

final class _NativePointerInput extends Struct {
  @Int32()
  external int kind;
  @Int32()
  external int x;
  @Int32()
  external int y;
  @Int32()
  external int secondary;
}

typedef _ReadNative = Int32 Function(Uint32, Pointer<Uint8>, Uint32);
typedef _ReadDart = int Function(int, Pointer<Uint8>, int);
typedef _PointerNative = Int32 Function(Pointer<_NativePointerInput>, Uint32);
typedef _PointerDart = int Function(Pointer<_NativePointerInput>, int);

class RustWindowsDesktopBackend implements WindowsDesktopBackend {
  RustWindowsDesktopBackend.fromPath(this._libraryPath);

  static const _maxOutput = 2 * 1024 * 1024;
  final String _libraryPath;
  Future<void> _pointerTail = Future<void>.value();

  static T _withLibrary<T>(String path, T Function(DynamicLibrary) invoke) {
    DynamicLibrary? library;
    try {
      library = DynamicLibrary.open(path);
      final version = library.lookupFunction<Uint32 Function(), int Function()>(
        'lumiakeys_desktop_abi_version',
      )();
      if (version != 1) throw StateError('Unsupported Windows Desktop ABI.');
      return invoke(library);
    } on ArgumentError {
      throw StateError('The Rust Windows Desktop backend could not be loaded.');
    } finally {
      library?.close();
    }
  }

  static _PointerDart _lookupPointer(DynamicLibrary library) =>
      library.lookupFunction<_PointerNative, _PointerDart>(
        'lumiakeys_desktop_pointer_v1',
      );

  @override
  Future<bool> supportsPointer() async {
    final libraryPath = _libraryPath;
    try {
      return await Isolate.run(() {
        return _withLibrary(libraryPath, (library) {
          _lookupPointer(library);
          return true;
        });
      });
    } on StateError {
      return false;
    }
  }

  @override
  Future<void> applyPointerInputs(List<PointerInput> inputs) async {
    if (inputs.isEmpty ||
        inputs.length > 32 ||
        inputs.any(
          (input) => switch (input.kind) {
            PointerInputKind.move =>
              input.x < -127 ||
                  input.x > 127 ||
                  input.y < -127 ||
                  input.y > 127,
            PointerInputKind.scroll =>
              input.y == 0 || input.y < -127 || input.y > 127,
            PointerInputKind.button => input.secondary == null,
          },
        )) {
      throw const FormatException('Invalid Windows pointer batch.');
    }
    final snapshot = List<PointerInput>.of(inputs, growable: false);
    final libraryPath = _libraryPath;
    final delivered = _pointerTail.then(
      (_) => _applyPointerBatchInBackground(libraryPath, snapshot),
    );
    _pointerTail = delivered.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    await delivered;
  }

  static Future<void> _applyPointerBatchInBackground(
    String libraryPath,
    List<PointerInput> inputs,
  ) async {
    final status = await Isolate.run(() => _sendPointer(libraryPath, inputs));
    if (status == 0) return;
    final message = switch (status) {
      1 => 'Invalid Windows pointer batch.',
      2 => 'Windows rejected pointer delivery.',
      3 => 'Windows accepted only part of the pointer batch.',
      4 =>
        'Windows accepted part of the pointer batch and button release failed.',
      _ => 'The Rust Windows pointer backend failed.',
    };
    throw StateError(message);
  }

  static int _sendPointer(String libraryPath, List<PointerInput> inputs) =>
      _withLibrary(libraryPath, (library) {
        final send = _lookupPointer(library);
        return using((arena) {
          final native = arena<_NativePointerInput>(inputs.length);
          for (var index = 0; index < inputs.length; index++) {
            final input = inputs[index];
            final value = native[index];
            value.kind = switch (input.kind) {
              PointerInputKind.move => 0,
              PointerInputKind.scroll => 1,
              PointerInputKind.button => 2,
            };
            value.x = input.x;
            value.y = input.y;
            value.secondary = input.secondary == true ? 1 : 0;
          }
          return send(native, inputs.length);
        });
      });

  Future<Object?> _read(int kind, int capacity) {
    final libraryPath = _libraryPath;
    return Isolate.run(() => _readNative(libraryPath, kind, capacity));
  }

  static Object? _readNative(String libraryPath, int kind, int capacity) =>
      _withLibrary(libraryPath, (library) {
        final read = library.lookupFunction<_ReadNative, _ReadDart>(
          'lumiakeys_desktop_read_v1',
        );
        return using((arena) {
          final output = arena<Uint8>(capacity);
          final length = read(kind, output, capacity);
          if (length <= 0 || length > capacity) {
            throw StateError('The Rust Windows Desktop read failed.');
          }
          try {
            return jsonDecode(utf8.decode(output.asTypedList(length)));
          } on FormatException {
            throw StateError('The Rust Windows Desktop response was invalid.');
          }
        });
      });

  @override
  Future<WindowsProcessSnapshot> readProcesses() async {
    final value = await _read(1, 256 * 1024);
    if (value is Map &&
        value['runningProcesses'] is List &&
        (value['runningProcesses'] as List).every((name) => name is String) &&
        (value['foregroundProcess'] == null ||
            value['foregroundProcess'] is String)) {
      return WindowsProcessSnapshot(
        runningProcesses: (value['runningProcesses'] as List).cast<String>(),
        foregroundProcess: value['foregroundProcess'] as String?,
      );
    }
    throw StateError('The Rust Windows process response was invalid.');
  }

  @override
  Future<String?> readForegroundProcess() async {
    final value = await _read(2, 4096);
    if (value == null || value is String) return value as String?;
    throw StateError('The Rust Windows foreground response was invalid.');
  }

  @override
  Future<WindowsRegistryInventory> readRegistry() async {
    final value = await _read(3, _maxOutput);
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
