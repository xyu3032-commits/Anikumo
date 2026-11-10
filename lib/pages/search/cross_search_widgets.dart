import 'package:flutter/material.dart';
import 'package:anikumo/bean/theme/signature.dart';
import 'package:anikumo/bean/widget/search_stage.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:anikumo/bean/card/bangumi_card.dart';
import 'package:anikumo/modules/bangumi/bangumi_item.dart';
import 'package:anikumo/modules/manga/manga_item.dart';
import 'package:anikumo/pages/manga/manga_widgets.dart';
import 'package:anikumo/services/manga/cross_media.dart';
import 'package:anikumo/services/manga/manga_sources.dart';
import 'package:anikumo/models/novel_item.dart';
import 'package:anikumo/pages/novel/novel_widgets.dart';
import 'package:anikumo/services/novel/novel_sources.dart';
import 'package:anikumo/bean/widget/anikumo_icons.dart';

/// The animated 全部 / 动漫 / 漫画 segmented switch shared by the
/// anime search page and the manga search page. Selection slides
/// with an AnimatedContainer so every switch is visibly animated.
class CrossSearchModeSwitch extends StatelessWidget {
  const CrossSearchModeSwitch({
    super.key,
    required this.mode,
    required this.onChanged,
  });

  final CrossSearchMode mode;
  final ValueChanged<CrossSearchMode> onChanged;

  static const _icons = {
    CrossSearchMode.all: AnikumoIcons.dashboard_rounded,
    CrossSearchMode.anime: AnikumoIcons.smart_display_rounded,
    CrossSearchMode.manga: AnikumoIcons.menu_book_rounded,
    CrossSearchMode.novel: AnikumoIcons.import_contacts_rounded,
  };

  @override
  Widget build(BuildContext context) {
    // Batch 110: the shared PillSwitch — gradient capsule,
    // icons, animated selection. Same API as before.
    return PillSwitch<CrossSearchMode>(
      value: mode,
      onChanged: onChanged,
      options: [
        for (final option in CrossSearchMode.values)
          PillSwitchOption(
            value: option,
            label: option.label,
            icon: _icons[option],
          ),
      ],
    );
  }
}

/// Manga results as a sliver grid (used inside the anime search
/// page's CustomScrollView).
class MangaResultsSliver extends StatelessWidget {
  const MangaResultsSliver({
    super.key,
    required this.items,
    this.showSourceBadge = false,
  });

  final List<MangaItem> items;
  final bool showSourceBadge;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final columns = width < 600 ? 3 : (width < 900 ? 5 : 6);
    final sourceNames = {
      for (final source in MangaSources.all()) source.id: source.name,
    };
    return SliverGrid.builder(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        mainAxisSpacing: 14,
        crossAxisSpacing: 12,
        childAspectRatio: 0.52,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return MangaRailCard(
            item: item,
            badge: showSourceBadge
                ? (sourceNames[item.source] ?? item.source)
                : null,
            width: double.infinity,
            onTap: () =>
                context.pushNamed('/manga/detail', arguments: item),
        );
      },
    );
  }
}

/// Manga results as a shrink-wrapped grid (used inside simple
/// ListViews, e.g. the manga search page's 全部 pane).
class MangaResultsGrid extends StatelessWidget {
  const MangaResultsGrid({
    super.key,
    required this.items,
    this.shrinkWrap = false,
    this.showSourceBadge = false,
  });

  final List<MangaItem> items;
  final bool shrinkWrap;

  /// Overlays each card with its source's name (aggregated
  /// multi-source search results).
  final bool showSourceBadge;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final columns = width < 600 ? 3 : (width < 900 ? 5 : 6);
    final sourceNames = {
      for (final source in MangaSources.all()) source.id: source.name,
    };
    return GridView.builder(
      shrinkWrap: shrinkWrap,
      physics: shrinkWrap ? const NeverScrollableScrollPhysics() : null,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        mainAxisSpacing: 14,
        crossAxisSpacing: 12,
        childAspectRatio: 0.52,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return MangaRailCard(
            item: item,
            badge: showSourceBadge
                ? (sourceNames[item.source] ?? item.source)
                : null,
            width: double.infinity,
            onTap: () =>
                context.pushNamed('/manga/detail', arguments: item),
        );
      },
    );
  }
}

/// Anime results as a shrink-wrapped grid of the standard
/// BangumiCardV (used by the manga search page's anime panes).
class AnimeResultsGrid extends StatelessWidget {
  const AnimeResultsGrid({
    super.key,
    required this.items,
    this.shrinkWrap = false,
  });

  final List<BangumiItem> items;
  final bool shrinkWrap;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final columns = width < 600 ? 3 : (width < 900 ? 5 : 6);
    final cellWidth =
        (width - 32 - (columns - 1) * 12) / columns;
    return GridView.builder(
      shrinkWrap: shrinkWrap,
      physics: shrinkWrap ? const NeverScrollableScrollPhysics() : null,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        mainAxisSpacing: 14,
        crossAxisSpacing: 12,
        mainAxisExtent: cellWidth / 0.65 + 52,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) => BangumiCardV(
        bangumiItem: items[index],
        canTap: true,
      ),
    );
  }
}

/// Anime results as a sliver grid — the lazy-loading twin of
/// [AnimeResultsGrid] for CustomScrollView panes (avoids the
/// build-everything cost of shrinkWrap grids).
class AnimeResultsSliver extends StatelessWidget {
  const AnimeResultsSliver({super.key, required this.items});

  final List<BangumiItem> items;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final columns = width < 600 ? 3 : (width < 900 ? 5 : 6);
    final cellWidth =
        (width - 32 - (columns - 1) * 12) / columns;
    return SliverGrid.builder(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        mainAxisSpacing: 14,
        crossAxisSpacing: 12,
        mainAxisExtent: cellWidth / 0.65 + 52,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) => BangumiCardV(
        bangumiItem: items[index],
        canTap: true,
      ),
    );
  }
}

/// A section title used to separate 动漫 / 漫画 blocks in the
/// unified 全部 results.
class CrossSectionHeader extends StatelessWidget {
  const CrossSectionHeader({
    super.key,
    required this.title,
    required this.count,
    this.busy = false,
    this.trailing,
  });

  final String title;
  final int count;

  /// Batch 110: while this section's sources are still
  /// answering, a small spinner rides the header.
  final bool busy;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 22, bottom: 12),
      child: Row(
        children: [
          const SectionAccentBar(height: 20),
          const SizedBox(width: 9),
          Text(
            title,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w800, fontSize: 17),
          ),
          const SizedBox(width: 9),
          Text(
            '$count',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.outline),
          ),
          if (busy) ...[
            const SizedBox(width: 10),
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: theme.colorScheme.primary,
              ),
            ),
          ],
          if (trailing != null) ...[
            const Spacer(),
            trailing!,
          ],
        ],
      ),
    );
  }
}

/// Batch 48: novel results as a sliver of rows (cover,
/// title, author · source), shared by both cross-search
/// pages' novel mode and their 全部 sections. Tapping a row
/// opens the novel in its own zone's detail page.
class NovelResultsSliver extends StatelessWidget {
  const NovelResultsSliver({super.key, required this.items});

  final List<NovelItem> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SliverList.builder(
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final sourceName =
            NovelSources.byId(item.source)?.name ?? item.source;
        return InkWell(
          onTap: () =>
              context.pushNamed('/novel/detail', arguments: item),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Row(
              children: [
                NovelCover(url: item.coverUrl, width: 46, height: 62),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        [
                          if (item.author.isNotEmpty) item.author,
                          sourceName,
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  AnikumoIcons.chevron_right,
                  size: 18,
                  color: theme.colorScheme.outline,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
