import 'dart:io';

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
    return candidate.existsSync() ? candidate : null;
  }

  Future<void> cleanupUnreferenced(AppConfig config) async {
    final referenced = <String>{};
    for (final profile in config.profiles) {
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
