import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:lumiakeys_protocol/codex_activity.dart';

/// Incremental decoder for the local length-prefixed Codex Desktop transport.
/// Oversized frames are drained without allocating their advertised size.
class CodexDesktopIpcDecoder {
  CodexDesktopIpcDecoder({
    required this.onMessage,
    required this.onSkippedFrame,
    this.maxFrameBytes = 2 * 1024 * 1024,
  });

  final void Function(Map<Object?, Object?>) onMessage;
  final void Function() onSkippedFrame;
  final int maxFrameBytes;
  final _header = Uint8List(4);
  int _headerBytes = 0;
  Uint8List? _body;
  int _bodyBytes = 0;
  int _skipBytes = 0;

  static Uint8List encode(Map<String, Object?> message) {
    final payload = utf8.encode(jsonEncode(message));
    final frame = Uint8List(4 + payload.length);
    ByteData.sublistView(frame).setUint32(0, payload.length, Endian.little);
    frame.setRange(4, frame.length, payload);
    return frame;
  }

  void add(Uint8List bytes) {
    var offset = 0;
    while (offset < bytes.length) {
      if (_skipBytes != 0) {
        final count = math.min(_skipBytes, bytes.length - offset);
        _skipBytes -= count;
        offset += count;
        continue;
      }
      if (_body == null) {
        final count = math.min(4 - _headerBytes, bytes.length - offset);
        _header.setRange(_headerBytes, _headerBytes + count, bytes, offset);
        _headerBytes += count;
        offset += count;
        if (_headerBytes < 4) continue;
        _headerBytes = 0;
        final length = ByteData.sublistView(
          _header,
        ).getUint32(0, Endian.little);
        if (length == 0 || length > maxFrameBytes) {
          _skipBytes = length;
          onSkippedFrame();
          continue;
        }
        _body = Uint8List(length);
        _bodyBytes = 0;
      }
      final body = _body!;
      final count = math.min(body.length - _bodyBytes, bytes.length - offset);
      body.setRange(_bodyBytes, _bodyBytes + count, bytes, offset);
      _bodyBytes += count;
      offset += count;
      if (_bodyBytes != body.length) continue;

      _body = null;
      try {
        final message = jsonDecode(utf8.decode(body));
        if (message is Map<Object?, Object?>) onMessage(message);
      } on FormatException {
        onSkippedFrame();
      }
    }
  }
}

typedef _Conversation = ({String host, String id});
typedef CodexDesktopActivityEvidence = ({
  CodexActivityStatus status,
  DateTime timestamp,
});

CodexActivityStatus? latestCodexDesktopActivity(
  CodexDesktopActivityEvidence? ipc,
  CodexDesktopActivityEvidence? rollout,
) =>
    rollout != null && (ipc == null || rollout.timestamp.isAfter(ipc.timestamp))
    ? rollout.status
    : ipc?.status;

/// Tracks the last explicit Desktop selection and retains only status fields.
/// Neither the incoming state snapshots nor their patches are retained.
class CodexDesktopIpcActivity {
  CodexDesktopIpcActivity({DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final DateTime Function() _now;
  ({String client, _Conversation conversation})? _selected;
  int _selectionRevision = 0;
  final _observed = <_Conversation, _ConversationStatus>{};
  static final _validId = RegExp(r'^[A-Za-z0-9_-]{1,128}$');

  String? get selectedChat => _selected?.conversation.host == 'local'
      ? _selected?.conversation.id
      : null;
  int get selectionRevision => _selectionRevision;
  CodexActivityStatus? get status => evidence?.status;
  CodexDesktopActivityEvidence? get evidence {
    final observed = _observed[_selected?.conversation];
    final status = observed?.status;
    return status == null
        ? null
        : (status: status, timestamp: observed!.observedAt);
  }

  void invalidateState() => _observed.clear();

  void onMessage(Map<Object?, Object?> message) {
    if (message['type'] != 'broadcast' || message['params'] is! Map) return;
    final params = message['params']! as Map;
    final source = message['sourceClientId'];
    if (source is! String || source.isEmpty || source.length > 128) return;
    if (message['method'] == 'client-status-changed' &&
        params['status'] == 'disconnected' &&
        params['clientId'] == _selected?.client) {
      _select(null);
      return;
    }
    final id = params['conversationId'];
    final host = params['hostId'];
    if (id is! String ||
        !_validId.hasMatch(id) ||
        host is! String ||
        host.isEmpty ||
        host.length > 128) {
      return;
    }
    final conversation = (host: host, id: id);
    switch (message['method']) {
      case 'thread-stream-following-changed':
        final selection = (client: source, conversation: conversation);
        if (params['following'] == true) {
          _select(selection);
        } else if (params['following'] == false && _selected == selection) {
          _select(null);
        }
      case 'thread-stream-state-changed':
        final change = params['change'];
        if (change is! Map) return;
        final revision = change['revision'];
        switch (change['type']) {
          case 'snapshot':
            final state = change['conversationState'];
            if (state is! Map) return;
            if (_observed.length >= 8 && !_observed.containsKey(conversation)) {
              final oldest = _observed.keys.firstWhere(
                (key) => key != _selected?.conversation,
              );
              _observed.remove(oldest);
            }
            _observed[conversation] = _ConversationStatus(
              owner: source,
              revision: revision is int ? revision : null,
              observedAt: _now(),
            )..replaceSnapshot(state);
          case 'patches':
            final state = _observed[conversation];
            final patches = change['patches'];
            if (state == null || state.owner != source || patches is! List) {
              return;
            }
            final base = change['baseRevision'];
            if (base is int &&
                state.revision != null &&
                base != state.revision) {
              _observed.remove(conversation);
              return;
            }
            final before = state.checkpoint;
            for (final patch in patches) {
              if (patch is Map) state.applyPatch(patch);
            }
            if (state.checkpoint != before) state.observedAt = _now();
            state.revision = revision is int ? revision : null;
        }
    }
  }

  void _select(({String client, _Conversation conversation})? selection) {
    if (_selected == selection) return;
    _selected = selection;
    _selectionRevision++;
  }
}

class _ConversationStatus {
  _ConversationStatus({
    required this.owner,
    required this.revision,
    required this.observedAt,
  });

  final String owner;
  int? revision;
  DateTime observedAt;
  int? _lastTurn;
  String? _turnStatus;
  bool _turnError = false;
  CodexActivityStatus? _threadStatus;
  List<bool> _pending = [];
  (int?, String?, bool, CodexActivityStatus?, bool) get checkpoint => (
    _lastTurn,
    _turnStatus,
    _turnError,
    _threadStatus,
    _pending.contains(true),
  );

  CodexActivityStatus? get status {
    if (_threadStatus == CodexActivityStatus.error) return _threadStatus;
    if (_threadStatus == CodexActivityStatus.needsInput ||
        _pending.contains(true)) {
      return CodexActivityStatus.needsInput;
    }
    if (_threadStatus == CodexActivityStatus.thinking) return _threadStatus;
    return switch (_turnStatus) {
      'inProgress' ||
      'in_progress' ||
      'running' => CodexActivityStatus.thinking,
      'completed' => CodexActivityStatus.complete,
      'failed' => CodexActivityStatus.error,
      'interrupted' =>
        _turnError ? CodexActivityStatus.error : CodexActivityStatus.idle,
      _ => _threadStatus,
    };
  }

  void replaceSnapshot(Map state) {
    _replaceTurns(state['turns']);
    _replacePending(state['requests']);
    _threadStatus = _readThreadStatus(state['threadStatus']);
  }

  void applyPatch(Map patch) {
    final path = patch['path'];
    final operation = patch['op'];
    if (path is! List ||
        (operation != 'add' &&
            operation != 'remove' &&
            operation != 'replace')) {
      return;
    }
    final value = operation == 'remove' ? null : patch['value'];
    if (path.isEmpty) {
      if (value is Map) replaceSnapshot(value);
      return;
    }
    switch (path.first) {
      case 'threadStatus':
        if (path.length == 1) _threadStatus = _readThreadStatus(value);
      case 'turns':
        _applyTurnPatch(path, operation, value);
      case 'requests':
        _applyPendingPatch(path, operation, value);
    }
  }

  void _replaceTurns(Object? turns) {
    _lastTurn = turns is List ? turns.length - 1 : null;
    _replaceLastTurn(turns is List && turns.isNotEmpty ? turns.last : null);
    if (_lastTurn == -1) _turnStatus = 'interrupted';
  }

  void _replaceLastTurn(Object? turn) {
    _turnStatus = turn is Map && turn['status'] is String
        ? turn['status'] as String
        : null;
    _turnError = turn is Map && turn['error'] is Map;
  }

  void _applyTurnPatch(List path, String operation, Object? value) {
    if (path.length == 1) {
      _replaceTurns(value);
      return;
    }
    final index = path[1];
    if (index is! int || index < 0) return;
    if (path.length == 2) {
      if (operation == 'add' && index == (_lastTurn ?? -1) + 1) {
        _lastTurn = index;
        _replaceLastTurn(value);
      } else if (index == _lastTurn) {
        if (operation == 'remove') _lastTurn = index - 1;
        _replaceLastTurn(value);
      }
    } else if (index == _lastTurn && path.length == 3) {
      if (path[2] == 'status') _turnStatus = value is String ? value : null;
      if (path[2] == 'error') _turnError = value is Map;
    }
  }

  void _replacePending(Object? requests) {
    _pending = requests is List && requests.length <= 128
        ? requests.map(_needsInput).toList()
        : [];
  }

  void _applyPendingPatch(List path, String operation, Object? value) {
    if (path.length == 1) {
      _replacePending(value);
      return;
    }
    final index = path[1];
    if (path.length != 2 ||
        index is! int ||
        index < 0 ||
        index > _pending.length) {
      return;
    }
    if (operation == 'add' && _pending.length < 128) {
      _pending.insert(index, _needsInput(value));
    } else if (index < _pending.length) {
      if (operation == 'remove') {
        _pending.removeAt(index);
      } else if (operation == 'replace') {
        _pending[index] = _needsInput(value);
      }
    }
  }

  static bool _needsInput(Object? request) =>
      request is Map &&
      const {
        'item/commandExecution/requestApproval',
        'item/fileChange/requestApproval',
        'item/permissions/requestApproval',
        'item/tool/requestUserInput',
        'mcpServer/elicitation/request',
        'execCommandApproval',
        'applyPatchApproval',
      }.contains(request['method']);

  static CodexActivityStatus? _readThreadStatus(Object? status) {
    if (status is! Map) return null;
    return switch (status['type']) {
      'active' when status['activeFlags'] is List =>
        (status['activeFlags'] as List).any(
              (flag) =>
                  flag == 'waitingOnApproval' || flag == 'waitingOnUserInput',
            )
            ? CodexActivityStatus.needsInput
            : CodexActivityStatus.thinking,
      'systemError' => CodexActivityStatus.error,
      'idle' => CodexActivityStatus.idle,
      _ => null,
    };
  }
}
