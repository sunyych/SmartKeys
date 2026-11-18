import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:flutter/services.dart';
import 'package:local_dictation/local_dictation.dart';
import 'package:lumiakeys_protocol/lumiakeys_protocol.dart';

import 'companion_server.dart';
import 'desktop_controller.dart';
import 'desktop_application_artwork.dart';
import 'installed_app_picker.dart';
import 'app_icon_service.dart';
import 'desktop_dictation.dart';
import 'shortcut_transfer_service.dart';
import 'tray_shell.dart' show desktopBrandAsset;

class DesktopSettingsHome extends StatelessWidget {
  const DesktopSettingsHome({
    super.key,
    required this.controller,
    required this.server,
    required this.dictation,
    this.displayHost,
  });

  final DesktopController controller;
  final CompanionServer server;
  final DesktopDictationService dictation;
  final String? displayHost;

  static const sections = [
    (Icons.tune, 'General'),
    (Icons.bluetooth, 'Bluetooth'),
    (Icons.dashboard_customize_outlined, 'Shortcut Layout'),
    (Icons.apps, 'Apps'),
    (Icons.layers_outlined, 'Profiles'),
    (Icons.info_outline, 'About'),
    (Icons.mic, 'Local Dictation'),
    (Icons.rocket_launch_outlined, 'Launcher'),
  ];

  @override
  Widget build(BuildContext context) {
    if (controller.loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final extendedNavigation = MediaQuery.sizeOf(context).width >= 920;
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            scrollable: true,
            extended: extendedNavigation,
            selectedIndex: controller.selectedSection,
            onDestinationSelected: controller.selectSection,
            leading: Padding(
              padding: const EdgeInsets.only(top: 16, bottom: 20),
              child: _BrandLogo(extended: extendedNavigation),
            ),
            destinations: sections
                .map(
                  (section) => NavigationRailDestination(
                    icon: Icon(section.$1),
                    label: Text(section.$2),
                  ),
                )
                .toList(growable: false),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: Column(
              children: [
                _TitleBar(title: sections[controller.selectedSection].$2),
                if (controller.error != null)
                  MaterialBanner(
                    content: Text(controller.error!),
                    actions: [
                      TextButton(
                        onPressed: controller.refreshApplications,
                        child: const Text('Retry'),
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
    ),
    1 => _BluetoothPage(
      controller: controller,
      server: server,
      displayHost: displayHost,
    ),
    2 => _ShortcutLayoutsPage(controller: controller),
    3 => _AppsPage(controller: controller),
    4 => _ProfilesPage(controller: controller),
    5 => const _AboutPage(),
    6 => _LocalDictationPage(dictation: dictation),
    _ => _LauncherPage(controller: controller),
  };
}

class _DesktopStatusBar extends StatelessWidget {
  const _DesktopStatusBar({required this.controller, required this.server});

  final DesktopController controller;
  final CompanionServer server;

  @override
  Widget build(BuildContext context) {
    final foreground = controller.foregroundApplication;
    return Container(
      key: const ValueKey('desktop-status-bar'),
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Colors.black12)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _DesktopStatusItem(
              icon: server.running ? Icons.sync : Icons.sync_problem,
              label: server.running ? 'Desktop ready' : 'Desktop offline',
              active: server.running,
            ),
          ),
          const VerticalDivider(indent: 8, endIndent: 8),
          Expanded(
            child: _DesktopStatusItem(
              icon: Icons.phone_android,
              label: controller.connectedPhone == null
                  ? 'Waiting for phone'
                  : 'Phone connected',
              active: controller.connectedPhone != null,
            ),
          ),
          const VerticalDivider(indent: 8, endIndent: 8),
          Expanded(
            child: _DesktopStatusItem(
              icon: Icons.center_focus_strong,
              label: foreground?.name ?? 'No mapped foreground app',
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
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: Colors.black12)),
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
          semanticLabel: 'LumiaKey logo',
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
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
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
  });

  final DesktopController controller;
  final CompanionServer server;
  final String? displayHost;

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
        const SizedBox(height: 24),
        Text('Synchronization', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Card(
          child: Column(
            children: [
              SwitchListTile(
                title: const Text('Enable Apps Sync'),
                subtitle: const Text(
                  'Publish managed apps and their layouts to Android',
                ),
                value: settings.enableAppsSync,
                onChanged: (value) => controller.updateSettings(
                  settings.copyWith(enableAppsSync: value),
                ),
              ),
              const Divider(height: 1),
              SwitchListTile(
                title: const Text('Auto Launch Apps'),
                subtitle: const Text(
                  'Allow phone app cards to launch configured desktop apps',
                ),
                value: settings.autoLaunchApps,
                onChanged: (value) => controller.updateSettings(
                  settings.copyWith(autoLaunchApps: value),
                ),
              ),
              const Divider(height: 1),
              SwitchListTile(
                title: const Text('Sync Icons'),
                subtitle: const Text(
                  'Include semantic icon identifiers in the phone manifest',
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
        Text('Current state', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.phone_android),
                title: const Text('Current Connected Phone'),
                subtitle: Text(
                  controller.connectedPhone ?? 'No phone connected',
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.layers_outlined),
                title: const Text('Current Shortcut Profile'),
                subtitle: Text(profile?.name ?? 'Unavailable'),
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
          ? Theme.of(
              context,
            ).colorScheme.primaryContainer.withValues(alpha: 0.45)
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
                        ? 'LumiaKey Desktop is ready'
                        : 'Sync service unavailable',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$platform · ${displayHost ?? Platform.localHostname} · revision ${controller.manifest.revision}',
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

class _BluetoothPage extends StatelessWidget {
  const _BluetoothPage({
    required this.controller,
    required this.server,
    required this.displayHost,
  });

  final DesktopController controller;
  final CompanionServer server;
  final String? displayHost;

  @override
  Widget build(BuildContext context) => _PageBody(
    children: [
      _StatusCard(
        controller: controller,
        server: server,
        displayHost: displayHost,
      ),
      const SizedBox(height: 24),
      _TabletPairingCard(server: server),
      const SizedBox(height: 24),
      Card(
        child: Column(
          children: [
            const ListTile(
              leading: Icon(Icons.bluetooth_connected),
              title: Text('Bluetooth HID'),
              subtitle: Text(
                'The Android phone pairs directly with this computer for keyboard and mouse input.',
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.sync),
              title: const Text('Desktop layout sync'),
              subtitle: Text(
                server.running
                    ? 'Authenticated local channel active on port ${server.actionPort ?? 'starting'}'
                    : server.error ?? 'Not running',
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.phone_android),
              title: const Text('Current Connected Phone'),
              subtitle: Text(
                controller.connectedPhone ?? 'Waiting for LumiaKey Android',
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      const Text(
        'Bluetooth HID remains the input path. V1.2 layout data uses the authenticated companion channel so the desktop can send structured layouts and icons back to Android.',
      ),
    ],
  );
}

class _TabletPairingCard extends StatefulWidget {
  const _TabletPairingCard({required this.server});
  final CompanionServer server;

  @override
  State<_TabletPairingCard> createState() => _TabletPairingCardState();
}

class _TabletPairingCardState extends State<_TabletPairingCard> {
  List<String> _addresses = const [];
  String? _selectedAddress;

  @override
  void initState() {
    super.initState();
    unawaited(_loadAddresses());
  }

  Future<void> _loadAddresses() async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      final values =
          interfaces
              .expand((interface) => interface.addresses)
              .where(_isPrivateIpv4)
              .map((address) => address.address)
              .toSet()
              .toList()
            ..sort();
      if (mounted) {
        setState(() {
          _addresses = values;
          if (!_addresses.contains(_selectedAddress)) {
            _selectedAddress = values.isEmpty ? null : values.first;
          }
        });
      }
    } on SocketException {
      if (mounted) setState(() => _addresses = const []);
    }
  }

  bool _isPrivateIpv4(InternetAddress address) {
    final bytes = address.rawAddress;
    return bytes[0] == 10 ||
        (bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31) ||
        (bytes[0] == 192 && bytes[1] == 168);
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Connect an iPhone, iPad, or Android device',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          const Text(
            'Join the same Wi-Fi, then scan this code in LumiaKey or paste the private connection code manually.',
          ),
          const SizedBox(height: 12),
          if (_addresses.isEmpty)
            const Text('No private IPv4 address is available.')
          else ...[
            DropdownButtonFormField<String>(
              initialValue: _addresses.contains(_selectedAddress)
                  ? _selectedAddress
                  : null,
              decoration: const InputDecoration(
                labelText: 'Desktop network address',
              ),
              items: _addresses
                  .map(
                    (address) =>
                        DropdownMenuItem(value: address, child: Text(address)),
                  )
                  .toList(growable: false),
              onChanged: (address) =>
                  setState(() => _selectedAddress = address),
            ),
            const SizedBox(height: 4),
            Text(
              'Choose the Wi-Fi address reachable by your iPhone or iPad. Avoid VPN or virtual adapter addresses.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (_addresses.contains(_selectedAddress) &&
              widget.server.running &&
              widget.server.actionPort != null) ...[
            const SizedBox(height: 12),
            DesktopPairingQr(
              code: desktopPairingCode(
                _selectedAddress!,
                widget.server.actionPort!,
                widget.server.token,
              ),
            ),
          ] else ...[
            const SizedBox(height: 12),
            const Text('Start LumiaKey Desktop to generate a pairing code.'),
          ],
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed:
                !widget.server.running ||
                    widget.server.actionPort == null ||
                    !_addresses.contains(_selectedAddress)
                ? null
                : () async {
                    final address = _selectedAddress;
                    if (address == null) return;
                    final code = desktopPairingCode(
                      address,
                      widget.server.actionPort!,
                      widget.server.token,
                    );
                    await Clipboard.setData(ClipboardData(text: code));
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Private connection code copied. Treat it like a password.',
                        ),
                      ),
                    );
                  },
            icon: const Icon(Icons.copy),
            label: const Text('Copy connection code'),
          ),
        ],
      ),
    ),
  );
}

String desktopPairingCode(String address, int port, String token) =>
    '$address:$port $token';

class DesktopPairingQr extends StatelessWidget {
  const DesktopPairingQr({super.key, required this.code});

  final String code;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Scan with LumiaKey on your phone'),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final qrSize = constraints.maxWidth.isFinite
                  ? (constraints.maxWidth - 32).clamp(0.0, 220.0)
                  : 220.0;
              return DecoratedBox(
                decoration: const BoxDecoration(color: Colors.white),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: QrImageView(
                    data: code,
                    size: qrSize,
                    padding: const EdgeInsets.all(16),
                    backgroundColor: Colors.white,
                    errorCorrectionLevel: QrErrorCorrectLevel.M,
                    semanticsLabel: 'Private LumiaKey Desktop pairing QR code',
                  ),
                ),
              );
            },
          ),
        ],
      ),
    ),
  );
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
                  decoration: const InputDecoration(
                    labelText: 'Shortcut Layout',
                  ),
                  items: layouts
                      .map(
                        (layout) => DropdownMenuItem(
                          value: layout.id,
                          child: Text(
                            '${layout.name} · ${layout.kind.name}',
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
              Chip(label: Text('${selected.buttons.length} buttons')),
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
                label: const Text('Import JSON'),
              ),
              OutlinedButton.icon(
                key: const ValueKey('desktop-export-shortcuts-json'),
                onPressed: transferring ? null : _exportJson,
                icon: const Icon(Icons.ios_share_outlined),
                label: const Text('Export JSON'),
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
                                button.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 3),
                              Text(
                                _buttonSummary(button),
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
      if (mounted) _showTransferMessage('Shortcut JSON imported');
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
        _showTransferMessage('Shortcut JSON exported');
      }
    } catch (error) {
      if (mounted) _showTransferMessage('$error');
    } finally {
      if (mounted) setState(() => transferring = false);
    }
  }

  void _showTransferMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _editButton(
    BuildContext context,
    RemoteShortcutLayout layout,
    RemoteShortcutButton button,
  ) async {
    if (button.targetType == RemoteTargetType.system ||
        button.id.endsWith('.deleteToStart')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This Desktop action has a fixed, guarded behavior.'),
        ),
      );
      return;
    }
    final updated = await showRemoteButtonEditor(
      context,
      button: button,
      applications: widget.controller.applicationsForCurrentPlatform,
    );
    if (updated != null) {
      await widget.controller.updateButton(layout.id, updated);
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
              'Managed Applications',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          OutlinedButton.icon(
            onPressed: controller.refreshApplications,
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh installed apps'),
          ),
        ],
      ),
      const SizedBox(height: 8),
      const Text(
        'Manage shortcut-enabled applications here. Choose all installed launch-only applications in Launchpad.',
      ),
      const SizedBox(height: 18),
      ...controller.applicationsForCurrentPlatform.map(
        (app) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Card(
            child: ListTile(
              leading: CircleAvatar(child: Icon(desktopIcon(app.icon))),
              title: Text(app.name),
              subtitle: Text(
                '${app.executable} · ${app.detected ? 'Detected' : 'Not detected'}',
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
                    label: Text(app.detected ? 'Installed' : 'Configured'),
                  ),
                  IconButton(
                    tooltip: 'Edit app',
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
  const _LauncherPage({required this.controller});

  final DesktopController controller;

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
    final date = '${_now.year}年${_now.month}月${_now.day}日';
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
                        '快捷启动台',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '把常用应用放在手边，让每一次开始都更轻松。',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                OutlinedButton.icon(
                  key: const ValueKey('launcher-edit'),
                  onPressed: () => _editKey(0),
                  icon: const Icon(Icons.edit_outlined, size: 17),
                  label: const Text('编辑按键'),
                ),
              ],
            ),
            const SizedBox(height: 18),
            _clockBar(theme, date),
            const SizedBox(height: 22),
            Row(
              children: [
                Text(
                  '我的应用',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '$launcherSlotCount 个快捷按键',
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
            Row(
              children: [
                _SystemActionButton(
                  icon: Icons.play_arrow,
                  label: '播放 / 暂停',
                  onPressed: _busy ? null : _playPause,
                ),
                const SizedBox(width: 10),
                _SystemActionButton(
                  icon: _muted == null
                      ? Icons.help_outline
                      : _muted == true
                      ? Icons.volume_off_outlined
                      : Icons.volume_up_outlined,
                  label: _muted == null
                      ? '静音状态未知'
                      : _muted == true
                      ? '已静音'
                      : '系统静音',
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
                        tooltip: '关闭',
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

  Widget _clockBar(ThemeData theme, String date) => LayoutBuilder(
    builder: (context, constraints) => Container(
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
          Flexible(child: Text('本地时间', style: theme.textTheme.labelLarge)),
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
          if (constraints.maxWidth >= 760) ...[
            const SizedBox(width: 12),
            Text(
              'MAKE SPACE FOR WHAT MATTERS',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.primary,
                letterSpacing: 1.1,
              ),
            ),
          ],
        ],
      ),
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
                    app?.name ?? '添加快捷应用',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    app == null
                        ? '点击配置'
                        : app!.detected
                        ? '点击启动'
                        : '应用不可用 · 绑定已保留',
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
                  tooltip: '编辑按键 ${index + 1}',
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
    title: Text('Edit ${widget.app.name}'),
    content: SizedBox(
      width: 520,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: name,
            decoration: const InputDecoration(labelText: 'Name'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: icon,
            decoration: const InputDecoration(labelText: 'Icon'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: executable,
            decoration: const InputDecoration(
              labelText: 'Executable / Application name',
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            initialValue: widget.app.layoutId,
            readOnly: true,
            decoration: const InputDecoration(labelText: 'Shortcut Layout'),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
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
        child: const Text('Save'),
      ),
    ],
  );
}

class _ProfilesPage extends StatelessWidget {
  const _ProfilesPage({required this.controller});

  final DesktopController controller;

  @override
  Widget build(BuildContext context) => _PageBody(
    children: [
      const Text(
        'Profiles select which desktop-owned layout is active on the phone. Automatic foreground-app switching is reserved for a future release.',
      ),
      const SizedBox(height: 18),
      Card(
        child: RadioGroup<String>(
          groupValue: controller.manifest.currentProfileId,
          onChanged: (value) {
            if (value != null) controller.switchProfile(value);
          },
          child: Column(
            children: controller.manifest.profiles
                .map(
                  (profile) => RadioListTile<String>(
                    value: profile.id,
                    title: Text(profile.name),
                    subtitle: Text(
                      [
                        'Layout: ${controller.manifest.layoutById(profile.layoutId)?.name ?? profile.layoutId}',
                        if (profile.platform != null) profile.platform!,
                        if (profile.applicationId != null)
                          profile.applicationId!,
                      ].join(' · '),
                    ),
                  ),
                )
                .toList(growable: false),
          ),
        ),
      ),
    ],
  );
}

class _AboutPage extends StatelessWidget {
  const _AboutPage();

  @override
  Widget build(BuildContext context) => const _PageBody(
    children: [
      Card(
        child: Padding(
          padding: EdgeInsets.all(28),
          child: Column(
            children: [
              Image(
                key: ValueKey('desktop-about-logo-image'),
                image: AssetImage(desktopBrandAsset),
                width: 80,
                height: 80,
                filterQuality: FilterQuality.high,
                semanticLabel: 'LumiaKey logo',
              ),
              SizedBox(height: 16),
              Text(
                'LumiaKey',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 6),
              Text('Version 1.2'),
              SizedBox(height: 18),
              Text(
                'The desktop-driven shortcut platform for LumiaKey Android. Layouts, app definitions, profiles, icons, and execution logic live on this computer.',
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
}) => showDialog<RemoteShortcutButton>(
  context: context,
  builder: (_) =>
      _RemoteButtonEditor(button: button, applications: applications),
);

class _RemoteButtonEditor extends StatefulWidget {
  const _RemoteButtonEditor({required this.button, required this.applications});

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
    title: Text('Edit ${widget.button.name}'),
    content: SizedBox(
      width: 560,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: 'Button Name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: icon,
              decoration: const InputDecoration(labelText: 'Icon'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<RemoteTargetType>(
              initialValue: type,
              decoration: const InputDecoration(labelText: 'Target Type'),
              items: RemoteTargetType.values
                  .where(
                    (value) =>
                        !widget.button.id.startsWith('vibe.') ||
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
                        '${_targetTypeLabel(value)}${value == RemoteTargetType.macro || value == RemoteTargetType.script
                            ? ' · Future'
                            : value == RemoteTargetType.system
                            ? ' · Fixed'
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
              title: const Text('Enabled'),
              value: enabled,
              onChanged: (value) => setState(() => enabled = value),
            ),
            if (type == RemoteTargetType.keyboardShortcut)
              TextField(
                key: const ValueKey('shortcut-field'),
                controller: shortcut,
                decoration: const InputDecoration(
                  labelText: 'Shortcut',
                  hintText: 'PRIMARY + SHIFT + V',
                  helperText:
                      'PRIMARY becomes Command on macOS and Ctrl on Windows.',
                ),
              )
            else if (type == RemoteTargetType.launchApplication)
              DropdownButtonFormField<String>(
                initialValue:
                    widget.applications.any((app) => app.id == selectedApp)
                    ? selectedApp
                    : null,
                decoration: const InputDecoration(labelText: 'Launch App'),
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
              const ListTile(
                leading: Icon(Icons.schedule),
                title: Text('Reserved for a future LumiaKey release'),
              ),
            const SizedBox(height: 12),
            TextField(
              controller: description,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Description'),
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
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _save, child: const Text('Save')),
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
      setState(() => validationError = 'Complete the required target fields.');
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
          title: const Text('Local Dictation'),
          content: const Text(
            'Local Dictation uses this computer’s microphone and the selected installed model. Audio is processed on this computer and is not saved. Phone dictation sends final text to this computer, never audio. App Voice Input is a separate shortcut that follows the selected application’s own microphone and privacy behavior. The microphone will start only after you continue.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('I understand — continue'),
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
            content: Text(service.error ?? 'Could not start local dictation.'),
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
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            'Private microphone dictation',
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: 6),
          const Text(
            'Recognize speech on this computer and type the final text into the focused external app.',
          ),
          const SizedBox(height: 18),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.graphic_eq, size: 30),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'App Voice Input\nRuns the selected app’s own dictation shortcut.',
                    ),
                  ),
                  const Icon(Icons.arrow_forward),
                  const SizedBox(width: 12),
                  const Icon(Icons.mic, size: 30, color: Color(0xFF008C95)),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Local Dictation\nUses this computer’s microphone and local model.',
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
                      const Expanded(
                        child: Text(
                          'Recognition',
                          style: TextStyle(fontWeight: FontWeight.w600),
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
                                ? 'Model verified and ready for offline use.'
                                : 'Model is not installed. Install or import it explicitly before starting.',
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
                          label: const Text('Download'),
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
                          label: const Text('Import'),
                        ),
                        IconButton(
                          tooltip: 'Delete installed model',
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
                      'Downloading ${progress.fileName} · ${(progress.fraction * 100).round()}%',
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (Platform.isMacOS)
            Card(
              child: ListTile(
                leading: Icon(
                  service.accessibilityGranted
                      ? Icons.check_circle_outline
                      : Icons.accessibility_new,
                ),
                title: Text(
                  service.accessibilityGranted
                      ? 'Accessibility and event permissions are ready'
                      : 'macOS input permission required',
                ),
                subtitle: const Text(
                  'macOS needs Accessibility and event posting permission to type into the focused app.',
                ),
                trailing: Wrap(
                  children: [
                    TextButton(
                      onPressed: service.requestAccessibility,
                      child: const Text('Request'),
                    ),
                    TextButton(
                      onPressed: service.openAccessibilitySettings,
                      child: const Text('Settings'),
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
                        ? 'Listening on this computer'
                        : 'Local microphone is stopped',
                  ),
                  subtitle: Text(
                    service.lastText.isEmpty
                        ? 'Audio stays in bounded memory and is never saved.'
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
                          ? 'Cancel start'
                          : service.listening
                          ? 'Stop'
                          : 'Start local dictation',
                    ),
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
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.keyboard),
                  title: const Text('Global toggle shortcut'),
                  subtitle: Text(
                    service.hotkeyError ??
                        'Ctrl+Shift+Space starts or stops local dictation.',
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

String _targetTypeLabel(RemoteTargetType type) => switch (type) {
  RemoteTargetType.keyboardShortcut => 'Keyboard Shortcut',
  RemoteTargetType.launchApplication => 'Launch Application',
  RemoteTargetType.voiceInput => 'Voice Input',
  RemoteTargetType.openUrl => 'Open URL',
  RemoteTargetType.macro => 'Macro',
  RemoteTargetType.script => 'Script',
  RemoteTargetType.system => 'Desktop System Action',
};

String _buttonSummary(RemoteShortcutButton button) =>
    switch (button.targetType) {
      RemoteTargetType.keyboardShortcut => formatShortcut(button.shortcut),
      RemoteTargetType.launchApplication => 'Launch ${button.target ?? 'app'}',
      RemoteTargetType.voiceInput => 'Start Codex dictation',
      RemoteTargetType.openUrl => button.target ?? 'URL',
      RemoteTargetType.macro => 'Macro · Future',
      RemoteTargetType.script => 'Script · Future',
      RemoteTargetType.system => button.name,
    };

IconData desktopIcon(String id) => switch (id) {
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
