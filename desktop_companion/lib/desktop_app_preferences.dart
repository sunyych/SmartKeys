import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'desktop_native_backend.dart';
import 'windows_desktop_backend.dart';
import 'windows_shortcut_backend.dart';

enum DesktopAppLanguage {
  english(Locale('en')),
  simplifiedChinese(Locale('zh', 'CN'));

  const DesktopAppLanguage(this.locale);
  final Locale locale;
}

class DesktopAppPreferences {
  const DesktopAppPreferences({
    this.language = DesktopAppLanguage.english,
    this.themeMode = ThemeMode.system,
    this.rustEnabled,
  });

  final DesktopAppLanguage language;
  final ThemeMode themeMode;
  final bool? rustEnabled;

  DesktopAppPreferences copyWith({
    DesktopAppLanguage? language,
    ThemeMode? themeMode,
    bool? rustEnabled,
  }) => DesktopAppPreferences(
    language: language ?? this.language,
    themeMode: themeMode ?? this.themeMode,
    rustEnabled: rustEnabled ?? this.rustEnabled,
  );
}

abstract interface class DesktopAppPreferencesStore {
  Future<DesktopAppPreferences> load();
  Future<void> save(DesktopAppPreferences preferences);
}

class SharedPreferencesDesktopAppPreferencesStore
    implements DesktopAppPreferencesStore {
  SharedPreferencesDesktopAppPreferencesStore({
    SharedPreferencesAsync? preferences,
  }) : _preferences = preferences ?? SharedPreferencesAsync();

  static const storageKey = 'lumiakeys.desktop.app_preferences.v1';
  final SharedPreferencesAsync _preferences;

  @override
  Future<DesktopAppPreferences> load() async {
    final raw = await _preferences.getString(storageKey);
    if (raw == null) return const DesktopAppPreferences();
    try {
      final data = jsonDecode(raw);
      if (data is! Map) return const DesktopAppPreferences();
      return DesktopAppPreferences(
        language: data['language'] == DesktopAppLanguage.simplifiedChinese.name
            ? DesktopAppLanguage.simplifiedChinese
            : DesktopAppLanguage.english,
        themeMode: switch (data['themeMode']) {
          'light' => ThemeMode.light,
          'dark' => ThemeMode.dark,
          _ => ThemeMode.system,
        },
        rustEnabled: data['rustEnabled'] is bool
            ? data['rustEnabled'] as bool
            : null,
      );
    } on FormatException {
      return const DesktopAppPreferences();
    }
  }

  @override
  Future<void> save(DesktopAppPreferences preferences) =>
      _preferences.setString(
        storageKey,
        jsonEncode({
          'language': preferences.language.name,
          'themeMode': preferences.themeMode.name,
          'rustEnabled': ?preferences.rustEnabled,
        }),
      );
}

Map<String, String> resolveDesktopBackendEnvironment(
  Map<String, String> inherited,
  bool? rustEnabled,
) {
  if (rustEnabled == null) return inherited;
  const backendKeys = {
    desktopBackendEnvironment,
    windowsDesktopBackendEnvironment,
    windowsShortcutBackendEnvironment,
  };
  return {
    for (final entry in inherited.entries)
      if (!backendKeys.contains(entry.key.toUpperCase()))
        entry.key: entry.value,
    if (rustEnabled) desktopBackendEnvironment: 'rust',
  };
}
