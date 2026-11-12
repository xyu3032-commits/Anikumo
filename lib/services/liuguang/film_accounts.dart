import 'package:dio/dio.dart';

import '../../request/apis/bangumi_api.dart';
import '../../request/core/dio_factory.dart';
import '../storage/storage.dart';
import '../tmdb/tmdb_episodes.dart';

/// Batch 254: film-zone account connections — a TMDB
/// personal account (v3 session auth) and the app-wide
/// Bangumi account (the access token the anime zone's
/// sync already uses; one credential, both zones).
/// Everything is local-first: credentials live in the
/// settings box only, nothing is logged, and every call
/// fails soft (null / false) like the zone's other
/// metadata services.

typedef FilmAccountHttp =
    Future<dynamic> Function(
      String method,
      String url, {
      Map<String, dynamic>? query,
      Object? body,
    });

FilmAccountHttp _dioHttp = (method, url, {query, body}) async {
  final dio = DioFactory.apiDio;
  final response = await dio.request<dynamic>(
    url,
    queryParameters: query,
    data: body,
    options: Options(method: method),
  );
  return response.data;
};

/// Test seam: swap the transport (must still throw on
/// HTTP errors, like Dio does).
void debugSetFilmAccountHttp(FilmAccountHttp? http) {
  _dioHttp = http ?? _dioHttp;
}

// ---------------------------------------------------------------------
// TMDB account
// ---------------------------------------------------------------------

class TmdbAccountItem {
  const TmdbAccountItem({
    required this.tmdbId,
    required this.isSeries,
    required this.title,
    this.year,
    this.posterUrl,
    this.score = 0,
  });

  final int tmdbId;
  final bool isSeries;
  final String title;
  final int? year;
  final String? posterUrl;
  final double score;
}

/// One page of a TMDB account list (favorites /
/// watchlist, movies or TV). Pure, for tests.
List<TmdbAccountItem> parseTmdbAccountList(
  dynamic json, {
  required bool isSeries,
}) {
  final results = json is Map ? json['results'] : null;
  if (results is! List) return const [];
  final out = <TmdbAccountItem>[];
  for (final row in results) {
    if (row is! Map) continue;
    final id = (row['id'] as num?)?.toInt() ?? 0;
    if (id <= 0) continue;
    final title = (isSeries ? row['name'] : row['title'])?.toString() ?? '';
    if (title.isEmpty) continue;
    final dateText =
        (isSeries ? row['first_air_date'] : row['release_date'])?.toString() ??
        '';
    final year = dateText.length >= 4
        ? int.tryParse(dateText.substring(0, 4))
        : null;
    final poster = row['poster_path']?.toString() ?? '';
    out.add(
      TmdbAccountItem(
        tmdbId: id,
        isSeries: isSeries,
        title: title,
        year: year,
        posterUrl: poster.isEmpty
            ? null
            : 'https://image.tmdb.org/t/p/w500$poster',
        score: (row['vote_average'] as num?)?.toDouble() ?? 0,
      ),
    );
  }
  return out;
}

class TmdbAccount {
  TmdbAccount._();

  static const _base = 'https://api.themoviedb.org/3';

  static String get _session {
    try {
      return GStorage.getSetting(SettingsKeys.filmTmdbSessionId).trim();
    } catch (_) {
      return '';
    }
  }

  static int get accountId {
    try {
      return GStorage.getSetting(SettingsKeys.filmTmdbAccountId);
    } catch (_) {
      return 0;
    }
  }

  static String get username {
    try {
      return GStorage.getSetting(SettingsKeys.filmTmdbUsername).trim();
    } catch (_) {
      return '';
    }
  }

  static bool get connected => _session.isNotEmpty && accountId > 0;

  static Map<String, dynamic> get _authQuery => {
    'api_key': TmdbEpisodeService.effectiveKey,
    'session_id': _session,
  };

  /// Step 1 of the v3 auth dance: a request token the
  /// user approves on TMDB's own page.
  static Future<String?> createRequestToken() async {
    try {
      final data = await _dioHttp(
        'GET',
        '$_base/authentication/token/new',
        query: {'api_key': TmdbEpisodeService.effectiveKey},
      );
      if (data is Map && data['success'] == true) {
        final token = data['request_token']?.toString() ?? '';
        return token.isEmpty ? null : token;
      }
    } catch (_) {}
    return null;
  }

  static String authenticateUrl(String requestToken) =>
      'https://www.themoviedb.org/authenticate/$requestToken';

  /// Step 3: exchange the approved token for a session
  /// and remember the account. False = not approved
  /// (or any failure) — the login page stays open.
  static Future<bool> completeLogin(String requestToken) async {
    try {
      final data = await _dioHttp(
        'POST',
        '$_base/authentication/session/new',
        query: {'api_key': TmdbEpisodeService.effectiveKey},
        body: {'request_token': requestToken},
      );
      if (data is! Map || data['success'] != true) return false;
      final session = data['session_id']?.toString() ?? '';
      if (session.isEmpty) return false;
      await GStorage.putSetting(SettingsKeys.filmTmdbSessionId, session);
      final account = await _dioHttp(
        'GET',
        '$_base/account',
        query: {
          'api_key': TmdbEpisodeService.effectiveKey,
          'session_id': session,
        },
      );
      if (account is Map) {
        await GStorage.putSetting(
          SettingsKeys.filmTmdbAccountId,
          (account['id'] as num?)?.toInt() ?? 0,
        );
        await GStorage.putSetting(
          SettingsKeys.filmTmdbUsername,
          account['username']?.toString() ?? '',
        );
      }
      return connected;
    } catch (_) {
      return false;
    }
  }

  static Future<void> logout() async {
    final session = _session;
    if (session.isNotEmpty) {
      try {
        await _dioHttp(
          'DELETE',
          '$_base/authentication/session',
          query: {'api_key': TmdbEpisodeService.effectiveKey},
          body: {'session_id': session},
        );
      } catch (_) {
        // Local sign-out proceeds either way.
      }
    }
    await GStorage.putSetting(SettingsKeys.filmTmdbSessionId, '');
    await GStorage.putSetting(SettingsKeys.filmTmdbAccountId, 0);
    await GStorage.putSetting(SettingsKeys.filmTmdbUsername, '');
  }

  /// The signed-in user's marks on one work.
  static Future<({bool favorite, bool watchlist})?> accountStates({
    required bool isSeries,
    required int tmdbId,
  }) async {
    if (!connected || tmdbId <= 0) return null;
    try {
      final data = await _dioHttp(
        'GET',
        '$_base/${isSeries ? 'tv' : 'movie'}/$tmdbId/account_states',
        query: _authQuery,
      );
      if (data is Map) {
        return (
          favorite: data['favorite'] == true,
          watchlist: data['watchlist'] == true,
        );
      }
    } catch (_) {}
    return null;
  }

  static Future<bool> _mark(
    String list,
    String flag, {
    required bool isSeries,
    required int tmdbId,
    required bool value,
  }) async {
    if (!connected || tmdbId <= 0) return false;
    try {
      final data = await _dioHttp(
        'POST',
        '$_base/account/$accountId/$list',
        query: _authQuery,
        body: {
          'media_type': isSeries ? 'tv' : 'movie',
          'media_id': tmdbId,
          flag: value,
        },
      );
      return data is Map &&
          (data['success'] == true ||
              data['status_code'] == 1 ||
              data['status_code'] == 12 ||
              data['status_code'] == 13);
    } catch (_) {
      return false;
    }
  }

  static Future<bool> setFavorite({
    required bool isSeries,
    required int tmdbId,
    required bool value,
  }) => _mark(
    'favorite',
    'favorite',
    isSeries: isSeries,
    tmdbId: tmdbId,
    value: value,
  );

  static Future<bool> setWatchlist({
    required bool isSeries,
    required int tmdbId,
    required bool value,
  }) => _mark(
    'watchlist',
    'watchlist',
    isSeries: isSeries,
    tmdbId: tmdbId,
    value: value,
  );

  /// One account list (favorites or watchlist), movies
  /// and series merged, newest marks first as TMDB
  /// returns them. Two pages per kind are plenty for a
  /// shelf; failures yield what was gathered.
  static Future<List<TmdbAccountItem>> fetchList(String list) async {
    if (!connected) return const [];
    final out = <TmdbAccountItem>[];
    for (final isSeries in [true, false]) {
      for (var page = 1; page <= 2; page++) {
        try {
          final data = await _dioHttp(
            'GET',
            '$_base/account/$accountId/$list/${isSeries ? 'tv' : 'movies'}',
            query: {..._authQuery, 'language': 'zh-CN', 'page': page},
          );
          final items = parseTmdbAccountList(data, isSeries: isSeries);
          out.addAll(items);
          final totalPages = data is Map
              ? (data['total_pages'] as num?)?.toInt() ?? 1
              : 1;
          if (page >= totalPages) break;
        } catch (_) {
          break;
        }
      }
    }
    return out;
  }
}

// ---------------------------------------------------------------------
// Bangumi account (shared app-wide credential)
// ---------------------------------------------------------------------

class BangumiAccount {
  BangumiAccount._();

  static String get token {
    try {
      return GStorage.getSetting(SettingsKeys.bangumiAccessToken).trim();
    } catch (_) {
      return '';
    }
  }

  static bool get connected => token.isNotEmpty;

  static String get username {
    try {
      return GStorage.getSetting(SettingsKeys.filmBangumiUsername).trim();
    } catch (_) {
      return '';
    }
  }

  /// Verifies a candidate token (or the stored one when
  /// [candidate] is null) against /v0/me and remembers
  /// the username. Returns the username or null.
  static Future<String?> verify({String? candidate}) async {
    try {
      final user = await BangumiApi.getCurrentUser(
        accessToken: candidate ?? token,
      );
      final name = (user?.username ?? '').trim();
      if (name.isEmpty) return null;
      await GStorage.putSetting(SettingsKeys.filmBangumiUsername, name);
      return name;
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveToken(String value) async {
    await GStorage.putSetting(SettingsKeys.bangumiAccessToken, value.trim());
  }

  static Future<void> disconnect() async {
    await GStorage.putSetting(SettingsKeys.bangumiAccessToken, '');
    await GStorage.putSetting(SettingsKeys.filmBangumiUsername, '');
  }

  /// Marks a subject with a local CollectType value
  /// （在看 1 / 想看 2 / 搁置 3 / 看过 4 / 抛弃 5) through
  /// the app's existing Bangumi API wrapper.
  static Future<bool> setCollection(int subjectId, int localType) async {
    if (!connected || subjectId <= 0) return false;
    try {
      return await BangumiApi.updateBangumiByType(subjectId, localType);
    } catch (_) {
      return false;
    }
  }
}
