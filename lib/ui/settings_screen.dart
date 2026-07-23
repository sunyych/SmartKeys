import 'package:flutter/material.dart';

import '../app.dart';
import '../controllers/app_controller.dart';
import '../models/config.dart';
import 'bluetooth_connection_sheet.dart';
import 'profile_management_screen.dart';
import 'shortcut_community_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final controller = SmartKeysScope.of(context);
    final preferences = controller.config.preferences;
    final content = ListView(
      key: embedded ? const ValueKey('embedded-settings') : null,
      children: [
        const _SectionLabel('BLUETOOTH HID'),
        ValueListenableBuilder(
          valueListenable: controller.hid.connectionStatus,
          builder: (context, status, _) => ListTile(
            leading: const Icon(Icons.bluetooth),
            title: const Text('Computer connection'),
            subtitle: Text(status.name),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showBluetoothConnectionSheet(context, controller.hid),
          ),
        ),
        const Divider(),
        const _SectionLabel('DESKTOP COMPANION'),
        ValueListenableBuilder(
          valueListenable: controller.companion.activeHost,
          builder: (context, host, _) => ListTile(
            leading: Icon(
              host == null ? Icons.desktop_access_disabled : Icons.computer,
            ),
            title: Text(host == null ? 'Looking for desktop…' : host.name),
            subtitle: Text(
              host == null
                  ? 'Open LumiaKeys Desktop on the same local network'
                  : host.supportsManifest
                  ? '${host.platform} · Desktop layout revision ${controller.desktopManifest?.revision ?? 'syncing'}'
                  : '${host.platform} · legacy actions only',
            ),
            trailing: host == null
                ? const Icon(Icons.search)
                : const Icon(Icons.check_circle, color: Colors.green),
          ),
        ),
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
        const Padding(
          padding: EdgeInsets.all(16),
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Bluetooth and Desktop use the same control surface. '
                      'Desktop only supplies installed apps and dynamic app '
                      'shortcuts; your phone Profiles remain available.',
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
              'Shortcut usage never leaves this phone. It is never sent to '
              'LumiaKeys Desktop, the cloud, or Profile exports.',
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
            leading: const Icon(Icons.low_priority),
            title: const Text('Reorder current Profile by usage'),
            subtitle: Text(
              'Put frequently used ${controller.activeProfile.name} shortcuts first',
            ),
            trailing: const Icon(Icons.chevron_right),
            enabled: records.isNotEmpty,
            onTap: records.isEmpty
                ? null
                : () async {
                    await controller.reorderActiveProfileByUsage();
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Current Profile reordered by usage'),
                      ),
                    );
                  },
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('Clear usage data'),
            enabled: records.isNotEmpty,
            onTap: records.isEmpty ? null : () => _confirmClear(context),
          ),
        ],
      );
    },
  );

  Future<void> _confirmClear(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear shortcut usage?'),
        content: const Text(
          'This permanently removes the private usage counters stored on this phone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed == true) await controller.shortcutUsage.clear();
  }
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
