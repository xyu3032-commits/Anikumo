import 'dart:convert';

import 'package:liuguang_network/liuguang_network.dart';

import 'package:anikumo/services/liuguang/video_engine.dart';

/// Batch 204: repository （仓库） configuration handling for
/// the 影视 zone. A repository address serves ONE JSON
/// configuration document listing many interface sources
/// ("sites"); installing a repository means reading that
/// document once and registering every directly-usable
/// site. Site kinds this app cannot run (script-plugin
/// sites that need a foreign runtime) are counted and
/// reported honestly, never silently dropped.

class RepositoryConfig {
  const RepositoryConfig({
    required this.sites,
    required this.skippedRuntime,
    required this.skippedOther,
    required this.nestedRepositories,
  });

  /// Directly installable sites as (name, api) pairs.
  final List<(String, String)> sites;

  /// Sites skipped because they need a script runtime this
  /// app does not have (type 3/4 in the configuration).
  final int skippedRuntime;

  /// Sites skipped for other reasons (missing/non-http api,
  /// malformed entries).
  final int skippedOther;

  /// A configuration that is itself a list of further
  /// repository addresses (the multi-repository shape).
  final List<VideoRepositoryEntry> nestedRepositories;
}

class RepositoryImportReport {
  const RepositoryImportReport({
    this.installed = 0,
    this.skippedRuntime = 0,
    this.skippedOther = 0,
    this.nestedRepositories = 0,
    this.error,
  });

  final int installed;
  final int skippedRuntime;
  final int skippedOther;
  final int nestedRepositories;
  final String? error;

  bool get ok => error == null;

  String describe() {
    if (!ok) return '导入失败：$error';
    final parts = <String>['已装入 $installed 个接口源'];
    if (nestedRepositories > 0) parts.add('另发现 $nestedRepositories 个仓库（已加入列表）');
    if (skippedRuntime > 0) {
      parts.add('$skippedRuntime 个站点需要专用运行环境，本应用无法使用，已跳过');
    }
    if (skippedOther > 0) parts.add('$skippedOther 个条目格式不完整，已跳过');
    return parts.join('；');
  }
}

/// Parses one configuration document. Accepts the strict
/// JSON first, then a lenient pass (line comments and
/// trailing commas are common in hand-maintained files).
RepositoryConfig parseRepositoryConfig(String text) {
  final decoded = _decodeLenient(text);
  var sitesRaw = const <dynamic>[];
  var nestedRaw = const <dynamic>[];
  if (decoded is List) {
    sitesRaw = decoded;
  } else if (decoded is Map) {
    if (decoded['sites'] is List) sitesRaw = decoded['sites'] as List;
    if (decoded['urls'] is List) nestedRaw = decoded['urls'] as List;
  } else {
    throw const FormatException('配置不是有效的 JSON 文档');
  }

  final sites = <(String, String)>[];
  var skippedRuntime = 0;
  var skippedOther = 0;
  for (final raw in sitesRaw) {
    if (raw is! Map) {
      skippedOther++;
      continue;
    }
    final api = raw['api']?.toString().trim() ?? '';
    final name = raw['name']?.toString().trim() ?? '';
    final type = raw['type'] is num
        ? (raw['type'] as num).toInt()
        : int.tryParse(raw['type']?.toString() ?? '') ?? -1;
    if (type == 3 || type == 4) {
      skippedRuntime++;
      continue;
    }
    if (api.isEmpty ||
        !(api.startsWith('http://') || api.startsWith('https://')) ||
        name.isEmpty) {
      skippedOther++;
      continue;
    }
    sites.add((name, api));
  }

  final nested = <VideoRepositoryEntry>[];
  for (final raw in nestedRaw) {
    if (raw is Map) {
      final url = raw['url']?.toString().trim() ?? '';
      final name = raw['name']?.toString().trim() ?? '';
      if (url.startsWith('http')) {
        nested.add(VideoRepositoryEntry(
          name: name.isEmpty ? url : name,
          url: url,
        ));
      }
    } else if (raw is String && raw.startsWith('http')) {
      nested.add(VideoRepositoryEntry(name: raw, url: raw));
    }
  }

  return RepositoryConfig(
    sites: sites,
    skippedRuntime: skippedRuntime,
    skippedOther: skippedOther,
    nestedRepositories: nested,
  );
}

Object? _decodeLenient(String text) {
  try {
    return jsonDecode(text);
  } catch (_) {
    final stripped = text
        .split('\n')
        .where((line) => !line.trimLeft().startsWith('//'))
        .join('\n')
        .replaceAll(RegExp(r',(\s*[}\]])'), r'$1');
    return jsonDecode(stripped);
  }
}

/// Fetches and installs repository configurations through
/// [VideoEngineService].
class VideoRepositoryImporter {
  VideoRepositoryImporter({LiuGuangHttpClient? client})
      : _client = client ?? LiuGuangHttpClient();

  final LiuGuangHttpClient _client;

  Future<RepositoryImportReport> importFromUrl(
    VideoRepositoryEntry repository,
  ) async {
    try {
      final response = await _client.get(
        repository.url,
        headers: const {
          'User-Agent': 'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 '
              'Chrome/120.0 Mobile Safari/537.36',
        },
      );
      return await importFromText(response.body, repositoryName: repository.name);
    } catch (e) {
      return RepositoryImportReport(error: e.toString());
    }
  }

  Future<RepositoryImportReport> importFromText(
    String text, {
    required String repositoryName,
  }) async {
    final RepositoryConfig config;
    try {
      config = parseRepositoryConfig(text);
    } catch (e) {
      return RepositoryImportReport(error: e.toString());
    }
    final service = VideoEngineService.instance;
    final before = service.sources.length;
    await service.addSources([
      for (final (name, api) in config.sites)
        VideoSourceEntry(
          id: VideoSourceEntry.idForApi(api),
          name: name,
          api: api,
          fromRepository: repositoryName,
        ),
    ]);
    for (final nested in config.nestedRepositories) {
      await service.addRepository(nested);
    }
    return RepositoryImportReport(
      installed: service.sources.length - before,
      skippedRuntime: config.skippedRuntime,
      skippedOther: config.skippedOther,
      nestedRepositories: config.nestedRepositories.length,
    );
  }
}
