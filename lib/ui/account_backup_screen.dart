import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../app.dart';
import '../controllers/app_controller.dart';
import '../data/account_backup_client.dart';
import '../data/account_backup_codec.dart';
import '../services/google_account_auth_service.dart';

class AccountBackupScreen extends StatefulWidget {
  const AccountBackupScreen({super.key, this.auth, this.client});

  final GoogleAccountAuthenticator? auth;
  final AccountBackupClient? client;

  @override
  State<AccountBackupScreen> createState() => _AccountBackupScreenState();
}

class _AccountBackupScreenState extends State<AccountBackupScreen> {
  late final GoogleAccountAuthenticator _auth;
  late final AccountBackupClient _client;
  final Set<String> _profileIds = {};
  bool _settings = true;
  bool _images = false;
  bool _busy = false;
  String? _message;
  Object? _error;
  bool _ownsClient = false;

  @override
  void initState() {
    super.initState();
    _auth = widget.auth ?? GoogleAccountAuthService.shared;
    _ownsClient = widget.client == null;
    _client = widget.client ?? AccountBackupClient(auth: _auth);
  }

  @override
  void dispose() {
    if (_ownsClient) _client.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = SmartKeysScope.of(context);
    final profiles = controller.orderedProfiles;
    final googleAuth = _auth is GoogleAccountAuthService ? _auth : null;
    final authConfigured = googleAuth?.configurationError == null;
    final canOperate = _client.isConfigured && authConfigured;
    return Scaffold(
      appBar: AppBar(title: const Text('Google account backup')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Back up selected items to the configured service using Google sign-in. This is separate from anonymous community rankings. Nothing uploads automatically.',
          ),
          const SizedBox(height: 16),
          if (_auth.displayEmail case final email?)
            ListTile(
              leading: const Icon(Icons.account_circle_outlined),
              title: Text(email),
              subtitle: const Text('Signed in on this device'),
              trailing: Wrap(
                spacing: 4,
                children: [
                  TextButton(
                    onPressed: _busy || !canOperate ? null : _signIn,
                    child: const Text('Switch account'),
                  ),
                  TextButton(
                    onPressed: _busy ? null : _signOut,
                    child: const Text('Sign out'),
                  ),
                ],
              ),
            )
          else
            FilledButton.tonalIcon(
              onPressed: _busy || !canOperate ? null : _signIn,
              icon: const Icon(Icons.login),
              label: const Text('Sign in with Google'),
            ),
          if (googleAuth?.configurationError != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                'Google sign-in is not available in this build.',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (!_client.isConfigured)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                'Online backup service is not configured for this build.',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          const Divider(height: 32),
          SwitchListTile(
            title: const Text('App settings'),
            value: _settings,
            onChanged: _busy ? null : (v) => setState(() => _settings = v),
          ),
          ...profiles.map(
            (profile) => CheckboxListTile(
              title: Text(profile.name),
              value: _profileIds.contains(profile.id),
              onChanged: _busy
                  ? null
                  : (checked) => setState(() {
                      if (checked == true) {
                        if (_profileIds.length < 4) _profileIds.add(profile.id);
                      } else {
                        _profileIds.remove(profile.id);
                      }
                    }),
            ),
          ),
          SwitchListTile(
            title: const Text('Include custom button images'),
            subtitle: const Text(
              'Images are optional; each image is limited to 4 MiB.',
            ),
            value: _images,
            onChanged: _busy ? null : (v) => setState(() => _images = v),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busy || !canOperate ? null : () => _backup(controller),
            icon: const Icon(Icons.cloud_upload_outlined),
            label: const Text('Preview and back up'),
          ),
          OutlinedButton.icon(
            onPressed: _busy || !canOperate ? null : () => _restore(controller),
            icon: const Icon(Icons.cloud_download_outlined),
            label: const Text('Preview and restore'),
          ),
          TextButton.icon(
            onPressed: _busy || !canOperate ? null : _delete,
            icon: const Icon(Icons.delete_outline),
            label: const Text('Delete online backup'),
          ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (_message case final message?)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(message),
            ),
          if (_error case final error?)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                '$error',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _signIn() async => _run(() async {
    await _auth.signIn();
    _message = 'Google account connected for this session.';
  });
  Future<void> _signOut() async => _run(() async {
    await _auth.signOut();
    _message = 'Signed out. Online backup is unchanged.';
  });

  Future<void> _backup(AppController controller) => _run(() async {
    await _ensureSignedIn();
    if (!_settings && _profileIds.isEmpty) {
      throw const FormatException('Select settings or at least one Profile.');
    }
    final selection = BackupSelection(
      settings: _settings,
      profileIds: _orderedSelectedIds(controller),
      images: _images,
    );
    final profilesToBackUp = controller.config.profiles.where(
      (p) => selection.profileIds.contains(p.id),
    );
    final Map<String, Uint8List> images = _images
        ? await controller.imageStore.readSelectedImages(profilesToBackUp)
        : const {};
    final envelope = await AccountBackupCodec.encodeAsync(
      controller.config,
      selection,
      images,
    );
    final data = envelope['data'] as Map<String, Object?>;
    final serializedProfiles = (data['profiles'] as List)
        .cast<Map<String, dynamic>>();
    final previewProfiles = serializedProfiles
        .map(
          (profile) => <String, Object?>{
            'id': profile['id'],
            'name': profile['name'],
            'targetApplication': profile['targetApplication'],
            'profileIcon': profile['profileIcon'],
            'buttons': (profile['buttons'] as List).map((button) {
              final item = button as Map<String, dynamic>;
              return {
                'position': item['position'],
                'label': item['label'],
                'subtitle': item['subtitle'],
                'visual': item['visual'],
                'action': item['action'],
              };
            }).toList(),
            'wheel': profile['wheel'],
          },
        )
        .toList();
    final imagePreview = (data['images'] as List)
        .cast<Map<String, dynamic>>()
        .map((image) {
          final encoded = image['data_base64'] as String;
          final padding = encoded.endsWith('==')
              ? 2
              : encoded.endsWith('=')
              ? 1
              : 0;
          return {
            'path': image['path'],
            'mime_type': image['mime_type'],
            'size_bytes': encoded.length * 3 ~/ 4 - padding,
          };
        })
        .toList();
    final preview = <String, Object?>{
      'selected_google_account':
          _auth.displayEmail ?? 'Google account for this sign-in session',
      'selection': envelope['selection'],
      'preferences': data['preferences'],
      'profiles': previewProfiles,
      'images': imagePreview,
      'image_bytes_are_not_rendered': true,
    };
    final accepted = await _confirm(
      'Review backup contents',
      'This replaces the previous online backup for this Google account. '
          'Only the selected items will be kept.\n\n'
          '${const JsonEncoder.withIndent('  ').convert(preview)}',
    );
    if (!accepted) return;
    final updated = await _client.putEnvelope(envelope);
    _message = 'Backup updated: $updated';
  });

  Future<void> _restore(AppController controller) => _run(() async {
    await _ensureSignedIn();
    final backup = await _client.get();
    if (backup == null) {
      _message = 'No online backup exists for this Google account.';
      return;
    }
    if (!mounted) return;
    final chosen = await showDialog<_RestoreChoice>(
      context: context,
      builder: (context) => _RestorePreviewDialog(backup: backup),
    );
    if (chosen == null) return;
    await controller.restoreAccountBackup(
      backup,
      restoreSettings: chosen.settings,
      profileIds: chosen.profileIds,
      restoreImages: chosen.images,
    );
    _message =
        'Selected backup items were restored. Device pairing and local usage history were kept.';
  });

  Future<void> _delete() => _run(() async {
    await _ensureSignedIn();
    final accepted = await _confirm(
      'Delete online backup?',
      'This permanently deletes the latest settings and Profile backup stored for the signed-in Google account.',
    );
    if (!accepted) return;
    await _client.delete();
    _message = 'Online backup deleted.';
  });

  List<String> _orderedSelectedIds(AppController controller) => controller
      .orderedProfiles
      .where((p) => _profileIds.contains(p.id))
      .map((p) => p.id)
      .toList();

  Future<void> _ensureSignedIn() async {
    if (_auth.idToken == null) await _auth.signIn();
  }

  Future<bool> _confirm(String title, String content) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(child: SelectableText(content)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Continue'),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _run(Future<void> Function() work) async {
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      await work();
    } catch (error) {
      _error = error;
    }
    if (mounted) setState(() => _busy = false);
  }
}

class _RestoreChoice {
  const _RestoreChoice(this.settings, this.profileIds, this.images);
  final bool settings;
  final Set<String> profileIds;
  final bool images;
}

class _RestorePreviewDialog extends StatefulWidget {
  const _RestorePreviewDialog({required this.backup});
  final DecodedAccountBackup backup;
  @override
  State<_RestorePreviewDialog> createState() => _RestorePreviewDialogState();
}

class _RestorePreviewDialogState extends State<_RestorePreviewDialog> {
  late bool _settings;
  late bool _images;
  final Set<String> _profiles = {};
  @override
  void initState() {
    super.initState();
    _settings = widget.backup.preferences != null;
    _images = widget.backup.images.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Review restore'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Backup from ${widget.backup.updatedAt}. This merges selected Profiles by ID and preserves device pairing and local usage.',
          ),
          if (widget.backup.preferences != null)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('App settings'),
              value: _settings,
              onChanged: (v) => setState(() => _settings = v ?? false),
            ),
          ...widget.backup.profiles.map(
            (p) => CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(p.name),
              value: _profiles.contains(p.id),
              onChanged: (v) => setState(() {
                if (v == true) {
                  _profiles.add(p.id);
                } else {
                  _profiles.remove(p.id);
                }
              }),
            ),
          ),
          if (widget.backup.images.isNotEmpty)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                'Restore ${widget.backup.images.length} custom images',
              ),
              value: _images,
              onChanged: (v) => setState(() => _images = v ?? false),
            ),
          const Text(
            'Restored shortcuts are saved but never executed automatically.',
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _settings || _profiles.isNotEmpty
            ? () => Navigator.pop(
                context,
                _RestoreChoice(_settings, Set.of(_profiles), _images),
              )
            : null,
        child: const Text('Restore selected'),
      ),
    ],
  );
}
