import 'package:flutter/material.dart';

import '../app.dart';
import '../data/profile_transfer_service.dart';
import '../icons/icon_catalog.dart';
import '../models/config.dart';
import 'profile_editor_screen.dart';
import 'profile_import_flow.dart';
import 'shortcut_community_screen.dart';

class ProfileManagementScreen extends StatelessWidget {
  const ProfileManagementScreen({super.key});

  static const transfer = ProfileTransferService();

  @override
  Widget build(BuildContext context) {
    final controller = SmartKeysScope.of(context);
    final byId = {
      for (final profile in controller.config.profiles) profile.id: profile,
    };
    final profiles = controller.config.profileOrder
        .map((id) => byId[id])
        .whereType<ProfileConfig>()
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profiles'),
        actions: [
          IconButton(
            tooltip: 'Shortcut Community',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const ShortcutCommunityScreen(),
              ),
            ),
            icon: const Icon(Icons.groups_outlined),
          ),
          IconButton(
            tooltip: 'Import profile',
            onPressed: () => _import(context),
            icon: const Icon(Icons.file_download_outlined),
          ),
        ],
      ),
      body: ReorderableListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: profiles.length,
        onReorderItem: controller.reorderProfiles,
        itemBuilder: (context, index) {
          final profile = profiles[index];
          final active = profile.id == controller.config.activeProfileId;
          final isDefault = profile.id == controller.config.defaultProfileId;
          final icon =
              BuiltinIconCatalog.find(profile.profileIcon.value)?.icon ??
              Icons.dashboard_customize_outlined;
          return Card(
            key: ValueKey(profile.id),
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: profile.accentColor == null
                    ? null
                    : Color(profile.accentColor!).withValues(alpha: 0.25),
                child: Icon(icon),
              ),
              title: Row(
                children: [
                  Flexible(child: Text(profile.name)),
                  if (active) ...[
                    const SizedBox(width: 8),
                    const Chip(
                      label: Text('Active'),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ],
              ),
              subtitle: Text(
                [
                  if (profile.targetApplication != null)
                    profile.targetApplication!,
                  if (isDefault) 'Default',
                  if (profile.isBuiltInTemplate) 'Built-in template',
                ].join(' · '),
              ),
              onTap: () => controller.switchProfile(profile.id),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Edit profile',
                    onPressed: () => _edit(context, profile.id),
                    icon: const Icon(Icons.edit_outlined),
                  ),
                  PopupMenuButton<_ProfileAction>(
                    onSelected: (action) =>
                        _handleAction(context, profile, action),
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: _ProfileAction.duplicate,
                        enabled: controller.canAddProfile,
                        child: const Text('Duplicate'),
                      ),
                      const PopupMenuItem(
                        value: _ProfileAction.makeDefault,
                        child: Text('Make default'),
                      ),
                      const PopupMenuItem(
                        value: _ProfileAction.export,
                        child: Text('Export'),
                      ),
                      if (defaultFreeProfileIds.contains(profile.id))
                        const PopupMenuItem(
                          value: _ProfileAction.restore,
                          child: Text('Restore template'),
                        ),
                      const PopupMenuDivider(),
                      const PopupMenuItem(
                        value: _ProfileAction.delete,
                        child: Text('Delete'),
                      ),
                    ],
                  ),
                  ReorderableDragStartListener(
                    index: index,
                    child: const Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(Icons.drag_handle),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: controller.canAddProfile ? () => _create(context) : null,
        icon: Icon(controller.canAddProfile ? Icons.add : Icons.lock_outline),
        label: Text(
          controller.canAddProfile
              ? 'New Profile'
              : '${controller.config.profiles.length}/$freeProfileLimit limit',
        ),
      ),
    );
  }

  Future<void> _create(BuildContext context) async {
    final profile = await SmartKeysScope.of(context).createProfile();
    if (context.mounted) await _edit(context, profile.id);
  }

  Future<void> _edit(BuildContext context, String profileId) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ProfileEditorScreen(profileId: profileId),
        ),
      );

  Future<void> _handleAction(
    BuildContext context,
    ProfileConfig profile,
    _ProfileAction action,
  ) async {
    final controller = SmartKeysScope.of(context);
    switch (action) {
      case _ProfileAction.duplicate:
        final duplicate = await controller.duplicateProfile(profile);
        if (context.mounted) await _edit(context, duplicate.id);
      case _ProfileAction.makeDefault:
        await controller.setDefaultProfile(profile.id);
      case _ProfileAction.export:
        try {
          final exported = await transfer.exportProfile(profile);
          if (exported && context.mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('Profile exported')));
          }
        } catch (error) {
          if (context.mounted) _showError(context, error);
        }
      case _ProfileAction.restore:
        final confirmed = await _confirm(
          context,
          'Restore ${profile.name}?',
          'Current edits to this built-in profile will be replaced.',
        );
        if (confirmed) await controller.restoreTemplate(profile.id);
      case _ProfileAction.delete:
        final confirmed = await _confirm(
          context,
          'Delete ${profile.name}?',
          'This removes its buttons, navigation control configuration, and unused images.',
        );
        if (!confirmed) return;
        try {
          await controller.deleteProfile(profile.id);
        } catch (error) {
          if (context.mounted) _showError(context, error);
        }
    }
  }

  Future<void> _import(BuildContext context) async {
    try {
      final profile = await transfer.importProfile();
      if (profile == null || !context.mounted) return;
      final installed = await installSharedProfile(context, profile);
      if (!installed || !context.mounted) return;
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('${profile.name} imported')));
      }
    } catch (error) {
      if (context.mounted) _showError(context, error);
    }
  }

  Future<bool> _confirm(
    BuildContext context,
    String title,
    String body,
  ) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(body),
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

  void _showError(BuildContext context, Object error) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$error')));
  }
}

enum _ProfileAction { duplicate, makeDefault, export, restore, delete }
