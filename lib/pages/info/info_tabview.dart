import 'package:anikumo/utils/tap_debouncer.dart';
import 'package:anikumo/services/novel/novel_sources.dart';
import 'package:anikumo/bean/widget/companion_state_row.dart';
import 'package:anikumo/services/novel/novel_api.dart';
import 'package:anikumo/pages/novel/novel_widgets.dart';
import 'package:anikumo/models/novel_item.dart';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:anikumo/bean/widget/error_widget.dart';
import 'package:anikumo/bean/widget/fade_slide_in.dart';
import 'package:anikumo/bean/widget/empty_state_widget.dart';
import 'package:anikumo/pages/info/info_comments_view.dart';
import 'package:anikumo/pages/info/info_controller.dart';
import 'package:anikumo/pages/info/source_sheet.dart';
import 'package:anikumo/bean/card/character_card.dart';
import 'package:anikumo/bean/card/staff_card.dart';
import 'package:anikumo/bean/card/network_img_layer.dart';
import 'package:skeletonizer/skeletonizer.dart';
import 'package:anikumo/modules/bangumi/bangumi_item.dart';
import 'package:anikumo/modules/bangumi/bangumi_relation.dart';
import 'package:anikumo/modules/manga/manga_item.dart';
import 'package:anikumo/pages/manga/manga_widgets.dart';
import 'package:anikumo/services/manga/cross_media.dart';
import 'package:anikumo/services/manga/manga_api.dart';
import 'package:anikumo/modules/comments/comment_item.dart';
import 'package:anikumo/modules/characters/character_item.dart';
import 'package:anikumo/modules/staff/staff_item.dart';
import 'package:anikumo/utils/constants.dart';
import 'package:anikumo/utils/device.dart';
import 'package:anikumo/bean/widget/anikumo_icons.dart';

class InfoTabView extends StatefulWidget {
  const InfoTabView({
    super.key,
    required this.commentsQueryTimeout,
    required this.commentsHasLoaded,
    required this.charactersQueryTimeout,
    required this.charactersIsEmpty,
    required this.staffQueryTimeout,
    required this.staffIsEmpty,
    required this.relationsQueryTimeout,
    required this.relationsIsLoading,
    required this.relationsHasLoaded,
    required this.tabController,
    required this.loadMoreComments,
    required this.loadCharacters,
    required this.loadStaff,
    required this.loadRelations,
    required this.bangumiItem,
    required this.commentsList,
    required this.commentsIsLoading,
    required this.onWriteReview,
    required this.infoController,
    required this.episodeTabIndex,
    required this.hasPlugins,
    required this.characterList,
    required this.staffList,
    required this.relationList,
    required this.isLoading,
  });

  final bool commentsQueryTimeout;
  final bool commentsHasLoaded;
  final bool commentsIsLoading;
  final VoidCallback onWriteReview;

  /// Batch 149: the 选集 tab hosts the episode picker in
  /// place (embedded SourceSheet). [infoController] feeds
  /// it, [episodeTabIndex] tells the lazy gate which tab it
  /// is, and [hasPlugins] swaps in the add-a-rule guidance
  /// when no source exists yet.
  final InfoController infoController;
  final int episodeTabIndex;
  final bool hasPlugins;
  final bool charactersQueryTimeout;
  final bool charactersIsEmpty;
  final bool staffQueryTimeout;
  final bool staffIsEmpty;
  final bool relationsQueryTimeout;
  final bool relationsIsLoading;
  final bool relationsHasLoaded;
  final TabController tabController;
  final Future<void> Function({bool loadMore}) loadMoreComments;
  final Future<void> Function() loadCharacters;
  final Future<void> Function() loadStaff;
  final Future<void> Function() loadRelations;
  final BangumiItem bangumiItem;
  final List<CommentItem> commentsList;
  final List<CharacterItem> characterList;
  final List<StaffFullItem> staffList;
  final List<BangumiRelation> relationList;
  final bool isLoading;

  @override
  State<InfoTabView> createState() => _InfoTabViewState();
}

class _InfoTabViewState extends State<InfoTabView> {
  final maxWidth = 950.0;
  bool fullIntro = false;
  bool fullTag = false;

  // 配套漫画 matched on MangaDex by title, loaded once per subject.
  List<MangaItem> _pairedManga = const [];
  bool _pairedMangaLoaded = false;

  // 配套小说 matched on the Legado novel sources by title.
  List<NovelItem> _pairedNovels = const [];
  bool _pairedNovelsLoaded = false;

  /// Batch 149: the embedded picker is created the first
  /// time the 选集 tab is actually opened, then kept alive —
  /// opening the detail page must not fire source searches
  /// the viewer never asked for, and switching away and
  /// back must not restart them either.
  bool _episodeTabSeen = false;

  /// Batch 151: the embedded picker's own scroll controller.
  /// Its GridView/ListViews default to the primary scroll
  /// controller — inside a NestedScrollView that is the
  /// shared inner controller, which the slot's outer
  /// CustomScrollView also uses; two primary scrollables on
  /// one controller desynchronised (the grid could be pulled
  /// down but not back, and the tab labels ghosted through
  /// the cards — the user's v39 screenshots). The picker
  /// gets a controller of its own; the outer view only
  /// absorbs the pinned header's overlap.
  final ScrollController _episodeScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _episodeTabSeen = widget.tabController.index == widget.episodeTabIndex;
    widget.tabController.addListener(_onTabSelectionChanged);
    _loadPairedManga();
    _loadPairedNovels();
  }

  void _onTabSelectionChanged() {
    if (_episodeTabSeen || !mounted) return;
    if (widget.tabController.index == widget.episodeTabIndex) {
      setState(() => _episodeTabSeen = true);
    }
  }

  @override
  void dispose() {
    widget.tabController.removeListener(_onTabSelectionChanged);
    _episodeScrollController.dispose();
    super.dispose();
  }

  Future<void> _loadPairedManga() async {
    // Batch 37: no try/finally here — when the active manga
    // source's search THREW (the broken-JS-source case), the
    // section stayed on its loading spinner forever. Every
    // companion load must settle, and a wedged source gets a
    // bounded wait per query.
    try {
      final item = widget.bangumiItem;
      final queries = buildCrossQueries(
        primary: item.nameCn,
        fallback: item.name,
      );
      var found = const <MangaItem>[];
      for (final query in queries) {
        // Batch 42: active source first, then the other
        // installed sources, keeping only sources whose top
        // match VERIFIES as readable — previously this rail
        // searched the active source only, so a comic that
        // existed (and was readable) elsewhere still showed
        // as "no paired manga", and a dead entry on the
        // active source showed as a broken pairing.
        found = await MangaApi.searchReadableCompanions(query)
            .timeout(const Duration(seconds: 45), onTimeout: () => []);
        if (found.isNotEmpty) break;
      }
      if (!mounted) return;
      setState(() => _pairedManga = found);
    } catch (_) {
      // Companions are best-effort.
    } finally {
      if (mounted) setState(() => _pairedMangaLoaded = true);
    }
  }


  /// Batch 28: 配套小说 — the novel counterpart of this
  /// anime, searched across all Legado sources with strict
  /// title relevance.
  Future<void> _loadPairedNovels() async {
    try {
      final item = widget.bangumiItem;
      final queries = buildCrossQueries(
        primary: item.nameCn,
        fallback: item.name,
      );
      for (final query in queries) {
        final results = await NovelApi.searchAll(query);
        final ranked = rankNovels(query, results, strict: true);
        if (ranked.isEmpty) continue;
        // Batch 42: verify the top matches really have
        // chapters and float the verified ones to the front
        // — a same-title book whose source serves nothing
        // must not be the pairing the user taps into. When
        // nothing verifies (all sources slow/down), keep
        // the ranked list rather than showing nothing.
        final verified = <NovelItem>[];
        var checked = 0;
        for (final candidate in ranked) {
          if (checked >= 3 || verified.length >= 3) break;
          checked++;
          try {
            final toc = await NovelApi.chapters(candidate).timeout(
              const Duration(seconds: 20),
              onTimeout: () => const <NovelChapter>[],
            );
            if (toc.isNotEmpty) verified.add(candidate);
          } catch (_) {
            // Unreadable here — the next candidate may work.
          }
        }
        final ordered = [
          ...verified,
          for (final r in ranked)
            if (!verified.contains(r)) r,
        ];
        if (mounted) {
          setState(() => _pairedNovels = ordered.take(10).toList());
        }
        break;
      }
    } catch (_) {
      // Companions are best-effort.
    } finally {
      if (mounted) setState(() => _pairedNovelsLoaded = true);
    }
  }

  /// Related anime subjects （配套动漫）: other seasons, prequels,
  /// sequels, OVAs and side stories from the relations feed.
  List<BangumiRelation> get _pairedAnime {
    return widget.relationList
        .where(
          (relation) =>
              relation.bangumiItem.type == 2 &&
              relation.bangumiItem.id != widget.bangumiItem.id,
        )
        .toList();
  }

  Widget get infoBody {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SizedBox(
          width: MediaQuery.sizeOf(context).width > maxWidth
              ? maxWidth
              : MediaQuery.sizeOf(context).width - 32,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('简介', style: TextStyle(fontSize: 18)),
              const SizedBox(height: 8),
              LayoutBuilder(
                builder: (context, constraints) {
                  final span = TextSpan(text: widget.bangumiItem.summary);
                  final tp = TextPainter(
                    text: span,
                    textDirection: TextDirection.ltr,
                  );
                  tp.layout(maxWidth: constraints.maxWidth);
                  final numLines = tp.computeLineMetrics().length;
                  if (numLines > 7) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        SizedBox(
                          height: fullIntro ? null : 120,
                          width: MediaQuery.sizeOf(context).width > maxWidth
                              ? maxWidth
                              : MediaQuery.sizeOf(context).width - 32,
                          child: SelectableText(
                            widget.bangumiItem.summary,
                            textAlign: TextAlign.start,
                            scrollBehavior: const ScrollBehavior().copyWith(
                              scrollbars: false,
                            ),
                            scrollPhysics: NeverScrollableScrollPhysics(),
                            selectionHeightStyle: ui.BoxHeightStyle.max,
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            setState(() {
                              fullIntro = !fullIntro;
                            });
                          },
                          child: Text(fullIntro ? '加载更少' : '加载更多'),
                        ),
                      ],
                    );
                  } else {
                    return SelectableText(
                      widget.bangumiItem.summary,
                      textAlign: TextAlign.start,
                      scrollPhysics: NeverScrollableScrollPhysics(),
                      selectionHeightStyle: ui.BoxHeightStyle.max,
                    );
                  }
                },
              ),
              const SizedBox(height: 16),
              Text('标签', style: TextStyle(fontSize: 18)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8.0,
                runSpacing: isDesktop() ? 8 : 0,
                children: List<Widget>.generate(
                  fullTag || widget.bangumiItem.tags.length < 13
                      ? widget.bangumiItem.tags.length
                      : 13,
                  (int index) {
                    if (!fullTag && index == 12) {
                      return ActionChip(
                        label: Text(
                          '更多 +',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        onPressed: () {
                          setState(() {
                            fullTag = !fullTag;
                          });
                        },
                      );
                    }
                    return ActionChip(
                      label: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('${widget.bangumiItem.tags[index].name} '),
                          Text(
                            '${widget.bangumiItem.tags[index].count}',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                      onPressed: () {
                        final tagName = Uri.encodeComponent(
                          widget.bangumiItem.tags[index].name,
                        );
                        context.pushNamed('/search/$tagName');
                      },
                    );
                  },
                ).toList(),
              ),
              if (_pairedAnime.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text('配套动漫', style: TextStyle(fontSize: 18)),
                const SizedBox(height: 8),
                FadeSlideIn(
                  delay: const Duration(milliseconds: 60),
                  child: SizedBox(
                    height: 186,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _pairedAnime.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(width: 10),
                      itemBuilder: (context, index) {
                        final relation = _pairedAnime[index];
                        final related = relation.bangumiItem;
                        return SizedBox(
                          width: 96,
                          child: InkWell(
                            onTap: () {
                              if (TapDebouncer.accept('info:${related.id}')) {
                                context.pushNamed('/info/',
                                    arguments: related);
                              }
                            },
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                NetworkImgLayer(
                                  src: related.images['large'] ?? '',
                                  width: 96,
                                  height: 128,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  relation.relation,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  related.nameCn,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              const Text('配套漫画', style: TextStyle(fontSize: 18)),
              const SizedBox(height: 8),
              if (!_pairedMangaLoaded)
                const CompanionLoadingRow(label: '正在漫画源里查找同名作品…')
              else if (_pairedManga.isEmpty)
                CompanionEmptyRow(
                  message: '漫画源里暂未找到同名作品',
                  actionLabel: '去漫画区搜索',
                  onAction: () => context.pushNamed(
                    '/manga/search',
                    arguments: widget.bangumiItem.nameCn,
                  ),
                )
              else ...[
                FadeSlideIn(
                  delay: const Duration(milliseconds: 120),
                  child: SizedBox(
                    height: 208,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _pairedManga.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(width: 10),
                      itemBuilder: (context, index) {
                        final manga = _pairedManga[index];
                        return MangaRailCard(
                          item: manga,
                          onTap: () => context.pushNamed(
                            '/manga/detail',
                            arguments: manga,
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              const Text('配套小说', style: TextStyle(fontSize: 18)),
              const SizedBox(height: 8),
              if (!_pairedNovelsLoaded)
                const CompanionLoadingRow(label: '正在小说源里查找同名作品…')
              else if (_pairedNovels.isEmpty)
                CompanionEmptyRow(
                  message: '小说源里暂未找到同名作品',
                  actionLabel: '去小说区搜索',
                  onAction: () => context.pushNamed(
                    '/novel/search',
                    arguments: widget.bangumiItem.nameCn,
                  ),
                )
              else ...[
                FadeSlideIn(
                  delay: const Duration(milliseconds: 120),
                  child: SizedBox(
                    height: 218,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _pairedNovels.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(width: 10),
                      itemBuilder: (context, index) =>
                          NovelRailCard(item: _pairedNovels[index]),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
  Widget get relationsListBody {
    return Builder(
      builder: (BuildContext context) {
        return CustomScrollView(
          scrollBehavior: const ScrollBehavior().copyWith(scrollbars: false),
          key: const PageStorageKey<String>('关联'),
          slivers: <Widget>[
            SliverOverlapInjector(
              handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
            ),
            SliverLayoutBuilder(
              builder: (context, constraints) {
                if (widget.relationsQueryTimeout) {
                  return SliverFillRemaining(
                    hasScrollBody: false,
                    child: GeneralErrorWidget(
                      title: '关联条目加载失败',
                      errMsg: '请检查网络连接后重试。',
                      onRetry: widget.loadRelations,
                    ),
                  );
                }
                if (widget.relationsHasLoaded && widget.relationList.isEmpty) {
                  return const SliverFillRemaining(
                    hasScrollBody: false,
                    child: GeneralEmptyState(
                      icon: AnikumoIcons.account_tree_rounded,
                      title: '暂无关联条目',
                    ),
                  );
                }

                final horizontalPadding =
                    ((constraints.crossAxisExtent - maxWidth) / 2)
                        .clamp(16.0, double.infinity)
                        .toDouble();
                final contentWidth =
                    constraints.crossAxisExtent - horizontalPadding * 2;
                final crossAxisCount = contentWidth >= 840
                    ? 3
                    : contentWidth >= 560
                    ? 2
                    : 1;
                final showSkeleton =
                    !widget.relationsHasLoaded || widget.relationsIsLoading;
                final itemCount = showSkeleton
                    ? crossAxisCount
                    : widget.relationList.length;

                return SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    16,
                    horizontalPadding,
                    16,
                  ),
                  sliver: SliverGrid(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      mainAxisSpacing: StyleString.cardSpace,
                      crossAxisSpacing: StyleString.cardSpace,
                      mainAxisExtent: _RelatedBangumiCardH.cardHeight,
                    ),
                    delegate: SliverChildBuilderDelegate((context, index) {
                      if (showSkeleton) {
                        return LayoutBuilder(
                          builder: (context, constraints) {
                            return Skeletonizer.zone(
                              child: Bone(
                                width: constraints.maxWidth,
                                height: _RelatedBangumiCardH.cardHeight,
                                uniRadius: 14,
                              ),
                            );
                          },
                        );
                      }
                      return _RelatedBangumiCardH(
                        relation: widget.relationList[index],
                      );
                    }, childCount: itemCount),
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }

  Widget get infoBodyBone {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SizedBox(
          width: MediaQuery.sizeOf(context).width > maxWidth
              ? maxWidth
              : MediaQuery.sizeOf(context).width - 32,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Skeletonizer.zone(child: Bone.text(fontSize: 18, width: 50)),
              const SizedBox(height: 8),
              Skeletonizer.zone(child: Bone.multiText(lines: 7)),
              const SizedBox(height: 16),
              Skeletonizer.zone(child: Bone.text(fontSize: 18, width: 50)),
              const SizedBox(height: 8),
              if (widget.isLoading)
                Skeletonizer.zone(
                  child: Wrap(
                    spacing: 8.0,
                    runSpacing: 8.0,
                    children: List.generate(
                      4,
                      (_) => Bone.button(uniRadius: 8, height: 32),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget get staffListBody {
    return Builder(
      builder: (BuildContext context) {
        return CustomScrollView(
          scrollBehavior: const ScrollBehavior().copyWith(scrollbars: false),
          key: PageStorageKey<String>('制作人员'),
          slivers: <Widget>[
            SliverOverlapInjector(
              handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
            ),
            SliverLayoutBuilder(
              builder: (context, _) {
                if (widget.staffList.isNotEmpty) {
                  return SliverList.builder(
                    itemCount: widget.staffList.length,
                    itemBuilder: (context, index) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0),
                          child: SizedBox(
                            width: MediaQuery.sizeOf(context).width > maxWidth
                                ? maxWidth
                                : MediaQuery.sizeOf(context).width - 32,
                            child: StaffCard(
                              staffFullItem: widget.staffList[index],
                            ),
                          ),
                        ),
                      );
                    },
                  );
                }
                if (widget.staffQueryTimeout) {
                  return SliverFillRemaining(
                    child: GeneralErrorWidget(
                      title: '制作人员加载失败',
                      errMsg: '请检查网络连接后重试。',
                      onRetry: widget.loadStaff,
                    ),
                  );
                }
                if (widget.staffIsEmpty) {
                  return const SliverFillRemaining(
                    hasScrollBody: false,
                    child: GeneralEmptyState(
                      icon: AnikumoIcons.groups_rounded,
                      title: '暂无制作人员信息',
                    ),
                  );
                }
                return SliverList.builder(
                  itemCount: 8,
                  itemBuilder: (context, _) {
                    return Align(
                      alignment: Alignment.topCenter,
                      child: SizedBox(
                        width: MediaQuery.sizeOf(context).width > maxWidth
                            ? maxWidth
                            : MediaQuery.sizeOf(context).width - 32,
                        child: Skeletonizer.zone(
                          child: ListTile(
                            leading: Bone.circle(size: 36),
                            title: Bone.text(width: 100),
                            subtitle: Bone.text(width: 80),
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ],
        );
      },
    );
  }

  Widget get charactersListBody {
    return Builder(
      builder: (BuildContext context) {
        return CustomScrollView(
          scrollBehavior: const ScrollBehavior().copyWith(scrollbars: false),
          key: PageStorageKey<String>('角色'),
          slivers: <Widget>[
            SliverOverlapInjector(
              handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
            ),
            SliverLayoutBuilder(
              builder: (context, _) {
                if (widget.characterList.isNotEmpty) {
                  return SliverList.builder(
                    itemCount: widget.characterList.length,
                    itemBuilder: (context, index) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0),
                          child: SizedBox(
                            width: MediaQuery.sizeOf(context).width > maxWidth
                                ? maxWidth
                                : MediaQuery.sizeOf(context).width - 32,
                            child: CharacterCard(
                              characterItem: widget.characterList[index],
                            ),
                          ),
                        ),
                      );
                    },
                  );
                }
                if (widget.charactersQueryTimeout) {
                  return SliverFillRemaining(
                    child: GeneralErrorWidget(
                      title: '角色列表加载失败',
                      errMsg: '请检查网络连接后重试。',
                      onRetry: widget.loadCharacters,
                    ),
                  );
                }
                if (widget.charactersIsEmpty) {
                  return const SliverFillRemaining(
                    hasScrollBody: false,
                    child: GeneralEmptyState(
                      icon: AnikumoIcons.people_alt_rounded,
                      title: '暂无角色信息',
                    ),
                  );
                }
                return SliverList.builder(
                  itemCount: 4,
                  itemBuilder: (context, _) {
                    return Align(
                      alignment: Alignment.topCenter,
                      child: SizedBox(
                        width: MediaQuery.sizeOf(context).width > maxWidth
                            ? maxWidth
                            : MediaQuery.sizeOf(context).width - 32,
                        child: Skeletonizer.zone(
                          child: ListTile(
                            leading: Bone.circle(size: 36),
                            title: Bone.text(width: 100),
                            subtitle: Bone.text(width: 80),
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return TabBarView(
      controller: widget.tabController,
      children: [
        Builder(
          // Resolve the overlap handle inside the NestedScrollView.
          builder: (BuildContext context) {
            return CustomScrollView(
              scrollBehavior: const ScrollBehavior().copyWith(
                scrollbars: false,
              ),
              key: PageStorageKey<String>('概览'),
              slivers: <Widget>[
                SliverOverlapInjector(
                  handle: NestedScrollView.sliverOverlapAbsorberHandleFor(
                    context,
                  ),
                ),
                SliverToBoxAdapter(
                  child: SafeArea(
                    top: false,
                    bottom: false,
                    child: widget.isLoading ? infoBodyBone : infoBody,
                  ),
                ),
              ],
            );
          },
        ),
        // Batch 149: 选集 is a real tab — the picker lives
        // right here and the TabBarView's own motion switches
        // to it, exactly like the other five tabs. No modal
        // sheet, no spring-back (batch 128's action tab is
        // retired by user call).
        if (!_episodeTabSeen)
          const SizedBox.shrink()
        else if (!widget.hasPlugins)
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('还没有规则，无法开始观看'),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () => context.pushNamed('/settings/plugin/'),
                  icon: const Icon(AnikumoIcons.add_rounded),
                  label: const Text('添加规则'),
                ),
              ],
            ),
          )
        else
          // Batch 150: the picker gets the same overlap
          // treatment as every other tab (a CustomScrollView
          // with an injector absorbing the pinned header);
          // as a bare column it started one tab-bar height
          // too high and the tab labels ghosted through its
          // first row (user screenshot). FillRemaining hands
          // it exactly the space below the header — its own
          // grid/lists scroll inside that box.
          Builder(
            builder: (context) => CustomScrollView(
              key: const PageStorageKey<String>('选集'),
              slivers: [
                SliverOverlapInjector(
                  handle: NestedScrollView.sliverOverlapAbsorberHandleFor(
                    context,
                  ),
                ),
                SliverFillRemaining(
                  hasScrollBody: true,
                  // Batch 151: see _episodeScrollController —
                  // the picker's scrollables must not share
                  // the NestedScrollView's primary controller
                  // with the CustomScrollView above them.
                  child: PrimaryScrollController(
                    controller: _episodeScrollController,
                    child: SourceSheet(
                      infoController: widget.infoController,
                      pickEpisode: true,
                      embedded: true,
                    ),
                  ),
                ),
              ],
            ),
          ),
        InfoCommentsView(
          interest: widget.bangumiItem.interest,
          comments: widget.commentsList,
          isLoading: widget.commentsIsLoading,
          hasLoaded: widget.commentsHasLoaded,
          hasError: widget.commentsQueryTimeout,
          onReviewTap: widget.onWriteReview,
          onRetry: () => widget.loadMoreComments(loadMore: false),
          onLoadMore: () => widget.loadMoreComments(loadMore: true),
        ),
        charactersListBody,
        relationsListBody,
        staffListBody,
      ],
    );
  }
}

class _RelatedBangumiCardH extends StatelessWidget {
  const _RelatedBangumiCardH({required this.relation});

  static const double cardHeight = 108;
  static const double imageHeight = 92;
  static const double posterAspectRatio = 0.65;

  final BangumiRelation relation;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textScaler = MediaQuery.textScalerOf(
      context,
    ).clamp(maxScaleFactor: 1.1);
    final relationLabel = relation.relation.isEmpty ? '关联' : relation.relation;
    final bangumiItem = relation.toBangumiItem();
    final title = bangumiItem.nameCn.isEmpty
        ? bangumiItem.name.trim()
        : bangumiItem.nameCn.trim();

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: colorScheme.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        onTap: () {
          if (TapDebouncer.accept('info:${bangumiItem.id}')) {
            context.pushNamed('/info/', arguments: bangumiItem);
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final gap = constraints.maxWidth.clamp(0.0, 10.0).toDouble();
              final maxImageWidth = (constraints.maxWidth - gap).clamp(
                0.0,
                152.0,
              );
              final imageWidth = (constraints.maxWidth * 0.42)
                  .clamp(0.0, maxImageWidth)
                  .toDouble();

              return Row(
                children: [
                  NetworkImgLayer(
                    src: bangumiItem.images['large'] ?? '',
                    width: imageWidth,
                    height: imageHeight,
                    origAspectRatio: posterAspectRatio,
                  ),
                  SizedBox(width: gap),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.start,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Align(
                            alignment: Alignment.topLeft,
                            child: Text(
                              title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              textScaler: textScaler,
                              style: theme.textTheme.titleSmall?.copyWith(
                                color: colorScheme.onSurface,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        Text(
                          relationLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textScaler: textScaler,
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
