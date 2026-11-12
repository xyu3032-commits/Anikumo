import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:liuguang_core/liuguang_core.dart';

import 'package:anikumo/request/apis/bangumi_api.dart';
import 'package:anikumo/request/core/dio_factory.dart';
import 'package:anikumo/services/liuguang/cms_api_source.dart';
import 'package:anikumo/services/liuguang/tmdb_enrich.dart';
import 'package:anikumo/services/storage/storage.dart';

/// Batch 245: Bangumi as the film zone's second metadata
/// source. Bangumi carries live-action series and films
/// too (subject type 6, plus type 2 for animated works),
/// and the user's priority chain is: covers TMDB →
/// Bangumi → source; ratings Bangumi → TMDB → source;
/// characters Bangumi → TMDB; comments TMDB + Bangumi
/// combined. Everything here is best-effort enrichment —
/// any failure reads as "Bangumi does not have it" and
/// the next tier answers instead.

/// One character entry: the character, who plays them,
/// and a portrait when Bangumi has one.
typedef BangumiFilmCharacter = ({
  String name,
  String actor,
  String? imageUrl,
});

/// One Bangumi subject comment （吐槽）: author, text, an
/// optional 0–10 rate, and a yyyy-MM-dd date.
typedef BangumiFilmComment = ({
  String author,
  String content,
  double? rating,
  String date,
});

/// One review in the zone's combined comment stream —
/// a TMDB review or a Bangumi comment, tagged with its
/// source for display.
typedef FilmReview = ({
  String author,
  String content,
  String date,
  double? rating,
  String source,
});

/// Batch 245: the resolved Bangumi data for one work.
class BangumiFilmData {
  const BangumiFilmData({
    required this.subjectId,
    this.score = 0,
    this.votes = 0,
    this.posterUrl,
    this.characters = const [],
    this.comments = const [],
    this.posterOnly = false,
    this.summary = '',
    this.tags = const [],
  });

  final int subjectId;

  /// Bangumi rating (0–10) and its vote count; 0 when
  /// nobody has rated the subject yet.
  final double score;
  final int votes;
  final String? posterUrl;
  final List<BangumiFilmCharacter> characters;
  final List<BangumiFilmComment> comments;

  /// True when only the search row (score / poster) has
  /// been resolved — characters and comments still owe
  /// their own calls, so a full read must not treat this
  /// entry as complete.
  final bool posterOnly;

  /// Batch 246: the subject's synopsis — the film zone's
  /// first-priority overview.
  final String summary;

  /// Batch 246: the subject's top user tags by count,
  /// medium/format words and years filtered out — the
  /// first tier of the merged genre/tag chips.
  final List<String> tags;

  bool get isEmpty =>
      score <= 0 &&
      posterUrl == null &&
      characters.isEmpty &&
      comments.isEmpty;

  Map<String, dynamic> toJson() => {
    'id': subjectId,
    'score': score,
    'votes': votes,
    'poster': posterUrl,
    'posterOnly': posterOnly,
    'summary': summary,
    'tags': tags,
    'characters': [
      for (final c in characters)
        {'name': c.name, 'actor': c.actor, 'image': c.imageUrl},
    ],
    'comments': [
      for (final c in comments)
        {
          'author': c.author,
          'content': c.content,
          'rating': c.rating,
          'date': c.date,
        },
    ],
  };

  static BangumiFilmData? fromJson(dynamic json) {
    if (json is! Map) return null;
    final id = (json['id'] as num?)?.toInt() ?? 0;
    if (id <= 0) return null;
    return BangumiFilmData(
      subjectId: id,
      score: (json['score'] as num?)?.toDouble() ?? 0,
      votes: (json['votes'] as num?)?.toInt() ?? 0,
      posterUrl: (json['poster']?.toString() ?? '').isEmpty
          ? null
          : json['poster'].toString(),
      posterOnly: json['posterOnly'] == true,
      summary: json['summary']?.toString() ?? '',
      tags: [
        if (json['tags'] is List)
          for (final t in json['tags'] as List) t.toString(),
      ],
      characters: [
        if (json['characters'] is List)
          for (final row in json['characters'] as List)
            if (row is Map)
              (
                name: row['name']?.toString() ?? '',
                actor: row['actor']?.toString() ?? '',
                imageUrl: (row['image']?.toString() ?? '').isEmpty
                    ? null
                    : row['image'].toString(),
              ),
      ],
      comments: [
        if (json['comments'] is List)
          for (final row in json['comments'] as List)
            if (row is Map)
              (
                author: row['author']?.toString() ?? '',
                content: row['content']?.toString() ?? '',
                rating: (row['rating'] as num?)?.toDouble(),
                date: row['date']?.toString() ?? '',
              ),
      ],
    );
  }
}

/// Batch 245: picks the Bangumi subject for one film
/// work out of v0 search rows. Conservative, like the
/// TMDB pick: a normalized-title exact hit on name or
/// name_cn (after stripping season markers), preferring
/// a year agreement and then the expected subject type
/// (6 for live action, 2 for animated works). No exact
/// hit, no pick — a wrong subject is worse than none.
/// Pure, for tests.
int? pickBangumiFilmSubject(
  List<dynamic> rows, {
  required String title,
  int? year,
  required bool preferReal,
}) {
  final wanted = normalizeTmdbTitle(cmsBaseTitle(title));
  if (wanted.isEmpty) return null;
  ({int id, int type, int? rowYear})? best;
  var bestScore = -1;
  for (final row in rows) {
    if (row is! Map) continue;
    final id = (row['id'] as num?)?.toInt();
    if (id == null) continue;
    var hit = false;
    for (final field in ['name', 'name_cn']) {
      final candidate = normalizeTmdbTitle(
        cmsBaseTitle(row[field]?.toString() ?? ''),
      );
      if (candidate.isNotEmpty && candidate == wanted) {
        hit = true;
        break;
      }
    }
    if (!hit) continue;
    final date = row['date']?.toString() ?? '';
    final rowYear = date.length >= 4 ? int.tryParse(date.substring(0, 4)) : null;
    final type = (row['type'] as num?)?.toInt() ?? 0;
    var score = 0;
    if (year != null && rowYear != null) {
      if (rowYear == year) {
        score += 4;
      } else if ((rowYear - year).abs() == 1) {
        score += 2;
      } else {
        continue; // same title, clearly another production
      }
    }
    if (type == (preferReal ? 6 : 2)) score += 1;
    if (score > bestScore) {
      bestScore = score;
      best = (id: id, type: type, rowYear: rowYear);
    }
  }
  return best?.id;
}

/// Batch 245: characters out of a v0
/// /subjects/{id}/characters payload — main relations
/// keep their served order, capped at 12. Pure, for tests.
List<BangumiFilmCharacter> parseBangumiFilmCharacters(dynamic json) {
  if (json is! List) return const [];
  final out = <BangumiFilmCharacter>[];
  for (final row in json) {
    if (row is! Map) continue;
    final name = (row['name']?.toString() ?? '').trim();
    if (name.isEmpty) continue;
    var actor = '';
    final actors = row['actors'];
    if (actors is List && actors.isNotEmpty && actors.first is Map) {
      actor = (actors.first as Map)['name']?.toString() ?? '';
    }
    final images = row['images'];
    var image = '';
    if (images is Map) {
      image =
          (images['medium'] ?? images['large'] ?? images['small'] ?? '')
              .toString();
    }
    out.add((
      name: name,
      actor: actor.trim(),
      imageUrl: image.isEmpty ? null : image,
    ));
    if (out.length >= 12) break;
  }
  return out;
}

/// Batch 245: the zone's combined comment stream — TMDB
/// reviews and Bangumi comments merged newest-first and
/// capped. Pure, for tests.
List<FilmReview> mergeFilmReviews({
  List<TmdbReview> tmdb = const [],
  List<BangumiFilmComment> bangumi = const [],
  int cap = 20,
}) {
  final out = <FilmReview>[
    for (final r in tmdb)
      (
        author: r.author,
        content: r.content,
        date: r.date,
        rating: r.rating,
        source: 'TMDB',
      ),
    for (final c in bangumi)
      (
        author: c.author,
        content: c.content,
        date: c.date,
        rating: c.rating,
        source: 'Bangumi',
      ),
  ];
  out.sort((a, b) => b.date.compareTo(a.date));
  return out.length > cap ? out.sublist(0, cap) : out;
}

/// Batch 246: Bangumi's top tags for a subject out of a
/// search row's `tags` list — sorted by count, with the
/// noise removed: pure years, the work's own title, and
/// medium/format words (the kind tag already says those).
/// Capped at 8. Pure, for tests.
List<String> parseBangumiFilmTags(
  dynamic tagsJson, {
  required String title,
}) {
  if (tagsJson is! List) return const [];
  const mediumWords = {
    '电视剧', '电影', '动画', '综艺', '纪录片', 'TV', 'TV剧', '剧集',
    '国产剧', '日剧', '韩剧', '美剧', '英剧', '港剧', '台剧',
  };
  final ownTitle = cmsBaseTitle(title).trim();
  final rows = <({String name, int count})>[];
  for (final row in tagsJson) {
    if (row is! Map) continue;
    final name = (row['name']?.toString() ?? '').trim();
    if (name.isEmpty) continue;
    if (RegExp(r'^\d{4}$').hasMatch(name)) continue;
    if (name == ownTitle || mediumWords.contains(name)) continue;
    rows.add((name: name, count: (row['count'] as num?)?.toInt() ?? 0));
  }
  rows.sort((a, b) => b.count.compareTo(a.count));
  return [for (final r in rows.take(8)) r.name];
}

/// Batch 246: the overview a detail page shows, by the
/// user's priority — Bangumi's synopsis, then TMDB's,
/// then the source's own. Pure, for tests.
String filmDisplayOverview({
  String bangumiSummary = '',
  String tmdbOverview = '',
  String sourceOverview = '',
}) {
  if (bangumiSummary.trim().isNotEmpty) return bangumiSummary.trim();
  if (tmdbOverview.trim().isNotEmpty) return tmdbOverview.trim();
  return sourceOverview;
}

/// Batch 246: the genre/tag chips a detail page shows —
/// the three sources merged in the user's priority
/// order (Bangumi tags, TMDB genres, TMDB keywords,
/// source genres), each term translated where a table
/// covers it and deduped on its normalized form, so an
/// English term and its Chinese gloss never both show.
/// Capped at 14. Pure, for tests.
List<String> mergeFilmGenreChips({
  List<String> bangumiTags = const [],
  List<String> tmdbGenres = const [],
  List<String> tmdbKeywords = const [],
  List<String> sourceGenres = const [],
  int cap = 14,
}) {
  final seen = <String>{};
  final out = <String>[];
  void add(String raw, {required bool translate}) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return;
    // Batch 247: every term goes through the shared key
    // machinery — the display is the canonical form and
    // the dedupe key is the genre key, so 剧情 / 剧情片 /
    // 劇情 / 小说改 / 小说改编 can no longer coexist.
    final display = cmsGenreDisplay(
      translate ? tmdbDisplayTerm(trimmed) : trimmed,
    );
    final key = cmsGenreKey(display);
    if (key.isEmpty || !seen.add(key)) return;
    out.add(display);
  }

  for (final t in bangumiTags) {
    add(t, translate: false);
  }
  for (final g in tmdbGenres) {
    add(g, translate: true);
  }
  for (final k in tmdbKeywords) {
    add(k, translate: true);
  }
  for (final g in sourceGenres) {
    add(g, translate: false);
  }
  return out.length > cap ? out.sublist(0, cap) : out;
}

/// Batch 245: the score a detail header shows, by the
/// user's priority — Bangumi first, then TMDB, then the
/// source's own rating. Null when nobody has one. Pure,
/// for tests.
({double score, String source, int votes})? filmDisplayScore({
  BangumiFilmData? bangumi,
  TmdbEnrichment? tmdb,
  double sourceScore = 0,
}) {
  if (bangumi != null && bangumi.score > 0) {
    return (score: bangumi.score, source: 'Bangumi', votes: bangumi.votes);
  }
  if (tmdb != null && tmdb.score > 0) {
    return (score: tmdb.score, source: 'TMDB', votes: 0);
  }
  if (sourceScore > 0) {
    return (score: sourceScore, source: '', votes: 0);
  }
  return null;
}

class BangumiFilmService {
  BangumiFilmService._();
  static final BangumiFilmService instance = BangumiFilmService._();

  static const _ua =
      'Anikumo/1.0.3 (https://github.com/xyu3032-commits/Anikumo)';
  static const _apiBase = 'https://api.bgm.tv';
  static const _maxCacheEntries = 300;
  static const _freshFor = Duration(days: 7);

  /// normalizedTitle|year → {'at': ms, 'data': json}.
  /// Only positive resolutions live here (and in the
  /// persisted copy): a miss is remembered in [_misses]
  /// for this process only. Persisting a miss from a
  /// cover grid's completion would start a settings-box
  /// write whose completion a disposed widget-test zone
  /// can swallow, wedging the box's write queue for
  /// everything after it — and a miss is cheap to
  /// re-check next launch anyway.
  final Map<String, dynamic> _cache = {};
  final Map<String, int> _misses = {};
  bool _cacheLoaded = false;
  final Map<String, Future<BangumiFilmData?>> _inFlight = {};
  final Map<String, Future<String?>> _posterInFlight = {};
  bool _persistDirty = false;
  Future<void> _persistChain = Future.value();

  String _key(MediaItem item) =>
      '${normalizeTmdbTitle(item.title)}|${item.year ?? ''}|'
      '${item.mediaType == MediaType.series ? 'tv' : 'movie'}';

  void _loadCache() {
    if (_cacheLoaded) return;
    _cacheLoaded = true;
    try {
      final raw = GStorage.getSetting(SettingsKeys.videoBangumiFilmCacheJson);
      if (raw.trim().isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        decoded.forEach((k, v) => _cache['$k'] = v);
      }
    } catch (_) {
      // A corrupt cache just re-resolves on demand.
    }
  }

  bool _fresh(dynamic entry) {
    if (entry is! Map) return false;
    final at = (entry['at'] as num?)?.toInt() ?? 0;
    if (at <= 0) return false;
    final age = DateTime.now().millisecondsSinceEpoch - at;
    return age >= 0 && age < _freshFor.inMilliseconds;
  }

  /// Persists are chained, never timer-throttled: a card
  /// grid resolving many posters at once collapses into
  /// a couple of writes (each link writes the cache as it
  /// stands when it runs), and no timer can outlive the
  /// work that scheduled it.
  Future<void> _schedulePersist() {
    _persistDirty = true;
    _persistChain = _persistChain.then((_) async {
      if (!_persistDirty) return;
      _persistDirty = false;
      while (_cache.length > _maxCacheEntries) {
        _cache.remove(_cache.keys.first);
      }
      try {
        await GStorage.putSetting(
          SettingsKeys.videoBangumiFilmCacheJson,
          jsonEncode(_cache),
        );
      } catch (_) {
        // Persistence is best-effort.
      }
    });
    return _persistChain;
  }

  Future<void> _remember(String key, BangumiFilmData? data) async {
    if (data == null) {
      _misses[key] = DateTime.now().millisecondsSinceEpoch;
      return;
    }
    _misses.remove(key);
    _cache[key] = {
      'at': DateTime.now().millisecondsSinceEpoch,
      'data': data.toJson(),
    };
    await _schedulePersist();
  }

  bool _missFresh(String key) {
    final at = _misses[key];
    if (at == null) return false;
    final age = DateTime.now().millisecondsSinceEpoch - at;
    return age >= 0 && age < _freshFor.inMilliseconds;
  }

  BangumiFilmData? _cached(String key, {required bool full}) {
    final entry = _cache[key];
    if (!_fresh(entry)) return null;
    final data = BangumiFilmData.fromJson((entry as Map)['data']);
    if (data == null) return null;
    if (full && data.posterOnly) return null;
    return data;
  }

  /// The already-known Bangumi poster for [item] (no
  /// network), or null when unknown / unmatched.
  String? cachedPosterFor(MediaItem item) {
    if (cmsItemIsLive(item)) return null;
    _loadCache();
    return _cached(_key(item), full: false)?.posterUrl;
  }

  /// Resolves the Bangumi poster for [item] through the
  /// search row alone (no characters/comments calls);
  /// null when Bangumi has no confident subject.
  Future<String?> posterFor(MediaItem item) {
    if (cmsItemIsLive(item)) return Future.value(null);
    _loadCache();
    final key = _key(item);
    final hit = _cached(key, full: false);
    if (hit != null) return Future.value(hit.posterUrl);
    if (_missFresh(key)) return Future.value(null);
    return _posterInFlight.putIfAbsent(key, () async {
      try {
        final row = await _searchRow(item);
        if (row == null) {
          await _remember(key, null);
          return null;
        }
        final data = _dataFromRow(row, posterOnly: true);
        await _remember(key, data);
        return data.posterUrl;
      } finally {
        _posterInFlight.remove(key);
      }
    });
  }

  /// The full Bangumi data for [item] — score, poster,
  /// characters and comments — or null when Bangumi has
  /// no confident subject for it.
  Future<BangumiFilmData?> forItem(MediaItem item) {
    if (cmsItemIsLive(item)) return Future.value(null);
    _loadCache();
    final key = _key(item);
    final hit = _cached(key, full: true);
    if (hit != null) return Future.value(hit.isEmpty ? null : hit);
    if (_missFresh(key)) return Future.value(null);
    return _inFlight.putIfAbsent(key, () async {
      try {
        final data = await _fetchFull(item);
        await _remember(key, data);
        return (data == null || data.isEmpty) ? null : data;
      } finally {
        _inFlight.remove(key);
      }
    });
  }

  /// One search round; returns the picked row or null.
  Future<Map<String, dynamic>?> _searchRow(MediaItem item) async {
    try {
      final preferReal = !cmsItemIsAnime(item) && !cmsItemIsManju(item);
      final response = await DioFactory.apiDio.post(
        '$_apiBase/v0/search/subjects?limit=10',
        data: {
          'keyword': cmsBaseTitle(item.title),
          'sort': 'match',
          'filter': {
            'type': [6, 2],
            'nsfw': false,
          },
        },
        options: _options,
      );
      final rows = (response.data is Map ? response.data['data'] : null);
      if (rows is! List || rows.isEmpty) return null;
      final id = pickBangumiFilmSubject(
        rows,
        title: item.title,
        year: item.year,
        preferReal: preferReal,
      );
      if (id == null) return null;
      for (final row in rows) {
        if (row is Map && (row['id'] as num?)?.toInt() == id) {
          return row.cast<String, dynamic>();
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  BangumiFilmData _dataFromRow(
    Map<String, dynamic> row, {
    required bool posterOnly,
    List<BangumiFilmCharacter> characters = const [],
    List<BangumiFilmComment> comments = const [],
  }) {
    final rating = row['rating'];
    final images = row['images'];
    var poster = '';
    if (images is Map) {
      poster = (images['large'] ?? images['common'] ?? '').toString();
    }
    return BangumiFilmData(
      subjectId: (row['id'] as num?)?.toInt() ?? 0,
      score: rating is Map ? (rating['score'] as num?)?.toDouble() ?? 0 : 0,
      votes: rating is Map ? (rating['total'] as num?)?.toInt() ?? 0 : 0,
      posterUrl: poster.isEmpty ? null : poster,
      characters: characters,
      comments: comments,
      posterOnly: posterOnly,
      summary: (row['summary']?.toString() ?? '').trim(),
      tags: parseBangumiFilmTags(
        row['tags'],
        title: (row['name']?.toString() ?? ''),
      ),
    );
  }

  Future<BangumiFilmData?> _fetchFull(MediaItem item) async {
    final row = await _searchRow(item);
    if (row == null) return null;
    final id = (row['id'] as num?)?.toInt() ?? 0;
    if (id <= 0) return null;
    // Batch 248: characters and comments both hang off
    // the id alone — fetch them together instead of
    // queuing two round trips.
    final pair = await Future.wait<dynamic>([
      () async {
        try {
          final response = await DioFactory.apiDio.get(
            '$_apiBase/v0/subjects/$id/characters',
            options: _options,
          );
          return parseBangumiFilmCharacters(response.data);
        } catch (_) {
          // Characters are one tier of several.
          return const <BangumiFilmCharacter>[];
        }
      }(),
      () async {
        try {
          final response = await BangumiApi.getBangumiCommentsByID(id);
          return <BangumiFilmComment>[
            for (final entry in response.commentList)
              if (entry.comment.comment.trim().isNotEmpty)
                (
                  author: entry.user.nickname.isNotEmpty
                      ? entry.user.nickname
                      : entry.user.username,
                  content: entry.comment.comment.trim(),
                  rating: entry.comment.rate > 0
                      ? entry.comment.rate.toDouble()
                      : null,
                  date: entry.comment.updatedAt > 0
                      ? DateTime.fromMillisecondsSinceEpoch(
                          entry.comment.updatedAt * 1000,
                        ).toIso8601String().substring(0, 10)
                      : '',
                ),
          ];
        } catch (_) {
          // Comments likewise.
          return const <BangumiFilmComment>[];
        }
      }(),
    ]);
    final characters = pair[0] as List<BangumiFilmCharacter>;
    final comments = pair[1] as List<BangumiFilmComment>;
    return _dataFromRow(
      row,
      posterOnly: false,
      characters: characters,
      comments: comments,
    );
  }

  /// Bangumi's API asks clients to identify themselves;
  /// the browser-style default agent is not acceptable.
  Options get _options => Options(headers: {'User-Agent': _ua});
}
