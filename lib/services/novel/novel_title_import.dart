import 'dart:convert';

import 'package:anikumo/models/novel_item.dart';

/// Batch 280 (#13): title-list import for the novel
/// zone — the film zone's 片单导入 (batch 272) interaction
/// rebuilt on novel seams (the manga zone got its own in
/// batch 279): paste or pick a title list, each title is
/// searched in the enabled sources, the user confirms
/// the matches, and the picks land in the novel
/// favorites.
///
/// Accepted input: a plain-text list (one title per
/// line, '#' comments allowed), a JSON document with a
/// "favorites" array of title-carrying objects, or the
/// favorites storage array itself. Bare titles cannot
/// restore the original entries, so every title goes
/// through search like the other zones' imports.
/// Duplicates collapse. The caller applies the 30-title
/// cap, mirroring the film flow.
List<String> parseNovelTitleList(String content) {
  final trimmed = content.trim();
  if (trimmed.isEmpty) return const [];
  if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
    try {
      final decoded = jsonDecode(trimmed);
      final rawList = decoded is Map
          ? decoded['favorites']
          : decoded is List
              ? decoded
              : null;
      if (rawList is List) {
        final titles = <String>[];
        for (final raw in rawList) {
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
NovelItem? pickNovelImportMatch(List<NovelItem> results, String title) {
  for (final item in results) {
    if (item.title == title) return item;
  }
  return results.firstOrNull;
}
