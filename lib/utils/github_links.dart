import 'dart:convert';

import 'package:dio/dio.dart';

/// Batch 63: GitHub link handling shared by the novel and
/// manga import flows (the anime rule repository grew its
/// own copy in batch 62; this is the neutral utility for
/// zones that import plain files rather than rule repos).
///
/// Two shapes matter to users, and both used to fail:
/// - A *file page* address (github.com/o/r/blob/main/x.js)
///   is an HTML page, not the file — it must be rewritten
///   to the raw file address before downloading.
/// - A *repository* address (github.com/o/r, optionally
///   /tree/<branch>/<subpath>) names a folder of files —
///   the import UIs list its files and let the user pick.
class GithubRepoRef {
  const GithubRepoRef({
    required this.owner,
    required this.repo,
    this.branch,
    this.subpath = '',
  });

  final String owner;
  final String repo;

  /// Null when the pasted address did not name a branch;
  /// the listing call then resolves the repo's default
  /// branch first instead of guessing `main`.
  final String? branch;

  /// Directory inside the repo ('' = root).
  final String subpath;
}

class GithubFileEntry {
  const GithubFileEntry({required this.name, required this.downloadUrl});

  final String name;
  final String downloadUrl;
}

typedef GithubTextFetcher = Future<String> Function(String url);

Future<String> _dioFetchText(String url) async {
  final response = await Dio().get<String>(
    url,
    options: Options(
      responseType: ResponseType.plain,
      headers: const {'User-Agent': 'Anikumo-App'},
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
    ),
  );
  return response.data ?? '';
}

class GithubLinks {
  const GithubLinks._();

  static Uri? _githubUri(String input) {
    final uri = Uri.tryParse(input.trim());
    if (uri == null || uri.host != 'github.com') return null;
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;
    return uri;
  }

  static List<String> _segments(Uri uri) => [
        for (final s in uri.pathSegments)
          if (s.isNotEmpty) s,
      ];

  /// Parses a repository address (root or /tree/...).
  /// File-page (blob) addresses and other in-repo pages
  /// return null — they are not repository references.
  static GithubRepoRef? parseRepo(String input) {
    final uri = _githubUri(input);
    if (uri == null) return null;
    final segments = _segments(uri);
    if (segments.length < 2) return null;
    var repo = segments[1];
    if (repo.toLowerCase().endsWith('.git')) {
      repo = repo.substring(0, repo.length - 4);
    }
    if (repo.isEmpty) return null;
    final rest = segments.sublist(2);
    if (rest.isEmpty) {
      return GithubRepoRef(owner: segments[0], repo: repo);
    }
    if (rest.first == 'tree' && rest.length >= 2) {
      return GithubRepoRef(
        owner: segments[0],
        repo: repo,
        branch: rest[1],
        subpath: rest.sublist(2).join('/'),
      );
    }
    return null;
  }

  /// Rewrites a GitHub file-page address (blob or raw
  /// path) to the raw file address. Returns the input
  /// unchanged for raw.githubusercontent.com addresses,
  /// and null for anything else (other hosts, repo pages),
  /// so callers can do `rawFileUrl(u) ?? u`.
  static String? rawFileUrl(String input) {
    final value = input.trim();
    final uri = Uri.tryParse(value);
    if (uri == null) return null;
    if (uri.host == 'raw.githubusercontent.com') return value;
    if (uri.host != 'github.com') return null;
    final segments = _segments(uri);
    if (segments.length < 5) return null;
    final kind = segments[2];
    if (kind != 'blob' && kind != 'raw') return null;
    return Uri(
      scheme: 'https',
      host: 'raw.githubusercontent.com',
      pathSegments: [
        segments[0],
        segments[1],
        segments[3],
        ...segments.sublist(4),
      ],
    ).toString();
  }

  /// Lists the files of the referenced directory via the
  /// GitHub contents API. Directories are skipped (only
  /// one level is listed). Throws on transport/API errors.
  static Future<List<GithubFileEntry>> listFiles(
    GithubRepoRef ref, {
    GithubTextFetcher? fetcher,
  }) async {
    final fetch = fetcher ?? _dioFetchText;
    var branch = ref.branch;
    if (branch == null) {
      final meta = json.decode(
        await fetch('https://api.github.com/repos/${ref.owner}/${ref.repo}'),
      );
      if (meta is Map && meta['default_branch'] is String) {
        branch = meta['default_branch'] as String;
      } else {
        throw const FormatException('读不到仓库信息（仓库不存在或不可见）');
      }
    }
    final pathPart = ref.subpath.isEmpty
        ? ''
        : '/${Uri.encodeFull(ref.subpath)}';
    final raw = await fetch(
      'https://api.github.com/repos/${ref.owner}/${ref.repo}'
      '/contents$pathPart?ref=$branch',
    );
    return parseContents(raw, ref: ref, branch: branch);
  }

  static List<GithubFileEntry> parseContents(
    String raw, {
    required GithubRepoRef ref,
    required String branch,
  }) {
    final decoded = json.decode(raw);
    if (decoded is! List) {
      throw const FormatException('仓库目录读取失败（可能不是目录地址）');
    }
    final files = <GithubFileEntry>[];
    for (final entry in decoded) {
      if (entry is! Map) continue;
      if (entry['type'] != 'file') continue;
      final name = entry['name'];
      if (name is! String || name.isEmpty) continue;
      final download = entry['download_url'];
      files.add(GithubFileEntry(
        name: name,
        downloadUrl: download is String && download.isNotEmpty
            ? download
            : Uri(
                scheme: 'https',
                host: 'raw.githubusercontent.com',
                pathSegments: [
                  ref.owner,
                  ref.repo,
                  branch,
                  if (ref.subpath.isNotEmpty) ...ref.subpath.split('/'),
                  name,
                ],
              ).toString(),
      ));
    }
    return files;
  }
}
