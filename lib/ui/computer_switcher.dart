import 'package:flutter/material.dart';

import '../controllers/app_controller.dart';
import '../mobile_appearance.dart';
import '../services/companion_service.dart';
import 'desktop_connection_panel.dart';

/// KVM target control. Every tap opens a list of Desktop Companion targets.
class ComputerSwitcher extends StatelessWidget {
  const ComputerSwitcher({
    super.key,
    required this.controller,
    this.compact = false,
    this.iconOnly = false,
  });

  final AppController controller;
  final bool compact;
  final bool iconOnly;

  static String _name(
    BuildContext context,
    List<({String id, String name, String platform, String address})> choices,
    String id,
  ) {
    for (final choice in choices) {
      if (choice.id == id) return '${choice.name} · ${choice.address}';
    }
    return context.mobileText('computer', '电脑');
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final choices = controller.switchableComputers;
      final selectedId = controller.selectedSwitchableComputerId;
      ({String id, String name, String platform, String address})? selected;
      for (final choice in choices) {
        if (choice.id == selectedId) selected = choice;
      }
      final pending = controller.computerSwitchPendingId;
      final noComputer = context.mobileText('No computer selected', '未选择电脑');
      if (compact) {
        if (choices.isEmpty && !iconOnly) return const SizedBox.shrink();
        final currentName = selected == null
            ? noComputer
            : _choiceLabel(choices, selected);
        final chooseTooltip = context.mobileText(
          'Choose a Desktop computer. Current: $currentName.',
          '请选择桌面电脑。当前：$currentName。',
        );
        if (iconOnly) {
          return Tooltip(
            message: chooseTooltip,
            child: IconButton(
              key: const ValueKey('computer-kvm-switch'),
              visualDensity: VisualDensity.compact,
              tooltip: context.mobileText(
                'Switch computer · $currentName',
                '切换电脑 · $currentName',
              ),
              onPressed: pending != null
                  ? null
                  : () => showPicker(context, controller),
              icon: pending != null
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.devices_other),
            ),
          );
        }
        return Tooltip(
          message: chooseTooltip,
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
                : () => showPicker(context, controller),
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
      final name = pending == null
          ? selected?.name ?? noComputer
          : _name(context, choices, pending);
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
                      : () => showPicker(context, controller),
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
                              ? context.mobileText(
                                  'Switching to $name…',
                                  '正在切换到 $name…',
                                )
                              : context.mobileText(
                                  'Switch computer · $name',
                                  '切换电脑 · $name',
                                ),
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
                tooltip: context.mobileText(
                  'Choose or manage computers',
                  '选择或管理电脑',
                ),
                icon: const Icon(Icons.devices_other, size: 19),
                onPressed: () => showPicker(context, controller),
              ),
            ],
          ),
        ),
      );
    },
  );

  static Future<void> showPicker(
    BuildContext context,
    AppController controller,
  ) async {
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
                    context.mobileText('Switch computer', '切换电脑'),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  if (choices.isEmpty)
                    const ListTile(
                      title: MobileText('No paired computers yet', '尚未配对电脑'),
                      subtitle: MobileText(
                        'Pair a computer with LumiaKey Desktop.',
                        '请配对已安装 LumiaKey Desktop 的电脑。',
                      ),
                    ),
                  for (final choice in choices)
                    Card(
                      key: ValueKey('computer-choice-${choice.id}'),
                      color: selectedId == choice.id
                          ? Theme.of(context).colorScheme.primaryContainer
                          : null,
                      child: ListTile(
                        leading: const Icon(Icons.desktop_windows),
                        title: Text(_choiceLabel(choices, choice)),
                        subtitle: Text(
                          '${choice.platform} · ${choice.address} · LumiaKey Desktop',
                        ),
                        trailing:
                            controller.computerSwitchPendingId == choice.id
                            ? const SizedBox.square(
                                dimension: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : selectedId == choice.id
                            ? OutlinedButton(
                                key: ValueKey('disconnect-${choice.id}'),
                                onPressed: () => _confirmDisconnect(
                                  context,
                                  sheetContext,
                                  controller,
                                  choice.id,
                                  controller.companion.activeHost.value,
                                ),
                                child: const MobileText('Disconnect', '断开连接'),
                              )
                            : null,
                        onTap:
                            controller.computerSwitchPendingId != null ||
                                selectedId == choice.id
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
                      Navigator.of(context).push<void>(
                        MaterialPageRoute(
                          builder: (_) => DesktopConnectionSettingsScreen(
                            companion: controller.companion,
                            onDisconnect: controller.disconnectActiveDesktop,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.desktop_windows),
                    label: const MobileText(
                      'Pair or manage LumiaKey Desktop',
                      '配对或管理 LumiaKey Desktop',
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  static Future<void> _confirmDisconnect(
    BuildContext context,
    BuildContext sheetContext,
    AppController controller,
    String choiceId,
    CompanionHost? expectedHost,
  ) async {
    if (expectedHost == null) return;
    final disconnected = await confirmDesktopDisconnect(
      context,
      companion: controller.companion,
      expectedHost: expectedHost,
      disconnect: (target) =>
          controller.disconnectComputer(choiceId, expectedHost: target),
    );
    if (disconnected && sheetContext.mounted) {
      Navigator.pop(sheetContext);
    }
  }

  static String _choiceLabel(
    List<({String id, String name, String platform, String address})> choices,
    ({String id, String name, String platform, String address}) choice,
  ) {
    final duplicates =
        choices
            .where(
              (item) => item.name.toLowerCase() == choice.name.toLowerCase(),
            )
            .length >
        1;
    return duplicates
        ? '${choice.name} · ${choice.platform} · ${choice.address}'
        : choice.name;
  }
}
