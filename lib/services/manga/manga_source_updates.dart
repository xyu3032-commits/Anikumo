import 'package:dio/dio.dart';

import 'manga_sources.dart';

/// Batch 190: manga source update checking.
///
/// An installed source's latest version is learned from
/// (in order):
/// 1. every recorded repository (index) — one fetch per
///    repository covers all the sources it lists;
/// 2. the source's own recorded origin URL — the file is
///    re-read and its declared version compared.
///
/// Everything is best-effort: any fetch or parse failure
/// simply yields no update for that source, so an
/// offline launch stays silent.

/// Fetches a URL's text, or null on any failure. Injected
/// in tests.
typedef MangaTextFetcher = Future<String?> Function(String url);

/// The production fetcher: a plain GET with the same
/// timeouts the source importer uses.
Future<String?> dioMangaTextFetch(String url) async {
  try {
    final response = await Dio().get<String>(
      url,
      options: Options(
        responseType: ResponseType.plain,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
      ),
    );
    return response.data;
  } catch (_) {
    return null;
  }
}

/// One installed source with a newer version available.
class MangaSourceUpdate {
  const MangaSourceUpdate({
    required this.jsKey,
    required this.name,
    required this.installedVersion,
    required this.latestVersion,
    required this.fileUrl,
  });

  final String jsKey;
  final String name;
  final String installedVersion;
  final String latestVersion;

  /// Where the new file downloads from.
  final String fileUrl;
}

/// Segment-wise dotted version compare ('1.10.0' > '1.9.9').
/// Segments compare by their leading number when both
/// have one; a segment without digits compares as text.
/// Empty versions never count as newer (or older) — a
/// source whose version is unknown is left alone.
bool isNewerMangaVersion(String latest, String installed) {
  final a = latest.trim();
  final b = installed.trim();
  if (a.isEmpty || b.isEmpty || a == b) return false;
  final pa = a.split('.');
  final pb = b.split('.');
  final n = pa.length > pb.length ? pa.length : pb.length;
  for (var i = 0; i < n; i++) {
    final sa = i < pa.length ? pa[i] : '';
    final sb = i < pb.length ? pb[i] : '';
    if (sa == sb) continue;
    final na = _segmentNumber(sa);
    final nb = _segmentNumber(sb);
    if (na != null && nb != null) {
      if (na != nb) return na > nb;
      continue;
    }
    return sa.compareTo(sb) > 0;
  }
  return false;
}

int? _segmentNumber(String segment) {
  final match = RegExp(r'^\d+').firstMatch(segment);
  if (match == null) return null;
  return int.tryParse(match.group(0)!);
}

class MangaSourceUpdates {
  MangaSourceUpdates._();

  /// Finds every installed JS source with a newer
  /// version available, sorted by display name.
  static Future<List<MangaSourceUpdate>> check({
    MangaTextFetcher fetch = dioMangaTextFetch,
  }) async {
    final byKey = <String, ({String version, String fileUrl})>{};
    for (final repo in MangaSources.sourceRepositories()) {
      final text = await fetch(repo);
      if (text == null) continue;
      final entries = MangaSources.parseVeneraIndex(text);
      if (entries == null) continue;
      final base = Uri.tryParse(repo);
      if (base == null) continue;
      for (final entry in entries) {
        if (entry.key.isEmpty || entry.version.isEmpty) continue;
        byKey[entry.key] = (
          version: entry.version,
          fileUrl: base.resolve(entry.fileName).toString(),
        );
      }
    }
    final updates = <MangaSourceUpdate>[];
    for (final source in MangaSources.installed()) {
      final hit = byKey[source.jsKey];
      if (hit != null) {
        if (isNewerMangaVersion(hit.version, source.version)) {
          updates.add(
            MangaSourceUpdate(
              jsKey: source.jsKey,
              name: source.displayName,
              installedVersion: source.version,
              latestVersion: hit.version,
              fileUrl: hit.fileUrl,
            ),
          );
        }
        continue;
      }
      final origin = MangaSources.originOfKey(source.jsKey);
      if (origin == null) continue;
      final text = await fetch(origin);
      if (text == null) continue;
      try {
        final meta = MangaSources.extractJsMetadata(text);
        if (meta.key != source.jsKey) continue;
        if (isNewerMangaVersion(meta.version, source.version)) {
          updates.add(
            MangaSourceUpdate(
              jsKey: source.jsKey,
              name: source.displayName,
              installedVersion: source.version,
              latestVersion: meta.version,
              fileUrl: origin,
            ),
          );
        }
      } catch (_) {
        // Not a readable source file — no verdict.
      }
    }
    updates.sort((a, b) => a.name.compareTo(b.name));
    return updates;
  }

  /// Downloads and installs each update (same-key
  /// overwrite through the validated installer, which
  /// also refreshes the recorded origin and clears the
  /// facade caches). Returns the success/failure counts.
  static Future<({int updated, int failed})> apply(
    List<MangaSourceUpdate> updates, {
    MangaTextFetcher fetch = dioMangaTextFetch,
  }) async {
    var updated = 0;
    var failed = 0;
    for (final update in updates) {
      try {
        final code = await fetch(update.fileUrl);
        if (code == null || code.trim().isEmpty) {
          failed++;
          continue;
        }
        await MangaSources.installCustomJs(
          code,
          fileName: update.fileUrl.split('/').last,
          origin: update.fileUrl,
        );
        updated++;
      } catch (_) {
        failed++;
      }
    }
    return (updated: updated, failed: failed);
  }
}
