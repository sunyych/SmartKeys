import 'package:flutter/material.dart';

import '../app.dart';
import '../controllers/app_controller.dart';
import '../data/community_setup_repository.dart';
import '../models/config.dart';
import '../services/ios_companion_hid_service.dart';
import 'bluetooth_connection_sheet.dart';
import 'profile_management_screen.dart';
import 'shortcut_community_screen.dart';
import 'desktop_installers_screen.dart';
import 'desktop_connection_panel.dart';
import 'usage_dashboard_screen.dart';
import 'account_backup_screen.dart';
import 'community_setup_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final controller = SmartKeysScope.of(context);
    final preferences = controller.config.preferences;
    final isIosDesktop = controller.hid is IosCompanionHidService;
    final content = ListView(
      key: ValueKey(embedded ? 'embedded-settings' : 'settings-list'),
      children: [
        if (!isIosDesktop) ...[
          const _SectionLabel('BLUETOOTH HID'),
          ValueListenableBuilder(
            valueListenable: controller.hid.connectionStatus,
            builder: (context, status, _) => ListTile(
              leading: const Icon(Icons.bluetooth),
              title: const Text('Computer connection'),
              subtitle: Text(status.name),
              trailing: const Icon(Icons.chevron_right),
              onTap: () =>
                  showBluetoothConnectionSheet(context, controller.hid),
            ),
          ),
          const Divider(),
        ],
        const _SectionLabel('DESKTOP COMPANION'),
        DesktopConnectionPanel(companion: controller.companion),
        const Divider(),
        const _SectionLabel('SHORTCUT PLATFORM'),
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
        const Divider(),
        const _SectionLabel('CONTROL SURFACE'),
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
          title: const Text('Shortcut board keys per screen'),
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
          title: const Text('Profiles'),
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
          title: const Text('Shortcut Community'),
          subtitle: const Text(
            'Import, replace, copy, and export Profile JSON',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const ShortcutCommunityScreen(),
            ),
          ),
        ),
        ListTile(
          key: const ValueKey('open-desktop-installers'),
          leading: const Icon(Icons.install_desktop_outlined),
          title: const Text('Desktop installers'),
          subtitle: const Text(
            'Verify and export bundled Windows and macOS installers',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const DesktopInstallersScreen(),
            ),
          ),
        ),
        const Divider(),
        const _SectionLabel('SCREEN ORIENTATION'),
        RadioGroup<OrientationMode>(
          groupValue: preferences.orientationMode,
          onChanged: (value) {
            if (value != null) controller.updateOrientationMode(value);
          },
          child: Column(
            children: OrientationMode.values
                .map(
                  (mode) => RadioListTile<OrientationMode>(
                    title: Text(_orientationTitle(mode)),
                    subtitle: Text(_orientationSubtitle(mode)),
                    value: mode,
                  ),
                )
                .toList(),
          ),
        ),
        const Divider(),
        const _SectionLabel('CHARGING DISPLAY'),
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
                title: Text('Fixed while charging'),
                subtitle: Text(
                  'Keep the app at the selected brightness when power is connected',
                ),
              ),
              RadioListTile<ChargingBrightnessMode>(
                value: ChargingBrightnessMode.dynamic,
                title: Text('Dynamic / system controlled'),
                subtitle: Text(
                  'Follow Android and compatible eye or presence tracking features',
                ),
              ),
            ],
          ),
        ),
        if (preferences.chargingBrightnessMode == ChargingBrightnessMode.fixed)
          ListTile(
            leading: const Icon(Icons.brightness_6_outlined),
            title: Text(
              'Charging brightness ${(preferences.chargingBrightness * 100).round()}%',
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
          title: const Text('Keep screen awake while charging'),
          subtitle: const Text(
            'Prevent automatic screen timeout while external power is connected',
          ),
          value: preferences.keepScreenOnWhileCharging,
          onChanged: (value) =>
              controller.updateChargingBrightness(keepScreenOn: value),
        ),
        const Divider(),
        const _SectionLabel('FEEDBACK'),
        SwitchListTile(
          secondary: const Icon(Icons.vibration),
          title: const Text('Haptic feedback'),
          value: preferences.hapticEnabled,
          onChanged: (value) =>
              controller.updateFeedbackPreferences(hapticEnabled: value),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.volume_up_outlined),
          title: const Text('Sound feedback'),
          value: preferences.soundEnabled,
          onChanged: (value) =>
              controller.updateFeedbackPreferences(soundEnabled: value),
        ),
        const Divider(),
        const _SectionLabel('COMMUNITY'),
        ListTile(
          key: const ValueKey('open-community-setup'),
          leading: const Icon(Icons.tune),
          title: const Text('Community sharing setup'),
          subtitle: const Text(
            'Optional profession and computer proficiency for reviewed batches',
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
        const _SectionLabel('SHORTCUT USAGE'),
        _ShortcutUsageSection(controller: controller),
        const Divider(),
        const _SectionLabel('BUILT-IN TEMPLATES'),
        ListTile(
          leading: const Icon(Icons.restore),
          title: const Text('Restore all default profiles'),
          subtitle: const Text(
            'Restores General, Web, Zoom / Teams, and Custom',
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
                    child: isIosDesktop
                        ? const Text(
                            'iPad sends supported keyboard shortcuts to '
                            'LumiaKey Desktop over Wi-Fi; speech recognition '
                            'stays on this device.',
                            key: ValueKey('ipad-desktop-keyboard-explanation'),
                          )
                        : const Text(
                            'Bluetooth and Desktop use the same control '
                            'surface. Desktop provides installed apps and '
                            'dynamic app shortcuts; your phone Profiles '
                            'remain available.',
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
      appBar: AppBar(title: const Text('Settings')),
      body: content,
    );
  }

  static String _orientationTitle(OrientationMode mode) => switch (mode) {
    OrientationMode.auto => 'Auto',
    OrientationMode.portrait => 'Portrait',
    OrientationMode.landscape => 'Landscape',
  };

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

  static String _orientationSubtitle(OrientationMode mode) => switch (mode) {
    OrientationMode.auto => 'Follow the physical device orientation',
    OrientationMode.portrait => 'Lock to portrait',
    OrientationMode.landscape => 'Allow landscape left and landscape right',
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
          ? 'Detect from the connected computer name; Ctrl until connected'
          : '${controller.primaryShortcutLabel} for ${controller.hid.activeHost.value!.name}',
    ShortcutPlatform.apple => 'PRIMARY sends Command (⌘)',
    ShortcutPlatform.windowsLinux => 'PRIMARY sends Ctrl',
  };

  Future<void> _confirmRestore(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restore default profiles?'),
        content: const Text(
          'All four Profile slots will return to General, Web, Zoom / Teams, and Custom.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await SmartKeysScope.of(context).restoreAllTemplates();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Default profiles restored')),
      );
    }
  }
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
            title: Text('Private, on-device data'),
            subtitle: Text(
              'Usage stays on this device unless you opt in to share aggregate counts.',
            ),
          ),
          if (mostUsed == null)
            const ListTile(
              leading: Icon(Icons.bar_chart_outlined),
              title: Text('No usage recorded yet'),
              subtitle: Text('Counts appear here after you use shortcuts.'),
            )
          else ...[
            ListTile(
              leading: const Icon(Icons.trending_up),
              title: const Text('Most used'),
              subtitle: Text(mostUsed.label),
              trailing: Text('${mostUsed.count}×'),
            ),
            ListTile(
              leading: const Icon(Icons.trending_down),
              title: const Text('Least used'),
              subtitle: Text(leastUsed!.label),
              trailing: Text('${leastUsed.count}×'),
            ),
          ],
          ListTile(
            key: const ValueKey('open-usage-dashboard'),
            leading: const Icon(Icons.query_stats_outlined),
            title: const Text('Usage Dashboard'),
            subtitle: const Text(
              'Filter history, sort shortcuts, and manage optional sharing',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const UsageDashboardScreen(),
              ),
            ),
          ),
          ListTile(
            key: const ValueKey('open-account-backup'),
            leading: const Icon(Icons.cloud_outlined),
            title: const Text('Google Drive backup'),
            subtitle: const Text('Back up and restore your profiles'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const AccountBackupScreen(),
              ),
            ),
          ),
        ],
      );
    },
  );
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Text(
        text,
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
