import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:diagnostics_core/diagnostics_core.dart';
import 'package:image/image.dart' as image_lib;
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../models/config.dart';
import '../icons/app_icon_validation.dart';

class PrivateImageStore {
  PrivateImageStore({
    ImagePicker? imagePicker,
    Future<Directory> Function()? documentsDirectory,
    this.reportDiagnostic,
  }) : _imagePicker = imagePicker ?? ImagePicker(),
       _documentsDirectory =
           documentsDirectory ?? getApplicationDocumentsDirectory;

  final ImagePicker _imagePicker;
  final void Function(DiagnosticCode)? reportDiagnostic;
  final Future<Directory> Function() _documentsDirectory;

  static const supportedExtensions = {'png', 'jpg', 'jpeg', 'webp'};

  Future<DateTime?> desktopAppIconUpdatedAt(
    String computerId,
    String appId,
  ) async {
    if (!_validDesktopIconKey(computerId, appId)) return null;
    try {
      final root = await _documentsDirectory();
      return await File(
        path.join(root.path, 'desktop_app_icons', computerId, '$appId.png'),
      ).lastModified();
    } on FileSystemException {
      return null;
    }
  }

  Future<Uint8List?> readDesktopAppIcon(String computerId, String appId) async {
    if (!_validDesktopIconKey(computerId, appId)) return null;
    final root = await _documentsDirectory();
    final file = File(
      path.join(root.path, 'desktop_app_icons', computerId, '$appId.png'),
    );
    if (!await file.exists()) return null;
    try {
      if (DateTime.now().difference(await file.lastModified()) >=
          const Duration(hours: 24)) {
        return null;
      }
      final length = await file.length();
      if (length < 8 || length > 64 * 1024) return null;
      final bytes = await file.readAsBytes();
      return AppIconValidation.isValidPng(bytes)
          ? Uint8List.fromList(bytes)
          : null;
    } on FileSystemException {
      return null;
    }
  }

  Future<void> cacheDesktopAppIcon(
    String computerId,
    String appId,
    Uint8List bytes,
  ) async {
    try {
      await _cacheDesktopAppIcon(computerId, appId, bytes);
    } catch (_) {
      try {
        reportDiagnostic?.call(DiagnosticCode.storageWriteFailed);
      } catch (_) {}
      rethrow;
    }
  }

  Future<void> _cacheDesktopAppIcon(
    String computerId,
    String appId,
    Uint8List bytes,
  ) async {
    if (!_validDesktopIconKey(computerId, appId) ||
        !AppIconValidation.isValidPng(bytes)) {
      throw const FormatException('Invalid desktop app icon.');
    }
    final root = await _documentsDirectory();
    final directory = Directory(
      path.join(root.path, 'desktop_app_icons', computerId),
    );
    await directory.create(recursive: true);
    final destination = File(path.join(directory.path, '$appId.png'));
    final temporary = File(
      '${destination.path}.${DateTime.now().microsecondsSinceEpoch}.${Random.secure().nextInt(1 << 24)}.next',
    );
    await temporary.writeAsBytes(bytes, flush: true);
    await temporary.rename(destination.path);
  }

  static bool _validDesktopIconKey(String computerId, String appId) =>
      RegExp(r'^[a-f0-9]{32}$').hasMatch(computerId) &&
      (RegExp(r'^[A-Za-z][A-Za-z0-9_-]{0,63}$').hasMatch(appId) ||
          RegExp(
            r'^installed\.[a-f0-9]{32}(?:_[a-f0-9]{12})?$',
          ).hasMatch(appId));

  Future<String?> importFromGallery(String profileId) async {
    final selection = await _imagePicker.pickImage(source: ImageSource.gallery);
    return selection == null
        ? null
        : importFile(profileId, File(selection.path));
  }

  Future<String?> importFromFiles(String profileId) async {
    final selection = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: supportedExtensions.toList(),
    );
    final selectedPath = selection?.files.single.path;
    return selectedPath == null
        ? null
        : importFile(profileId, File(selectedPath));
  }

  Future<String> importFile(String profileId, File source) async {
    final extension = path
        .extension(source.path)
        .replaceFirst('.', '')
        .toLowerCase();
    if (!supportedExtensions.contains(extension)) {
      throw const FormatException(
        'Only PNG, JPEG, and WebP images are supported.',
      );
    }
    final root = await _documentsDirectory();
    final safeProfile = profileId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final relativeDirectory = path.join('images', safeProfile);
    final destinationDirectory = Directory(
      path.join(root.path, relativeDirectory),
    );
    await destinationDirectory.create(recursive: true);
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final fileName = 'button_$stamp.$extension';
    final destination = File(path.join(destinationDirectory.path, fileName));
    await source.copy(destination.path);
    await _createThumbnail(destination, stamp);
    return path.join(relativeDirectory, fileName);
  }

  Future<void> _createThumbnail(File source, int stamp) async {
    final decoded = image_lib.decodeImage(await source.readAsBytes());
    if (decoded == null) return;
    final thumbnail = image_lib.copyResize(
      decoded,
      width: decoded.width >= decoded.height ? 320 : null,
      height: decoded.height > decoded.width ? 320 : null,
      interpolation: image_lib.Interpolation.average,
    );
    final thumbnailFile = File(
      path.join(source.parent.path, 'button_${stamp}_thumbnail.jpg'),
    );
    await thumbnailFile.writeAsBytes(
      image_lib.encodeJpg(thumbnail, quality: 82),
    );
  }

  Future<File?> resolve(String? relativePath) async {
    if (relativePath == null || path.isAbsolute(relativePath)) return null;
    final root = await _documentsDirectory();
    final candidate = File(path.normalize(path.join(root.path, relativePath)));
    if (!path.isWithin(root.path, candidate.path)) return null;
    if (!await candidate.exists()) return null;
    try {
      final resolvedRoot = await root.resolveSymbolicLinks();
      final resolvedCandidate = await candidate.resolveSymbolicLinks();
      if (!path.isWithin(resolvedRoot, resolvedCandidate)) return null;
    } on FileSystemException {
      return null;
    }
    return candidate;
  }

  Future<void> cleanupUnreferenced(AppConfig config) async {
    final referenced = <String>{};
    for (final profile in config.profiles) {
      if (profile.profileIcon.type == VisualType.customImage &&
          profile.profileIcon.value != null) {
        referenced.add(path.normalize(profile.profileIcon.value!));
      }
      for (final button in profile.buttons) {
        if (button.visual.type == VisualType.customImage &&
            button.visual.value != null) {
          referenced.add(path.normalize(button.visual.value!));
        }
      }
    }
    final root = await _documentsDirectory();
    final imageRoot = Directory(path.join(root.path, 'images'));
    if (!await imageRoot.exists()) return;
    await for (final entity in imageRoot.list(recursive: true)) {
      if (entity is! File) continue;
      final relative = path.relative(entity.path, from: root.path);
      final isThumbnail = path.basename(relative).contains('_thumbnail.');
      final original = isThumbnail
          ? relative.replaceFirst(RegExp(r'_thumbnail\.jpg$'), '')
          : relative;
      if (!referenced.contains(path.normalize(relative)) &&
          (!isThumbnail ||
              !referenced.any((item) => item.startsWith(original)))) {
        await entity.delete();
      }
    }
  }
}
