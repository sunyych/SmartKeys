import 'package:flutter/material.dart';

import '../controllers/app_controller.dart';
import 'bluetooth_connection_sheet.dart';
import 'desktop_connection_panel.dart';

/// Compact KVM target control. A tap cycles; a long press opens direct choice.
class ComputerSwitcher extends StatelessWidget {
  const ComputerSwitcher({
    super.key,
    required this.controller,
    this.compact = false,
  });

  final AppController controller;
  final bool compact;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final choices = controller.switchableComputers;
      final selectedId = controller.selectedSwitchableComputerId;
      ({String id, String name, bool desktop})? selected;
      for (final choice in choices) {
        if (choice.id == selectedId) selected = choice;
      }
      final pending = controller.computerSwitchPendingId;
      if (compact) {
        final currentName = selected?.name ?? 'No computer selected';
        return GestureDetector(
          onLongPress: () => _showPicker(context),
          child: Tooltip(
            message:
                'Switch computer. Current: $currentName. Tap to cycle; press and hold to choose.',
            triggerMode: TooltipTriggerMode.manual,
            child: TextButton.icon(
              key: const ValueKey('computer-kvm-switch'),
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 32),
                padding: const EdgeInsets.symmetric(horizontal: 7),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
              onPressed: pending != null
                  ? null
                  : () => _activate(context, choices, selectedId),
              icon: pending != null
                  ? const SizedBox.square(
                      dimension: 15,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.swap_horiz, size: 18),
              label: const Text('KVM'),
            ),
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
                  onTap: pending != null
                      ? null
                      : () => _activate(context, choices, selectedId),
                  onLongPress: () => _showPicker(context),
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

  void _activate(
    BuildContext context,
    List<({String id, String name, bool desktop})> choices,
    String? selectedId,
  ) {
    if (choices.length >= 2) {
      _cycle(context, choices, selectedId);
    } else if (choices.length == 1 && choices.single.id != selectedId) {
      controller.switchComputer(choices.single.id);
    } else {
      _showPicker(context);
    }
  }

  static String _name(
    List<({String id, String name, bool desktop})> choices,
    String id,
  ) {
    for (final choice in choices) {
      if (choice.id == id) return choice.name;
    }
    return 'computer';
  }

  Future<void> _cycle(
    BuildContext context,
    List<({String id, String name, bool desktop})> choices,
    String? selectedId,
  ) async {
    if (choices.length < 2) return;
    final index = choices.indexWhere((choice) => choice.id == selectedId);
    final next = choices[(index + 1) % choices.length];
    final succeeded = await controller.switchComputer(next.id);
    if (!succeeded &&
        context.mounted &&
        controller.computerSwitchError != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(controller.computerSwitchError!)));
    }
  }

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
                      subtitle: Text('Pair a computer to use it here.'),
                    ),
                  for (final choice in choices)
                    ListTile(
                      leading: Icon(
                        choice.desktop
                            ? Icons.desktop_windows
                            : Icons.bluetooth,
                      ),
                      title: Text(choice.name),
                      subtitle: Text(
                        choice.desktop ? 'LumiaKey Desktop' : 'Bluetooth',
                      ),
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
                  if (controller.supportsBluetoothComputerSwitch)
                    TextButton.icon(
                      onPressed: () async {
                        Navigator.pop(sheetContext);
                        await showBluetoothConnectionSheet(
                          context,
                          controller.hid,
                        );
                      },
                      icon: const Icon(Icons.bluetooth_searching),
                      label: const Text('Pair or manage Bluetooth computers'),
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
                    'Tap a computer to switch. Tap the top bar to cycle; press and hold it to choose directly.',
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
