import 'package:anikumo/modules/danmaku/danmaku_ch_convert.dart';
import 'package:anikumo/modules/danmaku/danmaku_episode_response.dart';
import 'package:anikumo/modules/danmaku/danmaku_module.dart';
import 'package:anikumo/modules/danmaku/danmaku_search_response.dart';
import 'package:anikumo/request/clients/danmaku_client.dart';
import 'package:anikumo/request/config/api_endpoints.dart';
import 'package:anikumo/services/danmaku/builtin_danmu.dart';
import 'package:anikumo/services/logging/logger.dart';
import 'package:anikumo/services/storage/storage.dart';

class DanmakuApi {
  static final DanmakuClient _client = DanmakuClient.instance;

  /// Batch 163: the built-in service silently serves
  /// danmaku when the user has not configured their own
  /// credentials. User configuration always wins.
  static bool get builtinActive =>
      !DanmakuClient.hasCredentials && BuiltinDanmu.available;

  /// Runs [call] against the built-in service's lines in
  /// order. A line that errors (network, auth, malformed
  /// body) falls through to the next; [accept] can also
  /// reject a well-formed but useless answer (an empty
  /// search result may still be filled by another line).
  /// When every line errors, the first error is rethrown;
  /// when at least one answered, the last answer wins.
  static Future<T> _builtinCall<T>(
    Future<T> Function(String baseUrl) call, {
    bool Function(T result)? accept,
  }) async {
    Object? firstError;
    T? lastResult;
    var hasResult = false;
    for (final base in BuiltinDanmu.baseUrls) {
      try {
        final result = await call(base);
        lastResult = result;
        hasResult = true;
        if (accept == null || accept(result)) return result;
      } catch (e) {
        firstError ??= e;
      }
    }
    if (hasResult) return lastResult as T;
    throw firstError ?? StateError('弹幕服务暂时不可用');
  }

  static Future<int> getDanDanBangumiIDByBgmBangumiID(int bgmBangumiID) async {
    final path = ApiEndpoints.formatUrl(
      ApiEndpoints.dandanAPIInfoByBgmBangumiId,
      [bgmBangumiID],
    );
    final endPoint = ApiEndpoints.dandanAPIDomain + path;
    final jsonData = await _client.get(endPoint);
    return DanmakuEpisodeResponse.fromJson(jsonData).bangumiId;
  }

  static Future<DanmakuEpisodeResponse> getDanDanEpisodesByDanDanBangumiID(
    int bangumiID,
  ) async {
    if (builtinActive) {
      return _builtinCall(
        (base) async => DanmakuEpisodeResponse.fromJson(
          await _client.getPlain('$base/api/v2/bangumi/$bangumiID'),
        ),
        accept: (r) => r.episodes.isNotEmpty,
      );
    }
    final path = ApiEndpoints.dandanAPIInfo + bangumiID.toString();
    final endPoint = ApiEndpoints.dandanAPIDomain + path;
    final jsonData = await _client.get(endPoint);
    return DanmakuEpisodeResponse.fromJson(jsonData);
  }

  // v2 episode search avoids the anime search's 25-result cap.
  // Fetch full episode lists separately; search results can truncate them.
  static Future<DanmakuSearchResponse> searchAnimes(String title) async {
    if (builtinActive) {
      return _builtinCall(
        (base) async => DanmakuSearchResponse.fromJson(
          await _client.getPlain(
            '$base/api/v2/search/anime',
            queryParameters: {'keyword': title},
          ),
        ),
        accept: (r) => r.animes.isNotEmpty,
      );
    }
    final endPoint =
        ApiEndpoints.dandanAPIDomain + ApiEndpoints.dandanAPISearchEpisodes;
    final jsonData = await _client.get(
      endPoint,
      queryParameters: {'anime': title, 'v2': 'true'},
    );
    return DanmakuSearchResponse.fromJson(jsonData);
  }

  /// Automatic danmaku for one episode, from whichever
  /// provider is active. Returns the entries and the
  /// provider-side anime id they were cached under (0 when
  /// nothing could be resolved).
  ///
  /// The credential flow maps the Bangumi id across and
  /// builds the episode id by convention. The built-in
  /// service has neither mapping, so it matches by title:
  /// search, pick the same-season entry, take the
  /// episode's real id, fetch its comments.
  static Future<(List<DanmakuEntry>, int)> fetchAutoDanmaku({
    required int bgmBangumiId,
    required String title,
    required int episode,
  }) async {
    if (!builtinActive) {
      final id = await getDanDanBangumiIDByBgmBangumiID(bgmBangumiId);
      if (id == 0) return (const <DanmakuEntry>[], 0);
      return (await getDanDanmaku(id, episode), id);
    }
    if (title.trim().isEmpty) return (const <DanmakuEntry>[], 0);
    final search = await searchAnimes(title);
    var animeId = BuiltinDanmu.pickAnimeIdStrict(search.animes, title);
    if (animeId == 0) {
      // Batch 182: the full-title search can miss the
      // wanted season entirely (field-verified: a bare
      // first-season title returned only seasons 2 and 3).
      // One widened retry with a shortened query, merged
      // into the pool, before the lenient first-hit pick.
      final shortQuery = BuiltinDanmu.shortQueryOf(title);
      if (shortQuery.isNotEmpty) {
        try {
          final wider = await searchAnimes(shortQuery);
          final byId = <int, DanmakuSearchAnime>{
            for (final a in search.animes) a.animeId: a,
            for (final a in wider.animes) a.animeId: a,
          };
          animeId = BuiltinDanmu.pickAnimeId(byId.values.toList(), title);
        } catch (_) {
          animeId = BuiltinDanmu.pickAnimeId(search.animes, title);
        }
      } else {
        animeId = BuiltinDanmu.pickAnimeId(search.animes, title);
      }
    }
    if (animeId == 0) return (const <DanmakuEntry>[], 0);
    final episodes = await getDanDanEpisodesByDanDanBangumiID(animeId);
    final episodeId =
        BuiltinDanmu.episodeIdForNumber(episodes.episodes, episode);
    if (episodeId == 0) return (const <DanmakuEntry>[], animeId);
    return (await getDanDanmakuByEpisodeID(episodeId), animeId);
  }

  static Future<List<DanmakuEntry>> getDanDanmaku(
    int bangumiID,
    int episode,
  ) async {
    if (bangumiID == 0) {
      return [];
    }
    // Automatic matching relies on an undocumented episode ID convention.
    return _getComments('$bangumiID${episode.toString().padLeft(4, '0')}');
  }

  static Future<List<DanmakuEntry>> getDanDanmakuByEpisodeID(int episodeID) =>
      _getComments(episodeID.toString());

  static Future<List<DanmakuEntry>> _getComments(String episodeID) async {
    if (builtinActive) {
      return _builtinCall((base) async {
        final endPoint = '$base/api/v2/comment/$episodeID';
        AnikumoLogger().i('Danmaku: final request URL $endPoint');
        final jsonData = await _client.getPlain(endPoint);
        final List<dynamic> comments = jsonData['comments'];
        return [for (final comment in comments) DanmakuEntry.fromJson(comment)];
      });
    }
    final endPoint =
        '${ApiEndpoints.dandanAPIDomain}${ApiEndpoints.dandanAPIComment}$episodeID';
    final conversion = DanmakuChConvert.fromValue(
      GStorage.getSetting(SettingsKeys.danmakuChConvert),
    );
    AnikumoLogger().i('Danmaku: final request URL $endPoint');
    final jsonData = await _client.get(
      endPoint,
      queryParameters: {
        'withRelated': 'true',
        'chConvert': conversion.value.toString(),
      },
    );
    final List<dynamic> comments = jsonData['comments'];
    return [for (final comment in comments) DanmakuEntry.fromJson(comment)];
  }
}
