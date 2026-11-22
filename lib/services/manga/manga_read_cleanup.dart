import 'package:anikumo/services/manga/manga_downloads.dart';
import 'package:anikumo/services/manga/manga_library.dart';

/// Batch 279 (#9): which downloaded chapters count as
/// "already read", for the downloads page's one-tap
/// cleanup of read chapters.
///
/// [MangaProgress] only remembers where the reader
/// stopped per manga (one chapter + page), so "read" is
/// derived from it:
/// - every downloaded chapter BEFORE the progress chapter
///   in the source's chapter order counts as read;
/// - the progress chapter itself counts once its last
///   page was reached;
/// - chapters after it, and everything about a manga
///   with no progress, never count.
///
/// [chapterOrderIds] is the source's chapter list order
/// (oldest first, as MangaApi.fetchChapters returns it).
/// When the order is unavailable (offline, source gone),
/// only the "progress chapter finished" rule can fire —
/// the conservative direction: when in doubt, keep the
/// download.
bool downloadedChapterIsRead({
  required MangaDownloadEntry entry,
  required MangaProgress? progress,
  required List<String> chapterOrderIds,
}) {
  if (progress == null) return false;
  if (progress.key != '${entry.source}:${entry.mangaId}') return false;
  final finishedCurrent = progress.totalPages > 0 &&
      progress.page >= progress.totalPages - 1;
  if (entry.chapterId == progress.chapterId) return finishedCurrent;
  final entryIndex = chapterOrderIds.indexOf(entry.chapterId);
  final progressIndex = chapterOrderIds.indexOf(progress.chapterId);
  if (entryIndex < 0 || progressIndex < 0) return false;
  return entryIndex < progressIndex;
}

/// The subset of [entries] that [downloadedChapterIsRead]
/// accepts. [progressByKey] is MangaProgress keyed by
/// 'source:mangaId'; [chapterOrderByMangaKey] maps the
/// same key to the source's chapter order (missing or
/// empty = order unknown).
List<MangaDownloadEntry> readDownloadedChapters({
  required List<MangaDownloadEntry> entries,
  required Map<String, MangaProgress> progressByKey,
  required Map<String, List<String>> chapterOrderByMangaKey,
}) {
  return [
    for (final entry in entries)
      if (downloadedChapterIsRead(
        entry: entry,
        progress: progressByKey['${entry.source}:${entry.mangaId}'],
        chapterOrderIds:
            chapterOrderByMangaKey['${entry.source}:${entry.mangaId}'] ??
                const [],
      ))
        entry,
  ];
}
