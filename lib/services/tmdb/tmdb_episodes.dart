import 'dart:convert';

import 'package:anikumo/modules/bangumi/bangumi_item.dart';
import 'package:anikumo/request/core/dio_factory.dart';
import 'package:anikumo/services/storage/storage.dart';
import 'package:anikumo/services/tmdb/tmdb_key.dart';

/// Batch 129: per-episode stills and metadata from TMDB —
/// the data the Bangumi API cannot provide (its EpisodeInfo
/// has no image/duration/air-date fields), used by the
/// episode quick picker (batch 127).
///
/// Bring-your-own key: the user pastes their own free TMDB
/// API key (v3) in 设置 → 剧集图片. With no key the service
/// resolves to an empty map and the picker keeps using the
/// series cover, exactly as before. Every failure is silent
/// for the same reason — stills are decoration, never a
/// blocker.
class TmdbEpisodeStill {
  const TmdbEpisodeStill({
    required this.imageUrl,
    required this.name,
    required this.airDate,
    required this.runtimeMinutes,
  });

  /// '' when TMDB has no still for this episode.
  final String imageUrl;
  final String name;
  final String airDate;
  final int runtimeMinutes;

  Map<String, dynamic> toJson() => {
        'img': imageUrl,
        'name': name,
        'air': airDate,
        'run': runtimeMinutes,
      };

  static TmdbEpisodeStill fromJson(Map<String, dynamic> json) {
    return TmdbEpisodeStill(
      imageUrl: (json['img'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      airDate: (json['air'] as String?) ?? '',
      runtimeMinutes: (json['run'] as num?)?.toInt() ?? 0,
    );
  }
}

/// TMDB image CDN prefix for episode stills (w500 ≈ 500px
/// wide, plenty for a picker card).
const String tmdbStillBase = 'https://image.tmdb.org/t/p/w500';

/// Parses a TMDB season payload into episode-number →
/// still. Pure, for tests.
Map<int, TmdbEpisodeStill> parseTmdbSeasonEpisodes(
  Map<String, dynamic> json,
) {
  final out = <int, TmdbEpisodeStill>{};
  final episodes = json['episodes'];
  if (episodes is List) {
    for (final entry in episodes) {
      if (entry is! Map) continue;
      final number = (entry['episode_number'] as num?)?.toInt() ?? 0;
      if (number < 1) continue;
      final stillPath = (entry['still_path'] as String?) ?? '';
      out[number] = TmdbEpisodeStill(
        imageUrl: stillPath.isEmpty ? '' : '$tmdbStillBase$stillPath',
        name: (entry['name'] as String?) ?? '',
        airDate: (entry['air_date'] as String?) ?? '',
        runtimeMinutes: (entry['runtime'] as num?)?.toInt() ?? 0,
      );
    }
  }
  return out;
}

/// Scores TMDB TV search hits for a Bangumi subject: an
/// exact title match (either name) dominates, then premiere
/// year closeness to the Bangumi air year. Pure, for tests.
int? pickTmdbShowId(
  List<dynamic> results, {
  required String name,
  required String nameCn,
  required int? year,
}) {
  Map? best;
  var bestScore = -1;
  for (final result in results) {
    if (result is! Map) continue;
    var score = 0;
    for (final title in [result['name'], result['original_name']]) {
      if (title is String && (title == nameCn || title == name)) {
        score += 100;
      }
    }
    final date = (result['first_air_date'] as String?) ?? '';
    if (year != null && date.length >= 4) {
      final hitYear = int.tryParse(date.substring(0, 4));
      if (hitYear != null) {
        if (hitYear == year) {
          score += 40;
        } else if ((hitYear - year).abs() <= 1) {
          score += 15;
        }
      }
    }
    if (score > bestScore) {
      bestScore = score;
      best = result;
    }
  }
  return (best?['id'] as num?)?.toInt();
}

/// A season number stated in a title. Recognised forms,
/// most explicit first: 第2期 / 第3季 / 第2シーズン (Arabic
/// or Chinese numerals), "2nd Season" / "3rd season",
/// "Season 2", a standalone "S2" token, and a trailing
/// roman numeral (II / III / IV…). Null when unstated.
///
/// Batch 156: the ordinal-before-Season, シーズン, S-token
/// and roman forms were missing — Bangumi titles use them
/// a lot (Re:ゼロ's subjects are literally named "2nd
/// season" / "3rd season"). An unrecognised marker made
/// every downstream default fall back to season 1: the
/// user taps 第二季 or 第三季 in 关联 and the picker opens
/// with the FIRST season's stills (and, for combined
/// subjects, no season slicing) — "the default is not the
/// season I picked".
int? statedSeasonNumber(String text) {
  final cn = RegExp(
    r'第\s*([0-9]+|[一二三四五六七八九十])\s*(?:期|季|シーズン)',
  ).firstMatch(text);
  if (cn != null) {
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
      '十': 10,
    };
    final token = cn.group(1)!;
    return int.tryParse(token) ?? numerals[token];
  }
  final ordinal = RegExp(
    r'\b([0-9]+)(?:st|nd|rd|th)\s*Season\b',
    caseSensitive: false,
  ).firstMatch(text);
  if (ordinal != null) return int.tryParse(ordinal.group(1)!);
  final en =
      RegExp(r'Season\s*([0-9]+)', caseSensitive: false).firstMatch(text);
  if (en != null) return int.tryParse(en.group(1)!);
  final sToken =
      RegExp(r'\bS([0-9]{1,2})\b', caseSensitive: false).firstMatch(text);
  if (sToken != null) return int.tryParse(sToken.group(1)!);
  // A trailing roman numeral: "タイトル II", "Title III".
  // Anchored to the end (an optional season word may
  // follow the numeral) so a numeral inside a title is
  // never read as a season.
  final roman = RegExp(
    r'\s(IV|III|II|V|VI|VII|VIII)\s*(?:期|季|シーズン)?\s*$',
    caseSensitive: false,
  ).firstMatch(text);
  if (roman != null) {
    const romans = {
      'II': 2,
      'III': 3,
      'IV': 4,
      'V': 5,
      'VI': 6,
      'VII': 7,
      'VIII': 8,
    };
    return romans[roman.group(1)!.toUpperCase()];
  }
  return null;
}

/// Which TMDB season a Bangumi subject maps to:
/// 1. a season stated in the title wins;
/// 2. else the season whose episode count equals the
///    subject's (the picker's road length);
/// 3. else the first real season.
/// Season 0 (specials) is never chosen implicitly.
int pickTmdbSeason({
  required List<({int number, int episodeCount})> seasons,
  required String title,
  required String titleCn,
  required int episodeCount,
}) {
  final real = [for (final s in seasons) if (s.number >= 1) s];
  if (real.isEmpty) return 1;
  final stated =
      statedSeasonNumber(titleCn) ?? statedSeasonNumber(title);
  if (stated != null && real.any((s) => s.number == stated)) {
    return stated;
  }
  if (episodeCount > 0) {
    for (final s in real) {
      if (s.episodeCount == episodeCount) return s.number;
    }
  }
  return real.first.number;
}

/// Batch 151: which season's stills a subject may show
/// BY NUMBER, or null when numbering cannot be trusted.
/// A season STATED in the title is a hard boundary: when
/// TMDB's entry for the show has no such season — some
/// entries file every cour under one long season — the
/// picker must never borrow another season's stills by
/// number. The borrowed map did three kinds of damage in
/// the user's v39 test （药屋少女的呢喃 第三季， whose TMDB
/// entry is a single 60-episode season): season 2 stills
/// and air dates filled the season 3 grid, the grid count
/// inflated to the whole series' 60, and tapping an
/// inflated number played the wrong episode from the
/// source. A null here does not mean "no stills at all"
/// since batch 152: the service then tries aligning by
/// air date ([alignStillsByAirDate]). Unstated titles keep
/// the batch-129/150 behaviour via [pickTmdbSeason].
int? seasonForStills({
  required List<({int number, int episodeCount})> seasons,
  required String title,
  required String titleCn,
  required int episodeCount,
}) {
  final stated = statedSeasonNumber(titleCn) ?? statedSeasonNumber(title);
  if (stated != null) {
    return seasons.any((s) => s.number == stated && s.number >= 1)
        ? stated
        : null;
  }
  return pickTmdbSeason(
    seasons: seasons,
    title: title,
    titleCn: titleCn,
    episodeCount: episodeCount,
  );
}

/// Batch 152: aligns TMDB stills to a subject's episodes
/// by AIR DATE when the numbering cannot be trusted (the
/// batch-151 null case: the title states a season TMDB's
/// entry does not have, e.g. every cour filed under one
/// long season). [subjectEpisodeDates] maps the subject's
/// own episode numbers to their Bangumi air dates;
/// [tmdbEpisodes] is every candidate episode of the show,
/// in series order. An episode only gets a still when its
/// date group lines up exactly: the dates are equal AND
/// both sides have the same number of episodes on that
/// date (a double-episode premiere zips in order; a
/// mismatch — one side listing a special the other lacks —
/// leaves the whole date unaligned rather than guessing).
/// Episodes without dates never align. Pure, for tests.
Map<int, TmdbEpisodeStill> alignStillsByAirDate({
  required Map<int, String> subjectEpisodeDates,
  required List<TmdbEpisodeStill> tmdbEpisodes,
}) {
  final tmdbByDate = <String, List<TmdbEpisodeStill>>{};
  for (final episode in tmdbEpisodes) {
    final date = episode.airDate.trim();
    if (date.isEmpty) continue;
    (tmdbByDate[date] ??= []).add(episode);
  }
  final subjectByDate = <String, List<int>>{};
  subjectEpisodeDates.forEach((episode, rawDate) {
    final date = rawDate.trim();
    if (date.isEmpty) return;
    (subjectByDate[date] ??= []).add(episode);
  });
  final out = <int, TmdbEpisodeStill>{};
  final usedTmdb = <TmdbEpisodeStill>{};
  subjectByDate.forEach((date, episodes) {
    final candidates = tmdbByDate[date];
    if (candidates == null || candidates.length != episodes.length) {
      return;
    }
    final sorted = [...episodes]..sort();
    for (var i = 0; i < sorted.length; i++) {
      out[sorted[i]] = candidates[i];
      usedTmdb.add(candidates[i]);
    }
  });
  // Batch 155: second pass with a one-day tolerance. The
  // two databases do not always agree on an episode's air
  // date — a late-night broadcast lands on the next
  // calendar day in one of them — and the strict pass
  // left those episodes with no still at all (the user's
  // "some episodes have no image"). The guards stay as
  // strict as the exact pass allows: only episodes still
  // unmatched on BOTH sides take part, a shifted date
  // group must match the subject group in count exactly,
  // and when the groups on BOTH neighbouring days could
  // fit, the date is left unaligned rather than guessed.
  final unmatchedByDate = <String, List<int>>{};
  subjectByDate.forEach((date, episodes) {
    final missing = [
      for (final episode in episodes)
        if (!out.containsKey(episode)) episode,
    ];
    if (missing.isNotEmpty) unmatchedByDate[date] = missing;
  });
  if (unmatchedByDate.isNotEmpty) {
    final unusedByDate = <String, List<TmdbEpisodeStill>>{};
    tmdbByDate.forEach((date, episodes) {
      final unused = [
        for (final episode in episodes)
          if (!usedTmdb.contains(episode)) episode,
      ];
      if (unused.isNotEmpty) unusedByDate[date] = unused;
    });
    final dates = unmatchedByDate.keys.toList()..sort();
    for (final date in dates) {
      final episodes = unmatchedByDate[date]!;
      final day = DateTime.tryParse(date);
      if (day == null) continue;
      List<TmdbEpisodeStill>? fit;
      String? fitKey;
      var ambiguous = false;
      for (final shift in const [-1, 1]) {
        final neighbour =
            _tmdbDateKey(day.add(Duration(days: shift)));
        final pool = unusedByDate[neighbour];
        if (pool == null || pool.length != episodes.length) continue;
        if (fit != null) {
          ambiguous = true;
          break;
        }
        fit = pool;
        fitKey = neighbour;
      }
      if (ambiguous || fit == null) continue;
      final sorted = [...episodes]..sort();
      for (var i = 0; i < sorted.length; i++) {
        out[sorted[i]] = fit[i];
        usedTmdb.add(fit[i]);
      }
      unusedByDate.remove(fitKey);
    }
  }
  return out;
}

/// Formats a date the way TMDB/Bangumi write air dates
/// ('yyyy-MM-dd'), for batch 155's shifted-date lookups.
String _tmdbDateKey(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-'
    '${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';

/// Batch 155: whether a TMDB stills cache entry may
/// answer without a refetch: current format (v5 — see
/// _cacheEntry for why v4 is not honoured) and written
/// within the last week. Pure, for tests.
bool tmdbCacheEntryIsFresh({
  required int version,
  required int writtenAtMs,
  required int nowMs,
}) {
  if (version != 5 || writtenAtMs <= 0) return false;
  final age = nowMs - writtenAtMs;
  return age >= 0 && age < const Duration(days: 7).inMilliseconds;
}

class TmdbEpisodeService {
  TmdbEpisodeService._();

  static const String _apiBase = 'https://api.themoviedb.org/3';

  static final Map<int, Map<int, TmdbEpisodeStill>> _memory = {};

  /// Batch 130: the key actually used — the user's own
  /// (设置 → 剧集图片) when set, else the build's built-in
  /// key (obfuscated; empty in the open-source tree).
  static String get effectiveKey {
    final user = GStorage.getSetting(SettingsKeys.tmdbApiKey).trim();
    return user.isNotEmpty ? user : builtinTmdbKey;
  }

  static bool get hasKey => effectiveKey.isNotEmpty;

  /// Resolves the stills for [item]'s own season (seasons
  /// are never merged — batch 150), or an empty map when no
  /// key is set, nothing matches, or anything fails along
  /// the way. [episodeDates] (the subject's episode numbers
  /// → Bangumi air dates) feeds batch 152's air-date
  /// alignment when TMDB's season layout has no season to
  /// match by number.
  static Future<Map<int, TmdbEpisodeStill>> stillsFor(
    BangumiItem item, {
    required int episodeCount,
    Map<int, String> episodeDates = const {},
  }) async {
    if (!hasKey) return const {};
    final memoized = _memory[item.id];
    if (memoized != null) return memoized;
    // Batch 155: cache policy — a fresh entry answers at
    // once; a stale one (over a week old, e.g. written
    // before TMDB had stills for the newest episodes of an
    // airing show) only serves as the fallback for when
    // the refetch comes back empty or fails.
    final entry = _cacheEntry(item.id);
    if (entry != null && entry.fresh) {
      _memory[item.id] = entry.stills;
      return entry.stills;
    }
    final fetched = await _fetchStills(
      item,
      episodeCount: episodeCount,
      episodeDates: episodeDates,
    );
    if (fetched.isNotEmpty) {
      _memory[item.id] = fetched;
      _writeCache(item.id, fetched);
      return fetched;
    }
    if (entry != null) {
      _memory[item.id] = entry.stills;
      return entry.stills;
    }
    return const {};
  }

  /// One network pass for [item]'s stills (batch 129's
  /// fetch, extracted by batch 155): the picked season by
  /// number, or air-date alignment when numbering cannot
  /// be trusted. Empty on any failure — the caller owns
  /// the cache policy.
  static Future<Map<int, TmdbEpisodeStill>> _fetchStills(
    BangumiItem item, {
    required int episodeCount,
    Map<int, String> episodeDates = const {},
  }) async {
    try {
      final dio = DioFactory.apiDio;
      final key = effectiveKey;

      Future<dynamic> get(String path, [Map<String, dynamic>? query]) async {
        final response = await dio.get(
          '$_apiBase$path',
          queryParameters: {
            'api_key': key,
            'language': 'zh-CN',
            ...?query,
          },
        );
        return response.data;
      }

      final year = item.airDate.length >= 4
          ? int.tryParse(item.airDate.substring(0, 4))
          : null;
      int? showId;
      for (final query in [item.nameCn, item.name]) {
        if (query.trim().isEmpty) continue;
        final data = await get('/search/tv', {'query': query});
        final results = (data is Map ? data['results'] : null) as List?;
        if (results == null || results.isEmpty) continue;
        showId = pickTmdbShowId(
          results,
          name: item.name,
          nameCn: item.nameCn,
          year: year,
        );
        if (showId != null) break;
      }
      if (showId == null) return const {};

      final detail = await get('/tv/$showId');
      final seasonList = (detail is Map ? detail['seasons'] : null) as List?;
      final seasons = <({int number, int episodeCount})>[
        if (seasonList != null)
          for (final s in seasonList)
            if (s is Map)
              (
                number: (s['season_number'] as num?)?.toInt() ?? 0,
                episodeCount: (s['episode_count'] as num?)?.toInt() ?? 0,
              ),
      ];
      // Batch 150 (user call, reverting batch 148): seasons
      // stay SEPARATE — only the one picked season is
      // fetched, exactly as in batch 129. The merge put
      // season 1/2 stills into later seasons' pickers,
      // which the user explicitly does not want ("不要第三
      // 季看到 1、2 季的内容"); each Bangumi subject is one
      // season, and its picker now only ever shows its own.
      // Batch 151: a title-stated season missing from
      // TMDB's entry is never borrowed BY NUMBER (see
      // seasonForStills). Batch 152: instead of giving up
      // on stills entirely, fall back to air-date
      // alignment — every season of the show is fetched
      // as candidates and only exact date matches are
      // attached to this subject's episodes, so a merged
      // TMDB season can still yield THIS season's stills
      // and nothing else's. Without subject air dates, or
      // when the candidate set is implausibly large, the
      // picker keeps the batch-151 cover fallback.
      final season = seasonForStills(
        seasons: seasons,
        title: item.name,
        titleCn: item.nameCn,
        episodeCount: episodeCount,
      );
      if (season == null) {
        if (episodeDates.isEmpty) return const {};
        final realSeasons = [
          for (final s in seasons)
            if (s.number >= 1) s.number,
        ]..sort();
        if (realSeasons.isEmpty || realSeasons.length > 12) {
          return const {};
        }
        final candidates = <TmdbEpisodeStill>[];
        for (final number in realSeasons) {
          final data = await get('/tv/$showId/season/$number');
          if (data is! Map<String, dynamic>) return const {};
          final parsed = parseTmdbSeasonEpisodes(data);
          final numbers = parsed.keys.toList()..sort();
          for (final n in numbers) {
            candidates.add(parsed[n]!);
          }
          if (candidates.length > 400) return const {};
        }
        final aligned = alignStillsByAirDate(
          subjectEpisodeDates: episodeDates,
          tmdbEpisodes: candidates,
        );
        if (aligned.isEmpty) return const {};
        return aligned;
      }
      final seasonData = await get('/tv/$showId/season/$season');
      if (seasonData is! Map<String, dynamic>) return const {};
      final stills = parseTmdbSeasonEpisodes(seasonData);
      if (stills.isEmpty) return const {};
      return stills;
    } catch (_) {
      // Stills are decoration; any failure degrades to the
      // series cover in the picker.
      return const {};
    }
  }

  static void clearCache() {
    _memory.clear();
    GStorage.putSetting(SettingsKeys.tmdbMatchCache, '');
  }

  /// Reads one cache entry, or null when there is none
  /// worth having. Cache format versions: v1 = batch 129
  /// single season, v2 = batch 148's merged-seasons format
  /// (reverted by batch 150 the same day), v3/v4 = the
  /// batch-150/151 era. Only v5 is honoured: v4's
  /// date-aligned entries were keyed by the franchise
  /// numbering batch 153 replaced with per-season local
  /// numbers — read back, every episode of a combined
  /// subject missed its lookup and showed no still (part
  /// of the user's "some episodes have no image"). A v5
  /// entry also carries its write time; entries over a
  /// week old come back as stale (see [stillsFor]).
  static ({Map<int, TmdbEpisodeStill> stills, bool fresh})? _cacheEntry(
    int bangumiId,
  ) {
    final raw = GStorage.getSetting(SettingsKeys.tmdbMatchCache);
    if (raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final entry = decoded['$bangumiId'];
      if (entry is! Map) return null;
      final version = (entry['v'] as num?)?.toInt() ?? 0;
      if (version != 5) return null;
      final stills = entry['stills'];
      if (stills is! Map) return null;
      return (
        stills: {
          for (final e in stills.entries)
            if (int.tryParse('${e.key}') != null && e.value is Map)
              int.parse('${e.key}'): TmdbEpisodeStill.fromJson(
                (e.value as Map).cast<String, dynamic>(),
              ),
        },
        fresh: tmdbCacheEntryIsFresh(
          version: version,
          writtenAtMs: (entry['t'] as num?)?.toInt() ?? 0,
          nowMs: DateTime.now().millisecondsSinceEpoch,
        ),
      );
    } catch (_) {
      return null;
    }
  }

  static void _writeCache(int bangumiId, Map<int, TmdbEpisodeStill> stills) {
    try {
      var all = <String, dynamic>{};
      final raw = GStorage.getSetting(SettingsKeys.tmdbMatchCache);
      if (raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) all = decoded.cast<String, dynamic>();
      }
      all['$bangumiId'] = {
        'v': 5,
        't': DateTime.now().millisecondsSinceEpoch,
        'stills': {
          for (final e in stills.entries) '${e.key}': e.value.toJson(),
        },
      };
      GStorage.putSetting(SettingsKeys.tmdbMatchCache, jsonEncode(all));
    } catch (_) {
      // A failed cache write only costs a refetch next time.
    }
  }
}

/// Batch 160: stable-order [items] so the entries whose
/// title states [statedSeason] lead. Plugin sites list
/// newest first, so without this the source sheet's
/// auto-previewed top result for a second-season subject
/// was its third season. Ranking: titles stating the
/// wanted season first; then season-less titles (for a
/// first-season subject they count as matches too — the
/// base entry usually carries no marker); then titles
/// stating a different season. Original order is kept
/// inside each rank. A null [statedSeason] (the subject
/// states no season) leaves the order untouched.
List<T> orderByStatedSeason<T>(
  List<T> items, {
  required int? statedSeason,
  required String Function(T item) titleOf,
}) {
  if (statedSeason == null || items.length < 2) return items;
  int rank(T item) {
    final season = statedSeasonNumber(titleOf(item));
    if (season == statedSeason) return 0;
    if (season == null) return statedSeason == 1 ? 0 : 1;
    return 2;
  }

  final decorated = [
    for (var i = 0; i < items.length; i++)
      (index: i, item: items[i], rank: rank(items[i])),
  ];
  decorated.sort((a, b) {
    final byRank = a.rank.compareTo(b.rank);
    return byRank != 0 ? byRank : a.index.compareTo(b.index);
  });
  return [for (final entry in decorated) entry.item];
}
