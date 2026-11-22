import 'dart:async';

import 'package:speech_to_text/speech_to_text.dart';

import 'package:anikumo/services/logging/logger.dart';

/// Batch 284 (#18): voice search input.
///
/// Wraps the platform speech recognizer. Everything is
/// failure-silent: a device without a recognizer, without
/// permission or on an unsupported platform (desktop)
/// reports unavailable, and the search page simply never
/// shows the microphone button — no dead entry anywhere.

/// Picks the recognition locale from the recognizer's
/// locale ids: simplified Chinese first, then any other
/// Chinese variant, then whatever the recognizer lists
/// first. Pure, so the preference order is testable.
String? pickVoiceLocale(List<String> localeIds) {
  if (localeIds.isEmpty) return null;
  String normalize(String id) => id.replaceAll('-', '_').toLowerCase();
  for (final id in localeIds) {
    final n = normalize(id);
    if (n == 'zh_cn' || n.startsWith('zh_hans')) return id;
  }
  for (final id in localeIds) {
    if (normalize(id).startsWith('zh')) return id;
  }
  return localeIds.first;
}

class VoiceSearchService {
  VoiceSearchService._();

  static final VoiceSearchService instance = VoiceSearchService._();

  final SpeechToText _speech = SpeechToText();
  bool? _available;
  String? _localeId;

  /// Fired when the recognizer stops on its own (silence
  /// timeout, error, or a finished utterance).
  void Function()? onListeningDone;

  /// True when this device can take voice input right
  /// now. The answer is probed once and cached; any
  /// failure along the way means "unavailable".
  Future<bool> isAvailable() async {
    final cached = _available;
    if (cached != null) return cached;
    try {
      final ok = await _speech.initialize(
        onStatus: (status) {
          if (status == SpeechToText.doneStatus ||
              status == SpeechToText.notListeningStatus) {
            onListeningDone?.call();
          }
        },
        onError: (_) {},
      );
      if (!ok) return _available = false;
      try {
        final locales = await _speech.locales();
        _localeId = pickVoiceLocale([for (final l in locales) l.localeId]);
      } catch (_) {
        _localeId = null;
      }
      return _available = true;
    } catch (e) {
      AnikumoLogger().w('VoiceSearch: initialize failed', error: e);
      return _available = false;
    }
  }

  bool get isListening => _speech.isListening;

  /// Starts a dictation session; [onResult] receives the
  /// live transcript and whether it is final.
  Future<void> startListening({
    required void Function(String words, bool isFinal) onResult,
  }) async {
    if (!await isAvailable()) return;
    try {
      await _speech.listen(
        onResult: (result) =>
            onResult(result.recognizedWords, result.finalResult),
        listenOptions: SpeechListenOptions(
          partialResults: true,
          listenMode: ListenMode.dictation,
          localeId: _localeId,
          cancelOnError: true,
          pauseFor: const Duration(seconds: 3),
          listenFor: const Duration(seconds: 30),
        ),
      );
    } catch (e) {
      AnikumoLogger().w('VoiceSearch: listen failed', error: e);
      onListeningDone?.call();
    }
  }

  Future<void> stopListening() async {
    try {
      await _speech.stop();
    } catch (_) {}
  }

  Future<void> cancelListening() async {
    try {
      await _speech.cancel();
    } catch (_) {}
  }
}
