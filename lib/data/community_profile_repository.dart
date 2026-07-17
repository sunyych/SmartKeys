import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/config.dart';

class CommunityProfileRepository {
  CommunityProfileRepository({AssetBundle? bundle})
    : bundle = bundle ?? rootBundle;

  final AssetBundle bundle;

  static const assetPaths = [
    'assets/community/presentation.json',
    'assets/community/vscode.json',
    'assets/community/media.json',
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
