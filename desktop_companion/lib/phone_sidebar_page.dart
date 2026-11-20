import 'package:flutter/material.dart';
import 'package:lumiakeys_protocol/lumiakeys_protocol.dart';
import 'codex_activity.dart';
import 'desktop_controller.dart';
import 'desktop_localizations.dart';

class PhoneSidebarPage extends StatefulWidget {
  const PhoneSidebarPage({
    super.key,
    required this.controller,
    this.codexActivity,
  });
  final DesktopController controller;
  final CodexActivityMonitor? codexActivity;
  @override
  State<PhoneSidebarPage> createState() => _PhoneSidebarPageState();
}

class _PhoneSidebarPageState extends State<PhoneSidebarPage> {
  bool busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _run(Future<void> Function() operation) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await operation();
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Could not save App Bar settings. Try again.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller,
        items = widget.controller.sidebarItems;
    final hidden = controller.sidebarCandidates
        .where((candidate) => !items.any((item) => item.key == candidate.key))
        .toList();
    final settings = controller.manifest.settings;
    return ListView(
      key: const ValueKey('desktop-phone-sidebar'),
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Manage the apps and shortcut profiles in the phone’s left menu.',
        ),
        const ListTile(
          leading: Icon(Icons.push_pin_outlined),
          title: Text('Launchpad · General'),
          subtitle: Text('Fixed top entries'),
        ),
        Card(
          child: SwitchListTile(
            key: const ValueKey('desktop-sidebar-global-launch'),
            title: const Text('Allow phone app launching'),
            subtitle: const Text(
              'Applies to App Bar and Launchpad. When off, App Bar opens the shortcut panel so you can focus the app on this computer.',
            ),
            value: settings.autoLaunchApps,
            onChanged: busy
                ? null
                : (value) => _run(
                    () => controller.updateSettings(
                      settings.copyWith(autoLaunchApps: value),
                    ),
                  ),
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                key: const ValueKey('desktop-sidebar-reset'),
                onPressed: busy
                    ? null
                    : () => _run(controller.restoreSidebarDefaults),
                icon: const Icon(Icons.restore),
                label: const Text('Restore App Bar defaults'),
              ),
              if (widget.codexActivity case final activity?)
                OutlinedButton.icon(
                  key: const ValueKey('desktop-sidebar-codex-activity'),
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => _CodexActivityDialog(activity: activity),
                  ),
                  icon: const Icon(Icons.circle_outlined),
                  label: Text(
                    desktopText(context, 'Codex status dot', 'Codex 状态点'),
                  ),
                ),
            ],
          ),
        ),
        if (error != null)
          Text(
            error!,
            key: const ValueKey('desktop-sidebar-error'),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        Text(
          'Visible on phone · ${items.length}/100',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        if (items.isEmpty)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              'Only Launchpad and General are shown. Add items below.',
            ),
          ),
        for (var index = 0; index < items.length; index++)
          Card(
            child: Column(
              children: [
                ListTile(
                  key: ValueKey('desktop-sidebar-visible-${items[index].key}'),
                  leading: Icon(
                    items[index].kind == RemoteSidebarKind.application
                        ? Icons.apps
                        : Icons.library_books_outlined,
                  ),
                  title: Text(controller.sidebarItemName(items[index])),
                  subtitle: Text(
                    items[index].kind == RemoteSidebarKind.application
                        ? 'Shortcut App'
                        : 'Installed App library profile',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        key: ValueKey('desktop-sidebar-up-${items[index].key}'),
                        tooltip: 'Move up',
                        onPressed: busy || index == 0
                            ? null
                            : () => _run(
                                () => controller.moveSidebarItem(
                                  items[index],
                                  -1,
                                ),
                              ),
                        icon: const Icon(Icons.arrow_upward),
                      ),
                      IconButton(
                        key: ValueKey(
                          'desktop-sidebar-down-${items[index].key}',
                        ),
                        tooltip: 'Move down',
                        onPressed: busy || index + 1 == items.length
                            ? null
                            : () => _run(
                                () =>
                                    controller.moveSidebarItem(items[index], 1),
                              ),
                        icon: const Icon(Icons.arrow_downward),
                      ),
                      IconButton(
                        key: ValueKey(
                          'desktop-sidebar-hide-${items[index].key}',
                        ),
                        tooltip: 'Hide on phone',
                        onPressed: busy
                            ? null
                            : () => _run(
                                () => controller.setSidebarVisible(
                                  items[index],
                                  false,
                                ),
                              ),
                        icon: const Icon(Icons.visibility_off_outlined),
                      ),
                    ],
                  ),
                ),
                if (items[index].kind == RemoteSidebarKind.application)
                  SwitchListTile(
                    key: ValueKey('desktop-sidebar-launch-${items[index].key}'),
                    title: const Text('Launch or focus when tapped'),
                    subtitle: const Text(
                      'Turn off to open the shortcut panel only.',
                    ),
                    value: !controller
                        .manifest
                        .sidebarShortcutOnlyApplicationIds
                        .contains(items[index].id),
                    onChanged: busy
                        ? null
                        : (value) => _run(
                            () => controller.setSidebarLaunchOnSelect(
                              items[index].id,
                              value,
                            ),
                          ),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 16),
        Text('Add to App Bar', style: Theme.of(context).textTheme.titleMedium),
        if (hidden.isEmpty)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              'All available shortcut Apps and installed library profiles are already shown. Install more profiles from App library.',
            ),
          ),
        for (final item in hidden)
          ListTile(
            key: ValueKey('desktop-sidebar-available-${item.key}'),
            title: Text(controller.sidebarItemName(item)),
            subtitle: Text(
              item.kind == RemoteSidebarKind.application
                  ? 'Shortcut App'
                  : 'Installed App library profile',
            ),
            trailing: IconButton(
              key: ValueKey('desktop-sidebar-add-${item.key}'),
              tooltip: 'Show on phone',
              onPressed: busy || items.length >= 100
                  ? null
                  : () => _run(() => controller.setSidebarVisible(item, true)),
              icon: const Icon(Icons.add),
            ),
          ),
      ],
    );
  }
}

class _CodexActivityDialog extends StatefulWidget {
  const _CodexActivityDialog({required this.activity});

  final CodexActivityMonitor activity;

  @override
  State<_CodexActivityDialog> createState() => _CodexActivityDialogState();
}

class _CodexActivityDialogState extends State<_CodexActivityDialog> {
  late final TextEditingController _endpoint = TextEditingController(
    text: widget.activity.target?.endpoint.toString(),
  );
  late final TextEditingController _chat = TextEditingController(
    text: widget.activity.target?.threadId,
  );
  bool _saving = false;
  String? _error;

  Future<void> _save() async {
    if (_saving) return;
    final endpoint = _endpoint.text.trim();
    final chat = _chat.text.trim();
    final CodexActivityTarget? target;
    try {
      target = endpoint.isEmpty && chat.isEmpty
          ? null
          : CodexActivityTarget(endpoint, chat);
    } on FormatException {
      setState(() {
        _error = desktopText(
          context,
          'Enter a local WebSocket address and a chat ID or link.',
          '请输入本机 WebSocket 地址及聊天 ID 或链接。',
        );
      });
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.activity.setTarget(target);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = desktopText(
          context,
          'Could not save the status dot settings.',
          '无法保存状态点设置。',
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(desktopText(context, 'Codex status dot', 'Codex 状态点')),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            desktopText(
              context,
              'Follow one chat from an existing App Server on this computer. '
                  'Clear both fields to hide the dot.',
              '通过本机已运行的 App Server 跟踪一个聊天。清空两项即可隐藏状态点。',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _endpoint,
            enabled: !_saving,
            decoration: InputDecoration(
              labelText: desktopText(context, 'App Server address', '服务器地址'),
              hintText: 'ws://127.0.0.1:7337',
            ),
          ),
          TextField(
            controller: _chat,
            enabled: !_saving,
            decoration: InputDecoration(
              labelText: desktopText(context, 'Chat ID or link', '聊天 ID 或链接'),
            ),
          ),
          if (_error case final error?) ...[
            const SizedBox(height: 8),
            Text(
              error,
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
        onPressed: _saving ? null : _save,
        child: Text(desktopText(context, 'Save', '保存')),
      ),
    ],
  );

  @override
  void dispose() {
    _endpoint.dispose();
    _chat.dispose();
    super.dispose();
  }
}
