import 'dart:convert';

import 'package:anikumo/modules/manga/manga_item.dart';
import 'package:anikumo/services/manga/js/js_manga_source.dart'
    show JsBackedMangaSource, MangaAccountSessions, MangaSettingDef;
import 'package:anikumo/services/manga/js/mangakit_host.dart';
import 'package:anikumo/services/manga/js/venera_engine.dart';
import 'package:anikumo/services/manga/manga_source.dart';

/// Batch 198: a downloaded Venera-format JS source running
/// on the MangaKit framework engine (the zone's engine from
/// this batch on). Same public surface as the legacy
/// JsMangaSource — registry, settings panel, image pipeline
/// and account flows keep their shapes; only the engine
/// behind them changed. Framework features ride along:
/// per-origin request gates, the 5 s GET cache with
/// in-flight dedupe, the 2 s refresh guard, progressive
/// explore sections, the verification-wall flow, and the
/// image-hook execution kinds. Batch 199: implements the
/// shared JsBackedMangaSource face alongside the legacy
/// engine — the zone's engine is user-switchable, MangaKit
/// remaining the default.
class MangaKitMangaSource extends JsBackedMangaSource {
  MangaKitMangaSource({
    required this.jsKey,
    required this.displayName,
    required this.version,
    required this.fileName,
    required String code,
  }) : _code = code;

  /// The key in the Venera configs index (e.g. 'copy_manga').
  final String jsKey;

  /// The source file's code (the registry compares it to
  /// detect re-downloads / updates).
  String get code => _code;
  final String displayName;
  final String version;
  final String fileName;
  final String _code;

  Map<String, dynamic>? _manifest;
  Map<String, dynamic>? _diagnostics;

  @override
  String get id => 'js:$jsKey';

  @override
  String get name => displayName;

  @override
  String get description => 'JS 源 · v$version';

  @override
  bool get supportsTags => true;

  MangaKitRuntime get _runtime => MangaKitRuntime.instance;

  /// The key the framework registered this source under
  /// (the source file's own key; normally identical to
  /// [jsKey]).
  String get manifestKey =>
      _manifest?['key']?.toString() ?? jsKey;

  /// Registration diagnostics from the compat layer
  /// (unmapped surfaces, init warnings), for the source
  /// info panel. Null until the source has registered.
  Map<String, dynamic>? get diagnostics => _diagnostics;

  /// The source's own declared site URL, when known (the
  /// registration manifest's url, else the class field).
  String? get declaredUrl {
    final fromManifest = _manifest?['url']?.toString() ?? '';
    if (fromManifest.isNotEmpty) return fromManifest;
    final match = RegExp(
      r'''^\s*url\s*=\s*["']([^"']+)["']''',
      multiLine: true,
    ).firstMatch(_code);
    return match?.group(1)?.trim();
  }

  /// Registers the source with the framework (idempotent —
  /// the runtime dedupes and caches registrations).
  Future<void> ensureInitialized() async {
    if (_manifest != null) return;
    final registration = await _runtime.registerVeneraSource(jsKey, _code);
    final manifest = registration['manifest'];
    if (manifest is Map) _manifest = manifest.cast<String, dynamic>();
    final diagnostics = registration['diagnostics'];
    if (diagnostics is Map) {
      _diagnostics = diagnostics.cast<String, dynamic>();
    }
  }

  Future<Map<String, dynamic>> _call(
    String kind, [
    Map<String, dynamic> args = const {},
  ]) async {
    await ensureInitialized();
    return _runtime.call(manifestKey, kind, args);
  }

  @override
  Future<List<MangaItem>> search(
    String keyword, {
    int limit = 30,
    int page = 1,
  }) async {
    final result = await _call('search', {'keyword': keyword, 'page': page});
    return mapMkComicList(result['items'], sourceId: id);
  }

  @override
  Future<List<MangaItem>> popular({int limit = 20, int page = 1}) =>
      popularWithSections(page: page);

  /// [popular] with the framework's progressive explore:
  /// [onSection] receives each section's items the moment
  /// the section lands (the future still completes with the
  /// full flattened list). [fresh] bypasses the framework's
  /// refresh guard — wire it to the pull-to-refresh gesture
  /// so a manual refresh really re-runs.
  Future<List<MangaItem>> popularWithSections({
    int page = 1,
    bool fresh = false,
    void Function(List<MangaItem> sectionItems)? onSection,
  }) async {
    final List<MangaItem> items;
    try {
      items = await exploreItems(
        page: page,
        refresh: fresh,
        onSection: onSection,
      );
    } on MangaKitException catch (e) {
      // A source with no explore surface at all falls back
      // to the blank search below; every other failure
      // (including verification walls) propagates.
      if (e.code != 'MK_UNSUPPORTED_KIND') rethrow;
      return _blankSearchFallback(page);
    }
    if (items.isNotEmpty || page > 1) return items;
    return _blankSearchFallback(page, seed: items);
  }

  Future<List<MangaItem>> _blankSearchFallback(
    int page, {
    List<MangaItem> seed = const [],
  }) async {
    try {
      return await search('', page: page);
    } catch (_) {
      return seed;
    }
  }

  @override
  Future<List<MangaItem>> updated({int limit = 20, int page = 1}) =>
      popular(limit: limit, page: page);

  /// All explore sections flattened into one list, in
  /// section order, de-duped by comic id. [onSection] fires
  /// per section the moment it lands (progressive output);
  /// [refresh] bypasses the framework's refresh guard (the
  /// pull-to-refresh gesture).
  Future<List<MangaItem>> exploreItems({
    int page = 1,
    void Function(List<MangaItem> sectionItems)? onSection,
    bool refresh = false,
  }) async {
    await ensureInitialized();
    final seen = <String>{};
    final collected = <MangaItem>[];
    void absorb(List<MangaItem> items) {
      for (final item in items) {
        if (seen.add(item.id)) collected.add(item);
      }
    }

    final result = await _runtime.call(
      manifestKey,
      'explore',
      {'page': page},
      refresh: refresh,
      onSection: onSection == null
          ? null
          : (section) {
              final items = mapMkComicList(section['items'], sourceId: id);
              if (items.isNotEmpty) onSection(items);
            },
    );
    final sections = result['sections'];
    if (sections is List) {
      for (final section in sections) {
        if (section is Map) {
          absorb(mapMkComicList(section['items'], sourceId: id));
        }
      }
    }
    return collected;
  }

  @override
  Future<List<MangaTag>> tags() async {
    try {
      final result = await _call('categories');
      final categories = result['categories'];
      if (categories is! List) return const [];
      return [
        for (final entry in categories)
          if (entry is Map)
            MangaTag(
              id: entry['id']?.toString() ?? '',
              name: entry['name']?.toString() ?? '',
              group: entry['group']?.toString() ?? '',
            ),
      ];
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
    final result = await _call('category', {
      'category': tagId,
      'page': page,
    });
    return mapMkComicList(result['items'], sourceId: id);
  }

  @override
  Future<List<MangaChapter>> chapters(MangaItem manga) async {
    final result = await _call('chapters', {'id': manga.id});
    final raw = result['chapters'];
    final chapters = <MangaChapter>[
      if (raw is List)
        for (final entry in raw)
          if (entry is Map) mapMkChapter(entry.cast<String, dynamic>()),
    ];
    if (chapters.isNotEmpty) return chapters;
    // Single-volume sources: the comic itself is the one
    // chapter (the framework's compat layer synthesizes it
    // too; this is the belt-and-braces path).
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

  @override
  Future<MangaItem?> details(MangaItem manga) async {
    final result = await _call('details', {'id': manga.id});
    return mergeMkDetails(manga, result);
  }

  @override
  Future<List<MangaPage>> pages(
    MangaItem manga,
    MangaChapter chapter,
  ) async {
    final result = await _call('pages', {
      'comicId': manga.id,
      'chapterId': chapter.id,
    });
    final images = result['images'];
    if (images is! List) return const [];
    return [
      for (final entry in images)
        if (entry is Map) mapMkPage(entry.cast<String, dynamic>()),
    ];
  }

  @override
  Future<List<String>> loadThumbnails(MangaItem manga) async {
    try {
      final result = await _call('thumbnails', {'id': manga.id});
      final images = result['images'];
      if (images is List) {
        return [
          for (final url in images)
            if (url is String && url.isNotEmpty) url,
        ];
      }
      return const [];
    } catch (_) {
      return const [];
    }
  }

  // ---- image hooks (driven by the reader pipeline) -------

  /// Runs the registered onResponse byte transform over
  /// downloaded bytes ('image' pages / 'thumb' covers).
  Future<List<int>?> transformImageBytes({
    required String mode,
    required String originalUrl,
    String id = '',
    String ep = '',
    required List<int> raw,
  }) async {
    try {
      final result = await _call('imageOnResponse', {
        'mode': mode,
        'of': originalUrl,
        'id': id,
        'ep': ep,
        'bytesB64': base64Encode(raw),
      });
      if (result['ok'] == true) {
        final b64 = result['bytesB64']?.toString() ?? '';
        if (b64.isNotEmpty) return base64Decode(b64);
      }
    } catch (_) {}
    return null;
  }

  /// Runs a config's modifyImage code string over downloaded
  /// bytes (descramble), on the host image registry.
  Future<List<int>?> modifyImageBytes({
    required String code,
    required List<int> raw,
  }) async {
    try {
      final result = await _call('imageModify', {
        'code': code,
        'bytesB64': base64Encode(raw),
      });
      if (result['ok'] == true) {
        final b64 = result['bytesB64']?.toString() ?? '';
        if (b64.isNotEmpty) return base64Decode(b64);
      }
    } catch (_) {}
    return null;
  }

  /// Asks the failed page's onLoadFailed hook for a
  /// replacement config, in the legacy config-map shape the
  /// image pipeline consumes.
  Future<Map<String, dynamic>?> loadFailedConfig({
    required String originalUrl,
    String id = '',
    String ep = '',
  }) async {
    try {
      final result = await _call('imageFallback', {
        'of': originalUrl,
        'id': id,
        'ep': ep,
      });
      final image = result['image'];
      if (image is! Map) return null;
      final entry = image.cast<String, dynamic>();
      return {
        'url': entry['url']?.toString() ?? '',
        'headers': entry['headers'] is Map
            ? (entry['headers'] as Map).cast<String, dynamic>()
            : <String, dynamic>{},
        'transform': entry['transformOf'] != null,
        'modify': entry['modifyCode']?.toString() ?? '',
        'fallback': entry['fallbackOf'] != null,
      };
    } catch (_) {
      return null;
    }
  }

  // ---- account ---------------------------------------------

  @override
  Future<MangaAccountInfo?> accountInfo() async {
    final Map<String, dynamic> result;
    try {
      result = await _call('account');
    } catch (_) {
      return null;
    }
    final hasLogin = result['hasLogin'] == true;
    if (!hasLogin) return null;
    var kvHasToken = false;
    try {
      final kv = jsonDecode(VeneraEngine.kvJsonFor(jsKey));
      if (kv is Map && kv['data'] is Map) {
        kvHasToken = (kv['data'] as Map)['token'] != null;
      }
    } catch (_) {}
    final website = result['registerWebsite']?.toString() ?? '';
    return MangaAccountInfo(
      hasLogin: true,
      hasLogout: result['hasLogout'] == true,
      isLoggedIn: result['isLoggedIn'] == true ||
          kvHasToken ||
          MangaAccountSessions.isLoggedIn(jsKey),
      registerWebsite: website.isEmpty ? null : website,
    );
  }

  @override
  Future<void> login(String username, String password) async {
    await _call('login', {'username': username, 'password': password});
    await MangaAccountSessions.markLoggedIn(jsKey);
  }

  @override
  Future<void> logout() async {
    try {
      await _call('logout');
    } finally {
      await MangaAccountSessions.markLoggedOut(jsKey);
    }
  }

  // ---- source settings (batch 191 surface) -----------------

  /// The declared settings schema, in declaration order.
  Future<List<MangaSettingDef>> settingsSchema() async {
    await ensureInitialized();
    final schema = await _runtime.settingsSchema(manifestKey);
    return [
      for (final item in schema)
        MangaSettingDef(
          key: item['key']?.toString() ?? '',
          title: item['title']?.toString() ?? item['key']?.toString() ?? '',
          type: item['type']?.toString() ?? 'input',
          options: [
            if (item['options'] is List)
              for (final option in item['options'] as List)
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
          defaultValue: item['default'],
          validator: item['validator']?.toString(),
          buttonText: item['buttonText']?.toString(),
          hasCallback: item['hasCallback'] == true,
        ),
    ];
  }

  /// Current setting values (defaults + user edits), read
  /// from the same persisted KV both engines share.
  Map<String, dynamic> settingValues() {
    try {
      final kv = jsonDecode(VeneraEngine.kvJsonFor(jsKey));
      if (kv is Map && kv['settings'] is Map) {
        return (kv['settings'] as Map).cast<String, dynamic>();
      }
    } catch (_) {}
    return const {};
  }

  /// Writes one setting value through the framework
  /// (persists via the bridge store into the shared KV,
  /// updates the live snapshot, fires the source's
  /// onSettingChange).
  Future<void> writeSetting(String key, Object? value) async {
    await ensureInitialized();
    await _runtime.writeSetting(manifestKey, key, value);
  }

  /// Runs a callback-type setting inside the runtime.
  Future<void> invokeSettingCallback(String key) async {
    await ensureInitialized();
    await _runtime.invokeSettingCallback(manifestKey, key);
  }
}

/// Maps one framework-normalized comic to a [MangaItem].
/// Pure and synchronous — the unit-testable half.
MangaItem mapMkComic(Map<String, dynamic> json, {required String sourceId}) {
  final tags = <String>[];
  final rawTags = json['tags'];
  if (rawTags is List) {
    for (final tag in rawTags) {
      if (tag is String) {
        if (tag.isNotEmpty) tags.add(tag);
      } else if (tag is Map) {
        final name = tag['name']?.toString() ?? tag['title']?.toString() ?? '';
        if (name.isNotEmpty) tags.add(name);
      }
    }
  }
  final headers = <String, String>{};
  final rawHeaders = json['coverHeaders'];
  if (rawHeaders is Map) {
    rawHeaders.forEach((k, v) {
      headers[k.toString()] = v.toString();
    });
  }
  DateTime? updatedAt;
  final rawUpdated = json['updatedAt'];
  if (rawUpdated is String && rawUpdated.isNotEmpty) {
    updatedAt = DateTime.tryParse(rawUpdated);
  } else if (rawUpdated is num && rawUpdated > 0) {
    updatedAt = DateTime.fromMillisecondsSinceEpoch(
      rawUpdated > 100000000000 ? rawUpdated.toInt() : (rawUpdated * 1000).toInt(),
    );
  }
  final author = json['author']?.toString() ?? '';
  return MangaItem(
    id: json['id']?.toString() ?? '',
    title: json['title']?.toString() ?? '',
    description: json['description']?.toString() ?? '',
    coverUrl: json['cover']?.toString() ?? '',
    author: author.isNotEmpty
        ? author
        : json['subtitle']?.toString() ?? '',
    status: normalizeMangaStatus(json['status']?.toString() ?? ''),
    year: updatedAt?.year,
    tags: tags,
    source: sourceId,
    headers: headers,
    coverTransformOf: json['coverTransformOf']?.toString(),
  );
}

List<MangaItem> mapMkComicList(dynamic raw, {required String sourceId}) {
  if (raw is! List) return const [];
  return [
    for (final entry in raw)
      if (entry is Map) mapMkComic(entry.cast<String, dynamic>(), sourceId: sourceId),
  ];
}

/// Maps one framework-normalized chapter to a [MangaChapter]
/// (the framework's `group` becomes the volume slot).
MangaChapter mapMkChapter(Map<String, dynamic> json) {
  DateTime? publishedAt;
  final rawUpdated = json['updatedAt'];
  if (rawUpdated is String && rawUpdated.isNotEmpty) {
    publishedAt = DateTime.tryParse(rawUpdated);
  }
  final group = json['group']?.toString() ?? '';
  return MangaChapter(
    id: json['id']?.toString() ?? '',
    volume: group.isEmpty ? null : group,
    chapter: null,
    title: json['title']?.toString() ?? '',
    language: '',
    pages: 0,
    publishedAt: publishedAt,
  );
}

/// Maps one framework-normalized image entry to a
/// [MangaPage], hook markers included.
MangaPage mapMkPage(Map<String, dynamic> json) {
  final headers = <String, String>{};
  final rawHeaders = json['headers'];
  if (rawHeaders is Map) {
    rawHeaders.forEach((k, v) {
      headers[k.toString()] = v.toString();
    });
  }
  return MangaPage(
    json['url']?.toString() ?? '',
    headers: headers,
    transformOf: json['transformOf']?.toString(),
    modifyCode: json['modifyCode']?.toString(),
    fallbackOf: json['fallbackOf']?.toString(),
  );
}

/// Merges a framework details result into the list-carried
/// item: detail fields win when non-empty, list fields are
/// kept otherwise.
MangaItem mergeMkDetails(MangaItem base, Map<String, dynamic> details) {
  final rich = mapMkComic(details, sourceId: base.source);
  return base.copyWith(
    title: rich.title.isNotEmpty ? rich.title : base.title,
    description:
        rich.description.isNotEmpty ? rich.description : base.description,
    coverUrl: rich.coverUrl.isNotEmpty ? rich.coverUrl : base.coverUrl,
    author: rich.author.isNotEmpty ? rich.author : base.author,
    status: rich.status.isNotEmpty ? rich.status : base.status,
    year: rich.year ?? base.year,
    tags: rich.tags.isNotEmpty ? rich.tags : base.tags,
    headers: rich.headers.isNotEmpty ? rich.headers : base.headers,
    coverTransformOf: rich.coverTransformOf ?? base.coverTransformOf,
  );
}
