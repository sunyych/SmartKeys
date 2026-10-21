import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_keys/data/community_setup_repository.dart';
import 'package:smart_keys/data/shortcut_usage_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'missing setup uses defaults and values survive a new repository',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'community_setup_',
      );
      addTearDown(() => directory.delete(recursive: true));
      final repository = CommunitySetupRepository(
        directoryProvider: () async => directory,
      );

      expect(await repository.load(), const CommunitySetupPreferences());
      const saved = CommunitySetupPreferences(
        completed: true,
        profession: 'design',
        experience: 'intermediate',
      );
      await repository.save(saved);

      final restarted = CommunitySetupRepository(
        directoryProvider: () async => directory,
      );
      final loaded = await restarted.load();
      expect(loaded.completed, isTrue);
      expect(loaded.profession, saved.profession);
      expect(loaded.experience, saved.experience);
      final savedJson =
          jsonDecode(
                await File(
                  '${directory.path}${Platform.pathSeparator}${CommunitySetupRepository.fileName}',
                ).readAsString(),
              )
              as Map<String, dynamic>;
      expect(savedJson.keys.toSet(), {
        'schema_version',
        'completed',
        'profession',
        'experience',
      });
      expect(
        await directory
            .list()
            .map((entity) => entity.uri.pathSegments.last)
            .toList(),
        [CommunitySetupRepository.fileName],
      );
    },
  );

  test(
    'interrupted replacement recovers previous file and drops temp file',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'community_setup_recovery_',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File(
        '${directory.path}${Platform.pathSeparator}${CommunitySetupRepository.fileName}',
      );
      final previous = File('${file.path}.previous');
      final temporary = File('${file.path}.next');
      await previous.writeAsString(
        jsonEncode({
          'schema_version': 1,
          'completed': true,
          'profession': 'office',
          'experience': 'advanced',
        }),
      );
      await temporary.writeAsString('incomplete write');

      final repository = CommunitySetupRepository(
        directoryProvider: () async => directory,
      );
      final recovered = await repository.load();

      expect(recovered.completed, isTrue);
      expect(recovered.profession, 'office');
      expect(recovered.experience, 'advanced');
      expect(await file.exists(), isTrue);
      expect(await temporary.exists(), isFalse);
      expect(await previous.exists(), isFalse);
    },
  );

  test(
    'loads and saves across repository instances serialize per directory',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'community_setup_concurrent_',
      );
      addTearDown(() => directory.delete(recursive: true));
      CommunitySetupRepository repository() =>
          CommunitySetupRepository(directoryProvider: () async => directory);

      final operations = <Future<void>>[];
      for (var index = 0; index < 12; index++) {
        final value = CommunitySetupPreferences(
          completed: true,
          profession: index.isEven ? 'design' : 'office',
          experience: index.isEven ? 'beginner' : 'advanced',
        );
        operations.add(repository().save(value));
        operations.add(
          repository().load().then((loaded) {
            expect(loaded.completed, isA<bool>());
            expect(loaded.profession, anyOf(isNull, 'design', 'office'));
            expect(loaded.experience, anyOf(isNull, 'beginner', 'advanced'));
          }),
        );
      }
      await Future.wait(operations);

      final finalState = await repository().load();
      expect(finalState.completed, isTrue);
      expect(
        (finalState.profession == 'design' &&
                finalState.experience == 'beginner') ||
            (finalState.profession == 'office' &&
                finalState.experience == 'advanced'),
        isTrue,
      );
      expect(
        await directory
            .list()
            .map((entity) => entity.uri.pathSegments.last)
            .toList(),
        [CommunitySetupRepository.fileName],
      );
    },
  );

  test(
    'invalid allowlist values and malformed stored data are rejected',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'community_setup_invalid_',
      );
      addTearDown(() => directory.delete(recursive: true));
      final repository = CommunitySetupRepository(
        directoryProvider: () async => directory,
      );
      await expectLater(
        repository.save(
          const CommunitySetupPreferences(
            completed: true,
            profession: 'free text',
          ),
        ),
        throwsArgumentError,
      );
      final file = File(
        '${directory.path}${Platform.pathSeparator}${CommunitySetupRepository.fileName}',
      );
      await file.writeAsString(
        jsonEncode({
          'schema_version': 1,
          'completed': true,
          'profession': null,
          'experience': 'expert',
        }),
      );
      await expectLater(repository.load(), throwsFormatException);
    },
  );

  test('storage errors propagate for the launch gate to fail open', () async {
    final repository = CommunitySetupRepository(
      directoryProvider: () async => throw const FileSystemException('offline'),
    );
    await expectLater(repository.load(), throwsA(isA<FileSystemException>()));
    await expectLater(
      repository.save(const CommunitySetupPreferences(completed: true)),
      throwsA(isA<FileSystemException>()),
    );
  });

  test('clearing shortcut history leaves setup choices untouched', () async {
    SharedPreferences.setMockInitialValues({});
    final directory = await Directory.systemTemp.createTemp(
      'community_setup_usage_clear_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final setup = CommunitySetupRepository(
      directoryProvider: () async => directory,
    );
    const saved = CommunitySetupPreferences(
      completed: true,
      profession: 'software_engineering',
      experience: 'advanced',
    );
    await setup.save(saved);
    final usage = FileShortcutUsageRepository(
      directoryProvider: () async => directory,
    );
    await usage.load();
    await usage.record('copy', 'Copy');
    await usage.flush();
    await usage.clear();

    final restored = await CommunitySetupRepository(
      directoryProvider: () async => directory,
    ).load();
    expect(restored.completed, isTrue);
    expect(restored.profession, saved.profession);
    expect(restored.experience, saved.experience);
  });
}
