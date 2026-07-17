import 'package:flutter/material.dart';

import '../app.dart';
import '../data/community_profile_repository.dart';
import '../data/profile_transfer_service.dart';
import '../icons/icon_catalog.dart';
import '../models/config.dart';
import 'profile_import_flow.dart';

class ShortcutCommunityScreen extends StatefulWidget {
  const ShortcutCommunityScreen({super.key});

  @override
  State<ShortcutCommunityScreen> createState() =>
      _ShortcutCommunityScreenState();
}

class _ShortcutCommunityScreenState extends State<ShortcutCommunityScreen> {
  static const transfer = ProfileTransferService();
  late final Future<List<ProfileConfig>> packs = CommunityProfileRepository()
      .loadAll();
  bool busy = false;

  @override
  Widget build(BuildContext context) {
    final controller = SmartKeysScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Shortcut Community')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.groups_outlined),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Exchange complete shortcut Profiles as JSON. Paste a '
                      'shared profile, import a file, or copy your active '
                      'Profile to share in any community or chat.',
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                key: const ValueKey('community-paste-json'),
                onPressed: busy ? null : () => _importClipboard(context),
                icon: const Icon(Icons.content_paste),
                label: const Text('Paste JSON'),
              ),
              OutlinedButton.icon(
                key: const ValueKey('community-import-file'),
                onPressed: busy ? null : () => _importFile(context),
                icon: const Icon(Icons.file_download_outlined),
                label: const Text('Import file'),
              ),
              OutlinedButton.icon(
                key: const ValueKey('community-copy-json'),
                onPressed: busy
                    ? null
                    : () => _copyActive(context, controller.activeProfile),
                icon: const Icon(Icons.copy_all_outlined),
                label: const Text('Copy active JSON'),
              ),
              OutlinedButton.icon(
                key: const ValueKey('community-export-file'),
                onPressed: busy
                    ? null
                    : () => _exportActive(context, controller.activeProfile),
                icon: const Icon(Icons.ios_share_outlined),
                label: const Text('Export file'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.lock_outline),
            title: const Text('Free Profile slots'),
            subtitle: const Text(
              'Imports can replace any existing slot when all four are full.',
            ),
            trailing: Chip(
              label: Text(
                '${controller.config.profiles.length}/$freeProfileLimit',
              ),
            ),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 10),
            child: Text(
              'CURATED COMMUNITY PACKS',
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                fontSize: 12,
              ),
            ),
          ),
          FutureBuilder<List<ProfileConfig>>(
            future: packs,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Text(
                  'Could not load community packs: ${snapshot.error}',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              return Column(
                children: snapshot.data!
                    .map(
                      (profile) => _CommunityPackCard(
                        profile: profile,
                        busy: busy,
                        onInstall: () =>
                            _run(context, () => _install(context, profile)),
                      ),
                    )
                    .toList(growable: false),
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _importClipboard(BuildContext context) =>
      _run(context, () async {
        final profile = await transfer.importProfileFromClipboard();
        if (context.mounted) await _install(context, profile);
      });

  Future<void> _importFile(BuildContext context) => _run(context, () async {
    final profile = await transfer.importProfile();
    if (profile != null && context.mounted) await _install(context, profile);
  });

  Future<void> _copyActive(BuildContext context, ProfileConfig profile) => _run(
    context,
    () async {
      await transfer.copyProfileJson(profile);
      if (context.mounted) _showMessage(context, '${profile.name} JSON copied');
    },
  );

  Future<void> _exportActive(BuildContext context, ProfileConfig profile) =>
      _run(context, () async {
        final exported = await transfer.exportProfile(profile);
        if (exported && context.mounted) {
          _showMessage(context, '${profile.name} JSON exported');
        }
      });

  Future<void> _install(BuildContext context, ProfileConfig profile) async {
    final installed = await installSharedProfile(context, profile);
    if (installed && context.mounted) {
      _showMessage(context, '${profile.name} installed');
    }
  }

  Future<void> _run(
    BuildContext context,
    Future<void> Function() operation,
  ) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await operation();
    } catch (error) {
      if (context.mounted) _showMessage(context, '$error');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _CommunityPackCard extends StatelessWidget {
  const _CommunityPackCard({
    required this.profile,
    required this.busy,
    required this.onInstall,
  });

  final ProfileConfig profile;
  final bool busy;
  final VoidCallback onInstall;

  @override
  Widget build(BuildContext context) {
    final icon =
        BuiltinIconCatalog.find(profile.profileIcon.value)?.icon ??
        Icons.groups_outlined;
    final configured = profile.buttons
        .where((button) => button.action.type != ActionType.none)
        .length;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: CircleAvatar(child: Icon(icon)),
        title: Text(profile.name),
        subtitle: Text(
          '${profile.targetApplication ?? 'Community pack'} · '
          '$configured shortcuts',
        ),
        trailing: FilledButton.tonal(
          key: ValueKey('install-community-${profile.id}'),
          onPressed: busy ? null : onInstall,
          child: const Text('Install'),
        ),
      ),
    );
  }
}
