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

  /// Batch 194: two danmaku lines exist side by side.
  ///
  /// Line 0 is the official API, signed with a credential
  /// pair (the user's own when stored, otherwise the
  /// build-carried pair from batch 193). Line 1 is the
  /// built-in service (batch 163). The official line is
  /// primary; the built-in service is the backup and takes
  /// over when the official line errors or answers empty.
  ///
  /// Ids are NOT portable between lines: an anime or
  /// episode id issued by one line means nothing on the
  /// other, so a flow that starts on one line stays on it
  /// (see [_sheetServedByBuiltin]).
  static bool get _officialReady => DanmakuClient.hasCredentials;
  static bool get _builtinReady => BuiltinDanmu.available;

  /// The lines to try, in order, for a fresh flow: 0 is
  /// the official line, 1 the built-in service. When
  /// nothing is configured at all the official line is
  /// still attempted, preserving the historical failure
  /// surface (the source sheet pre-empts that state with
  /// its unconfigured notice anyway).
  static List<int> lineOrderFor({
    required bool officialReady,
    required bool builtinReady,
  }) {
    if (officialReady && builtinReady) return const [0, 1];
    if (officialReady) return const [0];
    if (builtinReady) return const [1];
    return const [0];
  }

  static List<int> get _lineOrder => lineOrderFor(
        officialReady: _officialReady,
        builtinReady: _builtinReady,
      );

  /// Batch 163 compatibility: true only when the built-in
  /// service is the sole configured line (no official
  /// credentials at all). Routing no longer keys off this;
  /// it remains as the probe-visible summary of that
  /// configuration.
  static bool get builtinActive =>
      !DanmakuClient.hasCredentials && BuiltinDanmu.available;

  /// Which line served the most recent manual search. The
  /// episode list and comment calls that follow a search
  /// carry ids issued by that search's line, so they are
  /// routed back to it instead of joining the failover.
  static bool _sheetServedByBuiltin = false;

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

  static Future<DanmakuEpisodeResponse> _episodesOfficial(int bangumiID) async {
    final path = ApiEndpoints.dandanAPIInfo + bangumiID.toString();
    final endPoint = ApiEndpoints.dandanAPIDomain + path;
    final jsonData = await _client.get(endPoint);
    return DanmakuEpisodeResponse.fromJson(jsonData);
  }

  static Future<DanmakuEpisodeResponse> _episodesBuiltin(int bangumiID) {
    return _builtinCall(
      (base) async => DanmakuEpisodeResponse.fromJson(
        await _client.getPlain('$base/api/v2/bangumi/$bangumiID'),
      ),
      accept: (r) => r.episodes.isNotEmpty,
    );
  }

  static Future<DanmakuEpisodeResponse> getDanDanEpisodesByDanDanBangumiID(
    int bangumiID,
  ) {
    // The id came from the search line recorded in
    // [_sheetServedByBuiltin]; only that line can read it.
    return _sheetServedByBuiltin
        ? _episodesBuiltin(bangumiID)
        : _episodesOfficial(bangumiID);
  }

  static Future<DanmakuSearchResponse> _searchOfficial(String title) async {
    final endPoint =
        ApiEndpoints.dandanAPIDomain + ApiEndpoints.dandanAPISearchEpisodes;
    final jsonData = await _client.get(
      endPoint,
      queryParameters: {'anime': title, 'v2': 'true'},
    );
    return DanmakuSearchResponse.fromJson(jsonData);
  }

  static Future<DanmakuSearchResponse> _searchBuiltin(String title) {
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

  // v2 episode search avoids the anime search's 25-result cap.
  // Fetch full episode lists separately; search results can truncate them.
  static Future<DanmakuSearchResponse> searchAnimes(String title) async {
    Object? firstError;
    DanmakuSearchResponse? lastResult;
    var lastWasBuiltin = false;
    for (final line in _lineOrder) {
      try {
        final result =
            line == 1 ? await _searchBuiltin(title) : await _searchOfficial(title);
        lastResult = result;
        lastWasBuiltin = line == 1;
        if (result.animes.isNotEmpty) {
          _sheetServedByBuiltin = lastWasBuiltin;
          return result;
        }
      } catch (e) {
        firstError ??= e;
      }
    }
    if (lastResult != null) {
      _sheetServedByBuiltin = lastWasBuiltin;
      return lastResult;
    }
    throw firstError ?? StateError('弹幕服务暂时不可用');
  }

  /// Automatic danmaku for one episode. The official line
  /// runs first (batch 194); when it errors or resolves to
  /// nothing, the built-in service flow runs as backup.
  /// Returns the entries and the provider-side anime id
  /// they were cached under (0 when nothing resolved).
  static Future<(List<DanmakuEntry>, int)> fetchAutoDanmaku({
    required int bgmBangumiId,
    required String title,
    required int episode,
  }) async {
    Object? firstError;
    (List<DanmakuEntry>, int)? lastResult;
    for (final line in _lineOrder) {
      try {
        final result = line == 1
            ? await _fetchAutoBuiltin(title: title, episode: episode)
            : await _fetchAutoOfficial(
                bgmBangumiId: bgmBangumiId, episode: episode);
        lastResult = result;
        if (result.$1.isNotEmpty) return result;
      } catch (e) {
        firstError ??= e;
      }
    }
    if (lastResult != null) return lastResult;
    throw firstError ?? StateError('弹幕服务暂时不可用');
  }

  /// The official auto flow: map the Bangumi id across and
  /// build the episode id by convention.
  static Future<(List<DanmakuEntry>, int)> _fetchAutoOfficial({
    required int bgmBangumiId,
    required int episode,
  }) async {
    final id = await getDanDanBangumiIDByBgmBangumiID(bgmBangumiId);
    if (id == 0) return (const <DanmakuEntry>[], 0);
    return (await getDanDanmaku(id, episode), id);
  }

  /// The built-in service auto flow: it has no Bangumi id
  /// mapping, so it matches by title — search, pick the
  /// same-season entry, take the episode's real id, fetch
  /// its comments. Every step is forced onto the built-in
  /// line regardless of the manual-search routing flag.
  static Future<(List<DanmakuEntry>, int)> _fetchAutoBuiltin({
    required String title,
    required int episode,
  }) async {
    if (title.trim().isEmpty) return (const <DanmakuEntry>[], 0);
    final search = await _searchBuiltin(title);
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
          final wider = await _searchBuiltin(shortQuery);
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
    final episodes = await _episodesBuiltin(animeId);
    final episodeId =
        BuiltinDanmu.episodeIdForNumber(episodes.episodes, episode);
    if (episodeId == 0) return (const <DanmakuEntry>[], animeId);
    return (await _commentsBuiltin(episodeId.toString()), animeId);
  }

  static Future<List<DanmakuEntry>> getDanDanmaku(
    int bangumiID,
    int episode,
  ) async {
    if (bangumiID == 0) {
      return [];
    }
    // Automatic matching relies on an undocumented episode ID convention.
    return _commentsOfficial('$bangumiID${episode.toString().padLeft(4, '0')}');
  }

  static Future<List<DanmakuEntry>> getDanDanmakuByEpisodeID(int episodeID) {
    // Same id-ownership rule as the episode list: the id
    // belongs to the line that served the manual search.
    return _sheetServedByBuiltin
        ? _commentsBuiltin(episodeID.toString())
        : _commentsOfficial(episodeID.toString());
  }

  static Future<List<DanmakuEntry>> _commentsBuiltin(String episodeID) {
    return _builtinCall((base) async {
      final endPoint = '$base/api/v2/comment/$episodeID';
      AnikumoLogger().i('Danmaku: final request URL $endPoint');
      final jsonData = await _client.getPlain(endPoint);
      final List<dynamic> comments = jsonData['comments'];
      return [for (final comment in comments) DanmakuEntry.fromJson(comment)];
    });
  }

  static Future<List<DanmakuEntry>> _commentsOfficial(String episodeID) async {
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
