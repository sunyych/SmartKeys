import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:lumiakeys_protocol/codex_activity.dart';

import 'codex_desktop_ipc.dart';
import 'codex_desktop_rollout.dart';

/// Keeps decoding and local pipe operations off the Flutter UI isolate.
/// Only the activity enum crosses back into the app.
Stream<CodexActivityStatus?> watchWindowsCodexDesktopActivity() {
  if (!Platform.isWindows) return const Stream.empty();

  final events = ReceivePort();
  SendPort? stop;
  var cancelled = false;
  late final StreamController<CodexActivityStatus?> output;
  output = StreamController<CodexActivityStatus?>(
    onListen: () {
      events.listen((event) {
        if (event is SendPort) {
          stop = event;
          if (cancelled) {
            stop!.send(null);
            events.close();
          }
        } else if (event is int && !cancelled) {
          output.add(event < 0 ? null : CodexActivityStatus.values[event]);
        } else if (event == null) {
          events.close();
          if (!cancelled) unawaited(output.close());
        }
      });
      unawaited(() async {
        try {
          await Isolate.spawn(
            _watch,
            events.sendPort,
            onExit: events.sendPort,
            debugName: 'Codex Desktop activity',
          );
        } catch (_) {
          events.close();
          if (!cancelled) unawaited(output.close());
        }
      }());
    },
    onCancel: () {
      cancelled = true;
      if (stop != null) {
        stop!.send(null);
        events.close();
      }
    },
  );
  return output.stream;
}

Future<void> _watch(SendPort output) async {
  var stopped = false;
  final control = ReceivePort();
  control.listen((_) => stopped = true);
  output.send(control.sendPort);
  final random = math.Random.secure();
  int? published;
  void publish(CodexActivityStatus? status) {
    final next = status?.index ?? -1;
    if (published != next) output.send(next);
    published = next;
  }

  try {
    final api = _PipeApi();
    final rollout = CodexDesktopRollout.forCurrentUser();
    var retryMillis = 300;
    while (!stopped) {
      final pipe = api.connect();
      if (pipe == null) {
        await Future<void>.delayed(Duration(milliseconds: retryMillis));
        retryMillis = math.min(3000, retryMillis * 2);
        continue;
      }
      var initialized = false;
      final initializeId = _requestId(random);
      final stream = CodexDesktopIpcActivity();
      final decoder = CodexDesktopIpcDecoder(
        onMessage: (message) {
          if (message case {
            'type': 'response',
            'requestId': String id,
            'result': {'clientId': String clientId},
          } when id == initializeId && clientId.isNotEmpty) {
            initialized = true;
          } else {
            stream.onMessage(message);
          }
        },
        onSkippedFrame: stream.invalidateState,
      );
      final clock = Stopwatch()..start();
      var observedSelection = stream.selectionRevision;
      var nextRolloutRead = Duration.zero;
      var readingRollout = false;
      CodexDesktopActivityEvidence? rolloutStatus;
      try {
        final hello = CodexDesktopIpcDecoder.encode({
          'type': 'request',
          'requestId': initializeId,
          'sourceClientId': _requestId(random),
          'version': 0,
          'method': 'initialize',
          'params': {'clientType': 'lumiakeys-status'},
        });
        if (!pipe.write(hello)) {
          await Future<void>.delayed(Duration(milliseconds: retryMillis));
          retryMillis = math.min(3000, retryMillis * 2);
          continue;
        }
        while (!stopped) {
          if (!pipe.readAvailable(decoder.add)) break;
          if (initialized) {
            retryMillis = 300;
            final selection = stream.selectionRevision;
            if (observedSelection != selection) {
              observedSelection = selection;
              nextRolloutRead = Duration.zero;
              rolloutStatus = null;
            }
            final chat = stream.selectedChat;
            if (chat != null &&
                rollout != null &&
                !readingRollout &&
                clock.elapsed >= nextRolloutRead) {
              readingRollout = true;
              nextRolloutRead = clock.elapsed + const Duration(seconds: 2);
              unawaited(() async {
                try {
                  final status = await rollout.read(chat);
                  if (stream.selectionRevision == selection) {
                    rolloutStatus = status;
                  }
                } finally {
                  readingRollout = false;
                }
              }());
            }
            publish(latestCodexDesktopActivity(stream.evidence, rolloutStatus));
          } else if (clock.elapsed > const Duration(seconds: 4)) {
            break;
          }
          await Future<void>.delayed(const Duration(milliseconds: 80));
        }
      } finally {
        pipe.close();
        publish(null);
      }
      if (!stopped) {
        await Future<void>.delayed(Duration(milliseconds: retryMillis));
        retryMillis = math.min(3000, retryMillis * 2);
      }
    }
  } finally {
    control.close();
  }
}

String _requestId(math.Random random) {
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

class _PipeApi {
  final _kernel = DynamicLibrary.open('kernel32.dll');

  late final _open = _kernel
      .lookupFunction<
        IntPtr Function(
          Pointer<Utf16>,
          Uint32,
          Uint32,
          Pointer<Void>,
          Uint32,
          Uint32,
          IntPtr,
        ),
        int Function(Pointer<Utf16>, int, int, Pointer<Void>, int, int, int)
      >('CreateFileW');
  late final peek = _kernel
      .lookupFunction<
        Int32 Function(
          IntPtr,
          Pointer<Void>,
          Uint32,
          Pointer<Uint32>,
          Pointer<Uint32>,
          Pointer<Uint32>,
        ),
        int Function(
          int,
          Pointer<Void>,
          int,
          Pointer<Uint32>,
          Pointer<Uint32>,
          Pointer<Uint32>,
        )
      >('PeekNamedPipe');
  late final read = _kernel
      .lookupFunction<
        Int32 Function(
          IntPtr,
          Pointer<Uint8>,
          Uint32,
          Pointer<Uint32>,
          Pointer<Void>,
        ),
        int Function(int, Pointer<Uint8>, int, Pointer<Uint32>, Pointer<Void>)
      >('ReadFile');
  late final write = _kernel
      .lookupFunction<
        Int32 Function(
          IntPtr,
          Pointer<Uint8>,
          Uint32,
          Pointer<Uint32>,
          Pointer<Void>,
        ),
        int Function(int, Pointer<Uint8>, int, Pointer<Uint32>, Pointer<Void>)
      >('WriteFile');
  late final close = _kernel
      .lookupFunction<Int32 Function(IntPtr), int Function(int)>('CloseHandle');

  _WindowsPipe? connect() {
    final name = r'\\.\pipe\codex-ipc'.toNativeUtf16();
    try {
      const genericRead = 0x80000000;
      const genericWrite = 0x40000000;
      const openExisting = 3;
      const securityQosPresent = 0x00100000;
      const securityIdentification = 0x00010000;
      final handle = _open(
        name,
        genericRead | genericWrite,
        0,
        nullptr,
        openExisting,
        securityQosPresent | securityIdentification,
        0,
      );
      return handle == -1 ? null : _WindowsPipe(this, handle);
    } finally {
      malloc.free(name);
    }
  }
}

class _WindowsPipe {
  _WindowsPipe(this._api, this._handle);
  final _PipeApi _api;
  final int _handle;
  static const _chunkBytes = 64 * 1024;
  final _buffer = calloc<Uint8>(_chunkBytes);
  final _count = calloc<Uint32>();

  bool write(Uint8List bytes) {
    if (bytes.length > _chunkBytes) return false;
    _buffer.asTypedList(bytes.length).setAll(0, bytes);
    return _api.write(_handle, _buffer, bytes.length, _count, nullptr) != 0 &&
        _count.value == bytes.length;
  }

  bool readAvailable(void Function(Uint8List bytes) consume) {
    for (var chunk = 0; chunk < 8; chunk++) {
      if (_api.peek(_handle, nullptr, 0, nullptr, _count, nullptr) == 0) {
        return false;
      }
      final available = _count.value;
      if (available == 0) return true;
      if (_api.read(
                _handle,
                _buffer,
                math.min(available, _chunkBytes),
                _count,
                nullptr,
              ) ==
              0 ||
          _count.value == 0) {
        return false;
      }
      consume(_buffer.asTypedList(_count.value));
    }
    return true;
  }

  void close() {
    _api.close(_handle);
    calloc.free(_buffer);
    calloc.free(_count);
  }
}
