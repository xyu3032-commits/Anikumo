import 'dart:convert';

import 'package:anikumo/modules/manga/manga_item.dart';

/// Batch 279 (#11): title-list import for the manga
/// zone — the film zone's 片单导入 (batch 272) interaction
/// rebuilt on manga seams: paste or pick a title list,
/// each title is searched in the enabled sources, the
/// user confirms the matches, and the picks land in the
/// manga favorites.
///
/// Accepted input: a plain-text list (one title per
/// line, '#' comments allowed) or this app's own manga
/// library export document (its favorites' titles are
/// taken — the entries themselves cannot be restored
/// from a bare list, so they go through search like
/// every other title). Duplicates collapse. The caller
/// applies the 30-title cap, mirroring the film flow.
List<String> parseMangaTitleList(String content) {
  final trimmed = content.trim();
  if (trimmed.isEmpty) return const [];
  if (trimmed.startsWith('{')) {
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map && decoded['favorites'] is List) {
        final titles = <String>[];
        for (final raw in decoded['favorites'] as List) {
          if (raw is Map) {
            final title = raw['title']?.toString().trim() ?? '';
            if (title.isNotEmpty && !titles.contains(title)) {
              titles.add(title);
            }
          }
        }
        if (titles.isNotEmpty) return titles;
      }
    } catch (_) {
      // Not JSON after all — fall through to plain text.
    }
  }
  final titles = <String>[];
  for (final line in trimmed.split('\n')) {
    final title = line.trim();
    if (title.isEmpty || title.startsWith('#')) continue;
    if (!titles.contains(title)) titles.add(title);
  }
  return titles;
}

/// The match one imported [title] resolves to: an exact
/// title hit wins; otherwise the first search result
/// (the film import's rule). Null when nothing was found.
MangaItem? pickMangaImportMatch(List<MangaItem> results, String title) {
  for (final item in results) {
    if (item.title == title) return item;
  }
  return results.firstOrNull;
}
