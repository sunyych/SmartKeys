import 'package:flutter/material.dart';

import '../controllers/app_controller.dart';
import '../models/computer_setup.dart';

/// The app currently selected in the home-row app switcher.
///
/// This panel intentionally renders no app picker. A single top row owns app
/// selection, so Vibe, browsers, and meeting tools all behave the same way.
class StandaloneAppPanel extends StatelessWidget {
  const StandaloneAppPanel({
    super.key,
    required this.controller,
    required this.target,
    required this.application,
    this.onConfigure,
  });

  final AppController controller;
  final ComputerTarget target;
  final ComputerApplication application;
  final VoidCallback? onConfigure;

  @override
  Widget build(BuildContext context) {
    final shortcuts = computerShortcutsFor(
      application.category,
    ).where((shortcut) => shortcut.id != 'launch');

    return ListView(
      key: ValueKey('standalone-app-${application.id}'),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 18),
      children: [
        Text(
          application.name,
          key: const ValueKey('standalone-app-title'),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 4),
        Text(
          'Bluetooth controls for ${target.name}.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        for (final shortcut in shortcuts)
          _StandaloneShortcutTile(
            controller: controller,
            target: target,
            application: application,
            shortcut: shortcut,
          ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: const ValueKey('edit-computer-setup'),
          onPressed: onConfigure,
          icon: const Icon(Icons.tune),
          label: const Text('Computer app settings'),
        ),
      ],
    );
  }
}

class _StandaloneShortcutTile extends StatelessWidget {
  const _StandaloneShortcutTile({
    required this.controller,
    required this.target,
    required this.application,
    required this.shortcut,
  });

  final AppController controller;
  final ComputerTarget target;
  final ComputerApplication application;
  final ComputerShortcut shortcut;

  @override
  Widget build(BuildContext context) {
    final setup = controller.activeComputerSetup;
    final chord =
        setup?.bindingFor(application.id, shortcut.id) ??
        defaultComputerShortcut(target, application, shortcut.id);
    final action = chord == null ? null : parseComputerShortcut(chord);
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        key: ValueKey('standalone-action-${application.id}-${shortcut.id}'),
        enabled: action != null,
        title: Text(shortcut.label),
        subtitle: Text(
          action == null
              ? 'Set this shortcut in Computer app settings.'
              : _prettyChord(chord!),
        ),
        trailing: action == null
            ? const Icon(Icons.tune)
            : const Icon(Icons.keyboard_alt_outlined),
        onTap: action == null
            ? null
            : () async {
                try {
                  await controller.executeStandaloneShortcut(
                    target,
                    application.id,
                    shortcut.id,
                  );
                } catch (error) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context)
                    ..hideCurrentSnackBar()
                    ..showSnackBar(SnackBar(content: Text('$error')));
                }
              },
      ),
    );
  }

  static String _prettyChord(String chord) => chord
      .split('+')
      .map((part) {
        switch (part.trim().toLowerCase()) {
          case 'primary':
            return '⌘ / Ctrl';
          case 'command':
          case 'meta':
            return '⌘';
          case 'control':
            return 'Ctrl';
          default:
            final value = part.trim();
            return value.length == 1 ? value.toUpperCase() : value;
        }
      })
      .join(' + ');
}
