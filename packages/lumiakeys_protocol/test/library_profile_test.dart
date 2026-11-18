import 'package:test/test.dart';
import 'package:lumiakeys_protocol/lumiakeys_protocol.dart';

void main() {
  test(
    'old profile encoding and optional complete source metadata roundtrip',
    () {
      const old = RemoteProfile(id: 'old', name: 'Old', layoutId: 'keyboard');
      expect(RemoteProfile.fromJson(old.toJson()).isLibraryProfile, false);
      expect(old.toJson().containsKey('sourceAppId'), false);
      final source = RemoteProfile(
        id: 'library.1',
        name: 'Chrome',
        layoutId: 'library.1',
        platform: 'windows',
        sourceAppId: 'chrome',
        sourceIconId: 'chrome',
        sourceLibraryId: 'chrome.windowsLinux',
        sourceLibraryVersion: '1',
        sourceActionHashes: {'copy': 'a' * 64},
      );
      expect(RemoteProfile.fromJson(source.toJson()).toJson(), source.toJson());
      final manifest = DesktopManifest.regularStarter();
      final withSource = manifest.copyWith(
        profiles: [...manifest.profiles, source],
        layouts: [
          ...manifest.layouts,
          const RemoteShortcutLayout(
            id: 'library.1',
            name: 'Chrome',
            kind: RemoteLayoutKind.application,
            buttons: [],
          ),
        ],
      );
      expect(
        DesktopManifest.fromJson(
          withSource.toJson(forSync: true),
        ).profiles.last.sourceIconId,
        'chrome',
      );
    },
  );
  test('partial invalid hash and wrong source types are rejected', () {
    final old = const RemoteProfile(
      id: 'old',
      name: 'Old',
      layoutId: 'keyboard',
    ).toJson();
    for (final extra in [
      {'sourceAppId': 'chrome'},
      {
        'sourceActionHashes': {'copy': 'not-a-hash'},
      },
      {'sourceAppId': 42},
      {'sourceIconPngBase64': 'bad'},
    ]) {
      expect(
        () => RemoteProfile.fromJson({...old, ...extra}),
        throwsFormatException,
      );
    }
  });
}
