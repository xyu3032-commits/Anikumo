import 'dart:convert';

import 'package:anikumo/modules/manga/manga_item.dart';
import 'package:anikumo/services/manga/js/venera_engine.dart';
import 'package:anikumo/services/manga/manga_source.dart';
import 'package:anikumo/services/storage/storage.dart';

/// A downloaded Venera JS source running on the QuickJS
/// runtime — the original Venera mechanism: the .js file from
/// the community index is downloaded, installed, and executed,
/// instead of being re-expressed as a declarative definition.
class JsMangaSource extends MangaSource {
  JsMangaSource({
    required this.jsKey,
    required this.displayName,
    required this.version,
    required this.fileName,
    required String code,
  }) : engine = VeneraEngine(sourceKey: jsKey, code: code);

  /// The key in the Venera configs index (e.g. 'copy_manga').
  final String jsKey;
  final String displayName;
  final String version;
  final String fileName;
  final VeneraEngine engine;

  @override
  String get id => 'js:$jsKey';

  @override
  String get name => displayName;

  @override
  String get description => 'JS 源 · v$version';

  @override
  bool get supportsTags => true;

  @override
  Future<List<MangaItem>> search(
    String keyword, {
    int limit = 30,
    int page = 1,
  }) async {
    final result = await engine.call('search', {
      'keyword': keyword,
      'page': page,
    });
    return _withThumbnailConfigs(mapJsComicList(result, sourceId: id));
  }

  @override
  Future<List<MangaItem>> popular({int limit = 20, int page = 1}) async {
    final result = await engine.call('explore', {'page': page});
    final items = mapJsComicList(result, sourceId: id);
    if (items.isNotEmpty || page > 1) {
      return _withThumbnailConfigs(items);
    }
    // Sources without an explore section: fall back to a
    // blank-keyword search, which several sources treat as
    // their browse feed.
    try {
      return await search('', limit: limit, page: page);
    } catch (_) {
      return items;
    }
  }

  @override
  Future<List<MangaItem>> updated({int limit = 20, int page = 1}) =>
      popular(limit: limit, page: page);

  @override
  Future<List<MangaTag>> tags() async {
    try {
      final result = await engine.call('categories', const {});
      return mapJsCategories(result);
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<List<MangaItem>> byTag(
    String tagId, {
    int limit = 30,
    int page = 1,
  }) async {
    final result = await engine.call('categoryComics', {
      'category': tagId,
      'page': page,
    });
    return _withThumbnailConfigs(mapJsComicList(result, sourceId: id));
  }

  @override
  Future<List<MangaChapter>> chapters(MangaItem manga) async {
    final result = await engine.call('loadInfo', {'id': manga.id});
    // Batch 40: a non-Map reply means the bridge returned
    // garbage — that is a failure, not "this comic has no
    // chapters". Throw so the detail page shows its error
    // state with retry instead of a dead-end empty text.
    if (result is! Map) {
      throw StateError('$displayName 返回了无法识别的详情数据');
    }
    final chapters = mapJsChapters(
      unwrapJsDetails(result.cast<String, dynamic>()),
    );
    if (chapters.isNotEmpty) return chapters;
    // Batch 41: single-volume sources (nhentai, hitomi)
    // return a ComicDetails with NO chapters field at all —
    // in Venera the comic itself is the one episode and
    // loadEp ignores the ep id. Synthesize that episode or
    // the detail page dead-ends at 章节（0) with 开始阅读
    // disabled even though the source can serve every page.
    return [
      MangaChapter(
        id: manga.id,
        volume: null,
        chapter: null,
        title: '正文',
        language: '',
        pages: 0,
        publishedAt: null,
      ),
    ];
  }

  // ---- Batch 191: in-app source settings ---------------
  // The source's declared settings (schema from the
  // runtime, values in the persisted KV) rendered and
  // edited by the app's own UI — no trip to the source's
  // website.

  /// The declared settings schema, in declaration order.
  Future<List<MangaSettingDef>> settingsSchema() async {
    final result = await engine.call('settingsSchema', const {});
    if (result is! Map) return const [];
    return [
      for (final entry in result.entries)
        if (entry.value is Map)
          MangaSettingDef.fromJson(
            entry.key.toString(),
            (entry.value as Map).cast<String, dynamic>(),
          ),
    ];
  }

  /// Current setting values (schema defaults seeded at
  /// registration, user edits on top).
  Map<String, dynamic> settingValues() {
    try {
      final kv = jsonDecode(VeneraEngine.kvJsonFor(jsKey));
      if (kv is Map && kv['settings'] is Map) {
        return (kv['settings'] as Map).cast<String, dynamic>();
      }
    } catch (_) {}
    return const {};
  }

  /// Writes one setting value to the persisted KV and
  /// re-registers the source so the runtime picks it up.
  Future<void> writeSetting(String key, Object? value) async {
    Map<String, dynamic> kv;
    try {
      final decoded = jsonDecode(VeneraEngine.kvJsonFor(jsKey));
      kv = decoded is Map
          ? decoded.cast<String, dynamic>()
          : <String, dynamic>{};
    } catch (_) {
      kv = <String, dynamic>{};
    }
    final settings = kv['settings'] is Map
        ? (kv['settings'] as Map).cast<String, dynamic>()
        : <String, dynamic>{};
    settings[key] = value;
    kv['settings'] = settings;
    kv['data'] = kv['data'] is Map ? kv['data'] : <String, dynamic>{};
    VeneraEngine.persistKv(jsKey, jsonEncode(kv));
    await engine.refreshRegistration();
  }

  /// Runs a callback-type setting inside the runtime.
  Future<void> invokeSettingCallback(String key) async {
    await engine.call('settingCallback', {'settingKey': key});
  }

  /// The source's own declared site URL, when its class
  /// declares one (`url = "..."`), for the info panel.
  String? get declaredUrl {
    final match = RegExp(
      r'''^\s*url\s*=\s*["']([^"']+)["']''',
      multiLine: true,
    ).firstMatch(engine.code);
    return match?.group(1)?.trim();
  }

  @override
  Future<List<MangaPage>> pages(
    MangaItem manga,
    MangaChapter chapter,
  ) async {
    final result = await engine.call('loadEp', {
      'id': manga.id,
      'ep': chapter.id,
    });
    if (result is! Map) {
      throw StateError('$displayName 返回了无法识别的章节数据');
    }
    final pages = mapJsPages(result.cast<String, dynamic>());
    return _withImageConfigs(pages, manga, chapter);
  }

  @override
  Future<MangaItem?> details(MangaItem manga) async {
    final result = await engine.call('loadInfo', {'id': manga.id});
    if (result is! Map) return null;
    final item = mapJsDetails(
      unwrapJsDetails(result.cast<String, dynamic>()),
      manga,
    );
    final configured = await _withThumbnailConfigs([item]);
    return configured.first;
  }

  /// Batch 88: run the source's `comic.onImageLoad` hook over
  /// a chapter's pages (one batched engine call; the hook may
  /// be async and may do its own requests). Best-effort: any
  /// failure keeps the pages exactly as loadEp mapped them.
  Future<List<MangaPage>> _withImageConfigs(
    List<MangaPage> pages,
    MangaItem manga,
    MangaChapter chapter,
  ) async {
    if (pages.isEmpty) return pages;
    try {
      final configs = await engine.call('imageConfigs', {
        'urls': [for (final page in pages) page.url],
        'id': manga.id,
        'ep': chapter.id,
      });
      return applyImageConfigs(pages, configs);
    } catch (_) {
      return pages;
    }
  }

  /// Batch 102: run the registered `onResponse` byte
  /// transform (see the dispatcher's transform registry) over
  /// [raw] — the bytes downloaded from the config's url.
  /// [mode] is 'image' for chapter pages or 'thumb' for
  /// covers; [originalUrl] is the url the hook was originally
  /// called with; [id]/[ep] let a cold registry re-run the
  /// image hook. Returns null when no transform applies or
  /// the transform produced nothing usable — callers fall
  /// back to the raw bytes, which is never worse than the
  /// pre-batch-102 behavior.
  Future<List<int>?> transformImageBytes({
    required String mode,
    required String originalUrl,
    String id = '',
    String ep = '',
    required List<int> raw,
  }) async {
    try {
      final result = await engine.call('transformImage', {
        'mode': mode,
        'url': originalUrl,
        'id': id,
        'ep': ep,
        'dataB64': base64Encode(raw),
      });
      if (result is Map && result['ok'] == true) {
        final b64 = result['dataB64']?.toString() ?? '';
        if (b64.isNotEmpty) return base64Decode(b64);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Batch 103: runs a config's `modifyImage` code string
  /// over downloaded page bytes (image descramble). Null on
  /// any failure — the caller displays the raw bytes.
  Future<List<int>?> modifyImageBytes({
    required String code,
    required List<int> raw,
  }) async {
    try {
      final result = await engine.call('modifyImage', {
        'code': code,
        'dataB64': base64Encode(raw),
      });
      if (result is Map && result['ok'] == true) {
        final b64 = result['dataB64']?.toString() ?? '';
        if (b64.isNotEmpty) return base64Decode(b64);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Batch 103: asks the page's registered `onLoadFailed`
  /// for a replacement config after a failed download.
  /// Returns the normalized config map, or null when the
  /// source offered none.
  Future<Map<String, dynamic>?> loadFailedConfig({
    required String originalUrl,
    String id = '',
    String ep = '',
  }) async {
    try {
      final result = await engine.call('loadFailed', {
        'url': originalUrl,
        'id': id,
        'ep': ep,
      });
      if (result is Map) return result.cast<String, dynamic>();
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Batch 103: `comic.loadThumbnails` — detail-screen
  /// preview page urls. Sources without the hook answer
  /// null in the engine, which maps to an empty list here.
  @override
  Future<List<String>> loadThumbnails(MangaItem manga) async {
    try {
      final result = await engine.call('loadThumbnails', {
        'id': manga.id,
      });
      if (result is List) {
        return [
          for (final url in result)
            if (url is String && url.isNotEmpty) url,
        ];
      }
      return const [];
    } catch (_) {
      return const [];
    }
  }

  /// Batch 88: run `comic.onThumbnailLoad` over list/detail
  /// covers the same way. Sources without the hook answer
  /// null and the items pass through untouched.
  Future<List<MangaItem>> _withThumbnailConfigs(
    List<MangaItem> items,
  ) async {
    if (items.isEmpty) return items;
    try {
      // Batch 96: a 6 s cap on the cover-hook pass. A
      // homepage-sized result (100-300 covers) whose
      // onThumbnailLoad does per-cover work used to gate
      // the WHOLE list behind it — the explore grid showed
      // a skeleton while covers were still being signed.
      // On timeout the catch below returns the list
      // untouched (covers load from their raw URLs), which
      // is the same degradation as a failing hook.
      final configs = await engine
          .call('thumbnailConfigs', {
            'urls': [for (final item in items) item.coverUrl],
          })
          .timeout(const Duration(seconds: 6));
      return applyThumbnailConfigs(items, configs);
    } catch (_) {
      return items;
    }
  }

  @override
  Future<MangaAccountInfo?> accountInfo() async {
    final result = await engine.call('account', const {});
    if (result is! Map) return null;
    final info = mapJsAccountInfo(
      result.cast<String, dynamic>(),
      sessionOpen: MangaAccountSessions.isLoggedIn(jsKey),
    );
    return info.hasLogin ? info : null;
  }

  @override
  Future<void> login(String username, String password) async {
    await engine.call('login', {
      'username': username,
      'password': password,
    });
    await MangaAccountSessions.markLoggedIn(jsKey);
  }

  @override
  Future<void> logout() async {
    try {
      await engine.call('logout', const {});
    } finally {
      await MangaAccountSessions.markLoggedOut(jsKey);
    }
  }
}

/// Maps a dispatcher 'account' probe result to the model.
/// Pure — the unit-testable half of batch 74's login support.
MangaAccountInfo mapJsAccountInfo(
  Map<String, dynamic> json, {
  required bool sessionOpen,
}) {
  final website = json['registerWebsite']?.toString() ?? '';
  return MangaAccountInfo(
    hasLogin: json['hasLogin'] == true,
    hasLogout: json['hasLogout'] == true,
    isLoggedIn: json['hasToken'] == true || sessionOpen,
    registerWebsite: website.isEmpty ? null : website,
  );
}

/// Batch 74: which JS sources hold an account session opened
/// through the login page. Cookie-based sources (jm shape)
/// keep no token in their KV for the bridge's isLogged check
/// to find, so the host tracks the session itself; the
/// source's own logout + KV token clearing still run through
/// the engine on sign-out.
class MangaAccountSessions {
  MangaAccountSessions._();

  static List<String> _keys() {
    try {
      final raw = GStorage.getSetting(SettingsKeys.mangaAccountSessionsJson);
      if (raw.isEmpty) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded.map((e) => e.toString()).toList();
      }
    } catch (_) {}
    return const [];
  }

  static bool isLoggedIn(String jsKey) => _keys().contains(jsKey);

  static Future<void> markLoggedIn(String jsKey) async {
    final keys = _keys();
    if (keys.contains(jsKey)) return;
    await GStorage.putSetting(
      SettingsKeys.mangaAccountSessionsJson,
      jsonEncode([...keys, jsKey]),
    );
  }

  static Future<void> markLoggedOut(String jsKey) async {
    final keys = _keys();
    if (!keys.contains(jsKey)) return;
    await GStorage.putSetting(
      SettingsKeys.mangaAccountSessionsJson,
      jsonEncode(keys.where((k) => k != jsKey).toList()),
    );
  }
}

/// Maps one Venera `Comic` JSON object to a [MangaItem].
/// Pure and synchronous — the unit-testable half of the JS
/// source support.
MangaItem mapJsComic(Map<String, dynamic> json, {required String sourceId}) {
  final tags = <String>[];
  final rawTags = json['tags'];
  if (rawTags is List) {
    for (final tag in rawTags) {
      if (tag != null && tag.toString().isNotEmpty) {
        tags.add(tag.toString());
      }
    }
  } else if (rawTags is Map) {
    // Details-style grouped tags: {group: [names]}.
    for (final group in rawTags.values) {
      if (group is List) {
        for (final tag in group) {
          if (tag != null && tag.toString().isNotEmpty) {
            tags.add(tag.toString());
          }
        }
      }
    }
  }
  return MangaItem(
    id: json['id']?.toString() ?? '',
    title: (json['title'] ?? json['name'])?.toString() ?? '',
    description: json['description']?.toString() ?? '',
    coverUrl:
        (json['cover'] ?? json['coverUrl'] ?? json['thumbnail'])?.toString() ??
            '',
    author:
        (json['subtitle'] ?? json['subTitle'] ?? json['author'])?.toString() ??
            '',
    status: normalizeMangaStatus(json['status']?.toString() ?? ''),
    year: null,
    tags: tags,
    source: sourceId,
  );
}

/// Maps a dispatcher result ({comics: [...]} — or a bare list —
/// from search / explore / categoryComics) to items. Explore
/// results may be a list of SECTIONS ({title, comics: [...]},
/// the multi-part explore shape verified against manga_dex.js)
/// or a map carrying sections under 'sections'/'parts'; both
/// are flattened to their comics.
List<MangaItem> mapJsComicList(dynamic result, {required String sourceId}) {
  var raw = switch (result) {
    Map m => m['comics'] ?? m['sections'] ?? m['parts'],
    List l => l,
    _ => null,
  };
  // Batch 37: some sources' explore returns a map keyed by
  // SECTION TITLE ({推荐: [...], 热门: [...]}) — copy_manga
  // among them. Its home section and explore tab read as
  // permanently empty because only the comics/sections/parts
  // keys were consulted. Flatten the values instead.
  if (raw == null && result is Map) {
    raw = [
      for (final value in result.values)
        if (value is List) ...value,
    ];
  }
  if (raw is! List) return const [];
  final items = <MangaItem>[];
  void addEntry(dynamic entry) {
    if (entry is! Map) return;
    final map = entry.cast<String, dynamic>();
    final nested = map['comics'];
    if (nested is List && map['id'] == null && map['cover'] == null) {
      // A section, not a comic.
      for (final inner in nested) {
        addEntry(inner);
      }
      return;
    }
    items.add(mapJsComic(map, sourceId: sourceId));
  }

  for (final entry in raw) {
    addEntry(entry);
  }
  // Batch 185: an entry whose id never materialized cannot
  // be opened (every detail call keys on the id) — the
  // cross-source merge filters these, but single-source
  // lists reached the UI with them and died on tap.
  final beforeFilter = items.length;
  items.removeWhere((item) => item.id.trim().isEmpty);
  // Batch 188: a page whose entries ALL dropped is not
  // an empty page — the source answered with a shape
  // this build cannot read. Returning [] made the UI
  // latch "no more content" mid-list; throwing lands
  // the call on the retry path instead, where it
  // belongs. (A genuinely empty page has no entries
  // at all and still returns [].)
  if (beforeFilter > 0 && items.isEmpty) {
    throw StateError('这一页的条目都缺少可用标识，无法打开');
  }
  return items;
}

/// Some sources wrap ComicDetails in a {comic: {...}} envelope;
/// merge it over the outer map so chapters/tags sit at the top.
Map<String, dynamic> unwrapJsDetails(Map<String, dynamic> result) {
  final inner = result['comic'];
  if (inner is Map) {
    return {
      ...result,
      ...inner.cast<String, dynamic>(),
      if (result['chapters'] != null) 'chapters': result['chapters'],
    };
  }
  return result;
}

/// Maps Venera category definitions to the zone's tag model.
/// Entries are strings or {name, key} objects.
List<MangaTag> mapJsCategories(dynamic result) {
  if (result is! List) return const [];
  final tags = <MangaTag>[];
  for (final entry in result) {
    if (entry is String) {
      if (entry.isNotEmpty) {
        tags.add(MangaTag(id: entry, name: entry, group: ''));
      }
    } else if (entry is Map) {
      final name =
          (entry['name'] ?? entry['title'] ?? '').toString();
      if (name.isEmpty) continue;
      final key = (entry['key'] ?? entry['id'] ?? name).toString();
      tags.add(MangaTag(id: key, name: name, group: ''));
    }
  }
  return tags;
}

/// Flattens a ComicDetails `chapters` value into reading order.
/// Venera shapes: {groupTitle: {epId: epTitle}} (insertion
/// order preserved by the JS normalization pass) or a list of
/// {id, title}.
List<MangaChapter> mapJsChapters(Map<String, dynamic> details) {
  final raw = details['chapters'];
  final chapters = <MangaChapter>[];
  final seenIds = <String>{};
  void add(String id, String title) {
    if (id.isEmpty) return;
    // Batch 185: duplicate episode ids (a group map that
    // repeats an id, a list with the same chapter twice)
    // collide in the download index and confuse reader
    // chapter lookup. First occurrence wins, order kept.
    // (No reordering: the contract is the source's order —
    // both oldest-first and newest-first sources exist.)
    if (!seenIds.add(id)) return;
    chapters.add(
      MangaChapter(
        id: id,
        volume: null,
        chapter: parseJsChapterNumber(title),
        title: title,
        language: '',
        pages: 0,
        publishedAt: null,
      ),
    );
  }

  if (raw is Map) {
    for (final entry in raw.entries) {
      final group = entry.value;
      if (group is String || group is num) {
        // Flat {epId: title} map (no groups).
        add(entry.key.toString(), group.toString());
      } else if (group is Map) {
        for (final inner in group.entries) {
          add(inner.key.toString(), inner.value?.toString() ?? '');
        }
      } else if (group is List) {
        for (final item in group) {
          if (item is Map) {
            add(
              (item['id'] ?? '').toString(),
              (item['title'] ?? item['name'] ?? '').toString(),
            );
          }
        }
      }
    }
  } else if (raw is List) {
    for (final entry in raw) {
      if (entry is Map) {
        add(
          (entry['id'] ?? '').toString(),
          (entry['title'] ?? entry['name'] ?? '').toString(),
        );
      } else if (entry != null) {
        add(entry.toString(), '');
      }
    }
  }
  return chapters;
}

/// Best-effort chapter number from an episode title
/// ('第12话' / 'Chapter 12.5' / '12 - …').
String? parseJsChapterNumber(String title) {
  final match = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(title);
  return match?.group(1);
}

/// Maps a loadEp result ({images: [...]}) to pages. Images are
/// URL strings, or {url, headers} objects on sources whose CDN
/// needs per-image headers.
List<MangaPage> mapJsPages(Map<String, dynamic> result) {
  final images = result['images'] ?? result['urls'] ?? result['pages'];
  if (images is! List) return const [];
  final fallbackHeaders = <String, String>{};
  final rawHeaders = result['imageHeaders'] ?? result['headers'];
  if (rawHeaders is Map) {
    for (final entry in rawHeaders.entries) {
      fallbackHeaders[entry.key.toString()] = entry.value.toString();
    }
  }
  // Batch 185: page URLs are validated and deduplicated
  // here, at the one exit every JS source's page list
  // passes through. Empty strings (a map entry whose url
  // stringified to ''), non-URL junk and non-http(s)/file
  // schemes used to become pages verbatim — each one a
  // guaranteed broken page in the reader and a phantom
  // entry in the progress denominator; duplicates rendered
  // twice and counted twice. Order is preserved.
  final pages = <MangaPage>[];
  final seen = <String>{};
  void addPage(String url, Map<String, String> headers) {
    final cleaned = url.trim();
    if (cleaned.isEmpty) return;
    if (!cleaned.startsWith('http://') &&
        !cleaned.startsWith('https://') &&
        !cleaned.startsWith('file://')) {
      return;
    }
    if (!seen.add(cleaned)) return;
    pages.add(MangaPage(cleaned, headers: headers));
  }

  for (final image in images) {
    if (image is String) {
      addPage(image, fallbackHeaders);
    } else if (image is Map && image['url'] != null) {
      addPage(
        image['url'].toString(),
        {
          ...fallbackHeaders,
          if (image['headers'] is Map)
            for (final entry in (image['headers'] as Map).entries)
              entry.key.toString(): entry.value.toString(),
        },
      );
    }
  }
  return pages;
}

/// Batch 88: applies `comic.onImageLoad` results (a list
/// parallel to [pages]; null entries mean "no change") to a
/// chapter's pages. A config may replace the URL and add or
/// override headers. Configs asking for a non-GET request are
/// not honored — the reader loads pages with GET only — and
/// local (downloaded) pages are never rewritten.
List<MangaPage> applyImageConfigs(List<MangaPage> pages, dynamic configs) {
  if (configs is! List) return pages;
  return [
    for (var i = 0; i < pages.length; i++)
      _applyImageConfig(pages[i], i < configs.length ? configs[i] : null),
  ];
}

/// Batch 103: applies ONE normalized hook config to a page —
/// also the entry point for `onLoadFailed` replacement
/// configs, which arrive one at a time after a failed load.
MangaPage applyImageConfigToPage(MangaPage page, dynamic config) =>
    _applyImageConfig(page, config, fromFallback: true);

MangaPage _applyImageConfig(
  MangaPage page,
  dynamic config, {
  bool fromFallback = false,
}) {
  if (config is! Map || page.url.startsWith('file://')) return page;
  final method = config['method']?.toString().toUpperCase();
  if (method != null && method.isNotEmpty && method != 'GET') return page;
  final url = config['url']?.toString() ?? '';
  final modify = config['modify']?.toString() ?? '';
  final effectiveUrl = url.isNotEmpty ? url : page.url;
  // Registration keying differs by pass: the initial pass
  // registered the hook functions under the page's ORIGINAL
  // url (the one the hook was called with — batch 102),
  // while an onLoadFailed replacement was registered under
  // its own url by the dispatcher.
  final markerKey = fromFallback ? effectiveUrl : page.url;
  return MangaPage(
    effectiveUrl,
    headers: {
      ...page.headers,
      ..._configHeaders(config['headers']),
    },
    // Batch 102: the dispatcher flags configs whose hook
    // carried an onResponse; the transform is keyed by the
    // page's ORIGINAL url.
    transformOf: config['transform'] == true ? markerKey : page.transformOf,
    // Batch 103: modifyImage code string and onLoadFailed
    // presence, same keying. A replacement config without
    // its own markers keeps the originals (the fallback hook
    // speaks for the same logical page).
    modifyCode: modify.isNotEmpty ? modify : page.modifyCode,
    fallbackOf: config['fallback'] == true ? markerKey : page.fallbackOf,
  );
}

/// Batch 88: applies `comic.onThumbnailLoad` results to
/// items' covers the same way (URL replacement + headers,
/// which the cover widgets pass as `item.coverHeaders`).
List<MangaItem> applyThumbnailConfigs(
  List<MangaItem> items,
  dynamic configs,
) {
  if (configs is! List) return items;
  return [
    for (var i = 0; i < items.length; i++)
      _applyThumbnailConfig(items[i], i < configs.length ? configs[i] : null),
  ];
}

MangaItem _applyThumbnailConfig(MangaItem item, dynamic config) {
  if (config is! Map || item.coverUrl.isEmpty) return item;
  final method = config['method']?.toString().toUpperCase();
  if (method != null && method.isNotEmpty && method != 'GET') return item;
  final url = config['url']?.toString() ?? '';
  final headers = _configHeaders(config['headers']);
  // Batch 102: a transform-only config (same url, no extra
  // headers) is still a change — the cover bytes must go
  // through the registered onResponse.
  final transform = config['transform'] == true;
  if (url.isEmpty && headers.isEmpty && !transform) return item;
  return item.copyWith(
    coverUrl: url.isNotEmpty ? url : item.coverUrl,
    headers: {...item.headers, ...headers},
    coverTransformOf: transform ? item.coverUrl : null,
  );
}

Map<String, String> _configHeaders(dynamic raw) {
  if (raw is! Map) return const {};
  return {
    for (final entry in raw.entries)
      entry.key.toString(): entry.value.toString(),
  };
}

/// Merges a ComicDetails payload into the list-level item.
MangaItem mapJsDetails(Map<String, dynamic> details, MangaItem base) {
  final merged = mapJsComic(
    {
      'id': base.id,
      'title': details['title'] ?? base.title,
      'subtitle': details['subtitle'] ?? details['subTitle'] ?? base.author,
      'cover': details['cover'] ?? base.coverUrl,
      'description': details['description'] ?? base.description,
      'tags': details['tags'] ?? base.tags,
      'status': details['status'] ?? base.status,
    },
    sourceId: base.source,
  );
  return merged;
}


/// Batch 191: one entry of a JS source's declared
/// settings schema, as reported by the runtime.
class MangaSettingDef {
  const MangaSettingDef({
    required this.key,
    required this.title,
    required this.type,
    required this.options,
    required this.defaultValue,
    required this.validator,
    required this.buttonText,
    required this.hasCallback,
  });

  factory MangaSettingDef.fromJson(
    String key,
    Map<String, dynamic> json,
  ) {
    return MangaSettingDef(
      key: key,
      title: (json['title'] as String?) ?? key,
      type: (json['type'] as String?) ?? 'input',
      options: [
        if (json['options'] is List)
          for (final option in json['options'] as List)
            if (option is Map)
              (
                value: option['value']?.toString() ?? '',
                text: option['text']?.toString() ??
                    option['value']?.toString() ??
                    '',
              )
            else
              (value: option.toString(), text: option.toString()),
      ],
      defaultValue: json['defaultValue'],
      validator: json['validator'] as String?,
      buttonText: json['buttonText'] as String?,
      hasCallback: json['hasCallback'] == true,
    );
  }

  final String key;
  final String title;

  /// select / input / switch / callback (anything else
  /// renders as a text input).
  final String type;
  final List<({String value, String text})> options;
  final Object? defaultValue;
  final String? validator;
  final String? buttonText;
  final bool hasCallback;
}
