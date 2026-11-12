/// Minimal M3U8 parsing used by the download engine: media-playlist
/// segment extraction. Master playlists and encrypted playlists are
/// detected so the engine can fail loudly instead of producing garbage.
class M3u8Playlist {
  final List<String> segmentUris;
  final bool isMaster;
  final bool hasEndList;
  final String? keyMethod;
  const M3u8Playlist({required this.segmentUris, required this.isMaster, required this.hasEndList, this.keyMethod});
  bool get isLive => !hasEndList;
  bool get isEncrypted => keyMethod != null && keyMethod != 'NONE';
}

M3u8Playlist parseM3u8(String text, {Uri? base}) {
  final lines = text.split('\n').map((l) => l.trim()).toList();
  var isMaster = false;
  var hasEndList = false;
  String? keyMethod;
  final segments = <String>[];
  var expectSegment = false;
  for (final line in lines) {
    if (line.isEmpty) continue;
    if (line.startsWith('#EXT-X-STREAM-INF')) { isMaster = true; continue; }
    if (line.startsWith('#EXT-X-ENDLIST')) { hasEndList = true; continue; }
    if (line.startsWith('#EXT-X-KEY:')) {
      final m = RegExp(r'METHOD=([^,]+)').firstMatch(line);
      if (m != null) keyMethod = m.group(1);
      continue;
    }
    if (line.startsWith('#EXTINF')) { expectSegment = true; continue; }
    if (line.startsWith('#')) continue;
    if (expectSegment || !isMaster) {
      segments.add(base == null ? line : base.resolve(line).toString());
      expectSegment = false;
    }
  }
  return M3u8Playlist(segmentUris: segments, isMaster: isMaster, hasEndList: hasEndList, keyMethod: keyMethod);
}
