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
  String get description => 'JS 源（Venera 格式）· v$version';

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
    return mapJsComicList(result, sourceId: id);
  }

  @override
  Future<List<MangaItem>> popular({int limit = 20, int page = 1}) async {
    final result = await engine.call('explore', {'page': page});
    final items = mapJsComicList(result, sourceId: id);
    if (items.isNotEmpty || page > 1) return items;
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
    return mapJsComicList(result, sourceId: id);
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
    return mapJsPages(result.cast<String, dynamic>());
  }

  @override
  Future<MangaItem?> details(MangaItem manga) async {
    final result = await engine.call('loadInfo', {'id': manga.id});
    if (result is! Map) return null;
    return mapJsDetails(
      unwrapJsDetails(result.cast<String, dynamic>()),
      manga,
    );
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
  void add(String id, String title) {
    if (id.isEmpty) return;
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
  return [
    for (final image in images)
      if (image is String && image.isNotEmpty)
        MangaPage(image, headers: fallbackHeaders)
      else if (image is Map && image['url'] != null)
        MangaPage(
          image['url'].toString(),
          headers: {
            ...fallbackHeaders,
            if (image['headers'] is Map)
              for (final entry in (image['headers'] as Map).entries)
                entry.key.toString(): entry.value.toString(),
          },
        ),
  ];
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
