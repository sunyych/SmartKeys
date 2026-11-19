import 'package:flutter/material.dart';

import '../controllers/app_controller.dart';
import '../mobile_appearance.dart';
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
              onPressed: pending != null ? null : () => _showPicker(context),
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
                    ListTile(
                      leading: Icon(Icons.desktop_windows),
                      title: Text(_choiceLabel(choices, choice)),
                      subtitle: Text(
                        '${choice.platform} · ${choice.address} · LumiaKey Desktop',
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
                    label: const MobileText(
                      'Pair or manage LumiaKey Desktop',
                      '配对或管理 LumiaKey Desktop',
                    ),
                  ),
                  const SizedBox(height: 8),
                  const MobileText(
                    'Choose a paired LumiaKey Desktop computer. Android Bluetooth devices connect separately in Settings.',
                    '请选择已配对的 LumiaKey Desktop 电脑。Android 蓝牙设备需在设置中单独连接。',
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
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
