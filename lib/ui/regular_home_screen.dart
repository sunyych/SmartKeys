import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:lumiakeys_protocol/codex_activity.dart';
import 'package:lumiakeys_protocol/lumiakeys_protocol.dart';

import '../app.dart';
import '../icons/source_profile_icon.dart';
import '../controllers/app_controller.dart';
import '../models/config.dart';
import '../services/companion_service.dart';
import '../icons/app_icon_catalog.dart';
import '../mobile_appearance.dart';
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
  static const _libraryPrefix = 'library-profile:';
  static const _pageSize = 12;

  final _dictation = GlobalKey<LocalDictationEntryButtonState>();
  String _selection = _launchpad;
  Set<String>? _previousSidebarSelections;
  String? _sessionKey;
  String? _pendingApplication;
  String? _error;
  int _generation = 0;
  int _page = 0;
  bool _wasReady = false;
  String? _confirmedApplication;
  String? _confirmedSession;
  bool _selectedWithoutActivation = false;
  late final Timer _clock;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _clock.cancel();
    super.dispose();
  }

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
    _confirmedApplication = null;
    _confirmedSession = null;
    _selectedWithoutActivation = false;
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

  bool _applicationReady(AppController controller) {
    if (_selection == _launchpad || _selection == _general) return true;
    final libraryProfile = _selectedLibraryProfile(controller);
    if (libraryProfile != null) {
      return libraryProfile.applicationId == null ||
          controller.desktopManifest
                  ?.applicationById(libraryProfile.applicationId!)
                  ?.foreground ==
              true;
    }
    return (_selectedWithoutActivation ||
            _confirmedApplication == _selection) &&
        _confirmedSession == _session(controller) &&
        controller.desktopManifest?.applicationById(_selection)?.foreground ==
            true;
  }

  RemoteProfile? _selectedLibraryProfile(AppController controller) {
    if (!_selection.startsWith(_libraryPrefix)) return null;
    final id = _selection.substring(_libraryPrefix.length);
    return controller.desktopManifest?.profiles
        .where((profile) => profile.id == id && profile.isLibraryProfile)
        .firstOrNull;
  }

  Future<bool> _confirmActivation(
    AppController controller,
    RemoteApplication app,
    int previousSequence,
    String? session,
    int generation,
  ) async {
    final completion = Completer<bool>();
    void check() {
      if (completion.isCompleted) return;
      if (!mounted ||
          !_ready(controller) ||
          generation != _generation ||
          session != _session(controller)) {
        completion.complete(false);
        return;
      }
      final manifest = controller.desktopManifest;
      if (manifest != null &&
          manifest.applicationActivationSequence > previousSequence &&
          manifest.activatedApplicationId == app.id &&
          manifest.applicationById(app.id)?.foreground == true) {
        completion.complete(true);
      }
    }

    controller.addListener(check);
    final timeout = Timer(const Duration(seconds: 5), () {
      if (!completion.isCompleted) completion.complete(false);
    });
    try {
      check();
      if (!completion.isCompleted) {
        unawaited(
          controller.companion.refreshManifest().catchError((Object _) {}),
        );
      }
      return await completion.future;
    } finally {
      timeout.cancel();
      controller.removeListener(check);
    }
  }

  Future<void> _select(
    AppController controller,
    String selection, {
    RemoteApplication? application,
    bool fromAppBar = false,
  }) async {
    final generation = ++_generation;
    final session = _session(controller);
    final previousSequence =
        controller.desktopManifest?.applicationActivationSequence ?? 0;
    setState(() {
      _pendingApplication = application?.id;
      _confirmedApplication = null;
      _confirmedSession = null;
      _selectedWithoutActivation = false;
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
      var skipActivation = false;
      if (application != null) {
        if (!_ready(controller) ||
            !controller.syncedApplications.any(
              (app) => app.id == application.id,
            )) {
          return;
        }
        if (fromAppBar) {
          final manifest = controller.desktopManifest!;
          if (!manifest.effectiveSidebarItems.any(
            (item) =>
                item.kind == RemoteSidebarKind.application &&
                (item.id == application.id ||
                    (item.id == 'codex' && application.id == 'chatgpt')),
          )) {
            return;
          }
          skipActivation =
              !manifest.settings.autoLaunchApps ||
              manifest.sidebarShortcutOnlyApplicationIds.contains(
                application.id,
              );
        }
        if (!skipActivation) {
          await controller.launchRemoteApplication(application);
          if (!application.launchOnly &&
              !await _confirmActivation(
                controller,
                application,
                previousSequence,
                session,
                generation,
              )) {
            if (mounted &&
                generation == _generation &&
                session == _session(controller)) {
              throw StateError(
                context.mobileText(
                  'Desktop has not confirmed ${application.name} is active. Select it again to retry.',
                  '电脑尚未确认 ${application.name} 已切换到前台。请重新选择该应用。',
                ),
              );
            }
            return;
          }
        }
      }
      if (!mounted ||
          generation != _generation ||
          session != _session(controller)) {
        return;
      }
      if (application != null && !_ready(controller)) return;
      setState(() {
        _selection = application?.launchOnly == true ? _launchpad : selection;
        _selectedWithoutActivation = skipActivation;
        _confirmedApplication =
            skipActivation || application?.launchOnly == true
            ? null
            : application?.id;
        _confirmedSession = application == null || application.launchOnly
            ? null
            : session;
        _page = 0;
      });
    } catch (error) {
      if (mounted &&
          generation == _generation &&
          session == _session(controller)) {
        setState(
          () => _error = context.mobileText(
            'Could not open this application. $error',
            '无法打开此应用。$error',
          ),
        );
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
    final systemControl =
        button.id.startsWith('keyboard.') &&
        button.targetType == RemoteTargetType.system;
    if (!_ready(controller) ||
        _pendingApplication != null ||
        (!systemControl && !_applicationReady(controller))) {
      return;
    }
    if (isChatGptLocalDictationShortcut(button)) {
      await _dictation.currentState?.startQuickDictation();
      return;
    }
    if (_voiceShortcutNeedsSetup(button)) {
      await _showVoiceModeSetup();
      return;
    }
    if (isUnassignedChatGptShortcut(button)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.mobileText(
              'Assign and enable this shortcut in Desktop → Shortcut Layout → ChatGPT.',
              '请在桌面端的快捷键布局 → ChatGPT 中填写并启用此快捷键。',
            ),
          ),
        ),
      );
      return;
    }
    if (!button.enabled) return;
    final session = _session(controller);
    final generation = _generation;
    final approval = chatGptApprovalShortcutIds.contains(button.id);
    if (approval && !await _confirmPendingApproval(button)) return;
    if (!mounted) return;
    if ((button.targetType == RemoteTargetType.voiceInput ||
            button.id == chatGptNativeVoiceShortcutId) &&
        !await ensureDictationEntryExplained(context)) {
      return;
    }
    if (!mounted ||
        !_ready(controller) ||
        generation != _generation ||
        session != _session(controller) ||
        (!systemControl && !_applicationReady(controller)) ||
        controller.desktopManifest?.buttonById(button.id)?.enabled != true) {
      return;
    }
    try {
      await controller.executeRemoteButton(button, confirmedApproval: approval);
    } catch (error) {
      if (mounted &&
          generation == _generation &&
          session == _session(controller)) {
        setState(
          () => _error = context.mobileText(
            'Could not run this shortcut. $error',
            '无法执行此快捷键。$error',
          ),
        );
      }
    }
  }

  Future<void> _showVoiceModeSetup() => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(context.mobileText('Set up Voice Mode', '设置语音模式')),
      content: Text(
        context.mobileText(
          'If available, set a Voice chat hotkey in ChatGPT → Settings → Voice. Bind and enable the same shortcut in LumiaKey Desktop → Shortcut Layout → ChatGPT. If Voice Mode is missing there, update LumiaKey Desktop.',
          '如果 ChatGPT 支持语音聊天快捷键，请在“设置 → 语音”中设置，再在 LumiaKey 桌面版的“快捷键布局 → ChatGPT”中绑定并启用同一个快捷键。若找不到“语音模式”，请更新 LumiaKey 桌面版。',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.mobileText('Close', '关闭')),
        ),
      ],
    ),
  );

  Future<bool> _confirmPendingApproval(RemoteShortcutButton button) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(
            context.mobileText(
              'Does ChatGPT show an approval request?',
              '桌面上的 ChatGPT 是否显示待审批请求？',
            ),
          ),
          content: Text(
            context.mobileText(
              'Look at the request on your computer before using this shortcut.',
              '请先核对电脑上的审批请求，再执行此快捷键。',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.mobileText('Go Back', '返回')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(
                button.id == chatGptApproveShortcutId
                    ? context.mobileText('Approve Request', '确认请求')
                    : context.mobileText('Decline Request', '拒绝请求'),
              ),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _showConnection(AppController controller) =>
      showDesktopConnectionSheet(context, controller.companion);

  void _showLauncherSetup(AppController controller) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                context.mobileText(
                  'Configure Launchpad in Desktop',
                  '在桌面端配置启动台',
                ),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              const MobileText(
                'Open LumiaKey Desktop → Launchpad on your computer. Assign applications to the twelve slots; this phone displays that configuration automatically.',
                '在电脑上打开 LumiaKey Desktop 的启动台。为 12 个位置分配应用后，移动端会自动显示。',
              ),
              const SizedBox(height: 16),
              DesktopConnectionPanel(companion: controller.companion),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = SmartKeysScope.of(context);
    final viewport = MediaQuery.sizeOf(context);
    final landscape = viewport.width > viewport.height;
    controller.registerLayoutOrientation(landscape);
    _trackSession(controller, landscape);
    if (!landscape) {
      return Scaffold(
        key: const ValueKey('regular-portrait-gate'),
        body: SafeArea(
          child: _EmptySurface(
            icon: Icons.screen_rotation,
            title: context.mobileText('Rotate to landscape', '请切换到横屏'),
            message: context.mobileText(
              'Turn your device sideways to use LumiaKey.',
              '横置设备即可使用 LumiaKey。',
            ),
          ),
        ),
      );
    }
    final ready = _ready(controller);
    final companion = controller.companion;
    final codexActivity = ready && companion is CompanionCodexActivityConnection
        ? (companion as CompanionCodexActivityConnection).codexActivity
        : null;
    // A pointer route can outlive its rendered surface until the next frame.
    // Do not let an old key/app tap acquire authority from a newly ready host.
    final renderedSession = _session(controller);
    final renderedInputEpoch = controller.inputEpoch;
    bool acceptsRenderedInput() =>
        mounted &&
        renderedSession == _session(controller) &&
        renderedInputEpoch == controller.inputEpoch;
    final manifest = controller.desktopManifest;
    final applications = _applications(controller);
    final sidebarApps = {
      for (final app in applications.where((app) => !app.launchOnly))
        app.id: app,
    };
    final sidebarProfiles = {
      for (final profile in manifest?.profiles ?? const <RemoteProfile>[])
        if (profile.isLibraryProfile &&
            profile.platform == controller.companion.activeHost.value?.platform)
          profile.id: profile,
    };
    final sidebarKeys = <String>{};
    final sidebarItems =
        (manifest?.effectiveSidebarItems ?? const <RemoteSidebarItem>[])
            .map(
              (item) =>
                  item.kind == RemoteSidebarKind.application &&
                      item.id == 'codex' &&
                      sidebarApps.containsKey('chatgpt')
                  ? const RemoteSidebarItem.application('chatgpt')
                  : item,
            )
            .where(
              (item) =>
                  (item.kind == RemoteSidebarKind.application
                      ? sidebarApps.containsKey(item.id)
                      : sidebarProfiles.containsKey(item.id)) &&
                  sidebarKeys.add(item.key),
            )
            .toList();
    final visibleSelections = {
      for (final item in sidebarItems)
        item.kind == RemoteSidebarKind.application
            ? item.id
            : '$_libraryPrefix${item.id}',
    };
    final removedSelections =
        _previousSidebarSelections?.difference(visibleSelections) ??
        const <String>{};
    _previousSidebarSelections = visibleSelections;
    if (removedSelections.contains(_selection) ||
        removedSelections.contains(_pendingApplication)) {
      _selection = _launchpad;
      _page = 0;
      _pendingApplication = null;
      _confirmedApplication = null;
      _confirmedSession = null;
      _selectedWithoutActivation = false;
      ++_generation;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(_dictation.currentState?.stopQuickDictation());
          unawaited(controller.prepareForContextChange());
        }
      });
    }
    final application = applications.cast<RemoteApplication?>().firstWhere(
      (app) => app?.id == _selection,
      orElse: () => null,
    );
    final launcherSlots = List<RemoteApplication?>.generate(launcherSlotCount, (
      index,
    ) {
      if (manifest == null ||
          !manifest.settings.enableAppsSync ||
          index >= manifest.launcherApplicationIds.length) {
        return null;
      }
      final id = manifest.launcherApplicationIds[index];
      return id == null ? null : manifest.applicationById(id);
    });
    final libraryProfile = _selectedLibraryProfile(controller);
    final layout = libraryProfile != null
        ? manifest?.layoutById(libraryProfile.layoutId)
        : _selection == _general
        ? manifest?.layoutById('keyboard') ??
              manifest?.layouts.cast<RemoteShortcutLayout?>().firstWhere(
                (layout) => layout?.kind == RemoteLayoutKind.keyboard,
                orElse: () => null,
              )
        : application == null
        ? null
        : controller.layoutForApplication(
            application,
            chatGptPageSize: _pageSize,
          );
    final launcher = _selection == _launchpad;
    final buttons = _buttonsForGrid(layout);
    final count = launcher ? launcherSlotCount : buttons.length;
    final pageCount = math.max(1, (count / _pageSize).ceil());
    if (_page >= pageCount) _page = 0;
    final launchpadTitle = context.mobileText('Launchpad', '启动台');
    final generalTitle = context.mobileText('General', '常规');
    final title = launcher
        ? launchpadTitle
        : _selection == _general
        ? generalTitle
        : libraryProfile?.name ??
              application?.name ??
              context.mobileText('Application', '应用');
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
                    border: Border(
                      right: BorderSide(
                        color: theme.brightness == Brightness.dark
                            ? const Color(0xFF243242)
                            : theme.colorScheme.outlineVariant,
                      ),
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
                                key: const ValueKey('regular-brand-icon'),
                                width: 32,
                                height: 32,
                                cacheWidth: 96,
                                fit: BoxFit.contain,
                                semanticLabel: context.mobileText(
                                  'LumiaKey app icon',
                                  'LumiaKey 应用图标',
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'LumiaKey',
                              key: const ValueKey('regular-brand-label'),
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
                            _NavigationItem(
                              id: _launchpad,
                              label: launchpadTitle,
                              icon: const Icon(Icons.apps_rounded),
                              selected: launcher,
                              onTap: () => _select(controller, _launchpad),
                            ),
                            _NavigationItem(
                              id: _general,
                              label: generalTitle,
                              icon: const Icon(Icons.tune_rounded),
                              selected: _selection == _general,
                              onTap: () => _select(controller, _general),
                            ),
                            const Divider(indent: 10, endIndent: 10),
                            for (final item in sidebarItems)
                              if (item.kind == RemoteSidebarKind.application)
                                _NavigationItem(
                                  id: item.id,
                                  label: sidebarApps[item.id]!.name,
                                  icon: _ApplicationIcon(
                                    app: sidebarApps[item.id]!,
                                    size: 24,
                                  ),
                                  selected: item.id == _selection,
                                  busy: item.id == _pendingApplication,
                                  activity:
                                      item.id == 'chatgpt' || item.id == 'codex'
                                      ? codexActivity
                                      : null,
                                  onTap: ready
                                      ? () {
                                          if (acceptsRenderedInput()) {
                                            _select(
                                              controller,
                                              item.id,
                                              application: sidebarApps[item.id],
                                              fromAppBar: true,
                                            );
                                          }
                                        }
                                      : null,
                                )
                              else
                                _NavigationItem(
                                  id: 'library-profile-${item.id}',
                                  label: sidebarProfiles[item.id]!.name,
                                  icon: AppArtwork(
                                    appId:
                                        sidebarProfiles[item.id]!
                                            .sourceIconId ??
                                        sidebarProfiles[item.id]!.sourceAppId ??
                                        '',
                                    pngBytes: sourceProfileIcon(
                                      sidebarProfiles[item.id]!,
                                    ),
                                    size: 24,
                                  ),
                                  selected:
                                      _selection == '$_libraryPrefix${item.id}',
                                  onTap: ready
                                      ? () => _select(
                                          controller,
                                          '$_libraryPrefix${item.id}',
                                        )
                                      : null,
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
                        child: _header(
                          controller,
                          title: title,
                          ready: ready,
                          acceptsRenderedInput: acceptsRenderedInput,
                        ),
                      ),
                      Expanded(
                        child: Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  12,
                                  0,
                                  10,
                                  12,
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    if (pageCount > 1)
                                      SizedBox(
                                        height: 36,
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.end,
                                          children: [
                                            IconButton(
                                              key: const ValueKey(
                                                'regular-previous-page',
                                              ),
                                              tooltip: context.mobileText(
                                                'Previous page',
                                                '上一页',
                                              ),
                                              visualDensity:
                                                  VisualDensity.compact,
                                              onPressed: _page > 0
                                                  ? () =>
                                                        setState(() => _page--)
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
                                                'regular-next-page',
                                              ),
                                              tooltip: context.mobileText(
                                                'Next page',
                                                '下一页',
                                              ),
                                              visualDensity:
                                                  VisualDensity.compact,
                                              onPressed: _page + 1 < pageCount
                                                  ? () =>
                                                        setState(() => _page++)
                                                  : null,
                                              icon: const Icon(
                                                Icons.chevron_right,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    if (_error != null)
                                      _StatusBanner(
                                        message: _error!,
                                        error: true,
                                      ),
                                    if (launcher &&
                                        ready &&
                                        manifest?.settings.enableAppsSync !=
                                            true)
                                      _StatusBanner(
                                        message: context.mobileText(
                                          'Enable Apps Sync in LumiaKey Desktop to display your saved launcher.',
                                          '在 LumiaKey Desktop 中启用应用同步，即可显示已保存的启动台。',
                                        ),
                                      ),
                                    if (launcher &&
                                        ready &&
                                        launcherSlots.every(
                                          (app) => app == null,
                                        ))
                                      TextButton.icon(
                                        key: const ValueKey(
                                          'regular-configure-launchpad',
                                        ),
                                        onPressed: () =>
                                            _showLauncherSetup(controller),
                                        icon: const Icon(
                                          Icons.desktop_windows,
                                          size: 17,
                                        ),
                                        label: const MobileText(
                                          'Set up the twelve slots in Desktop',
                                          '在桌面端设置 12 个应用位置',
                                        ),
                                      ),
                                    if (libraryProfile != null &&
                                        libraryProfile.applicationId == null)
                                      _StatusBanner(
                                        message: context.mobileText(
                                          'Manual keyboard profile: focus the intended application on your computer before sending shortcuts. Selecting this profile does not launch or verify an app.',
                                          '这是手动键盘配置。发送快捷键前，请先将电脑上的目标应用切换到前台。',
                                        ),
                                      ),
                                    if (!launcher &&
                                        libraryProfile == null &&
                                        _selection != _general &&
                                        !_applicationReady(controller) &&
                                        _pendingApplication == null)
                                      _StatusBanner(
                                        message: _selectedWithoutActivation
                                            ? context.mobileText(
                                                'Bring the application to the foreground on your computer to use its shortcuts.',
                                                '请在电脑上将应用切换到前台，然后使用它的快捷键。',
                                              )
                                            : context.mobileText(
                                                'Select the application in App Bar to activate it before sending shortcuts.',
                                                '发送快捷键前，请在应用栏选择目标应用。',
                                              ),
                                      ),
                                    Expanded(
                                      child: !ready
                                          ? _ConnectionPrompt(
                                              onConnect: () =>
                                                  _showConnection(controller),
                                            )
                                          : !launcher && layout == null
                                          ? _EmptySurface(
                                              icon: Icons.keyboard_outlined,
                                              title: context.mobileText(
                                                'No shortcuts configured',
                                                '尚未配置快捷键',
                                              ),
                                              message: context.mobileText(
                                                'Add this application’s shortcut layout in LumiaKey Desktop.',
                                                '请在 LumiaKey Desktop 中添加此应用的快捷键布局。',
                                              ),
                                            )
                                          : _TwelveKeyGrid(
                                              page: _page,
                                              launcher: launcher,
                                              applications: launcherSlots,
                                              buttons: buttons,
                                              enabled:
                                                  _pendingApplication == null &&
                                                  (launcher ||
                                                      _applicationReady(
                                                        controller,
                                                      )),
                                              onConfigure: () {
                                                if (acceptsRenderedInput()) {
                                                  _showLauncherSetup(
                                                    controller,
                                                  );
                                                }
                                              },
                                              onApplication: (app) {
                                                if (acceptsRenderedInput()) {
                                                  _select(
                                                    controller,
                                                    app.id,
                                                    application: app,
                                                  );
                                                }
                                              },
                                              onButton: (button) {
                                                if (acceptsRenderedInput()) {
                                                  _execute(controller, button);
                                                }
                                              },
                                            ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  0,
                                  0,
                                  10,
                                  12,
                                ),
                                child: _DesktopTouchpad(
                                  controller: controller,
                                  enabled: ready,
                                  acceptsRenderedInput: acceptsRenderedInput,
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
            Positioned.fill(
              child: LocalDictationEntryButton(
                key: _dictation,
                hid: controller.hid,
                companion: controller.companion,
                forceDesktopOutput: true,
                entryEnabled:
                    ready &&
                    libraryProfile == null &&
                    _pendingApplication == null &&
                    _applicationReady(controller),
                topOffset: 9,
                rightInset: 52,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(
    AppController controller, {
    required String title,
    required bool ready,
    required bool Function() acceptsRenderedInput,
  }) {
    final theme = Theme.of(context), manifest = controller.desktopManifest;
    return SizedBox(
      height: 48,
      child: LayoutBuilder(
        builder: (context, bounds) => Row(
          key: const ValueKey('regular-header'),
          children: [
            SizedBox(
              width: (bounds.maxWidth * .20).clamp(92.0, 180.0),
              child: Text(
                title,
                key: const ValueKey('regular-workspace-title'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Expanded(
              child: Row(
                key: const ValueKey('regular-header-controls'),
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      ready
                          ? controller.companion.activeHost.value!.name
                          : context.mobileText(
                              'Desktop not connected',
                              '电脑未连接',
                            ),
                      key: const ValueKey('regular-host-name'),
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
                    key: const ValueKey('regular-clock'),
                    maxLines: 1,
                    style: theme.textTheme.labelLarge,
                  ),
                  for (final control in const [
                    (
                      'keyboard.playPause',
                      'Play / Pause',
                      '播放 / 暂停',
                      Icons.play_arrow,
                    ),
                    ('keyboard.mute', 'Mute', '静音', Icons.volume_off),
                  ])
                    IconButton(
                      key: ValueKey('regular-system-${control.$1}'),
                      tooltip: context.mobileText(control.$2, control.$3),
                      visualDensity: VisualDensity.compact,
                      onPressed:
                          ready &&
                              _pendingApplication == null &&
                              manifest?.buttonById(control.$1)?.enabled == true
                          ? () {
                              if (acceptsRenderedInput()) {
                                _execute(
                                  controller,
                                  manifest!.buttonById(control.$1)!,
                                );
                              }
                            }
                          : null,
                      icon: Icon(control.$4, size: 21),
                    ),
                ],
              ),
            ),
            Row(
              key: const ValueKey('regular-header-tools'),
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 40,
                  child: IconButton(
                    key: const ValueKey('regular-desktop-connection'),
                    tooltip: ready
                        ? context.mobileText('Desktop connected', '电脑已连接')
                        : context.mobileText('Connect Desktop', '连接电脑'),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _showConnection(controller),
                    color: ready ? theme.colorScheme.primary : null,
                    icon: Icon(
                      ready
                          ? Icons.desktop_windows
                          : Icons.desktop_access_disabled,
                    ),
                  ),
                ),
                SizedBox(
                  width: 40,
                  child: ComputerSwitcher(
                    controller: controller,
                    compact: true,
                    iconOnly: true,
                  ),
                ),
                const SizedBox(width: 44),
                SizedBox(
                  width: 40,
                  child: IconButton(
                    key: const ValueKey('regular-settings'),
                    tooltip: context.mobileText('Settings', '设置'),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const SettingsScreen(),
                      ),
                    ),
                    icon: const Icon(Icons.settings_outlined),
                  ),
                ),
              ],
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
    this.activity,
  });
  final String id;
  final String label;
  final Widget icon;
  final bool selected;
  final bool busy;
  final VoidCallback? onTap;
  final ValueListenable<CodexActivityStatus?>? activity;

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
              child: Stack(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: Column(
                      children: [
                        busy
                            ? const SizedBox.square(
                                dimension: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
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
                  if (activity case final current?)
                    Positioned(
                      right: 5,
                      top: 7,
                      child: ValueListenableBuilder<CodexActivityStatus?>(
                        valueListenable: current,
                        builder: (context, status, _) => status == null
                            ? const SizedBox.shrink()
                            : _CodexActivityDot(status: status),
                      ),
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

class _CodexActivityDot extends StatelessWidget {
  const _CodexActivityDot({required this.status});

  final CodexActivityStatus status;

  @override
  Widget build(BuildContext context) {
    final (color, english, chinese) = switch (status) {
      CodexActivityStatus.idle => (const Color(0xFFF5F7FA), 'Idle', '空闲'),
      CodexActivityStatus.thinking => (
        const Color(0xFF4C90FF),
        'Thinking',
        '处理中',
      ),
      CodexActivityStatus.complete => (
        const Color(0xFF38CD89),
        'Complete',
        '已完成',
      ),
      CodexActivityStatus.needsInput => (
        const Color(0xFFF1BE46),
        'Needs Input',
        '等待输入',
      ),
      CodexActivityStatus.error => (const Color(0xFFF26587), 'Error', '出错'),
    };
    final label = context.mobileText(
      'Codex activity: $english',
      'Codex 状态：$chinese',
    );
    return Semantics(
      label: label,
      child: Tooltip(
        message: label,
        excludeFromSemantics: true,
        child: DecoratedBox(
          key: const ValueKey('regular-chatgpt-activity-dot'),
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: status == CodexActivityStatus.idle
                ? Border.all(color: Theme.of(context).colorScheme.outline)
                : null,
          ),
          child: const SizedBox.square(dimension: 9),
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
    required this.onConfigure,
  });
  final int page;
  final bool launcher;
  final List<RemoteApplication?> applications;
  final List<RemoteShortcutButton?> buttons;
  final bool enabled;
  final ValueChanged<RemoteApplication> onApplication;
  final ValueChanged<RemoteShortcutButton> onButton;
  final VoidCallback onConfigure;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      const spacing = 8.0;
      final colors = Theme.of(context).colorScheme;
      final dark = colors.brightness == Brightness.dark;
      final vacantColor = dark
          ? const Color(0xFF10161F)
          : colors.surfaceContainerLow;
      final assignedColor = dark
          ? const Color(0xFF192433)
          : colors.surfaceContainerHighest;
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
          final dictation =
              button != null && isChatGptLocalDictationShortcut(button);
          final unassigned =
              button != null &&
              (isUnassignedChatGptShortcut(button) ||
                  _voiceShortcutNeedsSetup(button));
          final label =
              app?.name ??
              (launcher
                  ? context.mobileText('Slot ${index + 1}', '位置 ${index + 1}')
                  : dictation
                  ? context.mobileText('Dictation', '听写')
                  : button == null
                  ? ''
                  : button.id == chatGptNativeVoiceShortcutId &&
                        button.name == 'Voice Mode'
                  ? context.mobileText('Voice Mode', '语音模式')
                  : _shortcutLabel(button));
          final available =
              enabled &&
              (app?.detected == true ||
                  !launcher &&
                      (dictation || button?.enabled == true && !unassigned));
          return Material(
            key: ValueKey('regular-cell-$index'),
            color: app == null && button == null ? vacantColor : assignedColor,
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
                  : enabled && unassigned
                  ? () => onButton(button)
                  : launcher && (app == null || !app.detected)
                  ? onConfigure
                  : null,
              child: label.isEmpty
                  ? const SizedBox.expand()
                  : Tooltip(
                      message: launcher && (app == null || !app.detected)
                          ? context.mobileText(
                              'Configure this slot in LumiaKey Desktop',
                              '在 LumiaKey Desktop 中配置此位置',
                            )
                          : dictation
                          ? context.mobileText(
                              'Start LumiaKey local dictation',
                              '开始 LumiaKey 本地听写',
                            )
                          : unassigned
                          ? context.mobileText(
                              'Assign this shortcut in LumiaKey Desktop',
                              '在 LumiaKey 桌面端配置此快捷键',
                            )
                          : button?.description.isNotEmpty == true
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
                                            button == null
                                                ? Icons.add
                                                : _shortcutIcon(button.icon),
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

List<RemoteShortcutButton?> _buttonsForGrid(RemoteShortcutLayout? layout) {
  final buttons = layout?.buttons ?? const <RemoteShortcutButton>[];
  if (layout?.id != 'chatgpt') return buttons;
  final byId = {for (final button in buttons) button.id: button};
  // Older synced boards may omit new actions. Leave their cells empty so the
  // two voice controls and the start of the secondary page keep their slots.
  return [
    for (final id in chatGptRegularPrimaryShortcutIds) byId[id],
    ...buttons.where(
      (button) => !chatGptRegularPrimaryShortcutIds.contains(button.id),
    ),
  ];
}

bool _voiceShortcutNeedsSetup(RemoteShortcutButton button) =>
    button.id == chatGptNativeVoiceShortcutId &&
    (!button.enabled ||
        button.targetType != RemoteTargetType.keyboardShortcut ||
        button.shortcut.isEmpty);

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
  'graphic_eq' => Icons.graphic_eq,
  'mic_external_on' => Icons.mic_external_on,
  'bolt' => Icons.bolt,
  'call_split' => Icons.call_split,
  'close' => Icons.close,
  'backspace' => Icons.backspace_outlined,
  'content_cut' => Icons.content_cut,
  'center_focus_strong' => Icons.center_focus_strong,
  'keyboard_return' => Icons.keyboard_return,
  'arrow_forward' => Icons.arrow_forward,
  _ => remoteIcon(id),
};

class _ApplicationIcon extends StatefulWidget {
  const _ApplicationIcon({required this.app, required this.size});
  final RemoteApplication app;
  final double size;

  @override
  State<_ApplicationIcon> createState() => _ApplicationIconState();
}

class _ApplicationIconState extends State<_ApplicationIcon> {
  String? _requestKey;
  Future<Uint8List?>? _icon;

  @override
  Widget build(BuildContext context) {
    final controller = SmartKeysScope.of(context);
    final key = controller.desktopApplicationIconRequestKey(widget.app.id);
    if (_requestKey != key) {
      _requestKey = key;
      _icon = key == null
          ? null
          : controller.loadDesktopApplicationIcon(widget.app.id);
    }
    return FutureBuilder<Uint8List?>(
      key: ValueKey(key ?? 'unavailable:${widget.app.id}'),
      future: _icon,
      builder: (_, snapshot) => AppArtwork(
        appId: widget.app.launchOnly && widget.app.icon.isNotEmpty
            ? widget.app.icon
            : widget.app.id,
        pngBytes: snapshot.data,
        size: widget.size,
        semanticLabel: '${widget.app.name} app icon',
      ),
    );
  }
}

class _DesktopTouchpad extends StatelessWidget {
  const _DesktopTouchpad({
    required this.controller,
    required this.enabled,
    required this.acceptsRenderedInput,
  });
  final AppController controller;
  final bool enabled;
  final bool Function() acceptsRenderedInput;

  bool get _canSend =>
      enabled &&
      acceptsRenderedInput() &&
      controller.isDesktopSynced &&
      controller.computerSwitchPendingId == null &&
      controller.selectedDesktopSupportsMouse;

  @override
  Widget build(BuildContext context) {
    if (!_canSend) {
      return _EmptySurface(
        key: const ValueKey('regular-touchpad-unavailable'),
        icon: Icons.touch_app_outlined,
        title: context.mobileText('Touchpad', '触控板'),
        message: enabled
            ? context.mobileText(
                'Update LumiaKey Desktop to enable mouse control.',
                '更新 LumiaKey Desktop 以启用鼠标控制。',
              )
            : context.mobileText(
                'Connect LumiaKey Desktop to use the touchpad.',
                '连接 LumiaKey Desktop 后即可使用触控板。',
              ),
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        MouseTouchpad(
          key: const ValueKey('regular-touchpad'),
          config: WheelConfig(
            controlType: WheelControlType.mousePad,
            modeLabel: context.mobileText('Touchpad', '触控板'),
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
        ),
        ListenableBuilder(
          listenable: controller,
          builder: (context, _) {
            final error = controller.desktopPointerError;
            if (error == null || error.isEmpty) {
              return const SizedBox.shrink();
            }
            final macPermissionError =
                error.contains('pointer_permission') ||
                error.toLowerCase().contains('accessibility') ||
                error.toLowerCase().contains('event posting');
            return Align(
              alignment: Alignment.bottomCenter,
              child: Card(
                key: const ValueKey('regular-desktop-pointer-error'),
                color: Theme.of(context).colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Text(
                    macPermissionError
                        ? context.mobileText(
                            'Desktop could not send mouse input. On Mac, check LumiaKey Desktop → General → Accessibility and event posting permission, then retry.',
                            '桌面端无法发送鼠标操作。请在 Mac 上打开 LumiaKey Desktop → 常规，检查辅助功能与事件发送权限后重试。',
                          )
                        : context.mobileText(
                            'Desktop could not send mouse input. Check the Desktop connection and retry.',
                            '桌面端无法发送鼠标操作。请检查桌面连接后重试。',
                          ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            );
          },
        ),
      ],
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
            context.mobileText(
              'Connect LumiaKey Desktop',
              '连接 LumiaKey Desktop',
            ),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          const MobileText(
            'Your computer provides applications and shortcuts.',
            '应用和快捷键由电脑提供。',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            key: const ValueKey('regular-connect-desktop'),
            onPressed: onConnect,
            icon: const Icon(Icons.link),
            label: const MobileText('Connect Desktop', '连接电脑'),
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
      color: Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF10161F)
          : Theme.of(context).colorScheme.surfaceContainerLow,
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
