import 'package:flutter/material.dart';
import 'local_diagnostics.dart';
import 'icons/builtin_icon_catalog.g.dart';

class LiteSettingsScreen extends StatelessWidget {
  const LiteSettingsScreen({super.key, required this.diagnostics});
  final LiteDiagnostics diagnostics;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Local settings')),
    body: ListView(
      children: [
        const ListTile(
          title: Text('Bluetooth and offline only'),
          subtitle: Text(
            'This edition never uploads error logs or downloads icons.',
          ),
        ),
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
            await diagnostics.pruneExpired();
            if (!context.mounted) return;
            Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => LiteErrorLogScreen(diagnostics: diagnostics),
              ),
            );
          },
        ),
      ],
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
