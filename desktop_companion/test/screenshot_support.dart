import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';

const screenshotBoundaryKey = ValueKey<String>('screenshot-boundary');

Future<void>? _screenshotFontLoad;
bool _hasScreenshotSymbolFont = false;

List<String> get screenshotFontFamilyFallback =>
    _hasScreenshotSymbolFont ? const ['ScreenshotSymbols'] : const [];

/// Replaces flutter_test's square Ahem font with real Roboto and Material icons.
/// SMARTKEYS_SCREENSHOT_FONT can point at a local CJK-capable font file.
Future<void> prepareScreenshotFonts() =>
    _screenshotFontLoad ??= _loadScreenshotFonts();

Future<void> _loadScreenshotFonts() async {
  final fonts = _materialFontsDirectory();
  final configured = Platform.environment['SMARTKEYS_SCREENSHOT_FONT'];
  final regular = configured == null || configured.isEmpty
      ? File('${fonts.path}${Platform.pathSeparator}roboto-regular.ttf')
      : File(configured);
  final bold = configured == null || configured.isEmpty
      ? File('${fonts.path}${Platform.pathSeparator}roboto-bold.ttf')
      : File(configured);
  final icons = File(
    '${fonts.path}${Platform.pathSeparator}materialicons-regular.otf',
  );
  if (!await regular.exists() ||
      !await bold.exists() ||
      !await icons.exists()) {
    throw StateError('Screenshot fonts are unavailable in this Flutter SDK.');
  }
  Future<ByteData> data(File file) async =>
      ByteData.sublistView(await file.readAsBytes());
  final roboto = FontLoader('Roboto');
  roboto.addFont(data(regular));
  roboto.addFont(data(bold));
  await roboto.load();
  final materialIcons = FontLoader('MaterialIcons');
  materialIcons.addFont(data(icons));
  await materialIcons.load();
  final configuredSymbols =
      Platform.environment['SMARTKEYS_SCREENSHOT_SYMBOL_FONT'];
  if (configuredSymbols != null && configuredSymbols.isNotEmpty) {
    final symbols = File(configuredSymbols);
    if (!await symbols.exists()) {
      throw StateError(
        'Screenshot symbol font is unavailable: $configuredSymbols',
      );
    }
    final symbolLoader = FontLoader('ScreenshotSymbols');
    symbolLoader.addFont(data(symbols));
    await symbolLoader.load();
    _hasScreenshotSymbolFont = true;
  }
}

Directory _materialFontsDirectory() {
  final explicit = Platform.environment['FLUTTER_ROOT'];
  if (explicit != null && explicit.isNotEmpty) {
    final fonts = Directory(
      '$explicit${Platform.pathSeparator}bin${Platform.pathSeparator}cache${Platform.pathSeparator}artifacts${Platform.pathSeparator}material_fonts',
    );
    if (fonts.existsSync()) return fonts;
  }
  var candidate = File(Platform.resolvedExecutable).parent;
  for (var index = 0; index < 7; index++) {
    final fonts = Directory(
      '${candidate.path}${Platform.pathSeparator}bin${Platform.pathSeparator}cache${Platform.pathSeparator}artifacts${Platform.pathSeparator}material_fonts',
    );
    if (fonts.existsSync()) return fonts;
    candidate = candidate.parent;
  }
  throw StateError('Could not locate the Flutter SDK material fonts.');
}

Future<Directory> desktopScreenshotDirectory() async {
  final configured = Platform.environment['SMARTKEYS_SCREENSHOT_DIR'];
  late final Directory root;
  if (configured != null && configured.isNotEmpty) {
    root = Directory(configured);
  } else {
    var candidate = Directory.current.absolute;
    while (true) {
      if (await Directory(
        '${candidate.path}${Platform.pathSeparator}desktop_companion',
      ).exists()) {
        root = Directory(
          '${candidate.path}${Platform.pathSeparator}build${Platform.pathSeparator}ui_screenshots',
        );
        break;
      }
      final parent = candidate.parent;
      if (parent.path == candidate.path) {
        throw StateError('Could not locate the SmartKeys repository root.');
      }
      candidate = parent;
    }
  }
  final output = Directory('${root.path}${Platform.pathSeparator}desktop');
  await output.create(recursive: true);
  return output;
}

Future<File> captureDesktopScreenshot(
  WidgetTester tester, {
  required String id,
  required String title,
  required String orientation,
  required int width,
  required int height,
  required String notes,
}) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(screenshotBoundaryKey),
  );
  final imageFile = (await tester.runAsync<File>(() async {
    final ui.Image image = await boundary.toImage(pixelRatio: 1);
    try {
      expect(image.width, width);
      expect(image.height, height);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      expect(data, isNotNull);
      final Uint8List bytes = data!.buffer.asUint8List();
      expect(bytes.length, greaterThan(1500));

      final directory = await desktopScreenshotDirectory();
      final fileName = 'desktop/$id.png';
      final imageFile = File(
        '${directory.parent.path}${Platform.pathSeparator}$fileName',
      );
      await imageFile.writeAsBytes(bytes, flush: true);
      final metadata = <String, Object>{
        'id': id,
        'title': title,
        'platform': 'Windows widget',
        'orientation': orientation,
        'width': image.width,
        'height': image.height,
        'fileName': fileName,
        'notes': notes,
      };
      await File(
        '${directory.path}${Platform.pathSeparator}$id.json',
      ).writeAsString(const JsonEncoder.withIndent('  ').convert(metadata));
      return imageFile;
    } finally {
      image.dispose();
    }
  }))!;
  return imageFile;
}
