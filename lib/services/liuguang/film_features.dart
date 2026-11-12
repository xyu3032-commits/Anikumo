import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:liuguang_core/liuguang_core.dart';

import '../storage/storage.dart';

/// Batch 232: one optional feature in the film zone's
/// feature repository — the twin of the novel zone's
/// repository (Batch 158), opened for the film zone first
/// under the user's four-zones rollout order. Features are
/// capability modules the user installs or leaves out; an
/// uninstalled feature is fully inert (its UI entries and
/// integrations do not exist). The built-in catalog ships
/// with the app; extra repository addresses can list
/// further entries, and an entry is installable only when
/// its id matches a capability this version actually
/// implements — anything else is shown as unsupported
/// instead of pretending.
class FilmFeatureDef {
  const FilmFeatureDef({
    required this.id,
    required this.name,
    required this.description,
    required this.version,
    required this.sizeLabel,
    this.supported = true,
  });

  final String id;
  final String name;
  final String description;
  final String version;
  final String sizeLabel;

  /// False for entries coming from a remote repository
  /// whose id this version does not implement.
  final bool supported;

  FilmFeatureDef copyWith({String? name, String? description}) =>
      FilmFeatureDef(
        id: id,
        name: name ?? this.name,
        description: description ?? this.description,
        version: version,
        sizeLabel: sizeLabel,
        supported: supported,
      );
}

/// The repository: catalog, install state, and the user's
/// extra repository addresses.
class FilmFeatures {
  FilmFeatures._();

  static const fastResolveId = 'fast_resolve';
  static const lineSpeedId = 'line_speed';
  static const downloadSlimId = 'download_slim';
  static const autoUpdateId = 'auto_update';

  static const builtinCatalog = <FilmFeatureDef>[
    FilmFeatureDef(
      id: fastResolveId,
      name: '极速解析',
      description:
          '打开播放页、切换接口时，并发解析每一集的播放地址，'
          '不再逐集排队等待；集数越多的剧集，打开越快。',
      version: '1.0',
      sizeLabel: '内置功能',
    ),
    FilmFeatureDef(
      id: lineSpeedId,
      name: '线路测速优选',
      description:
          '在详情页一键测速全部线路，把最快的排到最前并记住；'
          '之后这部剧的选集和播放都会优先用快线。',
      version: '1.0',
      sizeLabel: '内置功能',
    ),
    FilmFeatureDef(
      id: downloadSlimId,
      name: '下载省空间',
      description:
          '同一集有多条线路可选时，先比较各线路的体积'
          '（直链文件大小或清单码率），自动选最小的一条下载，省空间也省流量。',
      version: '1.0',
      sizeLabel: '内置功能',
    ),
    FilmFeatureDef(
      id: autoUpdateId,
      name: '追剧自动更新',
      description:
          '进入影视区时自动检查收藏的剧集有没有更新'
          '（每 6 小时最多一次），有新集会在收藏页顶部提醒，不用再手动点检查更新。',
      version: '1.0',
      sizeLabel: '内置功能',
    ),
  ];

  static final ValueNotifier<int> revision = ValueNotifier(0);

  static Set<String> installedIds() {
    try {
      final raw = GStorage.getSetting(SettingsKeys.filmFeatureInstallsJson);
      if (raw.isEmpty) return {};
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return {for (final e in decoded) e.toString()};
      }
    } catch (_) {}
    return {};
  }

  static bool isInstalled(String id) => installedIds().contains(id);

  static Future<void> setInstalled(String id, bool installed) async {
    final ids = installedIds();
    if (installed) {
      ids.add(id);
    } else {
      ids.remove(id);
    }
    await GStorage.putSetting(
      SettingsKeys.filmFeatureInstallsJson,
      jsonEncode(ids.toList()),
    );
    revision.value++;
  }

  static List<String> repoUrls() {
    try {
      final raw = GStorage.getSetting(SettingsKeys.filmFeatureReposJson);
      if (raw.isEmpty) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return [for (final e in decoded) e.toString()];
      }
    } catch (_) {}
    return const [];
  }

  static Future<void> addRepo(String url) async {
    final urls = [...repoUrls()];
    if (!urls.contains(url)) urls.add(url);
    await GStorage.putSetting(
      SettingsKeys.filmFeatureReposJson,
      jsonEncode(urls),
    );
    revision.value++;
  }

  static Future<void> removeRepo(String url) async {
    final urls = repoUrls().where((e) => e != url).toList();
    await GStorage.putSetting(
      SettingsKeys.filmFeatureReposJson,
      jsonEncode(urls),
    );
    revision.value++;
  }

  /// Fetch and parse one repository address's catalog.
  /// Throws on network/HTTP/format errors so the caller can
  /// say why the address was rejected.
  static Future<List<FilmFeatureDef>> fetchCatalog(String url) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode >= 400) {
        throw StateError('仓库返回 ${response.statusCode}');
      }
      final decoded = jsonDecode(body);
      if (decoded is! List) {
        throw const FormatException('目录格式不对：应为功能列表');
      }
      final known = {for (final f in builtinCatalog) f.id: f};
      final out = <FilmFeatureDef>[];
      for (final entry in decoded) {
        if (entry is! Map) continue;
        final id = entry['id']?.toString() ?? '';
        if (id.isEmpty) continue;
        final base = known[id];
        if (base != null) {
          out.add(
            base.copyWith(
              name: entry['name']?.toString() ?? base.name,
              description: entry['description']?.toString() ?? base.description,
            ),
          );
        } else {
          out.add(
            FilmFeatureDef(
              id: id,
              name: entry['name']?.toString() ?? id,
              description: entry['description']?.toString() ?? '',
              version: entry['version']?.toString() ?? '',
              sizeLabel: '',
              supported: false,
            ),
          );
        }
      }
      return out;
    } finally {
      client.close(force: true);
    }
  }
}

/// Batch 232 （线路测速优选）: the remembered line order
/// per interface source — line titles, fastest first.
abstract final class FilmLineSpeed {
  static Map<String, List<String>> _all() {
    try {
      final raw = GStorage.getSetting(SettingsKeys.filmLineSpeedJson);
      if (raw.isEmpty) return {};
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return decoded.map(
          (k, v) => MapEntry(
            '$k',
            v is List ? [for (final e in v) e.toString()] : <String>[],
          ),
        );
      }
    } catch (_) {}
    return {};
  }

  static List<String> orderFor(String sourceId) => _all()[sourceId] ?? const [];

  static Future<void> saveOrder(String sourceId, List<String> titles) async {
    final all = _all();
    all[sourceId] = titles;
    await GStorage.putSetting(SettingsKeys.filmLineSpeedJson, jsonEncode(all));
  }
}

/// Stable-reorders [items] so the ones whose name appears
/// in [preference] come first, in preference order; the
/// rest keep their relative order behind them. Pure and
/// idempotent — applying it twice changes nothing.
List<T> orderByLinePreference<T>(
  List<T> items,
  List<String> preference,
  String Function(T) nameOf,
) {
  if (preference.isEmpty || items.length < 2) return items;
  final rank = <String, int>{};
  for (var i = 0; i < preference.length; i++) {
    rank.putIfAbsent(preference[i], () => i);
  }
  final decorated = [
    for (var i = 0; i < items.length; i++)
      (rank[nameOf(items[i])] ?? (1 << 20), i, items[i]),
  ];
  decorated.sort((a, b) {
    final byRank = a.$1.compareTo(b.$1);
    return byRank != 0 ? byRank : a.$2.compareTo(b.$2);
  });
  return [for (final d in decorated) d.$3];
}

/// Reorders a detail's seasons by the remembered line
/// preference for its source (no-op without a preference).
MediaDetail reorderDetailLines(MediaDetail detail, List<String> preference) {
  if (preference.isEmpty) return detail;
  final seasons = orderByLinePreference(
    detail.seasons,
    preference,
    (s) => s.title,
  );
  if (identical(seasons, detail.seasons)) return detail;
  return MediaDetail(item: detail.item, seasons: seasons);
}

/// Batch 232 （下载省空间）: the lowest-bandwidth variant
/// of an HLS master playlist, or null when [body] is not a
/// master playlist. Relative variant URIs resolve against
/// [base].
({int bandwidth, Uri uri})? parseMasterMinVariant(String body, Uri base) {
  if (!body.contains('#EXT-X-STREAM-INF')) return null;
  ({int bandwidth, Uri uri})? best;
  final lines = body.split('\n');
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i].trim();
    if (!line.startsWith('#EXT-X-STREAM-INF')) continue;
    final match = RegExp(r'BANDWIDTH=(\d+)').firstMatch(line);
    if (match == null) continue;
    final bandwidth = int.parse(match.group(1)!);
    // The variant URI is the next non-empty, non-tag line.
    for (var j = i + 1; j < lines.length; j++) {
      final uriLine = lines[j].trim();
      if (uriLine.isEmpty) continue;
      if (uriLine.startsWith('#')) break;
      final uri = base.resolve(uriLine);
      if (best == null || bandwidth < best.bandwidth) {
        best = (bandwidth: bandwidth, uri: uri);
      }
      break;
    }
  }
  return best;
}

/// Batch 232 （下载省空间）: picks the source with the
/// smallest known size hint. [sizeHints] maps source id →
/// bytes (direct file) or bandwidth (playlist); a null or
/// missing hint counts as unknown, and when everything is
/// unknown — or the current pick is already the smallest —
/// the [preferred] source (the requested line's own) wins.
VideoSource pickSlimmestSource(
  List<VideoSource> sources,
  Map<String, int?> sizeHints,
  VideoSource preferred,
) {
  VideoSource best = preferred;
  int? bestHint = sizeHints[preferred.id];
  for (final source in sources) {
    final hint = sizeHints[source.id];
    if (hint == null) continue;
    if (bestHint == null || hint < bestHint) {
      best = source;
      bestHint = hint;
    }
  }
  return best;
}
