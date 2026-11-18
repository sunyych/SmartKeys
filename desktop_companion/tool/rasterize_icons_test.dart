import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_svg/flutter_svg.dart';

// Explicit asset preparation tool, not part of the normal regression suite.
// Uses original registered vector artwork; never synthesizes brand marks.
void main() {
  testWidgets('rasterize registered offline icon artwork', (tester) async {
    await tester.runAsync(() async {
      final root = Directory.current.parent;
      final source = Directory(
        '${root.path}/community_server/assets/app_icons',
      );
      const registeredVectors = {
        'claude-app.svg',
        'cursor.svg',
        'firefox.svg',
        'safari.svg',
        'zoom.svg',
        'appleMusic.svg',
        'teams.svg',
      };
      for (final file in source.listSync().whereType<File>().where(
        (file) => registeredVectors.contains(file.uri.pathSegments.last),
      )) {
        final xml = await file.readAsString();
        expect(xml.length, lessThanOrEqualTo(64 * 1024));
        expect(
          RegExp(
            r'<(?:script|image|foreignObject)\b|<!DOCTYPE',
            caseSensitive: false,
          ).hasMatch(xml),
          isFalse,
        );
        final info = await vg.loadPicture(SvgStringLoader(xml), null);
        final recorder = ui.PictureRecorder();
        final canvas = ui.Canvas(recorder)
          ..scale(256 / info.size.width, 256 / info.size.height);
        canvas.drawPicture(info.picture);
        final picture = recorder.endRecording();
        final image = await picture.toImage(256, 256);
        final bytes = (await image.toByteData(
          format: ui.ImageByteFormat.png,
        ))!.buffer.asUint8List();
        expect(bytes.length, lessThanOrEqualTo(64 * 1024));
        final name = file.uri.pathSegments.last.replaceFirst(
          RegExp(r'\.svg$'),
          '.png',
        );
        for (final destination in [
          source,
          Directory('${root.path}/assets/app_icons'),
          Directory('${root.path}/desktop_companion/assets/app_icons'),
        ]) {
          final target = File('${destination.path}/$name');
          if (await target.exists()) {
            continue;
          }
          await target.writeAsBytes(bytes);
        }
        image.dispose();
        picture.dispose();
        info.picture.dispose();
      }
    });
  });
}
