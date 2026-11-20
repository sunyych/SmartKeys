import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:lumiakeys_protocol/codex_activity.dart';
import 'package:path/path.dart' as path;

import 'codex_desktop_ipc.dart';

typedef _RolloutRead = ({
  int length,
  Digest witness,
  CodexDesktopActivityEvidence? evidence,
});

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
  static const _maxScan = 32 * 1024 * 1024;
  static const _chunkSize = 256 * 1024;
  static const _matchPrefixSize = 1024;
  static const _maxLifecycleLine = _chunkSize;
  static const _witnessSize = 128;
  static final _eventType = RegExp(r'"type"\s*:\s*"event_msg"');
  static final _lifecycleType = RegExp(
    r'"type"\s*:\s*"(?:task_started|task_complete|turn_aborted)"',
  );
  static const _maxRunningAge = Duration(hours: 1);
  String? _cachedId;
  File? _cachedRollout;
  (int, DateTime)? _cachedFileVersion;
  _RolloutRead? _cachedRead;

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
        return _freshEvidence(_cachedRead?.evidence);
      }
      final previous = _cachedId == id ? _cachedRead : null;
      final result = await _readFile(file, id, previous);
      if (_cachedId == id) {
        _cachedRollout = file;
        _cachedFileVersion = version;
        _cachedRead = result;
      }
      return _freshEvidence(result?.evidence);
    } on FileSystemException {
      if (_cachedId == id) _forgetRollout();
      return null;
    }
  }

  void _forgetRollout() {
    _cachedRollout = null;
    _cachedFileVersion = null;
    _cachedRead = null;
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

  Future<_RolloutRead?> _readFile(
    File file,
    String id,
    _RolloutRead? previous,
  ) async {
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
        final append =
            previous != null &&
            previous.evidence != null &&
            length > previous.length &&
            length - previous.length < _maxScan &&
            await _witness(handle, previous.length) == previous.witness;
        final match = await _scanBackwards(
          handle,
          length,
          id,
          appendedAfter: append ? previous.length : null,
        );
        return (
          length: length,
          witness: await _witness(handle, length),
          evidence: match != null
              ? match.evidence
              : append
              ? previous.evidence
              : null,
        );
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

  Future<({CodexDesktopActivityEvidence? evidence})?> _scanBackwards(
    RandomAccessFile file,
    int length,
    String threadId, {
    required int? appendedAfter,
  }) async {
    final floor = math.max(0, length - _maxScan);
    // Ignore the uncommitted line after the last newline. A newline before
    // the previous EOF can be the start boundary of a newly completed line.
    int? lineEnd;
    for (var cursor = length; cursor > floor;) {
      final offset = math.max(floor, cursor - _chunkSize);
      final bytes = await _readAt(file, offset, cursor - offset);
      if (bytes.length != cursor - offset) return (evidence: null);
      for (var i = bytes.lastIndexOf(0x0a); i >= 0;) {
        if (lineEnd case final end?) {
          if (appendedAfter != null && end < appendedAfter) return null;
          final match = await _matchLine(
            file,
            bytes,
            offset,
            offset + i + 1,
            end,
            threadId,
          );
          if (match != null) return match;
        }
        lineEnd = offset + i;
        i = i == 0 ? -1 : bytes.lastIndexOf(0x0a, i - 1);
      }
      cursor = offset;
    }
    if (appendedAfter != null && lineEnd != null && lineEnd >= appendedAfter) {
      // The window cut into an unexamined line that could carry a newer event.
      return (evidence: null);
    }
    return null;
  }

  Future<({CodexDesktopActivityEvidence? evidence})?> _matchLine(
    RandomAccessFile file,
    Uint8List chunk,
    int offset,
    int lineStart,
    int lineEnd,
    String threadId,
  ) async {
    final length = lineEnd - lineStart;
    if (length <= 0) return null;
    Future<Uint8List> bytes(int count) async {
      final start = lineStart - offset;
      return start + count <= chunk.length
          ? Uint8List.sublistView(chunk, start, start + count)
          : _readAt(file, lineStart, count);
    }

    final prefix = latin1.decode(
      await bytes(math.min(length, _matchPrefixSize)),
    );
    if (!_eventType.hasMatch(prefix) || !_lifecycleType.hasMatch(prefix)) {
      return null;
    }
    if (length > _maxLifecycleLine) return (evidence: null);
    final line = await bytes(length);
    if (line.length != length) return (evidence: null);
    final event = _decodeLine(line, 0, length);
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
    return null;
  }

  static Future<Uint8List> _readAt(
    RandomAccessFile file,
    int start,
    int count,
  ) async {
    await file.setPosition(start);
    return file.read(count);
  }

  static Future<Digest> _witness(RandomAccessFile file, int length) async {
    final count = math.min(length, _witnessSize);
    return sha256.convert(await _readAt(file, length - count, count));
  }

  static Object? _decodeLine(Uint8List data, int start, int end) {
    try {
      return jsonDecode(utf8.decode(Uint8List.sublistView(data, start, end)));
    } on FormatException {
      return null;
    }
  }
}
