import 'dart:async';

import 'package:flutter/material.dart';

import 'package:anikumo/pages/player/player_controller.dart';
import 'package:anikumo/services/logging/logger.dart';
import 'package:anikumo/services/subtitle/subtitle_document.dart';
import 'package:anikumo/services/subtitle/subtitle_translator.dart';

/// Batch 278: the live machine-translation overlay —
/// one translated line under the video while the
/// feature is switched on in the subtitle sheet.
///
/// Feasibility note: the pinned media_kit fork's
/// NativePlayer already observes mpv's `sub-text`
/// property and republishes it as `Player.stream
/// .subtitle` (state.subtitle[0]), so no extra property
/// plumbing was needed — this widget consumes that
/// stream, machine-translates each new primary line on
/// device, and paints the result. Lines detected as
/// Chinese (or symbol-only) show nothing. Every failure
/// is swallowed: a translation hiccup must never
/// disturb playback.
class LiveTranslateOverlay extends StatefulWidget {
  const LiveTranslateOverlay({
    super.key,
    required this.playerController,
    this.translator,
  });

  final PlayerController playerController;

  /// Test seam; production leaves this null and gets the
  /// ML Kit translator, created lazily on first use.
  final SubtitleTranslator? translator;

  @override
  State<LiveTranslateOverlay> createState() => _LiveTranslateOverlayState();
}

class _LiveTranslateOverlayState extends State<LiveTranslateOverlay> {
  SubtitleTranslator? _translator;
  bool _ownsTranslator = false;

  String _sourceLine = '';
  String _translatedLine = '';
  int _requestSeq = 0;
  final Map<String, String> _lineCache = {};

  SubtitleTranslator get _activeTranslator {
    final injected = widget.translator;
    if (injected != null) return injected;
    _ownsTranslator = true;
    return _translator ??= MlKitSubtitleTranslator();
  }

  @override
  void dispose() {
    if (_ownsTranslator) {
      unawaited(_translator?.close() ?? Future<void>.value());
    }
    super.dispose();
  }

  void _onSubtitleLines(List<String> lines) {
    if (!mounted) return;
    final raw = lines.isEmpty ? '' : lines.first;
    final plain = stripSubtitleMarkup(raw.replaceAll('\n', ' '));
    if (plain == _sourceLine) return;
    _sourceLine = plain;
    final seq = ++_requestSeq;
    if (plain.isEmpty || !hasTranslatableText(plain)) {
      if (_translatedLine.isNotEmpty) {
        setState(() => _translatedLine = '');
      }
      return;
    }
    final cached = _lineCache[plain];
    if (cached != null) {
      setState(() => _translatedLine = cached);
      return;
    }
    final detected = detectSubtitleLanguage(plain, minLetters: 1);
    if (detected == 'zh') {
      if (_translatedLine.isNotEmpty) {
        setState(() => _translatedLine = '');
      }
      return;
    }
    unawaited(_translate(plain, detected ?? 'en', seq));
  }

  Future<void> _translate(String plain, String source, int seq) async {
    try {
      final result =
          await _activeTranslator.translate(plain, sourceLanguage: source);
      if (!mounted || seq != _requestSeq) return;
      final trimmed = result.trim();
      if (_lineCache.length > 200) _lineCache.clear();
      _lineCache[plain] = trimmed;
      setState(() => _translatedLine = trimmed);
    } catch (e) {
      // Silent by design — playback first.
      AnikumoLogger().w('LiveTranslate: line failed', error: e);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!subtitleTranslationSupported && widget.translator == null) {
      return const SizedBox.shrink();
    }
    return ValueListenableBuilder<bool>(
      valueListenable: widget.playerController.liveTranslateEnabled,
      builder: (context, enabled, _) {
        if (!enabled) return const SizedBox.shrink();
        final player = widget.playerController.playback.mediaPlayer;
        if (player == null) return const SizedBox.shrink();
        return StreamBuilder<List<String>>(
          stream: player.stream.subtitle,
          builder: (context, snapshot) {
            final lines = snapshot.data ?? player.state.subtitle;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _onSubtitleLines(lines);
            });
            if (_translatedLine.isEmpty) {
              return const SizedBox.shrink();
            }
            return Positioned(
              left: 32,
              right: 32,
              bottom: 88,
              child: IgnorePointer(
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.62),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _translatedLine,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        height: 1.35,
                        shadows: [
                          Shadow(color: Colors.black, blurRadius: 4),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
