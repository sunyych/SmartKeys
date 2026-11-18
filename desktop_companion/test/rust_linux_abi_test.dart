import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumiakeys_companion/desktop_native_backend.dart';

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
  final environment = Platform.environment;
  final libraryPath = environment['LUMIAKEY_TEST_DESKTOP_NATIVE_LIBRARY'];
  final canLoad = Platform.isLinux && libraryPath != null;

  group(
    'packaged Linux Rust ABI',
    () {
      late DynamicLibrary library;

      setUp(() {
        library = DynamicLibrary.open(libraryPath!);
        addTearDown(library.close);
      });

      test(
        'ABI version and read-only X11 pointer status are available',
        () async {
          final version = library
              .lookupFunction<Uint32 Function(), int Function()>(
                'lumiakeys_desktop_abi_version',
              );
          expect(version(), 1);
          expect(sizeOf<_RawPointerInput>(), 16);

          final status = library
              .lookupFunction<Int32 Function(), int Function()>(
                'lumiakeys_desktop_pointer_status_v1',
              )();
          final backend = RustDesktopBackend.fromPath(libraryPath!);
          if (environment['LUMIAKEY_TEST_LINUX_EXPECT_X11'] == '1') {
            expect(status, 0);
            expect(await backend.supportsPointer(), isTrue);
          } else if ((environment['DISPLAY'] ?? '').isEmpty ||
              (environment['WAYLAND_DISPLAY'] ?? '').isNotEmpty ||
              environment['XDG_SESSION_TYPE']?.toLowerCase() == 'wayland') {
            expect(status, 5);
            expect(await backend.supportsPointer(), isFalse);
          } else {
            expect(status, anyOf(0, 5));
            expect(await backend.supportsPointer(), status == 0);
          }
        },
      );

      test(
        'packaged Rust reads a process snapshot and nullable foreground',
        () async {
          final backend = RustDesktopBackend.fromPath(libraryPath!);
          final snapshot = await backend.readProcesses();
          expect(snapshot.runningProcesses.isNotEmpty, isTrue);
          expect(
            snapshot.runningProcesses.every((name) => name.isNotEmpty),
            isTrue,
          );
          expect(snapshot.foregroundProcess?.isEmpty ?? false, isFalse);

          final foreground = await backend.readForegroundProcess();
          expect(foreground?.isEmpty ?? false, isFalse);
        },
      );

      test('rejected Linux reads preserve the entire caller buffer', () {
        final read = library.lookupFunction<_ReadNative, _ReadDart>(
          'lumiakeys_desktop_read_v1',
        );
        using((arena) {
          const capacity = 16;
          final output = arena<Uint8>(capacity);
          final bytes = output.asTypedList(capacity)
            ..fillRange(0, capacity, 0xa5);

          expect(read(3, output, capacity), -1);
          expect(read(1, nullptr, capacity), -1);
          expect(read(2, output, 0), -1);
          expect(read(1, output, 1), -3);
          expect(bytes, everyElement(0xa5));
        });
      });

      test('native pointer ABI rejects malformed and out-of-range batches', () {
        final apply = library.lookupFunction<_PointerNative, _PointerDart>(
          'lumiakeys_desktop_pointer_v1',
        );
        using((arena) {
          final inputs = arena<_RawPointerInput>(33);
          for (var index = 0; index < 33; index++) {
            inputs[index]
              ..kind = -1
              ..x = 0
              ..y = 0
              ..secondary = 0;
          }

          expect(apply(nullptr, 1), 1);
          expect(apply(inputs, 0), 1);
          expect(apply(inputs, 33), 1);
          expect(apply(inputs, 1), 1);
        });
      });
    },
    skip: canLoad ? false : 'Requires the packaged Linux Rust desktop library',
  );
}
