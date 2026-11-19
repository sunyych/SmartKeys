import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../icons/app_icon_catalog.dart';
import '../icons/icon_library.dart';
import '../app.dart';
import '../app_library/app_library.dart';
import '../mobile_appearance.dart';

class AppIconLibraryScreen extends StatefulWidget {
  const AppIconLibraryScreen({super.key, this.library});
  final IconLibrary? library;
  @override
  State<AppIconLibraryScreen> createState() => _AppIconLibraryScreenState();
}

class _AppIconLibraryScreenState extends State<AppIconLibraryScreen> {
  IconLibrary? _library;
  bool _ownsLibrary = false;
  String _query = '', _filter = 'All';
  String _targetOS = 'windows';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_library != null) return;
    final hostOS = context
        .dependOnInheritedWidgetOfExactType<SmartKeysScope>()
        ?.notifier
        ?.companion
        .activeHost
        .value
        ?.platform;
    if (const {'macos', 'windows', 'linux'}.contains(hostOS)) {
      _targetOS = hostOS!;
    }
    _library = widget.library ?? IconLibraryScope.maybeOf(context);
    _ownsLibrary = _library == null;
    _library ??= IconLibrary();
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    await _library!.initialize();
    if (_library!.configured) await _library!.refresh();
  }

  @override
  void dispose() {
    if (_ownsLibrary) _library?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final library = _library!;
    return IconLibraryScope(
      library: library,
      child: AnimatedBuilder(
        animation: library,
        builder: (context, _) {
          final entriesById = {
            for (final entry in library.entries) entry.id: entry,
          };
          for (final app in AppLibraryCatalog.builtin.apps) {
            entriesById.putIfAbsent(
              app.id,
              () => LibraryIcon(
                id: app.id,
                name: app.name,
                aliases: app.aliases,
                sha256: registeredAppIconHash(app.iconId)!,
                version: app.libraries.first.version,
                width: 256,
                height: 256,
                bundled: app.bundled,
                available: false,
                sourceUrl: '',
                sourcePageUrl: '',
                termsUrl: '',
              ),
            );
          }
          final entries = entriesById.values
              .where(
                (entry) =>
                    entry.matches(_query) &&
                    AppLibraryCatalog.builtin
                            .appById(entry.id)
                            ?.libraryForOS(_targetOS) !=
                        null &&
                    switch (_filter) {
                      'Built-in' => entry.bundled,
                      'Online' => !entry.bundled,
                      'Downloaded' =>
                        !entry.bundled && library.isDownloaded(entry.id),
                      _ => true,
                    },
              )
              .toList();
          return Scaffold(
            key: const ValueKey('app-library-catalog'),
            appBar: AppBar(
              title: const MobileText('App library', '应用库'),
              actions: [
                IconButton(
                  key: const ValueKey('icon-library-refresh'),
                  tooltip: context.mobileText(
                    'Refresh online catalog',
                    '刷新在线目录',
                  ),
                  onPressed: library.loading ? null : library.refresh,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            body: CustomScrollView(
              key: const ValueKey('app-icon-library'),
              slivers: [
                SliverToBoxAdapter(
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                        child: LayoutBuilder(
                          builder: (context, bounds) {
                            final search = TextField(
                              key: const ValueKey('icon-library-search'),
                              decoration: InputDecoration(
                                prefixIcon: const Icon(Icons.search),
                                labelText: context.mobileText(
                                  'Search App name or ID',
                                  '搜索应用名称或 ID',
                                ),
                              ),
                              onChanged: (value) =>
                                  setState(() => _query = value),
                            );
                            final systems = DropdownButtonFormField<String>(
                              key: const ValueKey('app-library-os'),
                              initialValue: _targetOS,
                              isExpanded: true,
                              decoration: InputDecoration(
                                labelText: context.mobileText(
                                  'Computer OS',
                                  '电脑操作系统',
                                ),
                              ),
                              items: [
                                for (final value in const [
                                  'macos',
                                  'windows',
                                  'linux',
                                ])
                                  DropdownMenuItem(
                                    value: value,
                                    child: Text(appLibraryOSLabel(value)),
                                  ),
                              ],
                              onChanged: (value) =>
                                  setState(() => _targetOS = value!),
                            );
                            return bounds.maxWidth >= 600
                                ? Row(
                                    children: [
                                      Expanded(child: search),
                                      const SizedBox(width: 16),
                                      SizedBox(width: 180, child: systems),
                                    ],
                                  )
                                : Column(children: [search, systems]);
                          },
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        child: MobileText(
                          'Set up in LumiaKey Desktop → Apps → App library.',
                          '请在 LumiaKey Desktop → 应用 → 应用库中配置。',
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: [
                            Expanded(
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: [
                                    for (final filter in const [
                                      'All',
                                      'Built-in',
                                      'Online',
                                      'Downloaded',
                                    ])
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          right: 7,
                                        ),
                                        child: ChoiceChip(
                                          key: ValueKey('icon-filter-$filter'),
                                          label: Text(
                                            _localizedFilter(context, filter),
                                          ),
                                          selected: _filter == filter,
                                          onSelected: (_) =>
                                              setState(() => _filter = filter),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                            Text(
                              context.mobileText(
                                '${entries.length} Apps',
                                '${entries.length} 个应用',
                              ),
                              key: const ValueKey('icon-library-count'),
                            ),
                          ],
                        ),
                      ),
                      if (library.loading)
                        const LinearProgressIndicator(
                          key: ValueKey('icon-library-loading'),
                        ),
                      if (library.error case final message?)
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  message,
                                  key: const ValueKey('icon-library-error'),
                                ),
                              ),
                              TextButton(
                                onPressed: library.loading
                                    ? null
                                    : library.refresh,
                                child: const MobileText('Retry', '重试'),
                              ),
                            ],
                          ),
                        ),
                      if (!library.configured && library.error == null)
                        const Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 5,
                          ),
                          child: MobileText(
                            'Bundled artwork works offline. App shortcut previews are included; optional artwork additions require a configured icon service.',
                            '内置图标和快捷键预览可离线使用。下载更多图标需要配置图标服务。',
                          ),
                        ),
                    ],
                  ),
                ),
                if (entries.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: MobileText(
                        'No Apps match this search and computer OS.',
                        '没有应用符合当前搜索和电脑操作系统。',
                        key: ValueKey('icon-library-empty'),
                      ),
                    ),
                  )
                else
                  SliverLayoutBuilder(
                    builder: (context, bounds) => SliverPadding(
                      padding: const EdgeInsets.all(16),
                      sliver: SliverGrid(
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: bounds.crossAxisExtent < 500
                              ? 3
                              : bounds.crossAxisExtent < 900
                              ? 5
                              : 8,
                          mainAxisExtent: 160,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                        ),
                        delegate: SliverChildBuilderDelegate((context, index) {
                          final entry = entries[index];
                          return Card(
                            child: InkWell(
                              key: ValueKey('library-icon-${entry.id}'),
                              borderRadius: BorderRadius.circular(12),
                              onTap: () => _showEntry(library, entry),
                              child: Padding(
                                padding: const EdgeInsets.all(9),
                                child: Column(
                                  children: [
                                    AppArtwork(
                                      appId: entry.id,
                                      pngBytes: library.cachedBytes(entry.id),
                                      size: 54,
                                      semanticLabel: '${entry.name} icon',
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      entry.name,
                                      textAlign: TextAlign.center,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const Spacer(),
                                    Text(
                                      entry.bundled
                                          ? _localizedFilter(
                                              context,
                                              'Built-in',
                                            )
                                          : library.isDownloaded(entry.id)
                                          ? _localizedFilter(
                                              context,
                                              'Downloaded',
                                            )
                                          : _localizedFilter(context, 'Online'),
                                      style: Theme.of(
                                        context,
                                      ).textTheme.labelSmall,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }, childCount: entries.length),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  String _localizedFilter(BuildContext context, String value) =>
      context.mobileText(value, switch (value) {
        'Built-in' => '内置',
        'Downloaded' => '已下载',
        'Online' => '在线',
        _ => '全部',
      });

  Future<void> _showEntry(
    IconLibrary library,
    LibraryIcon entry,
  ) => showDialog<void>(
    context: context,
    builder: (dialogContext) => AnimatedBuilder(
      animation: library,
      builder: (context, _) => AlertDialog(
        key: const ValueKey('icon-library-preview'),
        scrollable: true,
        title: Text(entry.name),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (AppLibraryCatalog.builtin
                    .appById(entry.id)
                    ?.libraryForOS(_targetOS)
                case final appLibrary?) ...[
              Text(
                '${appLibraryOSLabel(_targetOS)} · ${appLibraryContextLabel(appLibrary.context)} · v${appLibrary.version}',
                key: const ValueKey('app-library-variant'),
              ),
              const MobileText(
                'Set up in LumiaKey Desktop → Apps → App library.',
                '请在 LumiaKey Desktop → 应用 → 应用库中配置。',
              ),
              for (final action in appLibrary.actions)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(action.title),
                  subtitle: Text(
                    action.isConfigured
                        ? formatAppLibraryChord(action.keys, _targetOS)
                        : context.mobileText(
                            'Unassigned · configure before use',
                            '未分配 · 请先配置',
                          ),
                  ),
                ),
              const MobileText('Shortcut sources', '快捷键来源'),
              for (final source in appLibrary.sourceUrls)
                SelectableText(source),
              const Divider(),
            ],
            Center(
              child: AppArtwork(
                appId: entry.id,
                pngBytes: library.cachedBytes(entry.id),
                size: 128,
                semanticLabel: '${entry.name} full icon',
              ),
            ),
            const SizedBox(height: 14),
            SelectableText(entry.id),
            Text(
              entry.bundled
                  ? context.mobileText('Included for offline use', '已内置，可离线使用')
                  : library.isDownloaded(entry.id)
                  ? context.mobileText(
                      'Downloaded for offline use',
                      '已下载，可离线使用',
                    )
                  : context.mobileText(
                      'Available from the icon library',
                      '可从图标库下载',
                    ),
            ),
            const SizedBox(height: 12),
            const MobileText('Source', '来源'),
            SelectableText(entry.sourcePageUrl),
            TextButton.icon(
              onPressed: () =>
                  Clipboard.setData(ClipboardData(text: entry.sourcePageUrl)),
              icon: const Icon(Icons.link),
              label: const MobileText('Copy source link', '复制来源链接'),
            ),
            const MobileText('Brand usage terms', '品牌使用条款'),
            SelectableText(entry.termsUrl),
            TextButton.icon(
              onPressed: () =>
                  Clipboard.setData(ClipboardData(text: entry.termsUrl)),
              icon: const Icon(Icons.link),
              label: const MobileText('Copy terms link', '复制条款链接'),
            ),
            if (!entry.bundled)
              FilledButton.icon(
                key: const ValueKey('icon-library-download'),
                onPressed: !entry.available || library.isDownloading(entry.id)
                    ? null
                    : () => library.download(entry.id),
                icon: library.isDownloading(entry.id)
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.download),
                label: Text(
                  library.isDownloading(entry.id)
                      ? context.mobileText('Downloading…', '正在下载…')
                      : library.isDownloaded(entry.id)
                      ? context.mobileText('Download again', '重新下载')
                      : context.mobileText(
                          'Download for offline use',
                          '下载以便离线使用',
                        ),
                ),
              ),
            if (library.error case final message?)
              Text(message, key: const ValueKey('icon-preview-error')),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Clipboard.setData(ClipboardData(text: entry.id)),
            child: const MobileText('Copy App ID', '复制应用 ID'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const MobileText('Close', '关闭'),
          ),
        ],
      ),
    ),
  );
}
