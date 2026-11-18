import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:lumiakeys_protocol/lumiakeys_protocol.dart';
import 'package:lumiakeys_companion/desktop_controller.dart';
import 'package:lumiakeys_companion/desktop_actions.dart';
import 'package:lumiakeys_companion/companion_server.dart';

class _Discovery implements ApplicationDiscovery {
  @override
  Future<List<RemoteApplication>> refresh(List<RemoteApplication> apps) async =>
      apps.map((app) => app.copyWith(detected: true)).toList();
}

class _Icons extends DesktopActions {
  _Icons() : super(platformOverride: TargetPlatform.windows);
  Uint8List? icon = Uint8List.fromList(
    img.encodePng(img.Image(width: 2, height: 2)),
  );
  bool fail = false;
  int calls = 0;
  @override
  Future<Uint8List?> getApplicationIcon(RemoteApplication app) async {
    calls++;
    if (fail) throw StateError('Optional icon failure');
    return icon;
  }
}

void main() {
  Future<
    ({
      CompanionServer server,
      DesktopController controller,
      _Icons icons,
      HttpClient client,
    })
  >
  fixture() async {
    final icons = _Icons();
    final controller = DesktopController(
      store: MemoryDesktopConfigStore(),
      discovery: _Discovery(),
      actions: icons,
    );
    await controller.initialize();
    addTearDown(controller.dispose);
    final server = CompanionServer(
      controller: controller,
      discoveryPort: 45849,
    );
    await server.start();
    addTearDown(server.dispose);
    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    return (
      server: server,
      controller: controller,
      icons: icons,
      client: client,
    );
  }

  Future<HttpClientResponse> get(
    ({
      CompanionServer server,
      DesktopController controller,
      _Icons icons,
      HttpClient client,
    })
    f,
    String path, {
    bool authorize = true,
    String? etag,
  }) async {
    final request = await f.client.get(
      InternetAddress.loopbackIPv4.address,
      f.server.actionPort!,
      path,
    );
    if (authorize) request.headers.set('x-lumiakeys-token', f.server.token);
    if (etag != null) request.headers.set(HttpHeaders.ifNoneMatchHeader, etag);
    return request.close();
  }

  test(
    'icon endpoint authenticates, validates registered IDs and revalidates with ETag',
    () async {
      final f = await fixture();
      final forbidden = await get(f, '/icons/chrome', authorize: false);
      expect(forbidden.statusCode, HttpStatus.forbidden);
      await forbidden.drain<void>();
      expect(f.icons.calls, 0);
      final unknown = await get(f, '/icons/unknown');
      expect(unknown.statusCode, HttpStatus.notFound);
      await unknown.drain<void>();
      expect(f.icons.calls, 0);
      final first = await get(f, '/icons/chrome');
      expect(first.statusCode, HttpStatus.ok);
      expect(first.headers.contentType!.mimeType, 'image/png');
      final etag = first.headers.value(HttpHeaders.etagHeader);
      expect(etag, isNotNull);
      await first.drain<void>();
      final cached = await get(f, '/icons/chrome', etag: etag);
      expect(cached.statusCode, HttpStatus.notModified);
      expect(
        await cached.fold<int>(0, (count, bytes) => count + bytes.length),
        0,
      );
      await f.controller.updateSettings(
        f.controller.manifest.settings.copyWith(syncIcons: false),
      );
      final disabled = await get(f, '/icons/chrome', etag: etag);
      expect(disabled.statusCode, HttpStatus.notFound);
      await disabled.drain<void>();
    },
  );
  test(
    'malformed native data and extraction errors cannot break the manifest endpoint',
    () async {
      final f = await fixture();
      f.icons.icon = Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]);
      final malformed = await get(f, '/icons/chrome');
      expect(malformed.statusCode, HttpStatus.notFound);
      await malformed.drain<void>();
      f.icons.fail = true;
      final failed = await get(f, '/icons/chrome');
      expect(failed.statusCode, HttpStatus.notFound);
      await failed.drain<void>();
      final manifest = await get(f, '/manifest');
      expect(manifest.statusCode, HttpStatus.ok);
      await manifest.drain<void>();
      await f.controller.updateSettings(
        f.controller.manifest.settings.copyWith(enableAppsSync: false),
      );
      final hidden = await get(f, '/icons/chrome');
      expect(hidden.statusCode, HttpStatus.notFound);
      await hidden.drain<void>();
    },
  );
}
