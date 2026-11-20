import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumiakeys_companion/codex_desktop_ipc.dart';
import 'package:lumiakeys_protocol/codex_activity.dart';

Map<String, Object?> _broadcast(
  String method,
  String chat,
  Map<String, Object?> data, {
  String source = 'window-1',
  String host = 'local',
}) => {
  'type': 'broadcast',
  'sourceClientId': source,
  'method': method,
  'params': {'conversationId': chat, 'hostId': host, ...data},
};

Map<String, Object?> _follow(
  String chat, {
  bool following = true,
  String source = 'window-1',
}) => _broadcast('thread-stream-following-changed', chat, {
  'following': following,
}, source: source);

void main() {
  test('fragmented frames, oversized discard and next frame stay aligned', () {
    final received = <Object?>[];
    var skipped = 0;
    final decoder = CodexDesktopIpcDecoder(
      onMessage: (message) => received.add(message['value']),
      onSkippedFrame: () => skipped++,
      maxFrameBytes: 48,
    );
    final first = CodexDesktopIpcDecoder.encode({'value': 'first'});
    final oversized = CodexDesktopIpcDecoder.encode({
      'value': List.filled(100, 'a').join(),
    });
    final next = CodexDesktopIpcDecoder.encode({'value': 'next'});
    decoder.add(Uint8List.sublistView(first, 0, 2));
    decoder.add(Uint8List.sublistView(first, 2, first.length - 1));
    expect(received, isEmpty);
    decoder.add(
      Uint8List.fromList([
        ...first.skip(first.length - 1),
        ...oversized.take(25),
      ]),
    );
    expect(received, ['first']);
    expect(skipped, 1);
    decoder.add(Uint8List.fromList([...oversized.skip(25), ...next]));
    expect(received, ['first', 'next']);
    expect(skipped, 1);
  });

  test('only explicit local following changes select a conversation', () {
    final reducer = CodexDesktopIpcActivity();
    final snapshot = _broadcast('thread-stream-state-changed', 'first', {
      'change': {
        'type': 'snapshot',
        'revision': 5,
        'conversationState': {
          'turns': [
            {'status': 'completed'},
          ],
        },
      },
    });
    reducer.onMessage(snapshot);
    expect(reducer.status, isNull);
    reducer.onMessage(_follow('first'));
    expect(reducer.status, CodexActivityStatus.complete);
    final firstRevision = reducer.selectionRevision;
    reducer.onMessage(
      _broadcast('thread-stream-following-changed', 'remote', {
        'following': true,
      }, host: 'other'),
    );
    expect(reducer.selectionRevision, greaterThan(firstRevision));
    expect(reducer.selectedChat, isNull);
    expect(reducer.status, isNull);
    reducer.onMessage(_follow('second', source: 'window-2'));
    expect(reducer.selectedChat, 'second');
    expect(reducer.status, isNull);
    reducer.onMessage(_follow('first', following: false));
    expect(reducer.selectedChat, 'second');
    reducer.onMessage(_follow('second', following: false, source: 'window-2'));
    expect(reducer.selectedChat, isNull);
    expect(reducer.status, isNull);
  });

  test('newer lifecycle resolves stale stream status without losing input', () {
    final now = DateTime.utc(2026, 11, 19);
    final waiting = (status: CodexActivityStatus.needsInput, timestamp: now);
    expect(
      latestCodexDesktopActivity(waiting, (
        status: CodexActivityStatus.thinking,
        timestamp: now.subtract(const Duration(seconds: 1)),
      )),
      CodexActivityStatus.needsInput,
    );
    expect(
      latestCodexDesktopActivity(waiting, (
        status: CodexActivityStatus.complete,
        timestamp: now.add(const Duration(seconds: 1)),
      )),
      CodexActivityStatus.complete,
    );
  });

  test('matching snapshots and patches drive all five activity statuses', () {
    final reducer = CodexDesktopIpcActivity();
    reducer.onMessage(_follow('chat'));
    reducer.onMessage(
      _broadcast('thread-stream-state-changed', 'chat', {
        'change': {
          'type': 'snapshot',
          'revision': 1,
          'conversationState': {'turns': [], 'requests': []},
        },
      }),
    );
    expect(reducer.status, CodexActivityStatus.idle);

    void patch(int base, List<Map<String, Object?>> patches) {
      reducer.onMessage(
        _broadcast('thread-stream-state-changed', 'chat', {
          'change': {
            'type': 'patches',
            'baseRevision': base,
            'revision': base + 1,
            'patches': patches,
          },
        }),
      );
    }

    patch(1, [
      {
        'op': 'add',
        'path': ['turns', 0],
        'value': {'status': 'inProgress'},
      },
    ]);
    expect(reducer.status, CodexActivityStatus.thinking);

    patch(2, [
      {
        'op': 'add',
        'path': ['requests', 0],
        'value': {'method': 'item/tool/requestUserInput'},
      },
    ]);
    expect(reducer.status, CodexActivityStatus.needsInput);

    patch(3, [
      {
        'op': 'remove',
        'path': ['requests', 0],
      },
      {
        'op': 'replace',
        'path': ['turns', 0, 'status'],
        'value': 'completed',
      },
    ]);
    expect(reducer.status, CodexActivityStatus.complete);
    patch(4, [
      {
        'op': 'replace',
        'path': ['turns', 0, 'status'],
        'value': 'failed',
      },
    ]);
    expect(reducer.status, CodexActivityStatus.error);
    patch(9, []);
    expect(reducer.status, isNull);
  });
}
