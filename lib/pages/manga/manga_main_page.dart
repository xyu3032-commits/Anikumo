import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:anikumo/utils/error_message.dart';
import 'package:anikumo/bean/theme/violet_glass.dart';
import 'package:anikumo/bean/widget/floating_capsule_nav.dart';
import 'package:anikumo/bean/widget/violet_components.dart';
import 'package:anikumo/bean/theme/signature.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_modular/flutter_modular.dart';
import 'package:anikumo/bean/widget/fade_slide_in.dart';
import 'package:anikumo/bean/widget/motion_kit.dart';
import 'package:anikumo/modules/manga/manga_item.dart';
import 'package:anikumo/pages/manga/manga_categories_page.dart';
import 'package:anikumo/pages/manga/manga_explore_page.dart';
import 'package:anikumo/pages/manga/manga_favorites_page.dart';
import 'package:anikumo/pages/manga/manga_settings_page.dart';
import 'package:anikumo/pages/manga/manga_widgets.dart';
import 'package:anikumo/services/manga/manga_library.dart';
import 'package:anikumo/services/manga/manga_api.dart';
import 'package:anikumo/services/manga/manga_source.dart';
import 'package:anikumo/services/manga/js/js_manga_source.dart';
import 'package:anikumo/services/manga/manga_sources.dart';
import 'package:anikumo/services/ui/app_extras.dart';
import 'package:anikumo/services/storage/storage.dart';
import 'package:anikumo/utils/constants.dart';

/// The manga zone shell, restructured after Venera's MainPage:
/// bottom navigation with 首页 / 收藏 / 探索 / 分类 tabs plus the
/// settings index as the fifth destination, and search as an
/// action from the home tab's pill search bar.
class MangaMainPage extends StatefulWidget {
  const MangaMainPage({super.key});

  @override
  State<MangaMainPage> createState() => _MangaMainPageState();
}

/// Cross-tab navigation requests inside the manga zone: a home
/// source section's 「全部」 categories chip sets this to the
/// categories tab index; the main page listens and switches.
final mangaTabSwitchRequest = ValueNotifier<int>(-1);

class _MangaMainPageState extends State<MangaMainPage>
    with WidgetsBindingObserver {
  int _index = 0;

  /// Batch 22: tabs mount lazily — building all five tabs on
  /// entry made every visit pay every tab's loads (explore
  /// lists, categories, favorites parsing) even though only
  /// the home tab is visible. A tab builds on its first visit
  /// and then stays mounted, so state and scroll positions
  /// survive switches exactly as before.
  final Set<int> _visited = {0};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    mangaTabSwitchRequest.addListener(_onTabSwitchRequest);
    // Batch 16: warm up the active JS source's runtime in the
    // background so the first search/tap doesn't pay the
    // QuickJS spin-up cost.
    final activeSource = MangaSources.activeOrNull();
    if (activeSource is JsMangaSource) {
      unawaited(activeSource.engine.ensureInitialized().catchError((_) {}));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    mangaTabSwitchRequest.removeListener(_onTabSwitchRequest);
    super.dispose();
  }

  /// Batch 25 (memory): when the OS reports memory pressure
  /// while the manga zone is open, drop decoded images — the
  /// single biggest manga-side memory pool. They re-decode
  /// from the disk cache on demand.
  @override
  void didHaveMemoryPressure() {
    final imageCache = PaintingBinding.instance.imageCache;
    imageCache.clear();
    imageCache.clearLiveImages();
  }

  void _onTabSwitchRequest() {
    final target = mangaTabSwitchRequest.value;
    if (target < 0 || target >= _tabs.length) return;
    mangaTabSwitchRequest.value = -1;
    setState(() {
      _index = target;
      _visited.add(target);
    });
  }

  static const _tabs = [
    MangaHomeTab(),
    MangaFavoritesTab(),
    MangaExploreTab(),
    MangaCategoriesTab(),
    MangaSettingsIndex(),
  ];

  @override
  Widget build(BuildContext context) {
    // Cross-fading tab stack: every tab stays mounted (state and
    // scroll positions survive) while switches animate smoothly.
    // NOTE: do not wrap the tabs in TickerMode — muting a tab's
    // ticker also freezes its AnimatedOpacity controller, so the
    // outgoing tab could never fade out (found on device: all
    // visited tabs stayed painted and switching looked dead).
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
        onDestinationSelected: (index) => setState(() {
          _index = index;
          _visited.add(index);
        }),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: '首页',
          ),
          NavigationDestination(
            icon: Icon(Icons.local_activity_outlined),
            selectedIcon: Icon(Icons.local_activity_rounded),
            label: '收藏',
          ),
          NavigationDestination(
            icon: Icon(Icons.explore_outlined),
            selectedIcon: Icon(Icons.explore_rounded),
            label: '探索',
          ),
          NavigationDestination(
            icon: Icon(Icons.category_outlined),
            selectedIcon: Icon(Icons.category_rounded),
            label: '分类',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings_rounded),
            label: '设置',
          ),
        ],
      ),
    );
  }
}

/// Home tab in Venera's shape: pill search bar, a bordered 历史
/// card with a count badge and the continue-reading rail inside,
/// then the source's recommendation rail, a 漫画源 card, and the
/// latest-updates list.
class MangaHomeTab extends StatefulWidget {
  const MangaHomeTab({super.key});

  @override
  State<MangaHomeTab> createState() => _MangaHomeTabState();
}

class _MangaHomeTabState extends State<MangaHomeTab> {
  List<MangaItem> _updated = const [];
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
    // Batch 14: every source gets its own section below (loaded
    // per-source); the tab itself only loads the active source's
    // latest-updates list now.
    final updated = await MangaApi.fetchRecentlyUpdated(limit: 15);
    if (!mounted) return;
    setState(() {
      _updated = updated;
      _loading = false;
    });
  }

  void _openDetail(MangaItem item) {
    context.pushNamed('/manga/detail', arguments: item).then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = MangaLibraryStore.loadProgressList();
    final railCount = GStorage.getSetting(SettingsKeys.mangaHistoryRailCount);
    final railProgress = progress.take(railCount).toList();
    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          scrollCacheExtent: const ScrollCacheExtent.pixels(600),
          slivers: [
            // ── pill search bar (Violet Glass) ──────────────
            SliverToBoxAdapter(
              child: Row(
                children: [
                  const SizedBox(width: 8),
                  // Batch 32: visible exit back to the anime
                  // zone (see the novel zone's home header).
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: IconButton(
                      tooltip: '返回动漫区',
                      icon: const Icon(Icons.arrow_back_rounded),
                      onPressed: () => context.pop(),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(4, 10, 16, 4),
                      child: VioletSearchPill(
                        hint: '搜索漫画',
                        onTap: () => context.pushNamed('/manga/search'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // ── featured banner (batch 38) ──────────────────
            SliverToBoxAdapter(
              child: _FeaturedBanner(onOpen: _openDetail),
            ),
            // ── history card ────────────────────────────────
            SliverToBoxAdapter(
              child: FadeSlideIn(
                delay: const Duration(milliseconds: 40),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: VioletGlassCard(
                    radius: 20,
                    onTap: () => context
                        .pushNamed('/manga/history')
                        .then((_) => mounted ? setState(() {}) : null),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: SizedBox(
                            height: 54,
                            child: Row(
                              children: [
                                Text(
                                  '历史',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Container(
                                  margin: const EdgeInsets.only(left: 8),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.secondaryContainer,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '${progress.length}',
                                    style: theme.textTheme.labelSmall,
                                  ),
                                ),
                                const Spacer(),
                                const Icon(Icons.arrow_right_rounded),
                              ],
                            ),
                          ),
                        ),
                        if (railProgress.isEmpty)
                          const Padding(
                            padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text('还没有阅读记录，去探索页逛逛吧'),
                            ),
                          )
                        else
                          SizedBox(
                            height: 208,
                            child: ListView.separated(
        scrollCacheExtent: const ScrollCacheExtent.pixels(700),
                              scrollDirection: Axis.horizontal,
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                              itemCount: railProgress.length,
                              separatorBuilder: (context, index) =>
                                  const SizedBox(width: 12),
                              itemBuilder: (context, index) {
                                final entry = railProgress[index];
                                return SizedBox(
                                  width: 104,
                                  child: InkWell(
                                    onTap: () => _openDetail(
                                      MangaItem(
                                        id: entry.mangaId,
                                        title: entry.mangaTitle,
                                        description: '',
                                        coverUrl: entry.coverUrl,
                                        author: '',
                                        status: '',
                                        year: null,
                                        tags: const [],
                                        source: entry.mangaSource,
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        MangaCover(
                                          url: entry.coverUrl,
                                          width: 104,
                                          height: 152,
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          entry.mangaTitle,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                                fontWeight: FontWeight.w600,
                                              ),
                                        ),
                                        Text(
                                          '${entry.chapterLabel} · 第 ${entry.page + 1} 页',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: theme.textTheme.labelSmall
                                              ?.copyWith(
                                                color:
                                                    theme.colorScheme.primary,
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (MangaSources.all().isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
                  child: VioletGlassCard(
                    radius: 20,
                    child: ListTile(
                      leading: const Icon(Icons.extension_off_rounded),
                      title: const Text('还没有漫画源'),
                      subtitle:
                          const Text('Anikumo 不内置任何漫画源。用你自己的 URL 链接导入 Venera JS 源后，这里就会有内容。'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.pushNamed('/manga/sources'),
                    ),
                  ),
                ),
              ),
            _ForYouSection(onOpen: _openDetail),
            // ── per-source sections (batch 14: multi-source
            // home — every source runs at once, one horizontal
            // band each: its category chips row + popular rail)
            for (final (index, source) in MangaSources.all().indexed)
              _SourceHomeSection(
                source: source,
                onOpen: _openDetail,
                startDelay: Duration(milliseconds: index * 90),
              ),
            // ── source management row ───────────────────────
            SliverToBoxAdapter(
              child: FadeSlideIn(
                delay: const Duration(milliseconds: 120),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                  child: VioletGlassCard(
                    radius: 20,
                    child: ListTile(
                    leading: const Icon(Icons.library_books_outlined),
                    title: const Text('漫画源管理'),
                    subtitle: const Text('下载 Venera JS 源、切换或删除来源'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.pushNamed('/manga/sources'),
                    ),
                  ),
                ),
              ),
            ),
            // ── latest updates ──────────────────────────────
            _sectionTitle(context, '最新更新'),
            if (_loading && _updated.isEmpty)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverList.builder(
                itemCount: _updated.length,
                itemBuilder: (context, index) => MangaListRow(
                  item: _updated[index],
                  onTap: () => _openDetail(_updated[index]),
                ),
              ),
            ),
            const SliverToBoxAdapter(
              child: SizedBox(height: StyleString.sectionSpace),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String title) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
        child: VioletSectionHeader(title: title),
      ),
    );
  }
}

/// One source's band on the multi-source home: header (name +
/// active state), a horizontal row of its category chips, and
/// its popular rail. Loads independently so one slow or broken
/// source never blocks the others.
class _SourceHomeSection extends StatefulWidget {
  const _SourceHomeSection({
    required this.source,
    required this.onOpen,
    this.startDelay = Duration.zero,
  });

  final MangaSource source;
  final void Function(MangaItem) onOpen;

  /// Batch 16: sections start loading in a short stagger so
  /// every source doesn't burst the network (and decode covers)
  /// in the same frame.
  final Duration startDelay;

  @override
  State<_SourceHomeSection> createState() => _SourceHomeSectionState();
}

class _SourceHomeSectionState extends State<_SourceHomeSection> {
  List<MangaTag> _tags = const [];
  List<MangaItem> _popular = const [];
  bool _loading = true;
  bool _failed = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    if (widget.startDelay == Duration.zero) {
      _load();
    } else {
      Future.delayed(widget.startDelay, () {
        if (mounted) _load();
      });
    }
  }

  Future<void> _load({bool force = false}) async {
    // Batch 25 (SWR): paint the disk snapshot immediately on
    // entry — a cold process previously showed skeletons for
    // every section until each source's full load landed.
    // A fresh snapshot (< 10 min) skips the network entirely;
    // a stale one stays on screen while the load below
    // refreshes it, and a failed refresh no longer replaces
    // good content with an error.
    if (!force) {
      final snap = MangaApi.popularSnapshot(widget.source, limit: 14);
      if (snap != null) {
        setState(() {
          _popular = snap.items;
          _loading = false;
        });
        if (snap.fresh) {
          unawaited(_loadTags());
          return;
        }
      }
    }
    // Batch 26: popular and tags settle INDEPENDENTLY. The
    // joint Future.wait kept the whole section on a skeleton
    // until the SLOWER of the two landed — a hanging tag
    // call hid content that was already there. Popular
    // paints the moment it lands; tags fill in on arrival.
    unawaited(_loadTags());
    try {
      final popular = await MangaApi.fetchPopularFor(widget.source, limit: 14);
      if (!mounted) return;
      setState(() {
        if (popular.isNotEmpty) _popular = popular;
        _loading = false;
        _failed = _popular.isEmpty;
        _errorText = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = _popular.isEmpty;
        // The real reason shows only when there is nothing
        // on screen (batch 16's rule); with a snapshot or
        // content visible, a failed refresh stays silent.
        _errorText = _popular.isEmpty ? friendlyError(e) : null;
      });
    }
  }

  Future<void> _loadTags() async {
    try {
      final tags = await MangaApi.fetchTagsFor(widget.source);
      if (mounted && tags.isNotEmpty) {
        setState(() => _tags = tags);
      }
    } catch (_) {
      // Categories are optional per source; the rail
      // matters more.
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final source = widget.source;
    final isActive = MangaSources.activeOrNull()?.id == source.id;
    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 8, 6),
            child: Row(
              children: [
                Text(
                  source.name,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 8),
                if (isActive)
                  Chip(
                    label: const Text('当前源'),
                    visualDensity: VisualDensity.compact,
                    side: BorderSide.none,
                    backgroundColor: theme.colorScheme.secondaryContainer,
                  )
                else
                  TextButton(
                    onPressed: () => MangaSources.setActive(source.id),
                    child: const Text('切换到此源'),
                  ),
                const Spacer(),
                TextButton(
                  onPressed: () => context.pushNamed(
                    '/manga/source',
                    arguments: source.id,
                  ),
                  child: const Text('更多'),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh_rounded, size: 20),
                  tooltip: '重新加载此源',
                  onPressed: () {
                    setState(() => _loading = true);
                    _load(force: true);
                  },
                ),
              ],
            ),
          ),
          if (_tags.isNotEmpty)
            SizedBox(
              height: 38,
              child: ListView.separated(
        scrollCacheExtent: const ScrollCacheExtent.pixels(700),
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _tags.length > 14 ? 15 : _tags.length,
                separatorBuilder: (context, index) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  if (index == 14) {
                    return ActionChip(
                      label: const Text('全部分类'),
                      onPressed: () => mangaTabSwitchRequest.value = 3,
                    );
                  }
                  final tag = _tags[index];
                  return ActionChip(
                    label: Text(tag.name),
                    onPressed: () => context.pushNamed(
                      '/manga/category',
                      arguments: MangaCategoryArgs(source: source, tag: tag),
                    ),
                  );
                },
              ),
            ),
          if (_loading)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Column(
                children: [
                  PulseBox(height: 14),
                  SizedBox(height: 10),
                  PulseBox(height: 120),
                ],
              ),
            )
          else if (_failed || _popular.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '该源暂时没有内容（网络或源本身的问题）',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (_errorText != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        _errorText!.length > 140
                            ? '${_errorText!.substring(0, 140)}…'
                            : _errorText!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ),
                ],
              ),
            )
          else
            SizedBox(
              height: 208,
              child: ListView.separated(
        scrollCacheExtent: const ScrollCacheExtent.pixels(700),
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _popular.length,
                separatorBuilder: (context, index) => const SizedBox(width: 12),
                itemBuilder: (context, index) => ScaleIn(
                  delay: Duration(milliseconds: index * 40),
                  child: MangaRailCard(
                    item: _popular[index],
                    onTap: () => widget.onOpen(_popular[index]),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 猜你喜欢 (batch 15, M10): takes the most recently read
/// manga, reads its tags from its own source, and rails more
/// manga carrying the first tag — excluding favorites and the
/// seed manga itself. Hides silently when there is no signal.
class _ForYouSection extends StatefulWidget {
  const _ForYouSection({required this.onOpen});

  final void Function(MangaItem) onOpen;

  @override
  State<_ForYouSection> createState() => _ForYouSectionState();
}

class _ForYouSectionState extends State<_ForYouSection> {
  List<MangaItem> _items = const [];
  String _seedTitle = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final progress = MangaLibraryStore.loadProgressList();
    if (progress.isEmpty) return;
    final seed = progress.first;
    final stub = MangaItem(
      id: seed.mangaId,
      title: seed.mangaTitle,
      description: '',
      coverUrl: seed.coverUrl,
      author: '',
      status: '',
      year: null,
      tags: const [],
      source: seed.mangaSource,
    );
    final details = await MangaApi.fetchDetails(stub);
    if (!mounted || details == null || details.tags.isEmpty) return;
    final source = MangaSources.byId(seed.mangaSource);
    if (source == null) return;
    final tag = await source.tags().then(
      (tags) => tags.where((t) => details.tags.contains(t.name)).firstOrNull,
    );
    if (!mounted || tag == null) return;
    final results = await source.byTag(tag.id, limit: 14);
    if (!mounted) return;
    final favoriteKeys = {
      for (final f in MangaLibraryStore.loadFavorites()) f.key,
    };
    setState(() {
      _seedTitle = seed.mangaTitle;
      _items = results
          .where(
            (item) =>
                item.storageKey != stub.storageKey &&
                !favoriteKeys.contains(item.storageKey),
          )
          .take(10)
          .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty) return const SliverToBoxAdapter(child: SizedBox());
    final theme = Theme.of(context);
    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 2),
            child: Text(
              '猜你喜欢',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Text(
              '因为你在读《$_seedTitle》',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          SizedBox(
            height: 208,
            child: ListView.separated(
        scrollCacheExtent: const ScrollCacheExtent.pixels(700),
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _items.length,
              separatorBuilder: (context, index) => const SizedBox(width: 12),
              itemBuilder: (context, index) => ScaleIn(
                delay: Duration(milliseconds: index * 40),
                child: MangaRailCard(
                  item: _items[index],
                  onTap: () => widget.onOpen(_items[index]),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Batch 38 (Violet Glass): the home featured banner — a
/// carousel over the ACTIVE source's popular top items.
/// Data is real and shared with the source sections below:
/// the disk snapshot paints instantly, a fetch refreshes it.
/// The cover doubles as a blurred backdrop (one bounded
/// ImageFiltered over the banner only); auto-advance pauses
/// under smooth mode and while the user interacts.
class _FeaturedBanner extends StatefulWidget {
  const _FeaturedBanner({required this.onOpen});

  final void Function(MangaItem) onOpen;

  @override
  State<_FeaturedBanner> createState() => _FeaturedBannerState();
}

class _FeaturedBannerState extends State<_FeaturedBanner> {
  final PageController _controller = PageController();
  List<MangaItem> _items = const [];
  int _page = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    MangaSources.revision.addListener(_load);
  }

  @override
  void dispose() {
    MangaSources.revision.removeListener(_load);
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _load() {
    final source = MangaSources.activeOrNull();
    if (source == null) return;
    final snap = MangaApi.popularSnapshot(source, limit: 5);
    if (snap != null && snap.items.isNotEmpty) {
      setState(() => _items = snap.items.take(5).toList());
      _restartTimer();
      if (snap.fresh) return;
    }
    MangaApi.fetchPopularFor(source, limit: 5).then((items) {
      if (!mounted || items.isEmpty) return;
      setState(() => _items = items.take(5).toList());
      _restartTimer();
    }).catchError((_) {});
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
                    onTap: () => widget.onOpen(item),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // Blurred cover backdrop.
                        // Batch 45: boundary so the blurred
                        // raster is cached as one layer while
                        // the list scrolls past.
                        RepaintBoundary(
                          child: ImageFiltered(
                          imageFilter: ui.ImageFilter.blur(
                            sigmaX: 24,
                            sigmaY: 24,
                          ),
                          child: MangaCover(
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
                              MangaCover(
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
                                    const SizedBox(height: 4),
                                    Text(
                                      item.description,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                        color: Colors.white70,
                                      ),
                                    ),
                                    const Spacer(),
                                    Row(
                                      children: [
                                        FilledButton.icon(
                                          onPressed: () =>
                                              widget.onOpen(item),
                                          icon: const Icon(
                                            Icons.play_arrow_rounded,
                                            size: 18,
                                          ),
                                          label: const Text('阅读'),
                                          style: FilledButton.styleFrom(
                                            visualDensity:
                                                VisualDensity.compact,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        if (item.tags.isNotEmpty)
                                          Expanded(
                                            child: Text(
                                              item.tags
                                                  .take(3)
                                                  .join(' · '),
                                              maxLines: 1,
                                              overflow:
                                                  TextOverflow.ellipsis,
                                              style: theme
                                                  .textTheme.labelSmall
                                                  ?.copyWith(
                                                color: Colors.white60,
                                              ),
                                            ),
                                          ),
                                      ],
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
                    gradient:
                        i == _page ? VioletGlass.gradient : null,
                    color: i == _page
                        ? null
                        : theme.colorScheme.onSurface
                            .withValues(alpha: 0.25),
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
