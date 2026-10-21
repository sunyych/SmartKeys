import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_keys/data/community_setup_repository.dart';
import 'package:smart_keys/ui/community_setup_screen.dart';

import 'screenshot_support.dart';

class _MemorySetupRepository extends CommunitySetupRepository {
  _MemorySetupRepository([this.preferences = const CommunitySetupPreferences()])
    : super(directoryProvider: () async => Directory.systemTemp);

  CommunitySetupPreferences preferences;

  @override
  Future<CommunitySetupPreferences> load() async => preferences;

  @override
  Future<void> save(CommunitySetupPreferences value) async {
    preferences = value;
  }
}

class _FailingLoadSetupRepository extends _MemorySetupRepository {
  @override
  Future<CommunitySetupPreferences> load() async =>
      throw const FileSystemException('private storage is unavailable');
}

class _FailingSaveSetupRepository extends _MemorySetupRepository {
  @override
  Future<void> save(CommunitySetupPreferences value) async =>
      throw const FileSystemException('private storage is unavailable');
}

class _FailingLoadWritableSetupRepository extends _MemorySetupRepository {
  _FailingLoadWritableSetupRepository(super.preferences);

  int saveCount = 0;

  @override
  Future<CommunitySetupPreferences> load() async =>
      throw const FileSystemException('private storage is unavailable');

  @override
  Future<void> save(CommunitySetupPreferences value) async {
    saveCount++;
    preferences = value;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(ScreenshotSupport.prepareFonts);

  testWidgets('community setup renders a phone screenshot', (tester) async {
    final shots = ScreenshotSupport(tester);
    addTearDown(() async {
      await shots.unmount();
      shots.resetViewport();
    });
    await shots.setViewport(const Size(390, 844));
    final boundaryKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          brightness: Brightness.dark,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF67E8F9),
            brightness: Brightness.dark,
            surface: const Color(0xFF10151D),
          ),
          scaffoldBackgroundColor: const Color(0xFF090D12),
          cardTheme: const CardThemeData(
            color: Color(0xFF151C26),
            elevation: 0,
            margin: EdgeInsets.zero,
          ),
          inputDecorationTheme: const InputDecorationTheme(
            border: OutlineInputBorder(),
          ),
          useMaterial3: true,
        ),
        home: screenshotBoundary(
          boundaryKey,
          CommunitySetupScreen(repository: _MemorySetupRepository()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await shots.capture(
      id: 'community-setup-phone',
      title: 'Community setup',
      orientation: 'portrait',
      notes: 'Optional local profession and computer proficiency setup.',
      boundaryKey: boundaryKey,
    );
  });

  testWidgets('first launch skip is saved and restart opens Home directly', (
    tester,
  ) async {
    final repository = _MemorySetupRepository();
    Future<void> pumpGate() => tester.pumpWidget(
      MaterialApp(
        home: CommunitySetupGate(
          repository: repository,
          child: const Scaffold(body: Text('Home')),
        ),
      ),
    );

    await pumpGate();
    await tester.pumpAndSettle();
    expect(find.text('Community setup'), findsOneWidget);
    expect(find.text('Home'), findsNothing);
    expect(
      find.textContaining('does not turn on sharing or upload'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('community-setup-skip')));
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsOneWidget);
    expect(repository.preferences.completed, isTrue);
    expect(repository.preferences.profession, isNull);
    expect(repository.preferences.experience, isNull);

    await pumpGate();
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Community setup'), findsNothing);
  });

  testWidgets('finish saves optional allowlisted choices', (tester) async {
    final repository = _MemorySetupRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: CommunitySetupGate(
          repository: repository,
          child: const Scaffold(body: Text('Home')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('community-setup-profession')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Design').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('community-setup-experience')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Beginner').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('community-setup-finish')));
    await tester.pumpAndSettle();

    expect(find.text('Home'), findsOneWidget);
    expect(repository.preferences.completed, isTrue);
    expect(repository.preferences.profession, 'design');
    expect(repository.preferences.experience, 'beginner');
  });

  testWidgets('storage errors never block Home or enable sharing', (
    tester,
  ) async {
    final failingLoad = _FailingLoadSetupRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: CommunitySetupGate(
          repository: failingLoad,
          child: const Scaffold(body: Text('Home')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Community setup'), findsNothing);

    final failingSave = _FailingSaveSetupRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: CommunitySetupGate(
          key: const ValueKey('failing-save-gate'),
          repository: failingSave,
          child: const Scaffold(body: Text('Home')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('community-setup-finish')));
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsOneWidget);
    expect(failingSave.preferences.completed, isFalse);
    expect(
      find.textContaining(
        'Sharing settings were not changed. No data was uploaded.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('load failure cannot overwrite choices when storage recovers', (
    tester,
  ) async {
    const existing = CommunitySetupPreferences(
      completed: true,
      profession: 'design',
      experience: 'advanced',
    );
    final repository = _FailingLoadWritableSetupRepository(existing);
    await tester.pumpWidget(
      MaterialApp(
        home: CommunitySetupScreen(repository: repository, isReopen: true),
      ),
    );
    await tester.pumpAndSettle();

    final save = tester.widget<FilledButton>(
      find.byKey(const ValueKey('community-setup-finish')),
    );
    expect(save.onPressed, isNull);
    expect(repository.saveCount, 0);
    expect(find.text('Continue without saving'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('community-setup-skip')));
    await tester.pumpAndSettle();
    expect(repository.saveCount, 0);
    expect(repository.preferences.profession, existing.profession);
    expect(repository.preferences.experience, existing.experience);
  });

  testWidgets('reopened setup can be cancelled without changing saved values', (
    tester,
  ) async {
    const existing = CommunitySetupPreferences(
      completed: true,
      profession: 'video_editing',
      experience: 'advanced',
    );
    final repository = _MemorySetupRepository(existing);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => CommunitySetupScreen(
                    repository: repository,
                    initialPreferences: existing,
                    isReopen: true,
                  ),
                ),
              ),
              child: const Text('Open setup'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open setup'));
    await tester.pumpAndSettle();
    expect(find.text('Cancel'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('community-setup-skip')));
    await tester.pumpAndSettle();
    expect(repository.preferences.profession, existing.profession);
    expect(repository.preferences.experience, existing.experience);
    expect(repository.preferences.completed, isTrue);
  });

  testWidgets('reopened setup can clear and save optional choices', (
    tester,
  ) async {
    const existing = CommunitySetupPreferences(
      completed: true,
      profession: 'design',
      experience: 'beginner',
    );
    final repository = _MemorySetupRepository(existing);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => CommunitySetupScreen(
                    repository: repository,
                    initialPreferences: existing,
                    isReopen: true,
                  ),
                ),
              ),
              child: const Text('Open setup'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open setup'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('community-setup-profession')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Prefer not to say').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('community-setup-experience')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Prefer not to say').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('community-setup-finish')));
    await tester.pumpAndSettle();

    expect(repository.preferences.completed, isTrue);
    expect(repository.preferences.profession, isNull);
    expect(repository.preferences.experience, isNull);
  });
}
