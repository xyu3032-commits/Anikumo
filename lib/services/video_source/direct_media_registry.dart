import 'package:anikumo/services/video_source/video_source_format.dart';

/// Batch 208: registry of URLs that are already direct media
/// streams (a finished m3u8/mp4 address, not a web page).
///
/// The WebView resolver normally treats every episode URL as a
/// page to load and sniff. Zones whose sources hand out direct
/// stream URLs (the 影视 zone's interface sources) register them
/// here; [WebViewVideoSourceService.resolve] then returns the
/// URL untouched instead of paying a WebView round that could
/// never parse a playlist file as a page.
///
/// Anime episode page URLs are never registered, so the anime
/// resolve path is byte-for-byte unchanged.
class DirectMediaRegistry {
  DirectMediaRegistry._();

  static final Map<String, VideoSourceFormat> _entries = {};

  static void register(String url, {VideoSourceFormat? format}) {
    if (url.isEmpty) return;
    _entries[url] =
        format ??
        (url.toLowerCase().contains('.m3u8')
            ? VideoSourceFormat.hls
            : VideoSourceFormat.auto);
  }

  /// Batch 223: whether [url] points at a media file itself
  /// (a playlist or container file), as opposed to a
  /// playback PAGE. Several interface stations hand out
  /// `/share/<hash>` page links as their first play line —
  /// those are web pages that hand the real stream to a
  /// player embedded in them, not streams. Only true media
  /// URLs may skip the WebView resolver; page URLs must go
  /// through it like anime episode pages, or the player is
  /// handed an HTML page where a stream should be (the
  /// series/variety episode failures the user hit — movie
  /// lines more often carry a direct playlist, which is why
  /// they played).
  static bool isDirectMediaUrl(String url) {
    final path = Uri.tryParse(url)?.path.toLowerCase() ?? '';
    return path.endsWith('.m3u8') ||
        path.endsWith('.mp4') ||
        path.endsWith('.mkv') ||
        path.endsWith('.webm') ||
        path.endsWith('.mov') ||
        path.endsWith('.flv') ||
        path.endsWith('.mpd');
  }

  static void registerAll(Iterable<String> urls) {
    for (final url in urls) {
      register(url);
    }
  }

  static VideoSourceFormat? lookup(String url) => _entries[url];

  static bool get isEmpty => _entries.isEmpty;

  static void clear() => _entries.clear();
}
