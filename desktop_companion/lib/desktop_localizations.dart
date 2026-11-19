import 'package:flutter/widgets.dart';

String desktopText(
  BuildContext context,
  String english,
  String simplifiedChinese,
) => desktopLocaleText(
  Localizations.maybeLocaleOf(context) ?? const Locale('en'),
  english,
  simplifiedChinese,
);

String desktopLocaleText(
  Locale locale,
  String english,
  String simplifiedChinese,
) => locale.languageCode == 'zh' ? simplifiedChinese : english;
