import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/config.dart';

class ProfileTemplateRepository {
  ProfileTemplateRepository({AssetBundle? bundle})
    : bundle = bundle ?? rootBundle;

  final AssetBundle bundle;

  static const assetPaths = [
    'assets/profiles/general.json',
    'assets/profiles/web.json',
    'assets/profiles/meetings.json',
    'assets/profiles/custom.json',
  ];

  Future<List<ProfileConfig>> loadAll() async {
    final profiles = <ProfileConfig>[];
    for (final path in assetPaths) {
      final raw = await bundle.loadString(path);
      profiles.add(
        ProfileConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>),
      );
    }
    return profiles;
  }
}
