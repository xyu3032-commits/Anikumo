import 'package:anikumo/modules/danmaku/danmaku_episode_response.dart';
import 'package:anikumo/modules/danmaku/danmaku_search_response.dart';
import 'package:anikumo/services/danmaku/danmu_token.dart';
import 'package:anikumo/services/storage/storage.dart';
import 'package:anikumo/services/tmdb/tmdb_episodes.dart';

/// Batch 163: the app's own danmaku service (a self-hosted
/// instance speaking the usual v2 search/bangumi/comment
/// protocol). It is a silent fallback: active only when
/// the build carries its token AND the user has not
/// configured their own danmaku credentials — user
/// configuration always wins.
///
/// There is deliberately no setting, no label and no UI
/// for it anywhere in the app.
class BuiltinDanmu {
  BuiltinDanmu._();

  static const String _host = 'http://node-1.consolex1.com:10200';
  /// The service base URL, present only when the build
  /// carries its token (injected at packaging time,
  /// never in source).
  static List<String> get baseUrls => [
        if (builtinDanmuToken.isNotEmpty) '$_host/$builtinDanmuToken',
      ];

  /// Available = the user's switch is on and at least one
  /// line is configured. The line check runs first so the
  /// storage read is skipped in token-less builds.
  static bool get available =>
      baseUrls.isNotEmpty &&
      GStorage.getSetting<bool>(SettingsKeys.danmakuBuiltinEnabled);

  // Bracket pairs seen in listing titles, written as
  // unicode escapes so the pattern survives any tooling:
  // 【 】 [ ] （ ） ( )
  static final RegExp _bracketed =
      RegExp('[\\u3010\\[\\uFF08(][^\\u3011\\]\\uFF09)]*[\\u3011\\]\\uFF09)]');

  /// Title comparison key: drops the service's decorations
  /// (a trailing "from <source>", bracketed tags and
  /// years) and all whitespace, so an item title and the
  /// service's listing title can be compared directly.
  static String normalizeTitle(String title) {
    var out = title.trim();
    out = out.replaceAll(RegExp(r'from\s+\S+$', caseSensitive: false), '');
    out = out.replaceAll(_bracketed, '');
    out = out.replaceAll(RegExp(r'\s+'), '');
    return out.toLowerCase();
  }

  /// The franchise part of a normalized title: the stated
  /// season marker removed.
  static String _franchiseOf(String normalized) {
    return normalized
        .replaceAll(
          RegExp(r'第[0-9一二三四五六七八九十]+[季期]'),
          '',
        )
        .replaceAll(RegExp(r'season[0-9]+'), '')
        .replaceAll(RegExp(r's[0-9]+$'), '');
  }

  /// Picks which search result serves [title]: same
  /// franchise AND same stated season (an unstated season
  /// counts as season 1, so a plain first-season title
  /// never lands on a later season's entry); then an exact
  /// normalized-title match; then the service's own
  /// ranking (its first result). 0 when there is nothing.
  static int pickAnimeId(List<DanmakuSearchAnime> animes, String title) {
    final strict = pickAnimeIdStrict(animes, title);
    if (strict != 0) return strict;
    return animes.isEmpty ? 0 : animes.first.animeId;
  }

  /// Only confident picks: same franchise + same season, or
  /// an exact normalized-title match. 0 when the pool holds
  /// no such candidate — the caller may widen the search
  /// before settling for [pickAnimeId]'s first-hit fallback
  /// (a wrong-season pick pours another season's comments
  /// over this episode, so it is the last resort, not the
  /// default).
  static int pickAnimeIdStrict(List<DanmakuSearchAnime> animes, String title) {
    if (animes.isEmpty) return 0;
    final want = normalizeTitle(title);
    if (want.isNotEmpty) {
      final wantSeason = statedSeasonNumber(title) ?? 1;
      final wantFranchise = _franchiseOf(want);
      for (final anime in animes) {
        final season = statedSeasonNumber(anime.animeTitle) ?? 1;
        if (season == wantSeason &&
            _franchiseOf(normalizeTitle(anime.animeTitle)) == wantFranchise) {
          return anime.animeId;
        }
      }
      for (final anime in animes) {
        if (normalizeTitle(anime.animeTitle) == want) return anime.animeId;
      }
    }
    return 0;
  }

  /// The widened-search query for when the full title found
  /// no confident pick: the service's aggregation ranks
  /// recent seasons first and can cut the wanted season
  /// from the full-title results entirely, while a short
  /// prefix query returns the whole franchise. First four
  /// characters of the normalized title; '' when the title
  /// is too short to shorten.
  static String shortQueryOf(String title) {
    final runes = normalizeTitle(title).runes.toList();
    if (runes.length < 5) return '';
    return String.fromCharCodes(runes.take(4));
  }

  /// The episodeId for 1-based episode [number]: parsed
  /// from the episode titles when possible, else the list
  /// position — the service returns episodes in order.
  /// 0 when out of range.
  static int episodeIdForNumber(List<DanmakuEpisode> episodes, int number) {
    if (number < 1) return 0;
    final marker = RegExp(r'第\s*(\d+)\s*集');
    for (final episode in episodes) {
      final match = marker.firstMatch(episode.episodeTitle);
      if (match != null && int.tryParse(match.group(1)!) == number) {
        return episode.episodeId;
      }
    }
    if (number <= episodes.length) return episodes[number - 1].episodeId;
    return 0;
  }
}
