import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:anikumo/bean/card/network_img_layer.dart';
import 'package:anikumo/bean/dialog/dialog_helper.dart';
import 'package:anikumo/modules/history/history_module.dart';
import 'package:anikumo/modules/manga/manga_item.dart';
import 'package:anikumo/services/library/user_library.dart';
import 'package:anikumo/services/manga/cross_media.dart';
import 'package:anikumo/services/manga/manga_library.dart';
import 'package:anikumo/services/novel/novel_library.dart';
import 'package:anikumo/utils/constants.dart';
import 'package:anikumo/utils/date_time.dart';
import 'package:anikumo/utils/tap_debouncer.dart';
import 'package:anikumo/bean/widget/anikumo_icons.dart';

/// Batch 80: one row of the history page's cross-media
/// modes （全部 / 漫画 / 小说）. The anime mode keeps its own
/// rich list; these entries project the manga and novel
/// reading progress (plus anime histories, for 全部） into
/// one plain, time-ordered shape. Builders are pure so the
/// merge can be unit tested without widgets or storage.
class CrossHistoryEntry {
  const CrossHistoryEntry({
    required this.mode,
    required this.title,
    required this.subtitle,
    required this.timeMs,
    this.coverUrl = '',
    this.anime,
    this.mangaProgress,
    this.novelProgress,
  });

  /// Which medium this entry belongs to (never `all`).
  final CrossSearchMode mode;
  final String title;
  final String subtitle;
  final int timeMs;
  final String coverUrl;
  final History? anime;
  final MangaProgress? mangaProgress;
  final NovelProgress? novelProgress;

  String get kindLabel => switch (mode) {
    CrossSearchMode.anime => '动漫',
    CrossSearchMode.manga => '漫画',
    CrossSearchMode.novel => '小说',
    CrossSearchMode.film => '影视',
    CrossSearchMode.all => '',
  };
}

List<CrossHistoryEntry> mangaHistoryEntries(List<MangaProgress> progress) {
  return [
    for (final p in progress)
      CrossHistoryEntry(
        mode: CrossSearchMode.manga,
        title: p.mangaTitle,
        subtitle: '${p.chapterLabel} · 第 ${p.page + 1} 页',
        timeMs: p.updatedAtMs,
        coverUrl: p.coverUrl,
        mangaProgress: p,
      ),
  ];
}

List<CrossHistoryEntry> novelHistoryEntries(List<NovelProgress> progress) {
  return [
    for (final p in progress)
      CrossHistoryEntry(
        mode: CrossSearchMode.novel,
        title: p.item.title,
        subtitle: p.chapterTitle,
        timeMs: p.updatedAt,
        coverUrl: p.item.coverUrl,
        novelProgress: p,
      ),
  ];
}

List<CrossHistoryEntry> animeHistoryEntries(List<History> histories) {
  return [
    for (final h in histories)
      CrossHistoryEntry(
        mode: CrossSearchMode.anime,
        title: bangumiDisplayTitle(h.bangumiItem),
        subtitle: h.lastWatchEpisodeName.isEmpty
            ? '看到第 ${h.lastWatchEpisode} 话'
            : h.lastWatchEpisodeName,
        timeMs: h.lastWatchTime.millisecondsSinceEpoch,
        coverUrl:
            h.bangumiItem.images['large'] ??
            h.bangumiItem.images['common'] ??
            '',
        anime: h,
      ),
  ];
}

/// The 全部 mode: every medium's records in one
/// newest-first stream.
List<CrossHistoryEntry> buildAllHistoryEntries({
  required List<History> anime,
  required List<MangaProgress> manga,
  required List<NovelProgress> novel,
  int limit = 200,
}) {
  final entries = <CrossHistoryEntry>[
    ...animeHistoryEntries(anime),
    ...mangaHistoryEntries(manga),
    ...novelHistoryEntries(novel),
  ]..sort((a, b) => b.timeMs.compareTo(a.timeMs));
  return entries.take(limit).toList();
}

void _openEntry(
  BuildContext context,
  CrossHistoryEntry entry,
  VoidCallback onReturn,
) {
  switch (entry.mode) {
    case CrossSearchMode.manga:
      final progress = entry.mangaProgress!;
      final item = MangaItem(
        id: progress.mangaId,
        title: progress.mangaTitle,
        description: '',
        coverUrl: progress.coverUrl,
        author: '',
        status: '',
        year: null,
        tags: const [],
        source: progress.mangaSource,
      );
      if (TapDebouncer.accept('manga:${item.source}:${item.id}')) {
        context
            .pushNamed('/manga/detail', arguments: item)
            .then((_) => onReturn());
      }
    case CrossSearchMode.novel:
      final progress = entry.novelProgress!;
      if (TapDebouncer.accept('novel:${progress.item.storageKey}')) {
        context
            .pushNamed('/novel/detail', arguments: progress.item)
            .then((_) => onReturn());
      }
    case CrossSearchMode.anime:
      final history = entry.anime!;
      if (TapDebouncer.accept('anime-info:${history.bangumiItem.id}')) {
        context
            .pushNamed('/info/', arguments: history.bangumiItem)
            .then((_) => onReturn());
      }
    // Batch 231: film entries never occur in this list
    // (film progress lives in the film zone's own store);
    // the case exists for exhaustiveness.
    case CrossSearchMode.film:
    case CrossSearchMode.all:
      break;
  }
}

class _CrossHistoryListView extends StatelessWidget {
  const _CrossHistoryListView({
    required this.entries,
    required this.emptyText,
    required this.showKindTag,
    required this.onReturn,
    this.onDeleteEntry,
  });

  final List<CrossHistoryEntry> entries;
  final String emptyText;
  final bool showKindTag;
  final VoidCallback onReturn;

  /// Batch 98: per-row browsing-history deletion for the
  /// manga / novel entries (anime entries keep the anime
  /// mode's own delete flow). Null hides the affordance.
  final Future<void> Function(CrossHistoryEntry entry)? onDeleteEntry;

  Future<void> _confirmAndDelete(
    BuildContext context,
    CrossHistoryEntry entry,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除这条记录？'),
        content: Text('将移除《${entry.title}》的阅读进度，此操作无法撤销。'),
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
    if (ok != true) return;
    await onDeleteEntry!(entry);
    if (context.mounted) {
      AnikumoDialog.showToast(context: context, message: '已删除');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return Center(child: Text(emptyText));
    }
    final theme = Theme.of(context);
    return ListView.builder(
      padding: const EdgeInsets.symmetric(
        horizontal: StyleString.pagePadding,
        vertical: 8,
      ),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        return InkWell(
          onTap: () => _openEntry(context, entry, onReturn),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Row(
              children: [
                NetworkImgLayer(src: entry.coverUrl, width: 44, height: 62),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        entry.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        formatTimestampToRelativeTime(entry.timeMs),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                ),
                if (showKindTag) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      entry.kindLabel,
                      style: theme.textTheme.labelSmall,
                    ),
                  ),
                ],
                if (onDeleteEntry != null &&
                    (entry.mangaProgress != null ||
                        entry.novelProgress != null))
                  IconButton(
                    tooltip: '删除记录',
                    icon: const Icon(AnikumoIcons.delete_outline_rounded),
                    onPressed: () => _confirmAndDelete(context, entry),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 漫画 mode: the manga zone's reading progress, newest
/// first — the same records as the manga zone's own
/// 阅读历史 page.
class MangaHistoryList extends StatefulWidget {
  const MangaHistoryList({super.key});

  @override
  State<MangaHistoryList> createState() => _MangaHistoryListState();
}

class _MangaHistoryListState extends State<MangaHistoryList> {
  @override
  Widget build(BuildContext context) {
    return _CrossHistoryListView(
      entries: mangaHistoryEntries(MangaLibraryStore.loadProgressList()),
      emptyText: '还没有漫画阅读记录',
      showKindTag: false,
      onReturn: () => setState(() {}),
      onDeleteEntry: (entry) async {
        final progress = entry.mangaProgress;
        if (progress == null) return;
        await MangaLibraryStore.removeProgress(progress.key);
        if (mounted) setState(() {});
      },
    );
  }
}

/// 小说 mode: the novel zone's reading progress.
class NovelHistoryList extends StatefulWidget {
  const NovelHistoryList({super.key});

  @override
  State<NovelHistoryList> createState() => _NovelHistoryListState();
}

class _NovelHistoryListState extends State<NovelHistoryList> {
  @override
  Widget build(BuildContext context) {
    return _CrossHistoryListView(
      entries: novelHistoryEntries(NovelLibraryStore.loadProgressList()),
      emptyText: '还没有小说阅读记录',
      showKindTag: false,
      onReturn: () => setState(() {}),
      onDeleteEntry: (entry) async {
        final progress = entry.novelProgress;
        if (progress == null) return;
        await NovelLibraryStore.removeProgress(progress.item.storageKey);
        if (mounted) setState(() {});
      },
    );
  }
}

/// 全部 mode: anime + manga + novel records merged by
/// time. Anime entries come from the page's controller;
/// manga / novel entries load fresh on every build, so
/// returning from a detail page shows new progress.
class AllHistoryList extends StatefulWidget {
  const AllHistoryList({super.key, required this.animeHistories});

  final List<History> animeHistories;

  @override
  State<AllHistoryList> createState() => _AllHistoryListState();
}

class _AllHistoryListState extends State<AllHistoryList> {
  @override
  Widget build(BuildContext context) {
    return _CrossHistoryListView(
      entries: buildAllHistoryEntries(
        anime: widget.animeHistories,
        manga: MangaLibraryStore.loadProgressList(),
        novel: NovelLibraryStore.loadProgressList(),
      ),
      emptyText: '还没有任何记录',
      showKindTag: true,
      onReturn: () => setState(() {}),
      onDeleteEntry: (entry) async {
        // Only manga / novel rows carry the button; anime
        // records stay owned by the anime mode's flow.
        if (entry.mangaProgress != null) {
          await MangaLibraryStore.removeProgress(entry.mangaProgress!.key);
        } else if (entry.novelProgress != null) {
          await NovelLibraryStore.removeProgress(
            entry.novelProgress!.item.storageKey,
          );
        } else {
          return;
        }
        if (mounted) setState(() {});
      },
    );
  }
}
