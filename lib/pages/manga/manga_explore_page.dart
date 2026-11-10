import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_modular/flutter_modular.dart';
import 'package:anikumo/modules/manga/manga_item.dart';
import 'package:skeletonizer/skeletonizer.dart';
import 'package:anikumo/bean/theme/violet_glass.dart';
import 'package:anikumo/bean/widget/empty_state_widget.dart';
import 'package:anikumo/pages/manga/manga_widgets.dart';
import 'package:anikumo/services/manga/manga_api.dart';
import 'package:anikumo/services/manga/manga_search_utils.dart';
import 'package:anikumo/services/manga/manga_source.dart';
import 'package:anikumo/services/manga/manga_sources.dart';
import 'package:anikumo/services/storage/storage.dart';
import 'package:anikumo/utils/constants.dart';
import 'package:anikumo/utils/error_message.dart';
import 'package:anikumo/bean/widget/anikumo_icons.dart';

void _noop() {}

/// 探索 tab — browse manga catalogues. Batch 37: this used
/// to follow ONLY the active source (behind a hardcoded
/// "MangaDex" label, which confused everyone). Now every
/// installed source gets a chip and the grid switches freely
/// between them; the selection is local to this tab and does
/// not change the zone's active source.
class MangaExploreTab extends StatefulWidget {
  const MangaExploreTab({super.key});

  @override
  State<MangaExploreTab> createState() => _MangaExploreTabState();
}

class _MangaExploreTabState extends State<MangaExploreTab> {
  String? _sourceId;

  /// Batch 47: sources whose grid failed in this session
  /// sink to the end of the chip row, badged 不可用, until
  /// one of their loads succeeds again — the fold-away the
  /// novel home got in batch 46, in chip form.
  final Set<String> _failedIds = {};

  void _onGridAvailability(String sourceId, bool ok) {
    if (ok) {
      if (_failedIds.remove(sourceId) && mounted) setState(() {});
    } else {
      if (_failedIds.add(sourceId) && mounted) setState(() {});
    }
  }

  @override
  void initState() {
    super.initState();
    _sourceId = MangaSources.activeOrNull()?.id ?? '';
    MangaSources.revision.addListener(_onRevision);
  }

  @override
  void dispose() {
    MangaSources.revision.removeListener(_onRevision);
    super.dispose();
  }

  void _onRevision() {
    if (!mounted) return;
    // Keep the local selection while it still exists; the
    // grid itself does not reload on global source changes.
    final all = MangaSources.all();
    if (!all.any((s) => s.id == _sourceId)) {
      setState(() => _sourceId = MangaSources.activeOrNull()?.id ?? '');
    } else {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Batch 59: with no imported sources there is nothing
    // to explore — show the import prompt instead of
    // dereferencing an active source that does not exist.
    if (MangaSources.all().isEmpty) {
      return SafeArea(
        bottom: false,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  AnikumoIcons.extension_off_rounded,
                  size: 44,
                  color: theme.colorScheme.outline,
                ),
                const SizedBox(height: 14),
                Text(
                  '还没有漫画源',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(
                  '用你自己的 URL 链接导入 JS 源后即可探索。',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => context.pushNamed('/manga/sources'),
                  icon: const Icon(AnikumoIcons.add_link_rounded, size: 18),
                  label: const Text('去导入漫画源'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    // Batch 47: pinned first, failed sources last.
    final pinnedFirst = MangaSources.sortForDisplay(MangaSources.all());
    final all = [
      for (final s in pinnedFirst)
        if (!_failedIds.contains(s.id)) s,
      for (final s in pinnedFirst)
        if (_failedIds.contains(s.id)) s,
    ];
    final activeId = MangaSources.activeOrNull()?.id ?? '';
    final selected = all.firstWhere(
      (s) => s.id == _sourceId,
      orElse: () => MangaSources.active(),
    );
    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 2),
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
                  '探索',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView.separated(
        scrollCacheExtent: const ScrollCacheExtent.pixels(700),
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: all.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final source = all[index];
                final isSelected = source.id == selected.id;
                final failed = _failedIds.contains(source.id);
                return ChoiceChip(
                  avatar: failed
                      ? Icon(
                          AnikumoIcons.cloud_off,
                          size: 14,
                          color: theme.colorScheme.error,
                        )
                      : null,
                  label: Text(
                    failed
                        ? '${source.name} · 不可用'
                        : source.id == activeId
                            ? '${source.name} · 当前源'
                            : source.name,
                  ),
                  selected: isSelected,
                  onSelected: (_) =>
                      setState(() => _sourceId = source.id),
                );
              },
            ),
          ),
          Expanded(
            child: MangaSourceGrid(
              key: ValueKey('explore-${selected.id}'),
              source: selected,
              onAvailability: _onGridAvailability,
            ),
          ),
        ],
      ),
    );
  }
}

/// The full-catalogue page for ONE source — where the home
/// sections' 「更多」 lands. Same paged grid as the explore
/// tab, bound to a fixed source.
class MangaSourcePage extends StatelessWidget {
  const MangaSourcePage({super.key, required this.sourceId});

  final String sourceId;

  @override
  Widget build(BuildContext context) {
    final source = MangaSources.byId(sourceId);
    if (source == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('这个源已经不存在了')),
      );
    }
    final isActive = MangaSources.activeOrNull()?.id == source.id;
    return Scaffold(
      appBar: AppBar(
        title: Text(source.name),
        actions: [
          if (!isActive)
            TextButton(
              onPressed: () => MangaSources.setActive(source.id),
              child: const Text('切换到此源'),
            ),
        ],
      ),
      body: MangaSourceGrid(source: source),
    );
  }
}

/// Paged popular grid for one source: disk snapshot first,
/// then network; failures surface the real reason with a
/// retry when the grid is empty (batch 27's rule, kept).
class MangaSourceGrid extends StatefulWidget {
  const MangaSourceGrid({super.key, required this.source, this.onAvailability});

  final MangaSource source;

  /// Batch 47: reports the first load's verdict (false =
  /// failed with nothing to show) so the explore tab can
  /// sink a dead source's chip to the end of the row.
  final void Function(String sourceId, bool ok)? onAvailability;

  @override
  State<MangaSourceGrid> createState() => _MangaSourceGridState();
}

class _MangaSourceGridState extends State<MangaSourceGrid> {
  static const _pageSize = 24;
  final List<MangaItem> _items = [];
  final ScrollController _scrollController = ScrollController();
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  // Batch 188: two consecutive dud pages end the list,
  // not one (see MangaEndOfList).
  final _endOfList = MangaEndOfList();
  bool _loadMoreFailed = false;
  String? _errorText;

  /// Batch 90: the next page to fetch, tracked explicitly.
  /// Deriving it from the item count broke whenever a
  /// source's own page size differed from ours (a 20-per-page
  /// source landed back on page 1 and repeated itself).
  int _nextPage = 2;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    final snap = MangaApi.popularSnapshot(
      widget.source,
      limit: _pageSize,
    );
    if (snap != null) {
      // Batch 90: even the instant snapshot paint is
      // shuffled — every entry into explore looks fresh.
      _items.addAll(shuffledMangaItems(snap.items));
      _loading = false;
    }
    _loadFirst();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  /// Batch 90: approaching the bottom loads the next page
  /// automatically — no manual 「加载更多」 tap.
  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 800) {
      _loadMore();
    }
  }

  Future<void> _loadFirst({bool fresh = false}) async {
    try {
      final items = await MangaApi.fetchPopularFor(
        widget.source,
        limit: _pageSize,
        fresh: fresh,
      );
      if (!mounted) return;
      setState(() {
        // Batch 90: shuffled on entry and on every manual
        // refresh — the catalogue order is the site's, the
        // discovery order is ours.
        _items
          ..clear()
          ..addAll(shuffledMangaItems(items));
        _loading = false;
        _errorText = null;
        _nextPage = 2;
        _endOfList.reset();
        _loadMoreFailed = false;
        // Only an EMPTY first page proves there is nothing
        // more; a short page is just the source's page size.
        _hasMore = items.isNotEmpty;
      });
      widget.onAvailability?.call(widget.source.id, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (_items.isEmpty) _errorText = friendlyError(e);
      });
      if (_items.isEmpty) {
        widget.onAvailability?.call(widget.source.id, false);
      }
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || !_hasMore) return;
    setState(() {
      _loadingMore = true;
      _loadMoreFailed = false;
    });
    try {
      final items = await MangaApi.fetchPopularFor(
        widget.source,
        limit: _pageSize,
        page: _nextPage,
      );
      if (!mounted) return;
      final batch = nextMangaPageBatch(
        [for (final item in _items) item.storageKey],
        items,
      );
      setState(() {
        _items.addAll(shuffledMangaItems(batch.additions));
        _hasMore = _endOfList.record(
          addedNew: batch.additions.isNotEmpty,
        );
        _nextPage++;
      });
    } catch (_) {
      // Keep what's on screen; the footer offers the retry
      // and scrolling away/back re-triggers the auto-load.
      if (mounted) setState(() => _loadMoreFailed = true);
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  bool get _footerVisible =>
      _hasMore ||
      _loadingMore ||
      _loadMoreFailed ||
      _items.length >= _pageSize;

  Widget _footer(ThemeData theme) {
    if (_loadingMore) return const CircularProgressIndicator();
    if (_loadMoreFailed) {
      return OutlinedButton(
        onPressed: _loadMore,
        child: const Text('加载失败，点按重试'),
      );
    }
    final style = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    if (!_hasMore) return Text('没有更多了', style: style);
    return Text('继续下滑自动加载', style: style);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final columns = GStorage.getSetting(SettingsKeys.mangaGridColumns);
    if (_loading) {
      return Skeletonizer.zone(
        child: GridView.builder(
        scrollCacheExtent: const ScrollCacheExtent.pixels(700),
          padding: const EdgeInsets.fromLTRB(
            StyleString.pagePadding,
            8,
            StyleString.pagePadding,
            StyleString.sectionSpace,
          ),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 14,
            crossAxisSpacing: 12,
            childAspectRatio: 0.52,
          ),
          itemCount: columns * 4,
          itemBuilder: (context, index) => const MangaRailCard(
            item: MangaItem(
              id: '',
              title: '加载中的漫画标题样本',
              description: '',
              coverUrl: '',
              author: '',
              status: 'ongoing',
              year: null,
              tags: [],
            ),
            width: double.infinity,
            onTap: _noop,
          ),
        ),
      );
    }
    if (_items.isEmpty) {
      // Batch 97: the empty/failed state joins the refresh
      // system too — it used to be the one part of this page
      // a pull could not reach (no scrollable at all), and
      // its retry button did not bypass the TTL memo.
      return LayoutBuilder(
        builder: (context, constraints) => RefreshIndicator(
          onRefresh: () => _loadFirst(fresh: true),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: SizedBox(
              height: constraints.maxHeight,
              child: GeneralEmptyState(
                icon: AnikumoIcons.cloud_off_rounded,
                title: _errorText != null ? '加载失败' : '这个源暂时没有内容',
                actions: [
                  if (_errorText != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(32, 0, 32, 4),
                      child: Text(
                        _errorText!,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ),
                  FilledButton.tonal(
                    onPressed: () {
                      setState(() {
                        _loading = true;
                        _errorText = null;
                      });
                      _loadFirst(fresh: true);
                    },
                    child: const Text('重试'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return RefreshIndicator(
      // Batch 90: a manual refresh bypasses the TTL memo,
      // so it is a real refresh (and reshuffles on arrival).
      onRefresh: () => _loadFirst(fresh: true),
      child: GridView.builder(
        controller: _scrollController,
        // Batch 97: with fewer items than a screenful the
        // grid is not scrollable under the default physics,
        // and the pull gesture silently does nothing — one
        // of the "部分不刷新" cases.
        physics: const AlwaysScrollableScrollPhysics(),
        scrollCacheExtent: const ScrollCacheExtent.pixels(700),
        padding: const EdgeInsets.fromLTRB(
          StyleString.pagePadding,
          8,
          StyleString.pagePadding,
          StyleString.sectionSpace,
        ),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          mainAxisSpacing: 14,
          crossAxisSpacing: 12,
          childAspectRatio: 0.52,
        ),
        itemCount: _items.length + (_footerVisible ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == _items.length) {
            return Center(child: _footer(theme));
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
    );
  }
}
