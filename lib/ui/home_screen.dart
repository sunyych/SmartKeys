import 'dart:async';
import 'dart:math' show sqrt;

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:local_dictation/local_dictation.dart';
import 'package:lumiakeys_protocol/lumiakeys_protocol.dart';

import '../app.dart';
import '../controllers/app_controller.dart';
import '../icons/icon_catalog.dart';
import '../models/config.dart';
import '../models/computer_setup.dart';
import '../models/control_surface_status.dart';
import '../services/hid_service.dart';
import '../services/ios_companion_hid_service.dart';
import 'button_editor_screen.dart';
import 'bluetooth_connection_sheet.dart';
import 'desktop_connection_panel.dart';
import 'computer_setup_wizard.dart';
import 'computer_switcher.dart';
import 'profile_management_screen.dart';
import 'settings_screen.dart';
import 'shortcut_community_screen.dart';
import 'dictation_entry_consent.dart';
import 'local_dictation_panel.dart';
import 'standalone_app_panel.dart';
import 'vibe_coding_panel.dart';
import 'wheel_editor_screen.dart';
import 'widgets/button_face.dart';
import 'widgets/jog_wheel.dart';
import 'widgets/mouse_touchpad.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    this.dictationModelManager,
    this.dictationCapture,
    this.dictationRecognizerFactory,
    this.enableDictationWakeLock,
    this.disableDictationWakeLock,
  });

  final ModelManager? dictationModelManager;
  final DictationCapture? dictationCapture;
  final Future<DictationRecognizer> Function(
    LocalAsrModelFiles,
    DictationLanguage,
  )?
  dictationRecognizerFactory;
  final Future<void> Function()? enableDictationWakeLock;
  final Future<void> Function()? disableDictationWakeLock;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool editing = false;
  _HomeTab selectedTab = _HomeTab.keyboard;
  String? selectedApplicationId;
  final GlobalKey<LocalDictationEntryButtonState> _dictationEntryKey =
      GlobalKey<LocalDictationEntryButtonState>();
  int _homeSelectionGeneration = 0;
  int? _pendingDesktopActivationGeneration;
  String? _pendingDesktopActivationApplicationId;
  int _computerTransitionGeneration = 0;
  bool _followForeground = true;
  bool _targetResetPending = false;
  String? _handledActivationToken;
  String? _lastScopeToken;
  String? _lastComputerId;
  int _activeBank = 0;

  @override
  Widget build(BuildContext context) {
    final controller = SmartKeysScope.of(context);
    final computer = controller.activeComputer;
    _trackComputerTarget(controller, computer);
    _consumeDesktopActivation(controller);
    final landscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    controller.registerLayoutOrientation(landscape);
    final mediaSize = MediaQuery.sizeOf(context);
    final shortestSide = mediaSize.shortestSide;
    final boardMode =
        switch (controller.config.preferences.controlSurfaceLayout) {
          ControlSurfaceLayout.phone => false,
          ControlSurfaceLayout.shortcutBoard => true,
          ControlSurfaceLayout.automatic => shortestSide >= 600,
        };
    final accent = controller.activeProfile.accentColor == null
        ? Theme.of(context).colorScheme.primary
        : Color(controller.activeProfile.accentColor!);
    final iosPairingGate =
        controller.hid is IosCompanionHidService ||
        defaultTargetPlatform == TargetPlatform.iOS;
    final desktopReconnecting =
        computer?.mode == ComputerMode.advanced && !controller.isDesktopSynced;
    final showFirstSetup =
        computer != null &&
        !controller.isActiveComputerSetupComplete &&
        (computer.mode == ComputerMode.standalone ||
            controller.isDesktopSynced);
    final availableApps = controller.availableComputerApplications;
    final selectedApplication = availableApps
        .cast<ComputerApplication?>()
        .firstWhere(
          (application) => application?.id == selectedApplicationId,
          orElse: () => null,
        );
    final applicationIsAvailable = selectedApplication != null;
    final foreground = controller.isDesktopSynced
        ? controller.foregroundApplication
        : null;
    final foregroundIsSelected =
        foreground != null &&
        availableApps.any((application) => application.id == foreground.id);
    var effectiveTab =
        selectedTab == _HomeTab.application &&
            selectedApplicationId != null &&
            !applicationIsAvailable
        ? _HomeTab.keyboard
        : selectedTab;
    if (_followForeground &&
        effectiveTab == _HomeTab.keyboard &&
        foregroundIsSelected) {
      selectedApplicationId = foreground.id;
      effectiveTab = _applicationTabFor(foreground.id);
    }
    final effectiveApplication = applicationIsAvailable
        ? selectedApplication
        : effectiveTab == _HomeTab.application && foregroundIsSelected
        ? availableApps.cast<ComputerApplication?>().firstWhere(
            (application) => application?.id == foreground.id,
            orElse: () => null,
          )
        : null;
    final selectedVibeApplicationId =
        selectedApplication?.category == ComputerAppCategory.vibeCoding &&
            applicationIsAvailable
        ? selectedApplication.id
        : _firstConfiguredVibeId(availableApps);
    final remoteApplication = effectiveApplication == null
        ? null
        : controller.desktopManifest?.applicationById(effectiveApplication.id);
    var remoteLayout =
        effectiveTab == _HomeTab.application &&
            computer?.mode == ComputerMode.advanced &&
            controller.isDesktopSynced &&
            effectiveApplication != null
        ? remoteApplication == null
              ? null
              : controller.layoutForApplication(remoteApplication)
        : effectiveTab == _HomeTab.keyboard &&
              controller.isDesktopSynced &&
              !desktopReconnecting
        ? controller.genericSyncedLayout
        : null;
    if (effectiveTab == _HomeTab.application &&
        effectiveApplication?.id == _pendingDesktopActivationApplicationId) {
      remoteLayout = remoteLayout?.copyWith(
        buttons: [
          for (final button in remoteLayout.buttons)
            button.copyWith(enabled: false),
        ],
      );
    }
    final keysPerPage = boardMode
        ? controller.config.preferences.tabletKeysPerPage
        : controlButtonCount;
    final scopeToken =
        '${mediaSize.width.round()}x${mediaSize.height.round()}:$boardMode:'
        '${controller.activeProfile.id}:${remoteLayout?.id}:$keysPerPage';
    if (_lastScopeToken != null && _lastScopeToken != scopeToken) {
      _activeBank = 0;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(controller.prepareForContextChange());
      });
    }
    _lastScopeToken = scopeToken;
    final expectedBankScope = scopeToken;
    final localCapacity = boardMode
        ? maxControlButtonCount
        : controller.activeProfile.buttons.fold<int>(
            controlButtonCount,
            (maxPosition, button) => maxPosition > button.position
                ? maxPosition
                : button.position + 1,
          );
    final effectiveBankCount = remoteLayout == null
        ? (localCapacity / keysPerPage).ceil()
        : (remoteLayout.buttons.length / keysPerPage).ceil().clamp(1, 99);
    if (_activeBank >= effectiveBankCount) _activeBank = 0;
    final keyboardSurface = boardMode
        ? _ShortcutBoard(
            key: const ValueKey('shortcut-board-layout'),
            controller: controller,
            editing: remoteLayout == null && editing,
            remoteLayout: remoteLayout,
            keysPerPage: keysPerPage,
            bank: _activeBank,
            onSelectBank: (bank) async {
              if (bank == _activeBank) return;
              await controller.prepareForContextChange();
              if (mounted && _lastScopeToken == expectedBankScope) {
                setState(() => _activeBank = bank);
              }
            },
            onToggleEditing: () => setState(() => editing = !editing),
          )
        : Column(
            children: [
              Expanded(
                child: landscape
                    ? _LandscapePanel(
                        key: const ValueKey('landscape-layout'),
                        controller: controller,
                        editing: remoteLayout == null && editing,
                        remoteLayout: remoteLayout,
                        startPosition: _activeBank * keysPerPage,
                        visibleCount: remoteLayout == null
                            ? (localCapacity - _activeBank * keysPerPage)
                                  .clamp(0, keysPerPage)
                                  .toInt()
                            : (remoteLayout.buttons.length -
                                      _activeBank * keysPerPage)
                                  .clamp(0, keysPerPage)
                                  .toInt(),
                        rowCountOverride: landscape ? 3 : 5,
                        onToggleEditing: () =>
                            setState(() => editing = !editing),
                      )
                    : _PortraitPanel(
                        key: const ValueKey('portrait-layout'),
                        controller: controller,
                        editing: remoteLayout == null && editing,
                        remoteLayout: remoteLayout,
                        startPosition: _activeBank * keysPerPage,
                        visibleCount: remoteLayout == null
                            ? (localCapacity - _activeBank * keysPerPage)
                                  .clamp(0, keysPerPage)
                                  .toInt()
                            : (remoteLayout.buttons.length -
                                      _activeBank * keysPerPage)
                                  .clamp(0, keysPerPage)
                                  .toInt(),
                        rowCountOverride: landscape ? 3 : 5,
                        onToggleEditing: () =>
                            setState(() => editing = !editing),
                      ),
              ),
              if (effectiveBankCount > 1)
                _PhoneBankNavigation(
                  bank: _activeBank,
                  bankCount: effectiveBankCount,
                  onSelect: (bank) async {
                    await controller.prepareForContextChange();
                    if (mounted && _lastScopeToken == expectedBankScope) {
                      setState(() => _activeBank = bank);
                    }
                  },
                ),
            ],
          );
    Future<void> selectTab(_HomeTab tab) async {
      final selectedVibe = tab == _HomeTab.vibeCoding
          ? (selectedApplication?.category == ComputerAppCategory.vibeCoding &&
                    applicationIsAvailable
                ? selectedApplication.id
                : _firstConfiguredVibeId(availableApps))
          : null;
      final generation = ++_homeSelectionGeneration;
      if (_pendingDesktopActivationGeneration != null) {
        setState(() {
          _pendingDesktopActivationGeneration = null;
          _pendingDesktopActivationApplicationId = null;
        });
      }
      if (tab != selectedTab ||
          selectedApplicationId != selectedVibe ||
          tab == _HomeTab.vibeCoding) {
        await _stopVibeDictation();
        await controller.prepareForContextChange();
      }
      if (!mounted || generation != _homeSelectionGeneration) return;
      setState(() {
        selectedTab = tab;
        selectedApplicationId = selectedVibe;
        editing = false;
        _activeBank = 0;
        _followForeground = false;
      });
    }

    Future<void> selectApplication(ComputerApplication application) async {
      final target = computer;
      if (target == null) return;
      if (target.mode == ComputerMode.advanced &&
          _pendingDesktopActivationApplicationId == application.id) {
        return;
      }
      final messenger = ScaffoldMessenger.of(context);
      final generation = ++_homeSelectionGeneration;
      await _stopVibeDictation();
      final afterStop = controller.activeComputer;
      if (!mounted ||
          generation != _homeSelectionGeneration ||
          afterStop?.id != target.id ||
          afterStop?.mode != target.mode ||
          target.mode == ComputerMode.advanced && !controller.isDesktopSynced) {
        return;
      }
      await controller.prepareForContextChange();
      if (!mounted || generation != _homeSelectionGeneration) return;
      final afterRelease = controller.activeComputer;
      if (afterRelease?.id != target.id ||
          afterRelease?.mode != target.mode ||
          target.mode == ComputerMode.advanced && !controller.isDesktopSynced) {
        return;
      }
      setState(() {
        selectedTab = _applicationTabFor(application.id);
        selectedApplicationId = application.id;
        editing = false;
        _activeBank = 0;
        _followForeground = false;
        if (target.mode == ComputerMode.advanced) {
          _pendingDesktopActivationGeneration = generation;
          _pendingDesktopActivationApplicationId = application.id;
        }
      });
      try {
        if (target.mode == ComputerMode.advanced) {
          final remote = controller.desktopManifest?.applicationById(
            application.id,
          );
          if (remote == null) {
            throw StateError('${application.name} is unavailable in Desktop.');
          }
          await controller.launchRemoteApplication(remote);
        }
      } catch (error) {
        if (mounted &&
            generation == _homeSelectionGeneration &&
            controller.activeComputer?.id == target.id &&
            controller.activeComputer?.mode == target.mode) {
          messenger.showSnackBar(SnackBar(content: Text('$error')));
        }
      } finally {
        if (mounted && _pendingDesktopActivationGeneration == generation) {
          setState(() {
            _pendingDesktopActivationGeneration = null;
            _pendingDesktopActivationApplicationId = null;
          });
        }
      }
    }

    Future<void> editComputerSetup() async {
      if (computer == null) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (routeContext) => Scaffold(
            body: ComputerSetupWizard(
              controller: controller,
              target: computer,
              initialSetup: controller.activeComputerSetup,
              onSaved: () => Navigator.of(routeContext).pop(),
              onCancel: () => Navigator.of(routeContext).pop(),
            ),
          ),
        ),
      );
    }

    final content = switch (effectiveTab) {
      _HomeTab.keyboard => keyboardSurface,
      _HomeTab.application =>
        computer == null || effectiveApplication == null
            ? keyboardSurface
            : computer.mode == ComputerMode.standalone
            ? StandaloneAppPanel(
                controller: controller,
                target: computer,
                application: effectiveApplication,
                onConfigure: editComputerSetup,
              )
            : remoteLayout == null
            ? _NoManagedAppLayout(
                applicationName: effectiveApplication.name,
                onManage: editComputerSetup,
              )
            : keyboardSurface,
      _HomeTab.vibeCoding => VibeCodingPanel(
        controller: controller,
        target: computer,
        selectedApplicationId: selectedVibeApplicationId,
        activationPending:
            _pendingDesktopActivationApplicationId == selectedVibeApplicationId,
        onConfigure: computer == null ? null : editComputerSetup,
        onBeforeContextChange: _stopVibeDictation,
        onStartDictation: () =>
            _startVibeDictation(controller, selectedVibeApplicationId),
        onStopDictation: _stopVibeDictation,
      ),
    };
    final iOSGateContent =
        iosPairingGate && computer?.mode != ComputerMode.advanced
        ? ListView(
            key: const ValueKey('ios-desktop-pairing-gate'),
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Connect LumiaKey Desktop',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              const Text(
                'On iPhone and iPad, LumiaKey needs its paired Desktop app to choose apps and send shortcuts.',
              ),
              const SizedBox(height: 16),
              DesktopConnectionPanel(companion: controller.companion),
            ],
          )
        : null;
    final setupContent = showFirstSetup
        ? ComputerSetupWizard(
            key: ValueKey('first-computer-setup-${computer.id}'),
            controller: controller,
            target: computer,
            initialSetup: controller.activeComputerSetup,
            onSaved: () => setState(() {
              selectedTab = _HomeTab.keyboard;
              selectedApplicationId = null;
              _followForeground = false;
            }),
          )
        : null;
    final safeContent = desktopReconnecting && !showFirstSetup
        ? _DesktopReconnectState(onManage: editComputerSetup)
        : setupContent ?? content;
    final visibleProfiles = controller.visibleHomeProfiles
        .where(
          (profile) =>
              computer == null ||
              profile.id != 'profile_web' && profile.id != 'profile_meetings',
        )
        .toList(growable: false);
    final showComputerAppBar =
        !showFirstSetup &&
        computer != null &&
        controller.isActiveComputerSetupComplete &&
        iOSGateContent == null;

    return Theme(
      data: Theme.of(context).copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: accent,
          brightness: Brightness.dark,
          surface: const Color(0xFF10151D),
        ),
      ),
      child: Scaffold(
        body: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  if (iOSGateContent != null) ...[
                    ComputerSwitcher(controller: controller),
                    Expanded(child: iOSGateContent),
                  ] else if (showFirstSetup) ...[
                    ComputerSwitcher(controller: controller),
                    Expanded(child: safeContent),
                  ] else ...[
                    if (showComputerAppBar)
                      _ComputerApplicationBar(
                        controller: controller,
                        applications: availableApps,
                        selectedApplicationId: applicationIsAvailable
                            ? selectedApplicationId
                            : null,
                        onSelectApplication: selectApplication,
                        onManage: editComputerSetup,
                      ),
                    Padding(
                      padding: EdgeInsets.fromLTRB(10, 10, 190, 6),
                      child: Row(
                        children: [
                          if (!showComputerAppBar) ...[
                            ComputerSwitcher(
                              controller: controller,
                              compact: true,
                            ),
                            const SizedBox(width: 4),
                          ],
                          Expanded(
                            child: _HomeTabBar(
                              controller: controller,
                              profiles: visibleProfiles,
                              activeProfileId: controller.activeProfile.id,
                              selectedTab: effectiveTab,
                              onSelectTab: selectTab,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: ValueListenableBuilder<String?>(
                        valueListenable: controller.hid.errorMessage,
                        builder: (context, error, _) => Column(
                          children: [
                            if (error != null)
                              Material(
                                key: const ValueKey('control-surface-error'),
                                color: Theme.of(
                                  context,
                                ).colorScheme.errorContainer,
                                child: SizedBox(
                                  width: double.infinity,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 5,
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.error_outline,
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onErrorContainer,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Tooltip(
                                            message: error,
                                            child: Text(
                                              error,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: Theme.of(
                                                  context,
                                                ).colorScheme.onErrorContainer,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            Expanded(child: safeContent),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              if (iOSGateContent == null && !showFirstSetup)
                Positioned(
                  top: showComputerAppBar ? 47 : 7,
                  right: 10,
                  child: _CompactControlMenu(
                    controller: controller,
                    editing: editing,
                    onToggleEditing: () => setState(() => editing = !editing),
                  ),
                ),
              if (iOSGateContent == null && !showFirstSetup)
                Positioned.fill(
                  child: LocalDictationEntryButton(
                    key: _dictationEntryKey,
                    hid: controller.hid,
                    topOffset: showComputerAppBar ? 47 : 7,
                    companion: controller.companion,
                    forceDesktopOutput: controller.hasPinnedDesktopComputer,
                    modelManager: widget.dictationModelManager,
                    capture: widget.dictationCapture,
                    recognizerFactory: widget.dictationRecognizerFactory,
                    enableWakeLock: widget.enableDictationWakeLock,
                    disableWakeLock: widget.disableDictationWakeLock,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _consumeDesktopActivation(AppController controller) {
    if (_targetResetPending) return;
    final manifest = controller.desktopManifest;
    final host = controller.companion.activeHost.value;
    final appId = manifest?.activatedApplicationId;
    final sequence = manifest?.applicationActivationSequence ?? 0;
    if (!controller.isDesktopSynced ||
        host == null ||
        appId == null ||
        sequence <= 0) {
      return;
    }
    final token = '${host.token}:$sequence';
    if (_handledActivationToken == token) return;
    if (!controller.availableComputerApplications.any(
      (application) => application.id == appId,
    )) {
      return;
    }
    final app = controller.syncedApplications
        .cast<RemoteApplication?>()
        .firstWhere(
          (candidate) =>
              candidate?.id == appId && candidate?.foreground == true,
          orElse: () => null,
        );
    if (app == null ||
        controller.layoutForApplication(app)?.buttons.isEmpty != false) {
      return;
    }
    _handledActivationToken = token;
    selectedTab = _applicationTabFor(app.id);
    selectedApplicationId = app.id;
    editing = false;
    _followForeground = false;
  }

  void _trackComputerTarget(AppController controller, ComputerTarget? target) {
    if (_lastComputerId == target?.id) return;
    final oldId = _lastComputerId;
    final wasResetPending = _targetResetPending;
    _lastComputerId = target?.id;
    ++_homeSelectionGeneration;
    _pendingDesktopActivationGeneration = null;
    _pendingDesktopActivationApplicationId = null;
    final transitionGeneration = ++_computerTransitionGeneration;
    if (oldId != null || wasResetPending) {
      _targetResetPending = true;
      selectedTab = _HomeTab.keyboard;
      selectedApplicationId = null;
      _activeBank = 0;
      _followForeground = false;
    } else {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _stopVibeDictation();
      if (!mounted ||
          transitionGeneration != _computerTransitionGeneration ||
          _lastComputerId != target?.id) {
        return;
      }
      await controller.prepareForContextChange();
      if (!mounted ||
          transitionGeneration != _computerTransitionGeneration ||
          _lastComputerId != target?.id) {
        return;
      }
      setState(() {
        _targetResetPending = false;
      });
    });
  }

  Future<void> _startVibeDictation(
    AppController controller,
    String applicationId,
  ) async {
    final manifest = controller.desktopManifest;
    if (controller.computerMode != ComputerMode.advanced ||
        !controller.isDesktopSynced ||
        manifest?.applicationById(applicationId)?.foreground != true) {
      throw StateError(
        'Focus ${_vibeApplicationLabel(applicationId)} before starting Local Dictation.',
      );
    }
    final entry = _dictationEntryKey.currentState;
    if (entry == null) {
      throw StateError('Local Dictation is not ready yet.');
    }
    await entry.startQuickDictation(forceDesktopOutput: true);
  }

  Future<void> _stopVibeDictation() async {
    await _dictationEntryKey.currentState?.stopQuickDictation();
  }
}

String _vibeApplicationLabel(String applicationId) => switch (applicationId) {
  'codex' => 'Codex',
  'claude' => 'Claude',
  'cursor' => 'Cursor',
  _ => 'the selected app',
};

_HomeTab _applicationTabFor(String applicationId) =>
    computerApplicationById(applicationId)?.category ==
        ComputerAppCategory.vibeCoding
    ? _HomeTab.vibeCoding
    : _HomeTab.application;

String _firstConfiguredVibeId(List<ComputerApplication> applications) {
  for (final application in applications) {
    if (application.category == ComputerAppCategory.vibeCoding) {
      return application.id;
    }
  }
  return '';
}

int _boardColumns(int keysPerPage, bool landscape) {
  final scale = landscape ? 1.25 : 0.8;
  return (sqrt(keysPerPage) * scale).round();
}

enum _HomeTab { keyboard, application, vibeCoding }

extension on _HomeTab {
  String get label => switch (this) {
    _HomeTab.keyboard => 'Keyboard',
    _HomeTab.application => 'Application',
    _HomeTab.vibeCoding => 'Vibe Coding',
  };

  IconData get icon => switch (this) {
    _HomeTab.keyboard => Icons.keyboard_alt_outlined,
    _HomeTab.application => Icons.layers_outlined,
    _HomeTab.vibeCoding => Icons.terminal,
  };
}

class _ShortcutBoard extends StatelessWidget {
  const _ShortcutBoard({
    super.key,
    required this.controller,
    required this.editing,
    required this.remoteLayout,
    required this.keysPerPage,
    required this.bank,
    required this.onSelectBank,
    required this.onToggleEditing,
  });

  final AppController controller;
  final bool editing;
  final RemoteShortcutLayout? remoteLayout;
  final int keysPerPage;
  final int bank;
  final ValueChanged<int> onSelectBank;
  final VoidCallback onToggleEditing;

  @override
  Widget build(BuildContext context) {
    final landscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final columns = _boardColumns(keysPerPage, landscape);
    final rows = (keysPerPage / columns).ceil();
    final banks = remoteLayout == null
        ? (maxControlButtonCount / keysPerPage).ceil()
        : (remoteLayout!.buttons.length / keysPerPage).ceil().clamp(1, 99);
    final start = bank * keysPerPage;
    final visibleCount = remoteLayout == null
        ? (maxControlButtonCount - start).clamp(0, keysPerPage).toInt()
        : (remoteLayout!.buttons.length - start).clamp(1, keysPerPage).toInt();
    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
            child: remoteLayout == null
                ? _ButtonGrid(
                    controller: controller,
                    editing: editing,
                    columns: columns,
                    startPosition: start,
                    visibleCount: visibleCount,
                    rowCountOverride: rows,
                  )
                : _RemoteButtonGrid(
                    controller: controller,
                    layout: remoteLayout!,
                    columns: columns,
                    startIndex: start,
                    visibleCount: visibleCount,
                    rowCountOverride: rows,
                  ),
          ),
        ),
        const Divider(height: 1),
        SizedBox(
          height: 48,
          child: Row(
            children: [
              const SizedBox(width: 10),
              IconButton(
                key: const ValueKey('board-bank-previous'),
                tooltip: 'Previous bank',
                onPressed: bank > 0 ? () => onSelectBank(bank - 1) : null,
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Center(
                  child: Text(
                    'Bank ${bank + 1} of $banks',
                    key: const ValueKey('board-bank-label'),
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
              ),
              if (remoteLayout == null)
                TextButton.icon(
                  key: const ValueKey('board-edit-toggle'),
                  onPressed: onToggleEditing,
                  icon: Icon(editing ? Icons.check : Icons.edit_outlined),
                  label: Text(editing ? 'Done' : 'Edit'),
                ),
              IconButton(
                key: const ValueKey('board-bank-next'),
                tooltip: 'Next bank',
                onPressed: bank + 1 < banks
                    ? () => onSelectBank(bank + 1)
                    : null,
                icon: const Icon(Icons.chevron_right),
              ),
              const SizedBox(width: 10),
            ],
          ),
        ),
      ],
    );
  }
}

class _PhoneBankNavigation extends StatelessWidget {
  const _PhoneBankNavigation({
    required this.bank,
    required this.bankCount,
    required this.onSelect,
  });

  final int bank;
  final int bankCount;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 42,
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          tooltip: 'Previous bank',
          onPressed: bank > 0 ? () => onSelect(bank - 1) : null,
          icon: const Icon(Icons.chevron_left),
        ),
        Text('Bank ${bank + 1} of $bankCount'),
        IconButton(
          tooltip: 'Next bank',
          onPressed: bank + 1 < bankCount ? () => onSelect(bank + 1) : null,
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    ),
  );
}

class _PortraitPanel extends StatelessWidget {
  const _PortraitPanel({
    super.key,
    required this.controller,
    required this.editing,
    required this.remoteLayout,
    required this.startPosition,
    required this.visibleCount,
    required this.rowCountOverride,
    required this.onToggleEditing,
  });

  final AppController controller;
  final bool editing;
  final RemoteShortcutLayout? remoteLayout;
  final int startPosition;
  final int visibleCount;
  final int rowCountOverride;
  final VoidCallback onToggleEditing;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          key: const ValueKey('key-region'),
          flex: 62,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
            child: remoteLayout == null
                ? _ButtonGrid(
                    controller: controller,
                    editing: editing,
                    columns: 3,
                    startPosition: startPosition,
                    visibleCount: visibleCount,
                    rowCountOverride: rowCountOverride,
                  )
                : _RemoteButtonGrid(
                    controller: controller,
                    layout: remoteLayout!,
                    columns: 3,
                    startIndex: startPosition,
                    visibleCount: visibleCount,
                    rowCountOverride: rowCountOverride,
                  ),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          key: const ValueKey('wheel-region'),
          flex: 33,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: _WheelPanel(
              controller: controller,
              editing: editing,
              onToggleEditing: onToggleEditing,
            ),
          ),
        ),
      ],
    );
  }
}

class _LandscapePanel extends StatelessWidget {
  const _LandscapePanel({
    super.key,
    required this.controller,
    required this.editing,
    required this.remoteLayout,
    required this.startPosition,
    required this.visibleCount,
    required this.rowCountOverride,
    required this.onToggleEditing,
  });

  final AppController controller;
  final bool editing;
  final RemoteShortcutLayout? remoteLayout;
  final int startPosition;
  final int visibleCount;
  final int rowCountOverride;
  final VoidCallback onToggleEditing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          key: const ValueKey('key-region'),
          flex: 2,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: remoteLayout == null
                ? _ButtonGrid(
                    controller: controller,
                    editing: editing,
                    columns: 5,
                    startPosition: startPosition,
                    visibleCount: visibleCount,
                    rowCountOverride: rowCountOverride,
                  )
                : _RemoteButtonGrid(
                    controller: controller,
                    layout: remoteLayout!,
                    columns: 5,
                    startIndex: startPosition,
                    visibleCount: visibleCount,
                    rowCountOverride: rowCountOverride,
                  ),
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          key: const ValueKey('wheel-region'),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: _WheelPanel(
              controller: controller,
              editing: editing,
              onToggleEditing: onToggleEditing,
            ),
          ),
        ),
      ],
    );
  }
}

class _HomeTabBar extends StatelessWidget {
  const _HomeTabBar({
    required this.controller,
    required this.profiles,
    required this.activeProfileId,
    required this.selectedTab,
    required this.onSelectTab,
  });

  final AppController controller;
  final List<ProfileConfig> profiles;
  final String activeProfileId;
  final _HomeTab selectedTab;
  final ValueChanged<_HomeTab> onSelectTab;

  @override
  Widget build(BuildContext context) {
    Widget vibeChip() => _HomeTabChip(
      key: const ValueKey('home-tab-vibe-coding'),
      label: _HomeTab.vibeCoding.label,
      icon: Icon(_HomeTab.vibeCoding.icon),
      selected: selectedTab == _HomeTab.vibeCoding,
      onTap: () => onSelectTab(_HomeTab.vibeCoding),
    );

    final items = <Widget>[];
    var insertedVibe = false;
    for (final profile in profiles) {
      if (profile.id == 'profile_custom') {
        items.add(vibeChip());
        insertedVibe = true;
      }
      items.add(
        _HomeTabChip(
          key: ValueKey('profile-quick-${profile.id}'),
          label: profile.name,
          icon: Icon(
            BuiltinIconCatalog.find(profile.profileIcon.value)?.icon ??
                Icons.dashboard_outlined,
          ),
          selected:
              selectedTab == _HomeTab.keyboard && profile.id == activeProfileId,
          onTap: () {
            onSelectTab(_HomeTab.keyboard);
            controller.switchProfile(profile.id);
          },
        ),
      );
    }
    if (!insertedVibe) items.add(vibeChip());
    return SizedBox(
      key: const ValueKey('profile-quick-switch-bar'),
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (context, index) => items[index],
      ),
    );
  }
}

class _ComputerApplicationBar extends StatelessWidget {
  const _ComputerApplicationBar({
    required this.controller,
    required this.applications,
    required this.selectedApplicationId,
    required this.onSelectApplication,
    required this.onManage,
  });

  final AppController controller;
  final List<ComputerApplication> applications;
  final String? selectedApplicationId;
  final ValueChanged<ComputerApplication> onSelectApplication;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) => SizedBox(
    key: const ValueKey('computer-app-row'),
    height: 42,
    child: Row(
      children: [
        Expanded(
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            itemCount: applications.length,
            separatorBuilder: (_, _) => const SizedBox(width: 6),
            itemBuilder: (context, index) {
              final application = applications[index];
              final remote = computerApplicationById(application.id);
              final selected = application.id == selectedApplicationId;
              final icon = _computerApplicationIcon(application.id);
              return _HomeTabChip(
                key: ValueKey('workspace-app-${application.id}'),
                label: remote?.name ?? application.name,
                icon: Icon(icon),
                selected: selected,
                onTap: () => onSelectApplication(application),
              );
            },
          ),
        ),
        ComputerSwitcher(controller: controller, compact: true),
        IconButton(
          key: const ValueKey('computer-app-manage'),
          tooltip: 'Choose computer apps and set up shortcuts',
          onPressed: onManage,
          icon: const Icon(Icons.tune),
        ),
      ],
    ),
  );
}

IconData _computerApplicationIcon(String id) => switch (id) {
  'chrome' || 'firefox' || 'edge' || 'safari' => Icons.language,
  'teams' || 'zoom' => Icons.video_call_outlined,
  'codex' => Icons.auto_awesome,
  'claude' => Icons.psychology_outlined,
  'cursor' => Icons.code,
  'chatgpt' => Icons.chat_bubble_outline,
  _ => Icons.apps,
};

class _HomeTabChip extends StatelessWidget {
  const _HomeTabChip({
    super.key,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final Widget icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      label: label,
      child: Material(
        color: selected
            ? Theme.of(context).colorScheme.primaryContainer
            : const Color(0xFF151C26),
        shape: StadiumBorder(
          side: BorderSide(
            color: selected
                ? Theme.of(context).colorScheme.primary
                : Colors.white12,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 13),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconTheme(
                  data: IconThemeData(
                    size: 16,
                    color: selected
                        ? Theme.of(context).colorScheme.onPrimaryContainer
                        : Colors.white60,
                  ),
                  child: SizedBox.square(dimension: 16, child: icon),
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DesktopReconnectState extends StatelessWidget {
  const _DesktopReconnectState({required this.onManage});

  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.sync, size: 38),
          const SizedBox(height: 12),
          Text(
            'Reconnect to LumiaKey Desktop',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          const Text(
            'This computer uses the Desktop mode saved for it. Check the pairing connection to continue.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            key: const ValueKey('desktop-reconnect-manage'),
            onPressed: onManage,
            icon: const Icon(Icons.tune),
            label: const Text('Connection and app settings'),
          ),
        ],
      ),
    ),
  );
}

class _NoManagedAppLayout extends StatelessWidget {
  const _NoManagedAppLayout({
    required this.applicationName,
    required this.onManage,
  });

  final String applicationName;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$applicationName is not ready in LumiaKey Desktop.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: onManage,
            icon: const Icon(Icons.tune),
            label: const Text('App settings'),
          ),
        ],
      ),
    ),
  );
}

class _RemoteButtonGrid extends StatelessWidget {
  const _RemoteButtonGrid({
    required this.controller,
    required this.layout,
    required this.columns,
    this.startIndex = 0,
    this.visibleCount = controlButtonCount,
    this.rowCountOverride,
  });

  final AppController controller;
  final RemoteShortcutLayout layout;
  final int columns;
  final int startIndex;
  final int visibleCount;
  final int? rowCountOverride;

  @override
  Widget build(BuildContext context) {
    final buttons = layout.buttons.skip(startIndex).take(visibleCount).toList();
    final count = visibleCount < 1 ? 1 : visibleCount;
    final rows = rowCountOverride ?? (count / columns).ceil();
    return LayoutBuilder(
      builder: (context, constraints) {
        const horizontalSpacing = 4.0;
        const verticalSpacing = 8.0;
        final width =
            (constraints.maxWidth - horizontalSpacing * (columns - 1)) /
            columns;
        final height =
            (constraints.maxHeight - verticalSpacing * (rows - 1)) / rows;
        return GridView.builder(
          key: ValueKey('remote-layout-${layout.id}'),
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          itemCount: count,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: horizontalSpacing,
            mainAxisSpacing: verticalSpacing,
            childAspectRatio: width / height,
          ),
          itemBuilder: (context, index) {
            if (index >= buttons.length) {
              return Material(
                color: const Color(0xFF10151D),
                borderRadius: BorderRadius.circular(14),
              );
            }
            final button = buttons[index];
            final appVoiceInput =
                button.targetType == RemoteTargetType.voiceInput;
            return Semantics(
              button: true,
              label: appVoiceInput
                  ? 'Application voice input, starts the selected app voice shortcut'
                  : button.name,
              child: Tooltip(
                message: appVoiceInput
                    ? 'Application voice input · runs the selected app shortcut'
                    : button.name,
                child: Material(
                  color: const Color(0xFF151C26),
                  borderRadius: BorderRadius.circular(14),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    key: ValueKey('remote-button-${button.id}'),
                    onTap: button.enabled
                        ? () async {
                            if (button.targetType ==
                                    RemoteTargetType.voiceInput &&
                                !await ensureDictationEntryExplained(context)) {
                              return;
                            }
                            if (!context.mounted) return;
                            await controller.executeRemoteButton(button);
                          }
                        : null,
                    child: LayoutBuilder(
                      builder: (context, cellConstraints) {
                        final compact = cellConstraints.maxHeight < 64;
                        final title = appVoiceInput
                            ? 'App voice input'
                            : button.name;
                        final shortcut =
                            button.targetType ==
                                RemoteTargetType.keyboardShortcut
                            ? formatShortcut(button.shortcut)
                            : null;
                        return Padding(
                          padding: EdgeInsets.all(compact ? 4 : 9),
                          child: compact
                              ? Row(
                                  children: [
                                    Icon(
                                      appVoiceInput
                                          ? Icons.graphic_eq
                                          : remoteIcon(button.icon),
                                      size: 18,
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            title,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          if (shortcut != null)
                                            Text(
                                              shortcut,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontSize: 9,
                                                color: Colors.white54,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ],
                                )
                              : Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      appVoiceInput
                                          ? Icons.graphic_eq
                                          : remoteIcon(button.icon),
                                      size: 25,
                                    ),
                                    const SizedBox(height: 5),
                                    Text(
                                      title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    if (shortcut != null)
                                      Text(
                                        shortcut,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 10,
                                          color: Colors.white54,
                                        ),
                                      ),
                                  ],
                                ),
                        );
                      },
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

IconData remoteIcon(String id) => switch (id) {
  'copy' => Icons.copy,
  'paste' => Icons.paste,
  'undo' => Icons.undo,
  'redo' => Icons.redo,
  'cut' => Icons.content_cut,
  'play' => Icons.play_arrow,
  'pause' => Icons.pause,
  'skip_next' => Icons.skip_next,
  'skip_previous' => Icons.skip_previous,
  'save' => Icons.save,
  'search' => Icons.search,
  'find_in_page' => Icons.find_in_page_outlined,
  'terminal' => Icons.terminal,
  'code' => Icons.code,
  'bug' => Icons.bug_report,
  'comment' => Icons.comment,
  'format' => Icons.format_align_left,
  'folder_open' => Icons.folder_open,
  'source_control' => Icons.account_tree,
  'image' => Icons.image,
  'draw' => Icons.draw,
  'view_in_ar' => Icons.view_in_ar,
  'movie' => Icons.movie,
  'language' => Icons.language,
  'check' => Icons.check,
  'close' => Icons.close,
  'arrow_next' => Icons.arrow_forward,
  'arrow_back' => Icons.arrow_back,
  'auto_awesome' => Icons.auto_awesome,
  'difference' => Icons.difference,
  'commit' => Icons.commit,
  'upload' => Icons.upload,
  'download' => Icons.download,
  'help' => Icons.help_outline,
  'build' => Icons.build,
  'refresh' => Icons.refresh,
  'export' => Icons.ios_share,
  'transform' => Icons.transform,
  'group' => Icons.group_work,
  'restore' => Icons.restore,
  'link' => Icons.link,
  'bookmark' => Icons.bookmark_outline,
  'password' => Icons.password,
  'volume_off' => Icons.volume_off,
  'volume_up' => Icons.volume_up,
  'volume_down' => Icons.volume_down,
  'music' => Icons.music_note,
  'map' => Icons.map_outlined,
  'calendar' => Icons.calendar_month_outlined,
  'journal' => Icons.edit_note,
  'note' => Icons.note_alt_outlined,
  'home' => Icons.home_outlined,
  'zoom_in' => Icons.zoom_in,
  'zoom_out' => Icons.zoom_out,
  'select_all' => Icons.select_all,
  'find_replace' => Icons.find_replace,
  'print' => Icons.print_outlined,
  'create_new_folder' => Icons.create_new_folder_outlined,
  'info' => Icons.info_outline,
  'delete' => Icons.delete_outline,
  'grid_view' => Icons.grid_view,
  'view_list' => Icons.view_list,
  'view_column' => Icons.view_column,
  'visibility' => Icons.visibility_outlined,
  'add' => Icons.add,
  'mic' => Icons.mic,
  'send' => Icons.send,
  'menu' => Icons.manage_search_outlined,
  'menu_open' => Icons.menu_open,
  'folder_back' => Icons.drive_folder_upload_outlined,
  'folder_next' => Icons.next_plan_outlined,
  'arrow_up' => Icons.keyboard_arrow_up,
  'arrow_down' => Icons.keyboard_arrow_down,
  'stop' => Icons.stop_circle_outlined,
  'science' => Icons.science_outlined,
  _ => Icons.keyboard_command_key,
};

class _ButtonGrid extends StatelessWidget {
  const _ButtonGrid({
    required this.controller,
    required this.editing,
    required this.columns,
    this.startPosition = 0,
    this.visibleCount = controlButtonCount,
    this.rowCountOverride,
  });

  final AppController controller;
  final bool editing;
  final int columns;
  final int startPosition;
  final int visibleCount;
  final int? rowCountOverride;

  @override
  Widget build(BuildContext context) {
    final byPosition = {
      for (final button in controller.activeProfile.buttons)
        button.position: button,
    };
    final buttons = List.generate(
      visibleCount,
      (index) =>
          byPosition[startPosition + index] ??
          ButtonConfig.empty(startPosition + index),
      growable: false,
    );
    final rows = rowCountOverride ?? (visibleCount / columns).ceil();
    return LayoutBuilder(
      builder: (context, constraints) {
        const horizontalSpacing = 4.0;
        const verticalSpacing = 8.0;
        final width =
            (constraints.maxWidth - horizontalSpacing * (columns - 1)) /
            columns;
        final height =
            (constraints.maxHeight - verticalSpacing * (rows - 1)) / rows;
        return GridView.builder(
          key: ValueKey('button-grid-${columns}x$rows'),
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: horizontalSpacing,
            mainAxisSpacing: verticalSpacing,
            childAspectRatio: width / height,
          ),
          itemCount: visibleCount,
          itemBuilder: (context, index) {
            final button = buttons[index];
            final control = Semantics(
              button: true,
              label: '${button.position + 1}. ${button.label}',
              hint: editing ? 'Long press and drag to swap position' : null,
              child: GestureDetector(
                key: ValueKey('control-button-${button.position}'),
                behavior: HitTestBehavior.opaque,
                onTap: editing
                    ? () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              ButtonEditorScreen(position: button.position),
                        ),
                      )
                    : null,
                onTapDown: editing
                    ? null
                    : (_) => controller.pressButton(button),
                onTapUp: editing
                    ? null
                    : (_) => controller.releaseButton(button),
                onTapCancel: editing
                    ? null
                    : () => controller.releaseButton(button),
                child: ButtonFace(
                  button: button,
                  imageStore: controller.imageStore,
                  shortcutLabel: controller.resolveShortcutLabel(button),
                  pressed:
                      controller.pressedPositions.contains(button.position) ||
                      (button.action.type == ActionType.companion &&
                          button.action.value?.contains('"kind":"dark"') ==
                              true &&
                          controller.isDarkModeActive),
                  editing: editing,
                ),
              ),
            );
            if (!editing) return control;
            return DragTarget<int>(
              onWillAcceptWithDetails: (details) =>
                  details.data != button.position,
              onAcceptWithDetails: (details) =>
                  controller.swapButtons(details.data, button.position),
              builder: (context, candidates, rejected) {
                final highlighted = candidates.any(
                  (position) => position != button.position,
                );
                return LongPressDraggable<int>(
                  data: button.position,
                  delay: const Duration(milliseconds: 300),
                  feedback: Material(
                    color: Colors.transparent,
                    child: SizedBox(
                      key: const ValueKey('button-drag-feedback'),
                      width: width,
                      height: height,
                      child: Transform.scale(
                        scale: 1.04,
                        child: ButtonFace(
                          button: button,
                          imageStore: controller.imageStore,
                          shortcutLabel: controller.resolveShortcutLabel(
                            button,
                          ),
                          pressed: true,
                          editing: true,
                        ),
                      ),
                    ),
                  ),
                  childWhenDragging: Opacity(opacity: 0.24, child: control),
                  child: AnimatedScale(
                    scale: highlighted ? 0.94 : 1,
                    duration: const Duration(milliseconds: 90),
                    child: control,
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

class _WheelPanel extends StatelessWidget {
  const _WheelPanel({
    required this.controller,
    required this.editing,
    required this.onToggleEditing,
  });

  final AppController controller;
  final bool editing;
  final VoidCallback onToggleEditing;

  @override
  Widget build(BuildContext context) {
    final wheel = controller.activeProfile.wheel;
    final isTouchpad = wheel.controlType == WheelControlType.mousePad;
    final desktopKeyboardOnly = controller.hid is IosCompanionHidService;
    final panel = Stack(
      fit: StackFit.expand,
      children: [
        AbsorbPointer(
          absorbing: editing,
          child: isTouchpad && desktopKeyboardOnly
              ? const _DesktopKeyboardOnlyHint()
              : isTouchpad
              ? MouseTouchpad(
                  config: wheel,
                  inputEpoch: controller.inputEpoch,
                  onMove: (delta) =>
                      controller.sendTouchpadMove(delta.dx, delta.dy),
                  onScroll: controller.sendTouchpadScroll,
                  onPrimaryTap: () =>
                      _sendMouseClick(context, secondary: false),
                  onSecondaryTap: () =>
                      _sendMouseClick(context, secondary: true),
                )
              : JogWheel(
                  config: wheel,
                  inputEpoch: controller.inputEpoch,
                  onStep: controller.sendWheelStep,
                  onCenterPress: controller.pressWheelCenter,
                  onCenterRelease: controller.releaseWheelCenter,
                ),
        ),
        if (editing)
          Material(
            color: Colors.transparent,
            child: InkWell(
              key: const ValueKey('edit-navigation-control'),
              borderRadius: BorderRadius.circular(isTouchpad ? 28 : 999),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const WheelEditorScreen(),
                ),
              ),
              child: const Align(
                alignment: Alignment.topLeft,
                child: CircleAvatar(
                  radius: 16,
                  child: Icon(Icons.edit, size: 16),
                ),
              ),
            ),
          ),
      ],
    );
    if (isTouchpad) return panel;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360, maxHeight: 360),
        child: panel,
      ),
    );
  }

  void _sendMouseClick(BuildContext context, {required bool secondary}) {
    if (controller.hid is IosCompanionHidService) return;
    if (controller.hid.connectionStatus.value !=
        HidConnectionStatus.connected) {
      showBluetoothConnectionSheet(
        context,
        controller.hid,
        beforeConnect: controller.prepareForBluetoothHostSelection,
      );
      return;
    }
    controller.sendMouseClick(secondary: secondary);
  }
}

class _DesktopKeyboardOnlyHint extends StatelessWidget {
  const _DesktopKeyboardOnlyHint();

  @override
  Widget build(BuildContext context) => Center(
    child: Card(
      key: const ValueKey('desktop-keyboard-only-hint'),
      child: const Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.desktop_windows_outlined, size: 28),
            SizedBox(height: 10),
            Text(
              'Mouse controls are unavailable on iPad. Connect to LumiaKey Desktop to use keyboard shortcuts.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    ),
  );
}

enum _ControlMenuAction {
  profiles,
  bluetooth,
  desktopConnection,
  importExport,
  toggleEditing,
  settings,
}

class _CompactControlMenu extends StatelessWidget {
  const _CompactControlMenu({
    required this.controller,
    required this.editing,
    required this.onToggleEditing,
  });

  final AppController controller;
  final bool editing;
  final VoidCallback onToggleEditing;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<HidConnectionStatus>(
      valueListenable: controller.hid.connectionStatus,
      builder: (context, status, _) => ValueListenableBuilder<bool?>(
        valueListenable: controller.powerBrightnessService.isPluggedIn,
        builder: (context, pluggedIn, _) {
          final desktopKeyboardOnly =
              controller.hid is IosCompanionHidService ||
              defaultTargetPlatform == TargetPlatform.iOS;
          final display = _statusDisplay(
            controller.controlSurfaceStatus,
            status,
          );
          return SizedBox(
            width: 124,
            height: 40,
            child: PopupMenuButton<_ControlMenuAction>(
              key: const ValueKey('control-menu'),
              tooltip: display.tooltip,
              position: PopupMenuPosition.under,
              padding: EdgeInsets.zero,
              onSelected: (action) => _handleAction(context, action),
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: _ControlMenuAction.profiles,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.dashboard_customize_outlined),
                    title: Text('Profiles · ${controller.activeProfile.name}'),
                  ),
                ),
                if (desktopKeyboardOnly)
                  const PopupMenuItem(
                    key: ValueKey('menu-desktop-connection'),
                    value: _ControlMenuAction.desktopConnection,
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.desktop_windows_outlined),
                      title: Text('Desktop connection'),
                    ),
                  )
                else ...[
                  PopupMenuItem(
                    key: const ValueKey('menu-bluetooth-connection'),
                    value: _ControlMenuAction.bluetooth,
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(_connectionIcon(status)),
                      title: Text('Bluetooth · ${_connectionLabel(status)}'),
                    ),
                  ),
                  const PopupMenuItem(
                    key: ValueKey('menu-desktop-connection'),
                    value: _ControlMenuAction.desktopConnection,
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.desktop_windows_outlined),
                      title: Text('LumiaKey Desktop'),
                    ),
                  ),
                ],
                PopupMenuItem(
                  value: _ControlMenuAction.toggleEditing,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(editing ? Icons.check : Icons.edit_outlined),
                    title: Text(editing ? 'Done editing' : 'Edit buttons'),
                  ),
                ),
                const PopupMenuItem(
                  value: _ControlMenuAction.importExport,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.import_export),
                    title: Text('Import / export JSON'),
                  ),
                ),
                const PopupMenuItem(
                  value: _ControlMenuAction.settings,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.settings_outlined),
                    title: Text('Settings'),
                  ),
                ),
              ],
              child: Tooltip(
                message: display.tooltip,
                child: Container(
                  key: ValueKey('status-mode-${display.key}'),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xD9101720),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: display.color.withValues(alpha: 0.72),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        editing ? Icons.check : display.icon,
                        size: 17,
                        color: display.color,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          editing ? 'Editing' : display.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Tooltip(
                        message: switch (pluggedIn) {
                          true => 'External power connected',
                          false => 'Running on battery',
                          null => 'Power status unavailable',
                        },
                        child: Icon(
                          pluggedIn == true
                              ? Icons.bolt
                              : pluggedIn == false
                              ? Icons.battery_full
                              : Icons.battery_unknown,
                          key: ValueKey('power-indicator-$pluggedIn'),
                          size: 12,
                          color: pluggedIn == true
                              ? const Color(0xFF7BD4E4)
                              : Colors.white54,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  _CompactStatusDisplay _statusDisplay(
    ControlSurfaceStatus surface,
    HidConnectionStatus hidStatus,
  ) {
    if (surface.desktopSynced &&
        surface.foregroundStatus == ForegroundWorkspaceStatus.ready) {
      final name = surface.foregroundApplicationName ?? 'App';
      return _CompactStatusDisplay(
        key: 'app',
        label: name,
        tooltip: 'Foreground app · $name',
        icon: Icons.center_focus_strong,
        color: Colors.lightGreenAccent,
      );
    }
    if (surface.desktopDiscovered) {
      return _CompactStatusDisplay(
        key: 'desktop',
        label: 'Desktop',
        tooltip: surface.desktopSynced
            ? 'LumiaKey Desktop connected'
            : 'LumiaKey Desktop syncing',
        icon: Icons.desktop_windows_outlined,
        color: surface.desktopSynced
            ? Colors.lightGreenAccent
            : Colors.amberAccent,
      );
    }
    if (controller.hid is IosCompanionHidService &&
        !surface.desktopDiscovered &&
        !surface.desktopSynced) {
      return const _CompactStatusDisplay(
        key: 'desktop-offline',
        label: 'Desktop',
        tooltip: 'LumiaKey Desktop · Not connected',
        icon: Icons.desktop_windows_outlined,
        color: Colors.amberAccent,
      );
    }
    return _CompactStatusDisplay(
      key: 'hid',
      label: 'HID',
      tooltip: 'Bluetooth HID · ${_connectionLabel(hidStatus)}',
      icon: _connectionIcon(hidStatus),
      color: _connectionColor(hidStatus),
    );
  }

  void _handleAction(BuildContext context, _ControlMenuAction action) {
    switch (action) {
      case _ControlMenuAction.profiles:
        _showProfileSelector(context, controller);
      case _ControlMenuAction.bluetooth:
        showBluetoothConnectionSheet(
          context,
          controller.hid,
          beforeConnect: controller.prepareForBluetoothHostSelection,
        );
      case _ControlMenuAction.desktopConnection:
        showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          builder: (context) => AnimatedPadding(
            duration: const Duration(milliseconds: 180),
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: SafeArea(
              child: SingleChildScrollView(
                child: DesktopConnectionPanel(companion: controller.companion),
              ),
            ),
          ),
        );
      case _ControlMenuAction.toggleEditing:
        onToggleEditing();
      case _ControlMenuAction.importExport:
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const ShortcutCommunityScreen(),
          ),
        );
      case _ControlMenuAction.settings:
        Navigator.of(
          context,
        ).push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen()));
    }
  }

  static String _connectionLabel(HidConnectionStatus status) =>
      switch (status) {
        HidConnectionStatus.connected => 'Connected',
        HidConnectionStatus.connecting => 'Connecting',
        HidConnectionStatus.registering => 'Registering',
        HidConnectionStatus.disconnected => 'Disconnected',
        HidConnectionStatus.permissionRequired => 'Permission required',
        HidConnectionStatus.bluetoothOff => 'Off',
        HidConnectionStatus.unavailable => 'Unavailable',
      };

  static IconData _connectionIcon(HidConnectionStatus status) =>
      switch (status) {
        HidConnectionStatus.connected => Icons.bluetooth_connected,
        HidConnectionStatus.connecting => Icons.bluetooth_searching,
        HidConnectionStatus.registering => Icons.app_registration,
        HidConnectionStatus.disconnected => Icons.bluetooth_disabled,
        HidConnectionStatus.permissionRequired => Icons.security,
        HidConnectionStatus.bluetoothOff => Icons.bluetooth_disabled,
        HidConnectionStatus.unavailable => Icons.error_outline,
      };

  static Color _connectionColor(HidConnectionStatus status) => switch (status) {
    HidConnectionStatus.connected => Colors.greenAccent,
    HidConnectionStatus.connecting ||
    HidConnectionStatus.registering ||
    HidConnectionStatus.permissionRequired => Colors.amberAccent,
    HidConnectionStatus.disconnected ||
    HidConnectionStatus.bluetoothOff ||
    HidConnectionStatus.unavailable => Colors.redAccent,
  };
}

class _CompactStatusDisplay {
  const _CompactStatusDisplay({
    required this.key,
    required this.label,
    required this.tooltip,
    required this.icon,
    required this.color,
  });

  final String key;
  final String label;
  final String tooltip;
  final IconData icon;
  final Color color;
}

Future<void> _showProfileSelector(
  BuildContext context,
  AppController controller,
) async {
  final profilesById = {
    for (final profile in controller.config.profiles) profile.id: profile,
  };
  final profiles = controller.config.profileOrder
      .map((id) => profilesById[id])
      .whereType<ProfileConfig>()
      .toList();
  final selected = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 8, 8),
            child: Row(
              children: [
                Text(
                  'Profiles',
                  style: Theme.of(sheetContext).textTheme.titleLarge,
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const ProfileManagementScreen(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.tune),
                  label: const Text('Manage'),
                ),
              ],
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: profiles.map((profile) {
                final selected =
                    profile.id == controller.config.activeProfileId;
                return ListTile(
                  leading: Icon(
                    BuiltinIconCatalog.find(profile.profileIcon.value)?.icon ??
                        Icons.dashboard,
                  ),
                  title: Text(profile.name),
                  subtitle: profile.targetApplication == null
                      ? null
                      : Text(profile.targetApplication!),
                  trailing: selected ? const Icon(Icons.check_circle) : null,
                  onTap: () => Navigator.pop(sheetContext, profile.id),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    ),
  );
  if (selected != null && context.mounted) {
    await controller.switchProfile(selected);
  }
}
