import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as paths;
import 'package:path_provider/path_provider.dart';

abstract interface class DiagnosticsStore {
  Future<Object?> readJournal();
  Future<Object?> readConsent();
  Future<void> writeJournal(Map<String, Object?> value);
  Future<void> writeConsent(Map<String, Object?> value);
  Future<bool> isRevoked();
  Future<void> markRevoked();
  Future<void> clearRevocation();
}

class FileDiagnosticsStore implements DiagnosticsStore {
  FileDiagnosticsStore({Future<Directory> Function()? directory})
    : _directory = directory ?? getApplicationSupportDirectory;
  final Future<Directory> Function() _directory;
  Future<File> _file(String name) async =>
      File(paths.join((await _directory()).path, 'error_diagnostics', name));
  Future<Object?> _read(String name, int limit) async {
    final file = await _file(name);
    if (!await file.exists()) return null;
    if (await file.length() > limit) {
      throw const FormatException('Diagnostic store exceeds its limit');
    }
    return jsonDecode(await file.readAsString());
  }

  Future<void> _write(
    String name,
    Map<String, Object?> value,
    int limit,
  ) async {
    final bytes = utf8.encode(jsonEncode(value));
    if (bytes.length > limit) {
      throw const FormatException('Diagnostic store exceeds its limit');
    }
    final file = await _file(name);
    await file.parent.create(recursive: true);
    final next = File('${file.path}.next');
    await next.writeAsBytes(bytes, flush: true);
    await next.rename(file.path);
  }

  @override
  Future<Object?> readJournal() => _read('journal.json', 5 * 1024 * 1024);
  @override
  Future<Object?> readConsent() => _read('consent.json', 2048);
  @override
  Future<void> writeJournal(Map<String, Object?> value) =>
      _write('journal.json', value, 5 * 1024 * 1024);
  @override
  Future<void> writeConsent(Map<String, Object?> value) =>
      _write('consent.json', value, 2048);
  @override
  Future<bool> isRevoked() async => (await _file('revoked')).exists();
  @override
  Future<void> markRevoked() async {
    final file = await _file('revoked');
    await file.parent.create(recursive: true);
    await file.writeAsString('revoked', flush: true);
  }

  @override
  Future<void> clearRevocation() async {
    final file = await _file('revoked');
    if (await file.exists()) await file.delete();
  }
}

class MemoryDiagnosticsStore implements DiagnosticsStore {
  Object? journal, consent;
  bool revoked = false,
      failJournal = false,
      failConsent = false,
      failTombstone = false;
  @override
  Future<Object?> readJournal() async => journal;
  @override
  Future<Object?> readConsent() async => consent;
  @override
  Future<void> writeJournal(Map<String, Object?> value) async {
    if (failJournal) throw const FileSystemException('Unavailable');
    journal = jsonDecode(jsonEncode(value));
  }

  @override
  Future<void> writeConsent(Map<String, Object?> value) async {
    if (failConsent) throw const FileSystemException('Unavailable');
    consent = jsonDecode(jsonEncode(value));
  }

  @override
  Future<bool> isRevoked() async => revoked;
  @override
  Future<void> markRevoked() async {
    if (failTombstone) throw const FileSystemException('Unavailable');
    revoked = true;
  }

  @override
  Future<void> clearRevocation() async {
    if (failTombstone) throw const FileSystemException('Unavailable');
    revoked = false;
  }
}
