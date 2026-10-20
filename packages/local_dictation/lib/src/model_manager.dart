import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'model.dart';

/// Installs pinned local model files into application-private support storage.
/// Network access occurs only from [prepareModel].
class ModelManager {
  ModelManager({
    Future<Directory> Function()? modelRootProvider,
    this._descriptorResolver,
    this._urlResolver,
    this._clientFactory,
  }) : _rootProvider = modelRootProvider;

  final Future<Directory> Function()? _rootProvider;
  final LocalAsrModelDescriptor Function(LocalAsrModel)? _descriptorResolver;
  final Uri Function(LocalAsrModelDescriptor, LocalAsrFile)? _urlResolver;
  final http.Client Function()? _clientFactory;
  bool _busy = false;
  bool _cancelled = false;
  http.Client? _activeClient;

  LocalAsrModelDescriptor descriptor(LocalAsrModel model) =>
      _descriptorResolver?.call(model) ??
      LocalAsrModelDescriptor.forModel(model);

  Future<Directory> _root() async {
    final root = await (_rootProvider?.call() ?? _defaultRoot());
    await root.create(recursive: true);
    if (await FileSystemEntity.type(root.path, followLinks: false) ==
        FileSystemEntityType.link) {
      throw FileSystemException(
        'Model root cannot be a symbolic link',
        root.path,
      );
    }
    return root;
  }

  Future<Directory> _defaultRoot() async {
    final support = await getApplicationSupportDirectory();
    return Directory(p.join(support.path, 'local_dictation', 'models'));
  }

  Future<Directory> _modelDirectory(LocalAsrModel model) async {
    final descriptor = descriptorForChecked(model);
    final root = await _root();
    final child = descriptor.directory;
    if (child.isEmpty ||
        p.isAbsolute(child) ||
        p.normalize(child) != child ||
        p.split(child).length != 1 ||
        child == '.' ||
        child == '..') {
      throw FileSystemException(
        'Model directory escapes its managed root',
        child,
      );
    }
    final target = Directory(p.join(root.path, child));
    if (await FileSystemEntity.type(target.path, followLinks: false) ==
        FileSystemEntityType.link) {
      throw FileSystemException(
        'Model cache cannot be a symbolic link',
        target.path,
      );
    }
    return target;
  }

  LocalAsrModelDescriptor descriptorForChecked(LocalAsrModel model) {
    final value = descriptor(model);
    if (value.model != model ||
        value.files.isEmpty ||
        value.files.map((f) => f.name).toSet().length != value.files.length ||
        value.files.any(
          (f) =>
              f.name.isEmpty ||
              p.isAbsolute(f.name) ||
              p.normalize(f.name) != f.name ||
              p.split(f.name).length != 1 ||
              f.sizeBytes <= 0 ||
              !RegExp(r'^[a-f0-9]{64}$').hasMatch(f.sha256),
        )) {
      throw ArgumentError('Invalid pinned descriptor for $model');
    }
    return value;
  }

  Future<bool> areModelsAvailable({
    LocalAsrModel model = LocalAsrModel.senseVoice,
  }) async {
    try {
      final descriptor = descriptorForChecked(model);
      final directory = await _modelDirectory(model);
      return await _directoryValid(directory, descriptor);
    } catch (_) {
      return false;
    }
  }

  Future<LocalAsrModelFiles> installedModel(LocalAsrModel model) async {
    final descriptor = descriptorForChecked(model);
    final directory = await _modelDirectory(model);
    if (!await _directoryValid(directory, descriptor)) {
      throw StateError(
        '${model.name} model is not installed or failed integrity validation.',
      );
    }
    return _filesFor(model, directory.path, descriptor);
  }

  Future<LocalAsrModelFiles> prepareModel(
    LocalAsrModel model, {
    void Function(ModelDownloadProgress progress)? onProgress,
  }) async {
    if (_busy) throw StateError('A model operation is already active.');
    _busy = true;
    _cancelled = false;
    try {
      final descriptor = descriptorForChecked(model);
      final directory = await _modelDirectory(model);
      await directory.create(recursive: true);
      for (final expected in descriptor.files) {
        _checkCancelled();
        final destination = File(p.join(directory.path, expected.name));
        if (await _fileValid(destination, expected)) continue;
        final partial = File('${destination.path}.part');
        if (await partial.exists()) await partial.delete();
        final client = _clientFactory?.call() ?? http.Client();
        _activeClient = client;
        RandomAccessFile? output;
        var received = 0;
        try {
          output = await partial.open(mode: FileMode.writeOnly);
          final uri =
              _urlResolver?.call(descriptor, expected) ??
              descriptor.urlFor(expected);
          final response = await client
              .send(http.Request('GET', uri))
              .timeout(const Duration(seconds: 45));
          if (response.statusCode != HttpStatus.ok) {
            throw HttpException(
              'Model request returned HTTP ${response.statusCode}.',
            );
          }
          if (response.contentLength != null &&
              response.contentLength != expected.sizeBytes) {
            throw HttpException('Unexpected size for ${expected.name}.');
          }
          await for (final chunk in response.stream.timeout(
            const Duration(seconds: 45),
          )) {
            _checkCancelled();
            received += chunk.length;
            if (received > expected.sizeBytes) {
              throw HttpException('Model file exceeds its pinned size.');
            }
            await output.writeFrom(chunk);
            onProgress?.call(
              ModelDownloadProgress(
                model: model,
                fileName: expected.name,
                bytesReceived: received,
                totalBytes: expected.sizeBytes,
              ),
            );
          }
          await output.flush();
          await output.close();
          output = null;
          if (received != expected.sizeBytes ||
              !await _fileValid(partial, expected)) {
            throw HttpException(
              'Model integrity validation failed for ${expected.name}.',
            );
          }
          _checkCancelled();
          if (await destination.exists()) await destination.delete();
          await partial.rename(destination.path);
        } catch (_) {
          await output?.close();
          if (await partial.exists()) await partial.delete();
          if (_cancelled) throw StateError('Model download cancelled.');
          rethrow;
        } finally {
          _activeClient = null;
          client.close();
        }
      }
      _checkCancelled();
      return _filesFor(model, directory.path, descriptor);
    } finally {
      _busy = false;
    }
  }

  /// Imports a directory containing every file for [model], validating pinned
  /// sizes and hashes before replacing the managed cache.
  Future<LocalAsrModelFiles> importModel(
    LocalAsrModel model,
    Directory source,
  ) async {
    if (_busy) throw StateError('A model operation is already active.');
    _busy = true;
    try {
      final descriptor = descriptorForChecked(model);
      if (!await _directoryValid(source, descriptor)) {
        throw FormatException(
          'Selected directory does not contain a complete valid ${model.label} model.',
        );
      }
      final destination = await _modelDirectory(model);
      final root = await _root();
      final staging = Directory('${destination.path}.importing');
      await _deleteChildIfPresent(staging, root);
      await staging.create(recursive: true);
      try {
        for (final expected in descriptor.files) {
          await File(
            p.join(source.path, expected.name),
          ).copy(p.join(staging.path, expected.name));
          if (!await _fileValid(
            File(p.join(staging.path, expected.name)),
            expected,
          )) {
            throw FormatException('Model changed while it was being imported.');
          }
        }
        final backup = Directory('${destination.path}.previous');
        await _deleteChildIfPresent(backup, root);
        if (await destination.exists()) await destination.rename(backup.path);
        try {
          await staging.rename(destination.path);
        } catch (_) {
          if (await backup.exists()) await backup.rename(destination.path);
          rethrow;
        }
        await _deleteChildIfPresent(backup, root);
      } catch (_) {
        await _deleteChildIfPresent(staging, root);
        rethrow;
      }
      return _filesFor(model, destination.path, descriptor);
    } finally {
      _busy = false;
    }
  }

  Future<void> deleteModel(LocalAsrModel model) async {
    if (_busy) {
      throw StateError('Cannot delete a model during another model operation.');
    }
    _busy = true;
    try {
      final directory = await _modelDirectory(model);
      final root = await _root();
      await _deleteChildIfPresent(directory, root);
      await _deleteChildIfPresent(
        Directory('${directory.path}.importing'),
        root,
      );
      await _deleteChildIfPresent(
        Directory('${directory.path}.previous'),
        root,
      );
    } finally {
      _busy = false;
    }
  }

  Future<void> _deleteChildIfPresent(Directory target, Directory root) async {
    final type = await FileSystemEntity.type(target.path, followLinks: false);
    if (type == FileSystemEntityType.notFound) return;
    if (type != FileSystemEntityType.directory) {
      throw FileSystemException(
        'Model staging path is not a managed directory.',
        target.path,
      );
    }
    final canonicalRoot = await root.resolveSymbolicLinks();
    final canonicalTarget = await target.resolveSymbolicLinks();
    final relative = p.relative(canonicalTarget, from: canonicalRoot);
    if (relative == '.' ||
        relative == '..' ||
        p.isAbsolute(relative) ||
        relative.startsWith('..${p.separator}')) {
      throw FileSystemException(
        'Model staging path escapes its managed root.',
        target.path,
      );
    }
    await target.delete(recursive: true);
  }

  void cancelDownload() {
    _cancelled = true;
    _activeClient?.close();
  }

  void _checkCancelled() {
    if (_cancelled) throw StateError('Model download cancelled.');
  }

  Future<bool> _directoryValid(
    Directory directory,
    LocalAsrModelDescriptor descriptor,
  ) async {
    for (final expected in descriptor.files) {
      if (!await _fileValid(
        File(p.join(directory.path, expected.name)),
        expected,
      )) {
        return false;
      }
    }
    return true;
  }

  Future<bool> _fileValid(File file, LocalAsrFile expected) async {
    if (await FileSystemEntity.type(file.path, followLinks: false) !=
            FileSystemEntityType.file ||
        !await file.exists() ||
        await file.length() != expected.sizeBytes) {
      return false;
    }
    return (await sha256.bind(file.openRead()).first).toString() ==
        expected.sha256;
  }

  LocalAsrModelFiles _filesFor(
    LocalAsrModel model,
    String path,
    LocalAsrModelDescriptor d,
  ) => LocalAsrModelFiles(
    model: model,
    modelPath: p.join(path, d.primaryModelFile),
    tokensPath: p.join(path, 'tokens.txt'),
    encoderPath: d.encoderFile == null ? null : p.join(path, d.encoderFile!),
    decoderPath: d.decoderFile == null ? null : p.join(path, d.decoderFile!),
  );
}
