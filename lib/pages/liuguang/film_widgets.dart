import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:liuguang_core/liuguang_core.dart';
import 'package:anikumo/bean/widget/anikumo_icons.dart';
import 'package:anikumo/bean/widget/zone_switcher.dart';
import 'package:anikumo/services/liuguang/bangumi_film.dart';
import 'package:anikumo/services/liuguang/cms_api_source.dart';
import 'package:anikumo/services/liuguang/film_prefs.dart';
import 'package:anikumo/services/liuguang/film_poster_resolver.dart';
import 'package:anikumo/services/liuguang/tmdb_enrich.dart';
import 'package:anikumo/services/liuguang/tvmaze_covers.dart';
import 'package:anikumo/services/liuguang/video_engine.dart';

/// Batch 213: the zone's kind filter — 电视剧 / 电影 / 综艺
/// are three separate shelves (variety used to hide inside
/// 电视剧， and misclassified series leaked into 电影）.
/// Batch 226: 直播 is its own shelf too (served through the
/// station's live categories, not the kind streams).
/// Batch 228: 动漫 splits out of 电视剧 the same way 综艺
/// did — live-action series and anime never mix.
enum FilmKindFilter {
  all('全部'),
  series('电视剧'),
  movie('电影'),
  variety('综艺'),
  anime('动漫'),
  // Batch 241: short dramas and manju (漫剧) are shelves
  // of their own — short dramas used to dissolve into
  // 电视剧 (or, when a finished one's remarks just said
  // 全集, into 电影), and manju hid inside 动漫.
  shortDrama('短剧'),
  manju('漫剧'),
  // Batch 256: the discover kind row's residual bucket —
  // everything that is not 电影/电视剧/综艺/漫剧 (anime,
  // short dramas, live, sports) collects here instead of
  // owning kind buttons of its own.
  other('其他'),
  live('直播');

  const FilmKindFilter(this.label);

  final String label;

  /// The engine kind this filter browses by (variety,
  /// anime, short-drama and manju are series sub-kinds;
  /// live has no engine kind).
  MediaType? get mediaType => switch (this) {
    FilmKindFilter.all || FilmKindFilter.live || FilmKindFilter.other => null,
    FilmKindFilter.series ||
    FilmKindFilter.variety ||
    FilmKindFilter.anime ||
    FilmKindFilter.shortDrama ||
    FilmKindFilter.manju => MediaType.series,
    FilmKindFilter.movie => MediaType.movie,
  };

  /// The variety constraint for browse(): only-variety,
  /// no-variety, or unconstrained.
  bool? get varietyOnly => switch (this) {
    FilmKindFilter.variety => true,
    FilmKindFilter.series || FilmKindFilter.anime => false,
    _ => null,
  };

  /// The anime constraint for browse() (Batch 228).
  bool? get animeOnly => switch (this) {
    FilmKindFilter.anime => true,
    FilmKindFilter.series ||
    FilmKindFilter.movie ||
    FilmKindFilter.variety => false,
    _ => null,
  };

  /// The short-drama constraint for browse() (Batch 241).
  bool? get shortDramaOnly => switch (this) {
    FilmKindFilter.shortDrama => true,
    FilmKindFilter.series ||
    FilmKindFilter.movie ||
    FilmKindFilter.variety ||
    FilmKindFilter.anime ||
    FilmKindFilter.manju => false,
    _ => null,
  };

  /// The manju constraint for browse() (Batch 241).
  bool? get manjuOnly => switch (this) {
    FilmKindFilter.manju => true,
    FilmKindFilter.series ||
    FilmKindFilter.movie ||
    FilmKindFilter.variety ||
    FilmKindFilter.anime ||
    FilmKindFilter.shortDrama => false,
    _ => null,
  };

  /// Client-side match (search results filtering). Search
  /// is explicit intent, so 全部 keeps everything — the
  /// catalogue flows exclude live at the browse layer.
  bool matches(MediaItem item) => switch (this) {
    FilmKindFilter.all => true,
    FilmKindFilter.series =>
      item.mediaType == MediaType.series &&
          !cmsItemIsVariety(item) &&
          !cmsItemIsAnime(item) &&
          !cmsItemIsShortDrama(item) &&
          !cmsItemIsManju(item) &&
          !cmsItemIsLive(item),
    FilmKindFilter.movie =>
      item.mediaType == MediaType.movie && !cmsItemIsLive(item),
    FilmKindFilter.variety =>
      cmsItemIsVariety(item) &&
          !cmsItemIsAnime(item) &&
          !cmsItemIsShortDrama(item) &&
          !cmsItemIsManju(item) &&
          !cmsItemIsLive(item),
    FilmKindFilter.anime =>
      item.mediaType == MediaType.series && cmsItemIsAnime(item),
    FilmKindFilter.shortDrama =>
      cmsItemIsShortDrama(item) && !cmsItemIsLive(item),
    FilmKindFilter.manju => cmsItemIsManju(item) && !cmsItemIsLive(item),
    // Batch 256: residual — a marked sub-kind that owns
    // no named bucket. Variety and manju win over it;
    // plain 电影/电视剧 are named, never residual.
    FilmKindFilter.other =>
      !cmsItemIsManju(item) &&
          !cmsItemIsVariety(item) &&
          (cmsItemIsAnime(item) ||
              cmsItemIsShortDrama(item) ||
              cmsItemIsLive(item) ||
              cmsItemIsSports(item)),
    FilmKindFilter.live => cmsItemIsLive(item),
  };
}

/// Shared empty state for the 影视 zone's tabs: an icon, a
/// line of explanation, and optionally one action.
class FilmEmptyState extends StatelessWidget {
  const FilmEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = zoneAccent(AppZone.video, scheme);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.13),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(icon, size: 34, color: accent),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 18),
              FilledButton.tonalIcon(
                onPressed: onAction,
                icon: const Icon(AnikumoIcons.add_rounded, size: 18),
                label: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The 电视剧 / 电影 kind tag shown on every card — the user
/// asked for the two kinds to be labelled apart everywhere.
class FilmKindTag extends StatelessWidget {
  const FilmKindTag({super.key, required this.type, this.item});

  final MediaType type;

  /// Batch 213: the item this tag describes, when known —
  /// variety shows get their own 综艺 tag instead of 电视剧.
  final MediaItem? item;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = zoneAccent(AppZone.video, scheme);
    // Batch 226/228: live channels and anime carry their
    // own tags, ahead of the 电视剧 / 电影 fallback.
    final isLive = item != null && cmsItemIsLive(item!);
    final isAnime = item != null && cmsItemIsAnime(item!);
    final isVariety = item != null && cmsItemIsVariety(item!);
    // Batch 241: the two new shelves wear their own badges
    // — a manju must not read 动漫, a short drama not 电视剧.
    final isManju = item != null && cmsItemIsManju(item!);
    final isShortDrama = item != null && cmsItemIsShortDrama(item!);
    final isSeries = type == MediaType.series;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
      decoration: BoxDecoration(
        color:
            (isLive
                    ? scheme.error
                    : isManju
                    ? const Color(0xFF7B1FA2)
                    : isShortDrama
                    ? const Color(0xFF00796B)
                    : isAnime
                    ? scheme.secondary
                    : isVariety
                    ? scheme.primary
                    : isSeries
                    ? accent
                    : scheme.tertiary)
                .withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        isLive
            ? '直播'
            : isManju
            ? '漫剧'
            : isShortDrama
            ? '短剧'
            : isAnime
            ? '动漫'
            : isVariety
            ? '综艺'
            : isSeries
            ? '电视剧'
            : '电影',
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: Colors.white,
          height: 1.1,
        ),
      ),
    );
  }
}

/// Batch 218: the film zone's own image cache — the manga
/// zone has had one all along; film posters used to flood
/// the DEFAULT cache manager shared with the anime zone,
/// evicting its covers and growing without bound. Capped
/// at 400 objects / 7 days.
final CacheManager filmCoverCacheManager = CacheManager(
  Config(
    'anikumoFilmCovers',
    stalePeriod: const Duration(days: 7),
    // Batch 239: 400 -> 300 objects, and the store joins
    // the byte-budget trimmer (it previously had none).
    maxNrOfCacheObjects: 300,
  ),
);

/// Batch 215: the cover image for a film item, resolving
/// its display poster the same way everywhere it appears
/// (poster cards AND the home banner): TVmaze for series
/// on a confident match, then the source's own poster,
/// then the batched backfill (Batch 212) for stations
/// whose list payloads carry no poster at all. Before this
/// widget existed the banner read the raw poster field
/// only and stayed blank for exactly those stations.
class FilmCoverImage extends StatefulWidget {
  const FilmCoverImage({
    super.key,
    required this.item,
    required this.placeholder,
    this.decodeWidth = 360,
  });

  final MediaItem item;
  final Widget placeholder;

  /// Batch 218: covers are decoded at display size, not at
  /// the source's full resolution — stations serve posters
  /// up to 2000px wide, and full-size decodes of hundreds
  /// of them thrashed the shared image memory cache (the
  /// cross-zone stutter the user reported).
  final int decodeWidth;

  @override
  State<FilmCoverImage> createState() => _FilmCoverImageState();
}

class _FilmCoverImageState extends State<FilmCoverImage> {
  /// Batch 243: the TMDB poster — the top of the cover
  /// chain (TMDB is the zone's metadata priority; works
  /// it lacks keep the chain below). Same id guard as the
  /// TVmaze cover.
  String? _tmdbPoster;
  String _tmdbForId = '';

  /// Batch 245: the Bangumi poster — second in the chain
  /// (TMDB → Bangumi → source), same id guard.
  String? _bangumiPoster;
  String _bangumiForId = '';

  /// The TVmaze poster resolved for [_resolvedForId]'s
  /// item. Grid cells recycle state across items, so the
  /// id guard is what keeps one show's cover off another's
  /// card.
  String? _tvmazePoster;
  String _resolvedForId = '';

  /// Batch 212: the source's own poster, backfilled from a
  /// batched detail call when the list payload carried
  /// none (same id guard as the TVmaze cover).
  String? _backfilledPoster;
  String _backfilledForId = '';

  MediaItem get item => widget.item;

  @override
  void initState() {
    super.initState();
    _resolveCover();
  }

  @override
  void didUpdateWidget(FilmCoverImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.id != widget.item.id) {
      _tmdbPoster = null;
      _tmdbForId = '';
      _bangumiPoster = null;
      _bangumiForId = '';
      _tvmazePoster = null;
      _resolvedForId = '';
      _backfilledPoster = null;
      _backfilledForId = '';
      _resolveCover();
    }
  }

  void _resolveCover() {
    _resolveTmdb();
    _resolveBangumi();
    _resolveTvmaze();
    _resolveBackfill();
  }

  void _resolveBangumi() {
    final service = BangumiFilmService.instance;
    final cached = service.cachedPosterFor(item);
    if (cached != null) {
      _bangumiPoster = cached;
      _bangumiForId = item.id;
      return;
    }
    final forId = item.id;
    service.posterFor(item).then((url) {
      if (!mounted || url == null) return;
      if (widget.item.id != forId) return;
      setState(() {
        _bangumiPoster = url;
        _bangumiForId = forId;
      });
    }).ignore();
  }

  void _resolveTmdb() {
    final service = TmdbPosterService.instance;
    final cached = service.cachedPosterFor(item);
    if (cached != null) {
      _tmdbPoster = cached;
      _tmdbForId = item.id;
      return;
    }
    final forId = item.id;
    service.posterFor(item).then((url) {
      if (!mounted || url == null) return;
      if (widget.item.id != forId) return;
      setState(() {
        _tmdbPoster = url;
        _tmdbForId = forId;
      });
    }).ignore();
  }

  void _resolveTvmaze() {
    if (item.mediaType != MediaType.series) return;
    final service = TvMazeCoverService.instance;
    final cached = service.cachedPosterFor(title: item.title, year: item.year);
    if (cached != null) {
      _tvmazePoster = cached;
      _resolvedForId = item.id;
      return;
    }
    final forId = item.id;
    service.posterFor(title: item.title, year: item.year).then((url) {
      if (!mounted || url == null) return;
      if (widget.item.id != forId) return;
      setState(() {
        _tvmazePoster = url;
        _resolvedForId = forId;
      });
    }).ignore();
  }

  void _resolveBackfill() {
    final own = item.artwork.poster;
    if (own != null && own.isNotEmpty) return;
    final forId = item.id;
    FilmPosterResolver.instance.posterFor(item).then((url) {
      if (!mounted || url == null) return;
      if (widget.item.id != forId) return;
      setState(() {
        _backfilledPoster = url;
        _backfilledForId = forId;
      });
    }).ignore();
  }

  String? get _effectivePoster {
    // Batch 243/245: TMDB first, Bangumi second — their
    // posters win over the source's own when they have
    // the work; the source fills in below them.
    if (_tmdbForId == item.id && _tmdbPoster != null) {
      return _tmdbPoster;
    }
    if (_bangumiForId == item.id && _bangumiPoster != null) {
      return _bangumiPoster;
    }
    if (item.mediaType == MediaType.series &&
        _resolvedForId == item.id &&
        _tvmazePoster != null) {
      return _tvmazePoster;
    }
    final own = item.artwork.poster;
    if (own != null && own.isNotEmpty) return own;
    if (_backfilledForId == item.id) return _backfilledPoster;
    return own;
  }

  @override
  Widget build(BuildContext context) {
    final url = _effectivePoster;
    if (url == null || url.isEmpty) return widget.placeholder;
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      cacheManager: filmCoverCacheManager,
      memCacheWidth: widget.decodeWidth,
      placeholder: (_, _) => widget.placeholder,
      errorWidget: (_, _, _) => widget.placeholder,
    );
  }
}

/// One poster card: cover, kind tag, remarks badge
/// （更新至X集）, title, and a meta line (year · area ·
/// rating). Used by 首页 rails, 发现 grid, 搜索 and 收藏.
///
/// Batch 211: for 电视剧 the cover comes from TVmaze when
/// it has a confident match (see TvMazeCoverService); the
/// source's own poster shows meanwhile and stays as the
/// fallback. 电影 never consults TVmaze.
class FilmPosterCard extends StatelessWidget {
  const FilmPosterCard({
    super.key,
    required this.item,
    required this.onTap,
    this.width,
  });

  final MediaItem item;
  final VoidCallback onTap;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final remarks = item.raw['remarks']?.toString() ?? '';
    final meta = [
      if (item.year != null) '${item.year}',
      if (item.countries.isNotEmpty) item.countries.first.name,
      if (item.rating.score > 0) '★ ${item.rating.score.toStringAsFixed(1)}',
    ].join(' · ');
    final card = InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 3 / 4,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  FilmCoverImage(item: item, placeholder: _placeholder(scheme)),
                  Positioned(
                    left: 6,
                    top: 6,
                    child: FilmKindTag(type: item.mediaType, item: item),
                  ),
                  if (remarks.isNotEmpty)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(7, 10, 7, 5),
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.transparent, Colors.black87],
                          ),
                        ),
                        child: Text(
                          remarks,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 10.5,
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            item.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
          if (meta.isNotEmpty)
            Text(
              meta,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
            ),
        ],
      ),
    );
    return width == null ? card : SizedBox(width: width, child: card);
  }

  Widget _placeholder(ColorScheme scheme) {
    return Container(
      color: scheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Icon(AnikumoIcons.movie_rounded, color: scheme.outline, size: 30),
    );
  }
}

/// Batch 221: the film zone's editorial title bar — the
/// anime zone's page language (an eyebrow line with wide
/// letter spacing over a heavy headline), worn with the
/// film zone's own wording. [title] is a widget so the
/// home tab can hang its kind menu off the headline, the
/// way the anime home hangs its tag menu off 热门番组.
class FilmEditorialTitle extends StatelessWidget {
  const FilmEditorialTitle({
    super.key,
    required this.eyebrow,
    required this.title,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(20, 14, 12, 4),
  });

  final String eyebrow;
  final Widget title;
  final Widget? trailing;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            eyebrow,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.outline,
              fontWeight: FontWeight.w700,
              letterSpacing: 2.4,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              title,
              if (trailing != null) ...[const Spacer(), trailing!],
            ],
          ),
        ],
      ),
    );
  }
}

/// A plain editorial headline for [FilmEditorialTitle].
Widget filmHeadline(BuildContext context, String text) {
  return Text(
    text,
    style: Theme.of(
      context,
    ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
  );
}

/// A titled horizontal rail of poster cards （首页精选）.
/// Batch 221: the title is optional — the home tab now
/// heads its rails with EditorialSectionHeader instead.
class FilmRail extends StatelessWidget {
  const FilmRail({
    super.key,
    this.title,
    required this.items,
    required this.onTapItem,
  });

  final String? title;
  final List<MediaItem> items;
  final void Function(MediaItem) onTapItem;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
            child: Text(
              title!,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
          ),
        SizedBox(
          height: 196,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, i) => FilmPosterCard(
              item: items[i],
              width: 104,
              onTap: () => onTapItem(items[i]),
            ),
          ),
        ),
      ],
    );
  }
}

/// Batch 231: the cross-zone search's film sub-filter —
/// 全部 / 电影 / 电视剧 / 其他， where 其他 collects
/// everything that is neither a plain series nor a movie
/// （综艺 / 动漫 / 直播 channels included).
enum FilmCrossFilter {
  all('全部'),
  movie('电影'),
  series('电视剧'),
  other('其他');

  const FilmCrossFilter(this.label);

  final String label;

  bool matches(MediaItem item) => switch (this) {
    FilmCrossFilter.all => true,
    FilmCrossFilter.movie => FilmKindFilter.movie.matches(item),
    FilmCrossFilter.series => FilmKindFilter.series.matches(item),
    FilmCrossFilter.other =>
      !FilmKindFilter.movie.matches(item) &&
          !FilmKindFilter.series.matches(item),
  };
}

/// Opens the film detail page for [item]. The route carries
/// the item object itself (same pattern as the novel zone's
/// detail route).
void openFilmDetail(BuildContext context, MediaItem item) {
  context.pushNamed('/film/detail', arguments: item);
}

/// Batch 214/219: 切换接口 sheet — searches the other
/// enabled interfaces for the same work and lists the
/// versions on offer. Shared by the detail page and the
/// player page (Batch 219).
///
/// Batch 219: results stream in per source instead of
/// waiting for every interface to answer — one dead
/// interface at its full timeout used to freeze the whole
/// sheet (the 切换接口卡顿 the user reported).
/// Batch 250: the copy of [item] hosted by [entry], or
/// null — one title search on that interface plus the
/// same-work check the switcher sheet uses. Best-effort:
/// any failure reads as "no copy there".
Future<MediaItem?> findWorkOnSource(
  VideoEngineService service,
  VideoSourceEntry entry,
  MediaItem item,
) async {
  final all = await findWorksOnSource(service, entry, item);
  return all.isEmpty ? null : all.first;
}

/// All copies of [item] hosted by [entry] — the
/// switcher sheet lists every one of them.
Future<List<MediaItem>> findWorksOnSource(
  VideoEngineService service,
  VideoSourceEntry entry,
  MediaItem item,
) async {
  try {
    final provider = service.providerFor(entry);
    final page = await provider.search(SearchRequest(keyword: item.title));
    return [
      for (final candidate in page.items)
        if (cmsSameWork(item, candidate)) candidate,
    ];
  } catch (_) {
    // A dead interface simply offers no version.
    return const [];
  }
}

/// Batch 250: the copy the 看剧取源 strategy would
/// rather watch than [item] itself, or null to stay.
/// 自定义： the pinned interface's copy (no copy / pin
/// gone / already there = stay). 最快优先： when the
/// current source is not the fastest measured, walk
/// the speed order downward — at most three candidates,
/// never past the current source — and take the first
/// faster holder.
Future<MediaItem?> resolveFilmPlaybackItem(MediaItem item) async {
  try {
    final service = VideoEngineService.instance;
    service.loadRegistry();
    final enabled = service.sources.where((s) => s.enabled).toList();
    final pin = FilmPlaybackSource.pinnedId;
    if (pin != null) {
      if (pin == item.sourceId) return null;
      for (final entry in enabled) {
        if (entry.id == pin) {
          return await findWorkOnSource(service, entry, item);
        }
      }
      return null;
    }
    final now = DateTime.now();
    final fastest = FilmSourceSpeeds.fastestId(now);
    if (fastest == null || fastest == item.sourceId) return null;
    final ordered = FilmSourceSpeeds.orderBySpeed(enabled, (e) => e.id, now);
    var tried = 0;
    for (final entry in ordered) {
      if (entry.id == item.sourceId) break;
      if (tried >= 3) break;
      tried++;
      final found = await findWorkOnSource(service, entry, item);
      if (found != null) return found;
    }
    return null;
  } catch (_) {
    return null;
  }
}

class FilmSourceSheet extends StatefulWidget {
  const FilmSourceSheet({super.key, required this.current});

  final MediaItem current;

  @override
  State<FilmSourceSheet> createState() => _FilmSourceSheetState();
}

class _FilmSourceSheetState extends State<FilmSourceSheet> {
  int _pending = 0;
  final List<({VideoSourceEntry entry, MediaItem item})> _versions = [];

  @override
  void initState() {
    super.initState();
    _search();
  }

  Future<void> _search() async {
    final service = VideoEngineService.instance;
    service.loadRegistry();
    final enabled = service.sources
        .where((s) => s.enabled && s.id != widget.current.sourceId)
        .toList();
    setState(() => _pending = enabled.length);
    for (final entry in enabled) {
      unawaited(_searchOne(service, entry));
    }
  }

  Future<void> _searchOne(
    VideoEngineService service,
    VideoSourceEntry entry,
  ) async {
    try {
      // Batch 250: one shared finder with the playback
      // strategy resolver (same search + same-work rule).
      final found = await findWorksOnSource(service, entry, widget.current);
      if (!mounted || found.isEmpty) return;
      setState(() {
        for (final item in found) {
          _versions.add((entry: entry, item: item));
        }
      });
    } finally {
      if (mounted) {
        setState(() => _pending--);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = VideoEngineService.instance;
    var currentName = '当前接口';
    for (final s in service.sources) {
      if (s.id == widget.current.sourceId) currentName = s.name;
    }
    final variant = Theme.of(context).colorScheme.onSurfaceVariant;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '切换接口',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              '同一部作品在其他接口上的版本；收藏与进度按各自接口分别记录。',
              style: TextStyle(color: variant, fontSize: 12.5),
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(AnikumoIcons.dns_rounded),
              title: Text(currentName),
              subtitle: Text(widget.current.title),
              trailing: const Chip(
                label: Text('当前'),
                visualDensity: VisualDensity.compact,
              ),
            ),
            for (final v in _versions)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(AnikumoIcons.dns_rounded),
                title: Text(v.entry.name),
                subtitle: Text(
                  [
                    v.item.title,
                    if (v.item.year != null) '${v.item.year}',
                    if ((v.item.raw['remarks']?.toString() ?? '').isNotEmpty)
                      v.item.raw['remarks'].toString(),
                  ].join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: const Icon(
                  AnikumoIcons.chevron_right_rounded,
                  size: 18,
                ),
                onTap: () => Navigator.of(context).pop(v.item),
              ),
            if (_pending > 0)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 15,
                      height: 15,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 9),
                    Text(
                      _versions.isEmpty ? '正在搜索其他接口…' : '仍在搜索其他接口…',
                      style: TextStyle(color: variant, fontSize: 12.5),
                    ),
                  ],
                ),
              )
            else if (_versions.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Text('其他接口里没有找到同名作品。', style: TextStyle(color: variant)),
              ),
          ],
        ),
      ),
    );
  }
}
