import 'package:flutter/material.dart';
import 'package:lumiakeys_protocol/lumiakeys_protocol.dart';

import '../controllers/app_controller.dart';
import '../models/computer_setup.dart';
import 'shortcut_grid_geometry.dart';

/// Controls for the app selected in the home row.
class StandaloneAppPanel extends StatefulWidget {
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
  State<StandaloneAppPanel> createState() => _StandaloneAppPanelState();
}

class _StandaloneAppPanelState extends State<StandaloneAppPanel> {
  int _chatGptPage = 0;

  @override
  void didUpdateWidget(covariant StandaloneAppPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.application.id != widget.application.id ||
        oldWidget.target.id != widget.target.id ||
        oldWidget.target.operatingSystem != widget.target.operatingSystem) {
      _chatGptPage = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewport = MediaQuery.sizeOf(context);
    final controller = widget.controller;
    final target = widget.target;
    final application = widget.application;
    final setup = controller.activeComputerSetup;
    final shortcuts = computerShortcutsFor(application.category)
        .where((shortcut) => shortcut.id != 'launch')
        .where((shortcut) {
          if (application.id != 'chatgpt') return true;
          final saved = setup?.bindingFor(application.id, shortcut.id)?.trim();
          return (saved != null &&
                  saved.isNotEmpty &&
                  parseComputerShortcut(saved) != null) ||
              defaultComputerShortcut(target, application, shortcut.id) != null;
        })
        .toList(growable: false);
    final orderedShortcuts = application.id == 'chatgpt'
        ? _orderChatGptShortcuts(shortcuts)
        : shortcuts;
    final hasChatGptPages =
        application.id == 'chatgpt' &&
        orderedShortcuts.any(
          (shortcut) =>
              !chatGptPrimaryShortcutIds.contains('chatgpt.${shortcut.id}'),
        );
    final pageShortcuts = hasChatGptPages
        ? orderedShortcuts
              .where((shortcut) {
                final primary = chatGptPrimaryShortcutIds.contains(
                  'chatgpt.${shortcut.id}',
                );
                return _chatGptPage == 0 ? primary : !primary;
              })
              .toList(growable: false)
        : orderedShortcuts;
    return LayoutBuilder(
      builder: (context, pageConstraints) {
        final safeInset =
            (viewport.width - pageConstraints.maxWidth).clamp(
              0,
              double.infinity,
            ) /
            2;
        final gridPadding = ShortcutGridGeometry.horizontalPaddingForViewport(
          viewport,
          safeAreaLeft: safeInset,
          safeAreaRight: safeInset,
          fullWidth: application.id == 'cursor',
        );
        return Column(
          children: [
            Expanded(
              child: CustomScrollView(
                key: ValueKey('standalone-app-${application.id}'),
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
                    sliver: SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
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
                        ],
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: EdgeInsets.only(
                      left: gridPadding.left,
                      right: gridPadding.right,
                    ),
                    sliver: SliverLayoutBuilder(
                      builder: (context, constraints) {
                        final geometry = ShortcutGridGeometry.forViewport(
                          viewport: viewport,
                          gridContentWidth: constraints.crossAxisExtent,
                          keysPerPage:
                              controller.config.preferences.tabletKeysPerPage,
                          safeAreaVertical: MediaQuery.viewPaddingOf(
                            context,
                          ).vertical,
                        );
                        return SliverGrid.builder(
                          itemCount: pageShortcuts.length,
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: geometry.columns,
                                crossAxisSpacing: ShortcutGridGeometry.spacing,
                                mainAxisSpacing: ShortcutGridGeometry.spacing,
                                childAspectRatio:
                                    geometry.width / geometry.height,
                              ),
                          itemBuilder: (context, index) =>
                              _StandaloneShortcutTile(
                                controller: controller,
                                target: target,
                                application: application,
                                shortcut: pageShortcuts[index],
                                compact: geometry.height < 104,
                              ),
                        );
                      },
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 18),
                    sliver: SliverToBoxAdapter(
                      child: OutlinedButton.icon(
                        key: const ValueKey('edit-computer-setup'),
                        onPressed: widget.onConfigure,
                        icon: const Icon(Icons.tune),
                        label: const Text('Computer app settings'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (hasChatGptPages)
              SizedBox(
                height: 48,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      key: const ValueKey('standalone-chatgpt-previous-page'),
                      onPressed: _chatGptPage == 0
                          ? null
                          : () => setState(() => _chatGptPage = 0),
                      tooltip: 'Previous page',
                      icon: const Icon(Icons.arrow_back),
                    ),
                    Text('Page ${_chatGptPage + 1} of 2'),
                    IconButton(
                      key: const ValueKey('standalone-chatgpt-next-page'),
                      onPressed: _chatGptPage == 1
                          ? null
                          : () => setState(() => _chatGptPage = 1),
                      tooltip: 'Next page',
                      icon: const Icon(Icons.arrow_forward),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

List<ComputerShortcut> _orderChatGptShortcuts(
  List<ComputerShortcut> shortcuts,
) {
  final primaryRank = {
    for (var index = 0; index < chatGptPrimaryShortcutIds.length; index++)
      chatGptPrimaryShortcutIds[index].substring('chatgpt.'.length): index,
  };
  final secondaryRank = {
    for (var index = 0; index < chatGptSecondaryShortcutIds.length; index++)
      chatGptSecondaryShortcutIds[index].substring('chatgpt.'.length): index,
  };
  final primary =
      shortcuts
          .where((shortcut) => primaryRank.containsKey(shortcut.id))
          .toList(growable: false)
        ..sort(
          (left, right) =>
              primaryRank[left.id]!.compareTo(primaryRank[right.id]!),
        );
  final secondary =
      shortcuts
          .where((shortcut) => !primaryRank.containsKey(shortcut.id))
          .toList(growable: false)
        ..sort((left, right) {
          final leftRank =
              secondaryRank[left.id] ?? chatGptSecondaryShortcutIds.length;
          final rightRank =
              secondaryRank[right.id] ?? chatGptSecondaryShortcutIds.length;
          final rankOrder = leftRank.compareTo(rightRank);
          return rankOrder == 0 ? left.id.compareTo(right.id) : rankOrder;
        });
  return [...primary, ...secondary];
}

class _StandaloneShortcutTile extends StatelessWidget {
  const _StandaloneShortcutTile({
    required this.controller,
    required this.target,
    required this.application,
    required this.shortcut,
    required this.compact,
  });

  final AppController controller;
  final ComputerTarget target;
  final ComputerApplication application;
  final ComputerShortcut shortcut;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final setup = controller.activeComputerSetup;
    final saved = setup?.bindingFor(application.id, shortcut.id);
    final savedAction = saved == null ? null : parseComputerShortcut(saved);
    final chord = application.id == 'chatgpt'
        ? savedAction == null
              ? defaultComputerShortcut(target, application, shortcut.id)
              : saved
        : saved ?? defaultComputerShortcut(target, application, shortcut.id);
    final action = chord == null ? null : parseComputerShortcut(chord);
    final color = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey('standalone-action-${application.id}-${shortcut.id}'),
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
        child: Padding(
          padding: EdgeInsets.all(compact ? 5 : 11),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Center(
                  child: chord == null
                      ? const Icon(Icons.tune, size: 30)
                      : _Keycaps(chord: chord, target: target),
                ),
              ),
              Text(
                shortcut.label,
                textAlign: TextAlign.center,
                maxLines: compact ? 1 : 2,
                overflow: TextOverflow.ellipsis,
                style: compact
                    ? Theme.of(context).textTheme.labelSmall
                    : Theme.of(context).textTheme.labelLarge,
              ),
              if (chord == null)
                Text(
                  'Set in app settings',
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall,
                )
              else if (saved == null)
                Text(
                  'Default',
                  textAlign: TextAlign.center,
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall?.copyWith(color: color.primary),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Keycaps extends StatelessWidget {
  const _Keycaps({required this.chord, required this.target});
  final String chord;
  final ComputerTarget target;

  @override
  Widget build(BuildContext context) {
    final os =
        target.operatingSystem ??
        (target.isApple ? ComputerOperatingSystem.macos : null);
    final isMac = os == ComputerOperatingSystem.macos;
    final keys = chord
        .split('+')
        .map((part) {
          final key = part.trim();
          return switch (key.toLowerCase()) {
            'command' || 'cmd' || 'meta' || 'win' || 'windows' =>
              isMac
                  ? '⌘'
                  : os == ComputerOperatingSystem.linux
                  ? 'Super'
                  : 'Win',
            'ctrl' || 'control' => 'Ctrl',
            'option' || 'alt' => isMac ? '⌥' : 'Alt',
            'shift' => isMac ? '⇧' : 'Shift',
            'primary' => isMac ? '⌘' : 'Ctrl',
            _ => key.length == 1 ? key.toUpperCase() : key,
          };
        })
        .toList(growable: false);
    final style = Theme.of(context).textTheme.labelLarge;
    final color = Theme.of(context).colorScheme;
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final key in keys)
          DecoratedBox(
            decoration: BoxDecoration(
              color: color.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: color.outlineVariant),
              boxShadow: [
                BoxShadow(
                  color: color.shadow.withValues(alpha: .12),
                  offset: const Offset(0, 2),
                  blurRadius: 0,
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              child: Text(key, style: style),
            ),
          ),
      ],
    );
  }
}
