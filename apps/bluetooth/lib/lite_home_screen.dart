import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';

import 'icons/builtin_icon_catalog.g.dart';
import 'lite_controller.dart';
import 'lite_editors.dart';
import 'local_profiles.dart';
import 'local_settings.dart';
import 'offline_touchpad.dart';

/// An entirely local Bluetooth surface. Page selection never launches an app.
class LiteHomeScreen extends StatefulWidget {
  const LiteHomeScreen({super.key, required this.controller});
  final LiteController controller;
  @override
  State<LiteHomeScreen> createState() => _LiteHomeScreenState();
}

class _LiteHomeScreenState extends State<LiteHomeScreen> {
  late final Timer _clock;
  DateTime _now = DateTime.now();
  int _page = 0;
  String? _lastProfile;
  bool _routeOpen = false;

  @override
  void initState() {
    super.initState();
    widget.controller.setControlsVisible(true);
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void didUpdateWidget(covariant LiteHomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.setControlsVisible(false);
      widget.controller.setControlsVisible(!_routeOpen);
      _page = 0;
    }
  }

  @override
  void dispose() {
    _clock.cancel();
    widget.controller.setControlsVisible(false);
    super.dispose();
  }

  Future<void> _open(Widget page) async {
    if (_routeOpen) return;
    final controller = widget.controller;
    _routeOpen = true;
    controller.setControlsVisible(false);
    try {
      await Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => page));
    } finally {
      if (mounted && identical(controller, widget.controller)) {
        _routeOpen = false;
        controller.setControlsVisible(true);
      }
    }
  }

  void _select(String? id) {
    widget.controller.selectProfile(id);
    setState(() => _page = 0);
  }

  void _pageTo(int value) {
    unawaited(widget.controller.releaseInput());
    setState(() => _page = value);
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final controller = widget.controller;
      final landscape =
          MediaQuery.sizeOf(context).width > MediaQuery.sizeOf(context).height;
      controller.setLandscape(landscape);
      if (!landscape) {
        return const Scaffold(
          key: ValueKey('lite-portrait-gate'),
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.screen_rotation, size: 36),
                    SizedBox(height: 12),
                    Text('Rotate to landscape'),
                    SizedBox(height: 6),
                    Text('Turn your device sideways to use LumiaKey.'),
                  ],
                ),
              ),
            ),
          ),
        );
      }
      if (controller.loading) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      if (_lastProfile != controller.selectedProfileId) {
        _lastProfile = controller.selectedProfileId;
        _page = 0;
      }
      final profile = controller.selectedProfile;
      final launcher = profile == null;
      final shortcuts = profile?.shortcuts ?? const <LocalShortcut>[];
      final pageCount = math.max(1, (shortcuts.length / 12).ceil());
      _page = math.min(_page, pageCount - 1);
      final theme = Theme.of(context);
      final enabled =
          controller.canSendInput && controller.pendingLaunchSlot == null;
      final epoch = controller.inputEpoch;
      LocalProfile? general;
      for (final item in controller.profiles) {
        if (item.id == 'general') general = item;
      }
      return Scaffold(
        key: const ValueKey('lite-home'),
        backgroundColor: const Color(0xFF090D12),
        body: SafeArea(
          child: Row(
            children: [
              Container(
                width: 86,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerLow,
                  border: const Border(
                    right: BorderSide(color: Color(0xFF243242)),
                  ),
                ),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
                      child: Column(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.asset(
                              'assets/app_icon/app_icon_source.png',
                              key: const ValueKey('lite-brand-icon'),
                              width: 32,
                              height: 32,
                              cacheWidth: 96,
                              fit: BoxFit.contain,
                              semanticLabel: 'LumiaKey app icon',
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'LumiaKey',
                            key: const ValueKey('lite-brand-label'),
                            maxLines: 1,
                            style: theme.textTheme.labelSmall,
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.symmetric(horizontal: 5),
                        children: [
                          _RailItem(
                            id: 'launchpad',
                            name: 'Launchpad',
                            icon: const Icon(Icons.apps_rounded, size: 24),
                            selected: launcher,
                            onTap: () => _select(null),
                          ),
                          if (general != null)
                            _RailItem(
                              id: 'general',
                              name: 'General',
                              icon: const Icon(Icons.tune_rounded, size: 24),
                              selected: profile?.id == general.id,
                              onTap: () => _select(general!.id),
                            ),
                          const Divider(indent: 10, endIndent: 10),
                          for (final item in controller.profiles.where(
                            (item) => item.id != 'general',
                          ))
                            _RailItem(
                              id: 'profile-${item.id}',
                              name: item.name,
                              icon: _OfflineAppIcon(
                                id: item.iconId ?? item.id,
                                size: 24,
                              ),
                              selected: profile?.id == item.id,
                              onTap: () => _select(item.id),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 5, 10, 0),
                      child: _header(profile?.name ?? 'Launchpad', enabled),
                    ),
                    Expanded(
                      child: Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(12, 0, 10, 12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (pageCount > 1 && !launcher)
                                    SizedBox(
                                      height: 36,
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.end,
                                        children: [
                                          IconButton(
                                            key: const ValueKey(
                                              'lite-previous-page',
                                            ),
                                            tooltip: 'Previous page',
                                            visualDensity:
                                                VisualDensity.compact,
                                            onPressed: _page > 0
                                                ? () => _pageTo(_page - 1)
                                                : null,
                                            icon: const Icon(
                                              Icons.chevron_left,
                                            ),
                                          ),
                                          Text(
                                            '${_page + 1} / $pageCount',
                                            style: theme.textTheme.labelSmall,
                                          ),
                                          IconButton(
                                            key: const ValueKey(
                                              'lite-next-page',
                                            ),
                                            tooltip: 'Next page',
                                            visualDensity:
                                                VisualDensity.compact,
                                            onPressed: _page + 1 < pageCount
                                                ? () => _pageTo(_page + 1)
                                                : null,
                                            icon: const Icon(
                                              Icons.chevron_right,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  if (controller.error case final message?)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 6),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              message,
                                              key: const ValueKey(
                                                'lite-home-error',
                                              ),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: theme.textTheme.labelMedium
                                                  ?.copyWith(
                                                    color:
                                                        theme.colorScheme.error,
                                                  ),
                                            ),
                                          ),
                                          IconButton(
                                            tooltip: 'Dismiss error',
                                            onPressed: controller.clearError,
                                            icon: const Icon(
                                              Icons.close,
                                              size: 18,
                                            ),
                                            visualDensity:
                                                VisualDensity.compact,
                                          ),
                                        ],
                                      ),
                                    ),
                                  Expanded(
                                    child: _grid(launcher, shortcuts, enabled),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(0, 0, 10, 12),
                              child: OfflineTouchpad(
                                key: ValueKey(controller),
                                enabled: enabled,
                                inputEpoch: epoch,
                                onMove: (delta) => unawaited(
                                  controller.movePointer(delta, epoch: epoch),
                                ),
                                onScroll: (delta) => unawaited(
                                  controller.scrollPointer(delta, epoch: epoch),
                                ),
                                onPrimaryTap: () => unawaited(
                                  controller.primaryClick(epoch: epoch),
                                ),
                                onSecondaryTap: () => unawaited(
                                  controller.secondaryClick(epoch: epoch),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );

  Widget _header(String title, bool enabled) {
    final controller = widget.controller;
    final theme = Theme.of(context);
    return SizedBox(
      height: 48,
      child: LayoutBuilder(
        builder: (context, bounds) {
          final edgeWidth = (bounds.maxWidth * .20).clamp(92.0, 180.0);
          return Row(
            key: const ValueKey('lite-header'),
            children: [
              SizedBox(
                width: edgeWidth,
                child: Text(
                  title,
                  key: const ValueKey('lite-workspace-title'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Expanded(
                child: Row(
                  key: const ValueKey('lite-header-controls'),
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        controller.connected
                            ? controller.activeHost!.name
                            : 'Bluetooth not connected',
                        key: const ValueKey('lite-host-name'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${_now.hour.toString().padLeft(2, '0')}:${_now.minute.toString().padLeft(2, '0')}:${_now.second.toString().padLeft(2, '0')}',
                      key: const ValueKey('lite-clock'),
                      style: theme.textTheme.labelLarge,
                    ),
                    for (final control in const [
                      ('PLAY_PAUSE', 'Play / Pause', Icons.play_arrow),
                      ('MUTE', 'Mute', Icons.volume_off),
                    ])
                      IconButton(
                        key: ValueKey('lite-system-${control.$1}'),
                        tooltip: control.$2,
                        visualDensity: VisualDensity.compact,
                        onPressed: enabled
                            ? () => controller.sendConsumer(control.$1)
                            : null,
                        icon: Icon(control.$3, size: 21),
                      ),
                  ],
                ),
              ),
              SizedBox(
                width: edgeWidth,
                child: Row(
                  key: const ValueKey('lite-header-tools'),
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    SizedBox(
                      width: 40,
                      child: IconButton(
                        key: const ValueKey('lite-bluetooth-connect'),
                        tooltip: 'Bluetooth devices',
                        visualDensity: VisualDensity.compact,
                        onPressed: () =>
                            _open(LiteBluetoothScreen(controller: controller)),
                        color: controller.connected
                            ? theme.colorScheme.primary
                            : null,
                        icon: Icon(
                          controller.connected
                              ? Icons.bluetooth_connected
                              : Icons.bluetooth,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 40,
                      child: IconButton(
                        key: const ValueKey('lite-settings'),
                        tooltip: 'Local settings',
                        visualDensity: VisualDensity.compact,
                        onPressed: () =>
                            _open(LiteSettingsScreen(controller: controller)),
                        icon: const Icon(Icons.settings_outlined),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _grid(bool launcher, List<LocalShortcut> shortcuts, bool enabled) {
    final controller = widget.controller;
    return LayoutBuilder(
      builder: (context, bounds) {
        final width = (bounds.maxWidth - 24) / 4,
            height = (bounds.maxHeight - 16) / 3;
        return GridView.builder(
          key: const ValueKey('lite-twelve-key-grid'),
          padding: EdgeInsets.zero,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: 12,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: math.max(1, width) / math.max(1, height),
          ),
          itemBuilder: (context, index) {
            final position = _page * 12 + index;
            final slot = launcher ? controller.launcherSlots[index] : null;
            final shortcut = !launcher && position < shortcuts.length
                ? shortcuts[position]
                : null;
            final label = slot != null
                ? (slot.title.isEmpty ? 'Slot ${index + 1}' : slot.title)
                : shortcut?.title ?? '';
            final configured = slot?.configured ?? shortcut != null;
            final available = enabled && configured;
            final configure = launcher && !configured;
            final compact = height < 82;
            return Material(
              key: ValueKey('lite-cell-$index'),
              color: configured
                  ? const Color(0xFF192433)
                  : const Color(0xFF10161F),
              borderRadius: BorderRadius.circular(15),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                key: ValueKey(
                  launcher ? 'lite-launch-$index' : 'lite-shortcut-$position',
                ),
                onTap: available
                    ? () {
                        if (launcher) {
                          unawaited(controller.launchSlot(index));
                        } else {
                          unawaited(controller.executeShortcut(shortcut!));
                        }
                      }
                    : configure
                    ? () => _open(
                        LiteLaunchSlotEditor(
                          controller: controller,
                          index: index,
                        ),
                      )
                    : null,
                child: label.isEmpty
                    ? const SizedBox.expand()
                    : Tooltip(
                        message: configure
                            ? 'Configure a launch combination in local settings'
                            : !enabled
                            ? 'Connect Bluetooth to use this control'
                            : label,
                        child: Opacity(
                          opacity: available ? 1 : .45,
                          child: Padding(
                            padding: EdgeInsets.all(compact ? 6 : 10),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (height > 48) ...[
                                  controller.pendingLaunchSlot == index &&
                                          launcher
                                      ? const SizedBox.square(
                                          dimension: 24,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : launcher
                                      ? _OfflineAppIcon(
                                          id: slot!.iconId,
                                          size: compact ? 24 : 35,
                                        )
                                      : Icon(
                                          _shortcutIcon(shortcut),
                                          size: compact ? 23 : 31,
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.primary,
                                        ),
                                  SizedBox(height: compact ? 5 : 10),
                                ],
                                Flexible(
                                  child: Text(
                                    label,
                                    textAlign: TextAlign.center,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall
                                        ?.copyWith(
                                          fontWeight: FontWeight.w600,
                                          fontSize: compact ? 12 : null,
                                        ),
                                  ),
                                ),
                                if (!launcher &&
                                    shortcut != null &&
                                    width > 130 &&
                                    height > 125) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    shortcutDescription(shortcut),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.labelSmall,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
              ),
            );
          },
        );
      },
    );
  }
}

class _RailItem extends StatelessWidget {
  const _RailItem({
    required this.id,
    required this.name,
    required this.icon,
    required this.selected,
    required this.onTap,
  });
  final String id, name;
  final Widget icon;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 5),
    child: Material(
      color: selected
          ? Theme.of(context).colorScheme.primaryContainer
          : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        key: ValueKey('lite-nav-$id'),
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 10),
          child: Column(
            children: [
              icon,
              const SizedBox(height: 4),
              Text(
                name,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _OfflineAppIcon extends StatelessWidget {
  const _OfflineAppIcon({required this.id, required this.size});
  final String? id;
  final double size;
  @override
  Widget build(BuildContext context) {
    final item = id == null
        ? null
        : builtinIconById(canonicalBuiltinIconId(id!) ?? id!);
    if (item == null) {
      return Icon(Icons.apps, size: size, semanticLabel: 'Application icon');
    }
    return Image.asset(
      item.assetPath,
      width: size,
      height: size,
      fit: BoxFit.contain,
      semanticLabel: '${item.name} icon',
      frameBuilder: (_, child, frame, synchronous) =>
          synchronous || frame != null ? child : Icon(Icons.apps, size: size),
      errorBuilder: (_, _, _) => Icon(Icons.apps, size: size),
    );
  }
}

IconData _shortcutIcon(LocalShortcut? shortcut) =>
    switch (shortcut?.consumerUsage) {
      'PLAY_PAUSE' => Icons.play_arrow,
      'MUTE' => Icons.volume_off,
      'VOLUME_UP' => Icons.volume_up,
      'VOLUME_DOWN' => Icons.volume_down,
      'NEXT_TRACK' => Icons.skip_next,
      'PREVIOUS_TRACK' => Icons.skip_previous,
      'STOP' => Icons.stop,
      _ => switch (shortcut?.title.toLowerCase()) {
        'copy' => Icons.copy,
        'paste' => Icons.paste,
        'cut' => Icons.content_cut,
        'undo' => Icons.undo,
        'redo' => Icons.redo,
        'select all' => Icons.select_all,
        'send' => Icons.send,
        'backspace' => Icons.backspace_outlined,
        _ => Icons.keyboard_command_key,
      },
    };
