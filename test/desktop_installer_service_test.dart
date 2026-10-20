import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_keys/services/desktop_installer_service.dart';
import 'package:smart_keys/ui/desktop_installers_screen.dart';

const _version = '1.2.3';
const _commit = '0123456789abcdef0123456789abcdef01234567';
const _bytes = <int>[1, 2, 3, 4, 5];
final _digest = sha256.convert(_bytes).toString();

String _path(String fileName) =>
    'assets/desktop_installers/releases/$_version-${_commit.substring(0, 12)}/$fileName';

String _fileName(DesktopInstallerPlatform platform) =>
    platform.fileNameFor(_version);

Map<String, Object?> _catalog({
  String? version,
  String? commit,
  int? windowsSize,
  String? windowsDigest,
  String? windowsPath,
  String windowsFileName = 'LumiaKey-Windows-v1.2.3-Setup.exe',
  String macosPlatform = 'macos',
}) => {
  'schemaVersion': 1,
  'version': version ?? _version,
  'commit': commit ?? _commit,
  'installers': [
    {
      'platform': 'windows',
      'filename': windowsFileName,
      'assetPath':
          windowsPath ?? _path(_fileName(DesktopInstallerPlatform.windows)),
      'sizeBytes': windowsSize ?? _bytes.length,
      'sha256': windowsDigest ?? _digest,
    },
    {
      'platform': macosPlatform,
      'filename': _fileName(DesktopInstallerPlatform.macos),
      'assetPath': _path(_fileName(DesktopInstallerPlatform.macos)),
      'sizeBytes': _bytes.length,
      'sha256': _digest,
    },
  ],
};

class _MemoryBundle extends CachingAssetBundle {
  _MemoryBundle({required this.catalog});

  final Map<String, Object?>? catalog;

  @override
  Future<ByteData> load(String key) async {
    if (key == desktopInstallerCatalogAsset && catalog != null) {
      final bytes = utf8.encode(jsonEncode(catalog));
      return ByteData.sublistView(Uint8List.fromList(bytes));
    }
    throw FlutterError('Missing asset $key');
  }
}

class _FakeBridge implements DesktopInstallerExportBridge {
  DesktopInstallerDestination?
  nextDestination = const DesktopInstallerDestination(
    treeUri:
        'content://com.android.externalstorage.documents/tree/primary%3ADownload',
    displayName: 'Download',
  );
  DesktopInstallerDestination? exportedDestination;
  DesktopInstallerEntry? exportedInstaller;
  DesktopInstallerExportReceipt? receipt;

  @override
  Future<DesktopInstallerDestination?> chooseExportDirectory() async =>
      nextDestination;

  @override
  Future<DesktopInstallerVerificationReceipt> verifyInstaller({
    required DesktopInstallerEntry installer,
  }) async {
    final actualHash = sha256.convert(_bytes).toString();
    if (_bytes.length != installer.sizeBytes ||
        actualHash != installer.sha256) {
      throw const FormatException('Fake native streaming verification failed.');
    }
    return DesktopInstallerVerificationReceipt(
      fileName: installer.fileName,
      bytesWritten: _bytes.length,
      sha256: actualHash,
    );
  }

  @override
  Future<DesktopInstallerExportReceipt> exportInstaller({
    required DesktopInstallerDestination destination,
    required DesktopInstallerEntry installer,
  }) async {
    exportedDestination = destination;
    exportedInstaller = installer;
    return receipt ??
        DesktopInstallerExportReceipt(
          fileName: installer.fileName,
          documentUri:
              'content://com.android.externalstorage.documents/document/primary%3ADownload%2F${installer.fileName}',
          bytesWritten: installer.sizeBytes,
          sha256: installer.sha256,
        );
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('development build without catalog reports unavailable', () async {
    final service = DesktopInstallerService(
      bundle: _MemoryBundle(catalog: null),
      exportBridge: _FakeBridge(),
    );
    expect(await service.loadCatalog(), isNull);
  });

  test('parses release catalog and verifies exact APK asset bytes', () async {
    final service = DesktopInstallerService(
      bundle: _MemoryBundle(catalog: _catalog()),
      exportBridge: _FakeBridge(),
    );
    final catalog = await service.loadCatalog();
    expect(catalog, isNotNull);
    expect(
      catalog!.installers.map((entry) => entry.platform),
      containsAll(DesktopInstallerPlatform.values),
    );
    final verified = await service.verify(catalog.installers.first);
    expect(verified.bytesVerified, _bytes.length);
  });

  test('rejects malformed or ambiguous catalog metadata', () async {
    Future<void> rejects(Map<String, Object?> data) async {
      final service = DesktopInstallerService(
        bundle: _MemoryBundle(catalog: data),
        exportBridge: _FakeBridge(),
      );
      await expectLater(service.loadCatalog(), throwsFormatException);
    }

    await rejects(_catalog(version: '../1.2.3'));
    await rejects(_catalog(commit: 'not-a-commit'));
    await rejects(_catalog(windowsFileName: '../Setup.exe'));
    await rejects(_catalog(windowsPath: 'assets/other/Setup.exe'));
    await rejects(_catalog(windowsSize: 0));
    await rejects(_catalog(windowsSize: 512 * 1024 * 1024 + 1));
    await rejects(_catalog(windowsDigest: 'bad'));
    await rejects(_catalog(macosPlatform: 'windows'));
  });

  test('detects size and hash corruption in bundled installers', () async {
    final wrongSize = DesktopInstallerService(
      bundle: _MemoryBundle(catalog: _catalog(windowsSize: _bytes.length + 1)),
      exportBridge: _FakeBridge(),
    );
    final sizeCatalog = await wrongSize.loadCatalog();
    await expectLater(
      wrongSize.verify(sizeCatalog!.installers.first),
      throwsFormatException,
    );

    final wrongHash = DesktopInstallerService(
      bundle: _MemoryBundle(catalog: _catalog(windowsDigest: '0' * 64)),
      exportBridge: _FakeBridge(),
    );
    final hashCatalog = await wrongHash.loadCatalog();
    await expectLater(
      wrongHash.verify(hashCatalog!.installers.first),
      throwsFormatException,
    );
  });

  test(
    'persists only a local SAF destination and exports catalog entries',
    () async {
      final bridge = _FakeBridge();
      final service = DesktopInstallerService(
        bundle: _MemoryBundle(catalog: _catalog()),
        exportBridge: bridge,
      );
      final catalog = (await service.loadCatalog())!;
      await expectLater(
        service.exportInstaller(catalog, catalog.installers.first),
        throwsStateError,
      );

      final destination = await service.chooseExportDirectory();
      expect(destination?.displayName, 'Download');
      expect(
        (await service.selectedDestination())?.treeUri,
        destination!.treeUri,
      );
      final receipt = await service.exportInstaller(
        catalog,
        catalog.installers.first,
      );
      expect(receipt.fileName, catalog.installers.first.fileName);
      expect(bridge.exportedDestination?.treeUri, destination.treeUri);
      expect(bridge.exportedInstaller, catalog.installers.first);

      bridge.nextDestination = const DesktopInstallerDestination(
        treeUri: 'content://drive.google.com/tree/remote-folder',
        displayName: 'Cloud drive',
      );
      await expectLater(service.chooseExportDirectory(), throwsFormatException);
    },
  );

  testWidgets('installer screen explains missing development bundle', (
    tester,
  ) async {
    final service = DesktopInstallerService(
      bundle: _MemoryBundle(catalog: null),
      exportBridge: _FakeBridge(),
    );
    await tester.pumpWidget(
      MaterialApp(home: DesktopInstallersScreen(service: service)),
    );
    await tester.pumpAndSettle();
    expect(find.text('No desktop installers are bundled'), findsOneWidget);
    expect(find.textContaining('development build'), findsOneWidget);
  });

  testWidgets('installer screen selects folder, verifies and exports', (
    tester,
  ) async {
    final bridge = _FakeBridge();
    final service = DesktopInstallerService(
      bundle: _MemoryBundle(catalog: _catalog()),
      exportBridge: bridge,
    );
    await tester.pumpWidget(
      MaterialApp(home: DesktopInstallersScreen(service: service)),
    );
    await tester.pumpAndSettle();
    final exportButton = find.byKey(const ValueKey('export-installer-windows'));
    expect(tester.widget<FilledButton>(exportButton).onPressed, isNull);

    await tester.tap(
      find.byKey(const ValueKey('choose-installer-destination')),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Selected folder: Download'), findsOneWidget);
    expect(tester.widget<FilledButton>(exportButton).onPressed, isNotNull);

    bridge.nextDestination = null;
    await tester.tap(
      find.byKey(const ValueKey('choose-installer-destination')),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Selected folder: Download'), findsOneWidget);
    expect(tester.widget<FilledButton>(exportButton).onPressed, isNotNull);
    bridge.nextDestination = const DesktopInstallerDestination(
      treeUri:
          'content://com.android.externalstorage.documents/tree/primary%3ADownload',
      displayName: 'Download',
    );

    await tester.ensureVisible(
      find.byKey(const ValueKey('verify-installer-windows')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('verify-installer-windows')));
    await tester.pumpAndSettle();
    expect(find.text('Verified on this phone'), findsOneWidget);

    await tester.ensureVisible(exportButton);
    await tester.pumpAndSettle();
    await tester.tap(exportButton);
    await tester.pumpAndSettle();
    expect(find.textContaining('Exported LumiaKey-Windows'), findsOneWidget);
    expect(
      bridge.exportedInstaller?.platform,
      DesktopInstallerPlatform.windows,
    );
  });
}
