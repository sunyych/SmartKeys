import 'package:flutter/material.dart';

import '../mobile_appearance.dart';
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
      appBar: AppBar(title: const MobileText('Desktop installers', '桌面安装包')),
      body: FutureBuilder<DesktopInstallerCatalog?>(
        future: _catalog,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _message(
              icon: Icons.error_outline,
              title: context.mobileText(
                'Installer catalog could not be verified',
                '无法验证安装包目录',
              ),
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
              title: context.mobileText(
                'No desktop installers are bundled',
                '此版本未内置桌面安装包',
              ),
              body: context.mobileText(
                'This development build has no desktop installer catalog. '
                    'Tagged Android releases include the Windows and macOS installers '
                    'built in the same release workflow run.',
                '当前开发版没有桌面安装包目录。Android 正式发布版包含同批构建的 Windows 和 macOS 安装包。',
              ),
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
                context.mobileText(
                  'Release v${catalog.version}',
                  '发布版本 v${catalog.version}',
                ),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                context.mobileText(
                  'Commit ${catalog.commit.substring(0, 12)}',
                  '提交 ${catalog.commit.substring(0, 12)}',
                ),
              ),
              const SizedBox(height: 8),
              const MobileText(
                'These packages come from the same tagged release run as this Android app. '
                    'Verify each package before exporting it.',
                '这些安装包与当前 Android 应用来自同一次发布构建。请在导出前验证安装包。',
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
                    context.mobileText('Export folder', '导出文件夹'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    destination == null
                        ? context.mobileText(
                            'Choose a local shared-storage folder before exporting.',
                            '请先在本地共享存储中选择导出文件夹。',
                          )
                        : context.mobileText(
                            'Selected folder: ${destination.displayName}',
                            '已选文件夹：${destination.displayName}',
                          ),
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
                          ? context.mobileText('Choose local folder', '选择本地文件夹')
                          : context.mobileText('Change folder', '更换文件夹'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const MobileText(
                    'After exporting, connect the phone by USB and choose file transfer (MTP) '
                        'on Android to copy the installer from that folder. This app does not '
                        'turn the phone into a USB mass-storage drive.',
                    '导出后，通过 USB 连接手机，在 Android 上选择文件传输（MTP），即可从所选文件夹复制安装包。',
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
                    context.mobileText(
                      '${installer.platform.label} installer',
                      '${installer.platform.label} 安装包',
                    ),
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
              context.mobileText(verification, switch (verification) {
                'Not verified on this phone' => '尚未在本机验证',
                'Verifying…' => '正在验证…',
                'Verified on this phone' => '已在本机验证',
                _ => verification.replaceFirst(
                  'Verification failed: ',
                  '验证失败：',
                ),
              }),
              key: ValueKey(
                'installer-verification-${installer.platform.name}',
              ),
              style: TextStyle(
                color: verification == 'Verified on this phone'
                    ? (Theme.of(context).brightness == Brightness.dark
                          ? Colors.lightGreenAccent
                          : Theme.of(context).colorScheme.tertiary)
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
                  label: const MobileText('Verify SHA-256', '验证 SHA-256'),
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
                  label: const MobileText('Export installer', '导出安装包'),
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
      if (mounted) {
        _showError(
          context.mobileText(
            'Folder selection failed: $error',
            '选择文件夹失败：$error',
          ),
        );
      }
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
        final folder =
            destination?.displayName ??
            context.mobileText('selected folder', '所选文件夹');
        setState(() {
          _verification[key] = 'Verified on this phone';
          _exports[key] = context.mobileText(
            'Exported ${receipt.fileName} to $folder',
            '已将 ${receipt.fileName} 导出至 $folder',
          );
        });
      }
    } catch (error) {
      if (mounted) {
        _showError(
          context.mobileText(
            'Installer export failed: $error',
            '安装包导出失败：$error',
          ),
        );
      }
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
