import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/config.dart';
import '../app_edition.dart';

class ProfileTemplateRepository {
  ProfileTemplateRepository({
    AssetBundle? bundle,
    this.edition = AppEdition.regular,
  }) : bundle = bundle ?? rootBundle;

  final AssetBundle bundle;
  final AppEdition edition;

  static const assetPaths = [
    'assets/profiles/general.json',
    'assets/profiles/web.json',
    'assets/profiles/meetings.json',
    'assets/profiles/custom.json',
  ];

  static const liteAssetPaths = [
    'assets/profiles/general.json',
    'assets/profiles/lite_chatgpt.json',
    'assets/profiles/lite_chrome.json',
  ];

  Future<List<ProfileConfig>> loadAll() async {
    final profiles = <ProfileConfig>[];
    for (final path
        in edition == AppEdition.lite ? liteAssetPaths : assetPaths) {
      final raw = await bundle.loadString(path);
      profiles.add(
        ProfileConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>),
      );
    }
    return profiles;
  }
}
