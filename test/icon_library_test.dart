import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:smart_keys/icons/icon_library.dart';
import 'package:smart_keys/icons/builtin_icon_catalog.g.dart';

Uint8List png(int color) => Uint8List.fromList(
  image.encodePng(
    image.Image(width: 2, height: 2)..setPixelRgb(0, 0, color, 0, 0),
  ),
);
Map<String, Object?> entry(String id, Uint8List bytes) => {
  'app_id': id,
  'canonical_id': id,
  'name': id,
  'aliases': <String>[],
  'sha256': sha256.convert(bytes).toString(),
  'version': '1',
  'width': 2,
  'height': 2,
  'bundled': false,
  'available': true,
  'mime_type': 'image/png',
  'download_url': '/v1/icons/$id',
  'source': 'https://example.com/source.png',
  'source_page_url': 'https://example.com/app',
  'terms_url': 'https://example.com/terms',
};

void main() {
  late Directory directory;
  late HttpServer server;
  late IconLibrary library;
  late List<Map<String, Object?>> records;
  late Map<String, Uint8List> images;
  late List<String> requests;
  Future<void> Function(HttpRequest)? intercept;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('icon-library-');
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    records = [entry('extra', png(12))];
    images = {'extra': png(12)};
    requests = [];
    intercept = null;
    server.listen((request) async {
      requests.add(request.uri.path);
      if (intercept != null) {
        await intercept!(request);
        return;
      }
      if (request.uri.path.endsWith('/catalog')) {
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({'schema_version': 1, 'icons': records}),
        );
      } else {
        request.response.headers.contentType = ContentType('image', 'png');
        request.response.add(
          images[request.uri.path.split('/').last] ?? <int>[],
        );
      }
      await request.response.close();
    });
    library = IconLibrary(
      baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
      allowLoopbackHttp: true,
      directory: () async => directory,
    );
  });
  tearDown(() async {
    library.dispose();
    await server.close(force: true);
    await directory.delete(recursive: true);
  });

  test(
    'exactly 50 genuine built-ins are immediately offline, aliases exclude codex',
    () async {
      expect(library.entries, hasLength(50));
      expect(requests, isEmpty);
      expect(builtinIconCatalog.map((e) => e.sha256).toSet(), hasLength(50));
      expect(canonicalBuiltinIconId('codex'), isNull);
      expect(legacyProtocolIconId('codex'), 'chatgpt');
      await library.initialize();
      expect(requests, isEmpty);
      expect(await library.download('unregistered'), false);
      expect(requests, isEmpty);
    },
  );
  test(
    'actual canonical server catalog accepts all 60 including numeric IDs and downloads extra',
    () async {
      final wire =
          jsonDecode(
                await File(
                  'community_server/assets/app_icons/catalog.json',
                ).readAsString(),
              )
              as Map;
      final actual = [
        for (final raw in wire['icons'] as List)
          LibraryIcon.fromJson(Map<String, dynamic>.from(raw as Map)),
      ];
      expect(actual, hasLength(60));
      expect(actual.where((e) => e.bundled), hasLength(50));
      expect(actual.where((e) => !e.bundled), hasLength(10));
      final source =
          jsonDecode(
                await File(
                  'packages/app_icon_catalog/catalog.json',
                ).readAsString(),
              )
              as Map;
      records = [
        for (final raw in source['icons'] as List)
          {
            'app_id': raw['id'],
            'canonical_id': raw['id'],
            'name': raw['name'],
            'aliases': raw['aliases'],
            'sha256': raw['sha256'],
            'version': raw['version'],
            'width': raw['width'],
            'height': raw['height'],
            'bundled': raw['bundled'],
            'available': true,
            'mime_type': 'image/png',
            'download_url': '/v1/icons/${raw['id']}',
            'source': raw['sourceUrl'],
            'source_page_url': raw['sourcePageUrl'],
            'terms_url': raw['termsUrl'],
          },
      ];
      await library.refresh();
      expect(library.error, isNull);
      expect(library.entries, hasLength(60));
      expect(library.byId('1password'), isNotNull);
      expect(library.byId('7zip'), isNotNull);
      final extra =
          records.firstWhere((record) => record['bundled'] == false)['app_id']
              as String;
      expect(builtinIconById(extra), isNull);
      images[extra] = await File(
        'packages/app_icon_catalog/png/$extra.png',
      ).readAsBytes();
      expect(await library.download(extra), true);
      expect(library.cachedBytes(extra), images[extra]);
    },
  );
  test(
    'downloaded extra survives offline restart and hash update invalidates RAM/disk',
    () async {
      await library.refresh();
      expect(await library.download('extra'), true);
      final restart = IconLibrary(
        baseUri: library.baseUri,
        allowLoopbackHttp: true,
        directory: () async => directory,
      );
      await restart.initialize();
      expect(restart.isDownloaded('extra'), true);
      restart.dispose();
      final v2 = png(33);
      records = [entry('extra', v2)];
      await library.refresh();
      expect(library.cachedBytes('extra'), isNull);
      expect(await library.loadCached('extra'), isNull);
      images['extra'] = v2;
      expect(await library.download('extra'), true);
      expect(library.cachedBytes('extra'), v2);
    },
  );
  test('old in-flight download cannot overwrite refreshed hash', () async {
    await library.refresh();
    final requested = Completer<void>(), release = Completer<void>();
    final old = images['extra']!;
    final updated = png(82);
    intercept = (request) async {
      if (request.uri.path.endsWith('/catalog')) {
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'schema_version': 1,
            'icons': [entry('extra', updated)],
          }),
        );
      } else {
        requested.complete();
        await release.future;
        request.response.headers.contentType = ContentType('image', 'png');
        request.response.add(old);
      }
      await request.response.close();
    };
    final pending = library.download('extra');
    await requested.future;
    await library.refresh();
    release.complete();
    expect(await pending, false);
    expect(library.cachedBytes('extra'), isNull);
  });
  test(
    'bad hash/corrupt PNG and redirects fail safely without following origin',
    () async {
      await library.refresh();
      images['extra'] = png(99);
      expect(await library.download('extra'), false);
      expect(library.isDownloaded('extra'), false);
      images['extra'] = Uint8List.fromList([1, 2, 3]);
      expect(await library.download('extra'), false);
      intercept = (request) async {
        request.response.statusCode = 302;
        request.response.headers.set('location', 'http://127.0.0.1:1/private');
        await request.response.close();
      };
      await library.refresh();
      expect(library.error, isNotNull);
      expect(
        () => IconLibrary(baseUri: Uri.parse('http://192.168.1.1')),
        throwsArgumentError,
      );
    },
  );
  test('LRU limits disk and RAM exactly without prefix collisions', () async {
    library.dispose();
    library = IconLibrary(
      baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
      allowLoopbackHttp: true,
      directory: () async => directory,
      maxImages: 1,
    );
    records = [entry('foo', png(1)), entry('foo-bar', png(2))];
    images = {'foo': png(1), 'foo-bar': png(2)};
    await library.refresh();
    await library.download('foo');
    await library.download('foo-bar');
    expect(library.isDownloaded('foo'), false);
    expect(library.isDownloaded('foo-bar'), true);
    final files = await directory
        .list(recursive: true)
        .where((e) => e.path.endsWith('.png'))
        .toList();
    expect(files, hasLength(1));
    await (files.single as File).writeAsString('corrupt');
    final restart = IconLibrary(
      baseUri: library.baseUri,
      allowLoopbackHttp: true,
      directory: () async => directory,
      maxImages: 1,
    );
    await restart.initialize();
    expect(restart.isDownloaded('foo-bar'), false);
    restart.dispose();
  });
  test(
    'catalog refresh at a held persistence boundary cannot bypass disk cap',
    () async {
      library.dispose();
      Completer<Directory>? holdNext;
      final entered = Completer<void>();
      library = IconLibrary(
        baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
        allowLoopbackHttp: true,
        maxImages: 1,
        directory: () async {
          final gate = holdNext;
          if (gate != null) {
            holdNext = null;
            entered.complete();
            return gate.future;
          }
          return directory;
        },
      );
      final foo = png(1), old = png(2), updated = png(3);
      records = [entry('foo', foo), entry('extra', old)];
      images = {'foo': foo, 'extra': old};
      await library.refresh();
      expect(await library.download('foo'), true);
      final release = Completer<Directory>();
      holdNext = release;
      final pending = library.download('extra');
      await entered.future;
      records = [entry('foo', foo), entry('extra', updated)];
      await library.refresh();
      release.complete(directory);
      expect(await pending, false);
      final files = await directory
          .list(recursive: true)
          .where((file) => file.path.endsWith('.png'))
          .toList();
      expect(files, hasLength(1));
      expect(library.isDownloaded('foo'), true);
      expect(library.cachedBytes('extra'), isNull);
      expect(
        files.single.path,
        isNot(contains(sha256.convert(old).toString())),
      );
    },
  );
}
