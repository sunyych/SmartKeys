import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as paths;
import 'package:path_provider/path_provider.dart';

import 'app_icon_validation.dart';
import 'builtin_icon_catalog.g.dart';

class LibraryIcon {
  const LibraryIcon({
    required this.id,
    required this.name,
    required this.aliases,
    required this.sha256,
    required this.version,
    required this.width,
    required this.height,
    required this.bundled,
    required this.available,
    required this.sourceUrl,
    required this.sourcePageUrl,
    required this.termsUrl,
    this.assetPath,
  });
  final String id, name, sha256, version, sourceUrl, sourcePageUrl, termsUrl;
  final List<String> aliases;
  final int width, height;
  final bool bundled, available;
  final String? assetPath;

  factory LibraryIcon.builtin(BuiltinIconEntry entry) => LibraryIcon(
    id: entry.id,
    name: entry.name,
    aliases: entry.aliases,
    sha256: entry.sha256,
    version: entry.version,
    width: entry.width,
    height: entry.height,
    bundled: true,
    available: true,
    sourceUrl: entry.sourceUrl,
    sourcePageUrl: entry.sourcePageUrl,
    termsUrl: entry.termsUrl,
    assetPath: entry.assetPath,
  );

  static bool validId(String value) =>
      RegExp(r'^[A-Za-z0-9_-]{1,64}$').hasMatch(value);
  factory LibraryIcon.fromJson(Map<String, dynamic> value) {
    String text(String field, [int max = 256]) {
      final text = value[field];
      if (text is! String ||
          text.isEmpty ||
          text.length > max ||
          text.codeUnits.any((unit) => unit < 32)) {
        throw const FormatException('Invalid icon catalog entry');
      }
      return text;
    }

    final id = text('app_id', 64);
    final canonical = value['canonical_id'] ?? id;
    final hash = text('sha256', 64);
    final aliases = value['aliases'];
    final width = value['width'], height = value['height'];
    if (!validId(id) ||
        canonical != id ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(hash) ||
        aliases is! List ||
        aliases.length > 32 ||
        aliases.any((alias) => alias is! String || !validId(alias)) ||
        width is! int ||
        height is! int ||
        width < 1 ||
        height < 1 ||
        width > 512 ||
        height > 512 ||
        value['mime_type'] != 'image/png' ||
        value['available'] is! bool ||
        value['bundled'] is! bool ||
        value['download_url'] != '/v1/icons/$id') {
      throw const FormatException('Invalid icon catalog entry');
    }
    final source = text('source', 2048);
    final sourcePage = value['source_page_url'] is String
        ? text('source_page_url', 2048)
        : source;
    final terms = text('terms_url', 2048);
    for (final url in [sourcePage, terms]) {
      final uri = Uri.tryParse(url);
      if (uri == null ||
          uri.scheme != 'https' ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty) {
        throw const FormatException('Invalid icon information link');
      }
    }
    return LibraryIcon(
      id: id,
      name: text('name', 100),
      aliases: List<String>.unmodifiable(aliases.cast<String>()),
      sha256: hash,
      version: text('version', 64),
      width: width,
      height: height,
      bundled: value['bundled'] as bool,
      available: value['available'] as bool,
      sourceUrl: source,
      sourcePageUrl: sourcePage,
      termsUrl: terms,
    );
  }

  Map<String, Object?> toJson() => {
    'app_id': id,
    'canonical_id': id,
    'name': name,
    'aliases': aliases,
    'sha256': sha256,
    'version': version,
    'width': width,
    'height': height,
    'bundled': bundled,
    'available': available,
    'mime_type': 'image/png',
    'download_url': '/v1/icons/$id',
    'source': sourceUrl,
    'source_page_url': sourcePageUrl,
    'terms_url': termsUrl,
  };

  bool matches(String query) {
    final search = query.trim().toLowerCase();
    return search.isEmpty ||
        [
          id,
          name,
          ...aliases,
        ].any((value) => value.toLowerCase().contains(search));
  }
}

class IconLibrary extends ChangeNotifier {
  IconLibrary({
    Uri? baseUri,
    String endpoint = const String.fromEnvironment('SMARTKEYS_ICON_URL'),
    Future<Directory> Function()? directory,
    HttpClient Function()? clientFactory,
    this.onFailure,
    bool allowLoopbackHttp = false,
    this.timeout = const Duration(seconds: 8),
    this.maxImages = 100,
    this.maxCacheBytes = 8 * 1024 * 1024,
  }) : _directoryProvider = directory ?? getApplicationSupportDirectory,
       _clientFactory = clientFactory ?? HttpClient.new,
       baseUri = _validateOrigin(baseUri, endpoint, allowLoopbackHttp);

  static Uri? _validateOrigin(Uri? uri, String endpoint, bool loopback) {
    uri ??= endpoint.isEmpty ? null : Uri.tryParse(endpoint);
    if (uri == null) return null;
    if (uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.query.isNotEmpty ||
        uri.fragment.isNotEmpty ||
        (uri.scheme != 'https' &&
            !(loopback &&
                uri.scheme == 'http' &&
                ['localhost', '127.0.0.1', '::1'].contains(uri.host)))) {
      throw ArgumentError(
        'The icon library requires a configured HTTPS origin',
      );
    }
    return uri.replace(path: uri.path.replaceFirst(RegExp(r'/$'), ''));
  }

  final Uri? baseUri;
  final Future<Directory> Function() _directoryProvider;
  final HttpClient Function() _clientFactory;
  final VoidCallback? onFailure;
  final Duration timeout;
  final int maxImages, maxCacheBytes;
  final Map<String, LibraryIcon> _online = {};
  final Map<String, Uint8List> _cached = {};
  final Map<String, Future<Uint8List?>> _loads = {};
  final Set<String> _downloading = {};
  bool loading = false, _disposed = false;
  Future<void>? _initializing;
  String? error;
  Future<void> _diskTail = Future.value();

  bool get configured => baseUri != null;
  bool isDownloading(String id) => _downloading.contains(id);
  bool isDownloaded(String id) => _cached.containsKey(id);
  List<LibraryIcon> get entries {
    final result = {
      for (final item in builtinIconCatalog) item.id: LibraryIcon.builtin(item),
      for (final item in _online.values)
        if (builtinIconById(item.id) == null) item.id: item,
    };
    return List<LibraryIcon>.unmodifiable(result.values);
  }

  LibraryIcon? byId(String id) {
    final bundled = builtinIconById(id);
    return bundled != null ? LibraryIcon.builtin(bundled) : _online[id];
  }

  Uint8List? cachedBytes(String id) =>
      _cached[id] == null ? null : Uint8List.fromList(_cached[id]!);

  Future<Directory> _cacheDirectory() async {
    final root = await _directoryProvider();
    final key = sha256
        .convert(utf8.encode(baseUri?.toString() ?? 'offline'))
        .toString();
    return Directory(paths.join(root.path, 'icon_library', key));
  }

  Future<void> initialize() => _initializing ??= _initialize();

  Future<void> _initialize() async {
    try {
      final directory = await _cacheDirectory();
      final file = File(paths.join(directory.path, 'catalog.json'));
      if (await file.exists() && await file.length() <= 1024 * 1024) {
        _replaceCatalog(jsonDecode(await file.readAsString()));
      }
      await _trimCache(directory);
      final remaining = await directory.exists()
          ? await directory
                .list()
                .where((entry) => entry is File && entry.path.endsWith('.png'))
                .toList()
          : <FileSystemEntity>[];
      final names = remaining.map((file) => paths.basename(file.path)).toSet();
      for (final item
          in _online.values
              .where((item) => names.contains('${item.id}-${item.sha256}.png'))
              .take(maxImages)) {
        await loadCached(item.id);
      }
    } catch (_) {
      /* A missing or corrupt cache must leave all built-ins usable. */
    }
    _notify();
  }

  void _replaceCatalog(Object? decoded) {
    if (decoded is! Map ||
        decoded['schema_version'] != 1 ||
        decoded['icons'] is! List ||
        (decoded['icons'] as List).length > 1000) {
      throw const FormatException('Invalid icon catalog');
    }
    final records = <String, LibraryIcon>{};
    for (final item in decoded['icons'] as List) {
      if (item is! Map) throw const FormatException('Invalid icon catalog');
      final entry = LibraryIcon.fromJson(Map<String, dynamic>.from(item));
      if (records.containsKey(entry.id)) {
        throw const FormatException('Duplicate icon ID');
      }
      records[entry.id] = entry;
    }
    _cached.removeWhere((id, _) => records[id]?.sha256 != _online[id]?.sha256);
    _online
      ..clear()
      ..addAll(records);
  }

  Future<Uint8List> _get(String path, String mime, int maxBytes) async {
    final origin = baseUri;
    if (origin == null) {
      throw const HttpException('Icon service is not configured');
    }
    final client = _clientFactory();
    try {
      final request = await client
          .getUrl(origin.replace(path: '${origin.path}$path'))
          .timeout(timeout);
      request.followRedirects = false;
      request.headers.set(HttpHeaders.acceptHeader, mime);
      final response = await request.close().timeout(timeout);
      if (response.statusCode != 200 ||
          response.headers.contentType?.mimeType != mime) {
        throw const HttpException('Icon service response was unavailable');
      }
      Future<Uint8List> read() async {
        final result = BytesBuilder(copy: false);
        await for (final chunk in response) {
          if (result.length + chunk.length > maxBytes) {
            throw const FormatException('Icon response is too large');
          }
          result.add(chunk);
        }
        return result.takeBytes();
      }

      return await read().timeout(timeout);
    } finally {
      client.close(force: true);
    }
  }

  Future<void> refresh() async {
    if (loading) return;
    loading = true;
    error = null;
    _notify();
    try {
      await initialize();
      final bytes = await _get(
        '/v1/icons/catalog',
        'application/json',
        1024 * 1024,
      );
      _replaceCatalog(jsonDecode(utf8.decode(bytes)));
      final directory = await _cacheDirectory();
      await _write(File(paths.join(directory.path, 'catalog.json')), bytes);
    } catch (_) {
      error = configured
          ? 'The icon service is unavailable. Built-in and downloaded icons are still available.'
          : 'Online icons are not configured. All built-in icons work offline.';
      _fail();
    } finally {
      loading = false;
      _notify();
    }
  }

  Future<Uint8List?> loadCached(String id) {
    if (_cached[id] case final bytes?) {
      return Future.value(Uint8List.fromList(bytes));
    }
    final item = _online[id];
    if (item == null) return Future.value(null);
    final key = '$id:${item.sha256}';
    return _loads.putIfAbsent(key, () async {
      try {
        final directory = await _cacheDirectory();
        final file = File(
          paths.join(directory.path, '${item.id}-${item.sha256}.png'),
        );
        if (!await file.exists() ||
            await file.length() > AppIconValidation.maxBytes) {
          return null;
        }
        final bytes = await file.readAsBytes();
        if (!_validImage(item, bytes)) {
          await file.delete();
          return null;
        }
        if (_online[id]?.sha256 != item.sha256) return null;
        _cached[id] = bytes;
        await file.setLastModified(DateTime.now());
        return Uint8List.fromList(bytes);
      } catch (_) {
        return null;
      } finally {
        _loads.remove(key);
      }
    });
  }

  static bool _validImage(LibraryIcon item, Uint8List bytes) =>
      AppIconValidation.isValidPng(bytes) &&
      sha256.convert(bytes).toString() == item.sha256 &&
      ByteData.sublistView(bytes).getUint32(16) == item.width &&
      ByteData.sublistView(bytes).getUint32(20) == item.height;

  Future<bool> download(String id) async {
    final item = _online[id];
    if (item == null ||
        !item.available ||
        !LibraryIcon.validId(id) ||
        _downloading.contains(id) ||
        _downloading.length >= 3) {
      return false;
    }
    _downloading.add(id);
    error = null;
    _notify();
    try {
      final bytes = await _get(
        '/v1/icons/${Uri.encodeComponent(id)}',
        'image/png',
        AppIconValidation.maxBytes,
      );
      if (!_validImage(item, bytes)) {
        throw const FormatException('Invalid icon image');
      }
      if (_online[id]?.sha256 != item.sha256) return false;
      final directory = await _cacheDirectory();
      final destination = File(
        paths.join(directory.path, '${item.id}-${item.sha256}.png'),
      );
      await _write(destination, bytes);
      final finalize = _diskTail.then((_) async {
        if (_online[id]?.sha256 != item.sha256) {
          // The registry can change while the disk write is awaiting I/O.
          // Discard exactly these stale bytes and still enforce the disk cap.
          if (await destination.exists()) await destination.delete();
        } else {
          _cached[id] = bytes;
        }
        await _trimCache(directory);
      });
      _diskTail = finalize.catchError((Object _) {});
      await finalize;
      return _online[id]?.sha256 == item.sha256 && _cached.containsKey(id);
    } catch (_) {
      error =
          'This icon could not be downloaded. Try again when the service is available.';
      _fail();
      return false;
    } finally {
      _downloading.remove(id);
      _notify();
    }
  }

  Future<void> _write(File destination, List<int> bytes) {
    final operation = _diskTail.then((_) async {
      await destination.parent.create(recursive: true);
      final temporary = File('${destination.path}.next');
      try {
        await temporary.writeAsBytes(bytes, flush: true);
        await temporary.rename(destination.path);
      } finally {
        if (await temporary.exists()) await temporary.delete();
      }
    });
    _diskTail = operation.catchError((Object _) {});
    return operation;
  }

  Future<void> _trimCache(Directory directory) async {
    if (!await directory.exists()) return;
    final files = await directory
        .list()
        .where((entry) => entry is File && entry.path.endsWith('.png'))
        .cast<File>()
        .toList();
    final stats = <({File file, FileStat stat})>[];
    for (final file in files) {
      stats.add((file: file, stat: await file.stat()));
    }
    stats.sort((a, b) => a.stat.modified.compareTo(b.stat.modified));
    var total = stats.fold<int>(0, (sum, entry) => sum + entry.stat.size);
    while (stats.length > maxImages || total > maxCacheBytes) {
      final oldest = stats.removeAt(0);
      total -= oldest.stat.size;
      await oldest.file.delete();
      _cached.removeWhere(
        (id, _) =>
            paths.basename(oldest.file.path) ==
            '$id-${_online[id]?.sha256}.png',
      );
    }
  }

  void _fail() {
    try {
      onFailure?.call();
    } catch (_) {}
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class IconLibraryScope extends InheritedNotifier<IconLibrary> {
  const IconLibraryScope({
    super.key,
    required IconLibrary library,
    required super.child,
  }) : super(notifier: library);
  static IconLibrary? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<IconLibraryScope>()?.notifier;
}
