import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

/// A transcript sink reports success only after the native injector has
/// submitted every Unicode event. It must never launch a process with text as
/// an argument or write to the clipboard.
abstract interface class DictationTextSink {
  Future<void> insertText(String text);
}

class DictationRequestException implements Exception {
  const DictationRequestException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  @override
  String toString() => message;
}

class DictationInputBusyException implements Exception {
  const DictationInputBusyException(this.reason);

  final String reason;

  @override
  String toString() => 'Text insertion is temporarily blocked: $reason';
}

/// Validates, deduplicates and serializes phone text delivery.
class DictationReceiver {
  DictationReceiver({
    required this.token,
    required this.sink,
    this.maxBodyBytes = 64 * 1024,
    this.maxTextCodeUnits = 8000,
    this.maxRememberedRequests = 1024,
  });

  final String token;
  final DictationTextSink sink;
  final int maxBodyBytes;
  final int maxTextCodeUnits;
  final int maxRememberedRequests;

  final LinkedHashMap<String, _DeliveryOutcome> _seen = LinkedHashMap();
  Future<void> _tail = Future<void>.value();
  int _pending = 0;

  Future<void> handle(HttpRequest request) async {
    request.response.headers.contentType = ContentType.json;
    if (request.headers.value('x-lumiakeys-token') != token) {
      throw const DictationRequestException(HttpStatus.forbidden, 'forbidden');
    }
    if (request.method != 'POST' || request.uri.path != '/dictation') {
      throw const DictationRequestException(HttpStatus.notFound, 'not found');
    }

    final body = await _readBounded(request);
    Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(body, allowMalformed: false));
    } on FormatException {
      throw const DictationRequestException(
        HttpStatus.badRequest,
        'invalid_json',
      );
    }
    if (decoded is! Map) {
      throw const DictationRequestException(
        HttpStatus.badRequest,
        'invalid_body',
      );
    }
    final session = decoded['sessionId'];
    final sequence = decoded['sequence'];
    final text = decoded['text'];
    if (session is! String ||
        session.isEmpty ||
        session.length > 128 ||
        !RegExp(r'^[A-Za-z0-9._:-]+$').hasMatch(session)) {
      throw const DictationRequestException(
        HttpStatus.badRequest,
        'invalid_session',
      );
    }
    if (sequence is! int || sequence < 0) {
      throw const DictationRequestException(
        HttpStatus.badRequest,
        'invalid_sequence',
      );
    }
    if (text is! String || text.isEmpty || text.length > maxTextCodeUnits) {
      throw const DictationRequestException(
        HttpStatus.badRequest,
        'invalid_text',
      );
    }
    if (text.runes.any(_isControl)) {
      throw const DictationRequestException(
        HttpStatus.badRequest,
        'unsupported_control_character',
      );
    }

    final key = '$session:$sequence';
    if (_pending >= 32) {
      throw const DictationRequestException(
        HttpStatus.tooManyRequests,
        'delivery_queue_full',
      );
    }
    _pending++;
    final result = Completer<void>();
    final previous = _tail;
    _tail = result.future.catchError((Object _) {});
    await previous;
    try {
      final seen = _seen[key];
      if (seen != null) {
        _touch(key);
        if (seen.textDigest != sha256.convert(utf8.encode(text)).toString()) {
          throw const DictationRequestException(
            HttpStatus.conflict,
            'sequence_payload_conflict',
          );
        }
        if (!seen.succeeded) {
          throw const DictationRequestException(
            HttpStatus.conflict,
            'previous_insertion_failed',
          );
        }
        return;
      }
      try {
        await sink.insertText(text);
        _remember(
          key,
          _DeliveryOutcome(
            succeeded: true,
            textDigest: sha256.convert(utf8.encode(text)).toString(),
          ),
        );
      } catch (_) {
        // A partial native submission is unsafe to replay. Keep a failed
        // tombstone so duplicates remain errors and never re-inject text.
        _remember(
          key,
          _DeliveryOutcome(
            succeeded: false,
            textDigest: sha256.convert(utf8.encode(text)).toString(),
          ),
        );
        rethrow;
      }
    } finally {
      _pending--;
      result.complete();
    }
  }

  Future<Uint8List> _readBounded(HttpRequest request) async {
    if (request.contentLength > maxBodyBytes) {
      await request.drain<void>();
      throw const DictationRequestException(
        HttpStatus.requestEntityTooLarge,
        'body_too_large',
      );
    }
    final builder = BytesBuilder(copy: false);
    var tooLarge = false;
    await for (final chunk in request) {
      if (builder.length + chunk.length > maxBodyBytes) {
        tooLarge = true;
        continue;
      }
      if (!tooLarge) builder.add(chunk);
    }
    if (tooLarge) {
      throw const DictationRequestException(
        HttpStatus.requestEntityTooLarge,
        'body_too_large',
      );
    }
    return builder.takeBytes();
  }

  static bool _isControl(int rune) =>
      rune < 0x20 || (rune >= 0x7f && rune <= 0x9f);

  void _remember(String key, _DeliveryOutcome outcome) {
    _seen[key] = outcome;
    while (_seen.length > maxRememberedRequests) {
      _seen.remove(_seen.keys.first);
    }
  }

  void _touch(String key) {
    final value = _seen.remove(key);
    if (value != null) _seen[key] = value;
  }
}

class _DeliveryOutcome {
  const _DeliveryOutcome({required this.succeeded, required this.textDigest});
  final bool succeeded;
  final String textDigest;
}

/// Executes a native insertion and maps native rejection/partial results to
/// an exception so the HTTP endpoint cannot acknowledge them.
class MethodChannelDictationTextSink implements DictationTextSink {
  MethodChannelDictationTextSink({
    this.channel = const MethodChannel('lumiakeys/dictation'),
  });

  final MethodChannel channel;
  Future<void> _tail = Future<void>.value();
  int _pending = 0;

  @override
  Future<void> insertText(String text) {
    if (_pending >= 32) {
      return Future.error(StateError('Text delivery queue is full'));
    }
    _pending++;
    final previous = _tail;
    final next = previous.then((_) => _insertText(text));
    _tail = next.catchError((Object _) {});
    return next.whenComplete(() => _pending--);
  }

  Future<void> _insertText(String text) async {
    final result = await channel.invokeMapMethod<String, Object?>(
      'insertText',
      {'text': text},
    );
    final status = result?['status'];
    if (status != 'delivered' && status != 'submitted') {
      final reason = result?['reason'];
      if (status == 'rejected' &&
          (reason == 'modifier_key_held' ||
              reason == 'foreground_changed_or_modifier_held' ||
              reason == 'held_modifier')) {
        throw DictationInputBusyException(reason! as String);
      }
      throw StateError('Text insertion failed: ${reason ?? 'unknown'}');
    }
  }
}
