import 'package:anikumo/services/liuguang/film_features.dart';
import 'package:anikumo/services/liuguang/film_probes.dart';
import 'dart:convert';

import 'package:liuguang_core/liuguang_core.dart';

import 'package:anikumo/services/liuguang/video_engine.dart';

/// Batch 207: film download bookkeeping on top of the
/// engine's DownloadManager. A task's id encodes everything
/// the downloads page needs to render and re-open the item:
/// id = 'lgf_' + base64url(JSON{mediaId, episodeId, title,
/// episodeTitle, line, episode}) without padding.

class FilmDownloadRef {
  const FilmDownloadRef({
    required this.mediaId,
    required this.episodeId,
    required this.title,
    required this.episodeTitle,
    required this.lineIndex,
    required this.episodeIndex,
  });

  final String mediaId;
  final String episodeId;
  final String title;
  final String episodeTitle;
  final int lineIndex;
  final int episodeIndex;
}

String encodeFilmDownloadId(FilmDownloadRef ref) {
  final payload = jsonEncode({
    'm': ref.mediaId,
    'e': ref.episodeId,
    't': ref.title,
    'et': ref.episodeTitle,
    'l': ref.lineIndex,
    'n': ref.episodeIndex,
  });
  return 'lgf_${base64Url.encode(utf8.encode(payload)).replaceAll('=', '')}';
}

FilmDownloadRef? decodeFilmDownloadId(String id) {
  if (!id.startsWith('lgf_')) return null;
  try {
    var body = id.substring(4);
    while (body.length % 4 != 0) {
      body += '=';
    }
    final map = jsonDecode(utf8.decode(base64Url.decode(body)));
    if (map is! Map) return null;
    return FilmDownloadRef(
      mediaId: map['m']?.toString() ?? '',
      episodeId: map['e']?.toString() ?? '',
      title: map['t']?.toString() ?? '',
      episodeTitle: map['et']?.toString() ?? '',
      lineIndex: map['l'] is num ? (map['l'] as num).toInt() : 0,
      episodeIndex: map['n'] is num ? (map['n'] as num).toInt() : 0,
    );
  } catch (_) {
    return null;
  }
}

String _sanitizeFilePart(String raw) {
  final cleaned = raw.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
  return cleaned.isEmpty ? 'video' : cleaned;
}

/// Resolves the episode's playback address and enqueues a
/// download task for it. Returns true when a new task was
/// created (an identical task id is left as-is by the
/// manager's enqueue semantics — callers check existence
/// first when they care).
Future<bool> enqueueFilmDownload({
  required MediaItem item,
  required int lineIndex,
  required Episode episode,
  required int episodeIndex,
}) async {
  final service = VideoEngineService.instance;
  final engine = await service.engine();
  final sources = await engine.getPlaybackSources(
    PlaybackQuery(mediaId: item.id, episodeId: episode.id),
  );
  // Prefer the requested line's own source; the source list
  // is ordered primary-first by the provider.
  VideoSource? chosen;
  for (final s in sources) {
    if (s.id.endsWith('::$lineIndex::$episodeIndex')) {
      chosen = s;
      break;
    }
  }
  chosen ??= sources.isEmpty ? null : sources.first;
  if (chosen == null) return false;
  // Batch 232 （下载省空间 pack): with several lines to
  // pick from, probe each candidate's weight and take the
  // slimmest — a master playlist's slimmest variant also
  // replaces the download URL. Unknown weights keep the
  // requested line's own source.
  var downloadUrl = chosen.url;
  if (FilmFeatures.isInstalled(FilmFeatures.downloadSlimId) &&
      sources.length > 1) {
    final hints = <String, int?>{};
    final overrides = <String, String>{};
    for (final s in sources) {
      final probe = await probeSizeHint(s);
      hints[s.id] = probe.hint;
      if (probe.urlOverride != null) overrides[s.id] = probe.urlOverride!;
    }
    final slim = pickSlimmestSource(sources, hints, chosen);
    downloadUrl = overrides[slim.id] ?? slim.url;
    chosen = slim;
  }
  final manager = await service.downloads();
  final ref = FilmDownloadRef(
    mediaId: item.id,
    episodeId: episode.id,
    title: item.title,
    episodeTitle: episode.title,
    lineIndex: lineIndex,
    episodeIndex: episodeIndex,
  );
  final id = encodeFilmDownloadId(ref);
  if (manager.task(id) != null) return false;
  final dir = await service.downloadsDirectory();
  final fileName =
      '${_sanitizeFilePart(item.title)}_${_sanitizeFilePart(episode.title)}.mp4';
  await manager.enqueue(
    url: downloadUrl,
    targetPath: '${dir.path}/$fileName',
    headers: chosen.headers,
    id: id,
  );
  await manager.start(id);
  return true;
}
