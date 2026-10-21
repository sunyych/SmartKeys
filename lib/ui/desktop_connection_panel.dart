import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/companion_service.dart';

/// Explicit same-network pairing UI for platforms without UDP discovery.
class DesktopConnectionPanel extends StatefulWidget {
  const DesktopConnectionPanel({super.key, required this.companion});

  final CompanionService companion;

  @override
  State<DesktopConnectionPanel> createState() => _DesktopConnectionPanelState();
}

class _DesktopConnectionPanelState extends State<DesktopConnectionPanel> {
  final _code = TextEditingController();
  bool _connecting = false;
  String? _localError;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final service = widget.companion;
    if (service is! ManualCompanionConnection || _connecting) return;
    final manualConnection = service as ManualCompanionConnection;
    setState(() => _connecting = true);
    try {
      await manualConnection.connectManually(_code.text);
      if (mounted) setState(() => _localError = null);
    } catch (error) {
      if (mounted) setState(() => _localError = '$error');
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final manual = widget.companion is ManualCompanionConnection;
    return AnimatedBuilder(
      animation: Listenable.merge([
        widget.companion.activeHost,
        widget.companion.syncStatus,
        widget.companion.errorMessage,
      ]),
      builder: (context, _) {
        final host = widget.companion.activeHost.value;
        final connected =
            host != null &&
            widget.companion.syncStatus.value == CompanionSyncStatus.ready;
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'LumiaKey Desktop',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                Text(
                  connected
                      ? 'Connected to ${host.name} (${host.address})'
                      : 'Pair on the same Wi-Fi. Your microphone audio and speech recognition stay on this iPad; only final text is sent to Desktop.',
                ),
                if (Platform.isIOS)
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text(
                      'Bluetooth HID is unavailable on iPad. Desktop mode sends keyboard shortcuts only.',
                    ),
                  ),
                if (manual && !connected) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _code,
                    obscureText: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    keyboardType: TextInputType.visiblePassword,
                    decoration: const InputDecoration(
                      labelText: 'Desktop connection code',
                      hintText: '192.168.1.20:45832 token',
                      helperText:
                          'The code stays on this device and is sent only in the authentication header.',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed: _connecting
                            ? null
                            : () async {
                                final data = await Clipboard.getData(
                                  Clipboard.kTextPlain,
                                );
                                if (data?.text != null && mounted) {
                                  _code.text = data!.text!;
                                }
                              },
                        icon: const Icon(Icons.content_paste),
                        label: const Text('Paste code'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: _connecting ? null : _connect,
                        child: _connecting
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Connect'),
                      ),
                    ],
                  ),
                ] else if (manual && connected) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton(
                      onPressed: () =>
                          (widget.companion as ManualCompanionConnection)
                              .disconnect(),
                      child: const Text('Disconnect'),
                    ),
                  ),
                ],
                if (widget.companion.errorMessage.value case final error?)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      error,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                if (_localError case final error?)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      error,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
