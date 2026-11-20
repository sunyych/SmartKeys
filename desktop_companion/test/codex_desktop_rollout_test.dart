import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumiakeys_companion/codex_desktop_rollout.dart';
import 'package:lumiakeys_protocol/codex_activity.dart';
import 'package:path/path.dart' as path;

String _id(DateTime creation, String suffix) {
  final hex = creation.millisecondsSinceEpoch
      .toRadixString(16)
      .padLeft(12, '0');
  return '${hex.substring(0, 8)}-${hex.substring(8)}-7000-8000-$suffix';
}

Map<String, Object?> _event(
  DateTime timestamp,
  String event, {
  String? thread,
  String? rootTurn,
  bool error = false,
}) => {
  'timestamp': timestamp.toIso8601String(),
  'type': 'event_msg',
  'payload': {
    'type': event,
    'turn_id': 'turn-1',
    'root_turn_id': ?rootTurn,
    'thread_id': ?thread,
    if (error) 'error': {'message': 'Not used by the status reader'},
  },
};

Future<File> _session(
  Directory sessions,
  DateTime creation,
  String id, {
  String? metadataId,
}) async {
  final day = creation.toLocal();
  final directory = Directory(
    path.join(
      sessions.path,
      day.year.toString(),
      day.month.toString().padLeft(2, '0'),
      day.day.toString().padLeft(2, '0'),
    ),
  );
  await directory.create(recursive: true);
  final file = File(path.join(directory.path, 'rollout-test-$id.jsonl'));
  return file.writeAsString(
    '${jsonEncode({
      'type': 'session_meta',
      'payload': {'id': metadataId ?? id},
    })}\n',
  );
}

Future<void> _appendLargeResponse(File file, int mebibytes) async {
  final session = await file.open(mode: FileMode.append);
  try {
    await session.writeString('{"type":"response_item","payload":{"text":"');
    final chunk = 'x' * (256 * 1024);
    for (var i = 0; i < 4 * mebibytes; i++) {
      await session.writeString(chunk);
    }
    await session.writeString('"}}\n');
  } finally {
    await session.close();
  }
}

void main() {
  final now = DateTime.utc(2026, 11, 19, 23);
  final selected = _id(now, '000000000001');
  final other = _id(now, '000000000002');
  final unrelated = _id(now, '000000000003');
  late Directory sessions;

  setUp(() async {
    sessions = await Directory.systemTemp.createTemp(
      'lumiakeys-codex-fixture-',
    );
    addTearDown(() => sessions.delete(recursive: true));
  });

  test('only the exact selected thread gives known lifecycle status', () async {
    final reader = CodexDesktopRollout(sessions, now: () => now);
    final current = await _session(sessions, now, selected);
    final newer = await _session(sessions, now, other);
    Future<void> append(
      File file,
      Map<String, Object?> event, {
      bool completeLine = true,
    }) => file.writeAsString(
      '${jsonEncode(event)}${completeLine ? '\n' : ''}',
      mode: FileMode.append,
    );
    await append(newer, _event(now, 'task_complete'));
    expect(await reader.read(selected), isNull);
    await append(current, _event(now, 'task_started'));
    await append(current, _event(now, 'task_complete', thread: other));
    await append(
      current,
      _event(now, 'task_complete', rootTurn: 'another-turn', error: true),
    );
    expect((await reader.read(selected))?.status, CodexActivityStatus.thinking);
    await append(current, _event(now, 'task_complete'), completeLine: false);
    expect((await reader.read(selected))?.status, CodexActivityStatus.thinking);
    await current.writeAsString('\n', mode: FileMode.append);
    expect((await reader.read(selected))?.status, CodexActivityStatus.complete);
    await append(current, _event(now, 'turn_aborted', error: true));
    expect((await reader.read(selected))?.status, CodexActivityStatus.error);
    await append(current, _event(now, 'turn_aborted'));
    expect((await reader.read(selected))?.status, CodexActivityStatus.idle);
    expect(await reader.read(unrelated), isNull);
  });

  test(
    'cold start finds the active turn behind a large unrelated record',
    () async {
      final reader = CodexDesktopRollout(sessions, now: () => now);
      final file = await _session(sessions, now, selected);
      await file.writeAsString(
        '${jsonEncode(_event(now, 'task_started'))}\n',
        mode: FileMode.append,
      );
      await _appendLargeResponse(file, 5);
      expect(
        (await reader.read(selected))?.status,
        CodexActivityStatus.thinking,
      );
    },
  );

  test(
    'verified append growth retains live evidence beyond the cold window',
    () async {
      var clock = now;
      final reader = CodexDesktopRollout(sessions, now: () => clock);
      final file = await _session(sessions, now, selected);
      await file.writeAsString(
        '${jsonEncode(_event(now, 'task_started'))}\n',
        mode: FileMode.append,
      );
      await _appendLargeResponse(file, 31);
      expect(
        (await reader.read(selected))?.status,
        CodexActivityStatus.thinking,
      );
      await _appendLargeResponse(file, 2);
      expect(
        (await reader.read(selected))?.status,
        CodexActivityStatus.thinking,
      );
      final coldReader = CodexDesktopRollout(sessions, now: () => clock);
      expect(await coldReader.read(selected), isNull);
      clock = now.add(const Duration(hours: 2));
      expect(await reader.read(selected), isNull);
      await file.writeAsString(
        '${jsonEncode(_event(clock, 'task_complete'))}\n',
        mode: FileMode.append,
      );
      expect(
        (await reader.read(selected))?.status,
        CodexActivityStatus.complete,
      );
    },
  );

  test('metadata mismatch and stale active turn fail closed', () async {
    final reader = CodexDesktopRollout(sessions, now: () => now);
    final stale = await _session(sessions, now, selected);
    await stale.writeAsString(
      '${jsonEncode(_event(now.subtract(const Duration(hours: 3)), 'task_started'))}\n',
      mode: FileMode.append,
    );
    final wrongFile = await _session(
      sessions,
      now,
      other,
      metadataId: selected,
    );
    await wrongFile.writeAsString(
      '${jsonEncode(_event(now, 'task_complete'))}\n',
      mode: FileMode.append,
    );
    expect(await reader.read(selected), isNull);
    expect(await reader.read(other), isNull);
  });

  test(
    'the bounded tail expands when recent records are not lifecycle events',
    () async {
      final reader = CodexDesktopRollout(sessions, now: () => now);
      final file = await _session(sessions, now, selected);
      final noise = jsonEncode({
        'type': 'response_item',
        'payload': {'text': List.filled(300 * 1024, 'a').join()},
      });
      await file.writeAsString(
        '${jsonEncode(_event(now, 'task_started'))}\n$noise\n',
        mode: FileMode.append,
      );
      expect(
        (await reader.read(selected))?.status,
        CodexActivityStatus.thinking,
      );
    },
  );
}
