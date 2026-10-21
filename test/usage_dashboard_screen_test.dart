import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_keys/app.dart';
import 'package:smart_keys/data/account_backup_client.dart';
import 'package:smart_keys/data/community_setup_repository.dart';
import 'package:smart_keys/data/shortcut_community_client.dart';
import 'package:smart_keys/data/shortcut_community_store.dart';
import 'package:smart_keys/services/google_account_auth_service.dart';
import 'package:smart_keys/ui/account_backup_screen.dart';
import 'package:smart_keys/ui/settings_screen.dart';
import 'package:smart_keys/ui/usage_dashboard_screen.dart';

import 'test_support.dart';
import 'screenshot_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(ScreenshotSupport.prepareFonts);

  testWidgets(
    'Settings links to Dashboard and Dashboard starts with sharing off',
    (tester) async {
      final harness = await TestHarness.create();
      addTearDown(harness.dispose);
      const privateUsageChannel = MethodChannel('smart_keys/private_usage');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            privateUsageChannel,
            (call) async => harness.directory.path,
          );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(privateUsageChannel, null),
      );
      await tester.pumpWidget(
        SmartKeysScope(
          controller: harness.controller,
          child: const MaterialApp(home: SettingsScreen()),
        ),
      );
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('open-usage-dashboard')),
        240,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('open-usage-dashboard')),
      );
      await _settleDashboard(tester);
      expect(find.text('Usage Dashboard'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('open-usage-dashboard')));
      await _settleDashboard(tester);
      expect(find.text('Shortcut usage'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('usage-sharing-enabled')),
        findsOneWidget,
      );
      final sharing = tester.widget<SwitchListTile>(
        find.byKey(const ValueKey('usage-sharing-enabled')),
      );
      expect(sharing.value, isFalse);
      expect(
        find.text('Community service is not configured for this build.'),
        findsOneWidget,
      );
    },
  );

  testWidgets('clear confirmation removes local history and ranking changes', (
    tester,
  ) async {
    final harness = await TestHarness.create();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await harness.dispose();
    });
    await harness.shortcutUsage.record(
      'key-a',
      'Copy',
      publicShortcutId: 'copy',
    );
    await harness.shortcutUsage.record(
      'key-b',
      'Copy',
      publicShortcutId: 'paste',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: SmartKeysScope(
          controller: harness.controller,
          child: UsageDashboardScreen(
            client: ShortcutCommunityClient(endpoint: ''),
            directoryProvider: () async => harness.directory,
          ),
        ),
      ),
    );
    await _settleDashboard(tester);
    expect(find.byKey(const ValueKey('usage-rank-key-a')), findsOneWidget);
    expect(find.byKey(const ValueKey('usage-rank-key-b')), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Today'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('usage-rank-key-a')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('usage-smart-sort')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey('usage-clear')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.widgetWithText(FilledButton, 'Clear'));
    await _settleDashboard(tester);
    expect(harness.shortcutUsage.events, isEmpty);
    expect(find.text('No clicks in this date range'), findsOneWidget);
  });

  testWidgets('community profession and experience filters are independent', (
    tester,
  ) async {
    final harness = await TestHarness.create();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await harness.dispose();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: SmartKeysScope(
          controller: harness.controller,
          child: UsageDashboardScreen(
            client: ShortcutCommunityClient(endpoint: ''),
            directoryProvider: () async => harness.directory,
          ),
        ),
      ),
    );
    await _settleDashboard(tester);

    final profession = find.byKey(const ValueKey('usage-community-tag'));
    await tester.scrollUntilVisible(
      profession,
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    await tester.ensureVisible(profession);
    await tester.pumpAndSettle();
    await tester.tap(profession);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Design').last);
    await tester.pumpAndSettle();

    final experience = find.byKey(const ValueKey('usage-community-experience'));
    await tester.scrollUntilVisible(
      experience,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    await tester.ensureVisible(experience);
    await tester.pumpAndSettle();
    await tester.tap(experience);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Advanced').last);
    await tester.pumpAndSettle();

    expect(tester.widget<DropdownButton<String>>(profession).value, 'design');
    expect(tester.widget<DropdownButton<String>>(experience).value, 'advanced');
  });

  testWidgets('Dashboard renders phone and tablet screenshots', (tester) async {
    final shots = ScreenshotSupport(tester);
    final harness = await TestHarness.create();
    addTearDown(() async {
      await shots.unmount();
      shots.resetViewport();
      await harness.dispose();
    });
    await harness.shortcutUsage.record(
      'key-copy',
      'Copy',
      publicShortcutId: 'copy',
    );
    await harness.shortcutUsage.record(
      'key-copy',
      'Copy',
      publicShortcutId: 'copy',
    );
    await harness.shortcutUsage.record(
      'key-paste',
      'Paste',
      publicShortcutId: 'paste',
    );

    Future<GlobalKey> capture(Size size, String id, String orientation) async {
      await shots.setViewport(size);
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: _screenshotTheme,
          home: SmartKeysScope(
            controller: harness.controller,
            child: RepaintBoundary(
              key: key,
              child: UsageDashboardScreen(
                client: ShortcutCommunityClient(endpoint: ''),
                directoryProvider: () async => harness.directory,
              ),
            ),
          ),
        ),
      );
      await _settleDashboard(tester);
      await shots.capture(
        id: id,
        title: orientation == 'portrait'
            ? 'Shortcut usage Dashboard · phone'
            : 'Shortcut usage Dashboard · tablet',
        orientation: orientation,
        notes:
            'Local ranking, date filters, community opt-in controls, and persistent bottom actions.',
        boundaryKey: key,
      );
      return key;
    }

    final phoneKey = await capture(
      const Size(412, 915),
      'usage-dashboard-phone',
      'portrait',
    );
    final experienceFilter = find.byKey(
      const ValueKey('usage-community-experience'),
    );
    await tester.scrollUntilVisible(
      experienceFilter,
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(experienceFilter);
    await tester.pumpAndSettle();
    await shots.capture(
      id: 'usage-dashboard-phone-experience-filter',
      title: 'Shortcut usage Dashboard · experience filter',
      orientation: 'portrait',
      notes:
          'Public rankings can be filtered independently by profession and optional computer proficiency.',
      boundaryKey: phoneKey,
    );
    await capture(
      const Size(1366, 1024),
      'usage-dashboard-tablet',
      'landscape',
    );
  });

  testWidgets('Account backup shows disabled state before OAuth setup', (
    tester,
  ) async {
    final shots = ScreenshotSupport(tester);
    final harness = await TestHarness.create();
    final auth = GoogleAccountAuthService(webClientId: '');
    final client = AccountBackupClient(auth: auth, endpoint: '');
    addTearDown(() async {
      await shots.unmount();
      shots.resetViewport();
      client.dispose();
      await harness.dispose();
    });
    await shots.setViewport(const Size(412, 915));
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        theme: _screenshotTheme,
        home: SmartKeysScope(
          controller: harness.controller,
          child: RepaintBoundary(
            key: key,
            child: AccountBackupScreen(auth: auth, client: client),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Google sign-in is not available in this build.'),
      findsOneWidget,
    );
    expect(
      find.text('Online backup service is not configured for this build.'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Sign in with Google'),
          )
          .onPressed,
      isNull,
    );
    await shots.capture(
      id: 'usage-account-backup-oauth-unconfigured',
      title: 'Google account backup · OAuth not configured',
      orientation: 'portrait',
      notes:
          'Backup controls remain disabled until OAuth configuration exists.',
      boundaryKey: key,
    );
  });

  testWidgets('sharing preview saves the selected profession tag per batch', (
    tester,
  ) async {
    final harness = await TestHarness.create();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await harness.dispose();
    });
    await harness.shortcutUsage.record(
      'key-copy',
      'Copy',
      publicShortcutId: 'copy',
    );
    final setupRepository = CommunitySetupRepository(
      directoryProvider: () async => harness.directory,
    );
    await tester.runAsync(
      () => setupRepository.save(
        const CommunitySetupPreferences(
          completed: true,
          profession: 'office',
          experience: 'beginner',
        ),
      ),
    );
    const endpoint = 'https://rankings.example.test';
    await tester.pumpWidget(
      MaterialApp(
        home: SmartKeysScope(
          controller: harness.controller,
          child: UsageDashboardScreen(
            client: ShortcutCommunityClient(endpoint: endpoint),
            directoryProvider: () async => harness.directory,
          ),
        ),
      ),
    );
    await _settleDashboard(tester);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('usage-sharing-enabled')),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    await tester.ensureVisible(
      find.byKey(const ValueKey('usage-sharing-enabled')),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const ValueKey('usage-sharing-enabled')),
          )
          .value,
      isFalse,
    );
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('usage-sharing-enabled')),
        matching: find.byType(Switch),
      ),
    );
    for (var attempt = 0; attempt < 60; attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
      final preview = find.byKey(const ValueKey('usage-share-preview'));
      final sharingEnabled = tester
          .widget<SwitchListTile>(
            find.byKey(const ValueKey('usage-sharing-enabled')),
          )
          .value;
      if (sharingEnabled && preview.evaluate().isNotEmpty) break;
    }
    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const ValueKey('usage-sharing-enabled')),
          )
          .value,
      isTrue,
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('usage-share-preview')),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    await tester.ensureVisible(
      find.byKey(const ValueKey('usage-share-preview')),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const ValueKey('usage-share-preview')));
    final previewTitle = find.text('Review this sharing batch');
    for (
      var attempt = 0;
      attempt < 60 && previewTitle.evaluate().isEmpty;
      attempt++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(previewTitle, findsOneWidget);
    expect(find.text('Copy: 1'), findsOneWidget);
    expect(find.text('Office work'), findsOneWidget);
    expect(find.text('Beginner'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('usage-preview-tag')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Design').last);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Design'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('usage-preview-experience')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Advanced').last);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Advanced'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Submit this batch'));
    await _settleDashboard(tester);
    final submissionStatus = find.textContaining('Submission not confirmed');
    for (
      var attempt = 0;
      attempt < 60 && submissionStatus.evaluate().isEmpty;
      attempt++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(submissionStatus, findsOneWidget);
    final restored = ShortcutCommunityStore(
      directory: harness.directory,
      serverOrigin: endpoint,
    );
    await tester.runAsync(restored.load);
    expect(restored.pending?.tag, 'design');
    expect(restored.pending?.experience, 'advanced');
    expect(restored.pending?.items, {'copy': 1});
  });

  testWidgets('sharing preview can omit saved metadata for one batch', (
    tester,
  ) async {
    final harness = await TestHarness.create();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await harness.dispose();
    });
    await harness.shortcutUsage.record(
      'key-paste',
      'Paste',
      publicShortcutId: 'paste',
    );
    final setupRepository = CommunitySetupRepository(
      directoryProvider: () async => harness.directory,
    );
    await tester.runAsync(
      () => setupRepository.save(
        const CommunitySetupPreferences(
          completed: true,
          profession: 'design',
          experience: 'advanced',
        ),
      ),
    );
    const endpoint = 'https://rankings.example.test';
    await tester.pumpWidget(
      MaterialApp(
        home: SmartKeysScope(
          controller: harness.controller,
          child: UsageDashboardScreen(
            client: ShortcutCommunityClient(endpoint: endpoint),
            directoryProvider: () async => harness.directory,
          ),
        ),
      ),
    );
    await _settleDashboard(tester);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('usage-sharing-enabled')),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    await tester.ensureVisible(
      find.byKey(const ValueKey('usage-sharing-enabled')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('usage-sharing-enabled')),
        matching: find.byType(Switch),
      ),
    );
    final preview = find.byKey(const ValueKey('usage-share-preview'));
    for (
      var attempt = 0;
      attempt < 60 && preview.evaluate().isEmpty;
      attempt++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(preview, findsOneWidget);
    await tester.scrollUntilVisible(
      preview,
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    await tester.ensureVisible(preview);
    await tester.pumpAndSettle();
    await tester.tap(preview);
    final previewTitle = find.text('Review this sharing batch');
    for (
      var attempt = 0;
      attempt < 60 && previewTitle.evaluate().isEmpty;
      attempt++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(previewTitle, findsOneWidget);
    expect(find.text('Design'), findsOneWidget);
    expect(find.text('Advanced'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('usage-preview-tag')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('None').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('usage-preview-experience')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('None').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Submit this batch'));
    final submissionStatus = find.textContaining('Submission not confirmed');
    for (
      var attempt = 0;
      attempt < 60 && submissionStatus.evaluate().isEmpty;
      attempt++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(submissionStatus, findsOneWidget);
    final restored = ShortcutCommunityStore(
      directory: harness.directory,
      serverOrigin: endpoint,
    );
    await tester.runAsync(restored.load);
    expect(restored.pending?.tag, isNull);
    expect(restored.pending?.experience, isNull);
    expect(restored.pending!.toPayload().containsKey('experience'), isFalse);
  });
}

final _screenshotTheme = ThemeData(
  brightness: Brightness.dark,
  colorScheme: ColorScheme.fromSeed(
    seedColor: Color(0xFF67E8F9),
    brightness: Brightness.dark,
    surface: Color(0xFF10151D),
  ),
  scaffoldBackgroundColor: Color(0xFF090D12),
  cardTheme: CardThemeData(
    color: Color(0xFF151C26),
    elevation: 0,
    margin: EdgeInsets.zero,
  ),
  inputDecorationTheme: InputDecorationTheme(border: OutlineInputBorder()),
  useMaterial3: true,
);

Future<void> _settleDashboard(WidgetTester tester) async {
  for (var attempt = 0; attempt < 6; attempt++) {
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    if (find.byType(CircularProgressIndicator).evaluate().isEmpty) break;
  }
}
