import 'package:flutter/material.dart';

import '../controllers/app_controller.dart';
import 'desktop_connection_panel.dart';

/// KVM target control. Every tap opens a list of Desktop Companion targets.
class ComputerSwitcher extends StatelessWidget {
  const ComputerSwitcher({
    super.key,
    required this.controller,
    this.compact = false,
  });

  final AppController controller;
  final bool compact;

  static String _name(List<({String id, String name})> choices, String id) {
    for (final choice in choices) {
      if (choice.id == id) return choice.name;
    }
    return 'computer';
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final choices = controller.switchableComputers;
      final selectedId = controller.selectedSwitchableComputerId;
      ({String id, String name})? selected;
      for (final choice in choices) {
        if (choice.id == selectedId) selected = choice;
      }
      final pending = controller.computerSwitchPendingId;
      if (compact) {
        if (choices.isEmpty) return const SizedBox.shrink();
        final currentName = selected?.name ?? 'No computer selected';
        return Tooltip(
          message: 'Choose a Desktop computer. Current: $currentName.',
          child: TextButton.icon(
            key: const ValueKey('computer-kvm-switch'),
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 32),
              padding: const EdgeInsets.symmetric(horizontal: 7),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
            onPressed: pending != null ? null : () => _showPicker(context),
            icon: pending != null
                ? const SizedBox.square(
                    dimension: 15,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.swap_horiz, size: 18),
            label: const Text('KVM'),
          ),
        );
      }
      return Material(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: .55),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: pending != null ? null : () => _showPicker(context),
                  child: Row(
                    children: [
                      Icon(
                        Icons.switch_account,
                        size: 19,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          pending != null
                              ? 'Switching to ${_name(choices, pending)}…'
                              : 'Switch computer · ${selected?.name ?? 'No computer selected'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                      ),
                      if (pending != null)
                        const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      const SizedBox(width: 4),
                      const Icon(Icons.expand_more, size: 19),
                    ],
                  ),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Choose or manage computers',
                icon: const Icon(Icons.devices_other, size: 19),
                onPressed: () => _showPicker(context),
              ),
            ],
          ),
        ),
      );
    },
  );

  Future<void> _showPicker(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: ListenableBuilder(
          listenable: controller,
          builder: (context, _) {
            final choices = controller.switchableComputers;
            final selectedId = controller.selectedSwitchableComputerId;
            final error = controller.computerSwitchError;
            return ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * .75,
              ),
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    'Switch computer',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  if (choices.isEmpty)
                    const ListTile(
                      title: Text('No paired computers yet'),
                      subtitle: Text('Pair a computer with LumiaKey Desktop.'),
                    ),
                  for (final choice in choices)
                    ListTile(
                      leading: Icon(Icons.desktop_windows),
                      title: Text(choice.name),
                      subtitle: const Text('LumiaKey Desktop'),
                      trailing: controller.computerSwitchPendingId == choice.id
                          ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : selectedId == choice.id
                          ? const Icon(Icons.check_circle)
                          : null,
                      onTap: controller.computerSwitchPendingId != null
                          ? null
                          : () async {
                              final ok = await controller.switchComputer(
                                choice.id,
                              );
                              if (ok && sheetContext.mounted) {
                                Navigator.pop(sheetContext);
                              }
                            },
                    ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        error,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  TextButton.icon(
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      showModalBottomSheet<void>(
                        context: context,
                        isScrollControlled: true,
                        builder: (_) => SafeArea(
                          child: DesktopConnectionPanel(
                            companion: controller.companion,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.desktop_windows),
                    label: const Text('Pair or manage LumiaKey Desktop'),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Choose a paired LumiaKey Desktop computer. Android Bluetooth devices connect separately in Settings.',
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
