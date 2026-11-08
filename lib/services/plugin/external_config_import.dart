import 'package:anikumo/plugins/api_rule_config.dart';
import 'package:anikumo/plugins/plugins.dart';
import 'package:anikumo/request/config/api_endpoints.dart';

/// Batch 107/108: external site-list configuration adapter.
///
/// Some video apps are configured by a JSON file shaped
/// like `{"sites": [...], "lives": [...]}` — a list of
/// content sites with a `type`, a display `name` and an
/// `api` endpoint each. That file is not a Kazumi rule
/// file, so the rule importer used to reject it wholesale.
/// Its dominant site kind — type 1, a fixed-shape JSON
/// content API (list/detail endpoints with play sources
/// encoded as delimited strings) — maps exactly onto this
/// app's api-mode rules:
///
///   search: GET {api}?ac=videolist&wd=@keyword
///           → $.list[*] / $.vod_name / $.vod_id
///   detail: GET {api}?ac=detail&ids=@source
///           → $.list[0].vod_play_from / $.list[0].vod_play_url
///             split by '$$$' (roads), '#' (episodes), '$'
///             (name$url) — the api chapter config's
///             delimited format, verbatim.
///
/// The converter emits ordinary api-mode [Plugin]s, so
/// converted sites persist, dedupe and play through the
/// exact same pipeline as hand-written API rules. Neither
/// the UI nor the converted data names the originating
/// format (batch 108) — messages describe interface kinds
/// only.
///
/// Site kinds that cannot be converted honestly are
/// reported as skips with reasons instead of failing the
/// whole file:
///   type 0 — XML responses: the api engine decodes JSON
///            responses only.
///   type 3 — script/spider sources: they need a script
///            runtime this app does not ship.
///   type 4 — remote/aggregated sources: undefined here.
class ExternalSiteConversion {
  const ExternalSiteConversion({required this.plugins, required this.skipped});

  final List<Plugin> plugins;

  /// One human line per skipped site, naming it and why.
  final List<String> skipped;
}

/// Whether [json] (already JSON-decoded) has the external
/// site-list shape: an object carrying a `sites` array.
bool isExternalSiteConfig(Object? json) {
  return json is Map && json['sites'] is List;
}

ExternalSiteConversion convertExternalSiteConfig(
  Map<dynamic, dynamic> config,
) {
  final plugins = <Plugin>[];
  final skipped = <String>[];
  final sites = config['sites'];
  if (sites is! List) {
    return const ExternalSiteConversion(
      plugins: [],
      skipped: ['配置缺少源列表'],
    );
  }
  for (final raw in sites) {
    if (raw is! Map) {
      skipped.add('一条源记录格式不对（不是 JSON 对象），已跳过');
      continue;
    }
    final site = raw.map((key, value) => MapEntry(key.toString(), value));
    final name = (site['name'] as String? ?? '').trim();
    final api = (site['api'] as String? ?? '').trim();
    final label = name.isEmpty ? '（未命名）' : name;
    if (name.isEmpty || api.isEmpty) {
      skipped.add('源「$label」缺少名称或接口地址，已跳过');
      continue;
    }
    final type = site['type'];
    final typeValue = type is num ? type.toInt() : int.tryParse('$type');
    switch (typeValue) {
      case 1:
        plugins.add(_jsonApiPlugin(name: name, api: api, site: site));
      case 0:
        skipped.add('源「$name」是 XML 接口，暂只支持 JSON 接口，已跳过');
      case 3:
        skipped.add('源「$name」是脚本类源，需要专门的运行环境，暂不支持，已跳过');
      case 4:
        skipped.add('源「$name」是远程源，暂不支持，已跳过');
      default:
        skipped.add('源「$name」的类型（$type）无法识别，已跳过');
    }
  }
  return ExternalSiteConversion(plugins: plugins, skipped: skipped);
}

Plugin _jsonApiPlugin({
  required String name,
  required String api,
  required Map<String, dynamic> site,
}) {
  final joiner = api.contains('?') ? '&' : '?';
  final searchUrl = '$api${joiner}ac=videolist&wd=@keyword';
  final detailUrl = '$api${joiner}ac=detail&ids=@source';
  final headers = <String, dynamic>{};
  final rawHeader = site['header'];
  if (rawHeader is Map) {
    for (final entry in rawHeader.entries) {
      headers[entry.key.toString()] = entry.value;
    }
  }
  final uri = Uri.tryParse(api);
  final baseUrl = uri != null && uri.hasScheme
      ? '${uri.scheme}://${uri.authority}/'
      : '';
  return Plugin(
    api: ApiEndpoints.apiLevel.toString(),
    type: 'anime',
    name: name,
    version: '',
    muliSources: true,
    useWebview: true,
    useNativePlayer: true,
    usePost: false,
    useLegacyParser: false,
    adBlocker: false,
    userAgent: '',
    baseUrl: baseUrl,
    searchURL: '',
    searchList: '',
    searchName: '',
    searchResult: '',
    chapterRoads: '',
    chapterResult: '',
    referer: '',
    searchMode: RuleMode.api,
    chapterMode: RuleMode.api,
    searchApiConfig: ApiSearchConfig(
      request: ApiRequestConfig(url: searchUrl, headers: headers),
      listPath: r'$.list[*]',
      namePath: r'$.vod_name',
      sourcePath: r'$.vod_id',
    ),
    chapterApiConfig: ApiChapterConfig(
      request: ApiRequestConfig(url: detailUrl, headers: headers),
      format: ApiChapterFormat.delimited,
      roadNamesPath: r'$.list[0].vod_play_from',
      roadEpisodesPath: r'$.list[0].vod_play_url',
    ),
  );
}

/// Batch 107/108: whether a decoded JSON array is a
/// book-source package from the novel-reader ecosystem —
/// its entries carry the book-source keys (bookSourceUrl /
/// ruleSearch / ruleVideo), which no Kazumi rule uses.
/// [isVideo] tells video sources (ruleVideo present) from
/// book sources. Returns null when the array is not
/// book-source-shaped. The result drives a guidance
/// message only; the format is never named in the UI.
({bool isVideo})? bookSourceShapeOf(Object? json) {
  if (json is! List || json.isEmpty) return null;
  var sawBookSource = false;
  var sawVideo = false;
  for (final entry in json) {
    if (entry is! Map) return null;
    final keys = entry.keys.map((k) => k.toString()).toSet();
    if (keys.contains('bookSourceUrl') ||
        keys.contains('ruleSearch') ||
        keys.contains('ruleVideo')) {
      sawBookSource = true;
    }
    if (keys.contains('ruleVideo')) sawVideo = true;
  }
  if (!sawBookSource) return null;
  return (isVideo: sawVideo);
}
