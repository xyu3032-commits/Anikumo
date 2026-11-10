import 'package:flutter/material.dart';
import 'package:anikumo/bean/theme/violet_glass.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_modular/flutter_modular.dart';
import 'package:anikumo/modules/manga/manga_item.dart';
import 'package:anikumo/pages/manga/manga_widgets.dart';
import 'package:anikumo/services/manga/manga_search_utils.dart';
import 'package:anikumo/services/manga/manga_source.dart';
import 'package:anikumo/services/manga/manga_sources.dart';
import 'package:anikumo/services/storage/storage.dart';
import 'package:anikumo/utils/constants.dart';
import 'package:anikumo/utils/error_message.dart';

/// 分类 tab — MangaDex tags grouped the way the source groups them
/// （题材 / 主题 / 形式 / 内容）, Venera's Categories page shape.
class MangaCategoriesTab extends StatefulWidget {
  const MangaCategoriesTab({super.key});

  @override
  State<MangaCategoriesTab> createState() => _MangaCategoriesTabState();
}

class _MangaCategoriesTabState extends State<MangaCategoriesTab> {
  // Batch 14: categories from EVERY source at once, grouped by
  // source (then by the source's own tag groups), so rich
  // category sets （恋爱 / 后宫 / 热血 …) are all reachable from
  // this one page.
  Map<String, List<MangaTag>> _tagsBySource = const {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
    MangaSources.revision.addListener(_load);
  }

  @override
  void dispose() {
    MangaSources.revision.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final sources = MangaSources.all();
    final results = await Future.wait([
      for (final source in sources)
        source.tags().catchError((_) => const <MangaTag>[]),
    ]);
    if (!mounted) return;
    setState(() {
      _tagsBySource = {
        for (var i = 0; i < sources.length; i++) sources[i].id: results[i],
      };
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sources = MangaSources.all();
    final activeId = MangaSources.activeOrNull()?.id ?? '';
    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Row(
              children: [
                Container(
                  width: 4,
                  height: 24,
                  decoration: BoxDecoration(
                    gradient: VioletGlass.gradient,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '分类',
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView(
        scrollCacheExtent: const ScrollCacheExtent.pixels(700),
                    padding: const EdgeInsets.fromLTRB(
                      StyleString.pagePadding,
                      4,
                      StyleString.pagePadding,
                      StyleString.sectionSpace,
                    ),
                    children: [
                      for (final source in sources) ...[
                        Padding(
                          padding: const EdgeInsets.only(top: 18, bottom: 2),
                          child: Row(
                            children: [
                              Text(
                                source.name,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(width: 8),
                              if (source.id == activeId)
                                Chip(
                                  label: const Text('当前源'),
                                  visualDensity: VisualDensity.compact,
                                  side: BorderSide.none,
                                  backgroundColor:
                                      theme.colorScheme.secondaryContainer,
                                )
                              else
                                TextButton(
                                  onPressed: () =>
                                      MangaSources.setActive(source.id),
                                  child: const Text('切换到此源'),
                                ),
                            ],
                          ),
                        ),
                        ..._sourceGroups(context, source),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  List<Widget> _sourceGroups(BuildContext context, MangaSource source) {
    final theme = Theme.of(context);
    final tags = _tagsBySource[source.id] ?? const <MangaTag>[];
    if (tags.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(
            '该源没有分类列表',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ];
    }
    final groups = <String, List<MangaTag>>{};
    for (final tag in tags) {
      groups.putIfAbsent(tag.group, () => []).add(tag);
    }
    final orderedGroups = ['genre', 'theme', 'format', 'content', '']
        .where((group) => groups.containsKey(group))
        .toList();
    return [
      for (final group in orderedGroups) ...[
        if (group.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 8),
            child: Row(
              children: [
                Container(
                  width: 3,
                  height: 14,
                  decoration: BoxDecoration(
                    gradient: VioletGlass.gradient,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 7),
                Text(
                  groups[group]!.first.groupLabel,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final tag in groups[group]!)
              ActionChip(
                label: Text(tag.name),
                onPressed: () => context.pushNamed(
                  '/manga/category',
                  arguments: MangaCategoryArgs(source: source, tag: tag),
                ),
              ),
          ],
        ),
      ],
    ];
  }
}

/// Route arguments for a category browse: the tag plus the
/// source it belongs to (categories are per-source).
class MangaCategoryArgs {
  const MangaCategoryArgs({required this.source, required this.tag});

  final MangaSource source;
  final MangaTag tag;
}

/// All manga carrying one tag, paged.
class MangaCategoryPage extends StatefulWidget {
  const MangaCategoryPage({super.key, required this.args});

  final MangaCategoryArgs args;

  MangaTag get tag => args.tag;

  @override
  State<MangaCategoryPage> createState() => _MangaCategoryPageState();
}

class _MangaCategoryPageState extends State<MangaCategoryPage> {
  static const _pageSize = 24;
  final List<MangaItem> _items = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  // Batch 188: two consecutive dud pages end the list,
  // not one (see MangaEndOfList).
  final _endOfList = MangaEndOfList();
  bool _loadMoreFailed = false;
  String? _errorText;

  /// Batch 90: explicit next-page counter — the same
  /// false-end fix as the explore grid (a short page is the
  /// source's page size, not the end of the listing).
  int _nextPage = 2;

  @override
  void initState() {
    super.initState();
    _loadFirst();
  }

  // Batch 27: same missing-failure-path fix as the explore
  // tab — a throwing byTag left this page spinning forever.
  // Batch 95: and a hard 30 s cap — a byTag queued behind a
  // wedged engine call (per-source serialization; the
  // engine's own cap starts only at the head of the queue)
  // otherwise spins for minutes on some tags. A timeout
  // lands in the same error state as a throw, with retry.
  Future<void> _loadFirst() async {
    try {
      final items = await widget.args.source
          .byTag(widget.tag.id, limit: _pageSize)
          .timeout(const Duration(seconds: 30));
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(items);
        _loading = false;
        _errorText = null;
        _nextPage = 2;
        _endOfList.reset();
        _loadMoreFailed = false;
        _hasMore = items.isNotEmpty;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (_items.isEmpty) _errorText = friendlyError(e);
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() {
      _loadingMore = true;
      _loadMoreFailed = false;
    });
    try {
      final items = await widget.args.source
          .byTag(
            widget.tag.id,
            limit: _pageSize,
            page: _nextPage,
          )
          .timeout(const Duration(seconds: 30));
      if (!mounted) return;
      final batch = nextMangaPageBatch(
        [for (final item in _items) item.storageKey],
        items,
      );
      setState(() {
        _items.addAll(batch.additions);
        _hasMore = _endOfList.record(
          addedNew: batch.additions.isNotEmpty,
        );
        _nextPage++;
      });
    } catch (_) {
      // Keep what's on screen; the footer offers the retry.
      if (mounted) setState(() => _loadMoreFailed = true);
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final columns = GStorage.getSetting(SettingsKeys.mangaGridColumns);
    return Scaffold(
      appBar: AppBar(title: Text(widget.tag.name)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty && _errorText != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(32, 0, 32, 12),
                        child: Text(
                          _errorText!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _loading = true;
                            _errorText = null;
                          });
                          _loadFirst();
                        },
                        child: const Text('加载失败，点这里重试'),
                      ),
                    ],
                  ),
                )
              : _items.isEmpty
              ? const Center(child: Text('这个分类下暂时没有漫画'))
              : NotificationListener<ScrollNotification>(
                  onNotification: (notification) {
                    // Batch 16: prefetch the next page before the
                    // end (was a manual button only).
                    if (_hasMore &&
                        !_loadingMore &&
                        notification.metrics.pixels >=
                            notification.metrics.maxScrollExtent - 320) {
                      _loadMore();
                    }
                    return false;
                  },
                  child: GridView.builder(
                  scrollCacheExtent: const ScrollCacheExtent.pixels(500),
                  padding: const EdgeInsets.fromLTRB(
                    StyleString.pagePadding,
                    12,
                    StyleString.pagePadding,
                    StyleString.sectionSpace,
                  ),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    mainAxisSpacing: 14,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.52,
                  ),
                  itemCount: _items.length +
                      ((_hasMore ||
                              _loadingMore ||
                              _loadMoreFailed ||
                              _items.length >= _pageSize)
                          ? 1
                          : 0),
                  itemBuilder: (context, index) {
                    if (index == _items.length) {
                      if (_loadingMore) {
                        return const Center(
                          child: CircularProgressIndicator(),
                        );
                      }
                      if (_loadMoreFailed) {
                        return Center(
                          child: OutlinedButton(
                            onPressed: _loadMore,
                            child: const Text('加载失败，点按重试'),
                          ),
                        );
                      }
                      return Center(
                        child: Text(
                          _hasMore ? '继续下滑自动加载' : '没有更多了',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                        ),
                      );
                    }
                    final item = _items[index];
                    return MangaRailCard(
                      item: item,
                      width: double.infinity,
                      onTap: () => context.pushNamed(
                        '/manga/detail',
                        arguments: item,
                      ),
                    );
                  },
                  ),
                ),
    );
  }
}
