import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

const desktopInstallerCatalogAsset = 'assets/desktop_installers/catalog.json';
const desktopInstallerChannelName = 'smart_keys/desktop_installers';
const _destinationUriPreference = 'desktop_installers.destination_uri.v1';
const _destinationNamePreference = 'desktop_installers.destination_name.v1';
const _maxInstallerBytes = 512 * 1024 * 1024;

enum DesktopInstallerPlatform { windows, macos }

extension DesktopInstallerPlatformLabel on DesktopInstallerPlatform {
  String get label => switch (this) {
    DesktopInstallerPlatform.windows => 'Windows',
    DesktopInstallerPlatform.macos => 'macOS',
  };

  String fileNameFor(String version) => switch (this) {
    DesktopInstallerPlatform.windows => 'LumiaKey-Windows-v$version-Setup.exe',
    DesktopInstallerPlatform.macos => 'LumiaKey-macOS-v$version.dmg',
  };
}

class DesktopInstallerEntry {
  const DesktopInstallerEntry({
    required this.platform,
    required this.fileName,
    required this.assetPath,
    required this.sizeBytes,
    required this.sha256,
  });

  final DesktopInstallerPlatform platform;
  final String fileName;
  final String assetPath;
  final int sizeBytes;
  final String sha256;
}

class DesktopInstallerCatalog {
  const DesktopInstallerCatalog({
    required this.version,
    required this.commit,
    required this.installers,
  });

  final String version;
  final String commit;
  final List<DesktopInstallerEntry> installers;
}

class VerifiedDesktopInstaller {
  const VerifiedDesktopInstaller({
    required this.entry,
    required this.bytesVerified,
  });

  final DesktopInstallerEntry entry;
  final int bytesVerified;
}

class DesktopInstallerVerificationReceipt {
  const DesktopInstallerVerificationReceipt({
    required this.fileName,
    required this.bytesWritten,
    required this.sha256,
  });

  final String fileName;
  final int bytesWritten;
  final String sha256;
}

class DesktopInstallerDestination {
  const DesktopInstallerDestination({
    required this.treeUri,
    required this.displayName,
  });

  final String treeUri;
  final String displayName;
}

class DesktopInstallerExportReceipt {
  const DesktopInstallerExportReceipt({
    required this.fileName,
    required this.documentUri,
    required this.bytesWritten,
    required this.sha256,
  });

  final String fileName;
  final String documentUri;
  final int bytesWritten;
  final String sha256;
}

/// Native boundary for choosing and exporting to an explicitly selected local
/// Android Storage Access Framework folder. Implementations stream assets and
/// must verify size and SHA-256 before publishing a final document.
abstract interface class DesktopInstallerExportBridge {
  Future<DesktopInstallerDestination?> chooseExportDirectory();

  Future<DesktopInstallerVerificationReceipt> verifyInstaller({
    required DesktopInstallerEntry installer,
  });

  Future<DesktopInstallerExportReceipt> exportInstaller({
    required DesktopInstallerDestination destination,
    required DesktopInstallerEntry installer,
  });
}

class MethodChannelDesktopInstallerExportBridge
    implements DesktopInstallerExportBridge {
  MethodChannelDesktopInstallerExportBridge({
    this._channel = const MethodChannel(desktopInstallerChannelName),
  });

  final MethodChannel _channel;

  @override
  Future<DesktopInstallerDestination?> chooseExportDirectory() async {
    final value = await _channel.invokeMapMethod<Object?, Object?>(
      'chooseExportDirectory',
    );
    if (value == null) return null;
    final uri = value['treeUri']?.toString();
    final name = value['displayName']?.toString();
    if (uri == null || uri.isEmpty || name == null || name.isEmpty) {
      throw const FormatException('Android returned an invalid export folder.');
    }
    return DesktopInstallerDestination(treeUri: uri, displayName: name);
  }

  @override
  Future<DesktopInstallerVerificationReceipt> verifyInstaller({
    required DesktopInstallerEntry installer,
  }) async {
    final value = await _channel
        .invokeMapMethod<Object?, Object?>('verifyInstaller', {
          'assetPath': installer.assetPath,
          'fileName': installer.fileName,
          'sizeBytes': installer.sizeBytes,
          'sha256': installer.sha256,
        });
    if (value == null ||
        value['fileName'] != installer.fileName ||
        value['bytesWritten'] != installer.sizeBytes ||
        value['sha256'] != installer.sha256) {
      throw const FormatException(
        'Android returned an invalid verification receipt.',
      );
    }
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
    final value = await _channel
        .invokeMapMethod<Object?, Object?>('exportInstaller', {
          'treeUri': destination.treeUri,
          'assetPath': installer.assetPath,
          'fileName': installer.fileName,
          'sizeBytes': installer.sizeBytes,
          'sha256': installer.sha256,
        });
    if (value == null) {
      throw const FormatException('Android did not return an export receipt.');
    }
    final fileName = value['fileName']?.toString();
    final documentUri = value['documentUri']?.toString();
    final bytesWritten = value['bytesWritten'];
    final sha256 = value['sha256']?.toString();
    if (fileName == null ||
        documentUri == null ||
        bytesWritten is! int ||
        sha256 == null) {
      throw const FormatException(
        'Android returned an invalid export receipt.',
      );
    }
    return DesktopInstallerExportReceipt(
      fileName: fileName,
      documentUri: documentUri,
      bytesWritten: bytesWritten,
      sha256: sha256,
    );
  }
}

/// Reads release-pipeline metadata and asks Android to stream-verify the exact
/// APK asset. Development builds without a release catalog return null.
class DesktopInstallerService {
  DesktopInstallerService({
    AssetBundle? bundle,
    DesktopInstallerExportBridge? exportBridge,
    Future<SharedPreferences> Function()? preferencesProvider,
  }) : _bundle = bundle ?? rootBundle,
       _exportBridge =
           exportBridge ?? MethodChannelDesktopInstallerExportBridge(),
       _preferencesProvider =
           preferencesProvider ?? SharedPreferences.getInstance;

  final AssetBundle _bundle;
  final DesktopInstallerExportBridge _exportBridge;
  final Future<SharedPreferences> Function() _preferencesProvider;

  Future<DesktopInstallerCatalog?> loadCatalog() async {
    String source;
    try {
      source = await _bundle.loadString(desktopInstallerCatalogAsset);
    } on FlutterError {
      return null;
    }
    final decoded = jsonDecode(source);
    if (decoded is! Map<String, Object?> ||
        decoded['schemaVersion'] != 1 ||
        decoded['version'] is! String ||
        decoded['commit'] is! String ||
        decoded['installers'] is! List<Object?>) {
      throw const FormatException('Invalid desktop installer catalog.');
    }
    final version = decoded['version']! as String;
    final commit = decoded['commit']! as String;
    if (!RegExp(r'^\d+\.\d+\.\d+$').hasMatch(version) ||
        !RegExp(r'^[0-9a-f]{40}$').hasMatch(commit)) {
      throw const FormatException(
        'Invalid release version or commit in catalog.',
      );
    }
    final installers = (decoded['installers']! as List<Object?>)
        .map((value) => _parseEntry(value, version: version, commit: commit))
        .toList(growable: false);
    if (installers.length != DesktopInstallerPlatform.values.length ||
        installers.map((entry) => entry.platform).toSet().length !=
            DesktopInstallerPlatform.values.length) {
      throw const FormatException(
        'Catalog must contain exactly one Windows and one macOS installer.',
      );
    }
    return DesktopInstallerCatalog(
      version: version,
      commit: commit,
      installers: installers,
    );
  }

  DesktopInstallerEntry _parseEntry(
    Object? value, {
    required String version,
    required String commit,
  }) {
    if (value is! Map<String, Object?>) {
      throw const FormatException('Invalid installer entry.');
    }
    final platformName = value['platform'];
    final platform = switch (platformName) {
      'windows' => DesktopInstallerPlatform.windows,
      'macos' => DesktopInstallerPlatform.macos,
      _ => throw const FormatException('Unknown desktop installer platform.'),
    };
    final fileName = value['filename'];
    final assetPath = value['assetPath'];
    final sizeBytes = value['sizeBytes'];
    final digest = value['sha256'];
    final expectedName = platform.fileNameFor(version);
    final expectedPath =
        'assets/desktop_installers/releases/$version-${commit.substring(0, 12)}/$expectedName';
    if (fileName != expectedName ||
        assetPath != expectedPath ||
        sizeBytes is! int ||
        sizeBytes <= 0 ||
        sizeBytes > _maxInstallerBytes ||
        digest is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(digest)) {
      throw FormatException(
        'Invalid metadata for ${platform.label} installer.',
      );
    }
    return DesktopInstallerEntry(
      platform: platform,
      fileName: fileName! as String,
      assetPath: assetPath! as String,
      sizeBytes: sizeBytes,
      sha256: digest,
    );
  }

  Future<VerifiedDesktopInstaller> verify(DesktopInstallerEntry entry) async {
    final receipt = await _exportBridge.verifyInstaller(installer: entry);
    if (receipt.fileName != entry.fileName ||
        receipt.bytesWritten != entry.sizeBytes ||
        receipt.sha256 != entry.sha256) {
      throw FormatException(
        'Android verification failed for ${entry.fileName}.',
      );
    }
    return VerifiedDesktopInstaller(
      entry: entry,
      bytesVerified: receipt.bytesWritten,
    );
  }

  Future<DesktopInstallerDestination?> selectedDestination() async {
    final preferences = await _preferencesProvider();
    final uri = preferences.getString(_destinationUriPreference);
    final name = preferences.getString(_destinationNamePreference);
    if (uri == null || uri.isEmpty || name == null || name.isEmpty) return null;
    return DesktopInstallerDestination(treeUri: uri, displayName: name);
  }

  Future<DesktopInstallerDestination?> chooseExportDirectory() async {
    final destination = await _exportBridge.chooseExportDirectory();
    if (destination == null) return null;
    final parsed = Uri.tryParse(destination.treeUri);
    if (parsed == null ||
        parsed.scheme != 'content' ||
        parsed.host != 'com.android.externalstorage.documents' ||
        destination.displayName.trim().isEmpty) {
      throw const FormatException(
        'Choose a folder in local Android shared storage.',
      );
    }
    final preferences = await _preferencesProvider();
    await preferences.setString(_destinationUriPreference, destination.treeUri);
    await preferences.setString(
      _destinationNamePreference,
      destination.displayName,
    );
    return destination;
  }

  /// Delegates a verified, allowlisted asset identity to Android. The native
  /// side verifies the APK asset, reserves a new SAF document with [fileName],
  /// streams the bytes, then reopens and verifies the stored document. The
  /// destination may show the file while the UI reports that export is running.
  Future<DesktopInstallerExportReceipt> exportInstaller(
    DesktopInstallerCatalog catalog,
    DesktopInstallerEntry entry,
  ) async {
    if (!catalog.installers.contains(entry)) {
      throw ArgumentError(
        'Installer is not part of the loaded release catalog.',
      );
    }
    final destination = await selectedDestination();
    if (destination == null) {
      throw StateError('Choose a local export folder first.');
    }
    final receipt = await _exportBridge.exportInstaller(
      destination: destination,
      installer: entry,
    );
    final documentUri = Uri.tryParse(receipt.documentUri);
    if (receipt.fileName != entry.fileName ||
        receipt.bytesWritten != entry.sizeBytes ||
        receipt.sha256 != entry.sha256 ||
        documentUri?.scheme != 'content' ||
        documentUri?.host != 'com.android.externalstorage.documents') {
      throw FormatException(
        'Android export receipt failed verification for ${entry.fileName}.',
      );
    }
    return receipt;
  }
}
