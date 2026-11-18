import 'package:flutter/material.dart';
import '../diagnostics/diagnostics_service.dart';

class ErrorLogScreen extends StatelessWidget {
  const ErrorLogScreen({super.key, required this.diagnostics});
  final DiagnosticsService diagnostics;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: diagnostics,
    builder: (context, _) {
      final events = diagnostics.events;
      return Scaffold(
        key: const ValueKey('error-log-screen'),
        appBar: AppBar(
          title: const Text('Error logs'),
          actions: [
            IconButton(
              key: const ValueKey('error-log-clear'),
              tooltip: 'Clear local errors',
              onPressed: () => _clear(context),
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
        body: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: SwitchListTile(
                key: const ValueKey('error-sharing-switch'),
                title: const Text('Share error diagnostics'),
                subtitle: const Text(
                  'Only sanitized errors created after allowing sharing. No key, shortcut or input history.',
                ),
                value: diagnostics.sharing,
                onChanged: (value) => _sharing(context, value),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        diagnostics.status,
                        key: const ValueKey('diagnostics-status'),
                      ),
                    ),
                    if (diagnostics.sharing && diagnostics.uploadError != null)
                      TextButton(
                        onPressed: diagnostics.retrySharing,
                        child: const Text('Retry'),
                      ),
                    const SizedBox(width: 12),
                    const Text('Keep'),
                    const SizedBox(width: 8),
                    DropdownButton<int>(
                      key: const ValueKey('diagnostics-retention'),
                      value: diagnostics.retentionDays,
                      items: const [
                        DropdownMenuItem(value: 7, child: Text('7 days')),
                        DropdownMenuItem(value: 30, child: Text('30 days')),
                      ],
                      onChanged: (days) {
                        if (days != null) diagnostics.setRetentionDays(days);
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SliverToBoxAdapter(child: Divider()),
            if (events.isEmpty)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: Center(
                    child: Text(
                      'No errors recorded.',
                      key: ValueKey('error-log-empty'),
                    ),
                  ),
                ),
              )
            else
              SliverList.builder(
                key: const ValueKey('error-log-list'),
                itemCount: events.length,
                itemBuilder: (context, index) {
                  final event = events[index];
                  return ListTile(
                    key: ValueKey('error-event-${event.id}'),
                    leading: const Icon(Icons.error_outline),
                    title: Text(event.message),
                    subtitle: Text(
                      '${event.lastOccurredAt.toLocal()} · ${event.module} · ${event.repeatCount} occurrence${event.repeatCount == 1 ? '' : 's'}',
                    ),
                    onTap: () => showDialog<void>(
                      context: context,
                      builder: (context) => AlertDialog(
                        key: const ValueKey('error-log-detail'),
                        title: Text(event.message),
                        scrollable: true,
                        content: Text(
                          'First: ${event.occurredAt.toLocal()}\nLatest: ${event.lastOccurredAt.toLocal()}\nModule: ${event.module}\nCategory: ${event.trigger}\nSeverity: ${event.severity}\nOccurrences: ${event.repeatCount}\nApp version: ${event.metadata.appVersion ?? 'Unavailable'}${event.metadata.appBuild == null ? '' : ' (${event.metadata.appBuild})'}',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Close'),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'Local limits: 1,000 errors and 5 MiB. Successful input operations are not logged.',
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
  Future<void> _sharing(BuildContext context, bool value) async {
    if (!value) {
      await diagnostics.setSharing(false);
      return;
    }
    final allow = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const ValueKey('error-sharing-confirmation'),
        title: const Text('Allow error sharing?'),
        content: const Text(
          'Only new sanitized errors will be sent to the central service. Earlier local errors are not included. You can turn sharing off at any time.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep local'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Allow sharing'),
          ),
        ],
      ),
    );
    if (allow == true) await diagnostics.setSharing(true);
  }

  Future<void> _clear(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const ValueKey('error-log-clear-confirmation'),
        title: const Text('Clear local error logs?'),
        content: const Text(
          'This removes saved local errors and cancels pending sharing. New errors follow your current sharing choice.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear logs'),
          ),
        ],
      ),
    );
    if (confirmed == true) await diagnostics.clear();
  }
}
