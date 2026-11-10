import 'dart:async';
import 'dart:ui' as ui;

import 'package:anikumo/bean/dialog/dialog_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:anikumo/utils/error_message.dart';
import 'package:anikumo/bean/widget/floating_capsule_nav.dart';
import 'package:anikumo/bean/widget/zone_switcher.dart';
import 'package:anikumo/bean/widget/empty_state_widget.dart';
import 'package:anikumo/bean/widget/violet_components.dart';
import 'package:flutter/services.dart';
import 'package:flutter_modular/flutter_modular.dart';

import '../../models/novel_item.dart';
import 'novel_cabinets_page.dart';
import '../../services/novel/novel_features.dart';
import '../../services/novel/novel_library.dart';
import '../../services/novel/moyuan_host.dart';
import '../../services/novel/novel_source.dart';
import '../../services/novel/novel_sources.dart';
import '../../services/ui/app_extras.dart';
import 'package:anikumo/bean/theme/violet_glass.dart';
import '../../services/storage/storage.dart';
import 'novel_explore_tab.dart';
import 'novel_sources_tab.dart';
import 'novel_widgets.dart';
import 'package:anikumo/bean/widget/anikumo_icons.dart';

/// The 小说专区 shell: five tabs over a cross-fading stack
/// (same construction as the manga zone — lazy mount, no
/// TickerMode, state and scroll survive switches).
class NovelMainPage extends StatefulWidget {
  const NovelMainPage({super.key});

  @override
  State<NovelMainPage> createState() => _NovelMainPageState();
}

class _NovelMainPageState extends State<NovelMainPage> {
  @override
  void initState() {
    super.initState();
    // Batch 192: warm the novel engine shortly after the
    // zone's first frame settles — the first search used
    // to pay the whole engine startup on the tap itself.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future<void>.delayed(const Duration(milliseconds: 400),
          () async {
        try {
          await MoyuanHost.instance.ensureStarted();
          await MoyuanHost.instance.syncSourcesIfChanged();
        } catch (_) {
          // Warm-up is best-effort; real calls retry.
        }
      });
    });
  }

  int _index = 0;
  final Set<int> _visited = {0};

  late final _tabs = const [
    NovelHomeTab(),
    NovelFavoritesTab(),
    // Batch 124: the cabinets tab, mirroring the manga zone.
    NovelCabinetsTab(),
    NovelExploreTab(),
    NovelSourcesTab(),
    NovelSettingsTab(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          for (var i = 0; i < _tabs.length; i++)
            if (!_visited.contains(i))
              const SizedBox.shrink()
            else
              IgnorePointer(
                ignoring: i != _index,
                child: Opacity(
                  opacity: i == _index ? 1 : 0,
                  // Batch 49 (was 32): the tab switch used to
                  // fade this cached layer over 220ms; on the
                  // user's device the full-screen blend still
                  // read as a hitch, so switching is instant
                  // now. The RepaintBoundary stays.
                  child: RepaintBoundary(child: _tabs[i]),
                ),
              ),
        ],
      ),
      bottomNavigationBar: FloatingCapsuleNavBar(
        selectedIndex: _index,
        onDestinationSelected: (index) {
          HapticFeedback.selectionClick();
          setState(() {
            _index = index;
            _visited.add(index);
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(AnikumoIcons.home_outlined),
            selectedIcon: Icon(AnikumoIcons.home),
            label: '首页',
          ),
          NavigationDestination(
            icon: Icon(AnikumoIcons.bookmark_outline),
            selectedIcon: Icon(AnikumoIcons.bookmark),
            label: '收藏',
          ),
          NavigationDestination(
            icon: Icon(AnikumoIcons.auto_stories_outlined),
            selectedIcon: Icon(AnikumoIcons.auto_stories),
            label: '书柜',
          ),
          NavigationDestination(
            icon: Icon(AnikumoIcons.explore_outlined),
            selectedIcon: Icon(AnikumoIcons.explore),
            label: '探索',
          ),
          NavigationDestination(
            icon: Icon(AnikumoIcons.library_books_outlined),
            selectedIcon: Icon(AnikumoIcons.library_books),
            label: '书源',
          ),
          NavigationDestination(
            icon: Icon(AnikumoIcons.settings_outlined),
            selectedIcon: Icon(AnikumoIcons.settings),
            label: '设置',
          ),
        ],
      ),
    );
  }
}

/// Home: continue reading, favorites, and one explore
/// section per source that declares categories.
class NovelHomeTab extends StatefulWidget {
  const NovelHomeTab({super.key});

  @override
  State<NovelHomeTab> createState() => _NovelHomeTabState();
}

class _NovelHomeTabState extends State<NovelHomeTab> {
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
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = NovelLibraryStore.loadProgressList();
    final favorites = NovelLibraryStore.loadFavorites();
    final sources = NovelSources.all();
    return SafeArea(
      bottom: false,
      child: ListView(
        scrollCacheExtent: const ScrollCacheExtent.pixels(700),
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: Row(
              children: [
                // Batch 32: an explicit way back to the anime
                // zone (the zones are pushed routes; users
                // asked for a visible exit, not just system
                // back).
                IconButton(
                  tooltip: '返回动漫区',
                  icon: const Icon(AnikumoIcons.arrow_back_rounded),
                  onPressed: () => context.pop(),
                ),
                // Batch 131: the zone's own title is the
                // switcher entry (with the swap glyph as its
                // affordance), same idea as the anime zone's
                // ANIME mark.
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () =>
                        showZoneSwitcher(context, current: AppZone.novel),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '小说',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Icon(
                          AnikumoIcons.unfold_more_rounded,
                          size: 17,
                          color: theme.colorScheme.outline,
                        ),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '搜索小说',
                  icon: const Icon(AnikumoIcons.search),
                  onPressed: () => context.pushNamed('/novel/search'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
            child: VioletSearchPill(
              hint: '搜索小说',
              onTap: () => context.pushNamed('/novel/search'),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              '当前源 ${sources.isEmpty ? '—' : NovelSources.active().name}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ),
          // Batch 42: the swipeable featured carousel the
          // manga home has had since batch 38 — the novel
          // home gets the same top slot, fed by the active
          // source's first explore category.
          if (sources.isNotEmpty) const _NovelFeaturedBanner(),
          if (progress.isNotEmpty) ...[
            const NovelSectionHeader(title: '继续阅读'),
            SizedBox(
              height: 218,
              child: ListView.separated(
        scrollCacheExtent: const ScrollCacheExtent.pixels(700),
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: progress.length.clamp(0, 12),
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (context, index) =>
                    NovelRailCard(item: progress[index].item),
              ),
            ),
          ],
          if (favorites.isNotEmpty) ...[
            const NovelSectionHeader(title: '我的收藏'),
            SizedBox(
              height: 218,
              child: ListView.separated(
        scrollCacheExtent: const ScrollCacheExtent.pixels(700),
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: favorites.length.clamp(0, 12),
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (context, index) =>
                    NovelRailCard(item: favorites[index]),
              ),
            ),
          ],
          // Batch 46: pinned sources first; dead sources'
          // sections hide themselves (see _SourceSection) —
          // counted here for the slim hint below.
          for (final source in NovelSources.sortForDisplay(sources))
            if (source.exploreCategories.isNotEmpty)
              _SourceSection(
                key: ValueKey('novel-section-${source.id}'),
                source: source,
              ),
          // Batch 65: sources without explore categories
          // (search-only sources — common in real bundles)
          // used to be completely ABSENT from the home, so
          // the page looked like it only had the handful of
          // sources that declare explore sections. They get
          // a slim presence row instead: name + a way in.
          for (final source in NovelSources.sortForDisplay(sources))
            if (source.exploreCategories.isEmpty &&
                !NovelSources.isDead(source.id))
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 2, 8, 2),
                child: Row(
                  children: [
                    Icon(
                      AnikumoIcons.menu_book_outlined,
                      size: 18,
                      color: theme.colorScheme.outline,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${source.name} · 该源没有发现分类，用搜索找书',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                    TextButton(
                      onPressed: () => context.pushNamed(
                        '/novel/source',
                        arguments: source.id,
                      ),
                      child: const Text('进入'),
                    ),
                  ],
                ),
              ),
          if (sources.any((s) => NovelSources.isDead(s.id)))
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text(
                '已隐藏 ${sources.where((s) => NovelSources.isDead(s.id)).length} 个失效书源'
                '（在「书源」页可清理或等待自动恢复）',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ),
          // Batch 61: zero sources used to render an endless
          // spinner here (the batch-59 pass fixed the explore
          // tab but missed the home tab — the user's screenshot
          // showed this page spinning forever). Show the import
          // prompt instead, same wording family as explore.
          if (sources.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 56, 24, 32),
              child: GeneralEmptyState(
                icon: AnikumoIcons.menu_book_outlined,
                title: '还没有书源',
                actions: [
                  Text(
                    '到下方「书源」页签，用你自己的 URL 链接导入后，'
                    '这里就会有书看了',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// One source's explore section on the home tab: category
/// chips + a horizontal rail, loading independently with
/// its own failure state (batch-27 pattern).
/// Batch 52: shared gate for home-section explore loads.
/// With dozens of sources installed, every section that
/// scrolls into the cache extent used to start its fetch at
/// once — a burst of network + JS evaluation + cover
/// decodes that stutters the whole zone while scrolling.
/// At most three section loads run at a time now; the rest
/// queue in build order (roughly scroll order). A section
/// load is also capped at 20s so dead sources cannot hold
/// a gate slot hostage — a timeout is a soft error (retry
/// row), never a dead-source strike.
/// Batch 65: concurrency 3 → 5 and a session cache below —
/// with many sources installed, later sections waited
/// behind two or three 20s timeouts and the home looked
/// stuck on the first three sources.
class _SectionLoadGate {
  _SectionLoadGate._();

  static int _inFlight = 0;
  static final List<Completer<void>> _waiters = [];

  static Future<void> acquire() {
    if (_inFlight < 5) {
      _inFlight++;
      return Future<void>.value();
    }
    final completer = Completer<void>();
    _waiters.add(completer);
    return completer.future;
  }

  static void release() {
    if (_waiters.isNotEmpty) {
      _waiters.removeAt(0).complete();
    } else if (_inFlight > 0) {
      _inFlight--;
    }
  }
}

/// Batch 65: session cache for home explore fetches. The
/// featured banner and the active source's section used to
/// fetch the SAME first category independently, and every
/// home rebuild re-fetched everything — on slow JS sources
/// the home felt permanently "loading". One in-flight
/// future per (source, category) is shared, and successful
/// results are reused for two minutes. Failures are not
/// cached (the section retry path must really retry).
class _HomeExploreCache {
  _HomeExploreCache._();

  static final Map<String, Future<List<NovelItem>>> _pending = {};
  static final Map<String, (DateTime, List<NovelItem>)> _done = {};

  static Future<List<NovelItem>> fetch(
    NovelSource source,
    NovelExploreCategory category,
  ) {
    final key = '${source.id}|${category.title}|${category.url}';
    final hit = _done[key];
    if (hit != null &&
        DateTime.now().difference(hit.$1) <
            const Duration(minutes: 2)) {
      return Future.value(hit.$2);
    }
    final running = _pending[key];
    if (running != null) return running;
    final future = source.explore(category).then((items) {
      _done[key] = (DateTime.now(), items);
      return items;
    }).whenComplete(() => _pending.remove(key));
    _pending[key] = future;
    return future;
  }
}

class _SourceSection extends StatefulWidget {
  const _SourceSection({super.key, required this.source});

  final NovelSource source;

  @override
  State<_SourceSection> createState() => _SourceSectionState();
}

class _SourceSectionState extends State<_SourceSection> {
  int _categoryIndex = 0;

  /// Batch 46: a failed section collapses to one slim row
  /// (name + reason + retry / expand) instead of the tall
  /// header + chips + error block. Expanding restores the
  /// full section so other categories stay reachable.
  bool _userExpanded = false;

  /// Batch 36: category switching used to reload the whole
  /// section on every tap — spinner replaced the rail, no
  /// caching, and a slow earlier load could land after a
  /// later tap and show the wrong category's books. Now:
  /// results are cached per category (switching back is
  /// instant), switching keeps the current rail on screen
  /// while the new category loads (thin progress line), and
  /// completions only touch the visible rail when their
  /// category is still the selected one — taps can fly.
  final Map<int, List<NovelItem>> _cache = {};
  final Map<int, String> _errors = {};
  final Set<int> _inFlight = {};
  List<NovelItem> _items = const [];

  /// Batch 173: fetchable categories only — group header
  /// kinds carry no URL and are skipped on this surface.
  List<NovelExploreCategory> get _itemsOnly => [
        for (final c in widget.source.exploreCategories)
          if (!c.isHeader) c,
      ];

  @override
  void initState() {
    super.initState();
    // Batch 173: script-declared categories resolve
    // asynchronously; restart clean once they land.
    widget.source.ensureExploreKinds();
    NovelSource.kindsRevision.addListener(_onKindsResolved);
    _ensure(0);
  }

  @override
  void dispose() {
    NovelSource.kindsRevision.removeListener(_onKindsResolved);
    super.dispose();
  }

  void _onKindsResolved() {
    if (!mounted || !widget.source.exploreKindsResolved) return;
    _cache.clear();
    _errors.clear();
    _inFlight.clear();
    _items = const [];
    _categoryIndex = 0;
    setState(() {});
    _ensure(0);
  }

  Future<void> _ensure(int index) async {
    if (!widget.source.exploreKindsResolved) return;
    if (_cache.containsKey(index) || _inFlight.contains(index)) {
      return;
    }
    final categories = _itemsOnly;
    if (index < 0 || index >= categories.length) return;
    _inFlight.add(index);
    if (mounted) setState(() {});
    await _SectionLoadGate.acquire();
    try {
      final items = await _HomeExploreCache.fetch(
        widget.source,
        categories[index],
      ).timeout(const Duration(seconds: 20));
      _cache[index] = items;
      _errors.remove(index);
      if (index == _categoryIndex) _items = items;
      // Batch 42: a source that answers again is not dead.
      if (NovelSources.isDead(widget.source.id)) {
        NovelSources.clearDead(widget.source.id);
      }
    } catch (e) {
      _errors[index] = friendlyError(e);
      // Batch 42/46: hard failures (dead domain, site
      // refusal 4xx/5xx, TLS/socket death) are recorded —
      // the sources tab badges the source, the home tab
      // hides it, and auto-delete may remove it after a
      // second strike. Timeouts never mark.
      if (NovelSources.isHardDeadError(e.toString())) {
        NovelSources.recordDead(widget.source.id);
      }
    } finally {
      _SectionLoadGate.release();
      _inFlight.remove(index);
      if (mounted) setState(() {});
    }
  }

  void _select(int index) {
    if (index == _categoryIndex) return;
    setState(() {
      _categoryIndex = index;
      final cached = _cache[index];
      if (cached != null) _items = cached;
    });
    _ensure(index);
  }

  void _retry() {
    _errors.remove(_categoryIndex);
    _cache.remove(_categoryIndex);
    setState(() {});
    _ensure(_categoryIndex);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final categories = _itemsOnly;
    final selectedError = _errors[_categoryIndex];
    final loadingSelected = _inFlight.contains(_categoryIndex);
    final selectedLoaded = _cache.containsKey(_categoryIndex);
    // Batch 46: dead sources hide from the home tab
    // entirely (they stay visible, badged, in 书源).
    if (NovelSources.isDead(widget.source.id)) {
      return const SizedBox.shrink();
    }
    // Batch 173: dynamic categories still resolving —
    // a slim loading row instead of fetching the bogus
    // static entry.
    if (!widget.source.exploreKindsResolved) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          NovelSectionHeader(title: widget.source.name),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: LinearProgressIndicator(minHeight: 2),
          ),
        ],
      );
    }
    // Batch 46: failed with nothing to show -> one slim
    // collapsed row until the user expands it.
    if (selectedError != null && _items.isEmpty && !_userExpanded) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
        child: Row(
          children: [
            Icon(
              AnikumoIcons.cloud_off_outlined,
              size: 18,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(width: 8),
            Text(
              widget.source.name,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                selectedError,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
            TextButton(onPressed: _retry, child: const Text('重试')),
            IconButton(
              tooltip: '展开',
              icon: const Icon(AnikumoIcons.expand_more),
              onPressed: () => setState(() => _userExpanded = true),
            ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        NovelSectionHeader(
          title: widget.source.name,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(
                onPressed: () => context.pushNamed(
                  '/novel/source',
                  arguments: widget.source.id,
                ),
                child: const Text('更多'),
              ),
              TextButton(
                onPressed: categories.isEmpty
                    ? null
                    : () => context.pushNamed(
                          '/novel/category',
                          arguments: (
                            sourceId: widget.source.id,
                            category: categories[_categoryIndex.clamp(
                                0, categories.length - 1)],
                          ),
                        ),
                child: const Text('全部'),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 36,
          child: ListView.separated(
        scrollCacheExtent: const ScrollCacheExtent.pixels(700),
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: categories.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) => ChoiceChip(
              label: Text(categories[index].title),
              selected: index == _categoryIndex,
              onSelected: (_) => _select(index),
            ),
          ),
        ),
        if (loadingSelected)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 6, 16, 0),
            child: LinearProgressIndicator(minHeight: 2),
          ),
        const SizedBox(height: 8),
        if (selectedError != null && _items.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    selectedError,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
                TextButton(onPressed: _retry, child: const Text('重试')),
              ],
            ),
          )
        else if (_items.isEmpty && !selectedLoaded)
          const SizedBox(
            height: 120,
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_items.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text('这个分类暂时没有内容'),
          )
        else
          SizedBox(
            height: 218,
            child: ListView.separated(
        scrollCacheExtent: const ScrollCacheExtent.pixels(700),
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _items.length.clamp(0, 14),
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, index) =>
                  NovelRailCard(item: _items[index]),
            ),
          ),
        if (selectedError != null && _items.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    selectedError,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
                TextButton(onPressed: _retry, child: const Text('重试')),
              ],
            ),
          ),
      ],
    );
  }
}

/// Favorites tab: the bookshelf + reading history.
class NovelFavoritesTab extends StatefulWidget {
  const NovelFavoritesTab({super.key});

  @override
  State<NovelFavoritesTab> createState() => _NovelFavoritesTabState();
}

class _NovelFavoritesTabState extends State<NovelFavoritesTab> {
  /// Batch 98: browsing-history deletion for the novel
  /// zone — per-row delete and clear-all, both confirmed.
  Future<bool> _confirm(String title, String message) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _deleteHistory(NovelProgress entry) async {
    if (!await _confirm(
      '删除这条记录？',
      '将移除《${entry.item.title}》的阅读进度，此操作无法撤销。',
    )) {
      return;
    }
    await NovelLibraryStore.removeProgress(entry.item.storageKey);
    if (!mounted) return;
    setState(() {});
    AnikumoDialog.showToast(message: '已删除');
  }

  Future<void> _clearHistory(int count) async {
    if (!await _confirm(
      '清空全部阅读历史？',
      '将删除全部 $count 条小说阅读记录，此操作无法撤销。',
    )) {
      return;
    }
    await NovelLibraryStore.clearProgress();
    if (!mounted) return;
    setState(() {});
    AnikumoDialog.showToast(message: '阅读历史已清空');
  }

  @override
  Widget build(BuildContext context) {
    final favorites = NovelLibraryStore.loadFavorites();
    final progress = NovelLibraryStore.loadProgressList();
    return SafeArea(
      bottom: false,
      child: ListView(
        scrollCacheExtent: const ScrollCacheExtent.pixels(700),
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          const NovelSectionHeader(title: '我的收藏'),
          if (favorites.isEmpty)
            const GeneralEmptyState(
              icon: AnikumoIcons.collections_bookmark_outlined,
              title: '还没有收藏，去探索里找本书吧',
              compact: true,
            )
          else
            for (final item in favorites) NovelBookTile(item: item),
          NovelSectionHeader(
            title: '阅读历史',
            trailing: progress.isEmpty
                ? null
                : TextButton(
                    onPressed: () => _clearHistory(progress.length),
                    child: const Text('清空'),
                  ),
          ),
          if (progress.isEmpty)
            const GeneralEmptyState(
              icon: AnikumoIcons.history_rounded,
              title: '暂无阅读记录',
              compact: true,
            )
          else
            for (final entry in progress)
              NovelBookTile(
                item: entry.item,
                subtitle: '读到 ${entry.chapterTitle}',
                trailing: IconButton(
                  tooltip: '删除记录',
                  icon: const Icon(AnikumoIcons.delete_outline_rounded),
                  onPressed: () => _deleteHistory(entry),
                ),
              ),
        ],
      ),
    );
  }
}

/// Settings tab: reader preferences + honest engine scope.
class NovelSettingsTab extends StatefulWidget {
  const NovelSettingsTab({super.key});

  @override
  State<NovelSettingsTab> createState() => _NovelSettingsTabState();
}

class _NovelSettingsTabState extends State<NovelSettingsTab> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fontSize = GStorage.getSetting(SettingsKeys.novelFontSize);
    return SafeArea(
      bottom: false,
      child: ListView(
        scrollCacheExtent: const ScrollCacheExtent.pixels(700),
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          const NovelSectionHeader(title: '阅读设置'),
          ListTile(
            title: const Text('正文字号'),
            subtitle: Text('${fontSize.toStringAsFixed(0)} px'),
          ),
          Slider(
            value: fontSize,
            min: 14,
            max: 24,
            divisions: 10,
            onChanged: (value) async {
              await GStorage.putSetting(SettingsKeys.novelFontSize, value);
              if (mounted) setState(() {});
            },
          ),
          const NovelSectionHeader(title: '下载'),
          ListTile(
            leading: const Icon(AnikumoIcons.download_rounded),
            title: const Text('下载管理'),
            subtitle: const Text('已下载章节 · 离线阅读 · 占用空间'),
            trailing: const Icon(AnikumoIcons.chevron_right, size: 18),
            onTap: () => context.pushNamed('/novel/downloads'),
          ),
          const NovelSectionHeader(title: '扩展功能'),
          ListTile(
            leading: const Icon(AnikumoIcons.storefront_rounded),
            title: const Text('功能仓库'),
            subtitle: const Text('可选功能 · 按需安装或卸载'),
            trailing: const Icon(AnikumoIcons.chevron_right, size: 18),
            onTap: () => context.pushNamed('/novel/features'),
          ),
          ValueListenableBuilder<int>(
            valueListenable: NovelFeatures.revision,
            builder: (context, _, _) =>
                NovelFeatures.isInstalled(NovelFeatures.localBooksId)
                    ? ListTile(
                        leading:
                            const Icon(AnikumoIcons.library_books_rounded),
                        title: const Text('本地书架'),
                        subtitle: const Text('导入的 EPUB / TXT 书籍'),
                        trailing:
                            const Icon(AnikumoIcons.chevron_right, size: 18),
                        onTap: () => context.pushNamed('/novel/local'),
                      )
                    : const SizedBox.shrink(),
          ),
          const NovelSectionHeader(title: '书源引擎'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              '按书源规则运行：CSS 选择器、'
              'JSONPath、##替换、<js> 脚本与 java 桥（getElements/ajax/post/'
              'md5/base64 等）均已支持。标记为 webView 的图片章节会在阅读器里'
              '以网页模式打开（站点自己的页面出图）。暂不支持：XPath 规则、'
              '需要登录的源、GBK 编码页面。'
              '这类源会明确报错，不会假装加载。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Batch 42: novel counterpart of the manga home's featured
/// banner — a swipeable carousel over the ACTIVE novel
/// source's first explore category (books with covers only).
/// Auto-advances every 5 s unless smooth mode is on; reloads
/// when the source set changes. A failed or cover-less feed
/// simply hides the banner (the sections below still work).
class _NovelFeaturedBanner extends StatefulWidget {
  const _NovelFeaturedBanner();

  @override
  State<_NovelFeaturedBanner> createState() =>
      _NovelFeaturedBannerState();
}

class _NovelFeaturedBannerState extends State<_NovelFeaturedBanner> {
  final PageController _controller = PageController();
  List<NovelItem> _items = const [];
  int _page = 0;
  String _loadedFor = '';
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    NovelSources.revision.addListener(_load);
    NovelSource.kindsRevision.addListener(_load);
  }

  @override
  void dispose() {
    NovelSources.revision.removeListener(_load);
    NovelSource.kindsRevision.removeListener(_load);
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final source = NovelSources.activeOrNull();
    if (source == null) return;
    // Batch 173: wait for script-declared categories
    // instead of fetching the bogus static entry.
    if (source.hasDynamicExplore && !source.exploreKindsResolved) {
      source.ensureExploreKinds();
      return;
    }
    final marker = '${source.id}|${source.exploreCategories.length}';
    if (marker == _loadedFor || source.exploreCategories.isEmpty) {
      return;
    }
    // Group headers carry no URL — the banner previews
    // the first fetchable category.
    final firstCategory = source.exploreCategories
        .where((c) => !c.isHeader)
        .firstOrNull;
    if (firstCategory == null) return;
    _loadedFor = marker;
    try {
      final items = await _HomeExploreCache.fetch(
        source,
        firstCategory,
      );
      if (!mounted) return;
      final withCovers = [
        for (final item in items)
          if (item.coverUrl.isNotEmpty) item,
      ].take(5).toList();
      setState(() => _items = withCovers);
      _restartTimer();
    } catch (_) {
      // Banner is decorative; sections carry their own errors.
    }
  }

  void _restartTimer() {
    _timer?.cancel();
    if (SmoothMode.enabled || _items.length < 2) return;
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || !_controller.hasClients) return;
      // Batch 47: don't animate the carousel while another
      // route (reader / player) covers this page — wasted
      // frames on the GPU the foreground wants.
      if (ModalRoute.of(context)?.isCurrent != true) return;
      final next = (_page + 1) % _items.length;
      _controller.animateToPage(
        next,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: Column(
        children: [
          SizedBox(
            height: 196,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: PageView.builder(
                controller: _controller,
                itemCount: _items.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (context, index) {
                  final item = _items[index];
                  return GestureDetector(
                    onTap: () => openNovelDetail(context, item),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        RepaintBoundary(
                          child: ImageFiltered(
                          imageFilter: ui.ImageFilter.blur(
                            sigmaX: 24,
                            sigmaY: 24,
                          ),
                          child: NovelCover(
                            url: item.coverUrl,
                            width: MediaQuery.sizeOf(context).width,
                            height: 196,
                            radius: 0,
                          ),
                          ),
                        ),
                        ColoredBox(
                          color: Colors.black.withValues(alpha: 0.45),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              NovelCover(
                                url: item.coverUrl,
                                width: 104,
                                height: 152,
                                radius: 14,
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        gradient: VioletGlass.gradient,
                                        borderRadius:
                                            BorderRadius.circular(8),
                                      ),
                                      child: const Text(
                                        '精选推荐',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      item.title,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.titleMedium
                                          ?.copyWith(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    if (item.author.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        item.author,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                          color: Colors.white70,
                                        ),
                                      ),
                                    ],
                                    if (item.lastChapter.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        '最新章节：${item.lastChapter}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                          color: Colors.white70,
                                        ),
                                      ),
                                    ],
                                    const Spacer(),
                                    FilledButton.icon(
                                      onPressed: () =>
                                          openNovelDetail(context, item),
                                      icon: const Icon(
                                        AnikumoIcons.menu_book_rounded,
                                        size: 18,
                                      ),
                                      label: const Text('开始阅读'),
                                      style: FilledButton.styleFrom(
                                        visualDensity:
                                            VisualDensity.compact,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < _items.length; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: i == _page ? 18 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: i == _page
                        ? theme.colorScheme.primary
                        : theme.colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
