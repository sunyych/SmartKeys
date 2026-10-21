import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image_lib;
import 'package:smart_keys/data/account_backup_codec.dart';
import 'package:smart_keys/data/profile_template_repository.dart';
import 'package:smart_keys/models/config.dart';
import 'package:smart_keys/services/google_account_auth_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'built-in General, Web, and Meetings serialize and decode exactly',
    () async {
      final profiles = await ProfileTemplateRepository().loadAll();
      final config = AppConfig(
        profiles: profiles,
        profileOrder: profiles.map((p) => p.id).toList(),
        activeProfileId: profiles.first.id,
        defaultProfileId: profiles.first.id,
      );
      final selected = profiles
          .where(
            (p) => const {
              'profile_general',
              'profile_web',
              'profile_meetings',
            }.contains(p.id),
          )
          .toList();
      final envelope = AccountBackupCodec.encode(
        config,
        BackupSelection(
          settings: true,
          profileIds: selected.map((p) => p.id).toList(),
        ),
        const {},
      );
      expect(envelope.keys.toSet(), {'schema_version', 'selection', 'data'});
      final data = envelope['data'] as Map<String, Object?>;
      expect(data.keys.toSet(), {'preferences', 'profiles', 'images'});
      final encodedSelection = envelope['selection'] as Map<String, Object?>;
      expect(encodedSelection.keys, isNot(contains('device')));
      expect(
        (envelope['data'] as Map<String, Object?>).keys,
        isNot(contains('device')),
      );
      final parsed = AccountBackupCodec.decode({
        'schema_version': 1,
        'updated_at': '2026-10-21T12:00:00Z',
        'backup': envelope,
      }, updatedAt: '2026-10-21T12:00:00Z');
      expect(parsed.profiles.map((p) => p.id), selected.map((p) => p.id));
      expect(parsed.profiles.first.buttons.first.action.value, 'MUTE');
      expect(parsed.profiles.first.wheel.up.value, 'UP');
      expect(
        jsonEncode(parsed.profiles.map((p) => p.toJson()).toList()),
        jsonEncode(selected.map((p) => p.toJson()).toList()),
      );
    },
  );

  test(
    'selected button and Profile icon images round-trip; settings-only excludes Profiles',
    () async {
      final base = (await ProfileTemplateRepository().loadAll()).first;
      final imagePath = 'images/custom/photo.png';
      final bytes = Uint8List.fromList(
        image_lib.encodePng(image_lib.Image(width: 1, height: 1)),
      );
      final withImage = base.copyWith(
        profileIcon: ButtonVisual(
          type: VisualType.customImage,
          value: imagePath,
        ),
        buttons: [
          base.buttons.first.copyWith(
            visual: ButtonVisual(
              type: VisualType.customImage,
              value: imagePath,
            ),
          ),
        ],
      );
      final config = AppConfig(
        profiles: [withImage],
        profileOrder: [withImage.id],
        activeProfileId: withImage.id,
        defaultProfileId: withImage.id,
      );
      final selection = BackupSelection(
        settings: false,
        profileIds: [withImage.id],
        images: true,
      );
      final payload = AccountBackupCodec.encode(config, selection, {
        imagePath: bytes,
      });
      final decoded = AccountBackupCodec.decode({
        'schema_version': 1,
        'updated_at': 'x',
        'backup': payload,
      }, updatedAt: 'x');
      expect(decoded.images[imagePath], bytes);
      expect(decoded.profiles.single.profileIcon.value, imagePath);
      expect(decoded.profiles.single.buttons.first.visual.value, imagePath);

      final settingsOnly = AccountBackupCodec.encode(
        config,
        const BackupSelection(settings: true),
        {imagePath: bytes},
      );
      final data = settingsOnly['data'] as Map<String, Object?>;
      expect(data['profiles'], isEmpty);
      expect(data['images'], isEmpty);
    },
  );

  test('Desktop JSON actions round-trip without executing', () async {
    final base = (await ProfileTemplateRepository().loadAll()).first;
    const desktopActions = [
      '{"kind":"launch","target":"ChatGPT"}',
      '{"kind":"voiceInput"}',
      '{"kind":"shortcut","keys":["CTRL","ALT","T"]}',
    ];
    final buttons = [...base.buttons];
    for (var i = 0; i < desktopActions.length; i++) {
      buttons[i] = buttons[i].copyWith(
        action: HidAction(type: ActionType.companion, value: desktopActions[i]),
      );
    }
    final wheelAction = const HidAction(
      type: ActionType.companion,
      value: '{"kind":"launch","target":"Firefox"}',
    );
    final profile = base.copyWith(
      buttons: buttons,
      wheel: WheelConfig.fromJson({
        ...base.wheel.toJson(),
        'clockwise': wheelAction.toJson(),
      }),
    );
    final config = AppConfig(
      profiles: [profile],
      profileOrder: [profile.id],
      activeProfileId: profile.id,
      defaultProfileId: profile.id,
    );
    final encoded = AccountBackupCodec.encode(
      config,
      BackupSelection(profileIds: [profile.id]),
      const {},
    );
    final decoded = AccountBackupCodec.decode({
      'schema_version': 1,
      'updated_at': 'x',
      'backup': encoded,
    }, updatedAt: 'x');
    expect(
      decoded.profiles.single.buttons
          .take(desktopActions.length)
          .map((button) => button.action.value),
      desktopActions,
    );
    expect(decoded.profiles.single.wheel.clockwise.value, wheelAction.value);
    expect(
      jsonEncode(decoded.profiles.single.toJson()),
      jsonEncode(profile.toJson()),
    );
  });

  test('invalid or oversized Desktop JSON is rejected', () async {
    final base = (await ProfileTemplateRepository().loadAll()).first;
    for (final value in [
      'not JSON',
      '[]',
      '{}',
      jsonEncode({'value': 'x' * AccountBackupCodec.maxCompanionPayloadBytes}),
    ]) {
      final profile = base.copyWith(
        buttons: [
          base.buttons.first.copyWith(
            action: HidAction(type: ActionType.companion, value: value),
          ),
        ],
      );
      final config = AppConfig(
        profiles: [profile],
        profileOrder: [profile.id],
        activeProfileId: profile.id,
        defaultProfileId: profile.id,
      );
      expect(
        () => AccountBackupCodec.encode(
          config,
          BackupSelection(profileIds: [profile.id]),
          const {},
        ),
        throwsFormatException,
      );
    }
  });

  test('keyboard actions reject more than eight modifiers', () async {
    final base = (await ProfileTemplateRepository().loadAll()).first;
    AppConfig configWithModifiers(int count) {
      final profile = base.copyWith(
        buttons: [
          base.buttons.first.copyWith(
            action: HidAction(
              type: ActionType.keyboard,
              keyCode: 'KEY_A',
              modifiers: List.filled(count, 'SHIFT'),
            ),
          ),
        ],
      );
      return AppConfig(
        profiles: [profile],
        profileOrder: [profile.id],
        activeProfileId: profile.id,
        defaultProfileId: profile.id,
      );
    }

    expect(
      () => AccountBackupCodec.encode(
        configWithModifiers(9),
        BackupSelection(profileIds: [base.id]),
        const {},
      ),
      throwsFormatException,
    );
    expect(
      () => AccountBackupCodec.encode(
        configWithModifiers(8),
        BackupSelection(profileIds: [base.id]),
        const {},
      ),
      returnsNormally,
    );
  });

  test(
    'decoder rejects missing fields, unknown config keys, and unsafe paths',
    () async {
      final profiles = await ProfileTemplateRepository().loadAll();
      final general = profiles.first;
      final config = AppConfig(
        profiles: [general],
        profileOrder: [general.id],
        activeProfileId: general.id,
        defaultProfileId: general.id,
      );
      final envelope = AccountBackupCodec.encode(
        config,
        BackupSelection(profileIds: [general.id]),
        const {},
      );
      final bad = jsonDecode(jsonEncode(envelope)) as Map<String, dynamic>;
      (bad['data']['profiles'][0] as Map<String, dynamic>)['unknown'] = true;
      expect(
        () => AccountBackupCodec.decode({
          'schema_version': 1,
          'updated_at': 'x',
          'backup': bad,
        }, updatedAt: 'x'),
        throwsFormatException,
      );

      final unsafe = general.copyWith(
        buttons: [
          general.buttons.first.copyWith(
            visual: const ButtonVisual(
              type: VisualType.customImage,
              value: r'images\..\escape.png',
            ),
          ),
        ],
      );
      final unsafeConfig = AppConfig(
        profiles: [unsafe],
        profileOrder: [unsafe.id],
        activeProfileId: unsafe.id,
        defaultProfileId: unsafe.id,
      );
      expect(
        () => AccountBackupCodec.encode(
          unsafeConfig,
          BackupSelection(profileIds: [unsafe.id]),
          const {},
        ),
        throwsFormatException,
      );
    },
  );

  test('Google iOS reversed client scheme retains full OAuth prefix', () {
    expect(
      GoogleAccountAuthService.reversedSchemeForClientId(
        '123456.apps.googleusercontent.com',
      ),
      'com.googleusercontent.apps.123456',
    );
  });

  test(
    'missing OAuth client configuration fails before invoking native sign-in',
    () async {
      final service = GoogleAccountAuthService(
        webClientId: '',
        iosClientId: '',
      );
      expect(
        service.configurationError,
        contains('SMARTKEYS_GOOGLE_WEB_CLIENT_ID'),
      );
      await expectLater(service.signIn(), throwsStateError);
      expect(service.idToken, isNull);
    },
  );
}
