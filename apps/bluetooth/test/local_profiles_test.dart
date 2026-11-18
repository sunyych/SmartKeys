import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lumiakey_bluetooth_lite/local_profiles.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'fresh install supplies three independent editable local profiles',
    () async {
      final profiles = await const SharedPreferencesProfileStore().load();
      expect(profiles.map((profile) => profile.name), [
        'General',
        'ChatGPT',
        'Chrome',
      ]);
      expect(
        profiles.every((profile) => profile.shortcuts.length == 12),
        isTrue,
      );
      for (final profile in profiles) {
        for (final shortcut in profile.shortcuts) {
          expect(
            LocalShortcut.fromJson(shortcut.toJson()).toHidAction(),
            shortcut.toHidAction(),
          );
        }
      }
    },
  );

  test('legacy user shortcuts remain intact as a Custom profile', () async {
    final legacy = jsonEncode([
      const LocalShortcut(
        title: 'My key',
        keyCode: 'F8',
        modifiers: ['LEFT_ALT'],
      ).toJson(),
    ]);
    SharedPreferences.setMockInitialValues({
      SharedPreferencesProfileStore.legacyStorageKey: legacy,
    });
    const store = SharedPreferencesProfileStore();
    final profiles = await store.load();
    expect(profiles.last.name, 'Custom');
    expect(profiles.last.shortcuts.single.keyCode, 'F8');
    await store.save(profiles);
    final reloaded = await store.load();
    expect(reloaded.last.shortcuts.single.title, 'My key');
    expect(
      (await SharedPreferences.getInstance()).getString(
        SharedPreferencesProfileStore.legacyStorageKey,
      ),
      legacy,
    );
  });

  test(
    'corrupt saved data reports an error without rewriting preferences',
    () async {
      SharedPreferences.setMockInitialValues({
        SharedPreferencesProfileStore.storageKey: 'broken',
      });
      await expectLater(
        const SharedPreferencesProfileStore().load(),
        throwsFormatException,
      );
      expect(
        (await SharedPreferences.getInstance()).getString(
          SharedPreferencesProfileStore.storageKey,
        ),
        'broken',
      );
    },
  );
}
