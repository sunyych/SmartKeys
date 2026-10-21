import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'private_usage_directory.dart';
import 'shortcut_community_client.dart';

class CommunitySetupPreferences {
  const CommunitySetupPreferences({
    this.completed = false,
    this.profession,
    this.experience,
  });

  final bool completed;
  final String? profession;
  final String? experience;
}

class CommunitySetupRepository {
  CommunitySetupRepository({Future<Directory> Function()? directoryProvider})
    : _directoryProvider = directoryProvider ?? privateUsageDirectory;

  static const fileName = 'community_setup.json';
  static const _temporarySuffix = '.next';
  static const _previousSuffix = '.previous';
  static final Map<String, Future<void>> _directoryTails = {};

  final Future<Directory> Function() _directoryProvider;

  Future<CommunitySetupPreferences> load() async {
    final directory = await _directoryProvider();
    return _serializeForDirectory(directory, () async {
      await directory.create(recursive: true);
      final file = _fileIn(directory);
      final temporary = File('${file.path}$_temporarySuffix');
      final previous = File('${file.path}$_previousSuffix');

      if (!await file.exists() && await previous.exists()) {
        await previous.rename(file.path);
      } else if (await file.exists() && await previous.exists()) {
        await previous.delete();
      }
      if (await temporary.exists()) await temporary.delete();
      if (!await file.exists()) return const CommunitySetupPreferences();

      final decoded = jsonDecode(utf8.decode(await file.readAsBytes()));
      if (decoded is! Map || decoded.keys.any((key) => key is! String)) {
        throw const FormatException('Community setup data must be an object.');
      }
      final data = decoded.cast<String, dynamic>();
      const expectedKeys = {
        'schema_version',
        'completed',
        'profession',
        'experience',
      };
      if (data.keys.toSet().difference(expectedKeys).isNotEmpty ||
          expectedKeys.difference(data.keys.toSet()).isNotEmpty ||
          data['schema_version'] != 1 ||
          data['completed'] is! bool ||
          !_isAllowedProfession(data['profession']) ||
          !_isAllowedExperience(data['experience'])) {
        throw const FormatException('Community setup data is invalid.');
      }
      return CommunitySetupPreferences(
        completed: data['completed'] as bool,
        profession: data['profession'] as String?,
        experience: data['experience'] as String?,
      );
    });
  }

  Future<void> save(CommunitySetupPreferences preferences) async {
    if (!_isAllowedProfession(preferences.profession) ||
        !_isAllowedExperience(preferences.experience)) {
      throw ArgumentError('Community setup values are not supported.');
    }
    final directory = await _directoryProvider();
    await _serializeForDirectory(directory, () async {
      await directory.create(recursive: true);
      final file = _fileIn(directory);
      final temporary = File('${file.path}$_temporarySuffix');
      final previous = File('${file.path}$_previousSuffix');
      final json = jsonEncode({
        'schema_version': 1,
        'completed': preferences.completed,
        'profession': preferences.profession,
        'experience': preferences.experience,
      });
      await temporary.writeAsString(json, encoding: utf8, flush: true);
      if (await previous.exists()) await previous.delete();
      if (await file.exists()) await file.rename(previous.path);
      try {
        await temporary.rename(file.path);
        if (await previous.exists()) await previous.delete();
      } catch (_) {
        if (!await file.exists() && await previous.exists()) {
          await previous.rename(file.path);
        }
        rethrow;
      }
    });
  }

  Future<T> _serializeForDirectory<T>(
    Directory directory,
    Future<T> Function() operation,
  ) async {
    final key = directory.absolute.path;
    final previous = _directoryTails[key] ?? Future<void>.value();
    final finished = Completer<void>();
    _directoryTails[key] = finished.future;
    await previous;
    try {
      return await operation();
    } finally {
      finished.complete();
      if (identical(_directoryTails[key], finished.future)) {
        _directoryTails.remove(key);
      }
    }
  }

  File _fileIn(Directory directory) =>
      File('${directory.path}${Platform.pathSeparator}$fileName');

  bool _isAllowedProfession(Object? value) =>
      value == null ||
      (value is String && communityProfessionTags.containsKey(value));

  bool _isAllowedExperience(Object? value) =>
      value == null ||
      (value is String && communityExperienceLevels.containsKey(value));
}
