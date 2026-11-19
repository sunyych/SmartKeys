import 'package:test/test.dart';
import 'package:lumiakeys_protocol/lumiakeys_protocol.dart';

void main() {
  test(
    'legacy absence defaults and explicit empty sidebar remain distinct',
    () {
      final old = DesktopManifest.regularStarter();
      expect(old.sidebarItems, isNull);
      expect(old.toJson().containsKey('sidebarItems'), false);
      expect(old.defaultSidebarItems.take(2).map((i) => i.id), [
        'chatgpt',
        'chrome',
      ]);
      final empty = old.copyWith(sidebarItems: const []);
      expect(DesktopManifest.fromJson(empty.toJson()).sidebarItems, isEmpty);
      expect(empty.copyWith(revision: 9).sidebarItems, isEmpty);
      expect(
        empty.copyWith(clearSidebarConfiguration: true).sidebarItems,
        isNull,
      );
    },
  );
  test(
    'ordered typed refs roundtrip and sync gating does not erase local selection',
    () {
      final base = DesktopManifest.regularStarter().copyWith(
        sidebarItems: const [
          RemoteSidebarItem.application('chrome'),
          RemoteSidebarItem.application('chatgpt'),
        ],
      );
      expect(
        DesktopManifest.fromJson(base.toJson()).sidebarItems!.map((i) => i.id),
        ['chrome', 'chatgpt'],
      );
      final hidden = base.copyWith(
        settings: base.settings.copyWith(enableAppsSync: false),
      );
      expect(
        DesktopManifest.fromJson(hidden.toJson(forSync: true)).sidebarItems,
        isEmpty,
      );
      expect(hidden.sidebarItems, hasLength(2));
    },
  );
  test('App Bar launch settings roundtrip separately from ordered items', () {
    const setting = 'sidebarShortcutOnlyApplicationIds';
    final legacy = DesktopManifest.regularStarter();
    expect(
      DesktopManifest.fromJson(
        legacy.toJson(),
      ).sidebarShortcutOnlyApplicationIds,
      isEmpty,
    );
    expect(legacy.toJson(), isNot(contains(setting)));

    final configured = legacy.copyWith(
      applications: [
        for (final app in legacy.applications)
          app.copyWith(detected: {'chrome', 'chatgpt'}.contains(app.id)),
      ],
      sidebarItems: const [RemoteSidebarItem.application('chrome')],
      sidebarShortcutOnlyApplicationIds: const {'chrome', 'chatgpt'},
    );
    final saved = configured.toJson();
    expect(saved['sidebarItems'], [
      {'kind': 'application', 'id': 'chrome'},
    ]);
    expect(DesktopManifest.fromJson(saved).sidebarShortcutOnlyApplicationIds, {
      'chrome',
      'chatgpt',
    });
    expect(
      DesktopManifest.fromJson(
        configured.toJson(forSync: true),
      ).sidebarShortcutOnlyApplicationIds,
      {'chrome'},
    );
    expect(
      configured.copyWith(clearSidebarConfiguration: true).toJson(),
      isNot(contains(setting)),
    );
    for (final invalid in [
      'chrome',
      [42],
      ['chrome', 'chrome'],
      ['missing'],
    ]) {
      expect(
        () => DesktopManifest.fromJson({...saved, setting: invalid}),
        throwsFormatException,
      );
    }
  });
  test('malformed duplicate unknown and launch-only refs fail closed', () {
    final old = DesktopManifest.regularStarter();
    for (final raw in [
      null,
      {},
      [
        {'kind': 'unknown', 'id': 'chrome'},
      ],
      [
        {'kind': 'application', 'id': 'missing'},
      ],
      [
        {'kind': 'application', 'id': 'chrome'},
        {'kind': 'application', 'id': 'chrome'},
      ],
      List.filled(101, {'kind': 'application', 'id': 'chrome'}),
    ]) {
      expect(
        () => DesktopManifest.fromJson({...old.toJson(), 'sidebarItems': raw}),
        throwsFormatException,
      );
    }
    const app = RemoteApplication(
      id: 'installed.0123456789abcdef0123456789abcdef',
      name: 'Untrusted',
      icon: 'apps',
      executable: 'Desktop-managed',
      layoutId: installedLaunchOnlyLayoutId,
      launchOnly: true,
    );
    final dynamic = old.copyWith(
      applications: [...old.applications, app],
      layouts: [...old.layouts, installedLaunchOnlyLayout],
      sidebarItems: [RemoteSidebarItem.application(app.id)],
    );
    expect(dynamic.validate, throwsFormatException);
  });
}
