import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// Captures real Flutter widget-tree renders for the offline UI gallery.
/// These are widget-rendered images, not Android or physical-device captures.
class ScreenshotSupport {
  static Future<void>? _fontLoad;

  ScreenshotSupport(this.tester)
    : root = Directory(
        Platform.environment['SMARTKEYS_SCREENSHOT_DIR'] ??
            '${Directory.current.path}${Platform.pathSeparator}build${Platform.pathSeparator}ui_screenshots',
      );

  final WidgetTester tester;
  final Directory root;

  static List<String>? get fontFamilyFallback {
    final symbolPath = Platform.environment['SMARTKEYS_SCREENSHOT_SYMBOL_FONT'];
    return symbolPath == null || symbolPath.isEmpty
        ? null
        : const ['ScreenshotSymbols'];
  }

  static Future<void> prepareFonts() => _fontLoad ??= _loadScreenshotFonts();

  static Future<void> _loadScreenshotFonts() async {
    final sdkFonts = _findFlutterRoot();
    final configured = Platform.environment['SMARTKEYS_SCREENSHOT_FONT'];
    final roboto = configured == null || configured.isEmpty
        ? File('${sdkFonts.path}${Platform.pathSeparator}roboto-regular.ttf')
        : File(configured);
    final bold = configured == null || configured.isEmpty
        ? File('${sdkFonts.path}${Platform.pathSeparator}roboto-bold.ttf')
        : File(configured);
    final iconFont = File(
      '${sdkFonts.path}${Platform.pathSeparator}materialicons-regular.otf',
    );
    if (!await roboto.exists() ||
        !await bold.exists() ||
        !await iconFont.exists()) {
      throw StateError(
        'Screenshot fonts are missing. Set SMARTKEYS_SCREENSHOT_FONT or use a complete Flutter SDK.',
      );
    }
    final textLoader = FontLoader('Roboto')
      ..addFont(_fontData(roboto))
      ..addFont(_fontData(bold));
    await textLoader.load();
    final iconLoader = FontLoader('MaterialIcons')
      ..addFont(_fontData(iconFont));
    await iconLoader.load();

    final symbolPath = Platform.environment['SMARTKEYS_SCREENSHOT_SYMBOL_FONT'];
    if (symbolPath != null && symbolPath.isNotEmpty) {
      final symbolFile = File(symbolPath);
      if (!await symbolFile.exists()) {
        throw StateError(
          'Configured screenshot symbol font does not exist: $symbolPath',
        );
      }
      final symbolLoader = FontLoader('ScreenshotSymbols')
        ..addFont(_fontData(symbolFile));
      await symbolLoader.load();
    }
  }

  static Future<ByteData> _fontData(File file) async =>
      ByteData.sublistView(await file.readAsBytes());

  static Directory _findFlutterRoot() {
    final explicit = Platform.environment['FLUTTER_ROOT'];
    if (explicit != null && explicit.isNotEmpty) {
      final root = Directory(
        '$explicit${Platform.pathSeparator}bin${Platform.pathSeparator}cache${Platform.pathSeparator}artifacts${Platform.pathSeparator}material_fonts',
      );
      if (root.existsSync()) return root;
    }
    var candidate = File(Platform.resolvedExecutable).parent;
    for (var index = 0; index < 7; index++) {
      final root = Directory(
        '${candidate.path}${Platform.pathSeparator}bin${Platform.pathSeparator}cache${Platform.pathSeparator}artifacts${Platform.pathSeparator}material_fonts',
      );
      if (root.existsSync()) return root;
      candidate = candidate.parent;
    }
    throw StateError('Could not locate Flutter SDK material fonts.');
  }

  Future<void> setViewport(Size size) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
  }

  Future<void> capture({
    required String id,
    required String title,
    required String orientation,
    required String notes,
    required GlobalKey boundaryKey,
  }) async {
    expect(orientation, anyOf('portrait', 'landscape'));
    expect(
      tester.takeException(),
      isNull,
      reason: 'Flutter exception before $id',
    );
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(boundaryKey),
    );
    expect(boundary.size.width, greaterThan(0));
    expect(boundary.size.height, greaterThan(0));
    final png = (await tester.runAsync<Uint8List>(() async {
      final image = await boundary.toImage(pixelRatio: 1);
      try {
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        if (bytes == null) throw StateError('Could not encode screenshot PNG');
        return bytes.buffer.asUint8List();
      } finally {
        image.dispose();
      }
    }))!;
    expect(png, isNotEmpty);
    final decoded = img.decodePng(png);
    expect(decoded, isNotNull, reason: '$id must be a valid PNG');
    expect(decoded!.width, greaterThan(200));
    expect(decoded.height, greaterThan(200));

    final fileName = 'phone/$id.png';
    late final File pngFile;
    final metadata = <String, Object>{
      'id': id,
      'title': title,
      'platform': 'Android widget',
      'orientation': orientation,
      'width': decoded.width,
      'height': decoded.height,
      'fileName': fileName.replaceAll(Platform.pathSeparator, '/'),
      'notes':
          '$notes Fixed Flutter test viewport; this is not a physical-device screenshot.',
    };
    await tester.runAsync(() async {
      final phone = Directory('${root.path}${Platform.pathSeparator}phone');
      await phone.create(recursive: true);
      pngFile = File('${phone.path}${Platform.pathSeparator}$id.png');
      await pngFile.writeAsBytes(png, flush: true);
      await File(
        '${phone.path}${Platform.pathSeparator}$id.json',
      ).writeAsString(
        const JsonEncoder.withIndent('  ').convert(metadata),
        flush: true,
      );
    });
    final length = await tester.runAsync(pngFile.length);
    expect(length, greaterThan(500));
    expect(
      tester.takeException(),
      isNull,
      reason: 'Flutter exception after $id',
    );
  }

  Future<void> unmount() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  void resetViewport() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  }
}

Widget screenshotBoundary(GlobalKey key, Widget child) =>
    RepaintBoundary(key: key, child: child);
