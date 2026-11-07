import 'package:anikumo/bean/widget/empty_state_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_modular/flutter_modular.dart';

import '../../models/novel_item.dart';
import '../../services/novel/novel_source.dart';
import '../../services/novel/novel_sources.dart';
import 'novel_widgets.dart';

/// Args for the /novel/category route.
typedef NovelCategoryArgs = ({
  String sourceId,
  NovelExploreCategory category,
});

/// Explore tab: the active source's categories as chips
/// over a paging grid.
class NovelExploreTab extends StatefulWidget {
  const NovelExploreTab({super.key});

  @override
  State<NovelExploreTab> createState() => _NovelExploreTabState();
}

class _NovelExploreTabState extends State<NovelExploreTab> {
  int _categoryIndex = 0;

  @override
  void initState() {
    super.initState();
    NovelSources.revision.addListener(_onRevision);
  }

  @override
  void dispose() {
    NovelSources.revision.removeListener(_onRevision);
    super.dispose();
  }

  void _onRevision() {
    if (mounted) setState(() => _categoryIndex = 0);
  }

  @override
  Widget build(BuildContext context) {
    final source = NovelSources.activeOrNull();
    if (source == null) {
      // Batch 59: no sources imported yet — an import
      // prompt, not an endless spinner.
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text('还没有书源。到「书源」页签用你自己的 URL 链接导入后即可探索。'),
        ),
      );
    }
    final categories = source.exploreCategories;
    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          NovelSectionHeader(title: '探索 · ${source.name}'),
          if (categories.isEmpty)
            const Expanded(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Text('这个源没有发现分类，用搜索找书吧'),
                ),
              ),
            )
          else ...[
            SizedBox(
              height: 40,
              child: ListView.separated(
        scrollCacheExtent: const ScrollCacheExtent.pixels(700),
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: categories.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) => ChoiceChip(
                  label: Text(categories[index].title),
                  selected: index == _categoryIndex,
                  onSelected: (_) =>
                      setState(() => _categoryIndex = index),
                ),
              ),
            ),
            Expanded(
              child: NovelBookGrid(
                key: ValueKey(
                  'explore-${source.id}-${categories[_categoryIndex].url}',
                ),
                source: source,
                category: categories[_categoryIndex],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The /novel/category page: one source category as a grid.
class NovelCategoryPage extends StatelessWidget {
  const NovelCategoryPage({super.key, required this.args});

  final NovelCategoryArgs args;

  @override
  Widget build(BuildContext context) {
    final source = NovelSources.byId(args.sourceId);
    return Scaffold(
      appBar: AppBar(title: Text(args.category.title)),
      body: source == null
          ? const GeneralEmptyState(
              icon: Icons.find_in_page_outlined,
              title: '书源不存在',
            )
          : NovelBookGrid(source: source, category: args.category),
    );
  }
}

/// A paging book grid for one (source, category) with the
/// batch-27 failure contract: errors surface with a reason
/// and a retry; a failed load-more keeps what's on screen.
class NovelBookGrid extends StatefulWidget {
  const NovelBookGrid({
    super.key,
    required this.source,
    required this.category,
  });

  final NovelSource source;
  final NovelExploreCategory category;

  @override
  State<NovelBookGrid> createState() => _NovelBookGridState();
}

class _NovelBookGridState extends State<NovelBookGrid> {
  final List<NovelItem> _items = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _errorText;
  int _page = 1;

  @override
  void initState() {
    super.initState();
    _loadFirst();
  }

  Future<void> _loadFirst() async {
    setState(() {
      _loading = true;
      _errorText = null;
    });
    try {
      final items = await widget.source.explore(widget.category, page: 1);
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(items);
        _page = 1;
        _loading = false;
        _hasMore = items.isNotEmpty;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorText = e.toString();
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final items = await widget.source.explore(
        widget.category,
        page: _page + 1,
      );
      if (!mounted) return;
      setState(() {
        _items.addAll(items);
        _page++;
        _hasMore = items.isNotEmpty;
      });
    } catch (_) {
      // Keep what's on screen; scrolling can retry.
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_items.isEmpty) {
      if (_errorText != null) {
        return NovelErrorState(message: _errorText!, onRetry: _loadFirst);
      }
      return const GeneralEmptyState(
        icon: Icons.inbox_rounded,
        title: '这个分类暂时没有内容',
      );
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.metrics.pixels >=
            notification.metrics.maxScrollExtent - 400) {
          _loadMore();
        }
        return false;
      },
      child: RefreshIndicator(
        onRefresh: _loadFirst,
        child: GridView.builder(
        scrollCacheExtent: const ScrollCacheExtent.pixels(700),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          // Batch 73: columns follow the width (same
          // 3/5/6 ladder as the cross-search grids) — the
          // fixed 3-across layout turned landscape into
          // three oversized cards.
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: () {
              final width = MediaQuery.sizeOf(context).width;
              return width < 600 ? 3 : (width < 900 ? 5 : 6);
            }(),
            mainAxisSpacing: 16,
            crossAxisSpacing: 12,
            childAspectRatio: 0.52,
          ),
          itemCount: _items.length,
          itemBuilder: (context, index) => NovelRailCard(
            item: _items[index],
            width: double.infinity,
          ),
        ),
      ),
    );
  }
}


/// The /novel/source page (batch 37): one source's whole
/// catalogue at a glance — every explore category as its own
/// rail. Where the home sections' 「更多」 lands; the home
/// section itself only ever shows the selected category.
class NovelSourcePage extends StatelessWidget {
  const NovelSourcePage({super.key, required this.sourceId});

  final String sourceId;

  @override
  Widget build(BuildContext context) {
    final source = NovelSources.byId(sourceId);
    if (source == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const GeneralEmptyState(
          icon: Icons.find_in_page_outlined,
          title: '书源不存在',
        ),
      );
    }
    final isActive = NovelSources.activeOrNull()?.id == source.id;
    final categories = source.exploreCategories;
    return Scaffold(
      appBar: AppBar(
        title: Text(source.name),
        actions: [
          if (!isActive)
            TextButton(
              onPressed: () => NovelSources.setActive(source.id),
              child: const Text('切换到此源'),
            ),
        ],
      ),
      body: categories.isEmpty
          ? const GeneralEmptyState(
              icon: Icons.explore_off_rounded,
              title: '这个源没有发现分类，用搜索找书吧',
            )
          : ListView.builder(
        scrollCacheExtent: const ScrollCacheExtent.pixels(700),
              padding: const EdgeInsets.only(bottom: 24),
              itemCount: categories.length,
              itemBuilder: (context, index) => _NovelCategoryRail(
                source: source,
                category: categories[index],
              ),
            ),
    );
  }
}

/// One category rail on the source hub page: loads page 1
/// independently; failures stay local to the rail.
class _NovelCategoryRail extends StatefulWidget {
  const _NovelCategoryRail({required this.source, required this.category});

  final NovelSource source;
  final NovelExploreCategory category;

  @override
  State<_NovelCategoryRail> createState() => _NovelCategoryRailState();
}

class _NovelCategoryRailState extends State<_NovelCategoryRail> {
  List<NovelItem>? _items;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await widget.source.explore(widget.category);
      if (mounted) setState(() => _items = items);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        NovelSectionHeader(
          title: widget.category.title,
          trailing: TextButton(
            onPressed: () => context.pushNamed(
              '/novel/category',
              arguments: (
                sourceId: widget.source.id,
                category: widget.category,
              ),
            ),
            child: const Text('全部'),
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _error!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    setState(() => _error = null);
                    _load();
                  },
                  child: const Text('重试'),
                ),
              ],
            ),
          )
        else if (_items == null)
          const SizedBox(
            height: 120,
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_items!.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Text('这个分类暂时没有内容'),
          )
        else
          SizedBox(
            height: 218,
            child: ListView.separated(
        scrollCacheExtent: const ScrollCacheExtent.pixels(700),
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _items!.length.clamp(0, 14),
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, index) =>
                  NovelRailCard(item: _items![index]),
            ),
          ),
      ],
    );
  }
}
