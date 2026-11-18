import 'package:flutter/material.dart';
import 'local_diagnostics.dart';
import 'lite_controller.dart';
import 'lite_editors.dart';
import 'local_profiles.dart';
import 'icons/builtin_icon_catalog.g.dart';

class LiteSettingsScreen extends StatelessWidget {
  const LiteSettingsScreen({super.key, this.controller, this.diagnostics})
    : assert(controller != null || diagnostics != null);
  final LiteController? controller;
  final LiteDiagnostics? diagnostics;
  LiteDiagnostics get localDiagnostics =>
      diagnostics ?? controller!.diagnostics;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Local settings')),
    body: controller == null
        ? entries(context)
        : AnimatedBuilder(
            animation: controller!,
            builder: (context, _) => entries(context),
          ),
  );
  Widget entries(BuildContext context) => ListView(
    children: [
      const ListTile(
        title: Text('Bluetooth and offline only'),
        subtitle: Text(
          'Configure keys on this phone. Nothing is uploaded or downloaded.',
        ),
      ),
      if (controller != null) ...[
        ListTile(
          key: const ValueKey('lite-profiles-entry'),
          leading: const Icon(Icons.grid_view),
          title: const Text('Profiles and shortcuts'),
          subtitle: Text('${controller!.profiles.length} local profiles'),
          onTap: controller!.loading
              ? null
              : () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => LiteProfilesScreen(controller: controller!),
                  ),
                ),
        ),
        ListTile(
          key: const ValueKey('lite-launchpad-entry'),
          leading: const Icon(Icons.apps),
          title: const Text('Launchpad'),
          subtitle: const Text('12 local slots · keyboard launch combinations'),
          onTap: controller!.loading
              ? null
              : () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        LiteLaunchpadSettingsScreen(controller: controller!),
                  ),
                ),
        ),
        ListTile(
          key: const ValueKey('lite-bluetooth-entry'),
          leading: const Icon(Icons.bluetooth),
          title: const Text('Bluetooth devices'),
          subtitle: Text(
            controller!.connected
                ? 'Connected to ${controller!.activeHost?.name ?? "computer"}'
                : 'Connect one paired computer',
          ),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => LiteBluetoothScreen(controller: controller!),
            ),
          ),
        ),
      ],
      ListTile(
        key: const ValueKey('lite-icon-library-entry'),
        leading: const Icon(Icons.apps),
        title: const Text('App icon library'),
        subtitle: const Text('50 bundled icons · available offline'),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) => const LiteIconLibraryScreen(),
          ),
        ),
      ),
      ListTile(
        key: const ValueKey('lite-error-logs-entry'),
        leading: const Icon(Icons.error_outline),
        title: const Text('Error logs'),
        subtitle: const Text('Saved on this phone only'),
        onTap: () async {
          await localDiagnostics.pruneExpired();
          if (context.mounted) {
            Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) =>
                    LiteErrorLogScreen(diagnostics: localDiagnostics),
              ),
            );
          }
        },
      ),
    ],
  );
}

class LiteProfilesScreen extends StatefulWidget {
  const LiteProfilesScreen({super.key, required this.controller});
  final LiteController controller;
  @override
  State<LiteProfilesScreen> createState() => _LiteProfilesScreenState();
}

class _LiteProfilesScreenState extends State<LiteProfilesScreen> {
  String? error;
  bool deleting = false;
  Future<void> remove(LocalProfile profile) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${profile.name}?'),
        content: const Text(
          'Its shortcuts will be removed from this phone. Linked launch slots will no longer select this profile.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      deleting = true;
      error = null;
    });
    try {
      await widget.controller.deleteProfile(profile.id);
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Could not delete this profile. The saved configuration is unchanged.',
        );
      }
    } finally {
      if (mounted) setState(() => deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) => Scaffold(
      appBar: AppBar(
        title: const Text('Profiles and shortcuts'),
        actions: [
          IconButton(
            key: const ValueKey('lite-new-profile'),
            tooltip: 'New profile',
            icon: const Icon(Icons.add),
            onPressed: deleting
                ? null
                : () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          LiteProfileEditor(controller: widget.controller),
                    ),
                  ),
          ),
        ],
      ),
      body: ListView(
        children: [
          if (error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(error!, key: const ValueKey('lite-settings-error')),
            ),
          for (final profile in widget.controller.profiles)
            ListTile(
              key: ValueKey('lite-profile-${profile.id}'),
              title: Text(profile.name),
              subtitle: Text('${profile.shortcuts.length} shortcuts'),
              onTap: deleting
                  ? null
                  : () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => LiteProfileEditor(
                          controller: widget.controller,
                          profile: profile,
                        ),
                      ),
                    ),
              trailing: IconButton(
                tooltip: 'Delete ${profile.name}',
                onPressed: deleting ? null : () => remove(profile),
                icon: const Icon(Icons.delete_outline),
              ),
            ),
        ],
      ),
    ),
  );
}

class LiteLaunchpadSettingsScreen extends StatelessWidget {
  const LiteLaunchpadSettingsScreen({super.key, required this.controller});
  final LiteController controller;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) => Scaffold(
      appBar: AppBar(title: const Text('Launchpad')),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Each slot sends only its saved keyboard combination to the connected computer. Set up that combination on the computer first.',
            ),
          ),
          for (var index = 0; index < controller.launcherSlots.length; index++)
            ListTile(
              key: ValueKey('lite-configure-slot-$index'),
              leading: Text('${index + 1}'),
              title: Text(
                controller.launcherSlots[index].title.isEmpty
                    ? 'Empty slot'
                    : controller.launcherSlots[index].title,
              ),
              subtitle: Text(
                controller.launcherSlots[index].launchShortcut == null
                    ? 'Launch not configured'
                    : shortcutDescription(
                        controller.launcherSlots[index].launchShortcut!,
                      ),
              ),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => LiteLaunchSlotEditor(
                    controller: controller,
                    index: index,
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

class LiteBluetoothScreen extends StatefulWidget {
  const LiteBluetoothScreen({super.key, required this.controller});
  final LiteController controller;
  @override
  State<LiteBluetoothScreen> createState() => _LiteBluetoothScreenState();
}

class _LiteBluetoothScreenState extends State<LiteBluetoothScreen> {
  bool busy = false;
  String? error;
  Future<void> act(Future<bool> Function() action) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (!await action() && mounted) {
        setState(
          () => error =
              'Bluetooth did not complete this request. Check the connection and retry.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Bluetooth is unavailable. Retry after checking Android permissions.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) => Scaffold(
      appBar: AppBar(
        title: const Text('Bluetooth devices'),
        actions: [
          IconButton(
            key: const ValueKey('lite-refresh-hosts'),
            tooltip: 'Refresh paired devices',
            onPressed: busy
                ? null
                : () => act(widget.controller.refreshPairedHosts),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Connect one paired computer. Pair LumiaKey in the computer’s Bluetooth settings before connecting here.',
          ),
          const SizedBox(height: 12),
          Text(
            widget.controller.connected
                ? 'Connected to ${widget.controller.activeHost?.name ?? "computer"}'
                : 'Status: ${widget.controller.status}',
          ),
          if (error != null)
            Text(error!, key: const ValueKey('lite-bluetooth-error')),
          if (widget.controller.connected)
            OutlinedButton(
              onPressed: busy ? null : () => act(widget.controller.disconnect),
              child: const Text('Disconnect'),
            ),
          for (final host in widget.controller.pairedHosts)
            ListTile(
              title: Text(host.name),
              trailing: TextButton(
                onPressed:
                    busy ||
                        widget.controller.activeHost?.address == host.address
                    ? null
                    : () => act(() => widget.controller.connect(host.address)),
                child: const Text('Connect'),
              ),
            ),
          if (widget.controller.pairedHosts.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text(
                'No paired computers found. Allow Bluetooth access, then pair this phone from the computer.',
              ),
            ),
          OutlinedButton(
            onPressed: busy
                ? null
                : () => act(widget.controller.requestBluetoothAccess),
            child: const Text('Allow Bluetooth access'),
          ),
          OutlinedButton(
            onPressed: busy
                ? null
                : () => act(widget.controller.makeDiscoverable),
            child: const Text('Make phone discoverable'),
          ),
        ],
      ),
    ),
  );
}

class LiteErrorLogScreen extends StatelessWidget {
  const LiteErrorLogScreen({super.key, required this.diagnostics});
  final LiteDiagnostics diagnostics;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: diagnostics,
    builder: (context, _) {
      final events = diagnostics.journal.events.reversed.toList();
      return Scaffold(
        appBar: AppBar(
          title: const Text('Error logs'),
          actions: [
            IconButton(
              key: const ValueKey('lite-clear-errors'),
              tooltip: 'Clear local logs',
              icon: const Icon(Icons.delete_outline),
              onPressed: events.isEmpty
                  ? null
                  : () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Clear local error logs?'),
                          content: const Text(
                            'This removes the saved errors from this phone.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('Cancel'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text('Clear'),
                            ),
                          ],
                        ),
                      );
                      if (confirmed == true) await diagnostics.clear();
                    },
            ),
          ],
        ),
        body: ListView(
          children: [
            const ListTile(
              title: Text('Local only · sharing unavailable'),
              subtitle: Text(
                'Only fixed error categories are saved. Key combinations, input text, device addresses and raw exceptions are never recorded.',
              ),
            ),
            ListTile(
              title: const Text('Keep error logs'),
              trailing: DropdownButton<int>(
                key: const ValueKey('lite-retention'),
                value: diagnostics.journal.retention.inDays,
                items: const [
                  DropdownMenuItem(value: 7, child: Text('7 days')),
                  DropdownMenuItem(value: 30, child: Text('30 days')),
                ],
                onChanged: (days) {
                  if (days != null) diagnostics.setRetentionDays(days);
                },
              ),
            ),
            if (!diagnostics.journal.metadata.verified)
              const ListTile(
                title: Text('App version unavailable'),
                subtitle: Text(
                  'Records remain local with unverified version metadata.',
                ),
              ),
            if (diagnostics.storageFailed)
              const ListTile(
                key: ValueKey('lite-log-storage-error'),
                title: Text('Could not save or load local logs'),
                subtitle: Text('The current in-memory log remains available.'),
              ),
            if (events.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'No errors recorded',
                  key: ValueKey('lite-empty-errors'),
                ),
              ),
            for (final event in events)
              ListTile(
                key: ValueKey('lite-event-${event.id}'),
                title: Text(event.message),
                subtitle: Text(
                  '${event.lastOccurredAt.toLocal()} · ${event.module} · ${event.repeatCount} occurrence(s)',
                ),
                onTap: () => showDialog<void>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Text(event.message),
                    content: SingleChildScrollView(
                      child: Text(
                        'Module: ${event.module}\nTrigger: ${event.trigger}\nSeverity: ${event.severity}\nFirst: ${event.occurredAt.toLocal()}\nLatest: ${event.lastOccurredAt.toLocal()}\nOccurrences: ${event.repeatCount}\nVersion: ${event.metadata.appVersion ?? "unverified"}\nBuild: ${event.metadata.appBuild ?? "unverified"}\nStored on this phone only.',
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Close'),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );
}

class LiteIconLibraryScreen extends StatefulWidget {
  const LiteIconLibraryScreen({super.key});
  @override
  State<LiteIconLibraryScreen> createState() => _LiteIconLibraryScreenState();
}

class _LiteIconLibraryScreenState extends State<LiteIconLibraryScreen> {
  String query = '';
  @override
  Widget build(BuildContext context) {
    final normalized = query.trim().toLowerCase();
    final entries = builtinIconCatalog
        .where(
          (entry) => [
            entry.id,
            entry.name,
            ...entry.aliases,
          ].any((text) => text.toLowerCase().contains(normalized)),
        )
        .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('App icon library')),
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              '50 bundled icons · fully offline. Icons do not add application launch or shortcut permissions.',
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              key: const ValueKey('lite-icon-search'),
              decoration: const InputDecoration(
                labelText: 'Search name, ID or alias',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (value) => setState(() => query = value),
            ),
          ),
          if (entries.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'No matching icons',
                key: ValueKey('lite-icon-empty'),
              ),
            ),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 180,
                mainAxisExtent: 170,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
              ),
              itemCount: entries.length,
              itemBuilder: (context, index) {
                final entry = entries[index];
                return Card(
                  child: InkWell(
                    key: ValueKey('lite-icon-${entry.id}'),
                    onTap: () => showDialog<void>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: Text(entry.name),
                        content: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Image.asset(
                                entry.assetPath,
                                width: 128,
                                height: 128,
                                fit: BoxFit.contain,
                                semanticLabel: '${entry.name} icon',
                              ),
                              SelectableText(
                                'ID: ${entry.id}\nBundled · offline\nSource: ${entry.sourcePageUrl}\nTerms: ${entry.termsUrl}\nBrand rights remain with their respective owners.',
                              ),
                            ],
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Close'),
                          ),
                        ],
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        children: [
                          Expanded(
                            child: Image.asset(
                              entry.assetPath,
                              fit: BoxFit.contain,
                              semanticLabel: '${entry.name} icon',
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            entry.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                          ),
                          Text(
                            entry.id,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
