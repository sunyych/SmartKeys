import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import 'hid_service.dart';

class HidTextOutputException implements Exception {
  const HidTextOutputException(this.message);

  final String message;

  @override
  String toString() => message;
}

@immutable
class HidTextOutputSession {
  const HidTextOutputSession._({
    required this.token,
    required this.address,
    required this.profile,
    required this._hostGeneration,
  });

  final String token;
  final String address;
  final HidTextProfile profile;
  final int _hostGeneration;
}

/// Encodes printable ASCII for a US-layout USB HID keyboard.
///
/// The complete string is validated before a single stroke can be returned, so
/// callers can reject unsupported text without producing a partial phrase.
class UsAsciiHidTextEncoder {
  const UsAsciiHidTextEncoder._();

  static List<HidTextStroke> encode(String text, {int maxStrokes = 256}) {
    final strokes = <HidTextStroke>[];
    for (final rune in text.runes) {
      if (rune < 0x20 || rune > 0x7e) {
        throw const HidTextOutputException(
          'Bluetooth dictation supports printable ASCII only. Use an English input state and US keyboard layout.',
        );
      }
      final stroke = _strokeFor(rune);
      if (stroke == null) {
        throw const HidTextOutputException(
          'This character is not supported by the US keyboard text encoder.',
        );
      }
      strokes.add(stroke);
      if (strokes.length > maxStrokes) {
        throw HidTextOutputException(
          'This phrase exceeds the $maxStrokes-character Bluetooth dictation limit.',
        );
      }
    }
    return List.unmodifiable(strokes);
  }

  static HidTextStroke? _strokeFor(int rune) {
    if (rune >= 0x61 && rune <= 0x7a) {
      return HidTextStroke(usage: 0x04 + rune - 0x61, shift: false);
    }
    if (rune >= 0x41 && rune <= 0x5a) {
      return HidTextStroke(usage: 0x04 + rune - 0x41, shift: true);
    }
    if (rune >= 0x31 && rune <= 0x39) {
      return HidTextStroke(usage: 0x1e + rune - 0x31, shift: false);
    }
    if (rune == 0x30) return const HidTextStroke(usage: 0x27, shift: false);
    return _punctuation[rune];
  }

  static const _punctuation = <int, HidTextStroke>{
    0x20: HidTextStroke(usage: 0x2c, shift: false),
    0x21: HidTextStroke(usage: 0x1e, shift: true),
    0x22: HidTextStroke(usage: 0x34, shift: true),
    0x23: HidTextStroke(usage: 0x20, shift: true),
    0x24: HidTextStroke(usage: 0x21, shift: true),
    0x25: HidTextStroke(usage: 0x22, shift: true),
    0x26: HidTextStroke(usage: 0x24, shift: true),
    0x27: HidTextStroke(usage: 0x34, shift: false),
    0x28: HidTextStroke(usage: 0x26, shift: true),
    0x29: HidTextStroke(usage: 0x27, shift: true),
    0x2a: HidTextStroke(usage: 0x25, shift: true),
    0x2b: HidTextStroke(usage: 0x2e, shift: true),
    0x2c: HidTextStroke(usage: 0x36, shift: false),
    0x2d: HidTextStroke(usage: 0x2d, shift: false),
    0x2e: HidTextStroke(usage: 0x37, shift: false),
    0x2f: HidTextStroke(usage: 0x38, shift: false),
    0x3a: HidTextStroke(usage: 0x33, shift: true),
    0x3b: HidTextStroke(usage: 0x33, shift: false),
    0x3c: HidTextStroke(usage: 0x36, shift: true),
    0x3d: HidTextStroke(usage: 0x2e, shift: false),
    0x3e: HidTextStroke(usage: 0x37, shift: true),
    0x3f: HidTextStroke(usage: 0x38, shift: true),
    0x40: HidTextStroke(usage: 0x1f, shift: true),
    0x5b: HidTextStroke(usage: 0x2f, shift: false),
    0x5c: HidTextStroke(usage: 0x31, shift: false),
    0x5d: HidTextStroke(usage: 0x30, shift: false),
    0x5e: HidTextStroke(usage: 0x23, shift: true),
    0x5f: HidTextStroke(usage: 0x2d, shift: true),
    0x60: HidTextStroke(usage: 0x35, shift: false),
    0x7b: HidTextStroke(usage: 0x2f, shift: true),
    0x7c: HidTextStroke(usage: 0x31, shift: true),
    0x7d: HidTextStroke(usage: 0x30, shift: true),
    0x7e: HidTextStroke(usage: 0x35, shift: true),
  };
}

/// Validates Windows Unicode HexNumpad input before a single batch is sent.
/// The native controller creates the narrowly allowlisted keypad frames.
class WindowsHexNumpadEncoder {
  const WindowsHexNumpadEncoder._();

  static List<int> encode(String text, {int maxCharacters = 256}) {
    final codePoints = <int>[];
    for (final rune in text.runes) {
      if (!_isPrintableBmpText(rune)) {
        throw const HidTextOutputException(
          'Windows Unicode dictation supports printable BMP text only. Controls, emoji, and non-BMP characters are rejected as a whole phrase.',
        );
      }
      codePoints.add(rune);
      if (codePoints.length > maxCharacters) {
        throw HidTextOutputException(
          'This phrase exceeds the $maxCharacters-character Bluetooth dictation limit.',
        );
      }
    }
    return List.unmodifiable(codePoints);
  }

  static bool _isPrintableBmpText(int rune) =>
      rune >= 0x20 &&
      rune <= 0xffff &&
      !(rune >= 0x7f && rune <= 0x9f) &&
      !(rune >= 0xd800 && rune <= 0xdfff) &&
      !(rune >= 0xfdd0 && rune <= 0xfdef) &&
      !(rune >= 0x200b && rune <= 0x200f) &&
      !(rune >= 0x2028 && rune <= 0x202e) &&
      !(rune >= 0x2060 && rune <= 0x206f) &&
      rune != 0xfeff &&
      rune != 0xfffe &&
      rune != 0xffff;
}

/// Serial, bounded Bluetooth HID text output pinned to one active phone host.
class HidTextOutputService {
  static int _globalSessionSequence = 0;

  HidTextOutputService({required this.hid, this.maxQueuedPhrases = 4})
    : _observedAddress = hid.activeHost.value?.address,
      _observedStatus = hid.connectionStatus.value {
    hid.activeHost.addListener(_handleHostChange);
    hid.connectionStatus.addListener(_handleHostChange);
  }

  final HidService hid;
  final int maxQueuedPhrases;
  final Queue<_QueuedText> _queue = Queue<_QueuedText>();
  HidTextOutputSession? _session;
  HidTextOutputSession? _lastCancelledSession;
  Future<void>? _lastCleanup;
  _QueuedText? _active;
  int _hostGeneration = 0;
  String? _observedAddress;
  HidConnectionStatus _observedStatus;
  bool _cleanupInProgress = false;
  bool _draining = false;

  int get pendingPhraseCount => _queue.length + (_active == null ? 0 : 1);

  HidTextOutputSession beginSession({
    HidTextProfile profile = HidTextProfile.usAscii,
  }) {
    if (_cleanupInProgress) {
      throw const HidTextOutputException(
        'Bluetooth input cleanup is still finishing. Try again in a moment.',
      );
    }
    if (!_isConnected) {
      throw const HidTextOutputException(
        'Connect a paired computer over Bluetooth HID before starting dictation.',
      );
    }
    if (_session != null) {
      throw const HidTextOutputException(
        'A Bluetooth dictation session is already active.',
      );
    }
    final address = hid.activeHost.value!.address;
    final session = HidTextOutputSession._(
      token:
          '$address-${DateTime.now().microsecondsSinceEpoch}-${++_globalSessionSequence}',
      address: address,
      profile: profile,
      hostGeneration: _hostGeneration,
    );
    _session = session;
    return session;
  }

  Future<void> sendText(HidTextOutputSession session, String text) {
    final strokes = session.profile == HidTextProfile.usAscii
        ? UsAsciiHidTextEncoder.encode(text)
        : const <HidTextStroke>[];
    final codePoints = session.profile == HidTextProfile.windowsHexNumpad
        ? WindowsHexNumpadEncoder.encode(text)
        : const <int>[];
    if (strokes.isEmpty && codePoints.isEmpty) return Future<void>.value();
    _requireValidSession(session);
    if (pendingPhraseCount >= maxQueuedPhrases) {
      throw const HidTextOutputException(
        'Bluetooth text output is busy. Stop and try the phrase again.',
      );
    }
    final item = _QueuedText(session, strokes, codePoints);
    _queue.addLast(item);
    unawaited(_drain());
    return item.completer.future;
  }

  Future<void> cancelSession(HidTextOutputSession session) {
    if (!identical(_session, session)) {
      return identical(_lastCancelledSession, session)
          ? (_lastCleanup ?? Future<void>.value())
          : Future<void>.value();
    }
    _session = null;
    _cleanupInProgress = true;
    for (final item in _queue.where(
      (item) => identical(item.session, session),
    )) {
      item.completer.completeError(
        const HidTextOutputException('Bluetooth dictation was cancelled.'),
      );
    }
    _queue.removeWhere((item) => identical(item.session, session));
    _lastCancelledSession = session;
    final cleanup = _cancelNativeSession(session);
    _lastCleanup = cleanup;
    return cleanup;
  }

  Future<void> _cancelNativeSession(HidTextOutputSession session) async {
    try {
      // Native cancellation is scoped to this unique token and releases its
      // held state. A global releaseAllKeys here could cancel another panel's
      // batch if this cleanup completes late.
      await hid.cancelTextBatch(session.token);
    } finally {
      _cleanupInProgress = false;
    }
  }

  void _handleHostChange() {
    final address = hid.activeHost.value?.address;
    final status = hid.connectionStatus.value;
    if (address == _observedAddress && status == _observedStatus) return;
    _observedAddress = address;
    _observedStatus = status;
    _hostGeneration++;
    final session = _session;
    if (session != null) {
      unawaited(cancelSession(session).catchError((Object _) {}));
    }
  }

  void dispose() {
    hid.activeHost.removeListener(_handleHostChange);
    hid.connectionStatus.removeListener(_handleHostChange);
    final session = _session;
    if (session != null) {
      unawaited(cancelSession(session).catchError((Object _) {}));
    }
  }

  bool get _isConnected =>
      hid.connectionStatus.value == HidConnectionStatus.connected &&
      (hid.activeHost.value?.address.isNotEmpty ?? false);

  void _requireValidSession(HidTextOutputSession session) {
    if (!identical(_session, session) ||
        session._hostGeneration != _hostGeneration ||
        !_isConnected ||
        hid.activeHost.value!.address != session.address) {
      throw const HidTextOutputException(
        'The Bluetooth host changed or disconnected. Dictation stopped.',
      );
    }
  }

  Future<void> _drain() async {
    if (_draining) return;
    _draining = true;
    try {
      while (_queue.isNotEmpty) {
        final item = _queue.removeFirst();
        _active = item;
        try {
          _requireValidSession(item.session);
          await hid.sendTextBatch(
            sessionToken: item.session.token,
            expectedAddress: item.session.address,
            profile: item.session.profile,
            strokes: item.strokes,
            codePoints: item.codePoints,
          );
          _requireValidSession(item.session);
          item.completer.complete();
        } catch (error, stackTrace) {
          item.completer.completeError(error, stackTrace);
          if (identical(_session, item.session)) {
            // A rejected native batch may have typed only part of the phrase.
            // Invalidate its session and discard every queued phrase; never
            // silently continue after uncertain partial output.
            try {
              await cancelSession(item.session);
            } catch (_) {
              // The originating phrase already reports the transport error.
            }
          }
        } finally {
          _active = null;
        }
      }
    } finally {
      _draining = false;
      if (_queue.isNotEmpty) unawaited(_drain());
    }
  }
}

class _QueuedText {
  _QueuedText(this.session, this.strokes, this.codePoints);

  final HidTextOutputSession session;
  final List<HidTextStroke> strokes;
  final List<int> codePoints;
  final Completer<void> completer = Completer<void>();
}
