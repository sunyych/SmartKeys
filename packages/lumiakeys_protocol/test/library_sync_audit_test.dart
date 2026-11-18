import 'package:lumiakeys_protocol/lumiakeys_protocol.dart';
import 'package:test/test.dart';

// Transport fixture only; registered PNG/hash verification belongs to the App
// bundle codec and image consumers, covered by Desktop and Full tests.
const tinyPng =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jGYoAAAAASUVORK5CYII=';
RemoteProfile libraryProfile() => RemoteProfile(
  id: 'library.audit',
  name: 'Local Word keys',
  layoutId: 'library.audit',
  platform: 'windows',
  sourceAppId: 'word',
  sourceIconId: 'word',
  sourceLibraryId: 'word.windowsLinux.default',
  sourceLibraryVersion: '1',
  sourceActionHashes: {'save': 'a' * 64},
  sourceIconPngBase64: tinyPng,
  sourceIconSha256: 'b' * 64,
);
DesktopManifest fixture() {
  final base = DesktopManifest.regularStarter();
  return base.copyWith(
    profiles: [...base.profiles, libraryProfile()],
    layouts: [
      ...base.layouts,
      const RemoteShortcutLayout(
        id: 'library.audit',
        name: 'Local Word keys',
        kind: RemoteLayoutKind.application,
        buttons: [],
      ),
    ],
    applications: [
      for (final app in base.applications)
        app.copyWith(detected: app.id == 'chrome'),
    ],
    sidebarItems: const [
      RemoteSidebarItem.profile('library.audit'),
      RemoteSidebarItem.application('chrome'),
      RemoteSidebarItem.application('chatgpt'),
    ],
  );
}

void main() {
  test(
    'syncIcons redacts embedded artwork and hash without removing profile source or private bytes',
    () {
      final original = fixture();
      expect(
        DesktopManifest.fromJson(
          original.toJson(forSync: true),
        ).profiles.last.sourceIconPngBase64,
        tinyPng,
      );
      final noIcons = original.copyWith(
        settings: original.settings.copyWith(syncIcons: false),
      );
      final wire = noIcons.toJson(forSync: true);
      final rows = wire['profiles'] as List;
      final source = rows.cast<Map>().singleWhere(
        (p) => p['id'] == 'library.audit',
      );
      expect(source.containsKey('sourceIconPngBase64'), false);
      expect(source.containsKey('sourceIconSha256'), false);
      final synced = DesktopManifest.fromJson(wire).profiles.last;
      expect(synced.sourceAppId, 'word');
      expect(synced.sourceIconId, 'word');
      expect(synced.sourceActionHashes, libraryProfile().sourceActionHashes);
      expect(noIcons.profiles.last.sourceIconPngBase64, tinyPng);
      expect(
        DesktopManifest.fromJson(
          noIcons.toJson(),
        ).profiles.last.sourceIconPngBase64,
        tinyPng,
      );
    },
  );
  test(
    'mixed profile and App sidebar sync removes unavailable references without changing saved order',
    () {
      final original = fixture();
      final synced = DesktopManifest.fromJson(original.toJson(forSync: true));
      expect(synced.sidebarItems!.map((i) => i.key), [
        'profile:library.audit',
        'application:chrome',
      ]);
      final noApps = original.copyWith(
        settings: original.settings.copyWith(enableAppsSync: false),
      );
      expect(
        DesktopManifest.fromJson(
          noApps.toJson(forSync: true),
        ).sidebarItems!.map((i) => i.key),
        ['profile:library.audit'],
      );
      expect(original.sidebarItems!.map((i) => i.key), [
        'profile:library.audit',
        'application:chrome',
        'application:chatgpt',
      ]);
    },
  );
}
