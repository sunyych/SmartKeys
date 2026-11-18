import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:diagnostics_core/diagnostics_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_keys/diagnostics/diagnostics_service.dart';
import 'package:smart_keys/diagnostics/diagnostics_store.dart';
import 'package:smart_keys/icons/app_icon_catalog.dart';
import 'package:smart_keys/icons/icon_library.dart';
import 'package:smart_keys/app_library/app_library.dart';
import 'package:smart_keys/ui/app_icon_library_screen.dart';
import 'package:smart_keys/ui/diagnostics_consent_screen.dart';
import 'package:smart_keys/ui/error_log_screen.dart';
import 'screenshot_support.dart';

class PreviewLibrary extends IconLibrary {
  List<LibraryIcon> online = [];
  final Map<String, Uint8List> downloaded = {};
  Completer<Uint8List?>? pending;
  bool onlineEnabled = false;
  @override
  bool get configured => onlineEnabled;
  @override
  List<LibraryIcon> get entries => [...super.entries, ...online];
  @override
  LibraryIcon? byId(String id) =>
      online.where((entry) => entry.id == id).firstOrNull ?? super.byId(id);
  @override
  Uint8List? cachedBytes(String id) => downloaded[id];
  @override
  bool isDownloaded(String id) => downloaded.containsKey(id);
  @override
  Future<void> initialize() async {}
  @override
  Future<void> refresh() async {
    notifyListeners();
  }

  @override
  Future<Uint8List?> loadCached(String id) =>
      pending?.future ?? Future.value(downloaded[id]);
  void changed() => notifyListeners();
}

DiagnosticsService diagnostics() => DiagnosticsService(
  metadata: DiagnosticMetadata(
    appVersion: '1.6.0',
    appBuild: 8,
    edition: DiagnosticEdition.full,
    platform: DiagnosticPlatform.android,
  ),
  store: MemoryDiagnosticsStore(),
  maintenanceInterval: Duration.zero,
);

Widget screen(
  Widget child, {
  IconLibrary? library,
  GlobalKey? boundary,
  double scale = 1,
}) {
  Widget result = MaterialApp(
    theme: ThemeData.dark(useMaterial3: true),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: child,
  );
  if (library != null) {
    result = IconLibraryScope(library: library, child: result);
  }
  return boundary == null ? result : screenshotBoundary(boundary, result);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(ScreenshotSupport.prepareFonts);
  testWidgets(
    'icon browser searches real catalog and narrow/large text stays usable',
    (tester) async {
      final library = PreviewLibrary();
      addTearDown(library.dispose);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(() {
        tester.view.resetDevicePixelRatio();
        tester.view.resetPhysicalSize();
      });
      await tester.pumpWidget(
        screen(const AppIconLibraryScreen(), library: library, scale: 1.3),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(
          '${AppLibraryCatalog.builtin.apps.where((app) => app.libraryForOS("windows") != null).length} Apps',
        ),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const ValueKey('icon-library-search')),
        'Google Chrome',
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('library-icon-chrome')), findsOneWidget);
      expect(find.text('1 Apps'), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const ValueKey('library-icon-chrome')),
      );
      await tester.tap(find.byKey(const ValueKey('library-icon-chrome')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('icon-library-preview')),
        findsOneWidget,
      );
      expect(find.text('Copy source link'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('icon-library-search')),
        'nothing-matches',
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('icon-library-empty')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'App library shows human macOS and Command labels without changing bindings',
    (tester) async {
      final library = PreviewLibrary();
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(844, 390);
      final app = AppLibraryCatalog.builtin.appById('chrome')!;
      final before = jsonEncode(app.toJson());
      try {
        await tester.pumpWidget(
          screen(const AppIconLibraryScreen(), library: library),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('app-library-os')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('macOS').last);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('icon-library-search')),
          'Chrome',
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(const ValueKey('library-icon-chrome')),
        );
        await tester.tap(find.byKey(const ValueKey('library-icon-chrome')));
        await tester.pumpAndSettle();
        expect(find.text('Command + T'), findsWidgets);
        expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('app-library-variant')))
              .data,
          'macOS · Desktop app · v${app.libraryForOS('macos')!.version}',
        );
        expect(find.textContaining('META +'), findsNothing);
        expect(find.textContaining('This phone does not write'), findsNothing);
        expect(jsonEncode(app.toJson()), before);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        library.dispose();
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      }
    },
  );
  testWidgets(
    'same extra ID hash/scope change drops old artwork while replacement is pending',
    (tester) async {
      final wire =
          jsonDecode(
                (await tester.runAsync(
                  () => File(
                    'community_server/assets/app_icons/catalog.json',
                  ).readAsString(),
                ))!,
              )
              as Map;
      final extra = LibraryIcon.fromJson(
        Map<String, dynamic>.from(
          (wire['icons'] as List).firstWhere((raw) => raw['bundled'] == false)
              as Map,
        ),
      );
      final bytes = (await tester.runAsync(
        () =>
            File('packages/app_icon_catalog/png/${extra.id}.png').readAsBytes(),
      ))!;
      final library = PreviewLibrary()
        ..online = [extra]
        ..downloaded[extra.id] = bytes;
      addTearDown(library.dispose);
      await tester.pumpWidget(
        screen(
          Center(child: AppArtwork(appId: extra.id)),
          library: library,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsOneWidget);
      final changed = extra.toJson()..['sha256'] = 'a' * 64;
      library.online = [
        LibraryIcon.fromJson(Map<String, dynamic>.from(changed)),
      ];
      library.pending = Completer<Uint8List?>();
      library.changed();
      await tester.pump();
      expect(find.byType(Image), findsNothing);
      expect(find.byIcon(Icons.apps), findsOneWidget);
      library.pending!.complete(null);
      await tester.pumpAndSettle();
    },
  );
  testWidgets(
    'consent skip is independent and log clear/retention/allow controls work',
    (tester) async {
      final service = diagnostics();
      await service.initialize();
      addTearDown(service.dispose);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(844, 390);
      addTearDown(() {
        tester.view.resetDevicePixelRatio();
        tester.view.resetPhysicalSize();
      });
      await tester.pumpWidget(
        screen(
          DiagnosticsConsentGate(
            diagnostics: service,
            child: const Scaffold(body: Text('Controls')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(service.sharing, false);
      await tester.ensureVisible(
        find.byKey(const ValueKey('diagnostics-not-now')),
      );
      await tester.tap(find.byKey(const ValueKey('diagnostics-not-now')));
      await tester.pumpAndSettle();
      expect(find.text('Controls'), findsOneWidget);
      expect(service.choice, DiagnosticChoice.undecided);
      await tester.pumpWidget(screen(ErrorLogScreen(diagnostics: service)));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('error-log-empty')), findsOneWidget);
      service.record(DiagnosticCode.iconDownloadFailed);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(ListTile).last);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('error-log-detail')), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('error-log-clear')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clear logs'));
      await tester.pumpAndSettle();
      expect(service.events, isEmpty);
      await tester.tap(find.byKey(const ValueKey('error-sharing-switch')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('error-sharing-confirmation')),
        findsOneWidget,
      );
      await tester.tap(find.text('Allow sharing'));
      await tester.pumpAndSettle();
      expect(service.sharing, true);
      expect(service.status, contains('unavailable'));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('idle hourly expiry refreshes an already open log screen', (
    tester,
  ) async {
    var now = DateTime.now();
    final store = MemoryDiagnosticsStore();
    final service = DiagnosticsService(
      metadata: diagnostics().metadata,
      store: store,
      clock: () => now,
      maintenanceInterval: const Duration(seconds: 1),
    );
    await service.initialize();
    await service.setRetentionDays(7);
    service.record(DiagnosticCode.runtimeFailure);
    await tester.pumpWidget(screen(ErrorLogScreen(diagnostics: service)));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('error-log-list')), findsOneWidget);
    now = now.add(const Duration(days: 8));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('error-log-empty')), findsOneWidget);
    expect(
      (((store.journal as Map)['journal'] as Map)['events'] as List),
      isEmpty,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    service.dispose();
  });
  testWidgets(
    'landscape icon search with keyboard and error banner can scroll to recovery',
    (tester) async {
      final library = PreviewLibrary()
        ..error =
            'The icon service is unavailable. Built-in and downloaded icons are still available.';
      addTearDown(library.dispose);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(844, 390);
      tester.view.viewInsets = const FakeViewPadding(bottom: 200);
      addTearDown(() {
        tester.view.resetViewInsets();
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await tester.pumpWidget(
        screen(const AppIconLibraryScreen(), library: library, scale: 1.3),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('icon-library-search')),
        'chrome',
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Retry'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('captures new Full icon and diagnostics production screens', (
    tester,
  ) async {
    final shots = ScreenshotSupport(tester), boundary = GlobalKey();
    final library = PreviewLibrary(), service = diagnostics();
    await service.initialize();
    final wire =
        jsonDecode(
              (await tester.runAsync(
                () => File(
                  'community_server/assets/app_icons/catalog.json',
                ).readAsString(),
              ))!,
            )
            as Map;
    library.online = [
      for (final raw in wire['icons'] as List)
        if (raw['bundled'] == false)
          LibraryIcon.fromJson(Map<String, dynamic>.from(raw as Map)),
    ];
    addTearDown(() async {
      await shots.unmount();
      shots.resetViewport();
      library.dispose();
      service.dispose();
    });
    Future<void> capture(
      String id,
      String title, {
      String notes =
          'Current production widgets with deterministic local fixtures. No real diagnostic uploads.',
    }) async {
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await shots.capture(
        id: id,
        title: title,
        orientation: 'landscape',
        notes: notes,
        boundaryKey: boundary,
      );
    }

    await shots.setViewport(const Size(844, 390));
    await tester.pumpWidget(
      screen(
        const AppIconLibraryScreen(),
        library: library,
        boundary: boundary,
      ),
    );
    final imageContext = tester.element(find.byType(AppIconLibraryScreen));
    await tester.runAsync(
      () => Future.wait([
        for (final asset in AppIconCatalog.assets.values.toSet())
          precacheImage(AssetImage(asset), imageContext),
      ]),
    );
    await tester.tap(find.widgetWithText(ChoiceChip, 'Built-in'));
    await capture(
      'full-icon-library-builtins',
      'Full icon library and offline built-ins',
    );
    await tester.enterText(
      find.byKey(const ValueKey('icon-library-search')),
      'chrome',
    );
    await capture('full-icon-library-search', 'Full searchable icon library');
    await tester.ensureVisible(
      find.byKey(const ValueKey('library-icon-chrome')),
    );
    await tester.tap(find.byKey(const ValueKey('library-icon-chrome')));
    await capture(
      'full-icon-library-preview',
      'Full icon preview and official source terms',
    );
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('icon-library-search')),
      'no-match-xyz',
    );
    await capture('full-icon-library-empty', 'Full icon library empty search');
    await tester.enterText(
      find.byKey(const ValueKey('icon-library-search')),
      '',
    );
    await tester.tap(find.widgetWithText(ChoiceChip, 'Online'));
    await capture(
      'full-icon-library-online',
      'Full registered online additions',
    );
    final extra = library.online.first;
    library.downloaded[extra.id] =
        await tester.runAsync(
          () => File(
            'packages/app_icon_catalog/png/${extra.id}.png',
          ).readAsBytes(),
        ) ??
        Uint8List(0);
    library.changed();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Downloaded'));
    await capture(
      'full-icon-library-downloaded',
      'Full downloaded icon available offline',
    );
    library.error =
        'The icon service is unavailable. Built-in and downloaded icons are still available.';
    library.changed();
    await capture('full-icon-library-error', 'Full icon service recovery');
    await tester.pumpWidget(
      screen(
        DiagnosticsConsentScreen(diagnostics: service, onContinue: () {}),
        boundary: boundary,
      ),
    );
    await capture(
      'full-error-consent',
      'Full independent error sharing choice',
    );
    await tester.pumpWidget(
      screen(ErrorLogScreen(diagnostics: service), boundary: boundary),
    );
    await capture('full-error-log-empty', 'Full empty local error log');
    service.record(DiagnosticCode.connectionTimeout);
    service.record(DiagnosticCode.iconDownloadFailed);
    await capture('full-error-log-list', 'Full sanitized local error log');
    await tester.tap(find.byType(ListTile).last);
    await capture(
      'full-error-log-detail',
      'Full fixed-category diagnostic details',
    );
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('error-log-clear')));
    await capture(
      'full-error-log-clear',
      'Full clear-local-errors confirmation',
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await service.setSharing(true);
    service.uploadError =
        'Sharing could not finish. Errors are kept on this device.';
    await capture(
      'full-error-sharing-failure',
      'Full sharing retry state',
      notes:
          'Deterministic unavailable-service state. Error sharing was enabled only in an in-memory test fixture; no upload endpoint exists.',
    );
    await shots.setViewport(const Size(1180, 820));
    await tester.pumpWidget(
      screen(
        const AppIconLibraryScreen(),
        library: library,
        boundary: boundary,
      ),
    );
    await capture('full-icon-library-ipad', 'Full iPad icon library');
  });
}
