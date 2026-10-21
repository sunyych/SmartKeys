import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:image/image.dart' as image_lib;
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../models/config.dart';

class PrivateImageStore {
  PrivateImageStore({
    ImagePicker? imagePicker,
    Future<Directory> Function()? documentsDirectory,
  }) : _imagePicker = imagePicker ?? ImagePicker(),
       _documentsDirectory =
           documentsDirectory ?? getApplicationDocumentsDirectory;

  final ImagePicker _imagePicker;
  final Future<Directory> Function() _documentsDirectory;

  static const supportedExtensions = {'png', 'jpg', 'jpeg', 'webp'};

  Future<String?> importFromGallery(String profileId) async {
    final selection = await _imagePicker.pickImage(source: ImageSource.gallery);
    return selection == null
        ? null
        : importFile(profileId, File(selection.path));
  }

  /// Writes restore bytes under fresh names, so a failed configuration save
  /// cannot overwrite an image still referenced by the current configuration.
  Future<Map<String, String>> writeRestoredImages(
    Map<String, Uint8List> images,
  ) async {
    if (images.isEmpty) return const {};
    final root = await _documentsDirectory();
    final folder =
        'backup_${DateTime.now().microsecondsSinceEpoch}_${Random.secure().nextInt(1 << 24).toRadixString(16)}';
    final directory = Directory(path.join(root.path, 'images', folder));
    await directory.create(recursive: true);
    final output = <String, String>{};
    try {
      for (final entry in images.entries) {
        final extension = path.extension(entry.key).toLowerCase();
        if (!supportedExtensions.contains(extension.replaceFirst('.', ''))) {
          throw const FormatException('Unsupported restored image type.');
        }
        final name =
            'image_${Random.secure().nextInt(1 << 32).toRadixString(16)}$extension';
        final relative = path.join('images', folder, name);
        final destination = File(path.join(root.path, relative));
        final temporary = File('${destination.path}.next');
        await temporary.writeAsBytes(entry.value, flush: true);
        await temporary.rename(destination.path);
        output[entry.key] = relative;
      }
      return output;
    } catch (_) {
      for (final file in directory.listSync().whereType<File>()) {
        try {
          await file.delete();
        } catch (_) {}
      }
      try {
        await directory.delete();
      } catch (_) {}
      rethrow;
    }
  }

  Future<void> deleteRestoredImages(Iterable<String> relativePaths) async {
    final root = await _documentsDirectory();
    for (final relative in relativePaths) {
      if (path.isAbsolute(relative)) continue;
      final target = File(path.normalize(path.join(root.path, relative)));
      if (!path.isWithin(path.join(root.path, 'images'), target.path)) continue;
      if (await target.exists()) await target.delete();
      final thumbnail = File(
        target.path.replaceFirst(RegExp(r'\.[^.]+$'), '_thumbnail.jpg'),
      );
      if (await thumbnail.exists()) await thumbnail.delete();
      if (await target.parent.exists() && await target.parent.list().isEmpty) {
        await target.parent.delete();
      }
    }
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

  Future<Map<String, Uint8List>> readSelectedImages(
    Iterable<ProfileConfig> profiles,
  ) async {
    final paths = <String>{};
    for (final profile in profiles) {
      final icon = profile.profileIcon;
      if (icon.type == VisualType.customImage && icon.value != null) {
        paths.add(icon.value!);
      }
      for (final button in profile.buttons) {
        if (button.visual.type == VisualType.customImage &&
            button.visual.value != null) {
          paths.add(button.visual.value!);
        }
      }
    }
    final result = <String, Uint8List>{};
    if (paths.length > 244) {
      throw StateError('Too many custom images were selected.');
    }
    var totalEncodedBytes = 0;
    for (final imagePath in paths) {
      final file = await resolve(imagePath);
      if (file == null) {
        throw StateError('A selected custom image is missing: $imagePath');
      }
      final length = await file.length();
      if (length == 0 || length > 4 * 1024 * 1024) {
        throw StateError(
          'A selected custom image exceeds the 4 MiB limit: $imagePath',
        );
      }
      totalEncodedBytes += ((length + 2) ~/ 3) * 4;
      if (totalEncodedBytes > 18 * 1024 * 1024) {
        throw StateError(
          'Selected images exceed the account backup request limit.',
        );
      }
      final bytes = await file.readAsBytes();
      result[imagePath] = bytes;
    }
    return result;
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
