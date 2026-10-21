import '../models/config.dart';

const publicShortcutLabels = <String, String>{
  'copy': 'Copy',
  'paste': 'Paste',
  'cut': 'Cut',
  'undo': 'Undo',
  'redo': 'Redo',
  'select_all': 'Select all',
  'save': 'Save',
  'find': 'Find',
  'new': 'New',
  'open': 'Open',
  'print': 'Print',
  'new_tab': 'New tab',
  'close_tab': 'Close tab',
  'bold': 'Bold',
  'italic': 'Italic',
};

String? publicShortcutIdForAction(HidAction action) {
  if (action.type != ActionType.keyboard ||
      action.value != null && action.value!.isNotEmpty) {
    return null;
  }
  final keyCode = action.keyCode?.toUpperCase();
  if (keyCode == null || !RegExp(r'^KEY_[A-Z]$').hasMatch(keyCode)) {
    return null;
  }
  final modifiers = <String>{};
  for (final raw in action.modifiers) {
    final modifier = raw.toUpperCase();
    if (!const {
      'PRIMARY',
      'LEFT_CTRL',
      'RIGHT_CTRL',
      'LEFT_META',
      'RIGHT_META',
      'SHIFT',
      'LEFT_SHIFT',
      'RIGHT_SHIFT',
    }.contains(modifier)) {
      return null;
    }
    if (!modifiers.add(modifier)) return null;
  }
  final primaryModifiers = modifiers
      .where(
        const {
          'PRIMARY',
          'LEFT_CTRL',
          'RIGHT_CTRL',
          'LEFT_META',
          'RIGHT_META',
        }.contains,
      )
      .toList();
  if (primaryModifiers.length != 1) return null;
  final shifts = modifiers
      .where(const {'SHIFT', 'LEFT_SHIFT', 'RIGHT_SHIFT'}.contains)
      .toList();
  if (shifts.length > 1) return null;
  final shift = shifts.isNotEmpty;
  const direct = <String, String>{
    'KEY_C': 'copy',
    'KEY_V': 'paste',
    'KEY_X': 'cut',
    'KEY_Y': 'redo',
    'KEY_A': 'select_all',
    'KEY_S': 'save',
    'KEY_F': 'find',
    'KEY_N': 'new',
    'KEY_O': 'open',
    'KEY_P': 'print',
    'KEY_B': 'bold',
    'KEY_I': 'italic',
  };
  if (keyCode == 'KEY_Z') return shift ? 'redo' : 'undo';
  if (keyCode == 'KEY_Y') return shift ? null : 'redo';
  if (!shift && keyCode == 'KEY_T') return 'new_tab';
  if (shift && keyCode == 'KEY_T') return null;
  if (!shift && keyCode == 'KEY_W') return 'close_tab';
  if (shift) return null;
  return direct[keyCode];
}
