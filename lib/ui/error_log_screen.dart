import 'package:flutter/material.dart';
import '../diagnostics/diagnostics_service.dart';
import '../mobile_appearance.dart';

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
          title: const MobileText('Error logs', '错误日志'),
          actions: [
            IconButton(
              key: const ValueKey('error-log-clear'),
              tooltip: context.mobileText('Clear local errors', '清除本地错误日志'),
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
                title: const MobileText('Share error diagnostics', '分享错误诊断信息'),
                subtitle: const MobileText(
                  'Only sanitized errors created after allowing sharing. No key, shortcut or input history.',
                  '仅分享在允许之后发生且已去除敏感信息的错误。报告不包含按键、快捷键或输入历史。',
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
                        child: const MobileText('Retry', '重试'),
                      ),
                    const SizedBox(width: 12),
                    const MobileText('Keep', '保留'),
                    const SizedBox(width: 8),
                    DropdownButton<int>(
                      key: const ValueKey('diagnostics-retention'),
                      value: diagnostics.retentionDays,
                      items: const [
                        DropdownMenuItem(
                          value: 7,
                          child: MobileText('7 days', '7 天'),
                        ),
                        DropdownMenuItem(
                          value: 30,
                          child: MobileText('30 days', '30 天'),
                        ),
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
                    child: MobileText(
                      'No errors recorded.',
                      '暂无错误记录。',
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
                      context.mobileText(
                        '${event.lastOccurredAt.toLocal()} · ${event.module} · ${event.repeatCount} occurrence${event.repeatCount == 1 ? '' : 's'}',
                        '${event.lastOccurredAt.toLocal()} · ${event.module} · ${event.repeatCount} 次',
                      ),
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
                            child: const MobileText('Close', '关闭'),
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
                child: MobileText(
                  'Local limits: 1,000 errors and 5 MiB. Successful input operations are not logged.',
                  '本地最多保留 1,000 条错误记录、共 5 MiB。成功的输入操作不会记录。',
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
        title: const MobileText('Allow error sharing?', '允许分享错误？'),
        content: const MobileText(
          'Only new sanitized errors will be sent to the central service. Earlier local errors are not included. You can turn sharing off at any time.',
          '仅将新发生且已去除敏感信息的错误发送到服务。之前的本地错误不会发送。你可以随时关闭分享。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const MobileText('Keep local', '仅保存在本机'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const MobileText('Allow sharing', '允许分享'),
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
        title: const MobileText('Clear local error logs?', '清除本地错误日志？'),
        content: const MobileText(
          'This removes saved local errors and cancels pending sharing. New errors follow your current sharing choice.',
          '这会删除本地已保存的错误，并取消尚未发送的分享。新错误仍遵循当前分享设置。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const MobileText('Cancel', '取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const MobileText('Clear logs', '清除日志'),
          ),
        ],
      ),
    );
    if (confirmed == true) await diagnostics.clear();
  }
}
