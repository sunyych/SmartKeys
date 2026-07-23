import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_keys/data/shortcut_usage_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('usage counters persist only in their private phone storage key', () async {
    SharedPreferences.setMockInitialValues({});
    final repository = SharedPreferencesShortcutUsageRepository();
    await repository.load();
    await repository.record('local:general:copy', 'General · Copy');
    await repository.record('local:general:copy', 'General · Copy');

    final restored = SharedPreferencesShortcutUsageRepository();
    await restored.load();
    final preferences = await SharedPreferences.getInstance();

    expect(restored.countFor('local:general:copy'), 2);
    expect(preferences.getKeys(), {
      SharedPreferencesShortcutUsageRepository.storageKey,
    });

    await restored.clear();
    expect(restored.records, isEmpty);
    expect(preferences.getKeys(), isEmpty);
  });
}
