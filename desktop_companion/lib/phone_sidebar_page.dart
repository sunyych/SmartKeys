import 'package:flutter/material.dart';
import 'package:lumiakeys_protocol/lumiakeys_protocol.dart';
import 'desktop_controller.dart';

class PhoneSidebarPage extends StatefulWidget {
  const PhoneSidebarPage({super.key, required this.controller});
  final DesktopController controller;
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
          child: OutlinedButton.icon(
            key: const ValueKey('desktop-sidebar-reset'),
            onPressed: busy
                ? null
                : () => _run(controller.restoreSidebarDefaults),
            icon: const Icon(Icons.restore),
            label: const Text('Restore App Bar defaults'),
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
