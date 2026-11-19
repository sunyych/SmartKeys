import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as paths;

import 'desktop_controller.dart';
import 'desktop_application_artwork.dart';
import 'desktop_localizations.dart';
import 'installed_app_discovery.dart';
import 'installed_app_registry.dart';

/// Only a local desktop picker can create an additional launch target.
Future<InstalledLaunchTarget?> pickInstalledApplication({
  String dialogTitle = 'Choose an installed application',
}) async {
  final picked = await FilePicker.platform.pickFiles(
    dialogTitle: dialogTitle,
    allowMultiple: false,
    type: Platform.isWindows || Platform.isMacOS
        ? FileType.custom
        : FileType.any,
    allowedExtensions: Platform.isWindows
        ? ['exe', 'lnk']
        : Platform.isMacOS
        ? ['app']
        : null,
  );
  final selected = picked?.files.single.path;
  if (selected == null) return null;
  final directory = Directory(selected);
  final canonical = Platform.isMacOS
      ? await directory.resolveSymbolicLinks()
      : await File(selected).resolveSymbolicLinks();
  final kind = Platform.isWindows
      ? canonical.toLowerCase().endsWith('.lnk')
            ? InstalledLaunchKind.windowsShortcut
            : InstalledLaunchKind.windowsExecutable
      : Platform.isMacOS
      ? InstalledLaunchKind.macBundle
      : canonical.endsWith('.desktop')
      ? InstalledLaunchKind.linuxDesktopEntry
      : InstalledLaunchKind.linuxExecutable;
  final name = paths.basenameWithoutExtension(canonical);
  final target = InstalledLaunchTarget.discovered(
    name: name,
    kind: kind,
    identity:
        'manual:${Platform.isWindows ? paths.windows.normalize(canonical).toLowerCase() : canonical}',
    locator: canonical,
    manual: true,
    executablePath:
        kind == InstalledLaunchKind.windowsExecutable ||
            kind == InstalledLaunchKind.linuxExecutable
        ? canonical
        : null,
    iconKey: PlatformInstalledApplicationDiscovery.iconForName(name),
  );
  if (!await installedTargetExists(target)) {
    throw const FormatException('Choose an available application');
  }
  return target;
}

class InstalledAppPicker extends StatefulWidget {
  const InstalledAppPicker({
    super.key,
    required this.controller,
    required this.index,
    this.pickLocal,
  });
  final DesktopController controller;
  final int index;
  final Future<InstalledLaunchTarget?> Function()? pickLocal;
  @override
  State<InstalledAppPicker> createState() => _InstalledAppPickerState();
}

class _InstalledAppPickerState extends State<InstalledAppPicker> {
  late String _selected;
  String _query = '';
  String? _error;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _selected = widget.controller.launcherAppIds[widget.index] ?? '';
  }

  Future<void> _refresh() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    await widget.controller.refreshApplications();
    if (mounted) {
      setState(() {
        _busy = false;
        _error =
            widget.controller.installedApplicationsError ??
            widget.controller.error;
      });
    }
  }

  Future<void> _add() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final target =
          await (widget.pickLocal?.call() ??
              pickInstalledApplication(
                dialogTitle: desktopText(
                  context,
                  'Choose an installed application',
                  '选择已安装的应用',
                ),
              ));
      if (target != null) {
        await widget.controller.addInstalledApplication(target);
        if (mounted) {
          setState(() {
            _selected = target.id;
            _query = '';
          });
        }
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = desktopText(
            context,
            'The application could not be saved. Your existing keys are unchanged.',
            '无法保存此应用，已有按键绑定未更改。',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final apps = widget.controller.launcherApplications
          .where(
            (app) =>
                _query.trim().isEmpty ||
                app.name.toLowerCase().contains(_query.trim().toLowerCase()),
          )
          .toList();
      return AlertDialog(
        key: const ValueKey('launcher-editor-dialog'),
        title: Text(
          desktopText(
            context,
            'Edit Key ${widget.index + 1}',
            '编辑按键 ${widget.index + 1}',
          ),
        ),
        content: SizedBox(
          width: 560,
          height: math.min(460, MediaQuery.sizeOf(context).height * .55),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                desktopText(
                  context,
                  'Choose an installed application or add one from this computer.',
                  '选择电脑上已安装的应用，或从本机添加应用。',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const ValueKey('launcher-app-search'),
                decoration: InputDecoration(
                  labelText: desktopText(context, 'Search apps', '搜索应用'),
                  prefixIcon: const Icon(Icons.search),
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  OutlinedButton.icon(
                    key: const ValueKey('launcher-refresh-apps'),
                    onPressed: _busy ? null : _refresh,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: Text(desktopText(context, 'Refresh Apps', '刷新应用')),
                  ),
                  OutlinedButton.icon(
                    key: const ValueKey('launcher-add-local-app'),
                    onPressed: _busy ? null : _add,
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(
                      desktopText(context, 'Add from This Computer', '从本机添加'),
                    ),
                  ),
                ],
              ),
              if (_busy) const LinearProgressIndicator(),
              if (_error ?? widget.controller.installedApplicationsError
                  case final message?)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(
                    message,
                    key: const ValueKey('launcher-picker-error'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              Expanded(
                child: ListView.builder(
                  key: const ValueKey('launcher-app-picker'),
                  itemCount: apps.length + 1,
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return ListTile(
                        key: const ValueKey('launcher-picker-none'),
                        title: Text(desktopText(context, 'No App', '不绑定应用')),
                        selected: _selected.isEmpty,
                        leading: const Icon(Icons.block),
                        onTap: _busy
                            ? null
                            : () => setState(() => _selected = ''),
                      );
                    }
                    final app = apps[index - 1];
                    return ListTile(
                      key: ValueKey('launcher-picker-${app.id}'),
                      leading: DesktopApplicationArtwork(
                        app: app,
                        size: 28,
                        iconService: widget.controller.actions.appIconService,
                      ),
                      title: Text(
                        app.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        !app.detected
                            ? desktopText(
                                context,
                                'App unavailable · assignment kept',
                                '应用不可用 · 已保留原绑定',
                              )
                            : app.launchOnly
                            ? desktopText(context, 'Launch app', '启动应用')
                            : desktopText(
                                context,
                                'Launch with configured shortcuts',
                                '启动并使用已配置的快捷键',
                              ),
                      ),
                      selected: _selected == app.id,
                      trailing: _selected == app.id
                          ? const Icon(Icons.check_circle)
                          : null,
                      enabled: !_busy && (app.detected || _selected == app.id),
                      onTap: () => setState(() => _selected = app.id),
                    );
                  },
                ),
              ),
              if (apps.isEmpty && _query.isNotEmpty)
                Text(
                  desktopText(
                    context,
                    'No matching installed apps',
                    '没有匹配的已安装应用',
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: Text(desktopText(context, 'Cancel', '取消')),
          ),
          FilledButton(
            key: const ValueKey('launcher-picker-save'),
            onPressed: _busy ? null : () => Navigator.pop(context, _selected),
            child: Text(desktopText(context, 'Save', '保存')),
          ),
        ],
      );
    },
  );
}
