import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app_icon_validation.dart';
import 'builtin_icon_catalog.g.dart';
import 'icon_library.dart';

/// Canonical IDs accepted by the bundled catalog and same-origin download API.
abstract final class AppIconCatalog {
  static final ids = Set<String>.unmodifiable(
    builtinIconCatalog.map((entry) => entry.id),
  );

  static final assets = Map<String, String>.unmodifiable({
    for (final entry in builtinIconCatalog) entry.id: entry.assetPath,
    'codex': builtinIconById(legacyProtocolIconId('codex'))!.assetPath,
  });

  static final Map<String, Future<bool>> _bundledAvailability = {};
  static bool matchesBundled(String id, Uint8List bytes) {
    final item = builtinIconById(id);
    return item != null &&
        AppIconValidation.isValidPng(bytes) &&
        sha256.convert(bytes).toString() == item.sha256;
  }

  static Future<bool> hasBundledAsset(String appId) =>
      _bundledAvailability.putIfAbsent(appId, () async {
        final asset = assets[appId];
        if (asset == null) return false;
        try {
          return (await rootBundle.load(asset)).lengthInBytes > 0;
        } catch (_) {
          return false;
        }
      });
}

/// Small shared RAM cache for downloaded or CompanionServer-provided PNGs.
/// The caller owns durable storage; this cache deliberately resets on restart.
abstract final class AppIconCache {
  static final Map<String, Uint8List> _items = {};
  static Uint8List? get(String appId) {
    final bytes = _items[appId];
    return bytes == null ? null : Uint8List.fromList(bytes);
  }

  static void put(String appId, Uint8List bytes) {
    if (!AppIconCatalog.matchesBundled(appId, bytes)) {
      return;
    }
    _items[appId] = Uint8List.fromList(bytes);
  }

  static void clear() => _items.clear();
}

/// Downloads allowlisted icon IDs from a configured same-origin icon service.
/// No caller-supplied URL is accepted after the base origin is constructed.
class IconCatalogClient {
  IconCatalogClient({
    Uri? baseUri,
    String endpoint = const String.fromEnvironment('SMARTKEYS_ICON_URL'),
    HttpClient Function()? clientFactory,
    bool allowLoopbackHttp = false,
    this.timeout = const Duration(seconds: 8),
    this.maxResponseBytes = 64 * 1024,
  }) : _baseUri = _validateBase(baseUri, endpoint, allowLoopbackHttp),
       _clientFactory = clientFactory ?? HttpClient.new;

  final Uri? _baseUri;
  final HttpClient Function() _clientFactory;
  final Duration timeout;
  final int maxResponseBytes;

  bool get isConfigured => _baseUri != null;

  static Uri? _validateBase(
    Uri? baseUri,
    String endpoint,
    bool allowLoopbackHttp,
  ) {
    final uri =
        baseUri ??
        (endpoint.trim().isEmpty ? null : Uri.tryParse(endpoint.trim()));
    if (uri == null) return null;
    final loopback = {
      'localhost',
      '127.0.0.1',
      '::1',
      '[::1]',
    }.contains(uri.host);
    if (uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.query.isNotEmpty ||
        uri.fragment.isNotEmpty ||
        (uri.scheme != 'https' &&
            !(allowLoopbackHttp && loopback && uri.scheme == 'http'))) {
      throw ArgumentError(
        'Icon service endpoint must be HTTPS (loopback HTTP is for development only)',
      );
    }
    return uri.replace(path: uri.path.replaceFirst(RegExp(r'/$'), ''));
  }

  Future<Uint8List?> downloadByAppId(String appId) async {
    if (!AppIconCatalog.ids.contains(appId)) return null;
    final cached = AppIconCache.get(appId);
    if (cached != null) return Uint8List.fromList(cached);
    final base = _baseUri;
    if (base == null) return null;
    final uri = base.replace(
      path: '${base.path}/v1/icons/${Uri.encodeComponent(appId)}',
    );
    final client = _clientFactory();
    try {
      final request = await client.getUrl(uri).timeout(timeout);
      request.followRedirects = false;
      request.headers.set(HttpHeaders.acceptHeader, 'image/png');
      final response = await request.close().timeout(timeout);
      if (response.statusCode != HttpStatus.ok ||
          !((response.headers.contentType?.mimeType.toLowerCase() ?? '') ==
              'image/png')) {
        return null;
      }
      Future<Uint8List?> readImage() async {
        final builder = BytesBuilder(copy: false);
        await for (final chunk in response.timeout(timeout)) {
          if (builder.length + chunk.length > maxResponseBytes ||
              builder.length + chunk.length > AppIconValidation.maxBytes) {
            return null;
          }
          builder.add(chunk);
        }
        return builder.takeBytes();
      }

      final bytes = await readImage().timeout(timeout);
      if (bytes == null || !AppIconCatalog.matchesBundled(appId, bytes)) {
        return null;
      }
      AppIconCache.put(appId, bytes);
      return bytes;
    } on TimeoutException {
      return null;
    } on SocketException {
      return null;
    } on HttpException {
      return null;
    } on FormatException {
      return null;
    } finally {
      client.close(force: true);
    }
  }
}

/// Displays a native or downloaded PNG first, then the offline bundled icon,
/// and finally an accessible generic app mark.
class AppArtwork extends StatelessWidget {
  const AppArtwork({
    super.key,
    required this.appId,
    this.pngBytes,
    this.pngBase64,
    this.size = 40,
    this.semanticLabel,
  });

  final String appId;
  final Uint8List? pngBytes;
  final String? pngBase64;
  final double size;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    Uint8List? bytes = pngBytes;
    if (bytes == null && pngBase64 != null && pngBase64!.length <= 87384) {
      try {
        bytes = base64Decode(pngBase64!);
      } on FormatException {
        bytes = null;
      }
    }
    if (bytes != null && AppIconValidation.isValidPng(bytes)) {
      return Image.memory(
        bytes,
        width: size,
        height: size,
        fit: BoxFit.contain,
        semanticLabel: semanticLabel ?? '$appId app icon',
        filterQuality: FilterQuality.none,
        frameBuilder: (context, child, frame, synchronous) =>
            synchronous || frame != null ? child : _bundled(context),
        errorBuilder: (_, _, _) => _bundled(context),
      );
    }
    return _bundled(context);
  }

  Widget _bundled(BuildContext context) {
    final asset = AppIconCatalog.assets[appId];
    if (asset != null) {
      return Image.asset(
        asset,
        width: size,
        height: size,
        fit: BoxFit.contain,
        semanticLabel: semanticLabel ?? '$appId app icon',
        frameBuilder: (context, child, frame, synchronous) =>
            synchronous || frame != null ? child : _fallback(context),
        errorBuilder: (_, _, _) => _fallback(context),
      );
    }
    final library = IconLibraryScope.maybeOf(context);
    if (library != null && library.byId(appId) != null) {
      return FutureBuilder<Uint8List?>(
        key: ValueKey((library, appId, library.byId(appId)?.sha256)),
        future: library.loadCached(appId),
        builder: (_, snapshot) => snapshot.data == null
            ? _fallback(context)
            : Image.memory(
                snapshot.data!,
                width: size,
                height: size,
                fit: BoxFit.contain,
                semanticLabel: semanticLabel ?? '$appId app icon',
                errorBuilder: (_, _, _) => _fallback(context),
              ),
      );
    }
    return _fallback(context);
  }

  Widget _fallback(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: Tooltip(
      message: semanticLabel ?? appId,
      child: Icon(
        Icons.apps,
        size: size * .8,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
}
