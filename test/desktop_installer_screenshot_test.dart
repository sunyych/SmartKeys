import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_keys/app.dart';
import 'package:smart_keys/services/desktop_installer_service.dart';
import 'package:smart_keys/ui/desktop_installers_screen.dart';

import 'screenshot_support.dart';
import 'test_support.dart';

const _version = '4.2.1';
const _commit = 'a123456789abcdef0123456789abcdef01234567';
const _fixtureBytes = <int>[0x4c, 0x55, 0x4d, 0x49, 0x41, 0x4b, 0x45, 0x59];
const _folderUri =
    'content://com.android.externalstorage.documents/tree/primary%3ADownload';
const _windowsFile = 'LumiaKey-Windows-v$_version-Setup.exe';
final _digest = sha256.convert(_fixtureBytes).toString();

String _installerPath(DesktopInstallerPlatform platform) =>
    'assets/desktop_installers/releases/$_version-${_commit.substring(0, 12)}/${platform.fileNameFor(_version)}';

Map<String, Object?> _fixtureCatalog() => {
  'schemaVersion': 1,
  'version': _version,
  'commit': _commit,
  'installers': [
    for (final platform in DesktopInstallerPlatform.values)
      {
        'platform': platform.name,
        'filename': platform.fileNameFor(_version),
        'assetPath': _installerPath(platform),
        'sizeBytes': _fixtureBytes.length,
        'sha256': _digest,
      },
  ],
};

class _ScreenshotBundle extends CachingAssetBundle {
  _ScreenshotBundle({required this.includeCatalog});

  final bool includeCatalog;

  @override
  Future<ByteData> load(String key) async {
    if (includeCatalog && key == desktopInstallerCatalogAsset) {
      return ByteData.sublistView(
        Uint8List.fromList(utf8.encode(jsonEncode(_fixtureCatalog()))),
      );
    }
    throw FlutterError('Missing fixture asset $key');
  }
}

class _ScreenshotExportBridge implements DesktopInstallerExportBridge {
  bool failVerification = false;
  bool failExport = false;
  Completer<DesktopInstallerExportReceipt>? pendingExport;

  @override
  Future<DesktopInstallerDestination?> chooseExportDirectory() async =>
      const DesktopInstallerDestination(
        treeUri: _folderUri,
        displayName: 'Download',
      );

  @override
  Future<DesktopInstallerVerificationReceipt> verifyInstaller({
    required DesktopInstallerEntry installer,
  }) async {
    if (failVerification) throw StateError('Fixture verification failure');
    return DesktopInstallerVerificationReceipt(
      fileName: installer.fileName,
      bytesWritten: installer.sizeBytes,
      sha256: installer.sha256,
    );
  }

  @override
  Future<DesktopInstallerExportReceipt> exportInstaller({
    required DesktopInstallerDestination destination,
    required DesktopInstallerEntry installer,
  }) async {
    if (failExport) throw StateError('Fixture export failure');
    final pending = pendingExport;
    if (pending != null) return pending.future;
    return DesktopInstallerExportReceipt(
      fileName: installer.fileName,
      documentUri:
          'content://com.android.externalstorage.documents/document/primary%3ADownload%2F${installer.fileName}',
      bytesWritten: installer.sizeBytes,
      sha256: installer.sha256,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(ScreenshotSupport.prepareFonts);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('desktop installer states render to screenshot gallery', (
    tester,
  ) async {
    final shots = ScreenshotSupport(tester);
    final harness = await TestHarness.create();
    addTearDown(() async {
      await shots.unmount();
      shots.resetViewport();
      await harness.dispose();
    });

    final key = GlobalKey();
    var mountSequence = 0;
    await shots.setViewport(const Size(390, 844));

    Future<void> mount({
      required bool includeCatalog,
      required _ScreenshotExportBridge bridge,
    }) async {
      final service = DesktopInstallerService(
        bundle: _ScreenshotBundle(includeCatalog: includeCatalog),
        exportBridge: bridge,
      );
      await tester.pumpWidget(
        _app(
          harness,
          key,
          DesktopInstallersScreen(
            key: ValueKey('installer-screen-${mountSequence++}'),
            service: service,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }

    await mount(includeCatalog: false, bridge: _ScreenshotExportBridge());
    expect(find.text('No desktop installers are bundled'), findsOneWidget);
    await shots.capture(
      id: 'phone-installer-catalog-missing',
      title: 'Desktop installers · development build unavailable',
      orientation: 'portrait',
      notes:
          'Missing release catalog state; the page clearly reports packages unavailable.',
      boundaryKey: key,
    );

    final bridge = _ScreenshotExportBridge();
    expect(
      await DesktopInstallerService(
        bundle: _ScreenshotBundle(includeCatalog: true),
        exportBridge: bridge,
      ).loadCatalog(),
      isNotNull,
    );
    await mount(includeCatalog: true, bridge: bridge);
    expect(find.text('Release v$_version'), findsOneWidget);
    expect(find.text('Windows installer'), findsOneWidget);
    await shots.capture(
      id: 'phone-installer-release-top',
      title: 'Desktop installers · release and Windows package',
      orientation: 'portrait',
      notes:
          'Top of the real installer page, including release metadata, local export guidance, and Windows package. Uses deterministic metadata fixtures.',
      boundaryKey: key,
    );

    final windowsVerify = find.byKey(
      const ValueKey('verify-installer-windows'),
    );
    await tester.ensureVisible(windowsVerify);
    await tester.pumpAndSettle();
    expect(find.text('LumiaKey-Windows-v$_version-Setup.exe'), findsOneWidget);
    await shots.capture(
      id: 'phone-installer-windows-card',
      title: 'Desktop installers · Windows package controls',
      orientation: 'portrait',
      notes:
          'Windows installer name, size, digest, verify, and export controls.',
      boundaryKey: key,
    );

    final macosVerify = find.byKey(const ValueKey('verify-installer-macos'));
    await tester.ensureVisible(macosVerify);
    await tester.pumpAndSettle();
    expect(find.text('LumiaKey-macOS-v$_version.dmg'), findsOneWidget);
    await shots.capture(
      id: 'phone-installer-macos-bottom',
      title: 'Desktop installers · macOS package at page bottom',
      orientation: 'portrait',
      notes: 'Scrolled to the macOS package card and its explicit actions.',
      boundaryKey: key,
    );

    await tester.ensureVisible(windowsVerify);
    await tester.pumpAndSettle();
    bridge.failVerification = true;
    await tester.tap(windowsVerify);
    await tester.pumpAndSettle();
    expect(find.textContaining('Verification failed:'), findsOneWidget);
    await shots.capture(
      id: 'phone-installer-verification-error',
      title: 'Desktop installers · verification error',
      orientation: 'portrait',
      notes:
          'Injected native streaming verification failure surfaced beside the Windows package.',
      boundaryKey: key,
    );

    bridge.failVerification = false;
    bridge.failExport = true;
    await tester.ensureVisible(
      find.byKey(const ValueKey('choose-installer-destination')),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const ValueKey('choose-installer-destination')),
          )
          .onPressed,
      isNotNull,
    );
    await tester.tap(
      find.byKey(const ValueKey('choose-installer-destination')),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('export-installer-windows')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('export-installer-windows')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Installer export failed:'), findsOneWidget);
    await shots.capture(
      id: 'phone-installer-export-error',
      title: 'Desktop installers · export error',
      orientation: 'portrait',
      notes:
          'Injected SAF export failure shown to the user; no real file is written.',
      boundaryKey: key,
    );

    bridge.failExport = false;
    bridge.pendingExport = Completer<DesktopInstallerExportReceipt>();
    await tester.ensureVisible(
      find.byKey(const ValueKey('export-installer-windows')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('export-installer-windows')));
    await tester.pump();
    await tester.ensureVisible(
      find.byKey(const ValueKey('choose-installer-destination')),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const ValueKey('choose-installer-destination')),
          )
          .onPressed,
      isNull,
      reason: 'Folder permissions must not change while an export is running.',
    );
    bridge.pendingExport!.complete(
      DesktopInstallerExportReceipt(
        fileName: _windowsFile,
        documentUri:
            'content://com.android.externalstorage.documents/document/primary%3ADownload%2F$_windowsFile',
        bytesWritten: _fixtureBytes.length,
        sha256: _digest,
      ),
    );
    bridge.pendingExport = null;
    await tester.pumpAndSettle();
    expect(find.text('Verified on this phone'), findsOneWidget);

    tester
        .state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger))
        .clearSnackBars();
    await tester.pumpAndSettle();
    await shots.setViewport(const Size(320, 720));
    await mount(includeCatalog: true, bridge: bridge);
    expect(find.text('Desktop installers'), findsOneWidget);
    expect(
      tester.takeException(),
      isNull,
      reason: 'Narrow portrait layout must not overflow.',
    );
    await shots.capture(
      id: 'phone-installer-narrow-portrait',
      title: 'Desktop installers · narrow portrait layout',
      orientation: 'portrait',
      notes:
          'Narrow 320×720 logical-pixel Flutter viewport; fixture metadata only.',
      boundaryKey: key,
    );
  });
}

Widget _app(TestHarness harness, GlobalKey boundaryKey, Widget page) =>
    screenshotBoundary(
      boundaryKey,
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          fontFamilyFallback: ScreenshotSupport.fontFamilyFallback,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF67E8F9),
            brightness: Brightness.dark,
            surface: const Color(0xFF10151D),
          ),
          scaffoldBackgroundColor: const Color(0xFF090D12),
          useMaterial3: true,
        ),
        home: SmartKeysScope(controller: harness.controller, child: page),
      ),
    );
