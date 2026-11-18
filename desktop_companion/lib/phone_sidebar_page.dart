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
        setState(
          () => error =
              'Could not save the phone sidebar. Your previous list is still available.',
        );
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
    return Scaffold(
      key: const ValueKey('desktop-phone-sidebar'),
      appBar: AppBar(title: const Text('Phone sidebar')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Choose which shortcut Apps and installed App library profiles appear in the phone’s left menu. Launchpad and General always stay at the top.',
          ),
          const ListTile(
            leading: Icon(Icons.push_pin_outlined),
            title: Text('Launchpad · General'),
            subtitle: Text('Fixed top entries'),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              key: const ValueKey('desktop-sidebar-reset'),
              onPressed: busy
                  ? null
                  : () => _run(controller.restoreSidebarDefaults),
              icon: const Icon(Icons.restore),
              label: const Text('Restore default list'),
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
              child: ListTile(
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
                              () =>
                                  controller.moveSidebarItem(items[index], -1),
                            ),
                      icon: const Icon(Icons.arrow_upward),
                    ),
                    IconButton(
                      key: ValueKey('desktop-sidebar-down-${items[index].key}'),
                      tooltip: 'Move down',
                      onPressed: busy || index + 1 == items.length
                          ? null
                          : () => _run(
                              () => controller.moveSidebarItem(items[index], 1),
                            ),
                      icon: const Icon(Icons.arrow_downward),
                    ),
                    IconButton(
                      key: ValueKey('desktop-sidebar-hide-${items[index].key}'),
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
            ),
          const SizedBox(height: 16),
          Text(
            'Add to phone sidebar',
            style: Theme.of(context).textTheme.titleMedium,
          ),
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
                    : () =>
                          _run(() => controller.setSidebarVisible(item, true)),
                icon: const Icon(Icons.add),
              ),
            ),
          const Padding(
            padding: EdgeInsets.only(top: 16),
            child: Text(
              'Apps that only support launching remain in Launchpad. Adding a sidebar item does not change an App’s shortcut permissions.',
            ),
          ),
        ],
      ),
    );
  }
}
