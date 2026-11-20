import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../mobile_appearance.dart';

const dictationStartupPreloadPreferenceKey = 'dictation.preload_on_startup.v1';

class DictationStartupSetting extends StatefulWidget {
  const DictationStartupSetting({super.key});

  @override
  State<DictationStartupSetting> createState() =>
      _DictationStartupSettingState();
}

class _DictationStartupSettingState extends State<DictationStartupSetting> {
  SharedPreferences? _preferences;
  bool _enabled = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _preferences = preferences;
        _enabled =
            preferences.getBool(dictationStartupPreloadPreferenceKey) ?? false;
      });
    } catch (_) {
      // Leave preload off if the settings store is unavailable.
    }
  }

  Future<void> _save(bool enabled) async {
    final preferences = _preferences;
    if (preferences == null || _saving) return;
    setState(() => _saving = true);
    var saved = false;
    try {
      saved = await preferences.setBool(
        dictationStartupPreloadPreferenceKey,
        enabled,
      );
    } catch (_) {
      // Keep showing the saved value.
    }
    if (!mounted) return;
    setState(() {
      if (saved) _enabled = enabled;
      _saving = false;
    });
    if (!saved) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: MobileText(
            'Could not save the dictation setting.',
            '无法保存听写设置。',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => SwitchListTile(
    key: const ValueKey('dictation-startup-preload'),
    secondary: const Icon(Icons.mic_external_on),
    title: const MobileText('Preload dictation at startup', '启动时预载听写模型'),
    subtitle: const MobileText(
      'Loads the installed model when the app opens. The microphone starts when you start dictation.',
      '打开应用时加载已安装的模型。开始听写时才使用麦克风。',
    ),
    value: _enabled,
    onChanged: _preferences == null || _saving ? null : _save,
  );
}
