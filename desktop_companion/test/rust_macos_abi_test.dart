import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumiakeys_companion/desktop_native_backend.dart';
import 'package:path/path.dart' as path;

typedef _VersionNative = Uint32 Function();
typedef _VersionDart = int Function();
typedef _StatusNative = Int32 Function();
typedef _StatusDart = int Function();
typedef _ReadNative = Int32 Function(Uint32, Pointer<Uint8>, Uint32);
typedef _ReadDart = int Function(int, Pointer<Uint8>, int);
typedef _PointerNative = Int32 Function(Pointer<_RawPointerInput>, Uint32);
typedef _PointerDart = int Function(Pointer<_RawPointerInput>, int);

final class _RawPointerInput extends Struct {
  @Int32()
  external int kind;
  @Int32()
  external int x;
  @Int32()
  external int y;
  @Int32()
  external int secondary;
}

void main() {
  test('Mac uses the Rust library only with the unified opt-in', () {
    NativeDesktopBackend? select(Map<String, String> environment) =>
        selectNativeDesktopBackend(
          platform: TargetPlatform.macOS,
          environment: environment,
        );

    expect(select(const {}), isNull);
    expect(select(const {'LUMIAKEY_WINDOWS_DESKTOP_BACKEND': 'rust'}), isNull);
    expect(select(const {'LUMIAKEY_DESKTOP_BACKEND': 'legacy'}), isNull);
    expect(
      select(const {'LUMIAKEY_DESKTOP_BACKEND': 'rust'}),
      isA<RustDesktopBackend>(),
    );
  });

  test(
    'missing Mac Rust library fails to initialize and advertises no input',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'lumiakeys-mac-abi-',
      );
      addTearDown(directory.delete);
      final backend = RustDesktopBackend.fromPath(
        path.join(directory.path, 'liblumiakeys_desktop.dylib'),
      );

      expect(await backend.supportsPointer(), isFalse);
      await expectLater(backend.readForegroundProcess(), throwsStateError);
    },
  );

  final libraryPath =
      Platform.environment['LUMIAKEY_TEST_DESKTOP_NATIVE_LIBRARY'];
  group(
    'macOS Rust desktop ABI',
    () {
      late DynamicLibrary library;

      setUp(() {
        library = DynamicLibrary.open(libraryPath!);
        addTearDown(library.close);
      });

      test('loads ABI v1 and probes event access without posting events', () {
        final version = library.lookupFunction<_VersionNative, _VersionDart>(
          'lumiakeys_desktop_abi_version',
        );
        final permission = library.lookupFunction<_StatusNative, _StatusDart>(
          'lumiakeys_desktop_pointer_status_v1',
        );
        expect(version(), 1);
        expect(sizeOf<_RawPointerInput>(), 16);
        expect(permission(), anyOf(0, 6));
      });

      test('reads only structured inventory and nullable foreground data', () {
        final read = library.lookupFunction<_ReadNative, _ReadDart>(
          'lumiakeys_desktop_read_v1',
        );
        using((arena) {
          const capacity = 256 * 1024;
          final buffer = arena<Uint8>(capacity);

          Object? json(int kind) {
            final length = read(kind, buffer, capacity);
            expect(length, inInclusiveRange(1, capacity));
            return jsonDecode(utf8.decode(buffer.asTypedList(length)));
          }

          final inventory = (json(1) as Map).cast<String, Object?>();
          final processes = inventory['runningProcesses'];
          final foreground = inventory['foregroundProcess'];
          expect(
            processes is List && processes.every((name) => name is String),
            isTrue,
          );
          expect(inventory.containsKey('foregroundProcess'), isTrue);
          expect(foreground == null || foreground is String, isTrue);
          final current = json(2);
          expect(current == null || current is String, isTrue);
        });
      });

      test(
        'the Dart adapter initializes the actual packaged Mac library',
        () async {
          final backend = RustDesktopBackend.fromPath(libraryPath!);
          expect(await backend.supportsPointer(), isTrue);
          final snapshot = await backend.readProcesses();
          expect(snapshot.runningProcesses, isA<List<String>>());
          expect(snapshot.foregroundProcess, anyOf(isNull, isA<String>()));
          expect(
            await backend.readForegroundProcess(),
            anyOf(isNull, isA<String>()),
          );
        },
      );

      test('rejects unsupported reads and malformed pointer inputs', () {
        final read = library.lookupFunction<_ReadNative, _ReadDart>(
          'lumiakeys_desktop_read_v1',
        );
        final pointer = library.lookupFunction<_PointerNative, _PointerDart>(
          'lumiakeys_desktop_pointer_v1',
        );
        using((arena) {
          final buffer = arena<Uint8>(32)..value = 0xa5;
          expect(read(3, buffer, 32), -1);
          expect(read(2, nullptr, 32), -1);
          expect(read(2, buffer, 0), -1);
          expect(buffer.value, 0xa5);

          final invalid = arena<_RawPointerInput>();
          invalid.ref
            ..kind = 0
            ..x = 128
            ..y = 1
            ..secondary = 0;
          expect(pointer(nullptr, 1), 1);
          expect(pointer(invalid, 0), 1);
          expect(pointer(invalid, 1), 1);
        });
      });
    },
    skip: !Platform.isMacOS || libraryPath == null || libraryPath.isEmpty
        ? 'Requires a packaged macOS Rust dylib'
        : false,
  );
}
