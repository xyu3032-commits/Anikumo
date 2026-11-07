import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:anikumo/plugins/plugins.dart';

/// Batch 62: user-supplied rule repository support.
///
/// A repository is a directory (usually a raw file host)
/// containing `index.json` — a JSON array of catalog entries
/// — plus one `<name>.json` file per rule. The batch-59 pass
/// removed the built-in repository; this restores the
/// capability driven entirely by an address the user enters,
/// with batch import. GitHub *web* addresses are accepted
/// and converted to their raw form, because that is what
/// users actually paste (batch 59's bare-URL download used
/// to fetch the repo's HTML page and fail).
class RuleRepository {
  const RuleRepository._();

  /// Normalizes a user-entered repository address to its
  /// base URL (always ends with '/'), or returns null when
  /// the input is not a repository address at all (e.g. a
  /// single rule file URL, or not a URL).
  static String? normalizeBase(String input) {
    final value = input.trim();
    if (value.isEmpty) return null;
    final uri = Uri.tryParse(value);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        !uri.hasAuthority ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      return null;
    }
    if (uri.host == 'github.com') {
      return _githubRawBase(uri);
    }
    // Raw / directory form: drop a trailing index.json, and
    // refuse anything that looks like a single file.
    final segments = [
      for (final s in uri.pathSegments)
        if (s.isNotEmpty) s,
    ];
    if (segments.isNotEmpty &&
        segments.last.toLowerCase() == 'index.json') {
      segments.removeLast();
    } else if (segments.isNotEmpty &&
        segments.last.contains('.') &&
        !value.endsWith('/')) {
      return null;
    }
    return Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      pathSegments: [...segments, ''],
    ).toString();
  }

  static String? _githubRawBase(Uri uri) {
    final segments = [
      for (final s in uri.pathSegments)
        if (s.isNotEmpty) s,
    ];
    if (segments.length < 2) return null;
    final owner = segments[0];
    var repo = segments[1];
    if (repo.toLowerCase().endsWith('.git')) {
      repo = repo.substring(0, repo.length - 4);
    }
    if (repo.isEmpty) return null;
    var branch = 'main';
    var subPath = <String>[];
    final rest = segments.sublist(2);
    if (rest.isNotEmpty && rest.first == 'tree') {
      if (rest.length < 2) return null;
      branch = rest[1];
      subPath = rest.sublist(2);
    } else if (rest.isNotEmpty) {
      // /owner/repo/<anything else> is a page inside the
      // repo (issues, a file view...) — not a repo root we
      // can resolve, except a plain trailing path under the
      // default branch is not distinguishable; refuse.
      return null;
    }
    return Uri(
      scheme: 'https',
      host: 'raw.githubusercontent.com',
      pathSegments: [owner, repo, branch, ...subPath, ''],
    ).toString();
  }

  static Uri catalogUri(String base) => Uri.parse(base).resolve('index.json');

  static Uri ruleUri(String base, String ruleName) =>
      Uri.parse(base).resolveUri(Uri(pathSegments: ['$ruleName.json']));

  static Future<String> _getText(String url) async {
    final response = await Dio().get<String>(
      url,
      options: Options(
        responseType: ResponseType.plain,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
      ),
    );
    return response.data ?? '';
  }

  /// Fetches and parses the repository catalog.
  static Future<RuleCatalog> fetchCatalog(String base) async {
    final raw = await _getText(catalogUri(base).toString());
    return parseCatalog(raw);
  }

  static RuleCatalog parseCatalog(String raw) {
    final decoded = json.decode(raw);
    if (decoded is! List) {
      throw const FormatException('仓库目录（index.json）格式不对：根节点必须是数组');
    }
    final items = <RuleCatalogItem>[];
    var skipped = 0;
    for (final entry in decoded) {
      final item = RuleCatalogItem.tryParse(entry);
      if (item == null) {
        skipped++;
      } else {
        items.add(item);
      }
    }
    if (decoded.isNotEmpty && items.isEmpty) {
      throw const FormatException('仓库目录里没有有效的规则条目');
    }
    return RuleCatalog(items: items, skipped: skipped);
  }

  /// Downloads one rule file and parses it as a Plugin.
  static Future<Plugin> fetchRule(String base, String name) async {
    final raw = await _getText(ruleUri(base, name).toString());
    final decoded = json.decode(raw);
    if (decoded is! Map) {
      throw FormatException('规则「$name」的文件格式不对');
    }
    return Plugin.fromJson(Map<String, dynamic>.from(decoded));
  }
}

class RuleCatalog {
  const RuleCatalog({required this.items, required this.skipped});

  final List<RuleCatalogItem> items;
  final int skipped;
}

class RuleCatalogItem {
  const RuleCatalogItem({
    required this.name,
    required this.version,
    required this.author,
    required this.lastUpdate,
  });

  final String name;
  final String version;
  final String author;
  final int lastUpdate;

  static RuleCatalogItem? tryParse(Object? value) {
    if (value is! Map) return null;
    final name = value['name'];
    if (name is! String || name.isEmpty) return null;
    return RuleCatalogItem(
      name: name,
      version: value['version']?.toString() ?? '',
      author: value['author']?.toString() ?? '',
      lastUpdate: value['lastUpdate'] is num
          ? (value['lastUpdate'] as num).toInt()
          : 0,
    );
  }
}
