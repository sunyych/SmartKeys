import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumiakeys_protocol/lumiakeys_protocol.dart';
import 'package:smart_keys/app_library/app_library.dart';
import 'package:smart_keys/icons/source_profile_icon.dart';

void main() {
  test(
    'all registered App icons and OS libraries survive Desktop wire to Full',
    () {
      final catalog = AppLibraryCatalog.builtin;
      final starter = DesktopManifest.regularStarter();
      expect(catalog.apps, hasLength(60));
      for (final app in catalog.apps) {
        final png = File(
          'packages/app_icon_catalog/png/${app.id}.png',
        ).readAsBytesSync();
        final hash = sha256.convert(png).toString();
        expect(hash, registeredAppIconHash(app.iconId), reason: app.id);
        for (final os in appLibraryOperatingSystems) {
          final library = app.libraryForOS(os);
          if (!app.supportedOS.contains(os)) {
            expect(library, isNull, reason: '${app.id}: $os');
            continue;
          }
          final profileId = 'received.${app.id}.$os';
          final layout = RemoteShortcutLayout(
            id: profileId,
            name: app.name,
            kind: RemoteLayoutKind.application,
            buttons: [
              for (final action in library!.actions)
                RemoteShortcutButton(
                  id: '$profileId.${action.id}',
                  name: action.title,
                  icon: 'keyboard',
                  targetType: RemoteTargetType.keyboardShortcut,
                  shortcut: action.keys.map(canonicalKeyToLiteral).toList(),
                  enabled: action.isConfigured,
                ),
            ],
          );
          final profile = RemoteProfile(
            id: profileId,
            name: app.name,
            layoutId: layout.id,
            platform: os,
            sourceAppId: app.id,
            sourceIconId: app.iconId,
            sourceLibraryId: library.id,
            sourceLibraryVersion: library.version,
            sourceActionHashes: {
              for (final action in library.actions)
                action.id: registeredAppActionHash(library.id, action.id)!,
            },
            sourceIconPngBase64: base64Encode(png),
            sourceIconSha256: hash,
          );
          final received = DesktopManifest.fromJson(
            jsonDecode(
                  jsonEncode(
                    starter
                        .copyWith(
                          profiles: [...starter.profiles, profile],
                          layouts: [...starter.layouts, layout],
                        )
                        .toJson(forSync: true),
                  ),
                )
                as Map<String, dynamic>,
          );
          final wireProfile = received.profiles.singleWhere(
            (candidate) => candidate.id == profileId,
          );
          expect(wireProfile.platform, os);
          expect(wireProfile.sourceAppId, app.id);
          expect(wireProfile.sourceIconId, app.id);
          expect(wireProfile.sourceLibraryId, library.id);
          expect(wireProfile.sourceActionHashes, profile.sourceActionHashes);
          expect(sourceProfileIcon(wireProfile), png, reason: '${app.id}: $os');
          final wireButtons = received.layoutById(layout.id)!.buttons;
          expect(wireButtons, hasLength(library.actions.length));
          for (var index = 0; index < wireButtons.length; index++) {
            expect(
              wireButtons[index].enabled,
              library.actions[index].isConfigured,
            );
            expect(
              wireButtons[index].shortcut,
              library.actions[index].keys.map(canonicalKeyToLiteral),
            );
          }
        }
      }
    },
  );

  test(
    'warm received icon cache cannot authorize tampered bytes or another ID',
    () {
      final png = File(
        'packages/app_icon_catalog/png/gimp.png',
      ).readAsBytesSync();
      final hash = registeredAppIconHash('gimp')!;
      RemoteProfile profile({required String encoded, String icon = 'gimp'}) =>
          RemoteProfile(
            id: 'received.gimp',
            name: 'Gimp',
            layoutId: 'received.gimp',
            platform: 'windows',
            sourceAppId: 'gimp',
            sourceIconId: icon,
            sourceLibraryId: 'gimp.windowsLinux',
            sourceLibraryVersion: '1',
            sourceIconPngBase64: encoded,
            sourceIconSha256: hash,
          );
      final valid = profile(encoded: base64Encode(png));
      final cached = sourceProfileIcon(valid)!;
      expect(cached, png);
      expect(() => cached[0] = 0, throwsUnsupportedError);
      final corrupted = png.toList()..[png.length - 1] ^= 1;
      expect(
        sourceProfileIcon(profile(encoded: base64Encode(corrupted))),
        isNull,
      );
      expect(
        sourceProfileIcon(profile(encoded: base64Encode(png), icon: 'word')),
        isNull,
      );
      expect(sourceProfileIcon(profile(encoded: 'A' * 87385)), isNull);
      expect(sourceProfileIcon(valid), png);
    },
  );
}
