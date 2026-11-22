import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:anikumo/services/storage/settings_keys.dart';
import 'package:anikumo/services/storage/storage.dart';

/// Batch 158: speech chunking for chapter text. System
/// speech engines cap one utterance (around 4000 chars on
/// Android) and very long single paragraphs also stall the
/// progress callbacks, so paragraphs are split at sentence
/// boundaries into chunks of at most [maxLen]; a single
/// over-long sentence is hard-split as a last resort.
List<String> splitTextForSpeech(String text, {int maxLen = 500}) {
  final out = <String>[];
  void addPiece(String piece) {
    var rest = piece.trim();
    while (rest.length > maxLen) {
      var cut = -1;
      for (final sep in ['。', '！', '？', '；', '…', '!', '?', ';']) {
        final idx = rest.lastIndexOf(sep, maxLen);
        if (idx > cut) cut = idx;
      }
      if (cut < maxLen ~/ 3) cut = maxLen;
      out.add(rest.substring(0, cut + 1).trim());
      rest = rest.substring(cut + 1).trim();
    }
    if (rest.isNotEmpty) out.add(rest);
  }

  for (final paragraph in text.split(RegExp(r'\n+'))) {
    if (paragraph.trim().isEmpty) continue;
    // Split the paragraph into sentences, then pack them.
    final sentences = <String>[];
    final buf = StringBuffer();
    for (var i = 0; i < paragraph.length; i++) {
      buf.write(paragraph[i]);
      if ('。！？；…!?;'.contains(paragraph[i])) {
        sentences.add(buf.toString());
        buf.clear();
      }
    }
    if (buf.isNotEmpty) sentences.add(buf.toString());
    var current = '';
    for (final s in sentences) {
      if (current.isNotEmpty && current.length + s.length > maxLen) {
        addPiece(current);
        current = '';
      }
      current += s;
    }
    if (current.isNotEmpty) addPiece(current);
  }
  return out;
}

/// Batch 280 (#14): one span of speech text — narration
/// or dialogue. [text] keeps the quote marks, so joining
/// the segments reproduces the input exactly.
class SpeechSegment {
  const SpeechSegment(this.text, {this.dialogue = false});

  final String text;
  final bool dialogue;

  @override
  bool operator ==(Object other) =>
      other is SpeechSegment &&
      other.text == text &&
      other.dialogue == dialogue;

  @override
  int get hashCode => Object.hash(text, dialogue);
}

/// Quote pairs the segmenter recognises: corner brackets,
/// fullwidth curly quotes, straight double quotes and
/// single curly quotes. A straight " opens and closes
/// with itself, handled by the stack logic below.
const _speechQuotePairs = <String, String>{
  '「': '」',
  '『': '』',
  '“': '”',
  '‘': '’',
  '"': '"',
};

/// Batch 280 (#14): split [text] into narration / dialogue
/// spans for multi-voice reading. Text inside the
/// outermost quote pair is dialogue; quotes nested inside
/// dialogue stay dialogue. An unclosed quote makes the
/// whole input narration — half-split dialogue would read
/// worse than none. Adjacent same-kind spans merge and
/// empty spans drop, so the output is the minimal span
/// list whose texts join back to [text].
List<SpeechSegment> segmentSpeechText(String text) {
  if (text.isEmpty) return const [];
  final stack = <String>[]; // Expected closers, innermost last.
  final out = <SpeechSegment>[];
  final buf = StringBuffer();
  var dialogue = false;

  void flush() {
    if (buf.isEmpty) return;
    final piece = buf.toString();
    buf.clear();
    if (out.isNotEmpty && out.last.dialogue == dialogue) {
      out[out.length - 1] = SpeechSegment(
        out.last.text + piece,
        dialogue: dialogue,
      );
    } else {
      out.add(SpeechSegment(piece, dialogue: dialogue));
    }
  }

  for (var i = 0; i < text.length; i++) {
    final ch = text[i];
    if (stack.isNotEmpty && ch == stack.last) {
      // A closer: part of the current span; the span kind
      // flips only when the outermost pair closes.
      buf.write(ch);
      stack.removeLast();
      if (stack.isEmpty) {
        flush();
        dialogue = false;
      }
      continue;
    }
    final closer = _speechQuotePairs[ch];
    if (closer != null && !(ch == '"' && stack.isNotEmpty)) {
      // An opener: at depth 0 it starts a dialogue span.
      if (stack.isEmpty) {
        flush();
        dialogue = true;
      }
      buf.write(ch);
      stack.add(closer);
      continue;
    }
    buf.write(ch);
  }
  if (stack.isNotEmpty) {
    // Unclosed quote: read it all as narration.
    return [SpeechSegment(text)];
  }
  flush();
  return out;
}

/// Batch 158: the read-aloud player (feature repository's
/// 语音朗读）. Drives the platform speech engine through the
/// novel_tts method channel: Dart keeps the chunk queue
/// and feeds one utterance at a time; the platform side
/// reports each finished utterance back, which advances
/// the queue. Pause is stop-and-resume-from-chunk (system
/// engines have no real pause), so a resumed chunk starts
/// from its beginning.
/// Batch 280 (#14): one queued utterance — a speech
/// chunk plus whether it is dialogue (read in the second
/// voice while multi-voice reading is on).
class _Utterance {
  const _Utterance(this.text, {this.dialogue = false});

  final String text;
  final bool dialogue;
}

class TtsPlayer extends ChangeNotifier {
  TtsPlayer._() {
    _channel.setMethodCallHandler(_onPlatformCall);
    // Batch 270: restore persisted rate / pitch / voice.
    // Storage may be unavailable in tests that merely touch
    // the singleton — defaults then apply.
    try {
      rate = GStorage.getSetting(SettingsKeys.novelTtsRate);
      pitch = GStorage.getSetting(SettingsKeys.novelTtsPitch);
      voiceName = GStorage.getSetting(SettingsKeys.novelTtsVoice);
      multiVoice = GStorage.getSetting(SettingsKeys.novelTtsMultiVoice);
    } catch (_) {
      // Keep the field defaults.
    }
  }

  static final TtsPlayer instance = TtsPlayer._();

  static const _channelName = 'com.anikumo.app/novel_tts';

  /// Visible for tests: the channel the player talks on.
  static const channel = MethodChannel(_channelName);

  MethodChannel get _channel => channel;

  bool speaking = false;
  bool paused = false;
  double rate = 1.0;

  /// Batch 270: pitch (0.5–2.0) and voice, persisted like
  /// the rate. [voiceName] '' means the engine default.
  double pitch = 1.0;
  String voiceName = '';

  /// Batch 280 (#14): dialogue lines are read in a second
  /// voice (the platform picks another engine voice, or
  /// falls back to [dialoguePitch] when it has only one).
  bool multiVoice = false;

  /// The pitch dialogue is read at when the engine has no
  /// second voice: the narration pitch shifted up 15%.
  double get dialoguePitch => (pitch * 1.15).clamp(0.5, 2.0);

  int currentChunk = 0;
  int totalChunks = 0;

  /// Fired when the queue runs out (the reader hooks this
  /// to continue into the next chapter).
  void Function()? onQueueFinished;

  List<_Utterance> _queue = const [];
  var _session = 0;

  /// Generation of the live utterance: a stopped utterance
  /// can still report back after a resume re-speaks the
  /// same chunk, and only the newest id may advance the
  /// queue.
  var _gen = 0;
  String _liveId = '';

  static Future<bool> isAvailable() async {
    try {
      final ok = await channel.invokeMethod<bool>('isAvailable');
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<dynamic> _onPlatformCall(MethodCall call) async {
    if (call.method == 'onUtteranceDone' ||
        call.method == 'onUtteranceError') {
      final id = call.arguments?.toString() ?? '';
      if (!speaking || paused) return null;
      if (id != _liveId) return null;
      currentChunk++;
      if (currentChunk >= _queue.length) {
        final finished = onQueueFinished;
        _reset();
        notifyListeners();
        finished?.call();
        return null;
      }
      notifyListeners();
      await _speakCurrent();
    }
    return null;
  }

  void _reset() {
    speaking = false;
    paused = false;
    currentChunk = 0;
    totalChunks = 0;
    _queue = const [];
  }

  /// Start reading [paragraphs] (raw chapter paragraphs;
  /// chunking happens inside). With multi-voice reading
  /// on, each paragraph is first split into narration /
  /// dialogue spans (batch 280) and the spans are chunked
  /// separately, so an utterance never mixes the two.
  Future<void> speakParagraphs(List<String> paragraphs) async {
    final utterances = <_Utterance>[];
    for (final p in paragraphs) {
      if (multiVoice) {
        for (final segment in segmentSpeechText(p)) {
          for (final chunk in splitTextForSpeech(segment.text)) {
            utterances.add(_Utterance(chunk, dialogue: segment.dialogue));
          }
        }
      } else {
        for (final chunk in splitTextForSpeech(p)) {
          utterances.add(_Utterance(chunk));
        }
      }
    }
    await stop();
    if (utterances.isEmpty) return;
    _session++;
    _queue = utterances;
    totalChunks = utterances.length;
    currentChunk = 0;
    speaking = true;
    paused = false;
    notifyListeners();
    await _speakCurrent();
  }

  Future<void> _speakCurrent() async {
    if (currentChunk >= _queue.length) return;
    _liveId = 'u$_session-$currentChunk-${++_gen}';
    final utterance = _queue[currentChunk];
    try {
      await _channel.invokeMethod<void>('speak', {
        'text': utterance.text,
        'id': _liveId,
        // Batch 280 (#14): dialogue utterances ask the
        // platform for its alternate voice; the pitch is
        // the fallback for single-voice engines.
        if (utterance.dialogue) 'altVoice': true,
        if (utterance.dialogue) 'pitch': dialoguePitch,
      });
    } catch (_) {
      // Engine vanished mid-chapter: end the session
      // quietly rather than wedging the reader controls.
      _reset();
      notifyListeners();
    }
  }

  Future<void> pause() async {
    if (!speaking || paused) return;
    paused = true;
    try {
      await _channel.invokeMethod<void>('stop');
    } catch (_) {}
    notifyListeners();
  }

  Future<void> resume() async {
    if (!speaking || !paused) return;
    paused = false;
    notifyListeners();
    await _speakCurrent();
  }

  Future<void> stop() async {
    if (!speaking && !paused) return;
    _session++;
    _reset();
    try {
      await _channel.invokeMethod<void>('stop');
    } catch (_) {}
    notifyListeners();
  }

  Future<void> setRate(double value) async {
    rate = value.clamp(0.5, 2.0);
    try {
      await _channel.invokeMethod<void>('setRate', {'rate': rate});
      await GStorage.putSetting(SettingsKeys.novelTtsRate, rate);
    } catch (_) {}
    notifyListeners();
  }

  /// Batch 270: the rate remembered for one book, if any.
  static double? rateForBook(String storageKey) {
    try {
      final raw = GStorage.getSetting(SettingsKeys.novelTtsRateByBookJson);
      if (raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is Map && decoded[storageKey] is num) {
        return (decoded[storageKey] as num).toDouble().clamp(0.5, 2.0);
      }
    } catch (_) {}
    return null;
  }

  /// Remembers [value] as the rate for one book (the global
  /// rate is updated too, via [setRate]).
  Future<void> setRateForBook(String storageKey, double value) async {
    await setRate(value);
    try {
      final raw = GStorage.getSetting(SettingsKeys.novelTtsRateByBookJson);
      final map = <String, dynamic>{};
      if (raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) map.addAll(decoded.cast<String, dynamic>());
      }
      map[storageKey] = rate;
      await GStorage.putSetting(
        SettingsKeys.novelTtsRateByBookJson,
        jsonEncode(map),
      );
    } catch (_) {}
  }

  Future<void> setPitch(double value) async {
    pitch = value.clamp(0.5, 2.0);
    try {
      await _channel.invokeMethod<void>('setPitch', {'pitch': pitch});
      await GStorage.putSetting(SettingsKeys.novelTtsPitch, pitch);
    } catch (_) {}
    notifyListeners();
  }

  /// Available engine voices as {name, locale} maps. Empty
  /// on platforms/engines that cannot enumerate them.
  Future<List<Map<String, String>>> fetchVoices() async {
    try {
      final raw = await _channel.invokeMethod<List<dynamic>>('getVoices');
      return [
        for (final entry in raw ?? const [])
          if (entry is Map)
            {
              'name': '${entry['name'] ?? ''}',
              'locale': '${entry['locale'] ?? ''}',
            },
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<void> setVoice(String name) async {
    voiceName = name;
    try {
      await _channel.invokeMethod<void>('setVoice', {'name': name});
      await GStorage.putSetting(SettingsKeys.novelTtsVoice, name);
    } catch (_) {}
    notifyListeners();
  }

  /// Batch 280 (#14): toggle multi-voice reading. Takes
  /// effect from the next speakParagraphs call; a session
  /// already playing keeps the queue it started with.
  Future<void> setMultiVoice(bool value) async {
    multiVoice = value;
    try {
      await GStorage.putSetting(SettingsKeys.novelTtsMultiVoice, value);
    } catch (_) {}
    notifyListeners();
  }

  /// Batch 270: push the persisted rate/pitch/voice to the
  /// engine. Called when a reading session starts; the
  /// platform side also keeps the last values and applies
  /// them when its engine finishes initializing.
  Future<void> applySettings() async {
    try {
      await _channel.invokeMethod<void>('setRate', {'rate': rate});
      await _channel.invokeMethod<void>('setPitch', {'pitch': pitch});
      if (voiceName.isNotEmpty) {
        await _channel.invokeMethod<void>('setVoice', {'name': voiceName});
      }
    } catch (_) {}
  }

  /// Batch 270: jump [delta] chunks (media-button next /
  /// previous while listening). Re-speaks from the target
  /// chunk, like resume does.
  Future<void> skipBy(int delta) async {
    if (!speaking || _queue.isEmpty) return;
    final target =
        (currentChunk + delta).clamp(0, _queue.length - 1).toInt();
    if (target == currentChunk && !paused) return;
    currentChunk = target;
    paused = false;
    try {
      await _channel.invokeMethod<void>('stop');
    } catch (_) {}
    notifyListeners();
    await _speakCurrent();
  }
}
