import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';

import '../app.dart';
import '../controllers/app_controller.dart';
import '../data/private_usage_directory.dart';
import '../data/public_shortcut_catalog.dart';
import '../data/community_setup_repository.dart';
import '../data/shortcut_community_client.dart';
import '../data/shortcut_community_store.dart';
import '../data/shortcut_usage_repository.dart';
import '../mobile_appearance.dart';
import 'community_setup_screen.dart';

enum _UsagePeriod { all, today, days7, days30, custom }

enum _RankingOrder { most, least, recent }

enum _HistoryOrder { newest, oldest }

class UsageDashboardScreen extends StatefulWidget {
  const UsageDashboardScreen({super.key, this.client, this.directoryProvider});

  final ShortcutCommunityClient? client;
  final Future<Directory> Function()? directoryProvider;

  @override
  State<UsageDashboardScreen> createState() => _UsageDashboardScreenState();
}

class _UsageDashboardScreenState extends State<UsageDashboardScreen> {
  _UsagePeriod _period = _UsagePeriod.all;
  _RankingOrder _rankingOrder = _RankingOrder.most;
  _HistoryOrder _historyOrder = _HistoryOrder.newest;
  DateTimeRange? _customRange;
  String _communityPeriod = 'all';
  String _communityTag = '';
  String _communityExperience = '';
  CommunityRanking? _communityRanking;
  String? _communityState;
  bool _working = false;
  bool _loadingServices = false;
  String? _servicesError;
  int _rankingRequestGeneration = 0;
  int _historyLimit = 100;
  late final ShortcutCommunityClient _client;
  Future<_DashboardServices>? _services;

  @override
  void initState() {
    super.initState();
    try {
      _client = widget.client ?? ShortcutCommunityClient();
    } on ArgumentError {
      _client = ShortcutCommunityClient(endpoint: '');
      _communityState = 'invalid_configuration';
    }
    if (_client.isConfigured) {
      _refreshCommunity();
    } else {
      _communityState ??= 'not_configured';
    }
  }

  Future<void> _loadServices(AppController controller) async {
    try {
      final directory =
          await (widget.directoryProvider ?? privateUsageDirectory)();
      final store = ShortcutCommunityStore(
        directory: directory,
        serverOrigin: _client.serverOrigin ?? 'unconfigured',
      );
      await store.load();
      if (mounted) {
        setState(() {
          _services = Future.value(
            _DashboardServices(controller.shortcutUsage, store),
          );
          _servicesError = null;
          _loadingServices = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _servicesError = 'Could not open private usage storage.';
          _loadingServices = false;
        });
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_services == null && !_loadingServices && _servicesError == null) {
      _loadingServices = true;
      _loadServices(SmartKeysScope.of(context));
    }
  }

  Future<void> _refreshCommunity() async {
    if (!_client.isConfigured) {
      setState(() => _communityState = 'not_configured');
      return;
    }
    final generation = ++_rankingRequestGeneration;
    final requestedPeriod = _communityPeriod;
    final requestedTag = _communityTag.isEmpty ? null : _communityTag;
    final requestedExperience = _communityExperience.isEmpty
        ? null
        : _communityExperience;
    setState(() => _communityState = 'loading');
    try {
      final result = await _client.fetchRankings(
        requestedPeriod,
        tag: requestedTag,
        experience: requestedExperience,
      );
      if (!mounted) return;
      if (generation != _rankingRequestGeneration ||
          requestedPeriod != _communityPeriod) {
        return;
      }
      if (requestedTag != (_communityTag.isEmpty ? null : _communityTag)) {
        return;
      }
      if (requestedExperience !=
          (_communityExperience.isEmpty ? null : _communityExperience)) {
        return;
      }
      setState(() {
        _communityRanking = result;
        _communityState = result.rows.isEmpty ? 'empty' : 'ready';
      });
    } on CommunityServiceException catch (error) {
      if (mounted && generation == _rankingRequestGeneration) {
        setState(() => _communityState = error.code);
      }
    } catch (_) {
      if (mounted && generation == _rankingRequestGeneration) {
        setState(() => _communityState = 'unavailable');
      }
    }
  }

  DateTime? _startAt(DateTime now) {
    switch (_period) {
      case _UsagePeriod.all:
        return null;
      case _UsagePeriod.today:
        return DateTime(now.year, now.month, now.day);
      case _UsagePeriod.days7:
        return DateTime(now.year, now.month, now.day - 6);
      case _UsagePeriod.days30:
        return DateTime(now.year, now.month, now.day - 29);
      case _UsagePeriod.custom:
        final range = _customRange;
        return range == null
            ? null
            : DateTime(range.start.year, range.start.month, range.start.day);
    }
  }

  DateTime? _endExclusiveAt(DateTime now) {
    switch (_period) {
      case _UsagePeriod.all:
        return null;
      case _UsagePeriod.today:
        return DateTime(now.year, now.month, now.day + 1);
      case _UsagePeriod.days7:
      case _UsagePeriod.days30:
        return DateTime(now.year, now.month, now.day + 1);
      case _UsagePeriod.custom:
        final range = _customRange;
        return range == null
            ? null
            : DateTime(range.end.year, range.end.month, range.end.day + 1);
    }
  }

  List<ShortcutUsageEvent> _filtered(
    List<ShortcutUsageEvent> events,
    DateTime? start,
    DateTime? end,
  ) => events
      .where((event) {
        final local = DateTime.fromMillisecondsSinceEpoch(
          event.usedAt,
        ).toLocal();
        return (start == null || !local.isBefore(start)) &&
            (end == null || local.isBefore(end));
      })
      .toList(growable: false);

  String _periodLabel() => switch (_period) {
    _UsagePeriod.all => context.mobileText('All time', '全部时间'),
    _UsagePeriod.today => context.mobileText('Today', '今天'),
    _UsagePeriod.days7 => context.mobileText('Last 7 days', '最近 7 天'),
    _UsagePeriod.days30 => context.mobileText('Last 30 days', '最近 30 天'),
    _UsagePeriod.custom =>
      _customRange == null
          ? context.mobileText('Custom dates', '自定义日期')
          : '${_date(_customRange!.start)} – ${_date(_customRange!.end)}',
  };

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const MobileText('Shortcut usage', '快捷键使用情况')),
    body: FutureBuilder<_DashboardServices>(
      future: _services,
      builder: (context, snapshot) {
        if (_servicesError != null) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_servicesError!),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: () {
                    setState(() {
                      _servicesError = null;
                      _loadingServices = true;
                    });
                    _loadServices(SmartKeysScope.of(context));
                  },
                  child: const MobileText('Retry', '重试'),
                ),
              ],
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final services = snapshot.data!;
        return AnimatedBuilder(
          animation: services.repository,
          builder: (context, _) => _buildDashboard(services),
        );
      },
    ),
  );

  Widget _buildDashboard(_DashboardServices services) {
    final now = DateTime.now();
    final start = _startAt(now);
    final end = _endExclusiveAt(now);
    final events = _filtered(services.repository.events, start, end);
    final rankingRecords = _period == _UsagePeriod.all
        ? services.repository.records
        : services.repository.recordsForPeriod(start: start, end: end);
    final ordered = [...rankingRecords];
    ordered.sort((a, b) {
      if (_rankingOrder == _RankingOrder.recent) {
        final byDate = b.lastUsedAt.compareTo(a.lastUsedAt);
        return byDate != 0 ? byDate : a.key.compareTo(b.key);
      }
      final byCount = _rankingOrder == _RankingOrder.most
          ? b.count.compareTo(a.count)
          : a.count.compareTo(b.count);
      return byCount != 0 ? byCount : a.key.compareTo(b.key);
    });
    final history = [...events]
      ..sort(
        (a, b) => _historyOrder == _HistoryOrder.newest
            ? b.usedAt.compareTo(a.usedAt)
            : a.usedAt.compareTo(b.usedAt),
      );
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            children: [
              if (services.repository.lastError != null)
                const ListTile(
                  leading: Icon(Icons.warning_amber_outlined),
                  title: MobileText(
                    'Some local usage changes could not be saved.',
                    '部分使用记录未能保存。',
                  ),
                  subtitle: MobileText(
                    'Shortcut controls remain available. Check local storage before clearing data.',
                    '仍可使用快捷键。清除数据前请检查本地存储。',
                  ),
                ),
              _periodSelector(),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth > 600;
                  final cards = [
                    _SummaryCard(
                      label: context.mobileText('Clicks', '点击次数'),
                      value:
                          '${_period == _UsagePeriod.all ? services.repository.records.fold<int>(0, (sum, record) => sum + record.count) : events.length}',
                      icon: Icons.touch_app_outlined,
                    ),
                    _SummaryCard(
                      label: context.mobileText('Shortcuts', '快捷键'),
                      value: '${ordered.length}',
                      icon: Icons.keyboard_alt_outlined,
                    ),
                    _SummaryCard(
                      label: context.mobileText('Range', '日期范围'),
                      value: _periodLabel(),
                      icon: Icons.date_range_outlined,
                    ),
                  ];
                  return wide
                      ? Row(
                          children: [
                            for (final card in cards)
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: card,
                                ),
                              ),
                          ],
                        )
                      : Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final card in cards)
                              SizedBox(
                                width: (constraints.maxWidth - 8) / 2,
                                child: card,
                              ),
                          ],
                        );
                },
              ),
              if (services.repository.hasLegacyCounts &&
                  _period == _UsagePeriod.all)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: MobileText(
                    'All-time totals also include older migrated counts; dated views include recorded clicks only.',
                    '汇总包含从旧版本迁移的次数，按日期筛选时仅显示有记录的点击。',
                  ),
                ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      context.mobileText('Shortcut ranking', '快捷键排行'),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  DropdownButton<_RankingOrder>(
                    value: _rankingOrder,
                    key: const ValueKey('usage-ranking-sort'),
                    items: const [
                      DropdownMenuItem(
                        value: _RankingOrder.most,
                        child: MobileText('Most used', '最常使用'),
                      ),
                      DropdownMenuItem(
                        value: _RankingOrder.least,
                        child: MobileText('Least used', '最少使用'),
                      ),
                      DropdownMenuItem(
                        value: _RankingOrder.recent,
                        child: MobileText('Recently used', '最近使用'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => _rankingOrder = value);
                    },
                  ),
                ],
              ),
              if (ordered.isEmpty)
                const ListTile(
                  title: MobileText(
                    'No clicks in this date range',
                    '此日期范围内没有点击记录',
                  ),
                )
              else
                for (var i = 0; i < ordered.length; i++)
                  ListTile(
                    key: ValueKey('usage-rank-${ordered[i].key}'),
                    leading: CircleAvatar(child: Text('${i + 1}')),
                    title: Text(ordered[i].label),
                    trailing: Text('${ordered[i].count}×'),
                    onTap: () => _showShortcutDetails(
                      context,
                      ordered[i].key,
                      ordered[i].label,
                      events,
                    ),
                  ),
              const Divider(height: 28),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      context.mobileText('Click history', '点击历史'),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  DropdownButton<_HistoryOrder>(
                    value: _historyOrder,
                    key: const ValueKey('usage-history-sort'),
                    items: const [
                      DropdownMenuItem(
                        value: _HistoryOrder.newest,
                        child: MobileText('Newest first', '最新在前'),
                      ),
                      DropdownMenuItem(
                        value: _HistoryOrder.oldest,
                        child: MobileText('Oldest first', '最早在前'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => _historyOrder = value);
                    },
                  ),
                ],
              ),
              if (history.isEmpty)
                const ListTile(
                  title: MobileText(
                    'No click history in this date range',
                    '此日期范围内没有点击历史',
                  ),
                ),
              for (final event in history.take(_historyLimit))
                ListTile(
                  key: ValueKey('usage-event-${event.id}'),
                  leading: const Icon(Icons.keyboard_outlined),
                  title: Text(event.label),
                  subtitle: Text(_timestamp(event.usedAt)),
                ),
              if (history.length > _historyLimit)
                Center(
                  child: TextButton(
                    onPressed: () => setState(() => _historyLimit += 100),
                    child: Text(
                      context.mobileText(
                        'Load more (${history.length - _historyLimit} remaining)',
                        '加载更多（剩余 ${history.length - _historyLimit} 条）',
                      ),
                    ),
                  ),
                ),
              const Divider(height: 28),
              _communityPanel(services),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Material(
            elevation: 8,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                runSpacing: 8,
                spacing: 8,
                children: [
                  OutlinedButton.icon(
                    key: const ValueKey('usage-smart-sort'),
                    icon: const Icon(Icons.low_priority),
                    label: Text(
                      context.mobileText(
                        'Smart sort · ${SmartKeysScope.of(context).activeProfile.name}',
                        '按使用次数排序 · ${SmartKeysScope.of(context).activeProfile.name}',
                      ),
                    ),
                    onPressed: _working || services.repository.records.isEmpty
                        ? null
                        : () async {
                            await SmartKeysScope.of(
                              context,
                            ).reorderActiveProfileByUsage();
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: MobileText(
                                    'Current Profile reordered by usage',
                                    '已按使用次数调整当前配置的顺序',
                                  ),
                                ),
                              );
                            }
                          },
                  ),
                  FilledButton.tonalIcon(
                    key: const ValueKey('usage-clear'),
                    icon: const Icon(Icons.delete_outline),
                    label: const MobileText('Clear local usage', '清除本地使用记录'),
                    onPressed: _working || services.repository.records.isEmpty
                        ? null
                        : () => _confirmClear(context, services.repository),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _periodSelector() => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final value in _UsagePeriod.values)
        ChoiceChip(
          label: Text(switch (value) {
            _UsagePeriod.all => context.mobileText('All time', '全部时间'),
            _UsagePeriod.today => context.mobileText('Today', '今天'),
            _UsagePeriod.days7 => context.mobileText('7 days', '7 天'),
            _UsagePeriod.days30 => context.mobileText('30 days', '30 天'),
            _UsagePeriod.custom => context.mobileText('Custom', '自定义'),
          }),
          selected: _period == value,
          onSelected: (_) async {
            if (value == _UsagePeriod.custom) {
              final now = DateTime.now();
              final range = await showDateRangePicker(
                context: context,
                firstDate: DateTime(2000),
                lastDate: now,
                initialDateRange:
                    _customRange ??
                    DateTimeRange(
                      start: now.subtract(const Duration(days: 6)),
                      end: now,
                    ),
              );
              if (range == null) return;
              setState(() {
                _customRange = range;
                _period = value;
              });
            } else {
              setState(() => _period = value);
            }
          },
        ),
    ],
  );

  Widget _communityPanel(_DashboardServices services) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        context.mobileText('Community ranking', '社区排行'),
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const ListTile(
        leading: Icon(Icons.public),
        title: MobileText('Public aggregate rankings', '公开汇总排行'),
        subtitle: MobileText(
          'Reading is available without sharing. Network connections reveal your IP address to the service.',
          '无需分享即可查看排行。联网时，服务可获取你的 IP 地址。',
        ),
      ),
      Wrap(
        children: [
          const MobileText('Period', '时间范围'),
          const SizedBox(width: 12),
          DropdownButton<String>(
            value: _communityPeriod,
            items: const [
              DropdownMenuItem(
                value: 'all',
                child: MobileText('All time', '全部时间'),
              ),
              DropdownMenuItem(value: '7d', child: MobileText('7 days', '7 天')),
              DropdownMenuItem(
                value: '30d',
                child: MobileText('30 days', '30 天'),
              ),
            ],
            onChanged: (value) {
              if (value != null) {
                setState(() => _communityPeriod = value);
                _refreshCommunity();
              }
            },
          ),
          const SizedBox(width: 16),
          const MobileText('Profession', '职业'),
          const SizedBox(width: 8),
          DropdownButton<String>(
            key: const ValueKey('usage-community-tag'),
            value: _communityTag,
            items: [
              const DropdownMenuItem(
                value: '',
                child: MobileText('All professions', '所有职业'),
              ),
              for (final entry in communityProfessionTags.entries)
                DropdownMenuItem(
                  value: entry.key,
                  child: Text(communityProfessionLabel(context, entry.key)),
                ),
            ],
            onChanged: (value) {
              if (value != null) {
                setState(() => _communityTag = value);
                _refreshCommunity();
              }
            },
          ),
          const SizedBox(width: 16),
          const MobileText('Experience', '熟练程度'),
          const SizedBox(width: 8),
          DropdownButton<String>(
            key: const ValueKey('usage-community-experience'),
            value: _communityExperience,
            items: [
              const DropdownMenuItem(
                value: '',
                child: MobileText('All experience levels', '所有熟练程度'),
              ),
              for (final entry in communityExperienceLevels.entries)
                DropdownMenuItem(
                  value: entry.key,
                  child: Text(communityExperienceLabel(context, entry.key)),
                ),
            ],
            onChanged: (value) {
              if (value != null) {
                setState(() => _communityExperience = value);
                _refreshCommunity();
              }
            },
          ),
          IconButton(
            tooltip: context.mobileText('Refresh rankings', '刷新排行'),
            onPressed: _refreshCommunity,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      if (_communityState == 'not_configured')
        const ListTile(
          title: MobileText(
            'Community service is not configured for this build.',
            '当前版本未配置社区服务。',
          ),
        )
      else if (_communityState == 'loading')
        const LinearProgressIndicator()
      else if (_communityState == 'empty')
        const ListTile(title: MobileText('No public rankings yet.', '暂无公开排行。'))
      else if (_communityState != 'ready')
        ListTile(
          title: Text(_communityErrorLabel(_communityState)),
          trailing: IconButton(
            onPressed: _refreshCommunity,
            icon: const Icon(Icons.refresh),
          ),
        )
      else
        ..._communityRanking!.rows.asMap().entries.map((entry) {
          final row = entry.value;
          return ListTile(
            leading: CircleAvatar(child: Text('${entry.key + 1}')),
            title: Text(publicShortcutLabels[row.shortcutId] ?? row.shortcutId),
            trailing: Text('${row.count}×'),
            subtitle: Text(
              context.mobileText(
                '${row.contributions} contributions',
                '${row.contributions} 份贡献',
              ),
            ),
          );
        }),
      const Divider(),
      SwitchListTile(
        key: const ValueKey('usage-sharing-enabled'),
        title: const MobileText('Share anonymous aggregate counts', '分享匿名汇总次数'),
        subtitle: const MobileText(
          'Off by default. Each batch needs its own preview and confirmation. Submitted batches can be withdrawn here.',
          '默认关闭。每批数据都需要预览并确认，已提交的批次也可在此撤回。',
        ),
        value: services.store.sharingEnabled,
        onChanged: (value) async {
          try {
            await services.store.setSharingEnabled(value);
          } catch (_) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: MobileText(
                    'Sharing preference could not be saved.',
                    '无法保存分享设置。',
                  ),
                ),
              );
            }
          } finally {
            if (mounted) setState(() {});
          }
        },
      ),
      if (services.store.pending != null && !services.store.pending!.cancelled)
        ListTile(
          title: const MobileText(
            'A submission is waiting for an explicit retry',
            '一批数据等待手动重试',
          ),
          subtitle: const MobileText(
            'The same saved batch will be retried to prevent duplicate counts.',
            '重试使用同一个已保存的批次，避免重复统计。',
          ),
          trailing: TextButton(
            onPressed: services.store.sharingEnabled && !_working
                ? () => _submitPending(services)
                : null,
            child: const MobileText('Retry', '重试'),
          ),
        ),
      if (services.store.pending != null && !services.store.pending!.cancelled)
        ListTile(
          key: const ValueKey('usage-cancel-pending'),
          leading: const Icon(Icons.pause_circle_outline),
          title: const MobileText('Cancel this pending batch', '取消待处理批次'),
          subtitle: const MobileText(
            'Keeps its receipt for withdrawal if the server accepted it.',
            '会保留回执，以便在服务器已接收时撤回。',
          ),
          onTap: _working ? null : () => _cancelPending(services),
        ),
      if (services.store.sharingEnabled && services.store.pending == null)
        ListTile(
          key: const ValueKey('usage-share-preview'),
          leading: const Icon(Icons.upload_outlined),
          title: const MobileText('Preview a new batch', '预览新批次'),
          subtitle: Text(
            _client.isConfigured
                ? context.mobileText(
                    'Only recognized shortcut categories and counts are included.',
                    '仅包含已识别的快捷键类别及次数。',
                  )
                : context.mobileText(
                    'Service unavailable for this build; configure a ranking endpoint to submit.',
                    '当前版本的服务不可用。请配置排行服务后提交。',
                  ),
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: _working || !_client.isConfigured
              ? null
              : () => _previewAndSubmit(context, services),
        ),
      if (services.store.receipts.isNotEmpty)
        ListTile(
          key: const ValueKey('usage-withdraw'),
          leading: const Icon(Icons.delete_sweep_outlined),
          title: const MobileText('Withdraw online contributions', '撤回在线贡献'),
          subtitle: Text(
            context.mobileText(
              '${services.store.receipts.length} saved receipt(s)',
              '已保存 ${services.store.receipts.length} 份回执',
            ),
          ),
          trailing: _working
              ? const CircularProgressIndicator()
              : const Icon(Icons.chevron_right),
          onTap: _working ? null : () => _withdraw(context, services),
        ),
    ],
  );

  Future<void> _previewAndSubmit(
    BuildContext context,
    _DashboardServices services,
  ) async {
    if (services.store.pending != null ||
        !services.store.sharingEnabled ||
        !_client.isConfigured) {
      return;
    }
    final alreadySubmitted = services.store.submittedEventIds;
    final eligible = services.repository.events
        .where(
          (e) =>
              e.publicShortcutId != null &&
              communityShortcutIds.contains(e.publicShortcutId) &&
              !alreadySubmitted.contains(e.id),
        )
        .toList();
    const maxBatchEvents = 100000;
    final batchEvents = eligible.take(maxBatchEvents).toList(growable: false);
    final counts = <String, int>{};
    for (final event in batchEvents) {
      final id = event.publicShortcutId!;
      counts[id] = (counts[id] ?? 0) + 1;
    }
    if (counts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: MobileText(
            'No new recognized shortcut clicks to share',
            '没有可分享的新快捷键点击',
          ),
        ),
      );
      return;
    }
    final items = counts.length > 15
        ? Map.fromEntries(counts.entries.take(15))
        : counts;
    CommunitySetupPreferences setup = const CommunitySetupPreferences();
    setState(() => _working = true);
    try {
      setup = await CommunitySetupRepository(
        directoryProvider: widget.directoryProvider,
      ).load();
    } on Object {
      // An unavailable setup preference must not block reviewed sharing.
    } finally {
      if (mounted) setState(() => _working = false);
    }
    if (!mounted || !context.mounted || !services.store.sharingEnabled) return;
    var selectedTag = setup.profession ?? '';
    var selectedExperience = setup.experience ?? '';
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const MobileText('Review this sharing batch', '检查分享批次'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'This batch includes these categories, counts and any optional choices below:',
                ),
                if (eligible.length > maxBatchEvents)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      '${eligible.length - maxBatchEvents} additional clicks can be reviewed in a later batch.',
                    ),
                  ),
                const SizedBox(height: 12),
                for (final entry in items.entries)
                  Text(
                    '${publicShortcutLabels[entry.key] ?? entry.key}: ${entry.value}',
                  ),
                const SizedBox(height: 12),
                const Text(
                  'The service sees your network IP address. No account or device ID is included.',
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  key: const ValueKey('usage-preview-tag'),
                  initialValue: selectedTag,
                  decoration: InputDecoration(
                    labelText: context.mobileText(
                      'Optional profession tag',
                      '职业（选填）',
                    ),
                    helperText: context.mobileText(
                      'Not inferred or linked to your Google account. Used only for this batch.',
                      '不会自动推断，也不会关联 Google 账号，仅用于这一批。',
                    ),
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: '',
                      child: MobileText('None', '无'),
                    ),
                    for (final entry in communityProfessionTags.entries)
                      DropdownMenuItem(
                        value: entry.key,
                        child: Text(
                          communityProfessionLabel(context, entry.key),
                        ),
                      ),
                  ],
                  onChanged: (value) => selectedTag = value ?? '',
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  key: const ValueKey('usage-preview-experience'),
                  initialValue: selectedExperience,
                  decoration: InputDecoration(
                    labelText: context.mobileText(
                      'Optional computer proficiency',
                      '电脑熟练程度（选填）',
                    ),
                    helperText: context.mobileText(
                      'Not inferred or linked to your Google account. Used only for this batch.',
                      '不会自动推断，也不会关联 Google 账号，仅用于这一批。',
                    ),
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: '',
                      child: MobileText('None', '无'),
                    ),
                    for (final entry in communityExperienceLevels.entries)
                      DropdownMenuItem(
                        value: entry.key,
                        child: Text(
                          communityExperienceLabel(context, entry.key),
                        ),
                      ),
                  ],
                  onChanged: (value) => selectedExperience = value ?? '',
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const MobileText('Cancel', '取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const MobileText('Submit this batch', '提交此批次'),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) return;
    if (!services.store.sharingEnabled) return;
    final eventIds = batchEvents
        .where((e) => items.containsKey(e.publicShortcutId))
        .map((e) => e.id)
        .toList();
    final batch = CommunityPendingBatch(
      batchId: _randomHex(16),
      deleteToken: _randomHex(32),
      serverOrigin: _client.serverOrigin ?? 'unconfigured',
      items: items,
      eventIds: eventIds,
      tag: selectedTag.isEmpty ? null : selectedTag,
      experience: selectedExperience.isEmpty ? null : selectedExperience,
    );
    setState(() => _working = true);
    try {
      await services.store.savePending(batch);
      if (!context.mounted) return;
      await _submitPending(services);
    } catch (_) {
      if (!context.mounted) return;
      setState(() => _working = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('The reviewed batch could not be saved securely.'),
        ),
      );
    }
  }

  Future<void> _submitPending(_DashboardServices services) async {
    final batch = services.store.pending;
    if (batch == null || batch.cancelled) {
      return;
    }
    if (!services.store.sharingEnabled) {
      if (mounted) setState(() => _working = false);
      return;
    }
    setState(() => _working = true);
    try {
      await _client.submit(batch);
      await services.store.acknowledgePending();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Community batch submitted')),
        );
      }
    } on CommunityServiceException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Submission not confirmed (${_communityErrorLabel(error.code)}). Retry uses the same batch.',
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Submission state could not be saved. The same batch is kept for explicit retry.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _withdraw(
    BuildContext context,
    _DashboardServices services,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const MobileText('Withdraw online contributions?', '撤回在线贡献？'),
        content: Text(
          'This removes ${services.store.receipts.length} submitted batch(es) from public aggregates. Failed requests keep their receipts for retry.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const MobileText('Withdraw', '撤回'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _working = true);
    final failures = <CommunityReceipt>[];
    for (final receipt in [...services.store.receipts]) {
      try {
        final client = receipt.serverOrigin == _client.serverOrigin
            ? _client
            : ShortcutCommunityClient(
                endpoint: receipt.serverOrigin,
                allowLoopbackHttp: _isLoopback(receipt.serverOrigin),
              );
        await client.withdraw(
          receipt.batchId,
          receipt.deleteToken,
          origin: receipt.serverOrigin,
        );
        await services.store.removeReceipt(receipt.batchId);
      } catch (_) {
        failures.add(receipt);
      }
    }
    if (context.mounted) {
      setState(() => _working = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            failures.isEmpty
                ? 'Online contributions withdrawn'
                : '${failures.length} withdrawal(s) failed; receipts are saved for retry',
          ),
        ),
      );
    }
  }

  Future<void> _cancelPending(_DashboardServices services) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const MobileText('Cancel pending batch?', '取消待处理批次？'),
        content: const Text(
          'The batch will never be retried. Its private receipt stays on this device so you can request withdrawal if the server already accepted it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const MobileText('Keep pending', '保持待处理'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const MobileText('Cancel batch', '取消批次'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _working = true);
    try {
      await services.store.cancelPendingSubmission();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not safely cancel the pending batch.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _confirmClear(
    BuildContext context,
    ShortcutUsageRepository repository,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const MobileText('Clear local usage?', '清除本地使用记录？'),
        content: const MobileText(
          'This permanently removes click history and local counters. An unsent batch will be canceled; contributions already accepted online remain there until you withdraw their saved receipts.',
          '这会永久删除本地点击历史和计数，并取消未提交的批次。已接收的在线贡献可凭已保存的回执撤回。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const MobileText('Clear', '清除'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      setState(() => _working = true);
      try {
        final services = await _services;
        await services?.store.cancelPendingSubmission();
        await repository.clear();
        if (context.mounted) setState(() {});
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not safely clear usage data. Try again.'),
            ),
          );
        }
      } finally {
        if (mounted) setState(() => _working = false);
      }
    }
  }

  void _showShortcutDetails(
    BuildContext context,
    String key,
    String label,
    List<ShortcutUsageEvent> events,
  ) {
    final details = events.where((event) => event.key == key).toList()
      ..sort((a, b) => a.usedAt.compareTo(b.usedAt));
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (c) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(c).height * .75,
          child: Column(
            children: [
              ListTile(
                title: Text(label),
                subtitle: Text('${details.length} clicks'),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: details.length,
                  itemBuilder: (context, index) {
                    final event =
                        details[_historyOrder == _HistoryOrder.oldest
                            ? index
                            : details.length - 1 - index];
                    return ListTile(title: Text(_timestamp(event.usedAt)));
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _randomHex(int bytes) {
    final random = Random.secure();
    return List.generate(
      bytes,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  bool _isLoopback(String endpoint) {
    final host = Uri.tryParse(endpoint)?.host;
    return host == 'localhost' ||
        host == '127.0.0.1' ||
        host == '::1' ||
        host == '[::1]';
  }

  String _date(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  String _timestamp(int value) {
    final d = DateTime.fromMillisecondsSinceEpoch(value).toLocal();
    return '${_date(d)} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}:${d.second.toString().padLeft(2, '0')}';
  }

  String _communityErrorLabel(String? code) => switch (code) {
    'not_configured' => 'Community service is not configured for this build.',
    'invalid_configuration' =>
      'Community service configuration is invalid for this build.',
    'empty' => 'No public rankings yet.',
    'timeout' => 'The community service timed out.',
    'rate_limited' => 'The community service is busy. Try again later.',
    'redirect_rejected' => 'The community service rejected a redirect.',
    'invalid_response' => 'The community service returned invalid data.',
    _ => 'Community rankings are temporarily unavailable.',
  };
}

class _DashboardServices {
  const _DashboardServices(this.repository, this.store);
  final ShortcutUsageRepository repository;
  final ShortcutCommunityStore store;
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.label,
    required this.value,
    required this.icon,
  });
  final String label, value;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Icon(icon),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label),
                Text(
                  value,
                  style: Theme.of(context).textTheme.titleMedium,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
