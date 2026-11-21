import 'package:flutter/material.dart';

import '../app.dart';
import '../app_edition.dart';
import '../controllers/app_controller.dart';
import '../data/community_setup_repository.dart';
import '../mobile_appearance.dart';
import '../models/config.dart';
import '../services/ios_companion_hid_service.dart';
import 'bluetooth_connection_sheet.dart';
import 'profile_management_screen.dart';
import 'shortcut_community_screen.dart';
import 'desktop_installers_screen.dart';
import 'desktop_connection_panel.dart';
import 'usage_dashboard_screen.dart';
import 'community_setup_screen.dart';
import 'lite_shortcut_settings_screen.dart';
import '../diagnostics/diagnostics_service.dart';
import 'error_log_screen.dart';
import 'app_icon_library_screen.dart';
import 'dictation_startup_setting.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final controller = SmartKeysScope.of(context);
    final preferences = controller.config.preferences;
    final isIosDesktop = controller.hid is IosCompanionHidService;
    final isLite = SmartKeysScope.editionOf(context) == AppEdition.lite;
    final appearance = MobileAppearanceScope.maybeOf(context);
    final content = ListView(
      key: ValueKey(embedded ? 'embedded-settings' : 'settings-list'),
      children: [
        if (!isLite && appearance != null) ...[
          _AppearanceSettings(appearance: appearance),
          const Divider(),
        ],
        if (!isLite) ...[
          ListTile(
            key: const ValueKey('open-app-icon-library'),
            leading: const Icon(Icons.apps),
            title: const MobileText('App library', '应用库'),
            subtitle: const MobileText(
              'App icons and shortcuts for your computer OS',
              '适用于电脑操作系统的应用图标和快捷键',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const AppIconLibraryScreen(),
              ),
            ),
          ),
          if (DiagnosticsScope.maybeOf(context) case final diagnostics?)
            ListTile(
              key: const ValueKey('open-error-logs'),
              leading: const Icon(Icons.bug_report_outlined),
              title: const MobileText('Error logs', '错误日志'),
              subtitle: Text(
                diagnostics.sharing
                    ? context.mobileText('Error sharing allowed', '已允许分享错误日志')
                    : context.mobileText(
                        'Saved only on this device',
                        '仅保存在本设备',
                      ),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ErrorLogScreen(diagnostics: diagnostics),
                ),
              ),
            ),
        ],
        if (isLite) ...[
          const _SectionLabel('BLUETOOTH HID', '蓝牙 HID'),
          ValueListenableBuilder(
            valueListenable: controller.hid.connectionStatus,
            builder: (context, status, _) => ListTile(
              leading: const Icon(Icons.bluetooth),
              title: const MobileText('Computer connection', '电脑连接'),
              subtitle: Text(status.name),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => showBluetoothConnectionSheet(
                context,
                controller.hid,
                beforeConnect: controller.prepareForBluetoothHostSelection,
              ),
            ),
          ),
          const Divider(),
        ],
        if (!isLite) ...[
          const _SectionLabel('DESKTOP COMPANION', '桌面连接'),
          DesktopConnectionPanel(
            companion: controller.companion,
            onDisconnect: controller.disconnectActiveDesktop,
          ),
          const Divider(),
          const ListTile(
            leading: Icon(Icons.desktop_windows_outlined),
            title: MobileText(
              'Shortcut settings on your computer',
              '在电脑上设置快捷键',
            ),
            subtitle: MobileText(
              'Edit applications and shortcut buttons in LumiaKey Desktop. '
                  'Launchpad shows the installed apps synced from your computer. '
                  'The mobile app displays twelve buttons in four columns and three rows.',
              '在 LumiaKey Desktop 中编辑应用和快捷按键。启动台显示从电脑同步的应用，'
                  '移动端以四列三行显示 12 个按键。',
            ),
          ),
        ],
        if (isLite) ...[
          const _SectionLabel('LOCAL SHORTCUTS', '本地快捷键'),
          ListTile(
            key: const ValueKey('lite-shortcut-settings'),
            leading: const Icon(Icons.keyboard_outlined),
            title: const MobileText('Shortcut settings', '快捷键设置'),
            subtitle: const MobileText(
              'Edit General, ChatGPT, Chrome, or add a profile',
              '编辑常规、ChatGPT、Chrome，或新增配置',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => const LiteShortcutSettingsScreen(),
              ),
            ),
          ),
          if (appearance != null) ...[
            const Divider(),
            _AppearanceSettings(appearance: appearance),
            const Divider(),
          ],
          const _SectionLabel('SHORTCUT PLATFORM', '快捷键平台'),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: MobileText(
              'Per-app shortcuts are sent exactly as entered. This setting is the fallback for Primary profile keys; the saved or paired computer OS takes priority.',
              '各应用的快捷键按输入值发送。此设置用于配置中的主修饰键，已保存或已配对的电脑系统优先。',
            ),
          ),
          Builder(
            builder: (context) {
              final computer = controller.activeComputer;
              final operatingSystem = computer?.operatingSystem;
              final currentSystem = operatingSystem == null
                  ? 'Computer OS not identified'
                  : operatingSystem.label;
              final modifier = controller.primaryShortcutLabel == 'Command'
                  ? 'Command (⌘)'
                  : 'Ctrl';
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  computer == null
                      ? 'No computer selected · fallback now uses $modifier.'
                      : 'Current computer: $currentSystem · Primary uses $modifier.',
                  key: const ValueKey('current-computer-shortcut-system'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              );
            },
          ),
          RadioGroup<ShortcutPlatform>(
            groupValue: preferences.shortcutPlatform,
            onChanged: (value) {
              if (value != null) controller.updateShortcutPlatform(value);
            },
            child: Column(
              children: ShortcutPlatform.values
                  .map(
                    (platform) => RadioListTile<ShortcutPlatform>(
                      title: Text(_shortcutPlatformTitle(platform)),
                      subtitle: Text(
                        _shortcutPlatformSubtitle(platform, controller),
                      ),
                      value: platform,
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
        if (isLite && !isIosDesktop) ...[
          const Divider(),
          const _SectionLabel('CONTROL SURFACE', '控制面板'),
          RadioGroup<ControlSurfaceLayout>(
            groupValue: preferences.controlSurfaceLayout,
            onChanged: (value) {
              if (value != null) controller.updateControlSurfaceLayout(value);
            },
            child: Column(
              children: ControlSurfaceLayout.values
                  .map(
                    (layout) => RadioListTile<ControlSurfaceLayout>(
                      title: Text(_controlSurfaceLayoutTitle(layout)),
                      subtitle: Text(_controlSurfaceLayoutSubtitle(layout)),
                      value: layout,
                    ),
                  )
                  .toList(),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.grid_view_outlined),
            title: const MobileText(
              'Shortcut board keys per screen',
              '每屏快捷按键数',
            ),
            trailing: DropdownButton<int>(
              key: const ValueKey('tablet-keys-per-page'),
              value: preferences.tabletKeysPerPage,
              items: [
                for (
                  var count = minTabletKeysPerPage;
                  count <= maxTabletKeysPerPage;
                  count++
                )
                  DropdownMenuItem<int>(
                    value: count,
                    child: Text(
                      count == 40
                          ? '$count (default)'
                          : tabletKeysPerPageOptions.contains(count)
                          ? '$count (preset)'
                          : '$count',
                    ),
                  ),
              ],
              onChanged: (value) {
                if (value != null) controller.updateTabletKeysPerPage(value);
              },
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.dashboard_customize_outlined),
            title: const MobileText('Profiles', '快捷键配置'),
            subtitle: Text(
              '${controller.config.profiles.length}/$freeProfileLimit profiles · manual switching',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const ProfileManagementScreen(),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.groups_outlined),
            title: const MobileText('Shortcut Community', '快捷键社区'),
            subtitle: const MobileText(
              'Import, replace, copy, and export Profile JSON',
              '导入、替换、复制和导出配置 JSON',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const ShortcutCommunityScreen(),
              ),
            ),
          ),
        ],
        if (!isLite)
          ListTile(
            key: const ValueKey('open-desktop-installers'),
            leading: const Icon(Icons.install_desktop_outlined),
            title: const MobileText('Desktop installers', '桌面安装包'),
            subtitle: const MobileText(
              'Verify and export bundled Windows and macOS installers',
              '验证和导出内置的 Windows 和 macOS 安装包',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const DesktopInstallersScreen(),
              ),
            ),
          ),
        const Divider(),
        const _SectionLabel('DICTATION', '听写'),
        const DictationStartupSetting(),
        const Divider(),
        const _SectionLabel('CHARGING DISPLAY', '充电时的屏幕设置'),
        RadioGroup<ChargingBrightnessMode>(
          groupValue: preferences.chargingBrightnessMode,
          onChanged: (value) {
            if (value != null) {
              controller.updateChargingBrightness(mode: value);
            }
          },
          child: const Column(
            children: [
              RadioListTile<ChargingBrightnessMode>(
                value: ChargingBrightnessMode.fixed,
                title: MobileText('Fixed while charging', '充电时固定亮度'),
                subtitle: MobileText(
                  'Keep the app at the selected brightness when power is connected',
                  '连接电源时使用选定的屏幕亮度',
                ),
              ),
              RadioListTile<ChargingBrightnessMode>(
                value: ChargingBrightnessMode.dynamic,
                title: MobileText('Dynamic / system controlled', '由系统动态调节'),
                subtitle: MobileText(
                  'Follow Android and compatible eye or presence tracking features',
                  '跟随 Android 及兼容的视线或在场检测功能',
                ),
              ),
            ],
          ),
        ),
        if (preferences.chargingBrightnessMode == ChargingBrightnessMode.fixed)
          ListTile(
            leading: const Icon(Icons.brightness_6_outlined),
            title: Text(
              context.mobileText(
                'Charging brightness ${(preferences.chargingBrightness * 100).round()}%',
                '充电时的亮度 ${(preferences.chargingBrightness * 100).round()}%',
              ),
            ),
            subtitle: Slider(
              key: const ValueKey('charging-brightness-slider'),
              value: preferences.chargingBrightness,
              min: 0.1,
              max: 1,
              divisions: 18,
              label: '${(preferences.chargingBrightness * 100).round()}%',
              onChanged: (value) =>
                  controller.updateChargingBrightness(brightness: value),
            ),
          ),
        SwitchListTile(
          secondary: const Icon(Icons.screen_lock_portrait_outlined),
          title: const MobileText(
            'Keep screen awake while charging',
            '充电时保持屏幕常亮',
          ),
          subtitle: const MobileText(
            'Prevent automatic screen timeout while external power is connected',
            '连接外部电源时防止屏幕自动熄灭',
          ),
          value: preferences.keepScreenOnWhileCharging,
          onChanged: (value) =>
              controller.updateChargingBrightness(keepScreenOn: value),
        ),
        const Divider(),
        const _SectionLabel('FEEDBACK', '操作反馈'),
        SwitchListTile(
          secondary: const Icon(Icons.vibration),
          title: const MobileText('Haptic feedback', '触觉反馈'),
          value: preferences.hapticEnabled,
          onChanged: (value) =>
              controller.updateFeedbackPreferences(hapticEnabled: value),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.volume_up_outlined),
          title: const MobileText('Sound feedback', '声音反馈'),
          value: preferences.soundEnabled,
          onChanged: (value) =>
              controller.updateFeedbackPreferences(soundEnabled: value),
        ),
        const Divider(),
        const _SectionLabel('COMMUNITY', '社区'),
        ListTile(
          key: const ValueKey('open-community-setup'),
          leading: const Icon(Icons.tune),
          title: const MobileText('Community sharing setup', '社区分享设置'),
          subtitle: const MobileText(
            'Optional profession and computer proficiency for reviewed batches',
            '可选填职业和电脑熟练程度，供分享内容审核参考',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => CommunitySetupScreen(
                repository: CommunitySetupRepository(),
                isReopen: true,
              ),
            ),
          ),
        ),
        const Divider(),
        const _SectionLabel('SHORTCUT USAGE', '快捷键使用情况'),
        _ShortcutUsageSection(controller: controller),
        const Divider(),
        if (isLite) const _SectionLabel('BUILT-IN TEMPLATES', '内置模板'),
        if (isLite)
          ListTile(
            leading: const Icon(Icons.restore),
            title: const MobileText('Restore all default profiles', '恢复所有默认配置'),
            subtitle: const MobileText(
              'Restores General, ChatGPT, and Chrome',
              '恢复常规、ChatGPT 和 Chrome 配置',
            ),
            onTap: () => _confirmRestore(context),
          ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline),
                  const SizedBox(width: 12),
                  Expanded(
                    child: !isLite
                        ? const MobileText(
                            'LumiaKey sends shortcuts and pointer controls to '
                                'LumiaKey Desktop over Wi-Fi; speech recognition '
                                'stays on this device.',
                            'LumiaKey 通过 Wi-Fi 向 LumiaKey Desktop 发送快捷键和指针操作，'
                                '语音识别在本设备上进行。',
                            key: ValueKey('ipad-desktop-keyboard-explanation'),
                          )
                        : const MobileText(
                            'LumiaKey Lite sends Bluetooth keyboard and mouse '
                                'input directly to your computer. Open the target '
                                'app yourself and configure its shortcuts here.',
                            'LumiaKey Lite 通过蓝牙直接向电脑发送键盘和鼠标操作。'
                                '请自行打开目标应用，并在这里设置它的快捷键。',
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
    if (embedded) return SafeArea(child: content);
    return Scaffold(
      appBar: AppBar(title: const MobileText('Settings', '设置')),
      body: content,
    );
  }

  static String _controlSurfaceLayoutTitle(ControlSurfaceLayout layout) =>
      switch (layout) {
        ControlSurfaceLayout.automatic => 'Automatic',
        ControlSurfaceLayout.phone => 'Phone controls',
        ControlSurfaceLayout.shortcutBoard => 'Shortcut board',
      };

  static String _controlSurfaceLayoutSubtitle(ControlSurfaceLayout layout) =>
      switch (layout) {
        ControlSurfaceLayout.automatic =>
          'Use the shortcut board when the window is tablet sized',
        ControlSurfaceLayout.phone => 'Use the existing phone controls',
        ControlSurfaceLayout.shortcutBoard =>
          'Use the full-screen keyboard-only board',
      };

  static String _shortcutPlatformTitle(ShortcutPlatform platform) =>
      switch (platform) {
        ShortcutPlatform.automatic => 'Automatic',
        ShortcutPlatform.apple => 'Apple',
        ShortcutPlatform.windowsLinux => 'Windows / Linux',
      };

  static String _shortcutPlatformSubtitle(
    ShortcutPlatform platform,
    AppController controller,
  ) => switch (platform) {
    ShortcutPlatform.automatic =>
      controller.hid.activeHost.value == null
          ? 'Use the active OS when available; otherwise use a best-effort computer-name hint.'
          : '${controller.primaryShortcutLabel} fallback for ${controller.hid.activeHost.value!.name}; saved OS wins.',
    ShortcutPlatform.apple =>
      'Command (⌘) fallback when this computer has no saved OS.',
    ShortcutPlatform.windowsLinux =>
      'Ctrl fallback when this computer has no saved OS.',
  };

  Future<void> _confirmRestore(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const MobileText('Restore default profiles?', '恢复默认配置？'),
        content: const MobileText(
          'Your local shortcuts will be replaced with General, ChatGPT, and Chrome.',
          '你的本地快捷键将被常规、ChatGPT 和 Chrome 的默认快捷键替换。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const MobileText('Cancel', '取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const MobileText('Restore', '恢复'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await SmartKeysScope.of(context).restoreAllTemplates();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: MobileText('Default profiles restored', '已恢复默认配置'),
        ),
      );
    }
  }
}

class _AppearanceSettings extends StatelessWidget {
  const _AppearanceSettings({required this.appearance});

  final MobileAppearance appearance;

  Future<void> _save(BuildContext context, Future<void> operation) async {
    try {
      await operation;
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: MobileText('Could not save this setting.', '无法保存此设置。'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      const _SectionLabel('APPEARANCE', '外观'),
      ListTile(
        leading: const Icon(Icons.language),
        title: const MobileText('Language', '语言'),
        trailing: DropdownButton<MobileLanguage>(
          key: const ValueKey('mobile-language-selector'),
          value: appearance.language,
          items: [
            for (final language in MobileLanguage.values)
              DropdownMenuItem(value: language, child: Text(language.label)),
          ],
          onChanged: appearance.ready
              ? (value) {
                  if (value != null) {
                    _save(context, appearance.setLanguage(value));
                  }
                }
              : null,
        ),
      ),
      ListTile(
        leading: const Icon(Icons.palette_outlined),
        title: const MobileText('Theme', '主题'),
        trailing: DropdownButton<ThemeMode>(
          key: const ValueKey('mobile-theme-selector'),
          value: appearance.themeMode,
          items: const [
            DropdownMenuItem(
              value: ThemeMode.system,
              child: MobileText('Follow system', '跟随系统'),
            ),
            DropdownMenuItem(
              value: ThemeMode.light,
              child: MobileText('Light', '浅色'),
            ),
            DropdownMenuItem(
              value: ThemeMode.dark,
              child: MobileText('Dark', '深色'),
            ),
          ],
          onChanged: appearance.ready
              ? (value) {
                  if (value != null) {
                    _save(context, appearance.setThemeMode(value));
                  }
                }
              : null,
        ),
      ),
    ],
  );
}

class _ShortcutUsageSection extends StatelessWidget {
  const _ShortcutUsageSection({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller.shortcutUsage,
    builder: (context, _) {
      final records = controller.shortcutUsage.records;
      final mostUsed = records.isEmpty ? null : records.first;
      final leastUsed = records.isEmpty ? null : records.last;
      return Column(
        children: [
          const ListTile(
            leading: Icon(Icons.privacy_tip_outlined),
            title: MobileText('Private, on-device data', '本机私密数据'),
            subtitle: MobileText(
              'Usage stays on this device unless you opt in to share aggregate counts.',
              '除非你选择分享汇总次数，使用记录仅保存在本设备。',
            ),
          ),
          if (mostUsed == null)
            const ListTile(
              leading: Icon(Icons.bar_chart_outlined),
              title: MobileText('No usage recorded yet', '暂无使用记录'),
              subtitle: MobileText(
                'Counts appear here after you use shortcuts.',
                '使用快捷键后，这里会显示次数。',
              ),
            )
          else ...[
            ListTile(
              leading: const Icon(Icons.trending_up),
              title: const MobileText('Most used', '最常使用'),
              subtitle: Text(mostUsed.label),
              trailing: Text('${mostUsed.count}×'),
            ),
            ListTile(
              leading: const Icon(Icons.trending_down),
              title: const MobileText('Least used', '最少使用'),
              subtitle: Text(leastUsed!.label),
              trailing: Text('${leastUsed.count}×'),
            ),
          ],
          ListTile(
            key: const ValueKey('open-usage-dashboard'),
            leading: const Icon(Icons.query_stats_outlined),
            title: const MobileText('Usage Dashboard', '使用统计'),
            subtitle: const MobileText(
              'Filter history, sort shortcuts, and manage optional sharing',
              '筛选历史记录、排列快捷键，以及管理分享选项',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const UsageDashboardScreen(),
              ),
            ),
          ),
        ],
      );
    },
  );
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text, this.translation);

  final String text;
  final String translation;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Text(
        context.mobileText(text, translation),
        style: TextStyle(
          color: Theme.of(context).colorScheme.primary,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}
