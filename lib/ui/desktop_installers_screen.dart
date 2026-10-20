import 'package:flutter/material.dart';

import '../services/desktop_installer_service.dart';

class DesktopInstallersScreen extends StatefulWidget {
  const DesktopInstallersScreen({super.key, this.service});

  final DesktopInstallerService? service;

  @override
  State<DesktopInstallersScreen> createState() =>
      _DesktopInstallersScreenState();
}

class _DesktopInstallersScreenState extends State<DesktopInstallersScreen> {
  late final DesktopInstallerService _service =
      widget.service ?? DesktopInstallerService();
  late final Future<DesktopInstallerCatalog?> _catalog = _service.loadCatalog();
  late Future<DesktopInstallerDestination?> _destination = _service
      .selectedDestination();
  final Map<String, String> _verification = {};
  final Map<String, String> _exports = {};
  bool _choosingDestination = false;
  bool _hasDestination = false;

  bool get _exportInProgress =>
      _exports.values.any((value) => value == 'Exporting…');

  @override
  void initState() {
    super.initState();
    _destination.then((value) {
      if (mounted) setState(() => _hasDestination = value != null);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Desktop installers')),
      body: FutureBuilder<DesktopInstallerCatalog?>(
        future: _catalog,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _message(
              icon: Icons.error_outline,
              title: 'Installer catalog could not be verified',
              body: '${snapshot.error}',
            );
          }
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final catalog = snapshot.data;
          if (catalog == null) {
            return _message(
              icon: Icons.inventory_2_outlined,
              title: 'No desktop installers are bundled',
              body:
                  'This development build has no desktop installer catalog. '
                  'Tagged Android releases include the Windows and macOS installers '
                  'built in the same release workflow run.',
            );
          }
          return _catalogPage(catalog);
        },
      ),
    );
  }

  Widget _message({
    required IconData icon,
    required String title,
    required String body,
  }) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 52, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 10),
            Text(body, textAlign: TextAlign.center),
          ],
        ),
      ),
    ),
  );

  Widget _catalogPage(DesktopInstallerCatalog catalog) => ListView(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
    children: [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Release v${catalog.version}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text('Commit ${catalog.commit.substring(0, 12)}'),
              const SizedBox(height: 8),
              const Text(
                'These packages come from the same tagged release run as this Android app. '
                'Verify each package before exporting it.',
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 12),
      FutureBuilder<DesktopInstallerDestination?>(
        future: _destination,
        builder: (context, snapshot) {
          final destination = snapshot.data;
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Export folder',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    destination == null
                        ? 'Choose a local shared-storage folder before exporting.'
                        : 'Selected folder: ${destination.displayName}',
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    key: const ValueKey('choose-installer-destination'),
                    onPressed: _choosingDestination || _exportInProgress
                        ? null
                        : _chooseDestination,
                    icon: _choosingDestination
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.folder_open),
                    label: Text(
                      destination == null
                          ? 'Choose local folder'
                          : 'Change folder',
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'After exporting, connect the phone by USB and choose file transfer (MTP) '
                    'on Android to copy the installer from that folder. This app does not '
                    'turn the phone into a USB mass-storage drive.',
                  ),
                ],
              ),
            ),
          );
        },
      ),
      const SizedBox(height: 8),
      for (final installer in catalog.installers)
        _installerCard(catalog, installer),
    ],
  );

  Widget _installerCard(
    DesktopInstallerCatalog catalog,
    DesktopInstallerEntry installer,
  ) {
    final key = installer.platform.name;
    final verification = _verification[key] ?? 'Not verified on this phone';
    final exportStatus = _exports[key];
    final verifying = verification == 'Verifying…';
    final exporting = exportStatus == 'Exporting…';
    final icon = installer.platform == DesktopInstallerPlatform.windows
        ? Icons.desktop_windows_outlined
        : Icons.laptop_mac_outlined;
    return Card(
      margin: const EdgeInsets.only(top: 10),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, size: 30),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '${installer.platform.label} installer',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SelectableText(installer.fileName),
            Text(_formatBytes(installer.sizeBytes)),
            const SizedBox(height: 6),
            SelectableText(
              'SHA-256  ${installer.sha256}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Text(
              verification,
              key: ValueKey(
                'installer-verification-${installer.platform.name}',
              ),
              style: TextStyle(
                color: verification == 'Verified on this phone'
                    ? Colors.lightGreenAccent
                    : verification.startsWith('Verification failed')
                    ? Theme.of(context).colorScheme.error
                    : null,
              ),
            ),
            if (exportStatus != null && exportStatus != 'Exporting…')
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  exportStatus,
                  key: ValueKey('installer-export-${installer.platform.name}'),
                ),
              ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  key: ValueKey('verify-installer-${installer.platform.name}'),
                  onPressed: verifying || exporting
                      ? null
                      : () => _verify(installer),
                  icon: verifying
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.verified_outlined),
                  label: const Text('Verify SHA-256'),
                ),
                FilledButton.icon(
                  key: ValueKey('export-installer-${installer.platform.name}'),
                  onPressed: !_hasDestination || exporting || verifying
                      ? null
                      : () => _export(catalog, installer),
                  icon: exporting
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.file_download_outlined),
                  label: const Text('Export installer'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _chooseDestination() async {
    setState(() => _choosingDestination = true);
    try {
      final destination = await _service.chooseExportDirectory();
      if (!mounted) return;
      if (destination != null) {
        setState(() {
          _destination = Future.value(destination);
          _hasDestination = true;
        });
      }
    } catch (error) {
      if (mounted) _showError('Folder selection failed: $error');
    } finally {
      if (mounted) setState(() => _choosingDestination = false);
    }
  }

  Future<void> _verify(DesktopInstallerEntry installer) async {
    final key = installer.platform.name;
    setState(() => _verification[key] = 'Verifying…');
    try {
      await _service.verify(installer);
      if (mounted) {
        setState(() => _verification[key] = 'Verified on this phone');
      }
    } catch (error) {
      if (mounted) {
        setState(() => _verification[key] = 'Verification failed: $error');
      }
    }
  }

  Future<void> _export(
    DesktopInstallerCatalog catalog,
    DesktopInstallerEntry installer,
  ) async {
    final key = installer.platform.name;
    setState(() => _exports[key] = 'Exporting…');
    try {
      final receipt = await _service.exportInstaller(catalog, installer);
      final destination = await _service.selectedDestination();
      if (mounted) {
        setState(() {
          _verification[key] = 'Verified on this phone';
          _exports[key] =
              'Exported ${receipt.fileName} to ${destination?.displayName ?? 'selected folder'}';
        });
      }
    } catch (error) {
      if (mounted) _showError('Installer export failed: $error');
      if (mounted) setState(() => _exports.remove(key));
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  static String _formatBytes(int bytes) {
    final mb = bytes / (1024 * 1024);
    return '${mb.toStringAsFixed(1)} MB';
  }
}
