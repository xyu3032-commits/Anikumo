import 'package:anikumo/utils/tap_debouncer.dart';
import 'package:flutter/material.dart';
import 'package:anikumo/bean/card/network_img_layer.dart';
import 'package:anikumo/modules/bangumi/bangumi_item.dart';

/// Batch 44: the anime zone's editorial design kit —
/// 「番组编辑部」. Shared by the redesigned shell and tab
/// pages so the zone reads as one publication: numbered
/// section heads with small-caps English labels, full-bleed
/// poster spotlights, giant-numeral rank rows and numbered
/// index rows. All colors and type come from the ambient
/// theme (light and dark both work); no zone-local palette.

// ----------------------------------------------------------------
// Section header
// ----------------------------------------------------------------

/// Editorial section head: a small index + English label
/// over a large title, hairline below, optional trailing
/// action (usually 「更多」).
class EditorialSectionHeader extends StatelessWidget {
  const EditorialSectionHeader({
    super.key,
    required this.index,
    required this.label,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  final String index;
  final String label;
  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 26, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                index,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.outline,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2.4,
                ),
              ),
              const Spacer(),
              if (actionLabel != null)
                TextButton(
                  onPressed: onAction,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(actionLabel!),
                      const Icon(Icons.arrow_forward, size: 16),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            title,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitle!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Container(
            height: 1,
            color: scheme.outlineVariant.withValues(alpha: 0.6),
          ),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------
// Hero spotlight
// ----------------------------------------------------------------

/// Full-bleed cinematic spotlight: the poster IS the page's
/// first visual. Kicker line, giant title, meta chips and an
/// optional score badge over a bottom scrim.
class EditorialHero extends StatelessWidget {
  const EditorialHero({
    super.key,
    required this.item,
    required this.kicker,
    required this.onTap,
  });

  final BangumiItem item;
  final String kicker;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = item.nameCn.isNotEmpty ? item.nameCn : item.name;
    return GestureDetector(
      onTap: onTap,
      child: AspectRatio(
        aspectRatio: 16 / 10,
        child: Stack(
          fit: StackFit.expand,
          children: [
            NetworkImgLayer(
              src: item.images['large'] ?? '',
              fallbackSrc: item.images['common'],
              width: MediaQuery.sizeOf(context).width,
              height: 260,
              // Batch 47: full-width photographic hero —
              // medium scaling is visually identical and
              // cheaper on the GPU while scrolling.
              filterQuality: FilterQuality.medium,
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black45,
                    Colors.black87,
                  ],
                  stops: [0.25, 0.62, 1],
                ),
              ),
            ),
            Positioned(
              left: 20,
              right: 20,
              bottom: 16,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 22,
                        height: 2,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          kicker,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: Colors.white70,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 2.2,
                          ),
                        ),
                      ),
                      if (item.ratingScore > 0) ...[
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.star_rounded,
                                size: 13,
                                color: Colors.amber,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                item.ratingScore.toStringAsFixed(1),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    [
                      if (item.airDate.length >= 4)
                        item.airDate.substring(0, 4),
                      if (item.rank > 0) 'Bangumi 排名 ${item.rank}',
                      if (item.votes > 0) '${item.votes} 人评分',
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------
// Hero carousel (batch 70)
// ----------------------------------------------------------------

/// The home spotlight as a freely swipeable loop of the
/// top entries: swipe right-to-left to advance, left-to-
/// right to go back, and both directions wrap — after the
/// last comes the first again (and vice versa). No
/// autoplay; the reader drives. Numbered bars under the
/// visual show the position and jump on tap. A single
/// entry degrades to the plain hero.
class EditorialHeroCarousel extends StatefulWidget {
  const EditorialHeroCarousel({
    super.key,
    required this.items,
    required this.kickerFor,
    required this.onTap,
  });

  final List<BangumiItem> items;

  /// Kicker line for the entry at [rank] (0-based).
  final String Function(int rank) kickerFor;
  final void Function(BangumiItem item) onTap;

  @override
  State<EditorialHeroCarousel> createState() =>
      _EditorialHeroCarouselState();
}

class _EditorialHeroCarouselState extends State<EditorialHeroCarousel> {
  late final PageController _controller;
  int _index = 0;

  int get _count => widget.items.length;

  @override
  void initState() {
    super.initState();
    // Start deep into page space so swiping backwards
    // from the first entry also wraps (to the last).
    _controller = PageController(initialPage: _count > 1 ? _count * 1000 : 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _jumpTo(int target) {
    if (_count <= 1) return;
    final current = _controller.page?.round() ?? _count * 1000;
    var delta = (target - _index) % _count;
    if (delta > _count ~/ 2) delta -= _count;
    if (delta == 0) return;
    _controller.animateToPage(
      current + delta,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_count == 0) return const SizedBox.shrink();
    if (_count == 1) {
      return EditorialHero(
        item: widget.items.first,
        kicker: widget.kickerFor(0),
        onTap: () => widget.onTap(widget.items.first),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AspectRatio(
          aspectRatio: 16 / 10,
          child: PageView.builder(
            controller: _controller,
            onPageChanged: (page) =>
                setState(() => _index = page % _count),
            itemBuilder: (context, page) {
              final rank = page % _count;
              final item = widget.items[rank];
              return EditorialHero(
                item: item,
                kicker: widget.kickerFor(rank),
                onTap: () => widget.onTap(item),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 2),
          child: Row(
            children: [
              Text(
                'TOP ${_index + 1} / $_count',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.6,
                ),
              ),
              const Spacer(),
              for (var i = 0; i < _count; i++)
                GestureDetector(
                  onTap: () => _jumpTo(i),
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      width: i == _index ? 24 : 12,
                      height: 3,
                      decoration: BoxDecoration(
                        color: i == _index
                            ? theme.colorScheme.primary
                            : theme.colorScheme.outlineVariant,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// ----------------------------------------------------------------
// Rank row
// ----------------------------------------------------------------

/// A leaderboard row: giant outlined numeral, poster thumb,
/// title + meta, score at the trailing edge.
class EditorialRankRow extends StatelessWidget {
  const EditorialRankRow({
    super.key,
    required this.rank,
    required this.item,
    required this.onTap,
    this.showDivider = true,
    this.enableHero = false,
  });

  final int rank;
  final BangumiItem item;
  final VoidCallback onTap;
  final bool showDivider;

  /// Batch 115: opt-in shared-element cover transition into the
  /// detail page, matching the grid cards. Off by default: the
  /// caller must guarantee no other hero with the same tag is on
  /// screen (the same item often also appears in a grid below).
  final bool enableHero;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final title = item.nameCn.isNotEmpty ? item.nameCn : item.name;
    return InkWell(
      // Batch 58: rapid double taps must not stack the
      // detail route twice.
      onTap: () {
        if (TapDebouncer.accept('info:${item.id}')) onTap();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Column(
          children: [
            Row(
              children: [
                SizedBox(
                  width: 52,
                  child: Text(
                    rank.toString().padLeft(2, '0'),
                    style: theme.textTheme.headlineLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: rank <= 3
                          ? scheme.primary
                          : scheme.onSurface.withValues(alpha: 0.28),
                      height: 1,
                    ),
                  ),
                ),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: enableHero
                      ? Hero(
                          transitionOnUserGestures: true,
                          flightShuttleBuilder:
                              NetworkImgLayer.heroFlightShuttleBuilder,
                          tag: item.id,
                          child: NetworkImgLayer(
                            src: item.images['medium'] ??
                                item.images['large'] ??
                                '',
                            fallbackSrc: item.images['common'],
                            width: 46,
                            height: 62,
                          ),
                        )
                      : NetworkImgLayer(
                          src: item.images['medium'] ??
                              item.images['large'] ??
                              '',
                          fallbackSrc: item.images['common'],
                          width: 46,
                          height: 62,
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        [
                          if (item.airDate.length >= 4)
                            item.airDate.substring(0, 4),
                          if (item.votes > 0) '${item.votes} 人评分',
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (item.ratingScore > 0)
                  Text(
                    item.ratingScore.toStringAsFixed(1),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: scheme.primary,
                    ),
                  ),
              ],
            ),
            if (showDivider) ...[
              const SizedBox(height: 10),
              Container(
                height: 1,
                color: scheme.outlineVariant.withValues(alpha: 0.45),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------
// Index row
// ----------------------------------------------------------------

/// A numbered index row — the editorial replacement for the
/// old two-column entry cards and plain tool rows. Used by
/// 发现 / 工具箱 / 时光 / 我的 for navigation entries.
class EditorialIndexRow extends StatefulWidget {
  const EditorialIndexRow({
    super.key,
    required this.index,
    required this.icon,
    required this.title,
    this.subtitle,
    required this.onTap,
    this.trailingText,
  });

  final String index;
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final String? trailingText;

  @override
  State<EditorialIndexRow> createState() => _EditorialIndexRowState();
}

class _EditorialIndexRowState extends State<EditorialIndexRow> {
  // Batch 58: instance-level tap guard — a fast double tap
  // on a navigation row used to push its route twice.
  DateTime? _lastTap;

  void _handleTap() {
    final now = DateTime.now();
    final last = _lastTap;
    if (last != null &&
        now.difference(last) < TapDebouncer.window) {
      return;
    }
    _lastTap = now;
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return InkWell(
      onTap: _handleTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
        child: Row(
          children: [
            Text(
              widget.index,
              style: theme.textTheme.labelLarge?.copyWith(
                color: scheme.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(width: 14),
            Icon(widget.icon, size: 21, color: scheme.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (widget.subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      widget.subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (widget.trailingText != null) ...[
              Text(
                widget.trailingText!,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 6),
            ],
            Icon(
              Icons.arrow_forward_ios_rounded,
              size: 14,
              color: scheme.outline,
            ),
          ],
        ),
      ),
    );
  }
}

/// Hairline divider aligned with index-row content.
class EditorialHairline extends StatelessWidget {
  const EditorialHairline({super.key, this.indent = 20});

  final double indent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: indent, right: 20),
      child: Container(
        height: 1,
        color: Theme.of(context)
            .colorScheme
            .outlineVariant
            .withValues(alpha: 0.45),
      ),
    );
  }
}
