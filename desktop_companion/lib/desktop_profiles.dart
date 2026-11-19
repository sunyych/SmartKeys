import 'package:flutter/material.dart';
import 'package:lumiakeys_protocol/lumiakeys_protocol.dart';

import 'app_library_page.dart' show desktopLibraryProfileIcon;
import 'desktop_application_artwork.dart';
import 'desktop_controller.dart';
import 'desktop_localizations.dart';

class DesktopProfilesPage extends StatefulWidget {
  const DesktopProfilesPage({super.key, required this.controller});

  final DesktopController controller;

  @override
  State<DesktopProfilesPage> createState() => _DesktopProfilesPageState();
}

class _DesktopProfilesPageState extends State<DesktopProfilesPage> {
  bool _busy = false;
  bool _saveFailed = false;

  Future<void> _update(Future<void> Function() operation) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _saveFailed = false;
    });
    try {
      await operation();
    } catch (_) {
      if (mounted) setState(() => _saveFailed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(RemoteProfile profile) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(desktopText(dialogContext, 'Delete profile?', '删除配置档案？')),
        content: Text(
          profile.isLibraryProfile
              ? desktopText(
                  dialogContext,
                  'Delete "${profile.name}" and its library shortcuts?',
                  '要删除“${profile.name}”及其快捷键库吗？',
                )
              : desktopText(
                  dialogContext,
                  'Delete "${profile.name}"?',
                  '要删除“${profile.name}”吗？',
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(desktopText(dialogContext, 'Cancel', '取消')),
          ),
          FilledButton(
            key: const ValueKey('desktop-profile-delete-confirm'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(desktopText(dialogContext, 'Delete', '删除')),
          ),
        ],
      ),
    );
    if (mounted && confirmed == true) {
      await _update(() => widget.controller.deleteProfile(profile.id));
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final manifest = widget.controller.manifest;
      return ListView(
        padding: const EdgeInsets.all(28),
        children: [
          Align(
            alignment: Alignment.topLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 980),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    desktopText(
                      context,
                      'Profiles select which desktop-owned layout is active on the phone.',
                      '配置档案决定手机当前显示的桌面快捷键布局。',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: FilledButton.icon(
                      key: const ValueKey('desktop-add-profile'),
                      onPressed:
                          _busy ||
                              widget.controller.profileLayoutOptions.isEmpty
                          ? null
                          : () => showDialog<void>(
                              context: context,
                              barrierDismissible: false,
                              builder: (_) => _AddProfileDialog(
                                controller: widget.controller,
                              ),
                            ),
                      icon: const Icon(Icons.add),
                      label: Text(
                        desktopText(context, 'Add profile', '添加配置档案'),
                      ),
                    ),
                  ),
                  if (_saveFailed) ...[
                    const SizedBox(height: 8),
                    Text(
                      desktopText(
                        context,
                        'Could not update the profiles.',
                        '无法更新配置档案。',
                      ),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Card(
                    child: RadioGroup<String>(
                      groupValue: manifest.currentProfileId,
                      onChanged: (id) {
                        if (id != null) {
                          _update(() => widget.controller.switchProfile(id));
                        }
                      },
                      child: Column(
                        children: [
                          for (final profile in manifest.profiles)
                            RadioListTile<String>(
                              value: profile.id,
                              enabled: !_busy,
                              title: _ProfileTitle(profile: profile),
                              subtitle: Text(
                                [
                                  desktopText(
                                    context,
                                    'Layout: ${manifest.layoutById(profile.layoutId)?.name ?? profile.layoutId}',
                                    '布局：${manifest.layoutById(profile.layoutId)?.name ?? profile.layoutId}',
                                  ),
                                  ?profile.platform,
                                  ?profile.applicationId,
                                ].join(' · '),
                              ),
                              secondary:
                                  profile.id == 'default' ||
                                      manifest.profiles.length == 1
                                  ? null
                                  : IconButton(
                                      key: ValueKey(
                                        'desktop-delete-profile-${profile.id}',
                                      ),
                                      tooltip: desktopText(
                                        context,
                                        'Delete profile',
                                        '删除配置档案',
                                      ),
                                      icon: const Icon(Icons.delete_outline),
                                      onPressed: _busy
                                          ? null
                                          : () => _delete(profile),
                                    ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    },
  );
}

class _ProfileTitle extends StatelessWidget {
  const _ProfileTitle({required this.profile});

  final RemoteProfile profile;

  @override
  Widget build(BuildContext context) {
    final icon = desktopAppIconAssets[profile.sourceIconId];
    final bytes = desktopLibraryProfileIcon(profile);
    return Row(
      children: [
        if (bytes != null) ...[
          Image.memory(bytes, width: 24, height: 24),
          const SizedBox(width: 8),
        ] else if (icon != null) ...[
          Image.asset('assets/app_icons/$icon', width: 24, height: 24),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Text(
            profile.id == 'default' && profile.name == 'Default'
                ? desktopText(context, 'Default', '默认')
                : profile.name,
          ),
        ),
      ],
    );
  }
}

class _AddProfileDialog extends StatefulWidget {
  const _AddProfileDialog({required this.controller});

  final DesktopController controller;

  @override
  State<_AddProfileDialog> createState() => _AddProfileDialogState();
}

class _AddProfileDialogState extends State<_AddProfileDialog> {
  final _name = TextEditingController();
  late final _layouts = widget.controller.profileLayoutOptions;
  late String _layout =
      _layouts.where((layout) => layout.id == 'keyboard').firstOrNull?.id ??
      _layouts.first.id;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.controller.addProfile(name: _name.text, layoutId: _layout);
      if (mounted) Navigator.pop(context);
    } on FormatException {
      if (mounted) {
        setState(
          () => _error = desktopText(
            context,
            'Choose a unique name (1–64 characters) and an available layout.',
            '请使用 1–64 个字符的唯一名称，并选择可用布局。',
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = desktopText(
            context,
            'Could not save the profile.',
            '无法保存配置档案。',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: Text(desktopText(context, 'Add profile', '添加配置档案')),
    content: SizedBox(
      width: 320,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const ValueKey('desktop-profile-name'),
            controller: _name,
            autofocus: true,
            enabled: !_saving,
            decoration: InputDecoration(
              labelText: desktopText(context, 'Profile name', '配置档案名称'),
            ),
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _layout,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: desktopText(context, 'Shortcut layout', '快捷键布局'),
            ),
            items: [
              for (final layout in _layouts)
                DropdownMenuItem(value: layout.id, child: Text(layout.name)),
            ],
            onChanged: _saving
                ? null
                : (layout) {
                    if (layout != null) setState(() => _layout = layout);
                  },
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context),
        child: Text(desktopText(context, 'Cancel', '取消')),
      ),
      FilledButton(
        key: const ValueKey('desktop-profile-add-confirm'),
        onPressed: _saving ? null : _save,
        child: Text(desktopText(context, 'Add', '添加')),
      ),
    ],
  );
}
