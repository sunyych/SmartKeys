import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:local_dictation/local_dictation.dart';
import 'package:lumiakeys_protocol/lumiakeys_protocol.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'codex_activity.dart';
import 'companion_server.dart';
import 'desktop_actions.dart';
import 'desktop_connections.dart';
import 'desktop_profiles.dart';
import 'desktop_app_preferences.dart';
import 'desktop_controller.dart';
import 'app_library_page.dart';
import 'phone_sidebar_page.dart';
import 'desktop_application_artwork.dart';
import 'installed_app_picker.dart';
import 'app_icon_service.dart';
import 'desktop_dictation.dart';
import 'desktop_localizations.dart';
import 'desktop_preferences_page.dart';
import 'shortcut_transfer_service.dart';
import 'tray_shell.dart' show desktopBrandAsset;

export 'desktop_connections.dart' show desktopPairingCode, DesktopPairingQr;

class DesktopSettingsHome extends StatelessWidget {
  const DesktopSettingsHome({
    super.key,
    required this.controller,
    required this.server,
    required this.dictation,
    this.displayHost,
    this.preferences = const DesktopAppPreferences(),
    this.onPreferencesChanged,
    this.savingPreferences = false,
    this.preferencesSaveFailed = false,
  });

  final DesktopController controller;
  final CompanionServer server;
  final DesktopDictationService dictation;
  final String? displayHost;
  final DesktopAppPreferences preferences;
  final ValueChanged<DesktopAppPreferences>? onPreferencesChanged;
  final bool savingPreferences;
  final bool preferencesSaveFailed;

  static const navigationOrder = [0, 1, 2, 3, 4, 6, 7, 8, 5];

  static const sections = [
    (Icons.tune, 'General', '常规'),
    (Icons.bluetooth, 'Connections', '连接'),
    (Icons.dashboard_customize_outlined, 'Shortcut Layout', '快捷键布局'),
    (Icons.apps, 'Apps', '应用'),
    (Icons.layers_outlined, 'Profiles', '配置方案'),
    (Icons.info_outline, 'About', '关于'),
    (Icons.mic, 'Local Dictation', '本地听写'),
    (Icons.rocket_launch_outlined, 'Launcher', '启动台'),
    (Icons.settings_outlined, 'Settings', '设置'),
  ];

  @override
  Widget build(BuildContext context) {
    if (controller.loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final extendedNavigation = MediaQuery.sizeOf(context).width >= 920;
    final selected = navigationOrder.contains(controller.selectedSection)
        ? controller.selectedSection
        : 7;
    String sectionLabel(int section) =>
        desktopText(context, sections[section].$2, sections[section].$3);
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            scrollable: true,
            extended: extendedNavigation,
            selectedIndex: navigationOrder.indexOf(selected),
            onDestinationSelected: (index) =>
                controller.selectSection(navigationOrder[index]),
            leading: Padding(
              padding: const EdgeInsets.only(top: 16, bottom: 20),
              child: _BrandLogo(extended: extendedNavigation),
            ),
            destinations: navigationOrder
                .map(
                  (section) => NavigationRailDestination(
                    icon: Icon(sections[section].$1),
                    label: Text(sectionLabel(section)),
                  ),
                )
                .toList(growable: false),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: Column(
              children: [
                _TitleBar(title: sectionLabel(selected)),
                if (controller.error != null)
                  MaterialBanner(
                    content: Text(controller.error!),
                    actions: [
                      TextButton(
                        onPressed: controller.refreshApplications,
                        child: Text(desktopText(context, 'Retry', '重试')),
                      ),
                    ],
                  ),
                Expanded(child: _selectedPage()),
                _DesktopStatusBar(controller: controller, server: server),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _selectedPage() => switch (controller.selectedSection) {
    0 => _GeneralPage(
      controller: controller,
      server: server,
      displayHost: displayHost,
      dictation: dictation,
    ),
    1 => DesktopConnectionsPage(
      controller: controller,
      server: server,
      statusCard: _StatusCard(
        controller: controller,
        server: server,
        displayHost: displayHost,
      ),
    ),
    2 => _ShortcutLayoutsPage(controller: controller),
    3 => _AppsPage(controller: controller),
    4 => DesktopProfilesPage(controller: controller),
    5 => _AboutPage(inputBackend: controller.actions.inputBackend),
    6 => _LocalDictationPage(dictation: dictation),
    8 => DesktopPreferencesPage(
      preferences: preferences,
      rustInitiallySelected:
          controller.actions.inputBackend != DesktopInputBackend.standard,
      onChanged: onPreferencesChanged,
      saving: savingPreferences,
      saveFailed: preferencesSaveFailed,
    ),
    _ => _LauncherPage(
      controller: controller,
      codexActivity: server.codexActivity,
    ),
  };
}

class _DesktopStatusBar extends StatelessWidget {
  const _DesktopStatusBar({required this.controller, required this.server});

  final DesktopController controller;
  final CompanionServer server;

  @override
  Widget build(BuildContext context) {
    final foreground = controller.foregroundApplication;
    final colors = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('desktop-status-bar'),
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.outlineVariant)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _DesktopStatusItem(
              icon: server.running ? Icons.sync : Icons.sync_problem,
              label: server.running
                  ? desktopText(context, 'Desktop ready', '桌面端已就绪')
                  : desktopText(context, 'Desktop offline', '桌面端离线'),
              active: server.running,
            ),
          ),
          const VerticalDivider(indent: 8, endIndent: 8),
          Expanded(
            child: _DesktopStatusItem(
              icon: Icons.phone_android,
              label: controller.connectedPhone == null
                  ? desktopText(context, 'Waiting for phone', '正在等待手机连接')
                  : desktopText(context, 'Phone connected', '手机已连接'),
              active: controller.connectedPhone != null,
            ),
          ),
          const VerticalDivider(indent: 8, endIndent: 8),
          Expanded(
            child: _DesktopStatusItem(
              icon: Icons.center_focus_strong,
              label:
                  foreground?.name ??
                  desktopText(
                    context,
                    'No mapped foreground app',
                    '没有已映射的前台应用',
                  ),
              active: foreground != null,
            ),
          ),
        ],
      ),
    );
  }
}

class _DesktopStatusItem extends StatelessWidget {
  const _DesktopStatusItem({
    required this.icon,
    required this.label,
    required this.active,
  });

  final IconData icon;
  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(
        icon,
        size: 14,
        color: active ? Theme.of(context).colorScheme.primary : Colors.black45,
      ),
      const SizedBox(width: 6),
      Expanded(
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelSmall,
        ),
      ),
    ],
  );
}

class _TitleBar extends StatelessWidget {
  const _TitleBar({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => Container(
    height: 68,
    alignment: Alignment.centerLeft,
    padding: const EdgeInsets.symmetric(horizontal: 28),
    decoration: BoxDecoration(
      border: Border(
        bottom: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
    ),
    child: Text(title, style: Theme.of(context).textTheme.headlineSmall),
  );
}

class _BrandLogo extends StatelessWidget {
  const _BrandLogo({required this.extended});

  final bool extended;

  @override
  Widget build(BuildContext context) => SizedBox(
    key: const ValueKey('desktop-brand-logo'),
    width: extended ? 160 : 48,
    height: 42,
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Image.asset(
          desktopBrandAsset,
          key: const ValueKey('desktop-brand-logo-image'),
          width: 42,
          height: 42,
          filterQuality: FilterQuality.high,
          semanticLabel: desktopText(context, 'LumiaKey logo', 'LumiaKey 标志'),
        ),
        if (extended) ...[
          const SizedBox(width: 10),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                'LumiaKey',
                maxLines: 1,
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ],
    ),
  );
}

class _PageBody extends StatelessWidget {
  const _PageBody({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(28),
    children: [
      Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 980),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ),
    ],
  );
}

class _GeneralPage extends StatelessWidget {
  const _GeneralPage({
    required this.controller,
    required this.server,
    required this.displayHost,
    required this.dictation,
  });

  final DesktopController controller;
  final CompanionServer server;
  final String? displayHost;
  final DesktopDictationService dictation;

  @override
  Widget build(BuildContext context) {
    final settings = controller.manifest.settings;
    final profile = controller.manifest.currentProfile;
    return _PageBody(
      children: [
        _StatusCard(
          controller: controller,
          server: server,
          displayHost: displayHost,
        ),
        if (dictation.usesMacInputPermissions) ...[
          const SizedBox(height: 16),
          _MacPointerPermissionCard(service: dictation),
        ],
        const SizedBox(height: 24),
        Text(
          desktopText(context, 'Synchronization', '同步'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Card(
          child: Column(
            children: [
              SwitchListTile(
                title: Text(desktopText(context, 'Enable Apps Sync', '启用应用同步')),
                subtitle: Text(
                  desktopText(
                    context,
                    'Publish managed apps and their layouts to Android',
                    '将受管理的应用及其布局同步到 Android',
                  ),
                ),
                value: settings.enableAppsSync,
                onChanged: (value) => controller.updateSettings(
                  settings.copyWith(enableAppsSync: value),
                ),
              ),
              const Divider(height: 1),
              SwitchListTile(
                title: Text(desktopText(context, 'Auto Launch Apps', '自动启动应用')),
                subtitle: Text(
                  desktopText(
                    context,
                    'Allow phone app cards to launch configured desktop apps',
                    '允许手机上的应用卡片启动已配置的桌面应用',
                  ),
                ),
                value: settings.autoLaunchApps,
                onChanged: (value) => controller.updateSettings(
                  settings.copyWith(autoLaunchApps: value),
                ),
              ),
              const Divider(height: 1),
              SwitchListTile(
                title: Text(desktopText(context, 'Sync Icons', '同步图标')),
                subtitle: Text(
                  desktopText(
                    context,
                    'Include semantic icon identifiers in the phone manifest',
                    '在发送给手机的配置中包含图标标识',
                  ),
                ),
                value: settings.syncIcons,
                onChanged: (value) => controller.updateSettings(
                  settings.copyWith(syncIcons: value),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Text(
          desktopText(context, 'Current state', '当前状态'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.phone_android),
                title: Text(
                  desktopText(context, 'Current Connected Phone', '当前连接的手机'),
                ),
                subtitle: Text(
                  controller.connectedPhone ??
                      desktopText(context, 'No phone connected', '尚未连接手机'),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.layers_outlined),
                title: Text(
                  desktopText(context, 'Current Shortcut Profile', '当前快捷键配置'),
                ),
                subtitle: Text(
                  profile?.name ?? desktopText(context, 'Unavailable', '不可用'),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => controller.selectSection(4),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MacPointerPermissionCard extends StatelessWidget {
  const _MacPointerPermissionCard({required this.service});

  final DesktopDictationService service;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: service,
    builder: (context, _) => Card(
      key: const ValueKey('mac-pointer-permission-card'),
      child: ListTile(
        leading: Icon(
          service.inputPermissionsGranted
              ? Icons.check_circle_outline
              : Icons.accessibility_new,
        ),
        title: Text(
          service.inputPermissionsGranted
              ? desktopText(
                  context,
                  'Mouse and keyboard permissions are ready',
                  '鼠标和键盘权限已就绪',
                )
              : desktopText(
                  context,
                  'Allow Mac mouse and keyboard control',
                  '允许控制 Mac 的鼠标和键盘',
                ),
        ),
        subtitle: Text(
          service.testFlightInput
              ? desktopText(
                  context,
                  'Request permission to send keyboard and mouse events. Follow the macOS prompt, then refresh the permission status.',
                  '请求发送键盘和鼠标事件的权限。按 macOS 提示操作后，刷新权限状态。',
                )
              : desktopText(
                  context,
                  'In System Settings → Privacy & Security → Accessibility, allow LumiaKey Desktop. This permission also enables event posting. If it is already enabled but input still fails, remove the old LumiaKey Desktop entry and add the current app again.',
                  '打开「系统设置 → 隐私与安全性 → 辅助功能」，允许 LumiaKey Desktop 控制电脑。该权限也用于发送输入事件。如果已授权但仍无法输入，请移除旧的 LumiaKey Desktop 条目，再添加当前应用。',
                ),
        ),
        trailing: Wrap(
          children: [
            TextButton(
              onPressed: service.requestAccessibility,
              child: Text(desktopText(context, 'Request', '请求权限')),
            ),
            TextButton(
              onPressed: service.openAccessibilitySettings,
              child: Text(desktopText(context, 'Settings', '系统设置')),
            ),
            IconButton(
              tooltip: desktopText(
                context,
                'Refresh permission status',
                '刷新权限状态',
              ),
              onPressed: service.refreshAccessibility,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
      ),
    ),
  );
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.controller,
    required this.server,
    required this.displayHost,
  });

  final DesktopController controller;
  final CompanionServer server;
  final String? displayHost;

  @override
  Widget build(BuildContext context) {
    final platform = Platform.isMacOS
        ? 'macOS'
        : Platform.isWindows
        ? 'Windows'
        : 'Linux';
    return Card(
      color: server.running
          ? Theme.of(context).colorScheme.primaryContainer
                .withValues(alpha: 0.45)
          : Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Icon(
              server.running ? Icons.check_circle : Icons.error,
              color: server.running ? Colors.green : null,
              size: 34,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    server.running
                        ? desktopText(
                            context,
                            'LumiaKey Desktop is ready',
                            'LumiaKey Desktop 已就绪',
                          )
                        : desktopText(
                            context,
                            'Sync service unavailable',
                            '同步服务不可用',
                          ),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$platform · ${displayHost ?? Platform.localHostname} · ${desktopText(context, 'revision', '修订版本')} ${controller.manifest.revision}',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShortcutLayoutsPage extends StatefulWidget {
  const _ShortcutLayoutsPage({required this.controller});

  final DesktopController controller;

  @override
  State<_ShortcutLayoutsPage> createState() => _ShortcutLayoutsPageState();
}

class _ShortcutLayoutsPageState extends State<_ShortcutLayoutsPage> {
  static const transfer = DesktopShortcutTransferService();
  String? selectedLayoutId;
  bool transferring = false;

  @override
  Widget build(BuildContext context) {
    final layouts = widget.controller.manifest.layouts;
    final selected =
        widget.controller.manifest.layoutById(
          selectedLayoutId ??
              widget.controller.manifest.currentLayout?.id ??
              layouts.first.id,
        ) ??
        layouts.first;
    selectedLayoutId = selected.id;
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  key: const ValueKey('layout-selector'),
                  initialValue: selected.id,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: desktopText(context, 'Shortcut Layout', '快捷键布局'),
                  ),
                  items: layouts
                      .map(
                        (layout) => DropdownMenuItem(
                          value: layout.id,
                          child: Text(
                            '${layout.name} · ${desktopText(context, layout.kind.name, switch (layout.kind) {
                              RemoteLayoutKind.keyboard => '键盘',
                              RemoteLayoutKind.application => '应用',
                              RemoteLayoutKind.codex => 'Codex',
                            })}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (value) =>
                      setState(() => selectedLayoutId = value),
                ),
              ),
              const SizedBox(width: 16),
              Chip(
                label: Text(
                  desktopText(
                    context,
                    '${selected.buttons.length} buttons',
                    '${selected.buttons.length} 个按键',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton.icon(
                key: const ValueKey('desktop-import-shortcuts-json'),
                onPressed: transferring ? null : _importJson,
                icon: const Icon(Icons.file_download_outlined),
                label: Text(desktopText(context, 'Import JSON', '导入 JSON')),
              ),
              OutlinedButton.icon(
                key: const ValueKey('desktop-export-shortcuts-json'),
                onPressed: transferring ? null : _exportJson,
                icon: const Icon(Icons.ios_share_outlined),
                label: Text(desktopText(context, 'Export JSON', '导出 JSON')),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 600 ? 4 : 2;
                return GridView.builder(
                  itemCount: selected.buttons.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    mainAxisExtent:
                        120 + MediaQuery.textScalerOf(context).scale(32),
                  ),
                  itemBuilder: (context, index) {
                    final button = selected.buttons[index];
                    return Card(
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        key: ValueKey('desktop-button-${button.id}'),
                        onTap: button.targetType == RemoteTargetType.system
                            ? null
                            : () => _editButton(context, selected, button),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(desktopIcon(button.icon)),
                                  const Spacer(),
                                  if (button.targetType !=
                                      RemoteTargetType.system)
                                    const Icon(Icons.edit_outlined, size: 18),
                                ],
                              ),
                              const Spacer(),
                              Text(
                                button.id == generalCloseAppShortcutId &&
                                        button.name == 'Close App'
                                    ? desktopText(context, 'Close App', '关闭软件')
                                    : button.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 3),
                              Text(
                                _buttonSummary(context, button),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              if (!button.enabled &&
                                  button.description.isNotEmpty)
                                Text(
                                  button.description,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _importJson() async {
    setState(() => transferring = true);
    try {
      final raw = await transfer.importJson();
      if (raw == null) return;
      await widget.controller.importShortcutLayouts(transfer.decode(raw));
      if (mounted) {
        _showTransferMessage(
          desktopText(context, 'Shortcut JSON imported', '已导入快捷键 JSON'),
        );
      }
    } catch (error) {
      if (mounted) _showTransferMessage('$error');
    } finally {
      if (mounted) setState(() => transferring = false);
    }
  }

  Future<void> _exportJson() async {
    setState(() => transferring = true);
    try {
      final exported = await transfer.exportJson(
        widget.controller.manifestForExport,
      );
      if (exported && mounted) {
        _showTransferMessage(
          desktopText(context, 'Shortcut JSON exported', '已导出快捷键 JSON'),
        );
      }
    } catch (error) {
      if (mounted) _showTransferMessage('$error');
    } finally {
      if (mounted) setState(() => transferring = false);
    }
  }

  void _showTransferMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _editButton(
    BuildContext context,
    RemoteShortcutLayout layout,
    RemoteShortcutButton button,
  ) async {
    if (button.targetType == RemoteTargetType.system ||
        button.id.endsWith('.deleteToStart')) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            desktopText(
              context,
              'This Desktop action has a fixed, guarded behavior.',
              '此桌面操作固定且受保护。',
            ),
          ),
        ),
      );
      return;
    }
    final updated = await showRemoteButtonEditor(
      context,
      button: button,
      applications: widget.controller.applicationsForCurrentPlatform,
      keyboardOnly:
          button.id == chatGptNativeVoiceShortcutId ||
          widget.controller.manifest.profiles.any(
            (p) => p.isLibraryProfile && p.layoutId == layout.id,
          ),
    );
    if (updated != null) {
      try {
        await widget.controller.updateButton(layout.id, updated);
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                desktopText(
                  context,
                  'Could not save. App library profiles accept one keyboard chord, or a disabled unassigned action.',
                  '无法保存。应用库配置仅接受一个组合键，或已停用的未分配操作。',
                ),
              ),
            ),
          );
        }
      }
    }
  }
}

class _AppsPage extends StatelessWidget {
  const _AppsPage({required this.controller});

  final DesktopController controller;

  @override
  Widget build(BuildContext context) => _PageBody(
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              desktopText(context, 'Managed Applications', '受管理的应用'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          OutlinedButton.icon(
            onPressed: controller.refreshApplications,
            icon: const Icon(Icons.refresh),
            label: Text(
              desktopText(context, 'Refresh installed apps', '刷新已安装应用'),
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      Text(
        desktopText(
          context,
          'Manage shortcut-enabled applications here. Choose all installed launch-only applications in Launchpad.',
          '在此管理支持快捷键的应用。可在启动台中选择已安装的仅启动应用。',
        ),
      ),
      const SizedBox(height: 12),
      Align(
        alignment: Alignment.centerLeft,
        child: FilledButton.icon(
          key: const ValueKey('desktop-open-app-library'),
          icon: const Icon(Icons.library_books_outlined),
          label: Text(desktopText(context, 'App library', '应用库')),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => DesktopAppLibraryPage(controller: controller),
            ),
          ),
        ),
      ),
      const SizedBox(height: 12),
      ...controller.applicationsForCurrentPlatform.map(
        (app) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Card(
            child: ListTile(
              leading: CircleAvatar(child: Icon(desktopIcon(app.icon))),
              title: Text(app.name),
              subtitle: Text(
                '${app.executable} · ${app.detected ? desktopText(context, 'Detected', '已检测到') : desktopText(context, 'Not detected', '未检测到')}',
              ),
              trailing: Wrap(
                spacing: 8,
                children: [
                  Chip(
                    avatar: Icon(
                      app.detected ? Icons.check_circle : Icons.help_outline,
                      size: 16,
                      color: app.detected ? Colors.green : null,
                    ),
                    label: Text(
                      app.detected
                          ? desktopText(context, 'Installed', '已安装')
                          : desktopText(context, 'Configured', '已配置'),
                    ),
                  ),
                  IconButton(
                    tooltip: desktopText(context, 'Edit app', '编辑应用'),
                    onPressed: () => _editApp(context, app),
                    icon: const Icon(Icons.edit_outlined),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ],
  );

  Future<void> _editApp(BuildContext context, RemoteApplication app) async {
    final updated = await showDialog<RemoteApplication>(
      context: context,
      builder: (_) => _ApplicationEditor(app: app),
    );
    if (updated != null) await controller.updateApplication(updated);
  }
}

class _LauncherPage extends StatefulWidget {
  const _LauncherPage({required this.controller, required this.codexActivity});

  final DesktopController controller;
  final CodexActivityMonitor codexActivity;

  @override
  State<_LauncherPage> createState() => _LauncherPageState();
}

class _LauncherPageState extends State<_LauncherPage> {
  DateTime _now = DateTime.now();
  Timer? _clockTimer;
  String? _error;
  bool? _muted;
  bool _busy = false;
  bool _checkingMute = false;
  int _clockTick = 0;
  int _muteGeneration = 0;

  @override
  void initState() {
    super.initState();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
      _clockTick++;
      if (_clockTick % 3 == 0) unawaited(_refreshMuteState());
    });
    unawaited(_refreshMuteState());
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshMuteState() async {
    if (_checkingMute || _busy) return;
    _checkingMute = true;
    final generation = _muteGeneration;
    try {
      final value = await widget.controller.actions.getOutputMuted();
      if (mounted &&
          generation == _muteGeneration &&
          !_busy &&
          _muted != value) {
        setState(() => _muted = value);
      }
    } catch (_) {
      if (mounted &&
          generation == _muteGeneration &&
          !_busy &&
          _muted != null) {
        setState(() => _muted = null);
      }
    } finally {
      _checkingMute = false;
    }
  }

  String get _time =>
      '${_two(_now.hour)}:${_two(_now.minute)}:${_two(_now.second)}';
  static String _two(int value) => value.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final date = MaterialLocalizations.of(context).formatFullDate(_now);
    final controller = widget.controller;
    return LayoutBuilder(
      builder: (context, constraints) {
        final contentWidth = (constraints.maxWidth - 56).clamp(
          0,
          double.infinity,
        );
        final columns = contentWidth < 620 ? 2 : 4;
        final spacing = 12.0;
        final tileWidth = (contentWidth - spacing * (columns - 1)) / columns;
        return ListView(
          key: const ValueKey('launcher-page'),
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 26),
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        desktopText(context, 'Quick Launcher', '快捷启动台'),
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        desktopText(
                          context,
                          'Open your frequently used applications.',
                          '启动常用应用。',
                        ),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        key: const ValueKey('launcher-edit'),
                        onPressed: () => _editKey(0),
                        icon: const Icon(Icons.edit_outlined, size: 17),
                        label: Text(desktopText(context, 'Edit Keys', '编辑按键')),
                      ),
                      OutlinedButton.icon(
                        key: const ValueKey('launcher-open-app-bar'),
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (context) => Scaffold(
                              appBar: AppBar(
                                title: Text(
                                  desktopText(context, 'App Bar', '应用栏'),
                                ),
                              ),
                              body: PhoneSidebarPage(
                                controller: controller,
                                codexActivity: widget.codexActivity,
                              ),
                            ),
                          ),
                        ),
                        icon: const Icon(Icons.view_sidebar_outlined, size: 17),
                        label: Text(desktopText(context, 'App Bar', '应用栏')),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            _clockBar(context, theme, date),
            const SizedBox(height: 22),
            Row(
              children: [
                Text(
                  desktopText(context, 'My Apps', '我的应用'),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  desktopText(
                    context,
                    '$launcherSlotCount shortcut keys',
                    '$launcherSlotCount 个快捷按键',
                  ),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: List.generate(launcherSlotCount, (index) {
                final appId = widget.controller.launcherAppIds[index];
                final app = appId == null
                    ? null
                    : widget.controller.manifest.applicationById(appId);
                return SizedBox(
                  width: tileWidth,
                  height: 108,
                  child: _LauncherKey(
                    index: index,
                    app: app,
                    iconService: widget.controller.actions.appIconService,
                    onTap: app != null && !app.detected
                        ? null
                        : () => app == null ? _editKey(index) : _launch(index),
                    onEdit: () => _editKey(index),
                  ),
                );
              }),
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                _SystemActionButton(
                  icon: Icons.play_arrow,
                  label: desktopText(context, 'Play / Pause', '播放 / 暂停'),
                  onPressed: _busy ? null : _playPause,
                ),
                _SystemActionButton(
                  icon: _muted == null
                      ? Icons.help_outline
                      : _muted == true
                      ? Icons.volume_off_outlined
                      : Icons.volume_up_outlined,
                  label: _muted == null
                      ? desktopText(context, 'Mute Status Unknown', '静音状态未知')
                      : _muted == true
                      ? desktopText(context, 'Muted', '已静音')
                      : desktopText(context, 'Mute System', '系统静音'),
                  onPressed: _busy ? null : _toggleMute,
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 14),
              Material(
                key: const ValueKey('launcher-error'),
                color: theme.colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 11,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.error_outline,
                        color: theme.colorScheme.error,
                        size: 18,
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          _error!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onErrorContainer,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: desktopText(context, 'Close', '关闭'),
                        onPressed: () => setState(() => _error = null),
                        icon: const Icon(Icons.close, size: 17),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _clockBar(BuildContext context, ThemeData theme, String date) =>
      Container(
        key: const ValueKey('launcher-clock'),
        height: 68,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: LinearGradient(
            colors: [
              theme.colorScheme.primaryContainer.withValues(alpha: .75),
              theme.colorScheme.surfaceContainerHighest,
            ],
          ),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Row(
          children: [
            Icon(Icons.schedule, color: theme.colorScheme.primary),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                desktopText(context, 'Local time', '本地时间'),
                style: theme.textTheme.labelLarge,
              ),
            ),
            const SizedBox(width: 18),
            Text(
              _time,
              key: const ValueKey('launcher-clock-time'),
              style: theme.textTheme.headlineSmall?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
                letterSpacing: 1.4,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 16),
            Container(
              width: 1,
              height: 25,
              color: theme.colorScheme.outlineVariant,
            ),
            const SizedBox(width: 16),
            Flexible(
              child: Text(
                date,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      );

  Future<void> _editKey(int index) async {
    final selected = await showDialog<String>(
      context: context,
      builder: (_) =>
          InstalledAppPicker(controller: widget.controller, index: index),
    );
    if (selected == null || !mounted) return;
    try {
      await widget.controller.assignLauncherApp(
        index,
        selected.isEmpty ? null : selected,
      );
      if (mounted) setState(() => _error = null);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  Future<void> _launch(int index) async {
    setState(() => _error = null);
    try {
      await widget.controller.launchLauncherApp(index);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  Future<void> _playPause() async {
    setState(() => _busy = true);
    try {
      await widget.controller.actions.playPause();
      if (mounted) setState(() => _error = null);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleMute() async {
    setState(() => _busy = true);
    _muteGeneration++;
    try {
      final muted = await widget.controller.actions.toggleOutputMute();
      if (mounted) {
        setState(() {
          _muted = muted;
          _error = null;
          _muteGeneration++;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _LauncherKey extends StatelessWidget {
  const _LauncherKey({
    required this.index,
    required this.app,
    required this.iconService,
    required this.onTap,
    required this.onEdit,
  });

  final int index;
  final RemoteApplication? app;
  final NativeAppIconService iconService;
  final VoidCallback? onTap;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        key: ValueKey('launcher-key-$index'),
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: app == null
                        ? Icon(
                            Icons.add,
                            color: theme.colorScheme.onPrimaryContainer,
                            size: 23,
                          )
                        : DesktopApplicationArtwork(
                            app: app!,
                            size: 34,
                            iconService: iconService,
                          ),
                  ),
                  const Spacer(),
                  Text(
                    app?.name ?? desktopText(context, 'Add App', '添加快捷应用'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    app == null
                        ? desktopText(context, 'Click to configure', '点击配置')
                        : app!.detected
                        ? desktopText(context, 'Click to launch', '点击启动')
                        : desktopText(
                            context,
                            'App unavailable · assignment kept',
                            '应用不可用 · 绑定已保留',
                          ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              Positioned(
                right: 0,
                top: -3,
                child: Text(
                  '${index + 1}'.padLeft(2, '0'),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              Positioned(
                right: -9,
                bottom: -10,
                child: IconButton(
                  key: ValueKey('launcher-edit-$index'),
                  tooltip: desktopText(
                    context,
                    'Edit Key ${index + 1}',
                    '编辑按键 ${index + 1}',
                  ),
                  onPressed: onEdit,
                  icon: const Icon(Icons.more_horiz, size: 18),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SystemActionButton extends StatelessWidget {
  const _SystemActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: onPressed,
    icon: Icon(icon, size: 18),
    label: Text(label),
  );
}

class _ApplicationEditor extends StatefulWidget {
  const _ApplicationEditor({required this.app});

  final RemoteApplication app;

  @override
  State<_ApplicationEditor> createState() => _ApplicationEditorState();
}

class _ApplicationEditorState extends State<_ApplicationEditor> {
  late final TextEditingController name;
  late final TextEditingController icon;
  late final TextEditingController executable;

  @override
  void initState() {
    super.initState();
    name = TextEditingController(text: widget.app.name);
    icon = TextEditingController(text: widget.app.icon);
    executable = TextEditingController(text: widget.app.executable);
  }

  @override
  void dispose() {
    name.dispose();
    icon.dispose();
    executable.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      desktopText(context, 'Edit ${widget.app.name}', '编辑 ${widget.app.name}'),
    ),
    content: SizedBox(
      width: 520,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: name,
            decoration: InputDecoration(
              labelText: desktopText(context, 'Name', '名称'),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: icon,
            decoration: InputDecoration(
              labelText: desktopText(context, 'Icon', '图标'),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: executable,
            decoration: InputDecoration(
              labelText: desktopText(
                context,
                'Executable / Application name',
                '可执行文件 / 应用名称',
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            initialValue: widget.app.layoutId,
            readOnly: true,
            decoration: InputDecoration(
              labelText: desktopText(context, 'Shortcut Layout', '快捷键布局'),
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(desktopText(context, 'Cancel', '取消')),
      ),
      FilledButton(
        onPressed: () {
          if (name.text.trim().isEmpty || executable.text.trim().isEmpty) {
            return;
          }
          Navigator.pop(
            context,
            widget.app.copyWith(
              name: name.text.trim(),
              icon: icon.text.trim(),
              executable: executable.text.trim(),
            ),
          );
        },
        child: Text(desktopText(context, 'Save', '保存')),
      ),
    ],
  );
}

class _AboutPage extends StatefulWidget {
  const _AboutPage({required this.inputBackend});

  final DesktopInputBackend inputBackend;

  @override
  State<_AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<_AboutPage> {
  late final Future<PackageInfo> _packageInfo = PackageInfo.fromPlatform();

  @override
  Widget build(BuildContext context) => _PageBody(
    children: [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            children: [
              const Image(
                key: ValueKey('desktop-about-logo-image'),
                image: AssetImage(desktopBrandAsset),
                width: 80,
                height: 80,
                filterQuality: FilterQuality.high,
                semanticLabel: 'LumiaKey logo',
              ),
              const SizedBox(height: 16),
              const Text(
                'LumiaKey Desktop',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              FutureBuilder<PackageInfo>(
                future: _packageInfo,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return Text(
                      desktopText(context, 'Loading version…', '正在读取版本…'),
                    );
                  }
                  final version = snapshot.data?.version.trim() ?? '';
                  if (version.isEmpty) {
                    return Text(
                      desktopText(context, 'Version unavailable', '无法获取版本'),
                    );
                  }
                  final build = snapshot.data?.buildNumber.trim() ?? '';
                  return Text(
                    desktopText(
                      context,
                      'Version $version${build.isEmpty ? '' : ' (build $build)'}',
                      '版本 $version${build.isEmpty ? '' : '（构建 $build）'}',
                    ),
                  );
                },
              ),
              const SizedBox(height: 6),
              Text(switch (widget.inputBackend) {
                DesktopInputBackend.standard => desktopText(
                  context,
                  'Input backend: Standard',
                  '输入后端：标准',
                ),
                DesktopInputBackend.rust => desktopText(
                  context,
                  'Input backend: Rust (selected)',
                  '输入后端：已选择 Rust',
                ),
                DesktopInputBackend.rustShortcuts => desktopText(
                  context,
                  'Input backend: Rust shortcuts (selected)',
                  '输入后端：已选择 Rust（仅快捷键）',
                ),
              }),
              const SizedBox(height: 18),
              Text(
                desktopText(
                  context,
                  'Manage LumiaKey shortcut layouts, apps, profiles, and icons from this computer. Desktop actions run here.',
                  '在此电脑上管理 LumiaKey 快捷键布局、应用、配置方案和图标。桌面操作在此电脑上执行。',
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    ],
  );
}

Future<RemoteShortcutButton?> showRemoteButtonEditor(
  BuildContext context, {
  required RemoteShortcutButton button,
  required List<RemoteApplication> applications,
  bool keyboardOnly = false,
}) => showDialog<RemoteShortcutButton>(
  context: context,
  builder: (_) => _RemoteButtonEditor(
    button: button,
    applications: applications,
    keyboardOnly: keyboardOnly,
  ),
);

class _RemoteButtonEditor extends StatefulWidget {
  const _RemoteButtonEditor({
    required this.button,
    required this.applications,
    this.keyboardOnly = false,
  });
  final bool keyboardOnly;

  final RemoteShortcutButton button;
  final List<RemoteApplication> applications;

  @override
  State<_RemoteButtonEditor> createState() => _RemoteButtonEditorState();
}

class _RemoteButtonEditorState extends State<_RemoteButtonEditor> {
  late final TextEditingController name;
  late final TextEditingController icon;
  late final TextEditingController shortcut;
  late final TextEditingController target;
  late final TextEditingController description;
  late bool enabled;
  late RemoteTargetType type;
  String? selectedApp;
  String? validationError;

  @override
  void initState() {
    super.initState();
    final button = widget.button;
    name = TextEditingController(text: button.name);
    icon = TextEditingController(text: button.icon);
    shortcut = TextEditingController(text: formatShortcut(button.shortcut));
    target = TextEditingController(
      text: button.targetType == RemoteTargetType.openUrl
          ? button.target ?? ''
          : '',
    );
    description = TextEditingController(text: button.description);
    enabled = button.enabled;
    type = button.targetType;
    selectedApp = button.targetType == RemoteTargetType.launchApplication
        ? button.target
        : widget.applications.isEmpty
        ? null
        : widget.applications.first.id;
  }

  @override
  void dispose() {
    name.dispose();
    icon.dispose();
    shortcut.dispose();
    target.dispose();
    description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      desktopText(
        context,
        'Edit ${widget.button.name}',
        '编辑 ${widget.button.name}',
      ),
    ),
    content: SizedBox(
      width: 560,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration: InputDecoration(
                labelText: desktopText(context, 'Button Name', '按键名称'),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: icon,
              decoration: InputDecoration(
                labelText: desktopText(context, 'Icon', '图标'),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<RemoteTargetType>(
              initialValue: type,
              decoration: InputDecoration(
                labelText: desktopText(context, 'Target Type', '目标类型'),
              ),
              items: RemoteTargetType.values
                  .where(
                    (value) =>
                        (!widget.keyboardOnly &&
                            !widget.button.id.startsWith('vibe.')) ||
                        value == RemoteTargetType.keyboardShortcut,
                  )
                  .map(
                    (value) => DropdownMenuItem(
                      value: value,
                      enabled:
                          value != RemoteTargetType.macro &&
                          value != RemoteTargetType.script &&
                          value != RemoteTargetType.system,
                      child: Text(
                        '${_targetTypeLabel(context, value)}${value == RemoteTargetType.macro || value == RemoteTargetType.script
                            ? desktopText(context, ' · Future', ' · 未来功能')
                            : value == RemoteTargetType.system
                            ? desktopText(context, ' · Fixed', ' · 固定')
                            : ''}',
                      ),
                    ),
                  )
                  .toList(growable: false),
              onChanged: (value) {
                if (value != null) setState(() => type = value);
              },
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(desktopText(context, 'Enabled', '已启用')),
              value: enabled,
              onChanged: (value) => setState(() => enabled = value),
            ),
            if (type == RemoteTargetType.keyboardShortcut)
              TextField(
                key: const ValueKey('shortcut-field'),
                controller: shortcut,
                decoration: InputDecoration(
                  labelText: desktopText(context, 'Shortcut', '快捷键'),
                  hintText: 'PRIMARY + SHIFT + V',
                  helperText: desktopText(
                    context,
                    'PRIMARY becomes Command on macOS and Ctrl on Windows.',
                    'PRIMARY 在 macOS 上表示 Command，在 Windows 上表示 Ctrl。',
                  ),
                ),
              )
            else if (type == RemoteTargetType.launchApplication)
              DropdownButtonFormField<String>(
                initialValue:
                    widget.applications.any((app) => app.id == selectedApp)
                    ? selectedApp
                    : null,
                decoration: InputDecoration(
                  labelText: desktopText(context, 'Launch App', '启动应用'),
                ),
                items: widget.applications
                    .map(
                      (app) => DropdownMenuItem(
                        value: app.id,
                        child: Text(app.name),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) => setState(() => selectedApp = value),
              )
            else if (type == RemoteTargetType.openUrl)
              TextField(
                controller: target,
                decoration: const InputDecoration(
                  labelText: 'URL',
                  hintText: 'https://example.com',
                ),
              )
            else
              ListTile(
                leading: const Icon(Icons.schedule),
                title: Text(
                  desktopText(
                    context,
                    'Reserved for a future LumiaKey release',
                    '将在未来的 LumiaKey 版本中提供',
                  ),
                ),
              ),
            const SizedBox(height: 12),
            TextField(
              controller: description,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: desktopText(context, 'Description', '说明'),
              ),
            ),
            if (validationError != null) ...[
              const SizedBox(height: 10),
              Text(
                validationError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(desktopText(context, 'Cancel', '取消')),
      ),
      FilledButton(
        onPressed: _save,
        child: Text(desktopText(context, 'Save', '保存')),
      ),
    ],
  );

  void _save() {
    final keys = parseShortcut(shortcut.text);
    final nextTarget = switch (type) {
      RemoteTargetType.launchApplication => selectedApp,
      RemoteTargetType.openUrl => target.text.trim(),
      _ => null,
    };
    if (name.text.trim().isEmpty ||
        (enabled &&
            type == RemoteTargetType.keyboardShortcut &&
            keys.isEmpty) ||
        ((type == RemoteTargetType.launchApplication ||
                type == RemoteTargetType.openUrl) &&
            (nextTarget == null || nextTarget.isEmpty))) {
      setState(
        () => validationError = desktopText(
          context,
          'Complete the required target fields.',
          '请填写所需的目标字段。',
        ),
      );
      return;
    }
    Navigator.pop(
      context,
      widget.button.copyWith(
        name: name.text.trim(),
        icon: icon.text.trim(),
        targetType: type,
        shortcut: type == RemoteTargetType.keyboardShortcut ? keys : const [],
        target: nextTarget,
        clearTarget: nextTarget == null,
        description: description.text.trim(),
        enabled: enabled,
      ),
    );
  }
}

class _LocalDictationPage extends StatefulWidget {
  const _LocalDictationPage({required this.dictation});
  final DesktopDictationService dictation;

  @override
  State<_LocalDictationPage> createState() => _LocalDictationPageState();
}

class _LocalDictationPageState extends State<_LocalDictationPage> {
  late Future<bool> _available;

  @override
  void initState() {
    super.initState();
    _available = widget.dictation.modelAvailable();
  }

  Future<void> _refreshModel() async {
    setState(() {
      _available = widget.dictation.modelAvailable();
    });
  }

  Future<void> _start() async {
    final service = widget.dictation;
    if (!service.firstUseAcknowledged) {
      final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.mic),
          title: Text(desktopText(context, 'Local Dictation', '本地听写')),
          content: Text(
            desktopText(
              context,
              service.testFlightInput
                  ? 'Audio is processed on this Mac and is never saved. Review the transcript here and copy it when you need it. The microphone will start after you continue.'
                  : 'Local Dictation uses this computer’s microphone and the selected installed model. Audio is processed on this computer and is not saved. Phone dictation sends final text to this computer, never audio. App Voice Input is a separate shortcut that follows the selected application’s own microphone and privacy behavior. The microphone will start only after you continue.',
              service.testFlightInput
                  ? '音频在这台 Mac 上处理，不会保存。识别结果会显示在这里，需要时可手动复制。继续后会启动麦克风。'
                  : '本地听写使用此电脑的麦克风和所选的已安装模型。音频在本机处理，不会保存。手机听写只向电脑发送最终文本。应用语音输入是独立的快捷键，遵循所选应用的麦克风和隐私设置。继续后才会启动麦克风。',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(desktopText(context, 'Cancel', '取消')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(
                desktopText(context, 'I understand — continue', '我知道了，继续'),
              ),
            ),
          ],
        ),
      );
      if (accepted != true) return;
      await service.acknowledgeFirstUse();
    }
    try {
      await service.start();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              service.error ??
                  desktopText(
                    context,
                    'Could not start local dictation.',
                    '无法开始本地听写。',
                  ),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.dictation,
    builder: (context, _) {
      final service = widget.dictation;
      final theme = Theme.of(context);
      String text(String english, String chinese) =>
          desktopText(context, english, chinese);
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            text('Private microphone dictation', '私密麦克风听写'),
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: 6),
          Text(
            service.testFlightInput
                ? text(
                    'TestFlight shows the transcript here for manual copying. It cannot verify a text field in another app.',
                    'TestFlight 版会在这里显示识别文字，供手动复制。此版本无法验证其他应用中的文本框。',
                  )
                : text(
                    'Recognize speech on this computer and type the final text into the focused external app.',
                    '在此电脑上识别语音，并将最终文本输入当前获得焦点的外部应用。',
                  ),
          ),
          const SizedBox(height: 18),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.graphic_eq, size: 30),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      text(
                        'App Voice Input\nRuns the selected app’s own dictation shortcut.',
                        '应用语音输入\n运行所选应用自带的听写快捷键。',
                      ),
                    ),
                  ),
                  const Icon(Icons.arrow_forward),
                  const SizedBox(width: 12),
                  Icon(Icons.mic, size: 30, color: theme.colorScheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      text(
                        'Local Dictation\nUses this computer’s microphone and local model.',
                        '本地听写\n使用此电脑的麦克风和本地模型。',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          text('Recognition', '语音识别'),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      DropdownButton<DictationLanguage>(
                        key: const ValueKey('dictation-language'),
                        value: service.language,
                        onChanged: service.busy || service.listening
                            ? null
                            : (value) async {
                                if (value != null) {
                                  await service.configure(language: value);
                                }
                              },
                        items: DictationLanguage.values
                            .map(
                              (value) => DropdownMenuItem(
                                value: value,
                                child: Text(value.label),
                              ),
                            )
                            .toList(),
                      ),
                      const SizedBox(width: 12),
                      DropdownButton<LocalAsrModel>(
                        key: const ValueKey('dictation-model'),
                        value: service.model,
                        onChanged: service.busy || service.listening
                            ? null
                            : (value) async {
                                if (value != null) {
                                  await service.configure(model: value);
                                  await _refreshModel();
                                }
                              },
                        items: LocalAsrModel.values
                            .map(
                              (value) => DropdownMenuItem(
                                value: value,
                                child: Text(value.label),
                              ),
                            )
                            .toList(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  FutureBuilder<bool>(
                    future: _available,
                    builder: (context, snapshot) => Row(
                      children: [
                        Icon(
                          snapshot.data == true
                              ? Icons.verified
                              : Icons.download_for_offline_outlined,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            snapshot.data == true
                                ? text(
                                    'Model verified and ready for offline use.',
                                    '模型已验证，可离线使用。',
                                  )
                                : text(
                                    'Model is not installed. Install or import it explicitly before starting.',
                                    '模型尚未安装。请先下载或导入模型。',
                                  ),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: service.busy || service.listening
                              ? null
                              : () async {
                                  try {
                                    await service.installModel();
                                    await _refreshModel();
                                  } catch (_) {}
                                },
                          icon: const Icon(Icons.download),
                          label: Text(text('Download', '下载')),
                        ),
                        TextButton.icon(
                          onPressed: service.busy || service.listening
                              ? null
                              : () async {
                                  try {
                                    await service.importModel();
                                    await _refreshModel();
                                  } catch (_) {}
                                },
                          icon: const Icon(Icons.folder_open),
                          label: Text(text('Import', '导入')),
                        ),
                        IconButton(
                          tooltip: text('Delete installed model', '删除已安装的模型'),
                          onPressed:
                              service.busy ||
                                  service.listening ||
                                  snapshot.data != true
                              ? null
                              : () async {
                                  await service.deleteModel(service.model);
                                  await _refreshModel();
                                },
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    ),
                  ),
                  if (service.progress case final progress?) ...[
                    const SizedBox(height: 10),
                    LinearProgressIndicator(
                      value: progress.fraction > 0
                          ? progress.fraction.clamp(0, 1)
                          : null,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      text(
                        'Downloading ${progress.fileName} · ${(progress.fraction * 100).round()}%',
                        '正在下载 ${progress.fileName} · ${(progress.fraction * 100).round()}%',
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (service.usesMacInputPermissions && !service.testFlightInput)
            Card(
              child: ListTile(
                leading: Icon(
                  service.accessibilityGranted
                      ? Icons.check_circle_outline
                      : Icons.accessibility_new,
                ),
                title: Text(
                  service.accessibilityGranted
                      ? text(
                          'Accessibility and event permissions are ready',
                          '辅助功能和事件权限已就绪',
                        )
                      : text(
                          'macOS input permission required',
                          '需要 macOS 输入权限',
                        ),
                ),
                subtitle: Text(
                  text(
                    'macOS needs Accessibility and event posting permission to type into the focused app.',
                    '在当前应用中输入文字需要 macOS 辅助功能和事件发送权限。',
                  ),
                ),
                trailing: Wrap(
                  children: [
                    TextButton(
                      onPressed: service.requestAccessibility,
                      child: Text(text('Request', '请求权限')),
                    ),
                    TextButton(
                      onPressed: service.openAccessibilitySettings,
                      child: Text(text('Settings', '系统设置')),
                    ),
                    IconButton(
                      onPressed: service.refreshAccessibility,
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                ),
              ),
            ),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: Icon(
                    service.listening ? Icons.mic : Icons.mic_none,
                    color: service.listening ? theme.colorScheme.primary : null,
                  ),
                  title: Text(
                    service.listening
                        ? text('Listening on this computer', '正在此电脑上听写')
                        : text('Local microphone is stopped', '本地麦克风已停止'),
                  ),
                  subtitle: Text(
                    service.lastText.isEmpty || service.testFlightInput
                        ? text(
                            'Audio stays in bounded memory and is never saved.',
                            '音频仅暂存于有限内存中，不会保存。',
                          )
                        : service.lastText,
                  ),
                  trailing: FilledButton.icon(
                    key: const ValueKey('dictation-toggle'),
                    onPressed:
                        service.busy && !service.starting && !service.listening
                        ? null
                        : service.listening || service.starting
                        ? service.stop
                        : _start,
                    icon: Icon(
                      service.listening || service.starting
                          ? Icons.stop
                          : Icons.mic,
                    ),
                    label: Text(
                      service.starting
                          ? text('Cancel start', '取消启动')
                          : service.listening
                          ? text('Stop', '停止')
                          : text('Start local dictation', '开始本地听写'),
                    ),
                  ),
                ),
                if (service.testFlightInput && service.lastText.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SelectableText(service.lastText),
                        TextButton.icon(
                          key: const ValueKey('testflight-copy-transcript'),
                          onPressed: () => Clipboard.setData(
                            ClipboardData(text: service.lastText),
                          ),
                          icon: const Icon(Icons.copy),
                          label: Text(text('Copy transcript', '复制识别文字')),
                        ),
                      ],
                    ),
                  ),
                if (service.error != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        service.error!,
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (!service.testFlightInput)
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.keyboard),
                    title: Text(text('Global toggle shortcut', '全局切换快捷键')),
                    subtitle: Text(
                      service.hotkeyError ??
                          text(
                            'Ctrl+Shift+Space starts or stops local dictation.',
                            '按 Ctrl+Shift+Space 开始或停止本地听写。',
                          ),
                    ),
                    trailing: DropdownButton<String>(
                      key: const ValueKey('dictation-hotkey'),
                      value: service.hotkey,
                      onChanged: (value) {
                        if (value != null) unawaited(service.setHotkey(value));
                      },
                      items: const [
                        DropdownMenuItem(
                          value: 'ctrlShiftSpace',
                          child: Text('Ctrl + Shift + Space'),
                        ),
                        DropdownMenuItem(
                          value: 'ctrlAltSpace',
                          child: Text('Ctrl + Alt + Space'),
                        ),
                        DropdownMenuItem(
                          value: 'altShiftSpace',
                          child: Text('Alt + Shift + Space'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      );
    },
  );
}

String _targetTypeLabel(BuildContext context, RemoteTargetType type) =>
    switch (type) {
      RemoteTargetType.keyboardShortcut => desktopText(
        context,
        'Keyboard Shortcut',
        '键盘快捷键',
      ),
      RemoteTargetType.launchApplication => desktopText(
        context,
        'Launch Application',
        '启动应用',
      ),
      RemoteTargetType.voiceInput => desktopText(
        context,
        'Voice Input',
        '语音输入',
      ),
      RemoteTargetType.openUrl => desktopText(context, 'Open URL', '打开网址'),
      RemoteTargetType.macro => desktopText(context, 'Macro', '宏'),
      RemoteTargetType.script => desktopText(context, 'Script', '脚本'),
      RemoteTargetType.system => desktopText(
        context,
        'Desktop System Action',
        '桌面系统操作',
      ),
    };

String _buttonSummary(BuildContext context, RemoteShortcutButton button) =>
    switch (button.targetType) {
      RemoteTargetType.keyboardShortcut =>
        isUnassignedChatGptShortcut(button)
            ? desktopText(context, 'Unassigned', '未设置')
            : formatShortcut(button.shortcut),
      RemoteTargetType.launchApplication => desktopText(
        context,
        'Launch ${button.target ?? 'app'}',
        '启动${button.target ?? '应用'}',
      ),
      RemoteTargetType.voiceInput => desktopText(
        context,
        'Start Codex dictation',
        '开始 Codex 听写',
      ),
      RemoteTargetType.openUrl => button.target ?? 'URL',
      RemoteTargetType.macro => desktopText(
        context,
        'Macro · Future',
        '宏 · 未来功能',
      ),
      RemoteTargetType.script => desktopText(
        context,
        'Script · Future',
        '脚本 · 未来功能',
      ),
      RemoteTargetType.system =>
        isChatGptLocalDictationShortcut(button)
            ? desktopText(context, 'Phone control', '手机操作')
            : button.name,
    };

IconData desktopIcon(String id) => switch (id) {
  'graphic_eq' => Icons.graphic_eq,
  'mic_external_on' => Icons.mic_external_on,
  'bolt' => Icons.bolt,
  'call_split' => Icons.call_split,
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
  'terminal' => Icons.terminal,
  'code' => Icons.code,
  'mic' => Icons.mic,
  'send' => Icons.send,
  'folder_back' => Icons.drive_folder_upload_outlined,
  'folder_next' => Icons.next_plan_outlined,
  'arrow_up' => Icons.keyboard_arrow_up,
  'arrow_down' => Icons.keyboard_arrow_down,
  'stop' => Icons.stop_circle_outlined,
  'science' => Icons.science_outlined,
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
  'add' => Icons.add,
  'volume_up' => Icons.volume_up,
  'volume_down' => Icons.volume_down,
  'music' => Icons.music_note,
  'create_new_folder' => Icons.create_new_folder_outlined,
  'info' => Icons.info_outline,
  'delete' => Icons.delete_outline,
  'grid_view' => Icons.grid_view,
  'view_list' => Icons.view_list,
  'view_column' => Icons.view_column,
  'visibility' => Icons.visibility_outlined,
  _ => Icons.keyboard_command_key,
};
