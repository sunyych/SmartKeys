import 'package:lumiakeys_protocol/lumiakeys_protocol.dart';
import 'package:test/test.dart';

void main() {
  test('legacy absence and explicit empty slots remain distinguishable', () {
    final starter = DesktopManifest.regularStarter();
    final legacy = DesktopManifest.fromJson(
      starter.toJson()..remove('launcherApplicationIds'),
    );
    expect(legacy.hasLauncherConfiguration, isFalse);
    expect(
      legacy.launcherApplicationIds,
      List<String?>.filled(launcherSlotCount, null),
    );
    expect(legacy.copyWith(revision: 3).hasLauncherConfiguration, isFalse);
    final cleared = legacy.copyWith(
      launcherApplicationIds: List<String?>.filled(launcherSlotCount, null),
    );
    expect(cleared.hasLauncherConfiguration, isTrue);
    expect(
      DesktopManifest.fromJson(cleared.toJson()).hasLauncherConfiguration,
      isTrue,
    );
  });

  test(
    'old eight configured slots pad to twelve without changing their order',
    () {
      final json = DesktopManifest.starter().toJson()
        ..['launcherApplicationIds'] = [
          'chrome',
          null,
          'chatgpt',
          null,
          null,
          null,
          null,
          'vscode',
        ];
      final restored = DesktopManifest.fromJson(json);
      expect(restored.hasLauncherConfiguration, isTrue);
      expect(restored.launcherApplicationIds, [
        'chrome',
        null,
        'chatgpt',
        null,
        null,
        null,
        null,
        'vscode',
        null,
        null,
        null,
        null,
      ]);
      restored.validate();
    },
  );

  test('slot lengths, types and unknown references are rejected', () {
    final starter = DesktopManifest.starter();
    for (final slots in [
      <Object?>[],
      <Object?>['chrome'],
      List<Object?>.filled(13, null),
      [1, ...List<Object?>.filled(11, null)],
      ['', ...List<Object?>.filled(11, null)],
      ['unknown', ...List<Object?>.filled(11, null)],
    ]) {
      expect(
        () => DesktopManifest.fromJson(
          starter.toJson()..['launcherApplicationIds'] = slots,
        ),
        throwsFormatException,
      );
    }
    expect(
      () =>
          starter.copyWith(launcherApplicationIds: const ['chrome']).validate(),
      throwsFormatException,
    );
  });

  test('disabled app sync hides twelve slots and all referenced app data', () {
    final starter = DesktopManifest.regularStarter();
    final configured = starter.copyWith(
      launcherApplicationIds: ['chrome', ...List<String?>.filled(11, null)],
    );
    final hidden = configured.copyWith(
      settings: configured.settings.copyWith(enableAppsSync: false),
    );
    final wire = DesktopManifest.fromJson(hidden.toJson(forSync: true));
    expect(
      wire.launcherApplicationIds,
      List<String?>.filled(launcherSlotCount, null),
    );
    expect(wire.applications, isEmpty);
    expect(
      hidden.toJson()['launcherApplicationIds'],
      configured.launcherApplicationIds,
    );
  });
}
