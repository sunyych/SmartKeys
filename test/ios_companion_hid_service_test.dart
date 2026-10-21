import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_keys/models/config.dart';
import 'package:smart_keys/services/companion_service.dart';
import 'package:smart_keys/services/hid_service.dart';
import 'package:smart_keys/services/ios_companion_hid_service.dart';

void main() {
  test('iPad maps a keyboard chord to one Desktop shortcut action', () async {
    final companion = RecordingCompanionService()
      ..host.value = const CompanionHost(
        name: 'Desktop',
        platform: 'windows',
        address: '192.168.1.2',
        port: 40000,
        token: 'test',
      )
      ..status.value = CompanionSyncStatus.ready;
    final hid = IosCompanionHidService(companion);
    addTearDown(() {
      hid.dispose();
      companion.dispose();
    });

    await hid.sendPress(
      const HidAction(
        type: ActionType.keyboard,
        keyCode: 'KEY_A',
        modifiers: ['CTRL', 'SHIFT'],
      ),
    );
    await hid.sendRelease(
      const HidAction(type: ActionType.keyboard, keyCode: 'KEY_A'),
    );

    expect(companion.commands, [
      jsonEncode({
        'kind': 'shortcut',
        'keys': ['CTRL', 'SHIFT', 'A'],
      }),
    ]);
    await hid.sendPress(
      const HidAction(
        type: ActionType.keyboard,
        keyCode: 'KEY_C',
        modifiers: ['LEFT_META'],
      ),
    );
    expect(
      companion.commands.last,
      jsonEncode({
        'kind': 'shortcut',
        'keys': ['META', 'C'],
      }),
    );
  });

  test('iPad refuses non-keyboard and text batch input visibly', () async {
    final companion = RecordingCompanionService();
    final hid = IosCompanionHidService(companion);
    addTearDown(() {
      hid.dispose();
      companion.dispose();
    });

    await hid.sendPress(
      const HidAction(type: ActionType.mouseWheel, value: '1'),
    );
    expect(hid.errorMessage.value, contains('keyboard shortcuts only'));
    await expectLater(
      hid.sendTextBatch(
        sessionToken: 'session',
        expectedAddress: '192.168.1.2',
        profile: HidTextProfile.usAscii,
        strokes: const [],
        codePoints: const [],
      ),
      throwsUnsupportedError,
    );
  });
}
