import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';

typedef _ShortcutNative = Int32 Function(Pointer<Utf8>, Uint32, Pointer<Utf8>);
typedef _ShortcutDart = int Function(Pointer<Utf8>, int, Pointer<Utf8>);
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
  final dllPath = Platform.environment['LUMIAKEY_TEST_WINDOWS_SHORTCUT_DLL'];
  final canLoadDll = Platform.isWindows && dllPath != null;

  group(
    'Windows Rust desktop ABI',
    () {
      late DynamicLibrary library;

      setUp(() {
        library = DynamicLibrary.open(dllPath!);
        addTearDown(library.close);
      });

      test('the original shortcut symbols retain ABI version 1', () {
        final version = library
            .lookupFunction<Uint32 Function(), int Function()>(
              'lumiakeys_shortcut_abi_version',
            );
        expect(version(), 1);
        expect(library.providesSymbol('lumiakeys_send_shortcut_v1'), isTrue);
      });

      test('shortcut ABI rejects null and malformed UTF-8 data', () {
        final send = library.lookupFunction<_ShortcutNative, _ShortcutDart>(
          'lumiakeys_send_shortcut_v1',
        );
        using((arena) {
          final emptyProcesses = ''.toNativeUtf8(allocator: arena);
          final invalidKey = 'F13'.toNativeUtf8(allocator: arena);
          final invalidUtf8 = arena<Uint8>(2);
          invalidUtf8.asTypedList(2).setAll(0, [0xc0, 0]);

          expect(send(nullptr, 0, emptyProcesses), 1);
          expect(send(invalidKey, 0, nullptr), 1);
          expect(send(invalidUtf8.cast(), 0, emptyProcesses), 1);
          expect(send(invalidKey, 0, invalidUtf8.cast()), 1);
        });
      });

      test('desktop exports are versioned independently from shortcuts', () {
        final version = library
            .lookupFunction<Uint32 Function(), int Function()>(
              'lumiakeys_desktop_abi_version',
            );
        expect(version(), 1);
        expect(library.providesSymbol('lumiakeys_desktop_read_v1'), isTrue);
        expect(library.providesSymbol('lumiakeys_desktop_pointer_v1'), isTrue);
        expect(sizeOf<_RawPointerInput>(), 16);
      });

      test('desktop read rejects invalid requests without writing output', () {
        final read = library.lookupFunction<_ReadNative, _ReadDart>(
          'lumiakeys_desktop_read_v1',
        );
        using((arena) {
          const excessiveCapacity = 2 * 1024 * 1024 + 1;
          final buffer = arena<Uint8>(excessiveCapacity)..value = 0xa5;

          expect(read(0, buffer, 1), -1);
          expect(read(4, buffer, 1), -1);
          expect(read(2, nullptr, 1), -1);
          expect(read(2, buffer, 0), -1);
          expect(read(2, buffer, excessiveCapacity), -1);
          expect(buffer.value, 0xa5);
        });
      });

      test(
        'foreground reads expose short buffers and a bounded JSON result',
        () {
          final read = library.lookupFunction<_ReadNative, _ReadDart>(
            'lumiakeys_desktop_read_v1',
          );
          using((arena) {
            const capacity = 4096;
            final buffer = arena<Uint8>(capacity);
            final bytes = buffer.asTypedList(capacity)
              ..fillRange(0, capacity, 0xa5);

            expect(read(2, buffer, 1), -3);
            expect(bytes.first, 0xa5);
            final received = read(2, buffer, capacity);
            expect(received, inInclusiveRange(2, capacity - 1));
            final decoded = jsonDecode(utf8.decode(bytes.sublist(0, received)));
            expect(decoded == null || decoded is String, isTrue);
            expect(bytes[received], 0xa5);
          });
        },
      );

      test('pointer ABI rejects null, out-of-bounds and malformed batches', () {
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
    skip: canLoadDll ? false : 'Requires the packaged Windows shortcut DLL',
  );
}
