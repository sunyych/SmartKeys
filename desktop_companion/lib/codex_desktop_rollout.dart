import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:lumiakeys_protocol/codex_activity.dart';
import 'package:path/path.dart' as path;

import 'codex_desktop_ipc.dart';

/// Reads lifecycle metadata for one thread identified by the live Desktop IPC.
/// The UUID timestamp bounds the search to the recorded creation date and its
/// adjacent days, including local-time timezone differences.
class CodexDesktopRollout {
  CodexDesktopRollout(this.sessions, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  static CodexDesktopRollout? forCurrentUser() {
    final env = Platform.environment;
    final configuredHome = env['CODEX_HOME'];
    final userProfile = env['USERPROFILE'];
    final home = configuredHome != null && configuredHome.isNotEmpty
        ? configuredHome
        : userProfile == null || userProfile.isEmpty
        ? null
        : path.join(userProfile, '.codex');
    return home == null
        ? null
        : CodexDesktopRollout(Directory(path.join(home, 'sessions')));
  }

  final Directory sessions;
  final DateTime Function() _now;
  static final _threadId = RegExp(
    r'^[a-f0-9]{8}-[a-f0-9]{4}-7[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$',
  );
  static const _maxHeader = 128 * 1024;
  static const _tailWindows = [256 * 1024, 1024 * 1024, 4 * 1024 * 1024];
  static const _maxRunningAge = Duration(hours: 1);
  String? _cachedId;
  File? _cachedRollout;
  (int, DateTime)? _cachedFileVersion;
  CodexDesktopActivityEvidence? _cachedEvidence;

  Future<CodexDesktopActivityEvidence?> read(String selectedChat) async {
    final id = selectedChat.toLowerCase();
    if (!_threadId.hasMatch(id)) return null;
    if (_cachedId != id) {
      _cachedId = id;
      _forgetRollout();
    }
    try {
      final file = _cachedRollout ?? await _find(id);
      if (file == null) return null;
      final stat = await file.stat();
      if (stat.type != FileSystemEntityType.file) {
        if (_cachedId == id) _forgetRollout();
        return null;
      }
      final version = (stat.size, stat.modified);
      if (_cachedId == id && _cachedFileVersion == version) {
        return _freshEvidence(_cachedEvidence);
      }
      final evidence = await _readFile(file, id);
      if (_cachedId == id) {
        _cachedRollout = file;
        _cachedFileVersion = version;
        _cachedEvidence = evidence;
      }
      return _freshEvidence(evidence);
    } on FileSystemException {
      if (_cachedId == id) _forgetRollout();
      return null;
    }
  }

  void _forgetRollout() {
    _cachedRollout = null;
    _cachedFileVersion = null;
    _cachedEvidence = null;
  }

  CodexDesktopActivityEvidence? _freshEvidence(
    CodexDesktopActivityEvidence? evidence,
  ) {
    if (evidence == null) return null;
    final age = _now().difference(evidence.timestamp);
    if (age.isNegative ||
        (evidence.status == CodexActivityStatus.thinking &&
            age > _maxRunningAge)) {
      return null;
    }
    return evidence;
  }

  Future<CodexDesktopActivityEvidence?> _readFile(File file, String id) async {
    final handle = await file.open();
    try {
      final head = await handle.read(_maxHeader);
      final endOfHead = head.indexOf(0x0a);
      if (endOfHead == -1) return null;
      final meta = _decodeLine(head, 0, endOfHead);
      if (meta case {
        'type': 'session_meta',
        'payload': {'id': String stored},
      } when stored.toLowerCase() == id) {
        final length = await handle.length();
        for (final window in _tailWindows) {
          final offset = math.max(0, length - window);
          await handle.setPosition(offset);
          final tail = await handle.read(window);
          final match = _readTail(tail, offset: offset, threadId: id);
          if (match != null || offset == 0) return match?.evidence;
        }
      }
    } finally {
      await handle.close();
    }
    return null;
  }

  Future<File?> _find(String id) async {
    final millis = int.parse(
      id.substring(0, 8) + id.substring(9, 13),
      radix: 16,
    );
    final created = DateTime.fromMillisecondsSinceEpoch(
      millis,
      isUtc: true,
    ).toLocal();
    for (final offset in [0, -1, 1]) {
      final day = DateTime(created.year, created.month, created.day + offset);
      final folder = Directory(
        path.join(
          sessions.path,
          day.year.toString().padLeft(4, '0'),
          day.month.toString().padLeft(2, '0'),
          day.day.toString().padLeft(2, '0'),
        ),
      );
      try {
        await for (final entry in folder.list(followLinks: false).take(4096)) {
          if (entry is! File) continue;
          final filename = path.basename(entry.path).toLowerCase();
          if (filename.startsWith('rollout-') &&
              filename.endsWith('-$id.jsonl')) {
            return entry;
          }
        }
      } on FileSystemException {
        // This day might not have a session directory.
      }
    }
    return null;
  }

  ({CodexDesktopActivityEvidence? evidence})? _readTail(
    Uint8List tail, {
    required int offset,
    required String threadId,
  }) {
    // The current writer may not have finished its last line.
    var end = tail.lastIndexOf(0x0a);
    while (end > 0) {
      final previous = tail.lastIndexOf(0x0a, end - 1);
      if (previous == -1 && offset != 0) return null;
      final event = _decodeLine(tail, previous + 1, end);
      if (event
          case {
            'type': 'event_msg',
            'payload': {'turn_id': String turnId} && Map payload,
          }
          when turnId.isNotEmpty &&
              (payload['thread_id'] == null ||
                  payload['thread_id'] == threadId) &&
              (payload['root_turn_id'] == null ||
                  payload['root_turn_id'] == turnId)) {
        final status = switch (payload['type']) {
          'task_started' => CodexActivityStatus.thinking,
          'task_complete' =>
            payload['error'] is Map
                ? CodexActivityStatus.error
                : CodexActivityStatus.complete,
          'turn_aborted' =>
            payload['error'] is Map
                ? CodexActivityStatus.error
                : CodexActivityStatus.idle,
          _ => null,
        };
        if (status != null) {
          final raw = event['timestamp'];
          final timestamp = raw is String ? DateTime.tryParse(raw) : null;
          return (
            evidence: timestamp == null
                ? null
                : (status: status, timestamp: timestamp),
          );
        }
      }
      end = previous;
    }
    return null;
  }

  static Object? _decodeLine(Uint8List data, int start, int end) {
    try {
      return jsonDecode(utf8.decode(Uint8List.sublistView(data, start, end)));
    } on FormatException {
      return null;
    }
  }
}
