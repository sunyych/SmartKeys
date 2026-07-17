import 'package:flutter/material.dart';

import '../services/hid_service.dart';

Future<void> showBluetoothConnectionSheet(
  BuildContext context,
  HidService hid,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => BluetoothConnectionSheet(hid: hid),
);

class BluetoothConnectionSheet extends StatefulWidget {
  const BluetoothConnectionSheet({super.key, required this.hid});

  final HidService hid;

  @override
  State<BluetoothConnectionSheet> createState() =>
      _BluetoothConnectionSheetState();
}

class _BluetoothConnectionSheetState extends State<BluetoothConnectionSheet> {
  bool busy = false;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListenableBuilder(
        listenable: Listenable.merge([
          widget.hid.connectionStatus,
          widget.hid.pairedHosts,
          widget.hid.activeHost,
          widget.hid.errorMessage,
        ]),
        builder: (context, _) {
          final status = widget.hid.connectionStatus.value;
          final activeHost = widget.hid.activeHost.value;
          final hosts = widget.hid.pairedHosts.value;
          final error = widget.hid.errorMessage.value;
          return ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.88,
            ),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              children: [
                Row(
                  children: [
                    const Icon(Icons.bluetooth, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Bluetooth HID connection',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          Text(_statusDescription(status, activeHost)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _StatusBanner(status: status, activeHost: activeHost),
                if (error != null && error.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    error,
                    key: const ValueKey('bluetooth-error'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                if (status == HidConnectionStatus.permissionRequired)
                  FilledButton.icon(
                    key: const ValueKey('grant-bluetooth-access'),
                    onPressed: busy
                        ? null
                        : () => _run(widget.hid.requestBluetoothAccess),
                    icon: const Icon(Icons.security),
                    label: const Text('Grant Nearby devices access'),
                  ),
                if (status == HidConnectionStatus.bluetoothOff)
                  FilledButton.icon(
                    key: const ValueKey('open-bluetooth-settings'),
                    onPressed: busy
                        ? null
                        : () => _run(widget.hid.openBluetoothSettings),
                    icon: const Icon(Icons.settings_bluetooth),
                    label: const Text('Open Bluetooth settings'),
                  ),
                if (status == HidConnectionStatus.registering ||
                    status == HidConnectionStatus.connecting)
                  const LinearProgressIndicator(),
                if (status == HidConnectionStatus.connected) ...[
                  FilledButton.tonalIcon(
                    key: const ValueKey('disconnect-bluetooth-host'),
                    onPressed: busy
                        ? null
                        : () => _run(widget.hid.disconnectHost),
                    icon: const Icon(Icons.link_off),
                    label: Text('Disconnect ${activeHost?.name ?? 'computer'}'),
                  ),
                  const SizedBox(height: 18),
                ],
                if (status != HidConnectionStatus.unavailable &&
                    status != HidConnectionStatus.permissionRequired &&
                    status != HidConnectionStatus.bluetoothOff) ...[
                  Text(
                    'Pair a new computer',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    '1. Make this phone discoverable.\n'
                    '2. On Windows, open Add Bluetooth device and pair the phone.\n'
                    '3. Return here, refresh, and connect the paired computer.',
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        key: const ValueKey('make-phone-discoverable'),
                        onPressed: busy
                            ? null
                            : () => _run(widget.hid.makeDiscoverable),
                        icon: const Icon(Icons.visibility),
                        label: const Text('Make discoverable'),
                      ),
                      OutlinedButton.icon(
                        onPressed: busy
                            ? null
                            : () => _run(widget.hid.openBluetoothSettings),
                        icon: const Icon(Icons.settings),
                        label: const Text('Android settings'),
                      ),
                      IconButton.filledTonal(
                        tooltip: 'Refresh paired computers',
                        onPressed: busy
                            ? null
                            : () => _run(widget.hid.refreshPairedHosts),
                        icon: const Icon(Icons.refresh),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Text(
                        'Paired devices',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const Spacer(),
                      Text('${hosts.length}'),
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (hosts.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                          'No paired devices found. Complete pairing in Windows '
                          'and Android Bluetooth settings, then refresh.',
                        ),
                      ),
                    )
                  else
                    ...hosts.map(
                      (host) => Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: Icon(
                            host.id == activeHost?.id
                                ? Icons.computer
                                : Icons.devices_other,
                          ),
                          title: Text(host.name),
                          subtitle: Text(host.address),
                          trailing: host.id == activeHost?.id
                              ? const Chip(label: Text('Connected'))
                              : FilledButton(
                                  key: ValueKey('connect-host-${host.id}'),
                                  onPressed: busy
                                      ? null
                                      : () => _run(
                                          () => widget.hid.connectHost(host.id),
                                        ),
                                  child: const Text('Connect'),
                                ),
                        ),
                      ),
                    ),
                ],
                if (status == HidConnectionStatus.unavailable) ...[
                  const SizedBox(height: 8),
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'SmartKeys uses Android’s public Bluetooth HID Device '
                        'profile and requires an Android 9+ phone that exposes '
                        'the HID Device profile.',
                      ),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _run(Future<void> Function() operation) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await operation();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  String _statusDescription(
    HidConnectionStatus status,
    HidHost? activeHost,
  ) => switch (status) {
    HidConnectionStatus.unavailable => 'HID Device profile unavailable',
    HidConnectionStatus.permissionRequired => 'Bluetooth permission required',
    HidConnectionStatus.bluetoothOff => 'Bluetooth is turned off',
    HidConnectionStatus.registering => 'Registering the HID control surface…',
    HidConnectionStatus.disconnected => 'Ready to connect a paired computer',
    HidConnectionStatus.connecting => 'Connecting…',
    HidConnectionStatus.connected =>
      'Connected to ${activeHost?.name ?? 'computer'}',
  };
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.status, required this.activeHost});

  final HidConnectionStatus status;
  final HidHost? activeHost;

  @override
  Widget build(BuildContext context) {
    final (icon, color, label) = switch (status) {
      HidConnectionStatus.unavailable => (
        Icons.error_outline,
        Colors.redAccent,
        'Unavailable',
      ),
      HidConnectionStatus.permissionRequired => (
        Icons.security,
        Colors.amberAccent,
        'Permission required',
      ),
      HidConnectionStatus.bluetoothOff => (
        Icons.bluetooth_disabled,
        Colors.redAccent,
        'Bluetooth off',
      ),
      HidConnectionStatus.registering => (
        Icons.app_registration,
        Colors.amberAccent,
        'Registering',
      ),
      HidConnectionStatus.disconnected => (
        Icons.link_off,
        Colors.orangeAccent,
        'Disconnected',
      ),
      HidConnectionStatus.connecting => (
        Icons.bluetooth_searching,
        Colors.amberAccent,
        'Connecting',
      ),
      HidConnectionStatus.connected => (
        Icons.bluetooth_connected,
        Colors.greenAccent,
        activeHost?.name ?? 'Connected',
      ),
    };
    return Container(
      key: ValueKey('bluetooth-status-${status.name}'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: color, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
