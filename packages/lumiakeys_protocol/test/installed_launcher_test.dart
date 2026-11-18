import 'package:lumiakeys_protocol/lumiakeys_protocol.dart';
import 'package:test/test.dart';

String installedId(int index) =>
    'installed.${index.toRadixString(16).padLeft(32, '0')}';
RemoteApplication installed(int index) => RemoteApplication(
  id: installedId(index),
  name: 'Installed $index',
  icon: 'apps',
  executable: '/private/local/application-$index',
  layoutId: installedLaunchOnlyLayoutId,
  detected: true,
  launchOnly: true,
);
DesktopManifest fixture() => DesktopManifest.regularStarter().copyWith(
  layouts: [
    ...DesktopManifest.regularStarter().layouts,
    installedLaunchOnlyLayout,
  ],
  applications: [
    ...DesktopManifest.regularStarter().applications,
    ...List.generate(40, installed),
  ],
  launcherApplicationIds: List.generate(launcherSlotCount, installedId),
);
void main() {
  test(
    'old applications default to managed compatibility, new flag roundtrips',
    () {
      final old = DesktopManifest.starter().applications.first.toJson()
        ..remove('launchOnly');
      expect(RemoteApplication.fromJson(old).launchOnly, isFalse);
      final app = installed(1);
      expect(RemoteApplication.fromJson(app.toJson()).launchOnly, isTrue);
      expect(app.copyWith(name: 'Renamed').launchOnly, isTrue);
      expect(
        () => RemoteApplication.fromJson({...old, 'launchOnly': 'true'}),
        throwsFormatException,
      );
    },
  );
  test('dynamic IDs have exact opaque namespace', () {
    expect(isInstalledApplicationId(installedId(1)), isTrue);
    for (final id in [
      'installed.bad',
      'installed.${'A' * 32}',
      'installed.${'a' * 33}',
      '../app',
      'chrome',
    ]) {
      expect(isInstalledApplicationId(id), isFalse);
    }
  });
  test(
    'sync sends only twelve configured dynamic entries with no executable paths',
    () {
      final manifest = fixture();
      manifest.validate();
      final local = manifest.toJson();
      final wire = manifest.toJson(forSync: true);
      final apps = (wire['applications'] as List).cast<Map>();
      expect(apps.where((app) => app['launchOnly'] == true).length, 12);
      expect(
        apps
            .where((app) => app['launchOnly'] == true)
            .every((app) => app['executable'] == 'Desktop-managed'),
        isTrue,
      );
      expect(
        ((local['applications'] as List).last as Map)['executable'],
        '/private/local/application-39',
      );
      final decoded = DesktopManifest.fromJson(wire);
      expect(decoded.launcherApplicationIds, List.generate(12, installedId));
      final hidden = manifest
          .copyWith(settings: const RemoteSettings(enableAppsSync: false))
          .toJson(forSync: true);
      expect(hidden['applications'], isEmpty);
    },
  );
  test('duplicate identities and launch-only actions are rejected', () {
    final manifest = fixture();
    expect(
      () => manifest
          .copyWith(applications: [...manifest.applications, installed(0)])
          .validate(),
      throwsFormatException,
    );
    expect(
      () => manifest
          .copyWith(applications: [installed(0).copyWith(launchOnly: false)])
          .validate(),
      throwsFormatException,
    );
    expect(
      () => manifest
          .copyWith(applications: [installed(0).copyWith(layoutId: 'keyboard')])
          .validate(),
      throwsFormatException,
    );
    expect(
      () => manifest
          .copyWith(
            layouts: [
              ...manifest.layouts.where(
                (layout) => layout.id != installedLaunchOnlyLayoutId,
              ),
              installedLaunchOnlyLayout.copyWith(
                buttons: [manifest.buttonById('keyboard.copy')!],
              ),
            ],
          )
          .validate(),
      throwsFormatException,
    );
  });
  test(
    'actions accept exact identifier-only JSON including old nullable keys',
    () {
      final request = RemoteActionRequest.launchApplication(installedId(1));
      expect(
        RemoteActionRequest.fromJson(request.toJson()).applicationId,
        installedId(1),
      );
      for (final field in [
        'executable',
        'path',
        'args',
        'target',
        'locator',
        'launchOnly',
      ]) {
        expect(
          () => RemoteActionRequest.fromJson({
            ...request.toJson(),
            field: 'anything',
          }),
          throwsFormatException,
        );
      }
      for (final value in [
        123,
        {'id': 'chrome'},
        ['chrome'],
        'a\n',
        'a' * 257,
      ]) {
        expect(
          () => RemoteActionRequest.fromJson({
            ...request.toJson(),
            'applicationId': value,
          }),
          throwsFormatException,
        );
      }
      expect(
        () => RemoteActionRequest.fromJson({
          ...request.toJson(),
          'buttonId': 'keyboard.copy',
        }),
        throwsFormatException,
      );
    },
  );
}
