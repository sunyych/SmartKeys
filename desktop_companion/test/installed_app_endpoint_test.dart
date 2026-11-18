import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:lumiakeys_protocol/lumiakeys_protocol.dart';
import 'package:lumiakeys_companion/companion_server.dart';
import 'package:lumiakeys_companion/desktop_actions.dart';
import 'package:lumiakeys_companion/desktop_controller.dart';
import 'package:lumiakeys_companion/installed_app_registry.dart';

class _Discovery implements ApplicationDiscovery {
  @override
  Future<List<RemoteApplication>> refresh(List<RemoteApplication> apps) async =>
      apps.map((app) => app.copyWith(detected: true)).toList();
}

class _Actions extends DesktopActions {
  _Actions() : super(platformOverride: TargetPlatform.windows);
  final launched = <String>[];
  int icons = 0;
  @override
  Future<void> activateInstalledApplication(String id) async {
    launched.add(id);
  }

  @override
  Future<Uint8List?> getApplicationIcon(RemoteApplication app) async {
    icons++;
    return Uint8List.fromList(img.encodePng(img.Image(width: 2, height: 2)));
  }
}

void main() {
  test(
    'HTTP accepts only selected live IDs, keeps launch-only capability separate, and gates registered icons',
    () async {
      final targets = List.generate(
        2,
        (i) => InstalledLaunchTarget.discovered(
          name: 'OS App $i',
          kind: InstalledLaunchKind.windowsAppId,
          identity: 'App$i!Main',
          locator: 'App$i!Main',
        ),
      );
      final registry = InstalledAppRegistry(
        discover: () async => targets,
        validate: (_) async => true,
      );
      final actions = _Actions();
      final controller = DesktopController(
        store: MemoryDesktopConfigStore(),
        discovery: _Discovery(),
        actions: actions,
        installedRegistry: registry,
      );
      await controller.initialize();
      addTearDown(controller.dispose);
      await controller.assignLauncherApp(0, targets.first.id);
      final server = CompanionServer(
        controller: controller,
        discoveryPort: 45857,
      );
      await server.start();
      addTearDown(server.dispose);
      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      Future<(int, String, Map<String, List<String>>)> request(
        String path, {
        Map<String, Object?>? body,
        String? raw,
        bool authenticated = true,
        Map<String, String> headers = const {},
      }) async {
        final req = await client.openUrl(
          body != null || raw != null ? 'POST' : 'GET',
          Uri.parse('http://127.0.0.1:${server.actionPort}$path'),
        );
        if (authenticated) req.headers.set('x-lumiakeys-token', server.token);
        headers.forEach(req.headers.set);
        if (body != null || raw != null) {
          req.headers.contentType = ContentType.json;
          req.write(raw ?? jsonEncode(body));
        }
        final result = await req.close();
        final data = await result.fold<List<int>>(
          [],
          (all, chunk) => all..addAll(chunk),
        );
        final captured = <String, List<String>>{};
        result.headers.forEach((name, values) => captured[name] = values);
        return (
          result.statusCode,
          utf8.decode(data, allowMalformed: true),
          captured,
        );
      }

      final info = await request('/info');
      expect(
        (jsonDecode(info.$2) as Map)['capabilities'],
        contains('installed-launcher-v1'),
      );
      final before = controller.manifest.applicationActivationSequence;
      final id = targets.first.id;
      expect(
        (await request(
          '/action',
          body: RemoteActionRequest.launchApplication(id).toJson(),
        )).$1,
        200,
      );
      expect(actions.launched, [id]);
      expect(controller.manifest.applicationActivationSequence, before);
      expect(controller.manifest.applicationById(id)!.foreground, isFalse);
      for (final extra in ['executable', 'locator', 'path', 'args', 'target']) {
        expect(
          (await request(
            '/action',
            body: {
              ...RemoteActionRequest.launchApplication(id).toJson(),
              extra: 'private/command',
            },
          )).$1,
          400,
        );
      }
      expect(
        (await request(
          '/action',
          body: RemoteActionRequest.launchApplication(targets.last.id).toJson(),
        )).$1,
        400,
      );
      expect(
        (await request(
          '/action',
          body: {'kind': 'launch', 'target': '/private/path.exe'},
        )).$1,
        400,
      );
      expect((await request('/action', raw: 'x' * 16385)).$1, 413);
      expect(actions.launched, [id]);
      expect((await request('/icons/$id', authenticated: false)).$1, 403);
      expect((await request('/icons/${targets.last.id}')).$1, 404);
      expect(actions.icons, 0);
      final icon = await request('/icons/$id');
      expect(icon.$1, 200);
      expect(icon.$3['content-type']!.single, 'image/png');
      expect(actions.icons, 1);
      final etag = icon.$3['etag']!.single;
      expect(
        (await request('/icons/$id', headers: {'if-none-match': etag})).$1,
        304,
      );
      await controller.updateSettings(
        controller.manifest.settings.copyWith(syncIcons: false),
      );
      expect((await request('/icons/$id')).$1, 404);
    },
  );
}
