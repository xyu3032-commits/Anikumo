import 'dart:math';

import 'package:flutter/material.dart';
import 'package:anikumo/bean/theme/signature.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_modular/flutter_modular.dart';
import 'package:anikumo/bean/card/bangumi_card.dart';
import 'package:anikumo/bean/widget/editorial_kit.dart';
import 'package:anikumo/bean/widget/empty_state_widget.dart';
import 'package:anikumo/bean/widget/error_widget.dart';
import 'package:anikumo/bean/widget/fade_slide_in.dart';
import 'package:anikumo/services/manga/manga_api.dart';
import 'package:anikumo/services/manga/manga_library.dart';
import 'package:anikumo/services/novel/novel_sources.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:anikumo/services/manga/manga_sources.dart';
import 'package:anikumo/services/novel/novel_library.dart';
import 'package:anikumo/services/ui/app_extras.dart';
import 'package:anikumo/bean/widget/loading_indicator.dart';
import 'package:anikumo/modules/bangumi/bangumi_item.dart';
import 'package:anikumo/modules/manga/manga_item.dart';
import 'package:anikumo/models/novel_item.dart';
import 'package:anikumo/request/apis/bangumi_api.dart';
import 'package:anikumo/services/browse/feed_builder.dart';
import 'package:anikumo/services/network/bangumi_acceleration.dart';
import 'package:anikumo/utils/constants.dart';

/// 发现 (discover) tab: anime discovery plus the manga and
/// novel zone entries.
///
/// 漫画专区 / 小说专区 — big entry cards at the top (the zones
/// stay here per the user's batch-37 instruction).
/// 内容发现 — 排行榜 / 今日上新 entries plus the tag exploration
/// (rotating tag chips, same queries as the popular page's
/// tag mode). Batch 37 moved the toolbox and 我的时光 zones
/// out to their own bottom-nav tabs （工具箱 / 时光）.
class DiscoverPage extends StatefulWidget {
  const DiscoverPage({super.key});

  @override
  State<DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends State<DiscoverPage> {
  final TagRotation _tagRotation = TagRotation(defaultAnimeTags, batchSize: 8);
  final ScrollController _scrollController = ScrollController();

  late List<String> _chipTags;
  String? _selectedTag;
  List<BangumiItem> _items = [];
  bool _loading = false;
  bool _loadingMore = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _chipTags = _tagRotation.nextBatch();
    _scrollController.addListener(_onScroll);
    if (_chipTags.isNotEmpty) {
      _selectTag(_chipTags.first);
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_loading &&
        !_loadingMore &&
        _selectedTag != null) {
      _loadTag(_selectedTag!, append: true);
    }
  }

  Future<void> _selectTag(String tag) async {
    if (tag == _selectedTag && _items.isNotEmpty) return;
    setState(() => _selectedTag = tag);
    await _loadTag(tag);
  }

  Future<void> _loadTag(String tag, {bool append = false}) async {
    if (append) {
      if (_loadingMore) return;
      setState(() => _loadingMore = true);
    } else {
      setState(() {
        _loading = true;
        _failed = false;
      });
    }
    final mirror = BangumiAcceleration.current == BangumiAcceleration.mirror;
    // Same query shape as PopularController.queryBangumiByTag.
    final result = mirror
        ? await BangumiApi.getBangumiMirrorPopularSubjects(
            tag: tag,
            offset: append ? _items.length : 0,
          )
        : await BangumiApi.getBangumiList(
            rank: Random().nextInt(8000) + 1,
            tag: tag,
          );
    if (!mounted || tag != _selectedTag) return;
    setState(() {
      if (append) {
        final existingIds = _items.map((item) => item.id).toSet();
        _items = [
          ..._items,
          ...result.where((item) => existingIds.add(item.id)),
        ];
        _loadingMore = false;
      } else {
        _items = result;
        _loading = false;
        _failed = result.isEmpty;
      }
    });
  }

  void _rotateTags() {
    setState(() => _chipTags = _tagRotation.nextBatch());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        scrollCacheExtent: const ScrollCacheExtent.pixels(600),
        controller: _scrollController,
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'DISCOVER · 探索中心',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 2.4,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '发现',
                    style: Theme.of(context)
                        .textTheme
                        .headlineMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
          ),

          // ── 漫画专区（独立大区）─────────────────────────
          // Batch 44: upgraded from a glass row card to a
          // cinematic zone feature (see _MangaZoneFeature).
          const SliverToBoxAdapter(
            child: FadeSlideIn(
              child: EditorialSectionHeader(
                index: '01',
                label: 'MANGA ZONE',
                title: '漫画专区',
                subtitle: '独立阅读区 · 多源实时更新',
              ),
            ),
          ),
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: StyleString.pagePadding,
              ),
              child: FadeSlideIn(child: _MangaZoneFeature()),
            ),
          ),
          const SliverToBoxAdapter(
              child: SizedBox(height: StyleString.sectionSpace)),

          // ── 小说专区（独立大区）─────────────────────────
          const SliverToBoxAdapter(
            child: FadeSlideIn(
              child: EditorialSectionHeader(
                index: '02',
                label: 'NOVEL ZONE',
                title: '小说专区',
                subtitle: '书源 · 与动漫漫画互为配套',
              ),
            ),
          ),
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: StyleString.pagePadding,
              ),
              child: FadeSlideIn(child: _NovelZoneFeature()),
            ),
          ),
          const SliverToBoxAdapter(
              child: SizedBox(height: StyleString.sectionSpace)),

          // ── 区二 · 内容发现 ──────────────────────────────
          // Batch 44: the two-column entry cards become a
          // numbered editorial index — same seven destinations.
          const SliverToBoxAdapter(
            child: FadeSlideIn(
              delay: Duration(milliseconds: 60),
              child: EditorialSectionHeader(
                index: '03',
                label: 'EXPLORE',
                title: '内容发现',
                subtitle: '排行榜、今日上新，还有按标签慢慢逛',
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: FadeSlideIn(
              delay: const Duration(milliseconds: 60),
              child: Column(
                children: [
                  EditorialIndexRow(
                    index: '01',
                    icon: Icons.emoji_events_outlined,
                    title: '排行榜',
                    subtitle: '按 Bangumi 排名看热门',
                    onTap: () =>
                        context.pushNamed('/tab/discover/rank/'),
                  ),
                  const EditorialHairline(),
                  EditorialIndexRow(
                    index: '02',
                    icon: Icons.today_outlined,
                    title: '今日上新',
                    subtitle: '今天播出的新番与你的在追',
                    onTap: () =>
                        context.pushNamed('/tab/discover/today/'),
                  ),
                  const EditorialHairline(),
                  EditorialIndexRow(
                    index: '03',
                    icon: Icons.auto_awesome_outlined,
                    title: '每日推荐',
                    subtitle: '每天换一批，专挑没看过的',
                    onTap: () =>
                        context.pushNamed('/tab/discover/daily/'),
                  ),
                  const EditorialHairline(),
                  EditorialIndexRow(
                    index: '04',
                    icon: Icons.update_outlined,
                    title: '更新中心',
                    subtitle: '在看的番这周哪天更新',
                    onTap: () =>
                        context.pushNamed('/tab/discover/updates/'),
                  ),
                  const EditorialHairline(),
                  EditorialIndexRow(
                    index: '05',
                    icon: Icons.movie_filter_outlined,
                    title: '相似推荐',
                    subtitle: '喜欢这部？再找几部像的',
                    onTap: () =>
                        context.pushNamed('/tab/discover/similar/'),
                  ),
                  const EditorialHairline(),
                  EditorialIndexRow(
                    index: '06',
                    icon: Icons.upcoming_outlined,
                    title: '即将开播',
                    subtitle: '想看里还没开播的，带倒计时',
                    onTap: () =>
                        context.pushNamed('/tab/discover/coming/'),
                  ),
                  const EditorialHairline(),
                  EditorialIndexRow(
                    index: '07',
                    icon: Icons.casino_outlined,
                    title: '随便看一部',
                    subtitle: '选择困难时，随机抽一部今晚看',
                    onTap: () =>
                        context.pushNamed('/tab/discover/random/'),
                  ),
                ],
              ),
            ),
          ),
          const SliverToBoxAdapter(
              child: SizedBox(height: StyleString.sectionSpace)),
          SliverToBoxAdapter(
            child: EditorialSectionHeader(
              index: '04',
              label: 'BY TAGS',
              title: '按标签发现',
              subtitle: '点一个标签，看看这个分类里有什么',
              actionLabel: '换一批',
              onAction: _rotateTags,
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: StyleString.pagePadding,
              ),
              child: Wrap(
                spacing: StyleString.cardSpace,
                runSpacing: StyleString.cardSpace,
                children: [
                  for (final tag in _chipTags)
                    ChoiceChip(
                      label: Text(tag),
                      selected: tag == _selectedTag,
                      onSelected: (_) => _selectTag(tag),
                    ),
                ],
              ),
            ),
          ),
          const SliverToBoxAdapter(
              child: SizedBox(height: StyleString.sectionSpace)),
          if (_loading)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: LoadingIndicator()),
            )
          else if (_failed)
            SliverFillRemaining(
              hasScrollBody: false,
              child: GeneralErrorWidget(
                errMsg: '这个标签暂时没有拉到内容，请重试或换个标签。',
                onRetry: () =>
                    _selectedTag == null ? null : _loadTag(_selectedTag!),
              ),
            )
          else if (_items.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: GeneralEmptyState(
                icon: Icons.explore_outlined,
                title: '选一个标签开始发现',
                compact: true,
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(
                horizontal: StyleString.cardSpace,
              ),
              sliver: _resultsGrid(),
            ),
          if (_loadingMore)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(StyleString.pagePadding),
                child: Center(child: LoadingIndicator(size: 28)),
              ),
            ),
          const SliverToBoxAdapter(
              child: SizedBox(height: StyleString.sectionSpace)),

        ],
      ),
    );
  }

  /// Same grid geometry as the popular page (3/5/6 columns by width),
  /// so cards feel identical across tabs.
  Widget _resultsGrid() {
    // Batch 15 (G7): the title filter also applies to tag
    // browse results.
    final filterKeywords = TitleFilterStore.loadKeywords();
    final visibleItems = filterKeywords.isEmpty
        ? _items
        : [
            for (final item in _items)
              if (!titleBlocked(
                item.nameCn.isNotEmpty ? item.nameCn : item.name,
                filterKeywords,
              ))
                item,
          ];
    int crossCount = 3;
    if (MediaQuery.sizeOf(context).width > LayoutBreakpoint.compact['width']!) {
      crossCount = 5;
    }
    if (MediaQuery.sizeOf(context).width > LayoutBreakpoint.medium['width']!) {
      crossCount = 6;
    }
    return SliverGrid(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        mainAxisSpacing: StyleString.cardSpace - 2,
        crossAxisSpacing: StyleString.cardSpace,
        crossAxisCount: crossCount,
        mainAxisExtent: MediaQuery.of(context).size.width / crossCount / 0.65 +
            MediaQuery.textScalerOf(context).scale(32.0),
      ),
      delegate: SliverChildBuilderDelegate(
        (context, index) => BangumiCardV(bangumiItem: visibleItems[index]),
        childCount: visibleItems.length,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Batch 44: zone feature cards （漫画/小说入口升级）.
//
// The zones' interiors are untouched; only this entry inside
// the anime zone changes. Everything shown is real data:
// library counts from the zone stores, the featured title
// from the zone's own popular/explore feed, and the continue
// button jumps straight into the work's detail page.
// ─────────────────────────────────────────────────────────────

Widget _zoneFeatureShell({
  required BuildContext context,
  required String kicker,
  required String title,
  required String stats,
  required String coverUrl,
  required String? sourceName,
  required String? featuredTitle,
  required VoidCallback onEnter,
  required Widget? continueButton,
}) {
  final theme = Theme.of(context);
  return ClipRRect(
    borderRadius: BorderRadius.circular(20),
    child: SizedBox(
      height: 218,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (coverUrl.isNotEmpty)
            CachedNetworkImage(
              imageUrl: coverUrl,
              fit: BoxFit.cover,
              // Batch 45: decode at display size, not the
              // cover's original resolution.
              memCacheWidth: (MediaQuery.sizeOf(context).width *
                      MediaQuery.devicePixelRatioOf(context))
                  .round(),
              errorWidget: (_, _, _) => const DecoratedBox(
                decoration: BoxDecoration(gradient: Signature.gradient),
              ),
            )
          else
            const DecoratedBox(
              decoration: BoxDecoration(gradient: Signature.gradient),
            ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black45, Colors.black54, Colors.black87],
                stops: [0, 0.45, 1],
              ),
            ),
          ),
          Material(
            type: MaterialType.transparency,
            child: InkWell(onTap: onEnter),
          ),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      kicker,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: Colors.white70,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 2.2,
                      ),
                    ),
                    const Spacer(),
                    if (sourceName != null)
                      Text(
                        '当前源 · $sourceName',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: Colors.white60,
                        ),
                      ),
                  ],
                ),
                const Spacer(),
                Text(
                  title,
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  stats,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.white70,
                  ),
                ),
                if (featuredTitle != null) ...[
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      const Icon(
                        Icons.star_rounded,
                        size: 14,
                        color: Colors.amber,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          '今日精选：《$featuredTitle》',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    if (continueButton != null) ...[
                      continueButton,
                      const SizedBox(width: 10),
                    ],
                    OutlinedButton(
                      onPressed: onEnter,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white54),
                        visualDensity: VisualDensity.compact,
                      ),
                      child: const Text('进入专区'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _MangaZoneFeature extends StatefulWidget {
  const _MangaZoneFeature();

  @override
  State<_MangaZoneFeature> createState() => _MangaZoneFeatureState();
}

class _MangaZoneFeatureState extends State<_MangaZoneFeature> {
  MangaItem? _featured;

  @override
  void initState() {
    super.initState();
    _loadFeatured();
  }

  Future<void> _loadFeatured() async {
    try {
      final source = MangaSources.active();
      final snapshot = MangaApi.popularSnapshot(source);
      if (snapshot != null && snapshot.items.isNotEmpty) {
        setState(() => _featured = snapshot.items.first);
        return;
      }
      final items = await MangaApi.fetchPopularFor(source);
      if (mounted && items.isNotEmpty) {
        setState(() => _featured = items.first);
      }
    } catch (_) {
      // The featured line is decorative; counts still render.
    }
  }

  @override
  Widget build(BuildContext context) {
    final favorites = MangaLibraryStore.loadFavorites();
    final reading = MangaLibraryStore.loadProgressList();
    final latest = reading.isEmpty ? null : reading.first;
    final empty = favorites.isEmpty && reading.isEmpty;
    return _zoneFeatureShell(
      context: context,
      kicker: 'MANGA · 漫画专区',
      title: '漫画专区',
      stats: empty
          ? '导入自己的 JS 源 · 点开即读'
          : '已收藏 ${favorites.length} 部 · 在读 ${reading.length} 部',
      coverUrl: latest?.coverUrl ?? _featured?.coverUrl ?? '',
      sourceName: MangaSources.activeOrNull()?.name,
      featuredTitle: _featured?.title,
      onEnter: () => context.pushNamed('/manga/'),
      continueButton: latest == null
          ? null
          : FilledButton.icon(
              onPressed: () => context.pushNamed(
                '/manga/detail',
                arguments: MangaItem(
                  id: latest.mangaId,
                  title: latest.mangaTitle,
                  description: '',
                  coverUrl: latest.coverUrl,
                  author: '',
                  status: '',
                  year: null,
                  tags: const [],
                  source: latest.mangaSource,
                ),
              ),
              icon: const Icon(Icons.play_arrow_rounded, size: 18),
              label: Text(
                '继续阅读 · ${latest.chapterLabel}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
              ),
            ),
    );
  }
}

class _NovelZoneFeature extends StatefulWidget {
  const _NovelZoneFeature();

  @override
  State<_NovelZoneFeature> createState() => _NovelZoneFeatureState();
}

class _NovelZoneFeatureState extends State<_NovelZoneFeature> {
  NovelItem? _featured;

  @override
  void initState() {
    super.initState();
    _loadFeatured();
  }

  Future<void> _loadFeatured() async {
    try {
      final source = NovelSources.active();
      if (source.exploreCategories.isEmpty) return;
      final items = await source.explore(source.exploreCategories.first);
      if (!mounted || items.isEmpty) return;
      setState(() {
        _featured = items.firstWhere(
          (item) => item.coverUrl.isNotEmpty,
          orElse: () => items.first,
        );
      });
    } catch (_) {
      // Decorative line only.
    }
  }

  @override
  Widget build(BuildContext context) {
    final favorites = NovelLibraryStore.loadFavorites();
    final reading = NovelLibraryStore.loadProgressList();
    final latest = reading.isEmpty ? null : reading.first;
    final empty = favorites.isEmpty && reading.isEmpty;
    String sourceName;
    try {
      sourceName = NovelSources.active().name;
    } catch (_) {
      sourceName = '';
    }
    return _zoneFeatureShell(
      context: context,
      kicker: 'NOVEL · 小说专区',
      title: '小说专区',
      stats: empty
          ? '导入自己的书源'
          : '已收藏 ${favorites.length} 本 · 在读 ${reading.length} 本',
      coverUrl: latest?.item.coverUrl ?? _featured?.coverUrl ?? '',
      sourceName: sourceName.isEmpty ? null : sourceName,
      featuredTitle: _featured?.title,
      onEnter: () => context.pushNamed('/novel/'),
      continueButton: latest == null
          ? null
          : FilledButton.icon(
              onPressed: () => context.pushNamed(
                '/novel/detail',
                arguments: latest.item,
              ),
              icon: const Icon(Icons.menu_book_rounded, size: 18),
              label: Text(
                '继续阅读 · ${latest.chapterTitle}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
              ),
            ),
    );
  }
}
