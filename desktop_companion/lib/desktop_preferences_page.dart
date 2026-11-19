import 'package:flutter/material.dart';

import 'desktop_app_preferences.dart';
import 'desktop_localizations.dart';

class DesktopPreferencesPage extends StatelessWidget {
  const DesktopPreferencesPage({
    super.key,
    required this.preferences,
    required this.rustInitiallySelected,
    required this.onChanged,
    this.saving = false,
    this.saveFailed = false,
  });

  final DesktopAppPreferences preferences;
  final bool rustInitiallySelected;
  final ValueChanged<DesktopAppPreferences>? onChanged;
  final bool saving;
  final bool saveFailed;

  @override
  Widget build(BuildContext context) {
    final change = saving ? null : onChanged;
    return ListView(
      padding: const EdgeInsets.all(28),
      children: [
        Card(
          child: Column(
            children: [
              ListTile(
                title: Text(desktopText(context, 'Language', '语言')),
                trailing: DropdownButton<DesktopAppLanguage>(
                  key: const ValueKey('desktop-settings-language'),
                  value: preferences.language,
                  items: const [
                    DropdownMenuItem(
                      value: DesktopAppLanguage.english,
                      child: Text('English'),
                    ),
                    DropdownMenuItem(
                      value: DesktopAppLanguage.simplifiedChinese,
                      child: Text('简体中文'),
                    ),
                  ],
                  onChanged: change == null
                      ? null
                      : (value) {
                          if (value != null) {
                            change(preferences.copyWith(language: value));
                          }
                        },
                ),
              ),
              const Divider(height: 1),
              ListTile(
                title: Text(desktopText(context, 'Theme', '主题')),
                trailing: DropdownButton<ThemeMode>(
                  key: const ValueKey('desktop-settings-theme'),
                  value: preferences.themeMode,
                  items: ThemeMode.values
                      .map((mode) {
                        final label = switch (mode) {
                          ThemeMode.system => desktopText(
                            context,
                            'System',
                            '跟随系统',
                          ),
                          ThemeMode.light => desktopText(
                            context,
                            'Light',
                            '浅色',
                          ),
                          ThemeMode.dark => desktopText(context, 'Dark', '深色'),
                        };
                        return DropdownMenuItem(
                          value: mode,
                          child: Text(label),
                        );
                      })
                      .toList(growable: false),
                  onChanged: change == null
                      ? null
                      : (value) {
                          if (value != null) {
                            change(preferences.copyWith(themeMode: value));
                          }
                        },
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: SwitchListTile(
            key: const ValueKey('desktop-settings-rust'),
            title: Text(desktopText(context, 'Rust backend', 'Rust 后端')),
            subtitle: Text(
              desktopText(
                context,
                'Restart LumiaKey Desktop to apply changes to the Rust backend.',
                '重启 LumiaKey Desktop 后，Rust 后端设置生效。',
              ),
            ),
            value: preferences.rustEnabled ?? rustInitiallySelected,
            onChanged: change == null
                ? null
                : (value) => change(preferences.copyWith(rustEnabled: value)),
          ),
        ),
        if (saveFailed)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              desktopText(
                context,
                'Could not save desktop settings. Try again.',
                '无法保存桌面设置，请重试。',
              ),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    );
  }
}
