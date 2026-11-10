import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../storage/storage.dart';

/// Batch 167: subscription sources — the RSS-format half of
/// the reading-ecosystem source packs (the yckceo 源仓库
/// "rss/json" endpoints are the canonical example). Their
/// entries name themselves with sourceName/sourceUrl and
/// carry article rules (ruleArticles/ruleTitle/ruleLink…)
/// instead of book rules, so the book-source importer used
/// to parse them as nothing at all and the user got a
/// silent zero. They now live in their own registry and
/// are read by the subscription engine on the
/// subscription pages.
///
/// A good share of these entries have no rules at all —
/// they are directory bookmarks to other repositories
/// (singleUrl). The UI opens those as web pages, which is
/// also what the original apps do with them.
class RssSourceDef {
  RssSourceDef(this.raw);

  final Map<String, dynamic> raw;

  String get name => raw['sourceName']?.toString().trim() ?? '';
  String get url => raw['sourceUrl']?.toString().trim() ?? '';

  /// Identity: the trimmed source URL, mirroring how book
  /// sources dedupe on their base URL.
  String get id => url;

  String get icon => raw['sourceIcon']?.toString() ?? '';
  String get group => raw['sourceGroup']?.toString() ?? '';

  String rule(String key) => raw[key]?.toString().trim() ?? '';

  String get sortUrl => rule('sortUrl');
  String get ruleArticles => rule('ruleArticles');
  String get ruleTitle => rule('ruleTitle');
  String get ruleLink => rule('ruleLink');
  String get rulePubDate => rule('rulePubDate');
  String get ruleDescription => rule('ruleDescription');
  String get ruleImage => rule('ruleImage');
  String get ruleContent => rule('ruleContent');

  /// True when the entry can produce an article list at
  /// all; rule-less entries are web bookmarks.
  bool get hasArticleRules => ruleArticles.isNotEmpty || sortUrl.isNotEmpty;
}

/// An entry is a subscription source when it names itself
/// the RSS way, does NOT carry a book-source name, and has
/// no book capability (no searchUrl, no search rules) —
/// mixed packs exist, so classification is per entry. The
/// book-capability guard matters: some foreign book
/// formats also name themselves with sourceName, and those
/// must stay book sources. Rule-less directory bookmarks
/// (name + url only) count as subscription entries.
bool isRssSourceEntry(Map<dynamic, dynamic> entry) {
  final name = entry['sourceName']?.toString().trim() ?? '';
  final url = entry['sourceUrl']?.toString().trim() ?? '';
  final bookName = entry['bookSourceName']?.toString().trim() ?? '';
  if (name.isEmpty || url.isEmpty || bookName.isNotEmpty) return false;
  final searchUrl = entry['searchUrl']?.toString().trim() ?? '';
  final ruleSearch = entry['ruleSearch'];
  final hasSearchRules = ruleSearch is Map
      ? ruleSearch.isNotEmpty
      : (ruleSearch?.toString().trim().isNotEmpty ?? false);
  return searchUrl.isEmpty && !hasSearchRules;
}

/// The .yds packs are a different app's obfuscated rule
/// container (magic header "@header:"), not a text format
/// this app can read. Detect the magic so the importer can
/// say so plainly instead of "unrecognized format".
bool isForeignPackPayload(String text) =>
    text.trimLeft().startsWith('@header:');

class RssSources {
  RssSources._();

  static final ValueNotifier<int> revision = ValueNotifier(0);

  static String? _cachedRaw;
  static List<RssSourceDef> _cache = const [];

  static List<RssSourceDef> all() {
    final raw = GStorage.getSetting(SettingsKeys.novelRssSourcesJson);
    final legacyRawForKey =
        GStorage.getSetting(SettingsKeys.novelInstalledSourcesJson);
    final cacheKey = '$raw\u0000$legacyRawForKey';
    if (cacheKey == _cachedRaw) return _cache;
    _cachedRaw = cacheKey;
    final out = <RssSourceDef>[];
    final seen = <String>{};
    void collect(String text) {
      if (text.isEmpty) return;
      try {
        final decoded = jsonDecode(text);
        if (decoded is List) {
          for (final entry in decoded) {
            if (entry is Map) {
              final def = RssSourceDef(
                entry.map((k, v) => MapEntry(k.toString(), v)),
              );
              if (def.id.isNotEmpty &&
                  def.name.isNotEmpty &&
                  seen.add(def.id)) {
                out.add(def);
              }
            }
          }
        }
      } catch (_) {
        // A corrupt store reads as empty; the next import
        // rewrites it wholesale.
      }
    }

    collect(raw);
    // Batch 167: imports made before subscription support
    // landed in the BOOK registry (the book parser accepts
    // sourceName/sourceUrl as fallbacks, producing rule-less
    // book entries that could never work). Those stored
    // entries surface here as subscriptions, read-only —
    // no storage migration needed — and the book registry
    // hides them (see NovelSources.imported).
    final legacyRaw = legacyRawForKey;
    if (legacyRaw.isNotEmpty) {
      try {
        final decoded = jsonDecode(legacyRaw);
        if (decoded is List) {
          for (final entry in decoded) {
            if (entry is Map && isRssSourceEntry(entry)) {
              final def = RssSourceDef(
                entry.map((k, v) => MapEntry(k.toString(), v)),
              );
              if (def.id.isNotEmpty &&
                  def.name.isNotEmpty &&
                  seen.add(def.id)) {
                out.add(def);
              }
            }
          }
        }
      } catch (_) {
        // Unparseable legacy store: nothing to surface.
      }
    }
    _cache = out;
    return out;
  }

  static RssSourceDef? byId(String id) {
    for (final source in all()) {
      if (source.id == id) return source;
    }
    return null;
  }

  /// Add subscription entries (already classified by the
  /// caller). Returns how many were new.
  static Future<int> importEntries(List<Map<String, dynamic>> entries) async {
    final stored = <Map<String, dynamic>>[
      for (final def in all()) def.raw,
    ];
    final seen = {for (final def in all()) def.id};
    var added = 0;
    for (final entry in entries) {
      final def = RssSourceDef(entry);
      if (def.id.isEmpty || def.name.isEmpty) continue;
      if (!seen.add(def.id)) continue;
      stored.add(entry);
      added++;
    }
    if (added > 0) {
      await _save(stored);
    }
    return added;
  }

  static Future<void> remove(String id) async {
    final rssRaw = GStorage.getSetting(SettingsKeys.novelRssSourcesJson);
    final stored = <Map<String, dynamic>>[];
    if (rssRaw.isNotEmpty) {
      try {
        final decoded = jsonDecode(rssRaw);
        if (decoded is List) {
          for (final entry in decoded) {
            if (entry is Map) {
              final def = RssSourceDef(
                entry.map((k, v) => MapEntry(k.toString(), v)),
              );
              if (def.id != id) stored.add(def.raw);
            }
          }
        }
      } catch (_) {
        // Keep _save semantics: a corrupt store is rewritten.
      }
    }
    await _save(stored);
    // Legacy copies live in the book registry; scrub there
    // too or the union in all() would resurrect the entry.
    final legacyRaw =
        GStorage.getSetting(SettingsKeys.novelInstalledSourcesJson);
    if (legacyRaw.isNotEmpty) {
      try {
        final decoded = jsonDecode(legacyRaw);
        if (decoded is List) {
          bool matchesId(Object? entry) {
            if (entry is! Map) return false;
            final url =
                (entry['bookSourceUrl'] ?? entry['sourceUrl'] ?? entry['url'])
                    ?.toString()
                    .trim();
            return url == id;
          }

          final kept = <dynamic>[
            for (final entry in decoded)
              if (!matchesId(entry)) entry,
          ];
          if (kept.length != decoded.length) {
            await GStorage.putSetting(
              SettingsKeys.novelInstalledSourcesJson,
              jsonEncode(kept),
            );
            _cachedRaw = null;
            revision.value++;
          }
        }
      } catch (_) {
        // Unparseable legacy store: nothing to scrub.
      }
    }
  }

  static Future<void> _save(List<Map<String, dynamic>> stored) async {
    await GStorage.putSetting(
      SettingsKeys.novelRssSourcesJson,
      jsonEncode(stored),
    );
    _cachedRaw = null;
    revision.value++;
  }
}
