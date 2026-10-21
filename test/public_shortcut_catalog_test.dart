import 'package:flutter_test/flutter_test.dart';
import 'package:smart_keys/data/public_shortcut_catalog.dart';
import 'package:smart_keys/models/config.dart';

void main() {
  test('catalog has only the agreed 15 public categories', () {
    expect(publicShortcutLabels.keys, {
      'copy',
      'paste',
      'cut',
      'undo',
      'redo',
      'select_all',
      'save',
      'find',
      'new',
      'open',
      'print',
      'new_tab',
      'close_tab',
      'bold',
      'italic',
    });
  });

  test('recognizes only exact canonical command combinations', () {
    HidAction action(String key, List<String> modifiers, {String? value}) =>
        HidAction(
          type: ActionType.keyboard,
          keyCode: key,
          modifiers: modifiers,
          value: value,
        );
    expect(publicShortcutIdForAction(action('KEY_C', ['PRIMARY'])), 'copy');
    expect(publicShortcutIdForAction(action('KEY_I', ['LEFT_META'])), 'italic');
    expect(
      publicShortcutIdForAction(action('KEY_Z', ['PRIMARY', 'LEFT_SHIFT'])),
      'redo',
    );
    expect(
      publicShortcutIdForAction(action('KEY_T', ['RIGHT_CTRL'])),
      'new_tab',
    );
    expect(
      publicShortcutIdForAction(action('KEY_C', ['PRIMARY', 'LEFT_CTRL'])),
      isNull,
    );
    expect(
      publicShortcutIdForAction(action('KEY_C', ['PRIMARY', 'LEFT_ALT'])),
      isNull,
    );
    expect(
      publicShortcutIdForAction(action('KEY_C', ['PRIMARY'], value: 'custom')),
      isNull,
    );
    expect(
      publicShortcutIdForAction(
        HidAction(type: ActionType.companion, value: '{"kind":"x"}'),
      ),
      isNull,
    );
  });
}
