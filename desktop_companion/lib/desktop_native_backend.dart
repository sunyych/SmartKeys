import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:lumiakeys_protocol/lumiakeys_protocol.dart';
import 'package:path/path.dart' as path;

import 'windows_shortcut_backend.dart';

const desktopBackendEnvironment = 'LUMIAKEY_DESKTOP_BACKEND';

class DesktopProcessSnapshot {
  const DesktopProcessSnapshot({
    required this.runningProcesses,
    required this.foregroundProcess,
  });

  final List<String> runningProcesses;
  final String? foregroundProcess;
}

abstract interface class NativeDesktopBackend {
  Future<bool> supportsPointer();
  Future<void> applyPointerInputs(List<PointerInput> inputs);
  Future<DesktopProcessSnapshot> readProcesses();
  Future<String?> readForegroundProcess();
}

NativeDesktopBackend? selectNativeDesktopBackend({
  required TargetPlatform platform,
  required Map<String, String> environment,
}) {
  if (environment[desktopBackendEnvironment] != 'rust') return null;
  final directory = path.dirname(Platform.resolvedExecutable);
  final bundledLibrary = switch (platform) {
    TargetPlatform.windows => path.join(directory, windowsShortcutLibraryName),
    TargetPlatform.macOS => path.join(
      directory,
      '..',
      'Frameworks',
      'liblumiakeys_desktop.dylib',
    ),
    TargetPlatform.linux => path.join(
      directory,
      'lib',
      'liblumiakeys_desktop.so',
    ),
    _ => null,
  };
  return bundledLibrary == null
      ? null
      : RustDesktopBackend.fromPath(path.normalize(bundledLibrary));
}

TargetPlatform hostDesktopTargetPlatform() => Platform.isWindows
    ? TargetPlatform.windows
    : Platform.isMacOS
    ? TargetPlatform.macOS
    : Platform.isLinux
    ? TargetPlatform.linux
    : defaultTargetPlatform;

bool isLinuxWaylandSession(Map<String, String> environment) =>
    (environment['WAYLAND_DISPLAY'] ?? '').isNotEmpty ||
    environment['XDG_SESSION_TYPE']?.trim().toLowerCase() == 'wayland';

bool isLinuxX11Session(Map<String, String> environment) =>
    (environment['DISPLAY'] ?? '').isNotEmpty &&
    !isLinuxWaylandSession(environment);

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

class RustDesktopBackend implements NativeDesktopBackend {
  RustDesktopBackend.fromPath(this._libraryPath);

  final String _libraryPath;
  Future<void> _pointerTail = Future<void>.value();

  static T _withLibrary<T>(String path, T Function(DynamicLibrary) invoke) {
    DynamicLibrary? library;
    try {
      library = DynamicLibrary.open(path);
      final version = library.lookupFunction<Uint32 Function(), int Function()>(
        'lumiakeys_desktop_abi_version',
      )();
      if (version != 1) throw StateError('Unsupported Desktop ABI.');
      return invoke(library);
    } on ArgumentError {
      throw StateError('The Rust Desktop backend could not be loaded.');
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
          final status = library
              .lookupFunction<Int32 Function(), int Function()>(
                'lumiakeys_desktop_pointer_status_v1',
              );
          final availability = status();
          // macOS permissions can be granted while Desktop stays running.
          return availability == 0 || (Platform.isMacOS && availability == 6);
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
      throw const FormatException('Invalid pointer batch.');
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
      1 => 'Invalid pointer batch.',
      2 => 'The operating system rejected pointer delivery.',
      3 => 'The operating system accepted only part of the pointer batch.',
      4 =>
        'The operating system accepted part of the pointer batch and button release failed.',
      5 => 'Pointer control is unavailable in this desktop session.',
      6 => 'Allow LumiaKey Desktop in macOS Accessibility settings.',
      _ => 'The Rust pointer backend failed.',
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

  @protected
  Future<Object?> readJson(int kind, int capacity) {
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
            throw StateError('The Rust Desktop read failed.');
          }
          try {
            return jsonDecode(utf8.decode(output.asTypedList(length)));
          } on FormatException {
            throw StateError('The Rust Desktop response was invalid.');
          }
        });
      });

  @override
  Future<DesktopProcessSnapshot> readProcesses() async {
    final value = await readJson(1, 256 * 1024);
    if (value is Map &&
        value['runningProcesses'] is List &&
        (value['runningProcesses'] as List).every((name) => name is String) &&
        (value['foregroundProcess'] == null ||
            value['foregroundProcess'] is String)) {
      return DesktopProcessSnapshot(
        runningProcesses: (value['runningProcesses'] as List).cast<String>(),
        foregroundProcess: value['foregroundProcess'] as String?,
      );
    }
    throw StateError('The Rust desktop process response was invalid.');
  }

  @override
  Future<String?> readForegroundProcess() async {
    final value = await readJson(2, 4096);
    if (value == null || value is String) return value as String?;
    throw StateError('The Rust desktop foreground response was invalid.');
  }
}
