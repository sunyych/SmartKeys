import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumiakeys_companion/main.dart';
import 'package:lumiakeys_protocol/lumiakeys_protocol.dart';

void main() {
  const transfer = DesktopShortcutTransferService();

  test('Desktop shortcut JSON round trips layouts only', () {
    final manifest = DesktopManifest.starter();
    final layouts = transfer.decode(transfer.encode(manifest));

    expect(
      layouts.map((layout) => layout.id),
      manifest.layouts.map((e) => e.id),
    );
    expect(
      layouts.firstWhere((layout) => layout.id == 'codex').buttons.first.id,
      'codex.focusInput',
    );
    expect(transfer.encode(manifest), isNot(contains('"executable"')));
    expect(
      layouts.firstWhere((layout) => layout.id == 'vibe.claude').buttons,
      hasLength(19),
    );
  });

  test('shortcut JSON keeps bounded layouts and fixed system actions', () {
    final manifest = DesktopManifest.starter();
    final layouts = manifest.layouts.map((layout) {
      if (layout.id != 'keyboard') return layout.toJson();
      final json = layout.toJson();
      json['buttons'] = [
        ...layout.buttons,
        ...List.generate(16, (i) => layout.buttons[i % layout.buttons.length]),
      ].map((button) => button.toJson()).toList();
      return json;
    }).toList();
    final oversized = jsonEncode({
      'format': DesktopShortcutTransferService.format,
      'version': DesktopShortcutTransferService.version,
      'layouts': layouts,
    });
    expect(() => transfer.decode(oversized), throwsFormatException);

    final encoded =
        jsonDecode(transfer.encode(manifest)) as Map<String, Object?>;
    final vibeCodex = (encoded['layouts'] as List)
        .cast<Map<String, Object?>>()
        .firstWhere((layout) => layout['id'] == 'vibe.codex');
    final comma = (vibeCodex['buttons'] as List)
        .cast<Map<String, Object?>>()
        .firstWhere((button) => button['id'] == 'vibe.codex.comma');
    comma['target'] = 'arbitrary-script';
    expect(() => transfer.decode(jsonEncode(encoded)), throwsFormatException);
  });

  test(
    'Desktop import rejects unknown layouts and application targets',
    () async {
      final controller = DesktopController(
        store: MemoryDesktopConfigStore(),
        discovery: _NoopDiscovery(),
      );
      addTearDown(controller.dispose);
      await controller.initialize();

      await expectLater(
        controller.importShortcutLayouts(const [
          RemoteShortcutLayout(
            id: 'unknown',
            name: 'Unknown',
            kind: RemoteLayoutKind.application,
            buttons: [],
          ),
        ]),
        throwsFormatException,
      );
      final codex = controller.manifest.layoutById('codex')!;
      await expectLater(
        controller.importShortcutLayouts([
          codex.copyWith(
            buttons: const [
              RemoteShortcutButton(
                id: 'codex.badLaunch',
                name: 'Bad Launch',
                icon: 'code',
                targetType: RemoteTargetType.launchApplication,
                target: '/tmp/arbitrary-app',
              ),
            ],
          ),
        ]),
        throwsFormatException,
      );

      final keyboard = controller.manifest.layoutById('keyboard')!;
      await controller.importShortcutLayouts([
        keyboard.copyWith(
          buttons: [
            keyboard.buttons.first.copyWith(name: 'Imported Copy'),
            ...keyboard.buttons.skip(1),
          ],
        ),
      ]);
      expect(
        controller.manifest.buttonById('keyboard.copy')!.name,
        'Imported Copy',
      );
    },
  );
}

class _NoopDiscovery implements ApplicationDiscovery {
  @override
  Future<List<RemoteApplication>> refresh(List<RemoteApplication> apps) async =>
      apps;
}
