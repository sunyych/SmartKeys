import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lumiakeys_protocol/lumiakeys_protocol.dart';

import '../app.dart';
import '../controllers/app_controller.dart';
import '../models/config.dart';
import 'computer_switcher.dart';
import 'desktop_connection_panel.dart';
import 'dictation_entry_consent.dart';
import 'home_screen.dart' show remoteIcon;
import 'local_dictation_panel.dart';
import 'settings_screen.dart';
import 'widgets/mouse_touchpad.dart';

/// The Desktop-owned control surface. Local Bluetooth Profiles are never used
/// to resolve its buttons, applications, or pointer commands.
class RegularHomeScreen extends StatefulWidget {
  const RegularHomeScreen({super.key});

  @override
  State<RegularHomeScreen> createState() => _RegularHomeScreenState();
}

class _RegularHomeScreenState extends State<RegularHomeScreen> {
  static const _launchpad = 'launchpad';
  static const _general = 'general';
  static const _pageSize = 12;

  final _dictation = GlobalKey<LocalDictationEntryButtonState>();
  String _selection = _launchpad;
  String? _sessionKey;
  String? _pendingApplication;
  String? _error;
  int _generation = 0;
  int _page = 0;
  bool _wasReady = false;

  bool _ready(AppController controller) =>
      controller.isDesktopSynced && controller.computerSwitchPendingId == null;

  String? _session(AppController controller) {
    final host = controller.companion.activeHost.value;
    return host == null
        ? null
        : '${host.computerId}|${host.address}|${host.port}|${host.token}';
  }

  void _trackSession(AppController controller, bool landscape) {
    final session = _session(controller);
    final ready = _ready(controller) && landscape;
    final invalidate = _sessionKey != session || (_wasReady && !ready);
    _wasReady = ready;
    if (!invalidate) return;
    _sessionKey = session;
    _selection = _launchpad;
    _page = 0;
    _pendingApplication = null;
    _error = null;
    ++_generation;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_dictation.currentState?.stopQuickDictation());
    });
  }

  List<RemoteApplication> _applications(AppController controller) {
    final applications = controller.syncedApplications.toList();
    int rank(String id) => switch (id) {
      'chatgpt' => 0,
      'chrome' => 1,
      _ => 2,
    };
    applications.sort((a, b) {
      final priority = rank(a.id).compareTo(rank(b.id));
      return priority != 0
          ? priority
          : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return applications;
  }

  Future<void> _select(
    AppController controller,
    String selection, {
    RemoteApplication? application,
  }) async {
    final generation = ++_generation;
    final session = _session(controller);
    setState(() {
      _pendingApplication = application?.id;
      _error = null;
    });
    try {
      await _dictation.currentState?.stopQuickDictation();
      await controller.prepareForContextChange();
      if (!mounted ||
          generation != _generation ||
          session != _session(controller)) {
        return;
      }
      if (application != null) {
        if (!_ready(controller) ||
            !controller.syncedApplications.any(
              (app) => app.id == application.id,
            )) {
          return;
        }
        await controller.launchRemoteApplication(application);
      }
      if (!mounted ||
          generation != _generation ||
          session != _session(controller)) {
        return;
      }
      if (application != null && !_ready(controller)) return;
      setState(() {
        _selection = selection;
        _page = 0;
      });
    } catch (error) {
      if (mounted &&
          generation == _generation &&
          session == _session(controller)) {
        setState(() => _error = 'Could not open this application. $error');
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _pendingApplication = null);
      }
    }
  }

  Future<void> _execute(
    AppController controller,
    RemoteShortcutButton button,
  ) async {
    if (!_ready(controller) || !button.enabled || _pendingApplication != null) {
      return;
    }
    final session = _session(controller);
    final generation = _generation;
    if (button.targetType == RemoteTargetType.voiceInput &&
        !await ensureDictationEntryExplained(context)) {
      return;
    }
    if (!mounted ||
        !_ready(controller) ||
        generation != _generation ||
        session != _session(controller) ||
        controller.desktopManifest?.buttonById(button.id)?.enabled != true) {
      return;
    }
    try {
      await controller.executeRemoteButton(button);
    } catch (error) {
      if (mounted &&
          generation == _generation &&
          session == _session(controller)) {
        setState(() => _error = 'Could not run this shortcut. $error');
      }
    }
  }

  Future<void> _showConnection(AppController controller) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: DesktopConnectionPanel(companion: controller.companion),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final controller = SmartKeysScope.of(context);
    final viewport = MediaQuery.sizeOf(context);
    final landscape = viewport.width > viewport.height;
    controller.registerLayoutOrientation(landscape);
    _trackSession(controller, landscape);
    if (!landscape) {
      return const Scaffold(
        key: ValueKey('regular-portrait-gate'),
        body: SafeArea(
          child: _EmptySurface(
            icon: Icons.screen_rotation,
            title: 'Rotate to landscape',
            message: 'Turn your device sideways to use LumiaKey.',
          ),
        ),
      );
    }
    final ready = _ready(controller);
    final applications = _applications(controller);
    final application = applications.cast<RemoteApplication?>().firstWhere(
      (app) => app?.id == _selection,
      orElse: () => null,
    );
    final manifest = controller.desktopManifest;
    final layout = _selection == _general
        ? manifest?.layoutById('keyboard') ??
              manifest?.layouts.cast<RemoteShortcutLayout?>().firstWhere(
                (layout) => layout?.kind == RemoteLayoutKind.keyboard,
                orElse: () => null,
              )
        : application == null
        ? null
        : controller.layoutForApplication(application);
    final launcher = _selection == _launchpad;
    final count = launcher ? applications.length : layout?.buttons.length ?? 0;
    final pageCount = math.max(1, (count / _pageSize).ceil());
    if (_page >= pageCount) _page = 0;
    final title = launcher
        ? 'Launchpad'
        : _selection == _general
        ? 'General'
        : application?.name ?? 'Application';
    final theme = Theme.of(context);

    return Scaffold(
      key: const ValueKey('regular-home'),
      body: SafeArea(
        child: Stack(
          children: [
            Row(
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
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Icon(Icons.keyboard_command_key, size: 24),
                      ),
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.symmetric(horizontal: 5),
                          children: [
                            _NavigationItem(
                              id: _launchpad,
                              label: 'Launchpad',
                              icon: const Icon(Icons.apps_rounded),
                              selected: launcher,
                              onTap: () => _select(controller, _launchpad),
                            ),
                            _NavigationItem(
                              id: _general,
                              label: 'General',
                              icon: const Icon(Icons.tune_rounded),
                              selected: _selection == _general,
                              onTap: () => _select(controller, _general),
                            ),
                            const Divider(indent: 10, endIndent: 10),
                            for (final app in applications)
                              _NavigationItem(
                                id: app.id,
                                label: app.name,
                                icon: _ApplicationIcon(app: app, size: 24),
                                selected: app.id == _selection,
                                busy: app.id == _pendingApplication,
                                onTap: ready
                                    ? () => _select(
                                        controller,
                                        app.id,
                                        application: app,
                                      )
                                    : null,
                              ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 9),
                        child: Text(
                          'LumiaKey',
                          style: theme.textTheme.labelSmall,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 5, 10, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          height: 43,
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  title,
                                  key: const ValueKey(
                                    'regular-workspace-title',
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              if (pageCount > 1) ...[
                                IconButton(
                                  key: const ValueKey('regular-previous-page'),
                                  tooltip: 'Previous page',
                                  visualDensity: VisualDensity.compact,
                                  onPressed: _page > 0
                                      ? () => setState(() => _page--)
                                      : null,
                                  icon: const Icon(Icons.chevron_left),
                                ),
                                Text(
                                  '${_page + 1} / $pageCount',
                                  style: theme.textTheme.labelSmall,
                                ),
                                IconButton(
                                  key: const ValueKey('regular-next-page'),
                                  tooltip: 'Next page',
                                  visualDensity: VisualDensity.compact,
                                  onPressed: _page + 1 < pageCount
                                      ? () => setState(() => _page++)
                                      : null,
                                  icon: const Icon(Icons.chevron_right),
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (_error != null)
                          _StatusBanner(message: _error!, error: true),
                        Expanded(
                          child: !ready
                              ? _ConnectionPrompt(
                                  onConnect: () => _showConnection(controller),
                                )
                              : launcher && applications.isEmpty
                              ? const _EmptySurface(
                                  icon: Icons.apps,
                                  title: 'Choose your applications in Desktop',
                                  message:
                                      'Enable Apps Sync and select installed applications in LumiaKey Desktop.',
                                )
                              : !launcher && layout == null
                              ? const _EmptySurface(
                                  icon: Icons.keyboard_outlined,
                                  title: 'No shortcuts configured',
                                  message:
                                      'Add this application’s shortcut layout in LumiaKey Desktop.',
                                )
                              : _TwelveKeyGrid(
                                  page: _page,
                                  launcher: launcher,
                                  applications: applications,
                                  buttons: layout?.buttons ?? const [],
                                  enabled: _pendingApplication == null,
                                  onApplication: (app) => _select(
                                    controller,
                                    app.id,
                                    application: app,
                                  ),
                                  onButton: (button) =>
                                      _execute(controller, button),
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(0, 5, 10, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          height: 43,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              IconButton(
                                key: const ValueKey(
                                  'regular-desktop-connection',
                                ),
                                tooltip: ready
                                    ? 'Desktop connected'
                                    : 'Connect Desktop',
                                visualDensity: VisualDensity.compact,
                                onPressed: () => _showConnection(controller),
                                color: ready ? theme.colorScheme.primary : null,
                                icon: Icon(
                                  ready
                                      ? Icons.desktop_windows
                                      : Icons.desktop_access_disabled,
                                ),
                              ),
                              ComputerSwitcher(
                                controller: controller,
                                compact: true,
                                iconOnly: true,
                              ),
                              const SizedBox(width: 42),
                              IconButton(
                                key: const ValueKey('regular-settings'),
                                tooltip: 'Settings',
                                visualDensity: VisualDensity.compact,
                                onPressed: () => Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => const SettingsScreen(),
                                  ),
                                ),
                                icon: const Icon(Icons.settings_outlined),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(10, 3, 8, 9),
                          child: Text(
                            ready
                                ? controller.companion.activeHost.value!.name
                                : 'Desktop not connected',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        Expanded(
                          child: _DesktopTouchpad(
                            controller: controller,
                            enabled: ready,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            Positioned.fill(
              child: LocalDictationEntryButton(
                key: _dictation,
                hid: controller.hid,
                companion: controller.companion,
                forceDesktopOutput: true,
                entryEnabled: ready && _pendingApplication == null,
                topOffset: 5,
                rightInset: 49,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavigationItem extends StatelessWidget {
  const _NavigationItem({
    required this.id,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.busy = false,
  });
  final String id;
  final String label;
  final Widget icon;
  final bool selected;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Tooltip(
        message: label,
        child: Material(
          color: selected ? colors.primaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(13),
          child: InkWell(
            key: ValueKey('regular-nav-$id'),
            borderRadius: BorderRadius.circular(13),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 3),
              child: Column(
                children: [
                  busy
                      ? const SizedBox.square(
                          dimension: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : icon,
                  const SizedBox(height: 5),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TwelveKeyGrid extends StatelessWidget {
  const _TwelveKeyGrid({
    required this.page,
    required this.launcher,
    required this.applications,
    required this.buttons,
    required this.enabled,
    required this.onApplication,
    required this.onButton,
  });
  final int page;
  final bool launcher;
  final List<RemoteApplication> applications;
  final List<RemoteShortcutButton> buttons;
  final bool enabled;
  final ValueChanged<RemoteApplication> onApplication;
  final ValueChanged<RemoteShortcutButton> onButton;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      const spacing = 8.0;
      final width = (constraints.maxWidth - spacing * 3) / 4;
      final height = (constraints.maxHeight - spacing * 2) / 3;
      return GridView.builder(
        key: const ValueKey('regular-twelve-key-grid'),
        padding: EdgeInsets.zero,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 12,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          crossAxisSpacing: spacing,
          mainAxisSpacing: spacing,
          childAspectRatio: math.max(1, width) / math.max(1, height),
        ),
        itemBuilder: (context, index) {
          final position = page * 12 + index;
          final app = launcher && position < applications.length
              ? applications[position]
              : null;
          final button = !launcher && position < buttons.length
              ? buttons[position]
              : null;
          final label =
              app?.name ?? (button == null ? '' : _shortcutLabel(button));
          final available = enabled && (app != null || button?.enabled == true);
          return Material(
            key: ValueKey('regular-cell-$index'),
            color: app == null && button == null
                ? const Color(0xFF10161F)
                : const Color(0xFF192433),
            borderRadius: BorderRadius.circular(15),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              key: app != null
                  ? ValueKey('regular-launch-${app.id}')
                  : button != null
                  ? ValueKey('regular-button-${button.id}')
                  : null,
              onTap: available
                  ? () => app != null ? onApplication(app) : onButton(button!)
                  : null,
              child: label.isEmpty
                  ? const SizedBox.expand()
                  : Tooltip(
                      message: button?.description.isNotEmpty == true
                          ? button!.description
                          : label,
                      child: LayoutBuilder(
                        builder: (context, cell) {
                          final compact = cell.maxHeight < 82;
                          return Opacity(
                            opacity: available ? 1 : .45,
                            child: Padding(
                              padding: EdgeInsets.all(compact ? 6 : 10),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  if (cell.maxHeight > 48) ...[
                                    app != null
                                        ? _ApplicationIcon(
                                            app: app,
                                            size: compact ? 24 : 35,
                                          )
                                        : Icon(
                                            _shortcutIcon(button!.icon),
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
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.center,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelLarge
                                          ?.copyWith(
                                            fontSize: compact ? 12 : 15,
                                          ),
                                    ),
                                  ),
                                  if (!compact &&
                                      button?.targetType ==
                                          RemoteTargetType.keyboardShortcut &&
                                      cell.maxHeight > 125) ...[
                                    const SizedBox(height: 6),
                                    Text(
                                      button!.shortcut.join(' + '),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                          ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
            ),
          );
        },
      );
    },
  );
}

String _shortcutLabel(RemoteShortcutButton button) {
  if (button.id.endsWith('.alternateSend') &&
      button.name == 'Alternate Send (app-defined)') {
    return 'Alt Send';
  }
  if (button.id.endsWith('.sidebar') &&
      const {
        'Show / Hide Sidebar',
        'Show/Hide Sidebar',
      }.contains(button.name)) {
    return 'Sidebar';
  }
  return button.name;
}

IconData _shortcutIcon(String id) => switch (id) {
  'backspace' => Icons.backspace_outlined,
  'content_cut' => Icons.content_cut,
  'center_focus_strong' => Icons.center_focus_strong,
  'keyboard_return' => Icons.keyboard_return,
  'arrow_forward' => Icons.arrow_forward,
  _ => remoteIcon(id),
};

class _ApplicationIcon extends StatelessWidget {
  const _ApplicationIcon({required this.app, required this.size});
  final RemoteApplication app;
  final double size;

  @override
  Widget build(BuildContext context) {
    final asset = switch (app.id.toLowerCase()) {
      'chatgpt' || 'codex' => 'openai',
      'chrome' ||
      'photoshop' ||
      'illustrator' ||
      'premiere' ||
      'vscode' ||
      'solidworks' => app.id.toLowerCase(),
      _ => null,
    };
    return asset == null
        ? Icon(remoteIcon(app.icon), size: size)
        : Image.asset(
            'assets/app_icons/$asset.png',
            width: size,
            height: size,
            frameBuilder: (context, child, frame, wasSynchronouslyLoaded) =>
                wasSynchronouslyLoaded || frame != null
                ? child
                : Icon(remoteIcon(app.icon), size: size),
            errorBuilder: (_, _, _) => Icon(remoteIcon(app.icon), size: size),
          );
  }
}

class _DesktopTouchpad extends StatelessWidget {
  const _DesktopTouchpad({required this.controller, required this.enabled});
  final AppController controller;
  final bool enabled;

  bool get _canSend =>
      enabled &&
      controller.isDesktopSynced &&
      controller.computerSwitchPendingId == null &&
      controller.selectedDesktopSupportsMouse;

  @override
  Widget build(BuildContext context) {
    if (!_canSend) {
      return _EmptySurface(
        key: const ValueKey('regular-touchpad-unavailable'),
        icon: Icons.touch_app_outlined,
        title: 'Touchpad',
        message: enabled
            ? 'Update LumiaKey Desktop to enable mouse control.'
            : 'Connect LumiaKey Desktop to use the touchpad.',
      );
    }
    return MouseTouchpad(
      key: const ValueKey('regular-touchpad'),
      config: const WheelConfig(
        controlType: WheelControlType.mousePad,
        modeLabel: 'Touchpad',
      ),
      inputEpoch: controller.inputEpoch,
      onMove: (delta) {
        if (_canSend) controller.sendTouchpadMove(delta.dx, delta.dy);
      },
      onScroll: (delta) {
        if (_canSend) controller.sendTouchpadScroll(delta);
      },
      onPrimaryTap: () {
        if (_canSend) controller.sendMouseClick(secondary: false);
      },
      onSecondaryTap: () {
        if (_canSend) controller.sendMouseClick(secondary: true);
      },
    );
  }
}

class _ConnectionPrompt extends StatelessWidget {
  const _ConnectionPrompt({required this.onConnect});
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.devices_outlined, size: 42),
          const SizedBox(height: 14),
          Text(
            'Connect LumiaKey Desktop',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          const Text(
            'Your computer provides applications and shortcuts.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            key: const ValueKey('regular-connect-desktop'),
            onPressed: onConnect,
            icon: const Icon(Icons.link),
            label: const Text('Connect Desktop'),
          ),
        ],
      ),
    ),
  );
}

class _EmptySurface extends StatelessWidget {
  const _EmptySurface({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
  });
  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: const Color(0xFF10161F),
      borderRadius: BorderRadius.circular(22),
    ),
    child: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 30),
            const SizedBox(height: 10),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 7),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    ),
  );
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.message, this.error = false});
  final String message;
  final bool error;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      message,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: error ? Theme.of(context).colorScheme.error : null,
      ),
    ),
  );
}
