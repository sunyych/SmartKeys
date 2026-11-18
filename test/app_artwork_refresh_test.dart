import 'dart:async';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:smart_keys/icons/app_icon_catalog.dart';
import 'package:smart_keys/icons/icon_library.dart';

Uint8List _png(int color) => Uint8List.fromList(
  image.encodePng(
    image.Image(width: 2, height: 2)..setPixelRgb(0, 0, color, 0, 0),
  ),
);

LibraryIcon _entry(Uint8List bytes) => LibraryIcon.fromJson({
  'app_id': 'extra',
  'canonical_id': 'extra',
  'name': 'Extra',
  'aliases': <String>[],
  'sha256': sha256.convert(bytes).toString(),
  'version': '1',
  'width': 2,
  'height': 2,
  'bundled': false,
  'available': true,
  'mime_type': 'image/png',
  'download_url': '/v1/icons/extra',
  'source': 'https://example.com/source.png',
  'source_page_url': 'https://example.com/app',
  'terms_url': 'https://example.com/terms',
});

class _Library extends IconLibrary {
  _Library(this.entry, {this.bytes});

  LibraryIcon entry;
  Uint8List? bytes;
  Uint8List? coldBytes;
  Completer<Uint8List?>? pending;
  int reads = 0;

  @override
  LibraryIcon? byId(String id) => id == entry.id ? entry : null;

  @override
  bool isDownloaded(String id) => bytes != null && id == entry.id;

  @override
  Future<Uint8List?> loadCached(String id) {
    reads++;
    // Match the real disk loader: a successful read fills the RAM cache but
    // does not notify IconLibraryScope listeners.
    bytes ??= coldBytes;
    return pending?.future ??
        Future.value(bytes == null ? null : Uint8List.fromList(bytes!));
  }

  void changed() => notifyListeners();
}

Widget _surface(_Library library, int tick) => IconLibraryScope(
  library: library,
  child: MaterialApp(
    home: Column(
      children: [
        Text('$tick'),
        AppArtwork(appId: 'extra'),
      ],
    ),
  ),
);

void main() {
  testWidgets(
    'cached extra artwork keeps its future and image across clock rebuilds',
    (tester) async {
      final bytes = _png(40);
      final library = _Library(_entry(bytes), bytes: bytes);
      addTearDown(library.dispose);
      await tester.pumpWidget(_surface(library, 0));
      await tester.pumpAndSettle();
      final provider = tester.widget<Image>(find.byType(Image)).image;
      for (var tick = 1; tick <= 5; tick++) {
        await tester.pumpWidget(_surface(library, tick));
        await tester.pump();
        expect(tester.widget<Image>(find.byType(Image)).image, provider);
      }
      expect(library.reads, 1);
    },
  );

  testWidgets(
    'cold disk cache filling RAM does not cause a second artwork read',
    (tester) async {
      final bytes = _png(60);
      final library = _Library(_entry(bytes))..coldBytes = bytes;
      addTearDown(library.dispose);
      expect(library.isDownloaded('extra'), isFalse);
      await tester.pumpWidget(_surface(library, 0));
      await tester.pumpAndSettle();
      expect(library.isDownloaded('extra'), isTrue);
      for (var tick = 1; tick <= 3; tick++) {
        await tester.pumpWidget(_surface(library, tick));
        await tester.pumpAndSettle();
      }
      expect(library.reads, 1);
      expect(find.byType(Image), findsOneWidget);
    },
  );

  testWidgets(
    'missing extra is read once, then download and eviction update artwork',
    (tester) async {
      final bytes = _png(80);
      final library = _Library(_entry(bytes));
      addTearDown(library.dispose);
      await tester.pumpWidget(_surface(library, 0));
      await tester.pumpAndSettle();
      for (var tick = 1; tick <= 5; tick++) {
        await tester.pumpWidget(_surface(library, tick));
        await tester.pumpAndSettle();
      }
      expect(library.reads, 1);
      expect(find.byType(Image), findsNothing);

      library.bytes = bytes;
      library.changed();
      await tester.pumpAndSettle();
      expect(library.reads, 2);
      expect(find.byType(Image), findsOneWidget);

      library.bytes = null;
      library.changed();
      await tester.pump();
      expect(find.byType(Image), findsNothing);
      await tester.pumpAndSettle();
      expect(library.reads, 3);
      library.bytes = bytes;
      library.changed();
      await tester.pumpAndSettle();
      expect(library.reads, 4);
      expect(find.byType(Image), findsOneWidget);
    },
  );

  testWidgets(
    'same extra ID drops old pixels on hash or library scope changes',
    (tester) async {
      final oldBytes = _png(10), nextBytes = _png(220);
      final first = _Library(_entry(oldBytes), bytes: oldBytes);
      final next = _Library(_entry(nextBytes))
        ..pending = Completer<Uint8List?>();
      addTearDown(first.dispose);
      addTearDown(next.dispose);
      await tester.pumpWidget(_surface(first, 0));
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsOneWidget);

      first.entry = _entry(nextBytes);
      first.bytes = null;
      first.pending = Completer<Uint8List?>();
      first.changed();
      await tester.pump();
      expect(find.byType(Image), findsNothing);
      await tester.pumpWidget(_surface(next, 1));
      expect(find.byType(Image), findsNothing);
      first.pending!.complete(oldBytes);
      await tester.pump();
      expect(find.byType(Image), findsNothing);
      next.bytes = nextBytes;
      next.pending!.complete(nextBytes);
      await tester.pumpAndSettle();
      final provider =
          tester.widget<Image>(find.byType(Image)).image as MemoryImage;
      expect(provider.bytes, nextBytes);
      expect(next.reads, 1);
    },
  );
}
