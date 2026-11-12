import 'dart:convert';

import 'package:dio/dio.dart';

import '../../request/core/dio_factory.dart';
import '../backup/local_backup.dart';
import '../storage/storage.dart';
import 'github_client_id.dart';

/// Batch 257: GitHub sign-in + backup sync for the user
/// center. Sign-in is the OAuth device-code flow (no
/// client secret ships in the app); sync stores the
/// app's existing local-backup payload as one file in a
/// repository in the USER'S OWN GitHub account.
///
/// Ordering rule (the user's chosen conflict policy):
/// every payload carries its exportedAt stamp. A sync
/// first looks at the remote file — when its stamp
/// differs from the stamp this device last pushed or
/// pulled, the remote copy is the newer line and is
/// pulled (after the user confirms the overwrite);
/// otherwise the local copy is pushed. First contact
/// with an existing remote file is a pull, never a
/// silent overwrite.

typedef GithubHttp =
    Future<({int status, dynamic data})> Function(
      String method,
      Uri url, {
      Map<String, String>? headers,
      Map<String, String>? form,
      Map<String, dynamic>? jsonBody,
    });

GithubHttp? _debugHttp;

/// Test seam: stand-in client id (the real one is
/// injected at packaging time and empty in the tree).
String debugGithubClientId = '';

String get _effectiveClientId =>
    debugGithubClientId.isNotEmpty ? debugGithubClientId : githubClientId;

/// Test seam: replace the HTTP layer (device flow, API
/// and contents calls all pass through it).
void debugSetGithubHttp(GithubHttp? handler) => _debugHttp = handler;

Map<String, dynamic> _asMap(dynamic data) =>
    data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};

Future<({int status, dynamic data})> _http(
  String method,
  Uri url, {
  Map<String, String>? headers,
  Map<String, String>? form,
  Map<String, dynamic>? jsonBody,
}) async {
  final override = _debugHttp;
  if (override != null) {
    return override(
      method,
      url,
      headers: headers,
      form: form,
      jsonBody: jsonBody,
    );
  }
  try {
    final response = await DioFactory.apiDio.requestUri<dynamic>(
      url,
      data: form ?? jsonBody,
      options: Options(
        method: method,
        headers: {'Accept': 'application/json', ...?headers},
        contentType: form != null ? Headers.formUrlEncodedContentType : null,
        validateStatus: (_) => true,
        responseType: ResponseType.json,
      ),
    );
    return (status: response.statusCode ?? 0, data: response.data);
  } on DioException catch (e) {
    return (status: e.response?.statusCode ?? 0, data: null);
  }
}

class GithubSyncException implements Exception {
  GithubSyncException(this.message);
  final String message;
  @override
  String toString() => message;
}

class GithubDeviceCode {
  const GithubDeviceCode({
    required this.deviceCode,
    required this.userCode,
    required this.verificationUri,
    required this.intervalSeconds,
  });

  final String deviceCode;
  final String userCode;
  final String verificationUri;
  final int intervalSeconds;
}

enum GithubPollState { pending, slowDown, authorized, denied, expired, error }

class GithubRepoChoice {
  const GithubRepoChoice({required this.fullName, required this.isPrivate});

  final String fullName;
  final bool isPrivate;
}

/// Reads the exportedAt stamp out of a backup payload;
/// null when the payload is not one of ours.
DateTime? parseSyncExportedAt(String? payload) {
  if (payload == null || payload.isEmpty) return null;
  try {
    final decoded = jsonDecode(payload);
    if (decoded is! Map) return null;
    if (decoded['app'] != 'anikumo') return null;
    return DateTime.tryParse('${decoded['exportedAt'] ?? ''}');
  } catch (_) {
    return null;
  }
}

/// The pull-first ordering test: the remote file leads
/// whenever its stamp is not the stamp this device last
/// pushed or pulled.
bool remoteLeads({
  required DateTime? remoteExportedAt,
  required String lastKnownExportedAt,
}) {
  if (remoteExportedAt == null) return false;
  return remoteExportedAt.toIso8601String() != lastKnownExportedAt;
}

abstract final class GithubSync {
  static const syncFileName = 'anikumo-backup.json';
  static const defaultRepoName = 'anikumo-sync';

  /// The GitHub contents endpoint refuses files much
  /// above 1 MB; guard before attempting the upload.
  static const maxPayloadBytes = 950000;

  static bool get configured => _effectiveClientId.isNotEmpty;

  static String get _token =>
      GStorage.getSetting(SettingsKeys.githubAccessToken);
  static bool get connected => _token.isNotEmpty;
  static String get username =>
      GStorage.getSetting(SettingsKeys.githubUsername);
  static String get avatarUrl =>
      GStorage.getSetting(SettingsKeys.githubAvatarUrl);
  static String get syncRepo =>
      GStorage.getSetting(SettingsKeys.githubSyncRepo);
  static String get lastSyncAt =>
      GStorage.getSetting(SettingsKeys.githubLastSyncAt);

  static Map<String, String> get _apiHeaders => {
    'Authorization': 'Bearer $_token',
    'Accept': 'application/vnd.github+json',
    'X-GitHub-Api-Version': '2022-11-28',
  };

  // ── device-code sign-in ─────────────────────────────

  static Future<GithubDeviceCode> startDeviceFlow() async {
    if (!configured) {
      throw GithubSyncException('这个版本没有配置 GitHub 登录（缺少应用标识）。');
    }
    final res = await _http(
      'POST',
      Uri.parse('https://github.com/login/device/code'),
      form: {'client_id': _effectiveClientId, 'scope': 'repo'},
    );
    final body = _asMap(res.data);
    final code = body['device_code'];
    final userCode = body['user_code'];
    if (res.status != 200 || code is! String || userCode is! String) {
      throw GithubSyncException('无法向 GitHub 申请登录码，请检查网络后重试。');
    }
    return GithubDeviceCode(
      deviceCode: code,
      userCode: userCode,
      verificationUri:
          '${body['verification_uri'] ?? 'https://github.com/login/device'}',
      intervalSeconds: (body['interval'] as num?)?.toInt() ?? 5,
    );
  }

  /// One poll of the token endpoint. On [authorized] the
  /// token and profile are already persisted.
  static Future<GithubPollState> pollDeviceFlow(GithubDeviceCode code) async {
    final res = await _http(
      'POST',
      Uri.parse('https://github.com/login/oauth/access_token'),
      form: {
        'client_id': _effectiveClientId,
        'device_code': code.deviceCode,
        'grant_type': 'urn:ietf:params:oauth:grant-type:device_code',
      },
    );
    final body = _asMap(res.data);
    final token = body['access_token'];
    if (token is String && token.isNotEmpty) {
      await GStorage.putSetting(SettingsKeys.githubAccessToken, token);
      await refreshProfile();
      return GithubPollState.authorized;
    }
    return switch (body['error']) {
      'authorization_pending' => GithubPollState.pending,
      'slow_down' => GithubPollState.slowDown,
      'access_denied' => GithubPollState.denied,
      'expired_token' => GithubPollState.expired,
      _ => GithubPollState.error,
    };
  }

  static Future<void> refreshProfile() async {
    if (!connected) return;
    final res = await _http(
      'GET',
      Uri.parse('https://api.github.com/user'),
      headers: _apiHeaders,
    );
    if (res.status == 200) {
      final body = _asMap(res.data);
      await GStorage.putSetting(
        SettingsKeys.githubUsername,
        '${body['login'] ?? ''}',
      );
      await GStorage.putSetting(
        SettingsKeys.githubAvatarUrl,
        '${body['avatar_url'] ?? ''}',
      );
    }
  }

  /// Drops the token and profile cache on this device.
  /// The repository and its file stay untouched in the
  /// user's account.
  static Future<void> disconnect() async {
    await GStorage.putSetting(SettingsKeys.githubAccessToken, '');
    await GStorage.putSetting(SettingsKeys.githubUsername, '');
    await GStorage.putSetting(SettingsKeys.githubAvatarUrl, '');
    await GStorage.putSetting(SettingsKeys.githubLastKnownExportedAt, '');
    await GStorage.putSetting(SettingsKeys.githubLastSyncAt, '');
  }

  // ── repository choice ───────────────────────────────

  static Future<List<GithubRepoChoice>> listOwnRepos() async {
    final res = await _http(
      'GET',
      Uri.parse(
        'https://api.github.com/user/repos?affiliation=owner&per_page=100&sort=updated',
      ),
      headers: _apiHeaders,
    );
    if (res.status != 200) {
      throw GithubSyncException('读取仓库列表失败（${res.status}），请检查网络或重新登录。');
    }
    final items = res.data is List ? res.data as List : const [];
    return [
      for (final item in items)
        if (item is Map)
          GithubRepoChoice(
            fullName: '${item['full_name'] ?? ''}',
            isPrivate: item['private'] == true,
          ),
    ]..removeWhere((r) => r.fullName.isEmpty);
  }

  /// Creates the dedicated private sync repository, or
  /// adopts it when it already exists.
  static Future<String> createSyncRepo() async {
    final res = await _http(
      'POST',
      Uri.parse('https://api.github.com/user/repos'),
      headers: _apiHeaders,
      jsonBody: {
        'name': defaultRepoName,
        'private': true,
        'description': 'Anikumo 数据同步（应用自动维护，请勿手动修改 anikumo-backup.json）',
      },
    );
    if (res.status == 201) {
      final fullName = '${_asMap(res.data)['full_name'] ?? ''}';
      if (fullName.isNotEmpty) return fullName;
    }
    if (res.status == 422) {
      // Already exists under this account — adopt it.
      final user = username.isNotEmpty ? username : (await _fetchLogin());
      if (user.isNotEmpty) return '$user/$defaultRepoName';
    }
    throw GithubSyncException('创建同步仓库失败（${res.status}）。');
  }

  static Future<String> _fetchLogin() async {
    final res = await _http(
      'GET',
      Uri.parse('https://api.github.com/user'),
      headers: _apiHeaders,
    );
    return res.status == 200 ? '${_asMap(res.data)['login'] ?? ''}' : '';
  }

  static Future<void> chooseRepo(String fullName) =>
      GStorage.putSetting(SettingsKeys.githubSyncRepo, fullName);

  // ── sync ────────────────────────────────────────────

  static Uri _contentsUri(String repo) =>
      Uri.parse('https://api.github.com/repos/$repo/contents/$syncFileName');

  static Future<({String? payload, String? sha})> _fetchRemote() async {
    final res = await _http(
      'GET',
      _contentsUri(syncRepo),
      headers: _apiHeaders,
    );
    if (res.status == 404) return (payload: null, sha: null);
    if (res.status != 200) {
      throw GithubSyncException('读取远端同步文件失败（${res.status}）。');
    }
    final body = _asMap(res.data);
    final encoded = '${body['content'] ?? ''}'.replaceAll('\n', '');
    String? payload;
    try {
      payload = utf8.decode(base64Decode(encoded));
    } catch (_) {
      payload = null;
    }
    final sha = body['sha'];
    return (payload: payload, sha: sha is String ? sha : null);
  }

  /// One manual sync. [confirmPull] is asked (with the
  /// remote stamp) before a remote-led overwrite is
  /// applied; declining leaves both copies untouched.
  /// Returns a user-facing outcome line.
  static Future<String> syncNow({
    required Future<bool> Function(DateTime remoteAt) confirmPull,
  }) async {
    if (!connected) throw GithubSyncException('请先登录 GitHub。');
    if (syncRepo.isEmpty) throw GithubSyncException('请先选择或创建同步仓库。');
    final remote = await _fetchRemote();
    final remoteAt = parseSyncExportedAt(remote.payload);
    final lastKnown = GStorage.getSetting(
      SettingsKeys.githubLastKnownExportedAt,
    );
    if (remote.payload != null &&
        remoteLeads(
          remoteExportedAt: remoteAt,
          lastKnownExportedAt: lastKnown,
        )) {
      final at = remoteAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      if (!await confirmPull(at)) return '已取消：远端较新，未做任何改动。';
      final data = LocalBackup.parse(remote.payload!);
      if (data == null) {
        throw GithubSyncException('远端文件不是有效的 Anikumo 备份，未做任何改动。');
      }
      await LocalBackup.apply(data);
      await GStorage.putSetting(
        SettingsKeys.githubLastKnownExportedAt,
        remoteAt?.toIso8601String() ?? '',
      );
      await GStorage.putSetting(
        SettingsKeys.githubLastSyncAt,
        DateTime.now().toIso8601String(),
      );
      return '已从云端拉取并应用（远端时间 ${remoteAt?.toLocal()}）。';
    }
    // Push path.
    final payload = await LocalBackup.exportJson();
    if (utf8.encode(payload).length > maxPayloadBytes) {
      throw GithubSyncException(
        '本地数据超过 GitHub 单文件接口上限（约 1MB），本次未同步。'
        '可以先到本地备份页导出文件手动保存。',
      );
    }
    var sha = remote.sha;
    for (var attempt = 0; attempt < 2; attempt++) {
      final res = await _http(
        'PUT',
        _contentsUri(syncRepo),
        headers: _apiHeaders,
        jsonBody: {
          'message': 'Anikumo sync ${DateTime.now().toIso8601String()}',
          'content': base64Encode(utf8.encode(payload)),
          if (sha != null) 'sha': sha,
        },
      );
      if (res.status == 200 || res.status == 201) {
        final stamp = parseSyncExportedAt(payload);
        await GStorage.putSetting(
          SettingsKeys.githubLastKnownExportedAt,
          stamp?.toIso8601String() ?? '',
        );
        await GStorage.putSetting(
          SettingsKeys.githubLastSyncAt,
          DateTime.now().toIso8601String(),
        );
        return '已把本机数据同步到云端仓库。';
      }
      if ((res.status == 409 || res.status == 422) && attempt == 0) {
        // The file moved under us — refetch its sha and
        // retry once (the 适配 half of the ordering rule).
        sha = (await _fetchRemote()).sha;
        continue;
      }
      throw GithubSyncException('上传同步文件失败（${res.status}）。');
    }
    throw GithubSyncException('上传同步文件失败，请稍后重试。');
  }
}
