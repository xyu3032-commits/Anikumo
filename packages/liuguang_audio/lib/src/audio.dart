import 'package:liuguang_models/liuguang_models.dart';
import 'package:liuguang_player_api/liuguang_player_api.dart';
import 'package:liuguang_storage/liuguang_storage.dart';

class ScoredAudioTrack {
  final AudioTrack track;
  final int score;
  final List<String> reasons;
  const ScoredAudioTrack(this.track, this.score, this.reasons);
}

class AudioTrackChoice {
  final AudioTrack? track;
  final int score;
  final List<String> reasons;
  final List<ScoredAudioTrack> ranked;
  const AudioTrackChoice({this.track, this.score = 0, this.reasons = const [], this.ranked = const []});
}

/// Deterministic audio-track selection policy.
///
/// Scoring (higher wins, ties keep the original list order):
/// - language preference: the earliest matching entry of
///   [languagePreferences] scores +(1000 - 100*index). Matching compares
///   primary subtags, so 'zh' matches 'zh-CN' and 'EN' matches 'en-US'.
/// - the track flagged default: +100
/// - forced tracks (label contains 'forced', e.g. forced-narrative dubs):
///   -400 — they are a fallback, not a main track
/// - channel count as a small tiebreak: +channels (unknown = 0)
class AudioTrackSelector {
  static String _primary(String lang) => lang.trim().toLowerCase().split(RegExp(r'[-_]')).first;
  static bool isForced(AudioTrack t) => t.label.toLowerCase().contains('forced');

  static List<ScoredAudioTrack> rank(List<AudioTrack> tracks, {List<String> languagePreferences = const []}) {
    final prefs = languagePreferences.map(_primary).toList();
    final scored = <ScoredAudioTrack>[];
    for (final t in tracks) {
      var score = 0;
      final reasons = <String>[];
      final langIdx = prefs.indexOf(_primary(t.language));
      if (langIdx >= 0) {
        score += 1000 - 100 * langIdx;
        reasons.add('language preference #${langIdx + 1} (${t.language})');
      }
      if (t.isDefault) { score += 100; reasons.add('default track'); }
      if (isForced(t)) { score -= 400; reasons.add('forced track deprioritized'); }
      if (t.channels != null && t.channels! > 0) { score += t.channels!; reasons.add('${t.channels} channels'); }
      if (reasons.isEmpty) reasons.add('no signals; list order applies');
      scored.add(ScoredAudioTrack(t, score, reasons));
    }
    // Stable sort by score desc (decorate with original index).
    final indexed = scored.asMap().entries.toList()
      ..sort((a, b) {
        final c = b.value.score.compareTo(a.value.score);
        return c != 0 ? c : a.key.compareTo(b.key);
      });
    return indexed.map((e) => e.value).toList();
  }

  static AudioTrackChoice select(List<AudioTrack> tracks, {List<String> languagePreferences = const []}) {
    if (tracks.isEmpty) return const AudioTrackChoice(reasons: ['no audio tracks available']);
    final ranked = rank(tracks, languagePreferences: languagePreferences);
    final top = ranked.first;
    return AudioTrackChoice(track: top.track, score: top.score, reasons: top.reasons, ranked: ranked);
  }
}

/// Per-(media, track) audio sync offsets, persisted via [StorageAdapter]
/// so a delay the user dialed in once is restored on the next play.
class AudioDelayStore {
  final StorageAdapter storage;
  static const table = 'audio_delays';
  AudioDelayStore(this.storage);
  String _key(String mediaId, String trackId) => '$mediaId::$trackId';
  Future<void> setDelay(String mediaId, String trackId, Duration delay) =>
      storage.put(table, _key(mediaId, trackId), {'mediaId': mediaId, 'trackId': trackId, 'delayMs': delay.inMilliseconds});
  Future<Duration> getDelay(String mediaId, String trackId) async {
    final j = await storage.get(table, _key(mediaId, trackId));
    if (j == null) return Duration.zero;
    return Duration(milliseconds: j['delayMs'] is num ? (j['delayMs'] as num).toInt() : 0);
  }
  Future<void> clearDelay(String mediaId, String trackId) => storage.delete(table, _key(mediaId, trackId));
  Future<void> clearForMedia(String mediaId) async {
    for (final row in await storage.all(table)) {
      if (row['mediaId']?.toString() == mediaId) {
        await storage.delete(table, _key(mediaId, row['trackId']?.toString() ?? ''));
      }
    }
  }
}

class AudioCapabilityView {
  final bool selectable;
  final String? disabledReason;
  const AudioCapabilityView({required this.selectable, this.disabledReason});
}

/// Pure capability logic for the UI layer: decides whether audio-track
/// switching should be offered or greyed out, and why.
/// The kernel's multiAudio capability wins over track count: a kernel
/// that cannot switch tracks disables selection even with many tracks.
AudioCapabilityView audioCapability(PlayerCapabilities caps, List<AudioTrack> tracks) {
  if (!caps.multiAudio) return const AudioCapabilityView(selectable: false, disabledReason: 'player kernel does not support multiple audio tracks');
  if (tracks.length <= 1) return const AudioCapabilityView(selectable: false, disabledReason: 'only one audio track available');
  return const AudioCapabilityView(selectable: true);
}

bool canSelectAudioTrack(PlayerCapabilities caps, List<AudioTrack> tracks) => audioCapability(caps, tracks).selectable;
