import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lumiakeys_protocol/lumiakeys_protocol.dart';

import 'app_icon_validation.dart';

/// Canonical IDs accepted by the bundled catalog and same-origin download API.
abstract final class AppIconCatalog {
  static const ids = remoteApplicationIconAppIds;

  static const assets = <String, String>{
    'codex': 'assets/app_icons/openai.png',
    'chatgpt': 'assets/app_icons/openai.png',
    'claude': 'assets/app_icons/claude-app.png',
    'cursor': 'assets/app_icons/cursor.png',
    'chrome': 'assets/app_icons/chrome.png',
    'vscode': 'assets/app_icons/vscode.png',
    'photoshop': 'assets/app_icons/photoshop.png',
    'illustrator': 'assets/app_icons/illustrator.png',
    'premiere': 'assets/app_icons/premiere.png',
    'solidworks': 'assets/app_icons/solidworks-app.png',
    'edge': 'assets/app_icons/edge.png',
    'firefox': 'assets/app_icons/firefox.png',
    'safari': 'assets/app_icons/safari.png',
    'teams': 'assets/app_icons/teams.png',
    'zoom': 'assets/app_icons/zoom.png',
    'appleMusic': 'assets/app_icons/appleMusic.png',
    'finder': 'assets/app_icons/finder.png',
  };

  static final Map<String, Future<bool>> _bundledAvailability = {};
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
    if (!AppIconCatalog.ids.contains(appId) ||
        !AppIconValidation.isValidPng(bytes)) {
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
      if (bytes == null || !AppIconValidation.isValidPng(bytes)) return null;
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
