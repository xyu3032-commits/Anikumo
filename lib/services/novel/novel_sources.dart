import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../storage/storage.dart';
import '../../utils/github_links.dart';
import 'legado_def.dart';
import 'legado_http.dart';
import 'legado_parse.dart';
import 'local_books.dart';
import 'novel_features.dart';
import 'novel_source.dart';
import 'rss_sources.dart';

/// Batch 66: the outcome of probing an import payload.
class ImportProbe {
  const ImportProbe({
    required this.entries,
    required this.recognized,
    required this.encrypted,
    this.rss = 0,
    this.foreignPack = false,
  });

  /// Source-shaped entries found in the payload.
  final int entries;

  /// Entries with a usable name + url.
  final int recognized;

  /// Entries carrying _H006_ encrypted rules.
  final int encrypted;

  /// Batch 167: entries that are subscription (RSS-format)
  /// sources rather than book sources.
  final int rss;

  /// Batch 167: the payload is a foreign app's obfuscated
  /// rule pack (the .yds container), not a text format.
  final bool foreignPack;
}

/// Registry of novel sources. Batch 59: the app ships
/// with NO built-in sources — every source here was
/// imported by the user (URL / paste / file).
class NovelSources {
  NovelSources._();

  static final ValueNotifier<int> revision = ValueNotifier(0);

  /// Batch 52: imported() used to re-parse the whole
  /// installed-sources JSON and construct FRESH source (and
  /// engine) objects on every call — and it is called by
  /// all(), which byId() calls per lookup, which the search
  /// results, detail pages and the home build call per item
  /// and per rebuild. With dozens of imported sources every
  /// frame of the novel zone paid a full re-parse, and the
  /// fresh instances also threw away each source's learned
  /// TOC-URL cache, so chapter loads re-ran bookInfo every
  /// time. The parsed list is now memoized until the stored
  /// JSON actually changes (import / remove invalidate).
  static List<LegadoNovelSource>? _importedCache;

  /// Batch 167: the subscription-filtered view of
  /// [_importedCache], memoized alongside it — callers
  /// (MangaSources.all among them) key their own memos on
  /// this list's identity, so it must stay identical while
  /// the raw cache is unchanged.
  static List<LegadoNovelSource>? _importedFilteredCache;

  static void _invalidateImported() {
    _importedCache = null;
    _importedFilteredCache = null;
  }

  /// Batch 83: backup restore writes the registry JSON
  /// directly through GStorage; drop the memoized parse and
  /// notify listeners so the restored sources take effect
  /// without an app restart.
  static void invalidateImportedCache() {
    _invalidateImported();
    revision.value++;
  }

  static List<LegadoNovelSource> imported() {
    final filtered = _importedFilteredCache;
    if (filtered != null) return filtered;
    var cached = _importedCache;
    if (cached != null) {
      return _importedFilteredCache = [
        for (final source in cached)
          if (!isRssSourceEntry(source.def.raw)) source,
      ];
    }
    final raw = GStorage.getSetting(SettingsKeys.novelInstalledSourcesJson);
    if (raw.isEmpty) {
      _importedCache = const [];
      _importedFilteredCache = const [];
      return const [];
    }
    final out = <LegadoNovelSource>[];
    for (final json in LegadoParse.parseSourceArray(raw)) {
      final def = LegadoSourceDef.fromJson(json);
      // Batch 65: def.enabled is NO longer a filter. In a
      // Legado bundle the `enabled` flag records whether
      // the source was switched on in the EXPORTER's app
      // (real bundles ship ~half their sources disabled —
      // XIU2 精品： 10 of 22). Filtering on it made those
      // sources silently nonexistent here while import
      // still counted them as added: the sources tab never
      // showed them, re-importing reported 都已存在， and
      // they could not even be deleted (never listed).
      // An imported source is an installed source.
      if (def != null) out.add(LegadoNovelSource(def));
    }
    _importedCache = out;
    return _importedFilteredCache = [
      for (final source in out)
        if (!isRssSourceEntry(source.def.raw)) source,
    ];
  }

  static List<NovelSource> all() {
    final seen = <String>{};
    final out = <NovelSource>[];
    for (final source in imported()) {
      if (seen.add(source.id)) out.add(source);
    }
    // Batch 158: the local-books source exists only while
    // its feature is installed in the feature repository.
    if (NovelFeatures.isInstalled(NovelFeatures.localBooksId) &&
        seen.add(LocalNovelSource.sourceId)) {
      out.add(const LocalNovelSource());
    }
    return out;
  }

  static NovelSource? byId(String id) {
    for (final source in all()) {
      if (source.id == id) return source;
    }
    return null;
  }

  /// The active source, or null when the user has not
  /// imported any source yet (batch 59: zero sources is a
  /// normal state).
  static NovelSource? activeOrNull() {
    final sources = all();
    if (sources.isEmpty) return null;
    final wanted = GStorage.getSetting(SettingsKeys.novelActiveSource);
    return byId(wanted) ?? sources.first;
  }

  static NovelSource active() {
    final source = activeOrNull();
    if (source == null) {
      throw StateError('没有可用的小说源');
    }
    return source;
  }

  static Future<void> setActive(String id) async {
    await GStorage.putSetting(SettingsKeys.novelActiveSource, id);
    revision.value++;
  }

  /// Import sources from raw text (plain JSON, a single
  /// object, or base16). Returns how many were added (new
  /// ids) — duplicates by bookSourceUrl are skipped.
  static Future<int> importFromText(String text) async {
    final (book, rss) = await importFromTextSplit(text);
    return book + rss;
  }

  /// Batch 167: the split form — subscription (RSS-format)
  /// entries in the payload are routed to the subscription
  /// registry instead of being dropped by the book-source
  /// parser, and the caller learns how many of each kind
  /// were added: (bookAdded, rssAdded).
  static Future<(int, int)> importFromTextSplit(String text) async {
    final incomingAll = LegadoParse.parseSourceArray(text);
    if (incomingAll.isEmpty) return (0, 0);
    final rssEntries = <Map<String, dynamic>>[
      for (final entry in incomingAll)
        if (isRssSourceEntry(entry)) entry,
    ];
    final rssAdded = rssEntries.isEmpty
        ? 0
        : await RssSources.importEntries(rssEntries);
    final incoming = <Map<String, dynamic>>[
      for (final entry in incomingAll)
        if (!isRssSourceEntry(entry)) entry,
    ];
    if (incoming.isEmpty) return (0, rssAdded);
    final existingRaw =
        GStorage.getSetting(SettingsKeys.novelInstalledSourcesJson);
    final stored = LegadoParse.parseSourceArray(existingRaw);
    // Batch 65: dedupe on the NORMALIZED def id (trimmed
    // bookSourceUrl via fromJson) on both sides. Seeding
    // with raw stored strings missed entries whose stored
    // URL carried stray whitespace — those could be
    // re-imported as phantom duplicates while the matching
    // removeImported also failed to find them.
    final seen = <String>{
      for (final s in stored)
        if (LegadoSourceDef.fromJson(s) case final def?) def.id,
    };
    var added = 0;
    for (final json in incoming) {
      final def = LegadoSourceDef.fromJson(json);
      if (def == null) continue;
      if (!seen.add(def.id)) continue;
      stored.add(json);
      added++;
    }
    if (added > 0) {
      await GStorage.putSetting(
        SettingsKeys.novelInstalledSourcesJson,
        jsonEncode(stored),
      );
      _invalidateImported();
      revision.value++;
    }
    return (added, rssAdded);
  }

  /// Import from a URL: a direct JSON/base16 file (the
  /// aoaostar bundles and the liruohrh raw files both work).
  /// Batch 63: a GitHub *file page* address (…/blob/…) is
  /// transparently rewritten to the raw file address —
  /// downloading the page itself would yield HTML.
  static Future<int> importFromUrl(String url) async {
    final ((book, rss), _) = await importFromUrlDiagnosed(url);
    return book + rss;
  }

  /// Batch 66: importFromUrl plus a probe of the payload,
  /// so the UI can say WHY nothing was added (unrecognized
  /// format vs. entries missing name/url vs. all already
  /// installed) instead of one misleading line for all.
  static Future<((int, int), ImportProbe)> importFromUrlDiagnosed(
    String url,
  ) async {
    final effective = GithubLinks.rawFileUrl(url) ?? url.trim();
    final response = await LegadoHttp.fetchRaw(effective);
    if (response.statusCode >= 400) {
      throw StateError('下载失败（${response.statusCode}）');
    }
    final probe = probeImport(response.body);
    final added = await importFromTextSplit(response.body);
    return (added, probe);
  }

  /// What a payload contains, without importing it:
  /// how many entries parsed, how many are recognizable
  /// sources (name + url), and how many carry _H006_
  /// encrypted rules (a YueDu-era protection scheme whose
  /// encrypted sections this app cannot decrypt — those
  /// sources import, but the encrypted parts won't run).
  static ImportProbe probeImport(String text) {
    final entries = LegadoParse.parseSourceArray(text);
    var recognized = 0;
    var encrypted = 0;
    var rss = 0;
    for (final entry in entries) {
      final rssEntry = isRssSourceEntry(entry);
      if (rssEntry) {
        rss++;
      } else if (LegadoSourceDef.fromJson(entry) != null) {
        recognized++;
      }
      if (_hasEncryptedRules(entry)) encrypted++;
    }
    return ImportProbe(
      entries: entries.length,
      recognized: recognized,
      encrypted: encrypted,
      rss: rss,
      foreignPack: entries.isEmpty && isForeignPackPayload(text),
    );
  }

  static bool _hasEncryptedRules(Map<String, dynamic> entry) {
    bool hit(Object? v) {
      if (v is String) return v.contains('_H006_');
      if (v is Map) return v.values.any(hit);
      if (v is List) return v.any(hit);
      return false;
    }

    return entry.values.any(hit);
  }

  /// Whether a stored registry entry belongs to one of
  /// [ids]. Batch 159: the match is a plain string compare
  /// on the entry's URL fields — the def id IS the trimmed
  /// URL (see LegadoSourceDef.fromJson), so this is exactly
  /// the old `fromJson(s)?.id == id` test without paying a
  /// full def parse per entry per deletion.
  static bool _storedEntryIn(Map<String, dynamic> entry, Set<String> ids) {
    final raw =
        (entry['bookSourceUrl'] ?? entry['sourceUrl'] ?? entry['url'])
            ?.toString();
    if (raw == null) return false;
    return ids.contains(raw) || ids.contains(raw.trim());
  }

  /// Batch 159: removes a whole set of imported sources in
  /// ONE pass — one registry parse, one encode, one write,
  /// and the side registries (dead / strikes / pins) swept
  /// once for the whole set. The memoized parse is updated
  /// surgically (survivors keep their instances and their
  /// learned TOC caches) instead of being dropped, so the
  /// list rebuild right after a deletion no longer re-parses
  /// every remaining source. The old per-id path re-ran all
  /// of that for EVERY source — deleting a handful from a
  /// big bundle was quadratic and visibly stalled the tab.
  /// Returns how many stored entries were removed.
  static Future<int> removeImportedBatch(Set<String> ids) async {
    if (ids.isEmpty) return 0;
    final raw = GStorage.getSetting(SettingsKeys.novelInstalledSourcesJson);
    final stored = LegadoParse.parseSourceArray(raw);
    final before = stored.length;
    // Batch 65: match on the normalized def id as well as
    // the raw string — a stored URL with stray whitespace
    // used to survive deletion, so the source "came back"
    // and re-importing it reported 都已存在.
    stored.removeWhere((s) => _storedEntryIn(s, ids));
    final removed = before - stored.length;
    await GStorage.putSetting(
      SettingsKeys.novelInstalledSourcesJson,
      jsonEncode(stored),
    );
    final cache = _importedCache;
    if (cache != null) {
      _importedCache = [
        for (final source in cache)
          if (!ids.contains(source.id)) source,
      ];
      _importedFilteredCache = null;
    }
    final dead = deadSourceIds();
    final deadBefore = dead.length;
    dead.removeAll(ids);
    if (dead.length != deadBefore) {
      await GStorage.putSetting(
        SettingsKeys.novelDeadSourceIds,
        jsonEncode(dead.toList()),
      );
    }
    final strikes = _strikeCounts();
    final strikesBefore = strikes.length;
    strikes.removeWhere((id, _) => ids.contains(id));
    if (strikes.length != strikesBefore) await _saveStrikes(strikes);
    final pins = pinnedIds();
    if (pins.any(ids.contains)) {
      await GStorage.putSetting(
        SettingsKeys.novelPinnedSourceIds,
        jsonEncode(pins.where((e) => !ids.contains(e)).toList()),
      );
    }
    revision.value++;
    return removed;
  }

  static Future<void> removeImported(String id) async {
    await removeImportedBatch({id});
  }

  // ---- Batch 42/46: dead-source registry ------------------
  //
  // Batch 42 marked only dead domains (Failed host lookup).
  // Batch 46 (user report: 铅笔 403 / 艾途 502 / 快书 握手失败
  // sat on the home tab forever, never badged, never
  // auto-deleted): a source also counts as dead when the
  // site refuses or cannot serve us at all — HTTP 4xx/5xx,
  // TLS handshake failure, refused/reset connections. A
  // later success clears the mark. Auto-delete stays
  // conservative: it needs TWO recorded strikes (see
  // recordDead), so a single bad evening deletes nothing.

  static Set<String> deadSourceIds() {
    final raw = GStorage.getSetting(SettingsKeys.novelDeadSourceIds);
    if (raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return {for (final e in decoded) e.toString()};
      }
    } catch (_) {}
    return {};
  }

  static bool isDead(String id) => deadSourceIds().contains(id);

  static bool get autoDeleteDeadSources =>
      GStorage.getSetting(SettingsKeys.novelAutoDeleteDeadSources);

  static Future<void> setAutoDeleteDeadSources(bool value) async {
    await GStorage.putSetting(
      SettingsKeys.novelAutoDeleteDeadSources,
      value,
    );
    revision.value++;
  }

  /// Is this failure the site being gone / refusing us
  /// (rather than a slow or flaky moment)? [rawError] is the
  /// unformatted error text. Timeouts deliberately do NOT
  /// count — a slow site is not a dead site.
  static bool isHardDeadError(String rawError) {
    if (rawError.contains('Failed host lookup')) return true;
    if (rawError.contains('HandshakeException')) return true;
    if (rawError.contains('SocketException')) return true;
    final status = RegExp(r'源站返回\s*(\d{3})').firstMatch(rawError);
    if (status != null) {
      final code = int.tryParse(status.group(1)!) ?? 0;
      if (code >= 400 && code < 600) return true;
    }
    return false;
  }

  static Map<String, int> _strikeCounts() {
    final raw = GStorage.getSetting(SettingsKeys.novelDeadStrikeCounts);
    if (raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return {
          for (final e in decoded.entries)
            e.key.toString(): (e.value as num?)?.toInt() ?? 0,
        };
      }
    } catch (_) {}
    return {};
  }

  static Future<void> _saveStrikes(Map<String, int> strikes) =>
      GStorage.putSetting(
        SettingsKeys.novelDeadStrikeCounts,
        jsonEncode(strikes),
      );

  /// Records one hard failure for [id]: the source joins
  /// the dead set (badge + home hides it) on the first
  /// strike; with auto-delete enabled an IMPORTED source is
  /// removed on the second strike.
  static Future<void> recordDead(String id) async {
    final source = byId(id);
    if (source == null) return;
    final strikes = _strikeCounts();
    final count = (strikes[id] ?? 0) + 1;
    strikes[id] = count;
    await _saveStrikes(strikes);
    if (autoDeleteDeadSources && count >= 2) {
      await removeImported(id);
      return;
    }
    final dead = deadSourceIds();
    if (dead.add(id)) {
      await GStorage.putSetting(
        SettingsKeys.novelDeadSourceIds,
        jsonEncode(dead.toList()),
      );
      revision.value++;
    }
  }

  static Future<void> clearDead(String id) async {
    final strikes = _strikeCounts();
    if (strikes.remove(id) != null) await _saveStrikes(strikes);
    final dead = deadSourceIds();
    if (dead.remove(id)) {
      await GStorage.putSetting(
        SettingsKeys.novelDeadSourceIds,
        jsonEncode(dead.toList()),
      );
      revision.value++;
    }
  }

  // ---- Batch 46: pinned sources ----------------------------

  /// Pinned source ids, in the order the user pinned them.
  static List<String> pinnedIds() {
    final raw = GStorage.getSetting(SettingsKeys.novelPinnedSourceIds);
    if (raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return [for (final e in decoded) e.toString()];
      }
    } catch (_) {}
    return const [];
  }

  static bool isPinned(String id) => pinnedIds().contains(id);

  static Future<void> togglePin(String id) async {
    final pins = [...pinnedIds()];
    if (pins.contains(id)) {
      pins.remove(id);
    } else {
      pins.add(id);
    }
    await GStorage.putSetting(
      SettingsKeys.novelPinnedSourceIds,
      jsonEncode(pins),
    );
    revision.value++;
  }

  /// Display order for source lists: pinned sources first
  /// (in pin order), the rest in their original order.
  static List<NovelSource> sortForDisplay(
    List<NovelSource> sources, {
    List<String>? pinned,
  }) {
    final pins = pinned ?? pinnedIds();
    if (pins.isEmpty) return sources;
    final byIdMap = {for (final s in sources) s.id: s};
    return [
      for (final id in pins)
        if (byIdMap.containsKey(id)) byIdMap[id]!,
      for (final s in sources)
        if (!pins.contains(s.id)) s,
    ];
  }

  /// Removes every dead source in one batch pass.
  /// Returns how many were removed.
  static Future<int> cleanupDeadImported() async {
    final dead = deadSourceIds();
    final ids = {
      for (final source in imported())
        if (dead.contains(source.id)) source.id,
    };
    if (ids.isEmpty) return 0;
    return removeImportedBatch(ids);
  }

}
