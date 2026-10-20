import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_keys/services/desktop_installer_service.dart';

const _version = '2.4.0';
const _commit = 'abcdef0123456789abcdef0123456789abcdef01';
const _treeUri =
    'content://com.android.externalstorage.documents/tree/primary%3ADownload';
const _fileBytes = <int>[0x53, 0x4b, 0x41, 0x50];
final _digest = sha256.convert(_fileBytes).toString();
const _windowsFile = 'LumiaKey-Windows-v$_version-Setup.exe';
const _macosFile = 'LumiaKey-macOS-v$_version.dmg';

String _asset(String fileName) =>
    'assets/desktop_installers/releases/$_version-${_commit.substring(0, 12)}/$fileName';

class _CatalogBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    if (key != desktopInstallerCatalogAsset) {
      throw FlutterError('Missing asset $key');
    }
    final manifest = {
      'schemaVersion': 1,
      'version': _version,
      'commit': _commit,
      'installers': [
        {
          'platform': 'windows',
          'filename': _windowsFile,
          'assetPath': _asset(_windowsFile),
          'sizeBytes': _fileBytes.length,
          'sha256': _digest,
        },
        {
          'platform': 'macos',
          'filename': _macosFile,
          'assetPath': _asset(_macosFile),
          'sizeBytes': _fileBytes.length,
          'sha256': _digest,
        },
      ],
    };
    return ByteData.sublistView(
      Uint8List.fromList(utf8.encode(jsonEncode(manifest))),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(desktopInstallerChannelName);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late MethodChannelDesktopInstallerExportBridge bridge;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    bridge = MethodChannelDesktopInstallerExportBridge(channel: channel);
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test(
    'forwards folder, streaming-verify, and export channel contracts',
    () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return switch (call.method) {
          'chooseExportDirectory' => {
            'treeUri': _treeUri,
            'displayName': 'Download',
          },
          'verifyInstaller' => {
            'fileName': _windowsFile,
            'bytesWritten': _fileBytes.length,
            'sha256': _digest,
          },
          'exportInstaller' => {
            'fileName': _windowsFile,
            'documentUri':
                'content://com.android.externalstorage.documents/document/primary%3ADownload%2F$_windowsFile',
            'bytesWritten': _fileBytes.length,
            'sha256': _digest,
          },
          _ => throw PlatformException(code: 'unexpected_method'),
        };
      });

      final destination = await bridge.chooseExportDirectory();
      expect(destination?.treeUri, _treeUri);
      expect(destination?.displayName, 'Download');

      final installer = DesktopInstallerEntry(
        platform: DesktopInstallerPlatform.windows,
        fileName: _windowsFile,
        assetPath: _asset(_windowsFile),
        sizeBytes: _fileBytes.length,
        sha256: _digest,
      );
      final verification = await bridge.verifyInstaller(installer: installer);
      expect(verification.bytesWritten, _fileBytes.length);
      expect(verification.sha256, _digest);

      final receipt = await bridge.exportInstaller(
        destination: destination!,
        installer: installer,
      );
      expect(receipt.fileName, _windowsFile);
      expect(receipt.documentUri, contains('/document/'));
      expect(calls.map((call) => call.method), [
        'chooseExportDirectory',
        'verifyInstaller',
        'exportInstaller',
      ]);
      expect(calls[0].arguments, isNull);
      expect(calls[1].arguments, {
        'assetPath': _asset(_windowsFile),
        'fileName': _windowsFile,
        'sizeBytes': _fileBytes.length,
        'sha256': _digest,
      });
      expect(calls[2].arguments, {
        'treeUri': _treeUri,
        'assetPath': _asset(_windowsFile),
        'fileName': _windowsFile,
        'sizeBytes': _fileBytes.length,
        'sha256': _digest,
      });
    },
  );

  test(
    'rejects malformed channel responses and mismatched service receipts',
    () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        return switch (call.method) {
          'chooseExportDirectory' => {'treeUri': _treeUri},
          'verifyInstaller' => {
            'fileName': _windowsFile,
            'bytesWritten': _fileBytes.length + 1,
            'sha256': _digest,
          },
          'exportInstaller' => {
            'fileName': _windowsFile,
            'bytesWritten': _fileBytes.length,
            'sha256': _digest,
          },
          _ => null,
        };
      });

      await expectLater(bridge.chooseExportDirectory(), throwsFormatException);
      final installer = DesktopInstallerEntry(
        platform: DesktopInstallerPlatform.windows,
        fileName: _windowsFile,
        assetPath: _asset(_windowsFile),
        sizeBytes: _fileBytes.length,
        sha256: _digest,
      );
      await expectLater(
        bridge.verifyInstaller(installer: installer),
        throwsFormatException,
      );
      await expectLater(
        bridge.exportInstaller(
          destination: const DesktopInstallerDestination(
            treeUri: _treeUri,
            displayName: 'Download',
          ),
          installer: installer,
        ),
        throwsFormatException,
      );

      SharedPreferences.setMockInitialValues({
        'desktop_installers.destination_uri.v1': _treeUri,
        'desktop_installers.destination_name.v1': 'Download',
      });
      final service = DesktopInstallerService(
        bundle: _CatalogBundle(),
        exportBridge: bridge,
      );
      final catalog = (await service.loadCatalog())!;
      await expectLater(
        service.exportInstaller(catalog, catalog.installers.first),
        throwsFormatException,
      );
    },
  );
}
