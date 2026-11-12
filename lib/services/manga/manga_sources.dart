import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:anikumo/services/manga/js/js_manga_source.dart';
import 'package:anikumo/services/manga/js/mangakit_host.dart';
import 'package:anikumo/services/manga/js/mangakit_source.dart';
import 'package:anikumo/services/manga/manga_api.dart';
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

  /// Batch 122: drops the memoized entry/installed lists.
  ///
  /// The memos key on the stored JSON string, but [installed]
  /// checks its own cache BEFORE re-reading the string — so a
  /// write that landed after the last read was invisible until
  /// some other call happened to re-read the string first:
  /// the first source imported in a session did not show up
  /// anywhere until the app restarted (a second import, whose
  /// installer re-read the string, unblocked both). Every
  /// writer of the registry JSON must invalidate explicitly.
  static void _invalidateInstalled() {
    _entriesRaw = null;
    _installedCache = null;
  }

  /// For writers outside this class (backup restore writes
  /// the registry JSON directly): invalidate + notify.
  static void invalidateInstalledCaches() {
    _invalidateInstalled();
    _bump();
  }

  // ---- downloaded JS sources (Venera format) ----

  /// Batch 199: which engine runs the JS sources — the user
  /// switches it in 漫画设置 → 漫画引擎， MangaKit by default.
  static bool get useLegacyEngine =>
      GStorage.getSetting(SettingsKeys.mangaEngineKind) == 'legacy';

  static String get _engineKind => useLegacyEngine ? 'legacy' : 'mangakit';

  /// Records the engine choice and drops every live handle,
  /// so the next [installed] rebuilds all sources on the
  /// newly picked engine. Persisted source data, settings
  /// and cookies are shared between the engines, so the
  /// switch itself loses nothing.
  static Future<void> setEngineKind(String kind) async {
    await GStorage.putSetting(SettingsKeys.mangaEngineKind, kind);
    for (final handle in _jsCache.values) {
      _dropHandle(handle);
    }
    _jsCache.clear();
    _jsCacheEngine = kind;
    _installedCache = null;
    _bump();
  }

  /// Releases one source handle's engine-side resources:
  /// a MangaKit handle unregisters from the shared runtime,
  /// a legacy handle disposes its own engine.
  static void _dropHandle(JsBackedMangaSource handle) {
    if (handle is MangaKitMangaSource) {
      unawaited(
        MangaKitRuntime.instance
            .removeSource(handle.jsKey, handle.manifestKey),
      );
    } else if (handle is JsMangaSource) {
      handle.engine.dispose();
    }
  }

  /// The engine the live handles in [_jsCache] were built
  /// for; a mismatch means the setting flipped underneath
  /// the cache (e.g. restored from a backup).
  static String? _jsCacheEngine;

  /// Live sources, one per installed JS source, keyed by the
  /// source's registry id (`js:<key>`). Rebuilt when the stored
  /// code changes (a re-download / update) or the engine
  /// setting flips.
  static final Map<String, JsBackedMangaSource> _jsCache = {};

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

  static List<JsBackedMangaSource>? _installedCache;

  static List<JsBackedMangaSource> installed() {
    // Batch 199: the engine setting flipped underneath the
    // cache — drop every handle and rebuild on the new one.
    if (_jsCacheEngine != _engineKind) {
      for (final handle in _jsCache.values) {
        _dropHandle(handle);
      }
      _jsCache.clear();
      _jsCacheEngine = _engineKind;
      _installedCache = null;
    }
    final cachedList = _installedCache;
    if (cachedList != null) return cachedList;
    final sources = <JsBackedMangaSource>[];
    final seen = <String>{};
    for (final entry in installedJsEntries()) {
      final jsKey = entry['key'] as String;
      final id = 'js:$jsKey';
      if (!seen.add(id)) continue;
      final code = entry['code'] as String;
      final cached = _jsCache[id];
      if (cached != null && cached.code == code) {
        sources.add(cached);
        continue;
      }
      if (cached != null) _dropHandle(cached);
      final name = (entry['name'] as String?) ?? jsKey;
      final version = (entry['version'] as String?) ?? '';
      final fileName = (entry['fileName'] as String?) ?? '$jsKey.js';
      final source = useLegacyEngine
          ? JsMangaSource(
              jsKey: jsKey,
              displayName: name,
              version: version,
              fileName: fileName,
              code: code,
            )
          : MangaKitMangaSource(
              jsKey: jsKey,
              displayName: name,
              version: version,
              fileName: fileName,
              code: code,
            );
      _jsCache[id] = source;
      sources.add(source);
    }
    // Drop sources whose entries were removed.
    for (final id in _jsCache.keys.toList()) {
      if (!seen.contains(id)) {
        final dropped = _jsCache.remove(id);
        if (dropped != null) _dropHandle(dropped);
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
  static List<JsBackedMangaSource>? _allCacheJs;
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
    String? origin,
  }) async {
    if (VeneraEngine.extractClassName(code) == null) {
      throw const FormatException('不是有效的 JS 源文件');
    }
    // Batch 190: remember where this source's file came
    // from (its download URL) so the update checker can
    // re-read it later. An install without an origin
    // (local file, pasted code, an update applied by the
    // checker itself passes one explicitly) keeps the
    // previously recorded origin.
    final effectiveOrigin = origin ?? originOfKey(key);
    final entries = [
      for (final existing in installedJsEntries())
        if (existing['key'] != key) existing,
      {
        'key': key,
        'name': name,
        'version': version,
        'fileName': fileName,
        'code': code,
        if (effectiveOrigin != null) 'origin': effectiveOrigin,
      },
    ];
    await GStorage.putSetting(
      SettingsKeys.mangaJsSourcesJson,
      jsonEncode(entries),
    );
    _invalidateInstalled();
    _bump();
    // Batch 185: the facade's memoized results are keyed
    // by source id, not by source code — a reinstalled or
    // updated source kept serving its predecessor's cached
    // searches/chapters/pages until the TTLs expired
    // (clearCaches existed but had no call sites).
    MangaApi.clearCaches();
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
      installCustomJs(
    String code, {
    String fileName = '',
    String? origin,
  }) async {
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
      origin: origin,
    );
    return meta;
  }

  /// Batch 190: the recorded download URL of an installed
  /// source's file, when it was installed from one.
  static String? originOfKey(String key) {
    for (final entry in installedJsEntries()) {
      if (entry['key'] == key) {
        final origin = entry['origin'];
        if (origin is String && origin.isNotEmpty) return origin;
      }
    }
    return null;
  }

  /// Batch 190: repository (index) URLs the user has
  /// imported sources from, in the order they were added.
  static List<String> sourceRepositories() {
    final raw = GStorage.getSetting(SettingsKeys.mangaSourceRepos);
    if (raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return [
          for (final e in decoded)
            if (e is String && e.isNotEmpty) e,
        ];
      }
    } catch (_) {}
    return const [];
  }

  /// Batch 190: remember a repository URL (deduplicated).
  static Future<void> addSourceRepository(String url) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return;
    final repos = sourceRepositories();
    if (repos.contains(trimmed)) return;
    await GStorage.putSetting(
      SettingsKeys.mangaSourceRepos,
      jsonEncode([...repos, trimmed]),
    );
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

  /// Batch 159: removes a whole set of installed sources
  /// in one pass per store — the JS registry blob (which
  /// embeds every source's full code) is re-encoded ONCE
  /// for the whole set instead of once per source, and the
  /// adapted entries go through the novel registry's own
  /// batch removal. Deleting several sources used to pay
  /// the full blob encode + decode per source and stalled
  /// the management page. Returns how many were removed.
  static Future<int> removeInstalledBatch(Set<String> ids) async {
    if (ids.isEmpty) return 0;
    var removed = 0;
    final novelIds = <String>{};
    final jsIds = <String>{};
    for (final id in ids) {
      final novelId = LegadoMangaSource.novelIdOf(id);
      if (novelId != null) {
        novelIds.add(novelId);
      } else if (id.startsWith('js:')) {
        jsIds.add(id);
      }
    }
    if (novelIds.isNotEmpty) {
      removed += await NovelSources.removeImportedBatch(novelIds);
    }
    if (jsIds.isNotEmpty) {
      final before = installedJsEntries();
      final entries = [
        for (final existing in before)
          if (!jsIds.contains('js:${existing['key']}')) existing,
      ];
      removed += before.length - entries.length;
      await GStorage.putSetting(
        SettingsKeys.mangaJsSourcesJson,
        jsonEncode(entries),
      );
      _invalidateInstalled();
    }
    if (removed > 0) {
      _bump();
      MangaApi.clearCaches();
      // If the active source went away, fall back to the
      // first remaining one (or none).
      if (ids.contains(GStorage.getSetting(SettingsKeys.mangaActiveSource))) {
        final rest = all();
        await setActive(rest.isEmpty ? '' : rest.first.id);
      }
    }
    return removed;
  }

  static Future<void> removeInstalled(String id) async {
    await removeInstalledBatch({id});
  }
}
