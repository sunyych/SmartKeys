import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lumiakeys_protocol/lumiakeys_protocol.dart';

import '../controllers/app_controller.dart';
import '../models/config.dart';
import '../models/computer_setup.dart';
import '../services/companion_service.dart';
import 'standalone_app_panel.dart';

class VibeCodingPanel extends StatefulWidget {
  const VibeCodingPanel({
    super.key,
    required this.controller,
    required this.target,
    required this.selectedApplicationId,
    this.activationPending = false,
    this.onConfigure,
    required this.onBeforeContextChange,
    required this.onStartDictation,
    required this.onStopDictation,
  });

  final AppController controller;
  final ComputerTarget? target;
  final String selectedApplicationId;
  final bool activationPending;
  final VoidCallback? onConfigure;
  final Future<void> Function() onBeforeContextChange;
  final Future<void> Function() onStartDictation;
  final Future<void> Function() onStopDictation;

  @override
  State<VibeCodingPanel> createState() => _VibeCodingPanelState();
}

class _VibeCodingPanelState extends State<VibeCodingPanel> {
  String? _pendingOperation;
  String? _operationError;
  bool _dictationBusy = false;
  bool _repeatActive = false;
  String? _repeatButtonId;
  Future<void>? _repeatTask;

  @override
  void didUpdateWidget(covariant VibeCodingPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedApplicationId != widget.selectedApplicationId) {
      unawaited(_stopBackspaceRepeat());
    }
  }

  @override
  void dispose() {
    _repeatActive = false;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final target = widget.target;
    final basicApplication = computerApplicationById(
      widget.selectedApplicationId,
    );
    if (target?.mode == ComputerMode.standalone && basicApplication != null) {
      return StandaloneAppPanel(
        controller: widget.controller,
        target: target!,
        application: basicApplication,
        onConfigure: widget.onConfigure,
      );
    }
    if (widget.selectedApplicationId.isEmpty) {
      return _VibeApplicationRequired(
        mode: target?.mode ?? ComputerMode.disconnected,
        onConfigure: widget.onConfigure,
      );
    }
    final companion = widget.controller.companion;
    return AnimatedBuilder(
      animation: Listenable.merge([
        companion.activeHost,
        companion.manifest,
        companion.syncStatus,
        companion.errorMessage,
      ]),
      builder: (context, _) {
        final appId = widget.selectedApplicationId;
        final manifest = companion.manifest.value;
        final layout = manifest?.layoutById('vibe.$appId');
        final application = manifest?.applicationById(appId);
        final availability = _availability(
          controller: widget.controller,
          manifest: manifest,
          layout: layout,
          application: application,
        );
        final foreground = widget.controller.foregroundApplication?.id == appId;
        final controlsEnabled =
            availability.ready && foreground && !widget.activationPending;
        final busy = _pendingOperation != null || _repeatActive;
        final error = _operationError ?? availability.error;
        if (_repeatActive && !controlsEnabled) {
          unawaited(_stopBackspaceRepeat());
        }
        final visibleButtons =
            layout?.buttons
                .where(
                  (button) => button.targetType != RemoteTargetType.voiceInput,
                )
                .toList(growable: false) ??
            const <RemoteShortcutButton>[];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Row(
                children: [
                  Icon(_vibeApplicationIcon(appId), size: 19),
                  const SizedBox(width: 8),
                  Text(
                    'Vibe Coding · ${_vibeApplicationLabel(appId)}',
                    key: const ValueKey('vibe-coding-title'),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 3, 12, 8),
              child: _VibeStatusCard(
                availability: availability,
                layoutName: layout?.name,
                error: error,
                pending: busy,
                onRefresh: companion.activeHost.value == null
                    ? null
                    : () => companion.refreshManifest(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.mic_none),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Local Dictation',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      OutlinedButton.icon(
                        key: const ValueKey('vibe-dictation-start'),
                        onPressed: controlsEnabled && !busy && !_dictationBusy
                            ? () => _runDictation(start: true)
                            : null,
                        icon: const Icon(Icons.mic, size: 18),
                        label: const Text('Start'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.tonalIcon(
                        key: const ValueKey('vibe-dictation-stop'),
                        onPressed: _dictationBusy
                            ? null
                            : () => _runDictation(start: false),
                        icon: const Icon(Icons.stop, size: 18),
                        label: const Text('Stop'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (layout != null && layout.buttons.any(_isUnassignedProject))
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: _ProjectSetupHint(layoutName: layout.name),
              ),
            if (layout == null)
              const Expanded(child: SizedBox.shrink())
            else ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (appId == 'claude')
                      Text(
                        'In Claude Desktop, select the Code tab.',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
              Expanded(
                child: visibleButtons.isEmpty
                    ? const Center(
                        child: Text('No Vibe Coding actions configured.'),
                      )
                    : Builder(
                        builder: (context) {
                          final landscape =
                              MediaQuery.orientationOf(context) ==
                              Orientation.landscape;
                          final columns = landscape ? 5 : 3;
                          const spacing = 6.0;
                          return GridView.builder(
                            key: const ValueKey('vibe-shortcut-grid'),
                            padding: const EdgeInsets.fromLTRB(10, 2, 10, 10),
                            physics: const BouncingScrollPhysics(),
                            itemCount: visibleButtons.length,
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: columns,
                                  crossAxisSpacing: spacing,
                                  mainAxisSpacing: spacing,
                                  mainAxisExtent: 88,
                                ),
                            itemBuilder: (context, index) {
                              final button = visibleButtons[index];
                              final isProject = _isProjectButton(button);
                              final isBackspace = button.id.endsWith(
                                '.backspace',
                              );
                              final isSend = button.id.endsWith('.send');
                              final alternateSend = _buttonById(
                                layout,
                                'vibe.$appId.alternateSend',
                              );
                              final deleteToStart = _buttonById(
                                layout,
                                'vibe.$appId.deleteToStart',
                              );
                              final enabled =
                                  controlsEnabled &&
                                  !busy &&
                                  button.enabled &&
                                  !(_pendingOperation == 'button:${button.id}');
                              return _VibeShortcutButton(
                                button: button,
                                enabled: enabled,
                                platform:
                                    widget.controller.effectiveShortcutPlatform,
                                pending:
                                    _pendingOperation ==
                                        'button:${button.id}' ||
                                    (_repeatActive &&
                                        _repeatButtonId == button.id),
                                onPressed: enabled
                                    ? () => _runButton(appId, button)
                                    : null,
                                onLongPressStart: enabled && isBackspace
                                    ? () => _startBackspaceRepeat(
                                        appId,
                                        button.id,
                                      )
                                    : enabled &&
                                          isSend &&
                                          alternateSend != null &&
                                          alternateSend.enabled
                                    ? () => _runButton(appId, alternateSend)
                                    : null,
                                onLongPressEnd: isBackspace
                                    ? _stopBackspaceRepeat
                                    : null,
                                onSecondaryTap:
                                    enabled &&
                                        isBackspace &&
                                        deleteToStart != null &&
                                        deleteToStart.enabled
                                    ? () => _runButton(appId, deleteToStart)
                                    : null,
                                onPointerStop: isBackspace
                                    ? _stopBackspaceRepeat
                                    : null,
                                alternateHint:
                                    isBackspace && deleteToStart != null
                                    ? 'Right-click for Delete to start'
                                    : isSend &&
                                          alternateSend != null &&
                                          alternateSend.enabled
                                    ? 'Hold for ${alternateSend.name}'
                                    : isBackspace
                                    ? 'Hold to repeat'
                                    : null,
                                projectSetup: isProject && !button.enabled,
                                projectLayoutName: layout.name,
                              );
                            },
                          );
                        },
                      ),
              ),
            ],
          ],
        );
      },
    );
  }

  Future<void> _runOperation(
    String operation,
    Future<void> Function() action,
  ) async {
    if (_pendingOperation != null) return;
    setState(() {
      _pendingOperation = operation;
      _operationError = null;
    });
    try {
      await action();
      if (widget.controller.companion.syncStatus.value ==
          CompanionSyncStatus.error) {
        _operationError =
            widget.controller.companion.errorMessage.value ??
            'LumiaKey Desktop could not complete this action.';
      }
    } catch (error) {
      _operationError = '$error';
    } finally {
      if (mounted) {
        setState(() => _pendingOperation = null);
      }
    }
  }

  Future<void> _runDictation({required bool start}) async {
    if (_dictationBusy) return;
    setState(() => _dictationBusy = true);
    try {
      if (start) {
        await widget.onStartDictation();
      } else {
        await widget.onStopDictation();
      }
    } catch (error) {
      if (mounted) setState(() => _operationError = '$error');
    } finally {
      if (mounted) setState(() => _dictationBusy = false);
    }
  }

  Future<void> _runButton(String applicationId, RemoteShortcutButton button) =>
      _runOperation('button:${button.id}', () async {
        if (_isProjectButton(button) ||
            button.targetType == RemoteTargetType.voiceInput) {
          await widget.onBeforeContextChange();
        }
        await widget.controller.executeVibeCodingButton(
          applicationId,
          button.id,
        );
      });

  void _startBackspaceRepeat(String applicationId, String buttonId) {
    if (_repeatActive || _pendingOperation != null) return;
    _repeatActive = true;
    _repeatButtonId = buttonId;
    setState(() {});
    _repeatTask = _repeatBackspace(applicationId, buttonId);
  }

  Future<void> _repeatBackspace(String applicationId, String buttonId) async {
    final activeHost = widget.controller.companion.activeHost.value;
    try {
      while (_repeatActive &&
          mounted &&
          widget.selectedApplicationId == applicationId &&
          activeHost != null &&
          widget.controller.companion.activeHost.value == activeHost &&
          widget.controller.desktopManifest
                  ?.applicationById(applicationId)
                  ?.foreground ==
              true) {
        final button = _buttonById(
          widget.controller.vibeCodingLayoutFor(applicationId),
          buttonId,
        );
        if (button == null || !button.enabled) break;
        await _runButton(applicationId, button);
        if (widget.controller.companion.syncStatus.value ==
            CompanionSyncStatus.error) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 180));
      }
    } catch (error) {
      _operationError = '$error';
    } finally {
      _repeatActive = false;
      _repeatButtonId = null;
      _repeatTask = null;
      if (mounted) setState(() {});
    }
  }

  Future<void> _stopBackspaceRepeat() async {
    _repeatActive = false;
    final task = _repeatTask;
    if (task != null) await task;
  }

  static RemoteShortcutButton? _buttonById(
    RemoteShortcutLayout? layout,
    String id,
  ) => layout?.buttons.cast<RemoteShortcutButton?>().firstWhere(
    (button) => button?.id == id,
    orElse: () => null,
  );

  static bool _isProjectButton(RemoteShortcutButton button) =>
      button.id.endsWith('.project');

  static bool _isUnassignedProject(RemoteShortcutButton button) =>
      _isProjectButton(button) && !button.enabled;

  _VibeAvailability _availability({
    required AppController controller,
    required DesktopManifest? manifest,
    required RemoteShortcutLayout? layout,
    required RemoteApplication? application,
  }) {
    final companion = controller.companion;
    if (companion.syncStatus.value == CompanionSyncStatus.error) {
      return _VibeAvailability(
        title: 'Desktop action failed',
        message: companion.errorMessage.value ?? 'Desktop connection failed.',
        icon: Icons.error_outline,
        error: companion.errorMessage.value ?? 'Desktop connection failed.',
      );
    }
    if (companion.activeHost.value == null) {
      final searching =
          companion.syncStatus.value == CompanionSyncStatus.discovering ||
          companion.syncStatus.value == CompanionSyncStatus.syncing;
      return _VibeAvailability(
        title: searching ? 'Looking for LumiaKey Desktop' : 'Desktop offline',
        message: searching
            ? 'Connect this device and LumiaKey Desktop to the same network.'
            : 'Connect LumiaKey Desktop on the same network to use Vibe Coding.',
        icon: Icons.desktop_access_disabled_outlined,
      );
    }
    if (!controller.isDesktopSynced || manifest == null) {
      return const _VibeAvailability(
        title: 'Connecting to Desktop',
        message: 'Waiting for a current Vibe Coding layout.',
        icon: Icons.sync,
      );
    }
    if (layout == null) {
      return const _VibeAvailability(
        title: 'Update LumiaKey Desktop',
        message: 'This Desktop version does not include Vibe Coding layouts.',
        icon: Icons.system_update_alt,
      );
    }
    if (!manifest.settings.enableAppsSync) {
      return const _VibeAvailability(
        title: 'Apps Sync is off',
        message: 'Enable Apps Sync in Desktop → General to detect these apps.',
        icon: Icons.sync_disabled,
      );
    }
    if (application == null || !application.detected) {
      return const _VibeAvailability(
        title: 'App not installed',
        message: 'Install this app on the computer running LumiaKey Desktop.',
        icon: Icons.install_desktop,
      );
    }
    if (!application.running || !application.foreground) {
      return _VibeAvailability(
        title: '${application.name} is ready',
        message: 'Tap the app above to launch or focus it.',
        icon: Icons.open_in_new,
      );
    }
    return _VibeAvailability(
      title: '${application.name} is active',
      message: 'Vibe shortcuts and Local Dictation are ready.',
      icon: Icons.check_circle_outline,
      ready: true,
    );
  }
}

class _VibeAvailability {
  const _VibeAvailability({
    required this.title,
    required this.message,
    required this.icon,
    this.ready = false,
    this.error,
  });

  final String title;
  final String message;
  final IconData icon;
  final bool ready;
  final String? error;
}

class _VibeApplicationRequired extends StatelessWidget {
  const _VibeApplicationRequired({required this.mode, this.onConfigure});

  final ComputerMode mode;
  final VoidCallback? onConfigure;

  @override
  Widget build(BuildContext context) {
    final message = switch (mode) {
      ComputerMode.standalone =>
        'Choose Codex, Claude or Cursor in computer app settings to set up Vibe Coding.',
      ComputerMode.advanced =>
        'Install or enable app sync for Codex, Claude or Cursor on LumiaKey Desktop.',
      ComputerMode.disconnected =>
        'Connect to a computer to use Vibe Coding shortcuts.',
    };
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.terminal, size: 38),
            const SizedBox(height: 12),
            const Text(
              'Choose an app for Vibe Coding',
              key: ValueKey('vibe-app-required-title'),
            ),
            const SizedBox(height: 6),
            Text(message, textAlign: TextAlign.center),
            if (onConfigure != null) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: const ValueKey('vibe-app-required-configure'),
                onPressed: onConfigure,
                icon: const Icon(Icons.tune),
                label: const Text('Computer app settings'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _vibeApplicationLabel(String applicationId) => switch (applicationId) {
  'codex' => 'Codex',
  'claude' => 'Claude',
  'cursor' => 'Cursor',
  _ => 'App',
};

IconData _vibeApplicationIcon(String applicationId) => switch (applicationId) {
  'codex' => Icons.auto_awesome,
  'claude' => Icons.psychology_outlined,
  'cursor' => Icons.code,
  _ => Icons.terminal,
};

class _VibeStatusCard extends StatelessWidget {
  const _VibeStatusCard({
    required this.availability,
    required this.layoutName,
    required this.error,
    required this.pending,
    required this.onRefresh,
  });

  final _VibeAvailability availability;
  final String? layoutName;
  final String? error;
  final bool pending;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    final color = error == null
        ? availability.ready
              ? Theme.of(context).colorScheme.primary
              : Colors.amberAccent
        : Theme.of(context).colorScheme.error;
    final projectName = layoutName == null ? '' : ' · $layoutName';
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: Row(
          children: [
            if (pending)
              const SizedBox.square(
                dimension: 19,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Icon(
                error == null ? availability.icon : Icons.error_outline,
                color: color,
                size: 20,
              ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    error == null
                        ? availability.title
                        : 'Desktop action failed',
                    style: TextStyle(color: color, fontWeight: FontWeight.w700),
                  ),
                  Text(
                    error ?? '${availability.message}$projectName',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            if (onRefresh != null)
              IconButton(
                key: const ValueKey('vibe-refresh-desktop'),
                tooltip: 'Refresh Desktop connection',
                onPressed: pending ? null : onRefresh,
                icon: const Icon(Icons.refresh),
              ),
          ],
        ),
      ),
    );
  }
}

class _ProjectSetupHint extends StatelessWidget {
  const _ProjectSetupHint({required this.layoutName});

  final String layoutName;

  @override
  Widget build(BuildContext context) => Card(
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.folder_off_outlined, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Project switching is not assigned. Set it up in Desktop → Shortcut Layout → $layoutName.',
              key: const ValueKey('vibe-project-setup-hint'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    ),
  );
}

class _VibeShortcutButton extends StatelessWidget {
  const _VibeShortcutButton({
    required this.button,
    required this.enabled,
    required this.platform,
    required this.pending,
    required this.onPressed,
    required this.onLongPressStart,
    required this.onLongPressEnd,
    required this.onSecondaryTap,
    required this.onPointerStop,
    required this.alternateHint,
    required this.projectSetup,
    required this.projectLayoutName,
  });

  final RemoteShortcutButton button;
  final bool enabled;
  final ShortcutPlatform platform;
  final bool pending;
  final VoidCallback? onPressed;
  final VoidCallback? onLongPressStart;
  final VoidCallback? onLongPressEnd;
  final VoidCallback? onSecondaryTap;
  final VoidCallback? onPointerStop;
  final String? alternateHint;
  final bool projectSetup;
  final String projectLayoutName;

  @override
  Widget build(BuildContext context) {
    final keys = button.shortcut.map((key) {
      final upper = key.toUpperCase();
      return switch (upper) {
        'PRIMARY' => platform == ShortcutPlatform.apple ? '⌘' : 'Ctrl',
        'CTRL' => 'Ctrl',
        'ALT' => platform == ShortcutPlatform.apple ? 'Option' : 'Alt',
        'SHIFT' => 'Shift',
        _ => key,
      };
    });
    final shortcut = keys.join(' + ');
    final isVoice = button.targetType == RemoteTargetType.voiceInput;
    final icon = _shortcutIcon(
      button.icon,
      voice: isVoice,
      project: projectSetup,
    );
    final foreground = enabled
        ? Theme.of(context).colorScheme.onSurface
        : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.42);
    return Tooltip(
      message: projectSetup
          ? 'Project setup required · Desktop → Shortcut Layout → $projectLayoutName'
          : button.description.isEmpty
          ? button.name
          : '${button.name} · ${button.description}',
      child: MouseRegion(
        onExit: onPointerStop == null ? null : (_) => onPointerStop!(),
        child: Listener(
          onPointerUp: onPointerStop == null ? null : (_) => onPointerStop!(),
          onPointerCancel: onPointerStop == null
              ? null
              : (_) => onPointerStop!(),
          child: GestureDetector(
            onLongPressStart: onLongPressStart == null
                ? null
                : (_) => onLongPressStart!(),
            onLongPressEnd: onLongPressEnd == null
                ? null
                : (_) => onLongPressEnd!(),
            onSecondaryTap: onSecondaryTap,
            child: Material(
              color: const Color(0xFF151C26),
              borderRadius: BorderRadius.circular(12),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                key: ValueKey('vibe-button-${button.id}'),
                onTap: onPressed,
                child: Padding(
                  padding: const EdgeInsets.all(7),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (pending)
                        const SizedBox.square(
                          dimension: 25,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else
                        Icon(icon, size: 25, color: foreground),
                      const SizedBox(height: 4),
                      Text(
                        projectSetup
                            ? 'Project setup'
                            : isVoice
                            ? 'App Voice'
                            : _buttonLabel(button),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: foreground,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                      if (shortcut.isNotEmpty)
                        Text(
                          shortcut,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: foreground.withValues(alpha: 0.68),
                            fontSize: 9,
                          ),
                        ),
                      if (alternateHint != null)
                        Text(
                          alternateHint!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: foreground.withValues(alpha: 0.58),
                            fontSize: 8,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _buttonLabel(RemoteShortcutButton button) =>
      button.id.endsWith('.deleteToStart')
      ? 'Delete to Line Start'
      : button.name;

  static IconData _shortcutIcon(
    String name, {
    required bool voice,
    required bool project,
  }) {
    if (project) return Icons.folder_off_outlined;
    if (voice) return Icons.mic;
    return switch (name) {
      'folder_open' || 'folder_next' || 'folder_back' => Icons.folder_open,
      'terminal' => Icons.terminal,
      'add' => Icons.add,
      'search' || 'find_in_page' || 'menu' => Icons.search,
      'send' => Icons.send,
      'difference' || 'review' => Icons.difference,
      'menu_open' => Icons.menu_open,
      'arrow_up' || 'arrow_back' => Icons.arrow_back,
      'arrow_down' || 'arrow_next' => Icons.arrow_forward,
      'save' => Icons.save_outlined,
      'play' => Icons.play_arrow,
      'mic' => Icons.mic,
      'code' => Icons.code,
      _ => Icons.keyboard_alt_outlined,
    };
  }
}
