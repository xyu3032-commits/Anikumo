import 'dart:async';
import 'dart:convert';

import 'package:liuguang_core/liuguang_core.dart';

import 'package:anikumo/request/core/dio_factory.dart';
import 'package:anikumo/services/liuguang/cms_api_source.dart';
import 'package:anikumo/services/liuguang/tvmaze_covers.dart';
import 'package:anikumo/services/storage/storage.dart';
import 'package:anikumo/services/tmdb/tmdb_episodes.dart';

/// Batch 229: TMDB enrichment for the film zone's detail
/// pages — the cast (with the character each person plays)
/// and the user reviews a CMS interface cannot provide,
/// plus an overview / score to fall back on when the
/// source's own are empty.
///
/// Posture (the TVmaze cover rules, batch 211): matching
/// is conservative — an exact title hit is required, the
/// year must agree when both sides know it — and every
/// failure is silent. With no TMDB key configured (the
/// user's own key wins, the built-in one backs it) the
/// service resolves to null and the detail page looks
/// exactly as before. Live channels never look up.
class TmdbCastMember {
  const TmdbCastMember({
    required this.name,
    required this.character,
    this.profileUrl,
  });

  final String name;
  final String character;
  final String? profileUrl;

  Map<String, dynamic> toJson() => {
    'n': name,
    'c': character,
    if (profileUrl != null) 'p': profileUrl,
  };

  static TmdbCastMember? fromJson(dynamic json) {
    if (json is! Map) return null;
    final name = json['n']?.toString() ?? '';
    if (name.isEmpty) return null;
    return TmdbCastMember(
      name: name,
      character: json['c']?.toString() ?? '',
      profileUrl: json['p']?.toString(),
    );
  }
}

class TmdbReview {
  const TmdbReview({
    required this.author,
    required this.content,
    this.rating,
    this.date = '',
  });

  final String author;
  final String content;
  final double? rating;

  /// yyyy-MM-dd, '' when unknown.
  final String date;

  Map<String, dynamic> toJson() => {
    'a': author,
    'c': content,
    if (rating != null) 'r': rating,
    if (date.isNotEmpty) 'd': date,
  };

  static TmdbReview? fromJson(dynamic json) {
    if (json is! Map) return null;
    final content = json['c']?.toString() ?? '';
    if (content.isEmpty) return null;
    return TmdbReview(
      author: json['a']?.toString() ?? '',
      content: content,
      rating: (json['r'] as num?)?.toDouble(),
      date: json['d']?.toString() ?? '',
    );
  }
}

class TmdbEnrichment {
  const TmdbEnrichment({
    this.cast = const [],
    this.reviews = const [],
    this.overview = '',
    this.score = 0,
    this.genres = const [],
    this.keywords = const [],
    this.tmdbId = 0,
    this.isSeries = false,
  });

  final List<TmdbCastMember> cast;
  final List<TmdbReview> reviews;
  final String overview;
  final double score;

  /// Batch 246: the work's TMDB genres and keyword tags,
  /// in whichever language the active mode fetched —
  /// display translates them (tmdbDisplayTerm).
  final List<String> genres;
  final List<String> keywords;

  /// Batch 254: the matched work's TMDB id and kind, so
  /// the detail page can drive account actions
  /// (favorite / watchlist) against the right entry.
  /// 0 = no confident match. Rides the cache JSON.
  final int tmdbId;
  final bool isSeries;

  bool get isEmpty => cast.isEmpty && reviews.isEmpty && overview.isEmpty;

  Map<String, dynamic> toJson() => {
    'cast': [for (final c in cast) c.toJson()],
    'reviews': [for (final r in reviews) r.toJson()],
    'overview': overview,
    'score': score,
    'genres': genres,
    'keywords': keywords,
    'tmdbId': tmdbId,
    'isSeries': isSeries,
  };

  static TmdbEnrichment? fromJson(dynamic json) {
    if (json is! Map) return null;
    final out = TmdbEnrichment(
      cast: [
        for (final c in (json['cast'] as List? ?? const []))
          if (TmdbCastMember.fromJson(c) case final m?) m,
      ],
      reviews: [
        for (final r in (json['reviews'] as List? ?? const []))
          if (TmdbReview.fromJson(r) case final m?) m,
      ],
      overview: json['overview']?.toString() ?? '',
      score: (json['score'] as num?)?.toDouble() ?? 0,
      genres: [
        for (final g in (json['genres'] as List? ?? const [])) g.toString(),
      ],
      keywords: [
        for (final k in (json['keywords'] as List? ?? const [])) k.toString(),
      ],
      tmdbId: (json['tmdbId'] as num?)?.toInt() ?? 0,
      isSeries: json['isSeries'] == true,
    );
    return out.isEmpty ? null : out;
  }
}

/// Title normalisation for matching: case- and
/// punctuation-insensitive, season suffixes stripped.
String normalizeTmdbTitle(String title) =>
    normalizeTvmazeTitle(cmsBaseTitle(title));

/// Batch 229: picks a TMDB work id out of decoded search
/// results — conservatively. An exact title match (against
/// the display or original title, of the season-stripped
/// base title too) is REQUIRED; the year then breaks ties
/// and a hard year conflict (both known, more than a year
/// apart) rejects the candidate outright. Pure, for tests.
int? pickTmdbWorkId(
  List<dynamic> results, {
  required String title,
  required int? year,
  required bool isSeries,
}) {
  final wanted = {normalizeTmdbTitle(title), normalizeTvmazeTitle(title)}
    ..remove('');
  if (wanted.isEmpty) return null;
  int? bestId;
  var bestScore = 99; // an exact title match scores 100
  for (final result in results) {
    if (result is! Map) continue;
    var exact = false;
    for (final key in const [
      'name',
      'title',
      'original_name',
      'original_title',
    ]) {
      final candidate = result[key];
      if (candidate is String &&
          wanted.contains(normalizeTvmazeTitle(candidate))) {
        exact = true;
        break;
      }
    }
    if (!exact) continue;
    var score = 100;
    final date = (result[isSeries ? 'first_air_date' : 'release_date'] ?? '')
        .toString();
    if (year != null && date.length >= 4) {
      final hitYear = int.tryParse(date.substring(0, 4));
      if (hitYear != null) {
        if (hitYear == year) {
          score += 40;
        } else if ((hitYear - year).abs() <= 1) {
          score += 15;
        } else {
          score -= 200; // a different work with the same name
        }
      }
    }
    if (score > bestScore) {
      bestScore = score;
      bestId = (result['id'] as num?)?.toInt();
    }
  }
  return bestId;
}

/// Batch 229: the cast of a decoded TMDB credits payload,
/// in billing order. Pure, for tests.
List<TmdbCastMember> parseTmdbCredits(dynamic json) {
  final cast = json is Map ? json['cast'] : null;
  if (cast is! List) return const [];
  final rows =
      [
        for (final row in cast)
          if (row is Map) row,
      ]..sort(
        (a, b) => ((a['order'] as num?)?.toInt() ?? 999).compareTo(
          (b['order'] as num?)?.toInt() ?? 999,
        ),
      );
  return [
    for (final row in rows.take(20))
      if ((row['name']?.toString() ?? '').isNotEmpty)
        TmdbCastMember(
          name: row['name'].toString(),
          character: row['character']?.toString() ?? '',
          profileUrl: (row['profile_path']?.toString() ?? '').isEmpty
              ? null
              : 'https://image.tmdb.org/t/p/w185${row['profile_path']}',
        ),
  ];
}

/// Batch 229: the reviews of a decoded TMDB reviews
/// payload, newest first. Pure, for tests.
List<TmdbReview> parseTmdbReviews(dynamic json) {
  final results = json is Map ? json['results'] : null;
  if (results is! List) return const [];
  final out = <TmdbReview>[];
  for (final row in results) {
    if (row is! Map) continue;
    final content = (row['content']?.toString() ?? '').trim();
    if (content.isEmpty) continue;
    final details = row['author_details'];
    var author = row['author']?.toString() ?? '';
    if (details is Map) {
      author = (details['name']?.toString().isNotEmpty ?? false)
          ? details['name'].toString()
          : (details['username']?.toString() ?? author);
    }
    final created = row['created_at']?.toString() ?? '';
    out.add(
      TmdbReview(
        author: author,
        content: content,
        rating: details is Map ? (details['rating'] as num?)?.toDouble() : null,
        date: created.length >= 10 ? created.substring(0, 10) : '',
      ),
    );
  }
  out.sort((a, b) => b.date.compareTo(a.date));
  return out.take(10).toList();
}

/// Batch 242: reviews for the detail page, Chinese
/// first. The page is a Chinese UI and popular works do
/// carry zh-CN reviews (verified live: Dune has 4), so
/// the zh call runs first; only when it yields nothing
/// does the default-language call run, so obscure titles
/// keep the reviews they have instead of losing the
/// section. [fetchReviews] performs one reviews call in
/// the given language mode. Pure flow, for tests.
Future<List<TmdbReview>> tmdbReviewsPreferZh(
  Future<dynamic> Function(bool zh) fetchReviews,
) async {
  try {
    final zh = parseTmdbReviews(await fetchReviews(true));
    if (zh.isNotEmpty) return zh;
  } catch (_) {
    // Fall through to the default-language call.
  }
  try {
    return parseTmdbReviews(await fetchReviews(false));
  } catch (_) {
    return const [];
  }
}

/// Batch 229: one enrichment out of a decoded TMDB detail
/// payload fetched with append_to_response=credits (the
/// reviews ride their own call — see the service). Pure,
/// for tests.
TmdbEnrichment parseTmdbDetail(
  dynamic json, {
  List<TmdbReview>? reviews,
  List<String>? keywords,
  int tmdbId = 0,
  bool isSeries = false,
}) {
  if (json is! Map) return const TmdbEnrichment();
  return TmdbEnrichment(
    tmdbId: tmdbId,
    isSeries: isSeries,
    cast: parseTmdbCredits(json['credits']),
    reviews: reviews ?? parseTmdbReviews(json['reviews']),
    overview: (json['overview']?.toString() ?? '').trim(),
    score: (json['vote_average'] as num?)?.toDouble() ?? 0,
    genres: [
      if (json['genres'] is List)
        for (final g in json['genres'] as List)
          if (g is Map && (g['name']?.toString() ?? '').isNotEmpty)
            g['name'].toString(),
    ],
    keywords: keywords ?? const [],
  );
}

/// Batch 246: keyword names out of a /keywords payload —
/// movies nest them under `keywords`, series under
/// `results`. Capped at 12 (the merge trims further).
/// Pure, for tests.
List<String> parseTmdbKeywords(dynamic json, {required bool isSeries}) {
  if (json is! Map) return const [];
  final rows = isSeries ? json['results'] : json['keywords'];
  if (rows is! List) return const [];
  final out = <String>[];
  for (final row in rows) {
    if (row is! Map) continue;
    final name = (row['name']?.toString() ?? '').trim();
    if (name.isEmpty) continue;
    out.add(name);
    if (out.length >= 12) break;
  }
  return out;
}

/// Batch 230: one TMDB work as the search page's TMDB
/// mode presents it — pure metadata; playability comes
/// from matching it against the installed sources.
class TmdbWork {
  const TmdbWork({
    required this.tmdbId,
    required this.isSeries,
    required this.title,
    this.year,
    this.overview = '',
    this.posterUrl,
    this.score = 0,
  });

  final int tmdbId;
  final bool isSeries;
  final String title;
  final int? year;
  final String overview;
  final String? posterUrl;
  final double score;
}

/// Batch 230: TMDB search results (the /search/multi
/// shape) as works — people and untitled rows are dropped.
/// Pure, for tests.
List<TmdbWork> parseTmdbSearchResults(dynamic json) {
  final results = json is Map ? json['results'] : null;
  if (results is! List) return const [];
  final out = <TmdbWork>[];
  for (final row in results) {
    if (row is! Map) continue;
    final type = row['media_type']?.toString() ?? '';
    if (type != 'tv' && type != 'movie') continue;
    final isSeries = type == 'tv';
    final title = (row[isSeries ? 'name' : 'title'] ?? '').toString().trim();
    final id = (row['id'] as num?)?.toInt();
    if (title.isEmpty || id == null) continue;
    final date = (row[isSeries ? 'first_air_date' : 'release_date'] ?? '')
        .toString();
    final poster = (row['poster_path']?.toString() ?? '').trim();
    out.add(
      TmdbWork(
        tmdbId: id,
        isSeries: isSeries,
        title: title,
        year: date.length >= 4 ? int.tryParse(date.substring(0, 4)) : null,
        overview: (row['overview']?.toString() ?? '').trim(),
        posterUrl: poster.isEmpty
            ? null
            : 'https://image.tmdb.org/t/p/w500$poster',
        score: (row['vote_average'] as num?)?.toDouble() ?? 0,
      ),
    );
    if (out.length >= 20) break;
  }
  return out;
}

/// Batch 230: orders matched catalogue items best-first —
/// by the caller-supplied source rank (healthy sources
/// first), stable within a rank. Pure, for tests.
List<MediaItem> rankTmdbMatches(
  List<MediaItem> items,
  int Function(String sourceId) sourceRank,
) {
  final decorated = [for (var i = 0; i < items.length; i++) (i, items[i])]
    ..sort((a, b) {
      final byRank = sourceRank(
        a.$2.sourceId,
      ).compareTo(sourceRank(b.$2.sourceId));
      return byRank != 0 ? byRank : a.$1.compareTo(b.$1);
    });
  return [for (final d in decorated) d.$2];
}

/// Batch 230: finds the playable versions of TMDB works
/// among the installed sources. One aggregated search per
/// work (the engine fans out to every enabled source),
/// filtered by cmsMatchesTmdbWork; results are memoized
/// per work so a card's badge and its tap share one pass.
class TmdbWorkMatcher {
  TmdbWorkMatcher(this._searchAll);

  final Future<List<MediaItem>> Function(String keyword) _searchAll;
  final Map<String, Future<List<MediaItem>>> _memo = {};

  static String _keyOf(TmdbWork work) =>
      '${work.isSeries ? 'tv' : 'movie'}:${work.tmdbId}';

  Future<List<MediaItem>> matchesFor(TmdbWork work) {
    return _memo.putIfAbsent(_keyOf(work), () async {
      try {
        final items = await _searchAll(cmsBaseTitle(work.title));
        return items
            .where(
              (item) => cmsMatchesTmdbWork(
                item,
                title: work.title,
                year: work.year,
                isSeries: work.isSeries,
              ),
            )
            .toList();
      } catch (_) {
        return const [];
      }
    });
  }
}

/// Batch 243: the film zone's TMDB data mode, set in the
/// film settings — false （国内， the default) pulls
/// zh-CN metadata; true （海外） pulls TMDB's default
/// original-language metadata. Guarded like every other
/// film-zone storage read.
bool tmdbOverseasMode() {
  try {
    return GStorage.getSetting(SettingsKeys.filmTmdbOverseas);
  } catch (_) {
    return false;
  }
}

/// Batch 243: the poster a TMDB kind-search payload
/// offers for one work — the confident pick's w500
/// poster, or null. Pure, for tests.
String? tmdbPosterUrlFromSearch(
  dynamic json, {
  required String title,
  int? year,
  required bool isSeries,
}) {
  final results = json is Map ? json['results'] : null;
  if (results is! List) return null;
  final id = pickTmdbWorkId(
    results,
    title: title,
    year: year,
    isSeries: isSeries,
  );
  if (id == null) return null;
  for (final row in results) {
    if (row is Map && (row['id'] as num?)?.toInt() == id) {
      final path = (row['poster_path']?.toString() ?? '').trim();
      return path.isEmpty ? null : 'https://image.tmdb.org/t/p/w500$path';
    }
  }
  return null;
}

/// Batch 243: card posters from TMDB, ahead of every
/// other cover source (the user set TMDB as the metadata
/// priority; works TMDB lacks keep the source's own
/// chain). One kind-search per work, cached persistently
/// per data mode, misses cached as ''.
class TmdbPosterService {
  TmdbPosterService._();
  static final TmdbPosterService instance = TmdbPosterService._();

  static const _maxCacheEntries = 600;
  // Batch 248: 3 -> 6 — a full grid of first-visit
  // posters queued three-wide felt like the wall itself
  // was loading slowly.
  static const _maxConcurrent = 6;

  final Map<String, String> _cache = {};
  final Map<String, Future<String?>> _inFlight = {};
  bool _cacheLoaded = false;
  int _active = 0;
  final List<Completer<void>> _waiters = [];
  DateTime? _lastPersistAt;
  Timer? _persistTimer;
  bool _persistDirty = false;

  String _key(MediaItem item) =>
      '${tmdbOverseasMode() ? 'intl' : 'cn'}|'
      '${normalizeTmdbTitle(item.title)}|${item.year ?? ''}|'
      '${item.mediaType == MediaType.series ? 'tv' : 'movie'}';

  void _loadCache() {
    if (_cacheLoaded) return;
    _cacheLoaded = true;
    try {
      final raw = GStorage.getSetting(SettingsKeys.videoTmdbPosterCacheJson);
      if (raw.trim().isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        decoded.forEach((k, v) => _cache['$k'] = '$v');
      }
    } catch (_) {
      // A corrupt poster cache just re-resolves on demand.
    }
  }

  Future<void> _schedulePersist() {
    _persistDirty = true;
    final last = _lastPersistAt;
    if (last != null &&
        DateTime.now().difference(last) < const Duration(seconds: 2)) {
      _persistTimer ??= Timer(const Duration(seconds: 2), () {
        _persistTimer = null;
        if (_persistDirty) _persistCache();
      });
      return Future.value();
    }
    return _persistCache();
  }

  Future<void> _persistCache() async {
    _persistDirty = false;
    _lastPersistAt = DateTime.now();
    while (_cache.length > _maxCacheEntries) {
      _cache.remove(_cache.keys.first);
    }
    try {
      await GStorage.putSetting(
        SettingsKeys.videoTmdbPosterCacheJson,
        jsonEncode(_cache),
      );
    } catch (_) {
      // Persistence is best-effort.
    }
  }

  /// The already-known TMDB poster for [item] (no
  /// network), or null when unknown / a confirmed miss.
  String? cachedPosterFor(MediaItem item) {
    _loadCache();
    final hit = _cache[_key(item)];
    return (hit == null || hit.isEmpty) ? null : hit;
  }

  /// Resolves the TMDB poster for [item]; null when
  /// there is no key, the work is live, or TMDB has no
  /// confident match — the card keeps its other covers.
  Future<String?> posterFor(MediaItem item) {
    if (cmsItemIsLive(item)) return Future.value(null);
    // Batch 244 fix: hasKey reads storage unguarded — in
    // contexts where storage is not up yet (widget tests,
    // early frames) that throws a LateError, so the key
    // check takes the zone's usual guarded shape here.
    var hasKey = false;
    try {
      hasKey = TmdbEpisodeService.hasKey;
    } catch (_) {}
    if (!hasKey) return Future.value(null);
    _loadCache();
    final key = _key(item);
    final hit = _cache[key];
    if (hit != null) return Future.value(hit.isEmpty ? null : hit);
    return _inFlight.putIfAbsent(key, () => _resolve(key, item));
  }

  Future<void> _acquire() {
    if (_active < _maxConcurrent) {
      _active++;
      return Future.value();
    }
    final completer = Completer<void>();
    _waiters.add(completer);
    return completer.future.then((_) => _active++);
  }

  void _release() {
    _active--;
    if (_waiters.isNotEmpty) {
      _waiters.removeAt(0).complete();
    }
  }

  Future<String?> _resolve(String key, MediaItem item) async {
    await _acquire();
    try {
      final isSeries = item.mediaType == MediaType.series;
      final kind = isSeries ? 'tv' : 'movie';
      final response = await DioFactory.apiDio.get(
        '${TmdbEnrichService._apiBase}/search/$kind',
        queryParameters: {
          'api_key': TmdbEpisodeService.effectiveKey,
          if (!tmdbOverseasMode()) 'language': 'zh-CN',
          'query': cmsBaseTitle(item.title),
        },
      );
      final url = tmdbPosterUrlFromSearch(
        response.data,
        title: item.title,
        year: item.year,
        isSeries: isSeries,
      );
      _cache[key] = url ?? '';
      await _schedulePersist();
      return url;
    } catch (_) {
      return null; // failures stay uncached and retry later
    } finally {
      _release();
      _inFlight.remove(key);
    }
  }
}

/// Batch 244: the season number a title declares —
/// 第N季 (Arabic or Chinese numerals), Season N, or SN.
/// Null when the title carries no season marker. Pure,
/// for tests.
int? tmdbSeasonNumberFromTitle(String title) {
  const numerals = {
    '一': 1,
    '二': 2,
    '三': 3,
    '四': 4,
    '五': 5,
    '六': 6,
    '七': 7,
    '八': 8,
    '九': 9,
  };
  final cn = RegExp(r'第([一二三四五六七八九十]+)季').firstMatch(title);
  if (cn != null) {
    final token = cn.group(1)!;
    var value = 0;
    var ok = true;
    for (final ch in token.split('')) {
      if (ch == '十') {
        value = (value == 0 ? 1 : value) * 10;
      } else if (numerals.containsKey(ch)) {
        value += numerals[ch]!;
      } else {
        ok = false;
        break;
      }
    }
    if (ok && value > 0) return value;
  }
  final ar = RegExp(r'第\s*(\d+)\s*季').firstMatch(title);
  if (ar != null) return int.tryParse(ar.group(1)!);
  final en = RegExp(r'[Ss]eason\s*(\d+)').firstMatch(title);
  if (en != null) return int.tryParse(en.group(1)!);
  final sN = RegExp(r'\bS(\d{1,2})\b').firstMatch(title);
  if (sN != null) return int.tryParse(sN.group(1)!);
  return null;
}

/// Batch 244: episode names from a TMDB
/// /tv/{id}/season/{n} payload — {episode_number: name},
/// unnamed episodes omitted. Pure, for tests.
Map<int, String> parseTmdbSeasonEpisodeNames(dynamic json) {
  final episodes = json is Map ? json['episodes'] : null;
  if (episodes is! List) return const {};
  final out = <int, String>{};
  for (final row in episodes) {
    if (row is! Map) continue;
    final number = (row['episode_number'] as num?)?.toInt();
    final name = (row['name']?.toString() ?? '').trim();
    if (number != null && number > 0 && name.isNotEmpty) {
      out[number] = name;
    }
  }
  return out;
}

/// Batch 244: TMDB episode names for the film zone's
/// series — shown in the detail page's episode grid and
/// the shared player's episode panel, whose identifiers
/// otherwise carry the station's bare 第N集 labels. One
/// search + one season call per work, cached per data
/// mode; any failure reads as no names and the station's
/// own labels stay.
class TmdbEpisodeNamesService {
  TmdbEpisodeNamesService._();
  static final TmdbEpisodeNamesService instance = TmdbEpisodeNamesService._();

  static const _maxCacheEntries = 300;

  final Map<String, Map<int, String>> _cache = {};
  final Map<String, Future<Map<int, String>>> _inFlight = {};
  bool _cacheLoaded = false;
  DateTime? _lastPersistAt;
  Timer? _persistTimer;
  bool _persistDirty = false;

  String _key(MediaItem item) =>
      '${tmdbOverseasMode() ? 'intl' : 'cn'}|'
      '${normalizeTmdbTitle(item.title)}|${item.year ?? ''}';

  void _loadCache() {
    if (_cacheLoaded) return;
    _cacheLoaded = true;
    try {
      final raw = GStorage.getSetting(
        SettingsKeys.videoTmdbEpisodeNamesCacheJson,
      );
      if (raw.trim().isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        decoded.forEach((k, v) {
          if (v is Map) {
            _cache['$k'] = {
              for (final e in v.entries)
                if (int.tryParse('${e.key}') != null)
                  int.parse('${e.key}'): '${e.value}',
            };
          }
        });
      }
    } catch (_) {
      // A corrupt cache just re-resolves on demand.
    }
  }

  Future<void> _schedulePersist() {
    _persistDirty = true;
    final last = _lastPersistAt;
    if (last != null &&
        DateTime.now().difference(last) < const Duration(seconds: 2)) {
      _persistTimer ??= Timer(const Duration(seconds: 2), () {
        _persistTimer = null;
        if (_persistDirty) _persistCache();
      });
      return Future.value();
    }
    return _persistCache();
  }

  Future<void> _persistCache() async {
    _persistDirty = false;
    _lastPersistAt = DateTime.now();
    while (_cache.length > _maxCacheEntries) {
      _cache.remove(_cache.keys.first);
    }
    try {
      await GStorage.putSetting(
        SettingsKeys.videoTmdbEpisodeNamesCacheJson,
        jsonEncode({
          for (final e in _cache.entries)
            e.key: {for (final n in e.value.entries) '${n.key}': n.value},
        }),
      );
    } catch (_) {
      // Persistence is best-effort.
    }
  }

  /// Episode names by episode number for a series item;
  /// empty when there is no key, the item is not a
  /// series, or TMDB has no confident match. [episodeCount]
  /// hints which season to pick when the title declares
  /// none and TMDB lists several.
  Future<Map<int, String>> forItem(MediaItem item, {int? episodeCount}) {
    if (item.mediaType != MediaType.series) return Future.value(const {});
    if (cmsItemIsLive(item)) return Future.value(const {});
    var hasKey = false;
    try {
      hasKey = TmdbEpisodeService.hasKey;
    } catch (_) {}
    if (!hasKey) return Future.value(const {});
    _loadCache();
    final key = _key(item);
    final hit = _cache[key];
    if (hit != null) return Future.value(hit);
    return _inFlight.putIfAbsent(key, () => _resolve(key, item, episodeCount));
  }

  Future<Map<int, String>> _resolve(
    String key,
    MediaItem item,
    int? episodeCount,
  ) async {
    try {
      final dio = DioFactory.apiDio;
      final apiKey = TmdbEpisodeService.effectiveKey;
      final overseas = tmdbOverseasMode();

      Future<dynamic> get(String path, [Map<String, dynamic>? query]) async {
        final response = await dio.get(
          '${TmdbEnrichService._apiBase}$path',
          queryParameters: {
            'api_key': apiKey,
            if (!overseas) 'language': 'zh-CN',
            ...?query,
          },
        );
        return response.data;
      }

      final search = await get('/search/tv', {
        'query': cmsBaseTitle(item.title),
      });
      final results = (search is Map ? search['results'] : null) as List?;
      if (results == null || results.isEmpty) {
        return _remember(key, const {});
      }
      final id = pickTmdbWorkId(
        results,
        title: item.title,
        year: item.year,
        isSeries: true,
      );
      if (id == null) return _remember(key, const {});

      final detail = await get('/tv/$id');
      final seasonList = (detail is Map ? detail['seasons'] : null) as List?;
      final seasons = <({int number, int episodes})>[
        if (seasonList != null)
          for (final s in seasonList)
            if (s is Map && ((s['season_number'] as num?)?.toInt() ?? 0) > 0)
              (
                number: (s['season_number'] as num).toInt(),
                episodes: (s['episode_count'] as num?)?.toInt() ?? 0,
              ),
      ];
      if (seasons.isEmpty) return _remember(key, const {});
      var season = tmdbSeasonNumberFromTitle(item.title);
      if (season == null || !seasons.any((s) => s.number == season)) {
        if (seasons.length == 1) {
          season = seasons.single.number;
        } else if (episodeCount != null) {
          seasons.sort(
            (a, b) => (a.episodes - episodeCount).abs().compareTo(
              (b.episodes - episodeCount).abs(),
            ),
          );
          season = seasons.first.number;
        } else {
          season = 1;
        }
      }
      final seasonData = await get('/tv/$id/season/$season');
      return _remember(key, parseTmdbSeasonEpisodeNames(seasonData));
    } catch (_) {
      return const {}; // failures stay uncached and retry later
    } finally {
      _inFlight.remove(key);
    }
  }

  Map<int, String> _remember(String key, Map<int, String> names) {
    _cache[key] = names;
    unawaited(_schedulePersist());
    return names;
  }
}

class TmdbEnrichService {
  TmdbEnrichService._();
  static final TmdbEnrichService instance = TmdbEnrichService._();

  static const String _apiBase = 'https://api.themoviedb.org/3';
  static const _maxCacheEntries = 300;

  /// normalizedTitle|year|kind → {'at': ms, 'data': json}
  /// or {'at': ms} alone for a confirmed no-match.
  final Map<String, dynamic> _cache = {};
  bool _cacheLoaded = false;
  DateTime? _lastPersistAt;
  Timer? _persistTimer;
  bool _persistDirty = false;

  // Batch 242/243: the v3 prefix orphans enrichments
  // cached before the zh-first reviews switch; the mode
  // segment keeps 国内 and 海外 enrichments apart (a
  // poster's language differs between the two).
  String _key(MediaItem item) =>
      'v4|${tmdbOverseasMode() ? 'intl' : 'cn'}|'
      '${normalizeTmdbTitle(item.title)}|${item.year ?? ''}|'
      '${item.mediaType == MediaType.series ? 'tv' : 'movie'}';

  void _loadCache() {
    if (_cacheLoaded) return;
    _cacheLoaded = true;
    try {
      final raw = GStorage.getSetting(SettingsKeys.videoTmdbEnrichCacheJson);
      if (raw.trim().isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        decoded.forEach((k, v) => _cache['$k'] = v);
      }
    } catch (_) {
      // A corrupt cache just re-resolves on demand.
    }
  }

  Future<void> _schedulePersist() {
    _persistDirty = true;
    final last = _lastPersistAt;
    if (last != null &&
        DateTime.now().difference(last) < const Duration(seconds: 2)) {
      _persistTimer ??= Timer(const Duration(seconds: 2), () {
        _persistTimer = null;
        if (_persistDirty) _persistCache();
      });
      return Future.value();
    }
    return _persistCache();
  }

  Future<void> _persistCache() async {
    _persistDirty = false;
    _lastPersistAt = DateTime.now();
    while (_cache.length > _maxCacheEntries) {
      _cache.remove(_cache.keys.first);
    }
    await GStorage.putSetting(
      SettingsKeys.videoTmdbEnrichCacheJson,
      jsonEncode(_cache),
    );
  }

  bool _fresh(dynamic entry) {
    if (entry is! Map) return false;
    final at = (entry['at'] as num?)?.toInt() ?? 0;
    if (at <= 0) return false;
    final age = DateTime.now().millisecondsSinceEpoch - at;
    return age >= 0 && age < const Duration(days: 7).inMilliseconds;
  }

  /// Batch 230: TMDB works matching [query] for the
  /// search page's TMDB mode. Empty without a key or on
  /// any failure — the caller falls back to source search.
  Future<List<TmdbWork>> searchWorks(String query) async {
    if (!TmdbEpisodeService.hasKey) return const [];
    try {
      final response = await DioFactory.apiDio.get(
        '$_apiBase/search/multi',
        queryParameters: {
          'api_key': TmdbEpisodeService.effectiveKey,
          if (!tmdbOverseasMode()) 'language': 'zh-CN',
          'query': query,
        },
      );
      return parseTmdbSearchResults(response.data);
    } catch (_) {
      return const [];
    }
  }

  /// The enrichment for [item], or null when there is no
  /// key, no confident match, or anything fails.
  Future<TmdbEnrichment?> forItem(MediaItem item) async {
    if (cmsItemIsLive(item)) return null;
    if (!TmdbEpisodeService.hasKey) return null;
    _loadCache();
    final key = _key(item);
    final cached = _cache[key];
    if (_fresh(cached)) {
      final data = (cached as Map)['data'];
      return data == null ? null : TmdbEnrichment.fromJson(data);
    }
    final fetched = await _fetch(item);
    if (fetched == null) return null; // failures stay uncached
    _cache[key] = {
      'at': DateTime.now().millisecondsSinceEpoch,
      if (!fetched.isEmpty) 'data': fetched.toJson(),
    };
    await _schedulePersist();
    return fetched.isEmpty ? null : fetched;
  }

  Future<TmdbEnrichment?> _fetch(MediaItem item) async {
    try {
      final dio = DioFactory.apiDio;
      final key = TmdbEpisodeService.effectiveKey;
      final isSeries = item.mediaType == MediaType.series;
      final kind = isSeries ? 'tv' : 'movie';

      // Batch 243: 海外 mode sends no language at all —
      // every call below then rides TMDB's default.
      final overseas = tmdbOverseasMode();

      Future<dynamic> get(
        String path, {
        Map<String, dynamic>? query,
        bool zh = true,
      }) async {
        final response = await dio.get(
          '$_apiBase$path',
          queryParameters: {
            'api_key': key,
            if (zh && !overseas) 'language': 'zh-CN',
            ...?query,
          },
        );
        return response.data;
      }

      final search = await get(
        '/search/$kind',
        query: {'query': cmsBaseTitle(item.title)},
      );
      final results = (search is Map ? search['results'] : null) as List?;
      if (results == null || results.isEmpty) return const TmdbEnrichment();
      final id = pickTmdbWorkId(
        results,
        title: item.title,
        year: item.year,
        isSeries: isSeries,
      );
      if (id == null) return const TmdbEnrichment();

      // Batch 248: detail, reviews and keywords all hang
      // off the id alone — they used to queue serially
      // (three round trips end to end); now they fly
      // together and the chain costs one trip past the
      // search. A detail failure still fails the fetch,
      // exactly as before (Future.wait rethrows it).
      final trio = await Future.wait<dynamic>([
        get('/$kind/$id', query: {'append_to_response': 'credits'}),
        () async {
          // Batch 242: reviews prefer zh-CN like the rest
          // of the page, falling back to the default
          // language only when Chinese has none.
          // Batch 243: 海外 mode keeps the single default
          // call — there is no Chinese layer to prefer.
          if (overseas) {
            try {
              return parseTmdbReviews(
                await get('/$kind/$id/reviews', zh: false),
              );
            } catch (_) {
              // Reviews are the most optional part of all.
              return const <TmdbReview>[];
            }
          }
          return tmdbReviewsPreferZh((zh) => get('/$kind/$id/reviews', zh: zh));
        }(),
        () async {
          // Batch 246: keywords ride their own endpoint;
          // a failure just leaves the tag tier to others.
          try {
            return parseTmdbKeywords(
              await get('/$kind/$id/keywords'),
              isSeries: isSeries,
            );
          } catch (_) {
            return const <String>[];
          }
        }(),
      ]);
      final detail = trio[0];
      final reviews = trio[1] as List<TmdbReview>;
      final keywords = trio[2] as List<String>;
      return parseTmdbDetail(
        detail,
        reviews: reviews,
        keywords: keywords,
        tmdbId: id,
        isSeries: isSeries,
      );
    } catch (_) {
      return null;
    }
  }
}
