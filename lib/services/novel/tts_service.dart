import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

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

/// Batch 158: the read-aloud player (feature repository's
/// 语音朗读）. Drives the platform speech engine through the
/// novel_tts method channel: Dart keeps the chunk queue
/// and feeds one utterance at a time; the platform side
/// reports each finished utterance back, which advances
/// the queue. Pause is stop-and-resume-from-chunk (system
/// engines have no real pause), so a resumed chunk starts
/// from its beginning.
class TtsPlayer extends ChangeNotifier {
  TtsPlayer._() {
    _channel.setMethodCallHandler(_onPlatformCall);
  }

  static final TtsPlayer instance = TtsPlayer._();

  static const _channelName = 'com.anikumo.app/novel_tts';

  /// Visible for tests: the channel the player talks on.
  static const channel = MethodChannel(_channelName);

  MethodChannel get _channel => channel;

  bool speaking = false;
  bool paused = false;
  double rate = 1.0;
  int currentChunk = 0;
  int totalChunks = 0;

  /// Fired when the queue runs out (the reader hooks this
  /// to continue into the next chapter).
  void Function()? onQueueFinished;

  List<String> _queue = const [];
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
  /// chunking happens inside).
  Future<void> speakParagraphs(List<String> paragraphs) async {
    final chunks = <String>[
      for (final p in paragraphs) ...splitTextForSpeech(p),
    ];
    await stop();
    if (chunks.isEmpty) return;
    _session++;
    _queue = chunks;
    totalChunks = chunks.length;
    currentChunk = 0;
    speaking = true;
    paused = false;
    notifyListeners();
    await _speakCurrent();
  }

  Future<void> _speakCurrent() async {
    if (currentChunk >= _queue.length) return;
    _liveId = 'u$_session-$currentChunk-${++_gen}';
    try {
      await _channel.invokeMethod<void>('speak', {
        'text': _queue[currentChunk],
        'id': _liveId,
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
    } catch (_) {}
    notifyListeners();
  }
}
