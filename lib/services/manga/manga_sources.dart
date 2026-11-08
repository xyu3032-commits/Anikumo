import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:anikumo/services/manga/js/js_manga_source.dart';
import 'package:anikumo/services/manga/js/venera_engine.dart';
import 'package:anikumo/services/manga/legado_manga_source.dart';
import 'package:anikumo/services/manga/local_manga_source.dart';
import 'package:anikumo/services/manga/manga_source.dart';
import 'package:anikumo/services/novel/legado_def.dart';
import 'package:anikumo/services/novel/legado_parse.dart';
import 'package:anikumo/services/novel/novel_source.dart';
import 'package:anikumo/services/novel/novel_sources.dart';
import 'package:anikumo/services/storage/storage.dart';

/// Batch 88: one entry of a Venera source index (the
/// venera-configs `index.json` shape): a display [name], the
/// source [key], its [version], and the [fileName] of the .js
/// file (relative to the index URL, or an absolute URL).
typedef VeneraIndexEntry = ({
  String name,
  String key,
  String version,
  String fileName
});

/// The source registry. Batch 59: the app ships with NO
/// built-in sources — every manga source here is a Venera
/// JS source the user imported themselves (URL / paste /
/// file). This registry tracks those sources and which
/// one is active.
class MangaSources {
  MangaSources._();

  /// Bumped whenever the source set or the active source changes,
  /// so mounted tabs can reload their content for the new source.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static void _bump() => revision.value++;

  /// Batch 83: for writers that replace the registry JSON
  /// outside the install / remove paths (backup restore).
  /// The batch-79 memoized decode keys on the raw string,
  /// so content refreshes by itself; this only notifies
  /// listeners.
  static void notifyRegistryChanged() => _bump();

  // ---- downloaded JS sources (Venera format) ----

  /// Live engines, one per installed JS source, keyed by the
  /// source's registry id (`js:<key>`). Rebuilt when the stored
  /// code changes (a re-download / update).
  static final Map<String, JsMangaSource> _jsCache = {};

  // Batch 79: the stored JSON embeds every installed source's
  // full JS code (hundreds of KB in total). installed() / all()
  // are called from builds and per-item lookups all over the
  // manga zone, and each call used to re-decode the whole blob
  // on the UI isolate — a prime suspect for the zone-entry
  // jank users report (taps dead until the zone settles). The
  // decode is now memoized on the raw string (the novel
  // registry got the same treatment in batch 52); installs,
  // removals and updates rewrite the string and invalidate
  // the cache naturally.
  static String? _entriesRaw;
  static List<Map<String, dynamic>> _entriesCache = const [];

  static List<Map<String, dynamic>> installedJsEntries() {
    final raw = GStorage.getSetting(SettingsKeys.mangaJsSourcesJson);
    if (raw == _entriesRaw) return _entriesCache;
    _entriesRaw = raw;
    _installedCache = null;
    if (raw.isEmpty) {
      _entriesCache = const [];
      return _entriesCache;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        _entriesCache = const [];
        return _entriesCache;
      }
      _entriesCache = [
        for (final entry in decoded)
          if (entry is Map && entry['key'] is String && entry['code'] is String)
            entry.cast<String, dynamic>(),
      ];
      return _entriesCache;
    } catch (_) {
      _entriesCache = const [];
      return _entriesCache;
    }
  }

  static List<JsMangaSource>? _installedCache;

  static List<JsMangaSource> installed() {
    final cachedList = _installedCache;
    if (cachedList != null) return cachedList;
    final sources = <JsMangaSource>[];
    final seen = <String>{};
    for (final entry in installedJsEntries()) {
      final jsKey = entry['key'] as String;
      final id = 'js:$jsKey';
      if (!seen.add(id)) continue;
      final code = entry['code'] as String;
      final cached = _jsCache[id];
      if (cached != null && cached.engine.code == code) {
        sources.add(cached);
        continue;
      }
      cached?.engine.dispose();
      final source = JsMangaSource(
        jsKey: jsKey,
        displayName: (entry['name'] as String?) ?? jsKey,
        version: (entry['version'] as String?) ?? '',
        fileName: (entry['fileName'] as String?) ?? '$jsKey.js',
        code: code,
      );
      _jsCache[id] = source;
      sources.add(source);
    }
    // Drop engines whose entries were removed.
    for (final id in _jsCache.keys.toList()) {
      if (!seen.contains(id)) {
        _jsCache.remove(id)?.engine.dispose();
      }
    }
    _installedCache = sources;
    return sources;
  }

  /// Batch 67: Legado 图片型 (type 2) sources from the
  /// novel registry, adapted into this zone. The novel
  /// registry is the single store for Legado-format
  /// sources; the adapters are cheap wrappers over its
  /// memoized instances.
  static List<LegadoMangaSource> legadoAdapters() {
    _attachNovelListener();
    return [
      for (final source in NovelSources.all())
        if (source.type == 2) LegadoMangaSource(source),
    ];
  }

  static bool _novelListenerAttached = false;

  /// Novel-side imports/removals refresh the manga zone
  /// too (an adapted source may have appeared or gone).
  static void _attachNovelListener() {
    if (_novelListenerAttached) return;
    _novelListenerAttached = true;
    NovelSources.revision.addListener(_bump);
  }

  // Batch 79: all() is called per build and per lookup across
  // the zone; rebuilding the combined list (and re-wrapping
  // every Legado adapter) on each call was pure churn.
  // Memoized on the identities of its two memoized inputs.
  static List<MangaSource>? _allCache;
  static List<JsMangaSource>? _allCacheJs;
  static List<LegadoNovelSource>? _allCacheNovel;

  static List<MangaSource> all() {
    final js = installed();
    final novel = NovelSources.imported();
    final cached = _allCache;
    if (cached != null &&
        identical(_allCacheJs, js) &&
        identical(_allCacheNovel, novel)) {
      return cached;
    }
    final combined = [...js, ...legadoAdapters()];
    _allCache = combined;
    _allCacheJs = js;
    _allCacheNovel = novel;
    // Batch 102: the local (imported CBZ/ZIP) source rides
    // along whenever books exist. It is appended outside the
    // memoized list: the book set changes without the JS /
    // novel registries changing, and a zero-book library must
    // keep the batch-59 zero-source state intact.
    if (LocalMangaLibrary.cachedBooks.isEmpty) return combined;
    return [...combined, LocalMangaSource.instance];
  }

  static MangaSource? byId(String id) {
    for (final source in all()) {
      if (source.id == id) return source;
    }
    return null;
  }

  /// The active source, or null when the user has not
  /// imported any source yet (batch 59: zero sources is a
  /// normal state — pages must render an import prompt
  /// instead of crashing).
  static MangaSource? activeOrNull() {
    final found = byId(GStorage.getSetting(SettingsKeys.mangaActiveSource));
    if (found != null) return found;
    final sources = all();
    return sources.isEmpty ? null : sources.first;
  }

  static MangaSource active() {
    final source = activeOrNull();
    if (source == null) {
      throw StateError('没有可用的漫画源');
    }
    return source;
  }

  static Future<void> setActive(String id) async {
    await GStorage.putSetting(SettingsKeys.mangaActiveSource, id);
    _bump();
  }

  /// Installs (or replaces) a downloaded Venera JS source.
  /// Throws a [FormatException] when the file is not a Venera
  /// source or its key collides with a built-in.
  static Future<void> installJs({
    required String key,
    required String name,
    required String version,
    required String fileName,
    required String code,
  }) async {
    if (VeneraEngine.extractClassName(code) == null) {
      throw const FormatException('不是有效的 JS 源文件');
    }
    final entries = [
      for (final existing in installedJsEntries())
        if (existing['key'] != key) existing,
      {
        'key': key,
        'name': name,
        'version': version,
        'fileName': fileName,
        'code': code,
      },
    ];
    await GStorage.putSetting(
      SettingsKeys.mangaJsSourcesJson,
      jsonEncode(entries),
    );
    _bump();
  }

  /// Batch 45: reads a Venera source's own metadata (the
  /// `name` / `key` / `version` class fields every Venera
  /// source declares at the top of its class). The search
  /// starts at the class declaration so top-level helper
  /// code cannot shadow the fields. Missing fields fall
  /// back: name ← class name, key ← sanitized class name,
  /// version ← '1.0.0'.
  static ({String key, String name, String version}) extractJsMetadata(
    String code,
  ) {
    final className = VeneraEngine.extractClassName(code) ?? 'Custom';
    final classAt = code.indexOf('class $className');
    final body = classAt >= 0 ? code.substring(classAt) : code;
    String? field(String label) {
      final match = RegExp(
        r'^\s*' + label + r'''\s*=\s*["']([^"']+)["']''',
        multiLine: true,
      ).firstMatch(body);
      return match?.group(1)?.trim();
    }

    var key = field('key') ?? '';
    if (key.isEmpty) {
      key = className.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
      if (key.isEmpty) key = 'custom';
    }
    return (
      key: key,
      name: field('name') ?? className,
      version: field('version') ?? '1.0.0',
    );
  }

  /// Batch 45: installs a Venera JS source the user supplied
  /// themselves (URL download, pasted code or a local file) —
  /// same validation and storage as a source-store install;
  /// the metadata comes from the code itself. Returns the
  /// extracted metadata so the caller can confirm by name.
  static Future<({String key, String name, String version})>
      installCustomJs(String code, {String fileName = ''}) async {
    if (VeneraEngine.extractClassName(code) == null) {
      throw const FormatException('不是有效的 JS 源文件（没有找到源类）');
    }
    final meta = extractJsMetadata(code);
    await installJs(
      key: meta.key,
      name: meta.name,
      version: meta.version,
      fileName: fileName.isNotEmpty ? fileName : '${meta.key}.js',
      code: code,
    );
    return meta;
  }

  // ---- Batch 47: pinned sources (mirror of the novel
  // zone's batch-46 pins) --------------------------------

  /// Pinned source ids, in the order the user pinned them.
  static List<String> pinnedIds() {
    final raw = GStorage.getSetting(SettingsKeys.mangaPinnedSourceIds);
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
      SettingsKeys.mangaPinnedSourceIds,
      jsonEncode(pins),
    );
    _bump();
  }

  /// Display order: pinned first (pin order), rest as-is.
  static List<MangaSource> sortForDisplay(
    List<MangaSource> sources, {
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

  /// Batch 88: detects a Venera source *index* — a JSON array
  /// whose every entry carries a `.js` fileName. The community
  /// index link used to fall through to the single-source
  /// installer and fail as "not a Venera source"; importing it
  /// now resolves and installs every listed source. Returns
  /// null for anything else (a single JS source, a Legado
  /// pack, arbitrary JSON), so the other import routes are
  /// untouched.
  static List<VeneraIndexEntry>? parseVeneraIndex(String code) {
    final trimmed = code.trim();
    if (!trimmed.startsWith('[')) return null;
    dynamic decoded;
    try {
      decoded = jsonDecode(trimmed);
    } catch (_) {
      return null;
    }
    if (decoded is! List || decoded.isEmpty) return null;
    final entries = <VeneraIndexEntry>[];
    for (final raw in decoded) {
      if (raw is! Map) return null;
      final fileName = raw['fileName']?.toString().trim() ?? '';
      if (!fileName.toLowerCase().endsWith('.js')) return null;
      final key = raw['key']?.toString().trim() ?? '';
      final name = raw['name']?.toString().trim() ?? '';
      entries.add((
        name: name.isNotEmpty ? name : (key.isNotEmpty ? key : fileName),
        key: key,
        version: raw['version']?.toString().trim() ?? '',
        fileName: fileName,
      ));
    }
    return entries;
  }

  /// Batch 67: when [code] is actually a Legado book-source
  /// pack (JSON / base16 / base64-zlib — the manga files in
  /// that ecosystem are type-2 sources in a .json/.txt),
  /// import it into the novel registry instead of the JS
  /// installer; its type-2 entries then appear in this zone
  /// through the adapters. Returns null when the payload is
  /// not a recognizable Legado pack.
  static Future<({int added, int mangaCount})?> importLegadoPackIfAny(
    String code,
  ) async {
    final entries = LegadoParse.parseSourceArray(code);
    if (entries.isEmpty) return null;
    var recognized = 0;
    var mangaCount = 0;
    for (final entry in entries) {
      final def = LegadoSourceDef.fromJson(entry);
      if (def == null) continue;
      recognized++;
      if (def.type == 2) mangaCount++;
    }
    if (recognized == 0) return null;
    final added = await NovelSources.importFromText(code);
    return (added: added, mangaCount: mangaCount);
  }

  static Future<void> removeInstalled(String id) async {
    // Batch 67: an adapted Legado source is removed from
    // the novel registry it lives in.
    final novelId = LegadoMangaSource.novelIdOf(id);
    if (novelId != null) {
      await NovelSources.removeImported(novelId);
      _bump();
      if (GStorage.getSetting(SettingsKeys.mangaActiveSource) == id) {
        final rest = all();
        await setActive(rest.isEmpty ? '' : rest.first.id);
      }
      return;
    }
    final entries = [
      for (final existing in installedJsEntries())
        if ('js:${existing['key']}' != id) existing,
    ];
    await GStorage.putSetting(
      SettingsKeys.mangaJsSourcesJson,
      jsonEncode(entries),
    );
    _bump();
    if (GStorage.getSetting(SettingsKeys.mangaActiveSource) == id) {
      // Fall back to the first remaining source (or none).
      await setActive(
        entries.isEmpty ? '' : 'js:${entries.first['key']}',
      );
    }
  }
}
