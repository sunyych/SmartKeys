import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:image/image.dart' as image_lib;

import '../models/config.dart';
import 'private_image_store.dart';

class BackupSelection {
  const BackupSelection({
    this.settings = true,
    this.profileIds = const [],
    this.images = false,
  });

  final bool settings;
  final List<String> profileIds;
  final bool images;

  Map<String, Object?> toJson() => {
    'settings': settings,
    'profile_ids': profileIds,
    'images': images,
  };
}

class DecodedAccountBackup {
  const DecodedAccountBackup({
    required this.selection,
    required this.preferences,
    required this.profiles,
    required this.images,
    required this.updatedAt,
  });

  final BackupSelection selection;
  final AppPreferences? preferences;
  final List<ProfileConfig> profiles;
  final Map<String, Uint8List> images;
  final String updatedAt;
}

class AccountBackupCodec {
  static const maxImageBytes = 4 * 1024 * 1024;
  static const maxImages = 244;
  static const maxBodyBytes = 20 * 1024 * 1024;
  static const maxCompanionPayloadBytes = 16 * 1024;

  static Future<Map<String, Object?>> encodeAsync(
    AppConfig config,
    BackupSelection selection,
    Map<String, Uint8List> images,
  ) => Isolate.run(() => encode(config, selection, images));

  static Future<DecodedAccountBackup> decodeAsync(
    Object? value, {
    required String updatedAt,
  }) => Isolate.run(() => decode(value, updatedAt: updatedAt));

  static Map<String, Object?> encode(
    AppConfig config,
    BackupSelection selection,
    Map<String, Uint8List> images,
  ) {
    if (!selection.settings && selection.profileIds.isEmpty) {
      throw const FormatException('Select settings or at least one Profile.');
    }
    if (selection.profileIds.length > freeProfileLimit ||
        selection.profileIds.toSet().length != selection.profileIds.length) {
      throw const FormatException('Profile selection is invalid.');
    }
    final profilesById = {
      for (final profile in config.profiles) profile.id: profile,
    };
    final selectedProfiles = selection.profileIds
        .map((id) {
          final profile = profilesById[id];
          if (profile == null) throw FormatException('Unknown Profile: $id');
          final json = profile.toJson();
          return json;
        })
        .toList(growable: false);
    final normalizedImages = {
      for (final entry in images.entries)
        entry.key.replaceAll('\\', '/'): entry.value,
    };
    final referenced = <String>{};
    for (final profile in selectedProfiles) {
      _normalizeImagePaths(profile);
      _validateProfile(profile);
      _collectImagePaths(profile, referenced);
    }
    for (final imagePath in referenced) {
      _validateImagePath(imagePath);
    }
    final encodedImages = <Map<String, Object?>>[];
    if (selection.images) {
      if (normalizedImages.length > maxImages) {
        throw const FormatException('Too many images.');
      }
      for (final entry in normalizedImages.entries) {
        if (!referenced.contains(entry.key)) continue;
        _validateImagePath(entry.key);
        _validateImageBytes(entry.key, entry.value);
        encodedImages.add({
          'path': entry.key,
          'mime_type': _mimeFor(entry.key),
          'data_base64': base64Encode(entry.value),
        });
      }
      if (referenced.any((path) => !normalizedImages.containsKey(path))) {
        throw const FormatException('A selected custom image is unavailable.');
      }
    }
    final envelope = <String, Object?>{
      'schema_version': 1,
      'selection': selection.toJson(),
      'data': {
        'preferences': selection.settings ? config.preferences.toJson() : null,
        'profiles': selectedProfiles,
        'images': encodedImages,
      },
    };
    if (utf8.encode(jsonEncode(envelope)).length > maxBodyBytes) {
      throw const FormatException('Backup exceeds the 20 MiB request limit.');
    }
    return envelope;
  }

  static DecodedAccountBackup decode(
    Object? value, {
    required String updatedAt,
  }) {
    final wrapper = _map(value, 'backup wrapper');
    _keys(wrapper, const {'schema_version', 'updated_at', 'backup'}, 'wrapper');
    if (wrapper['schema_version'] != 1 || wrapper['updated_at'] != updatedAt) {
      throw const FormatException('Unsupported backup response.');
    }
    final envelope = _map(wrapper['backup'], 'backup');
    _keys(envelope, const {'schema_version', 'selection', 'data'}, 'backup');
    if (envelope['schema_version'] != 1) {
      throw const FormatException('Unsupported backup version.');
    }
    if (utf8.encode(jsonEncode(envelope)).length > maxBodyBytes) {
      throw const FormatException('Backup exceeds the 20 MiB request limit.');
    }
    final selectionMap = _map(envelope['selection'], 'selection');
    _keys(selectionMap, const {
      'settings',
      'profile_ids',
      'images',
    }, 'selection');
    final settings = selectionMap['settings'];
    final wantsImages = selectionMap['images'];
    final rawIds = selectionMap['profile_ids'];
    if (settings is! bool ||
        wantsImages is! bool ||
        rawIds is! List ||
        rawIds.length > freeProfileLimit ||
        rawIds.any((id) => id is! String) ||
        rawIds.toSet().length != rawIds.length ||
        (!settings && rawIds.isEmpty)) {
      throw const FormatException('Invalid backup selection.');
    }
    final ids = rawIds.cast<String>();
    final data = _map(envelope['data'], 'data');
    _keys(data, const {'preferences', 'profiles', 'images'}, 'data');
    final rawPreferences = data['preferences'];
    if (settings != (rawPreferences != null)) {
      throw const FormatException('Settings selection does not match data.');
    }
    final preferences = rawPreferences == null
        ? null
        : _decodePreferences(_map(rawPreferences, 'preferences'));
    final rawProfiles = data['profiles'];
    if (rawProfiles is! List || rawProfiles.length != ids.length) {
      throw const FormatException('Profiles do not match selection.');
    }
    final profiles = <ProfileConfig>[];
    for (var i = 0; i < ids.length; i++) {
      final profileJson = _map(rawProfiles[i], 'Profile');
      _validateProfile(profileJson);
      if (profileJson['id'] != ids[i]) {
        throw const FormatException(
          'Profile IDs do not match selection order.',
        );
      }
      profiles.add(ProfileConfig.fromJson(profileJson));
    }
    final rawImages = data['images'];
    if (rawImages is! List ||
        rawImages.length > maxImages ||
        (!wantsImages && rawImages.isNotEmpty)) {
      throw const FormatException('Invalid image list.');
    }
    final decodedImages = <String, Uint8List>{};
    for (final item in rawImages) {
      final image = _map(item, 'image');
      _keys(image, const {'path', 'mime_type', 'data_base64'}, 'image');
      final imagePath = image['path'];
      final mime = image['mime_type'];
      final encoded = image['data_base64'];
      if (imagePath is! String || mime is! String || encoded is! String) {
        throw const FormatException('Invalid image entry.');
      }
      _validateImagePath(imagePath);
      if (mime != _mimeFor(imagePath)) {
        throw const FormatException('Image MIME type does not match its path.');
      }
      final bytes = base64Decode(encoded);
      _validateImageBytes(imagePath, bytes);
      if (decodedImages.containsKey(imagePath)) {
        throw const FormatException('Duplicate image path.');
      }
      decodedImages[imagePath] = bytes;
    }
    final selectedImagePaths = <String>{};
    for (final profile in profiles) {
      _collectImagePaths(profile.toJson(), selectedImagePaths);
    }
    if (!selectedImagePaths.containsAll(decodedImages.keys)) {
      throw const FormatException('Backup contains an unreferenced image.');
    }
    return DecodedAccountBackup(
      selection: BackupSelection(
        settings: settings,
        profileIds: ids,
        images: wantsImages,
      ),
      preferences: preferences,
      profiles: profiles,
      images: decodedImages,
      updatedAt: updatedAt,
    );
  }

  static AppPreferences _decodePreferences(Map<String, dynamic> json) {
    const keys = {
      'hapticEnabled',
      'soundEnabled',
      'orientationMode',
      'shortcutPlatform',
      'controlSurfaceLayout',
      'tabletKeysPerPage',
      'chargingBrightnessMode',
      'chargingBrightness',
      'keepScreenOnWhileCharging',
    };
    _keys(json, keys, 'preferences');
    if (json['hapticEnabled'] is! bool ||
        json['soundEnabled'] is! bool ||
        json['keepScreenOnWhileCharging'] is! bool ||
        !OrientationMode.values.any((v) => v.name == json['orientationMode']) ||
        !ShortcutPlatform.values.any(
          (v) => v.name == json['shortcutPlatform'],
        ) ||
        !ControlSurfaceLayout.values.any(
          (v) => v.name == json['controlSurfaceLayout'],
        ) ||
        json['tabletKeysPerPage'] is! int ||
        (json['tabletKeysPerPage'] as int) < minTabletKeysPerPage ||
        (json['tabletKeysPerPage'] as int) > maxTabletKeysPerPage ||
        !ChargingBrightnessMode.values.any(
          (v) => v.name == json['chargingBrightnessMode'],
        ) ||
        json['chargingBrightness'] is! num ||
        !(json['chargingBrightness'] as num).isFinite ||
        (json['chargingBrightness'] as num) < 0.1 ||
        (json['chargingBrightness'] as num) > 1.0) {
      throw const FormatException('Invalid preferences values.');
    }
    return AppPreferences.fromJson(json);
  }

  static Map<String, dynamic> _map(Object? value, String name) {
    if (value is! Map || value.keys.any((key) => key is! String)) {
      throw FormatException('$name must be an object.');
    }
    return value.cast<String, dynamic>();
  }

  static void _keys(
    Map<String, dynamic> map,
    Set<String> allowed,
    String name,
  ) {
    if (map.keys.toSet().difference(allowed).isNotEmpty ||
        allowed.difference(map.keys.toSet()).isNotEmpty) {
      throw FormatException('$name fields do not match the supported schema.');
    }
  }

  static void _validateProfile(Map<String, dynamic> profile) {
    _keys(profile, const {
      'id',
      'name',
      'targetApplication',
      'profileIcon',
      'accentColor',
      'isBuiltInTemplate',
      'buttons',
      'wheel',
      'createdAt',
      'updatedAt',
    }, 'Profile');
    if (profile['id'] is! String ||
        (profile['id'] as String).isEmpty ||
        profile['name'] is! String ||
        (profile['targetApplication'] != null &&
            profile['targetApplication'] is! String) ||
        (profile['accentColor'] != null && profile['accentColor'] is! int) ||
        profile['isBuiltInTemplate'] is! bool ||
        profile['createdAt'] is! int ||
        profile['updatedAt'] is! int ||
        profile['buttons'] is! List) {
      throw const FormatException('Invalid Profile.');
    }
    final buttons = profile['buttons'] as List;
    if (buttons.length > maxControlButtonCount) {
      throw const FormatException('Too many button positions.');
    }
    final positions = <int>{};
    for (final raw in buttons) {
      final button = _map(raw, 'button');
      _keys(button, const {
        'id',
        'position',
        'label',
        'subtitle',
        'showLabel',
        'showShortcut',
        'visual',
        'action',
        'hapticEnabled',
        'soundEnabled',
        'textSize',
      }, 'button');
      if (button['id'] is! String ||
          button['label'] is! String ||
          button['subtitle'] is! String ||
          button['showLabel'] is! bool ||
          button['showShortcut'] is! bool ||
          button['hapticEnabled'] is! bool ||
          button['soundEnabled'] is! bool ||
          button['textSize'] is! num) {
        throw const FormatException('Invalid button fields.');
      }
      final position = button['position'];
      if (position is! int ||
          position < 0 ||
          position >= maxControlButtonCount ||
          !positions.add(position)) {
        throw const FormatException('Invalid button position.');
      }
      final visual = _map(button['visual'], 'visual');
      _keys(visual, const {
        'type',
        'value',
        'fit',
        'tintColor',
        'backgroundColor',
        'iconSize',
        'imageScale',
        'alignmentX',
        'alignmentY',
      }, 'visual');
      _validateVisual(visual);
      _validateAction(_map(button['action'], 'action'));
    }
    if (profile['profileIcon'] != null) {
      final icon = _map(profile['profileIcon'], 'profile icon');
      _keys(icon, const {
        'type',
        'value',
        'fit',
        'tintColor',
        'backgroundColor',
        'iconSize',
        'imageScale',
        'alignmentX',
        'alignmentY',
      }, 'profile icon');
      _validateVisual(icon);
    }
    final wheel = _map(profile['wheel'], 'wheel');
    _keys(wheel, const {
      'controlType',
      'clockwise',
      'counterClockwise',
      'center',
      'up',
      'down',
      'left',
      'right',
      'modeLabel',
    }, 'wheel');
    if (wheel['modeLabel'] is! String ||
        !WheelControlType.values.any((v) => v.name == wheel['controlType'])) {
      throw const FormatException('Invalid wheel.');
    }
    for (final name in const [
      'clockwise',
      'counterClockwise',
      'center',
      'up',
      'down',
      'left',
      'right',
    ]) {
      _validateAction(_map(wheel[name], 'wheel action'));
    }
  }

  static void _validateAction(Map<String, dynamic> action) {
    _keys(action, const {'type', 'keyCode', 'modifiers', 'value'}, 'action');
    final type = action['type'];
    final value = action['value'];
    if (type is! String ||
        !ActionType.values.any((v) => v.name == type) ||
        action['modifiers'] is! List ||
        (action['modifiers'] as List).length > 8 ||
        (action['modifiers'] as List).any((m) => m is! String)) {
      throw const FormatException('Invalid action.');
    }
    if (type == 'companion' && !_isValidCompanionPayload(value)) {
      throw const FormatException('Invalid Desktop action JSON.');
    }
    if (type == 'mouseMove' &&
        !(const {'UP', 'DOWN', 'LEFT', 'RIGHT'}.contains(value) ||
            (value is String &&
                RegExp(r'^-?\d{1,4},-?\d{1,4}$').hasMatch(value)))) {
      throw const FormatException('Unsafe mouse action.');
    }
    if (type == 'mouseWheel' &&
        !(const {'UP', 'DOWN', 'WHEEL_UP', 'WHEEL_DOWN'}.contains(value) ||
            (value is String &&
                RegExp(
                  r'^-?(?:[0-9]|[1-9][0-9]|1[01][0-9]|12[0-7])$',
                ).hasMatch(value)))) {
      throw const FormatException('Unsafe wheel action.');
    }
    if (type == 'mouseButton' &&
        !const {
          'LEFT',
          'PRIMARY',
          'RIGHT',
          'SECONDARY',
          'MIDDLE',
        }.contains(value)) {
      throw const FormatException('Unsafe mouse button action.');
    }
    if (type == 'consumerControl' &&
        !const {
          'BRIGHTNESS_UP',
          'BRIGHTNESS_DOWN',
          'KEYBOARD_BRIGHTNESS_UP',
          'KEYBOARD_BRIGHTNESS_DOWN',
          'KEYBOARD_BACKLIGHT_MINIMUM',
          'KEYBOARD_BACKLIGHT_MAXIMUM',
          'PLAY',
          'PAUSE',
          'RECORD',
          'NEXT_TRACK',
          'PREVIOUS_TRACK',
          'STOP',
          'PLAY_PAUSE',
          'MUTE',
          'VOLUME_UP',
          'VOLUME_DOWN',
        }.contains(value)) {
      throw const FormatException('Unsafe consumer control action.');
    }
    if (type == 'keyboard') {
      if (action['keyCode'] is! String ||
          !RegExp(
            r'^KEY_[A-Z0-9_]{1,40}$',
          ).hasMatch(action['keyCode'] as String) ||
          value != null ||
          (action['modifiers'] as List).any(
            (modifier) => !const {
              'PRIMARY',
              'LEFT_CTRL',
              'RIGHT_CTRL',
              'LEFT_SHIFT',
              'RIGHT_SHIFT',
              'SHIFT',
              'ALT',
              'LEFT_ALT',
              'RIGHT_ALT',
              'META',
              'LEFT_META',
              'RIGHT_META',
              'GUI',
              'LEFT_GUI',
              'RIGHT_GUI',
            }.contains(modifier),
          )) {
        throw const FormatException('Invalid keyboard action.');
      }
    } else if (action['keyCode'] != null ||
        (action['modifiers'] as List).isNotEmpty) {
      throw const FormatException(
        'Non-keyboard actions cannot contain key codes or modifiers.',
      );
    }
    if (type == 'none' && (value != null || action['keyCode'] != null)) {
      throw const FormatException('Invalid empty action.');
    }
  }

  static void _collectImagePaths(
    Map<String, dynamic> profile,
    Set<String> result,
  ) {
    final profileIcon = profile['profileIcon'];
    if (profileIcon is Map<String, dynamic> &&
        profileIcon['type'] == 'customImage' &&
        profileIcon['value'] is String) {
      result.add(profileIcon['value'] as String);
    }
    for (final raw in profile['buttons'] as List) {
      final button = raw as Map<String, dynamic>;
      final visual = button['visual'] as Map<String, dynamic>;
      if (visual['type'] == 'customImage' && visual['value'] is String) {
        result.add(visual['value'] as String);
      }
    }
  }

  static bool _isValidCompanionPayload(Object? value) {
    if (value is! String) return false;
    if (utf8.encode(value).length > maxCompanionPayloadBytes) return false;
    try {
      final decoded = jsonDecode(value);
      return decoded is Map && decoded.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static void _normalizeImagePaths(Map<String, dynamic> profile) {
    final icon = profile['profileIcon'];
    if (icon is Map<String, dynamic> &&
        icon['type'] == 'customImage' &&
        icon['value'] is String) {
      icon['value'] = (icon['value'] as String).replaceAll('\\', '/');
    }
    for (final raw in profile['buttons'] as List) {
      final visual =
          (raw as Map<String, dynamic>)['visual'] as Map<String, dynamic>;
      if (visual['type'] == 'customImage' && visual['value'] is String) {
        visual['value'] = (visual['value'] as String).replaceAll('\\', '/');
      }
    }
  }

  static void _validateVisual(Map<String, dynamic> visual) {
    if (!VisualType.values.any((v) => v.name == visual['type']) ||
        !VisualFit.values.any((v) => v.name == visual['fit']) ||
        (visual['value'] != null && visual['value'] is! String) ||
        (visual['tintColor'] != null && visual['tintColor'] is! int) ||
        (visual['backgroundColor'] != null &&
            visual['backgroundColor'] is! int) ||
        visual['iconSize'] is! num ||
        visual['imageScale'] is! num ||
        visual['alignmentX'] is! num ||
        visual['alignmentY'] is! num) {
      throw const FormatException('Invalid visual.');
    }
    if (visual['type'] == 'customImage' && visual['value'] is String) {
      _validateImagePath(visual['value'] as String);
    }
  }

  static void _validateImagePath(String value) {
    if (value.contains('\\')) {
      throw const FormatException('Image paths must use forward slashes.');
    }
    final parts = p.posix.split(value);
    if (p.posix.isAbsolute(value) ||
        parts.length != 3 ||
        parts[0] != 'images' ||
        parts.any(
          (part) =>
              part.isEmpty ||
              part == '.' ||
              part == '..' ||
              part.length > 80 ||
              !RegExp(r'^[A-Za-z0-9_-]+(?:\.[A-Za-z0-9]+)?$').hasMatch(part),
        ) ||
        !PrivateImageStore.supportedExtensions.contains(
          p.posix.extension(value).replaceFirst('.', '').toLowerCase(),
        )) {
      throw const FormatException('Unsafe image path.');
    }
    if (value.length > 200) {
      throw const FormatException('Image path is too long.');
    }
  }

  static String _mimeFor(String path) =>
      switch (p.posix.extension(path).toLowerCase()) {
        '.png' => 'image/png',
        '.jpg' || '.jpeg' => 'image/jpeg',
        '.webp' => 'image/webp',
        _ => throw const FormatException('Unsupported image type.'),
      };

  static void _validateImageBytes(String path, Uint8List bytes) {
    if (bytes.isEmpty || bytes.length > maxImageBytes) {
      throw const FormatException('Image must be between 1 byte and 4 MiB.');
    }
    final ext = p.posix.extension(path).toLowerCase();
    final valid = ext == '.png'
        ? bytes.length >= 8 &&
              bytes.take(8).toList().toString() ==
                  [137, 80, 78, 71, 13, 10, 26, 10].toString()
        : ext == '.jpg' || ext == '.jpeg'
        ? bytes.length >= 3 &&
              bytes[0] == 0xff &&
              bytes[1] == 0xd8 &&
              bytes[2] == 0xff
        : bytes.length >= 12 &&
              String.fromCharCodes(bytes.sublist(0, 4)) == 'RIFF' &&
              String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP';
    if (!valid) {
      throw const FormatException(
        'Image content does not match its extension.',
      );
    }
    final decoder = image_lib.findDecoderForData(bytes);
    final info = decoder?.startDecode(bytes);
    if (info == null ||
        info.width <= 0 ||
        info.height <= 0 ||
        info.width * info.height > 16 * 1000 * 1000) {
      throw const FormatException(
        'Image dimensions are invalid or exceed the 16 megapixel limit.',
      );
    }
    if (decoder!.decode(bytes) == null) {
      throw const FormatException('Image data is malformed.');
    }
  }
}
