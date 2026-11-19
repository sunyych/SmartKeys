import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum MobileLanguage {
  english(Locale('en'), 'English'),
  simplifiedChinese(Locale('zh', 'CN'), '简体中文');

  const MobileLanguage(this.locale, this.label);

  final Locale locale;
  final String label;
}

/// Device-local presentation preferences. These are independent of the
/// shortcut configuration, which can be synchronized and restored.
class MobileAppearance extends ChangeNotifier {
  MobileAppearance() {
    _pending = _load();
  }

  static const _languageKey = 'lumiakey.appearance.language';
  static const _themeKey = 'lumiakey.appearance.theme';

  MobileLanguage _language = MobileLanguage.english;
  ThemeMode _themeMode = ThemeMode.dark;
  late Future<void> _pending;
  bool _disposed = false;
  bool _ready = false;

  MobileLanguage get language => _language;
  ThemeMode get themeMode => _themeMode;
  bool get ready => _ready;

  Future<void> _load() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      _language = preferences.get(_languageKey) == 'zh'
          ? MobileLanguage.simplifiedChinese
          : MobileLanguage.english;
      _themeMode = switch (preferences.get(_themeKey)) {
        'light' => ThemeMode.light,
        'system' => ThemeMode.system,
        _ => ThemeMode.dark,
      };
    } catch (_) {
      // The existing app defaults still work if device storage is unavailable.
    } finally {
      _ready = true;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> setLanguage(MobileLanguage language) => _save(
    _languageKey,
    language.locale.languageCode,
    () => _language = language,
  );

  Future<void> setThemeMode(ThemeMode mode) =>
      _save(_themeKey, mode.name, () => _themeMode = mode);

  Future<void> _save(String key, String value, VoidCallback apply) {
    final operation = _pending.then((_) async {
      if (_disposed) return;
      final preferences = await SharedPreferences.getInstance();
      if (!await preferences.setString(key, value)) {
        throw StateError('Appearance preference could not be saved.');
      }
      if (_disposed) return;
      apply();
      notifyListeners();
    });
    _pending = operation.catchError((Object _) {});
    return operation;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class MobileAppearanceScope extends InheritedNotifier<MobileAppearance> {
  const MobileAppearanceScope({
    super.key,
    required MobileAppearance appearance,
    required super.child,
  }) : super(notifier: appearance);

  static MobileAppearance? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<MobileAppearanceScope>()
      ?.notifier;
}

extension MobileTranslation on BuildContext {
  String mobileText(String english, String chinese) =>
      Localizations.maybeLocaleOf(this)?.languageCode == 'zh'
      ? chinese
      : english;
}

/// Bilingual text for constant widget subtrees.
class MobileText extends StatelessWidget {
  const MobileText(this.english, this.chinese, {super.key, this.textAlign});

  final String english;
  final String chinese;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) =>
      Text(context.mobileText(english, chinese), textAlign: textAlign);
}
