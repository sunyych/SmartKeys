import 'package:flutter/material.dart';

import '../app.dart';
import '../models/config.dart';
import 'button_editor_screen.dart';
import 'profile_management_screen.dart';

/// All Lite shortcuts are stored and edited on this Android device.
class LiteShortcutSettingsScreen extends StatelessWidget {
  const LiteShortcutSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = SmartKeysScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Shortcut settings')),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Choose a profile to add or edit Bluetooth shortcuts. '
              'Open the matching app on your computer first. '
              'Lite sends keys to the focused app and does not launch apps.',
            ),
          ),
          for (final profile in controller.orderedProfiles)
            ListTile(
              key: ValueKey('lite-shortcuts-${profile.id}'),
              leading: const Icon(Icons.keyboard_outlined),
              title: Text(profile.name),
              subtitle: const Text('Edit local Bluetooth shortcut buttons'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                await controller.switchProfile(profile.id);
                if (!context.mounted) return;
                await Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => _LiteProfileButtons(profileId: profile.id),
                  ),
                );
              },
            ),
          const Divider(),
          ListTile(
            key: const ValueKey('lite-manage-profiles'),
            leading: const Icon(Icons.add_box_outlined),
            title: const Text('Add or manage profiles'),
            subtitle: const Text(
              'Create, rename, import, or reorder shortcuts',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => const ProfileManagementScreen(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LiteProfileButtons extends StatelessWidget {
  const _LiteProfileButtons({required this.profileId});

  final String profileId;

  @override
  Widget build(BuildContext context) {
    final controller = SmartKeysScope.of(context);
    final profile = controller.config.profiles.firstWhere(
      (profile) => profile.id == profileId,
    );
    return Scaffold(
      appBar: AppBar(title: Text('${profile.name} shortcuts')),
      body: ListView.builder(
        itemCount: profile.buttons.length,
        itemBuilder: (context, index) {
          final button = profile.buttons[index];
          return ListTile(
            key: ValueKey('lite-edit-button-${button.position}'),
            leading: CircleAvatar(child: Text('${button.position + 1}')),
            title: Text(button.label),
            subtitle: Text(
              button.action.type == ActionType.none
                  ? 'Tap to add a shortcut'
                  : controller.resolveShortcutLabel(button),
            ),
            trailing: const Icon(Icons.edit_outlined),
            onTap: () async {
              await controller.switchProfile(profileId);
              if (!context.mounted) return;
              await Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => ButtonEditorScreen(position: button.position),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
