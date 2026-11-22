import 'dart:io';

import 'package:google_mlkit_translation/google_mlkit_translation.dart';

import 'package:anikumo/services/logging/logger.dart';

/// Batch 278: the translator seam for subtitle machine
/// translation.
///
/// The pipeline (file translation service, live overlay)
/// only ever talks to this interface, so tests drive it
/// with a fake and the ML Kit binding stays in one place.
/// Languages are the detector's ISO codes ('ja', 'en',
/// 'ko', ...); the target is always Chinese — that is
/// the feature as specced.
abstract interface class SubtitleTranslator {
  /// Translates one line/block of [text] from
  /// [sourceLanguage] (a [detectSubtitleLanguage] code)
  /// into Chinese. Throws on any failure; callers degrade
  /// silently.
  Future<String> translate(String text, {required String sourceLanguage});

  /// Releases native resources held by this translator.
  Future<void> close();
}

/// Whether on-device translation can run at all on this
/// platform. ML Kit translation ships Android/iOS only;
/// on desktop (and anywhere the plugin is missing) the
/// subtitle sheet hides its translation entries instead
/// of showing dead buttons.
bool get subtitleTranslationSupported =>
    Platform.isAndroid || Platform.isIOS;

/// Maps a detector language code onto the ML Kit enum;
/// null when ML Kit has no model for it.
TranslateLanguage? mlKitLanguageFor(String code) {
  return switch (code) {
    'en' => TranslateLanguage.english,
    'ja' => TranslateLanguage.japanese,
    'ko' => TranslateLanguage.korean,
    'ru' => TranslateLanguage.russian,
    'fr' => TranslateLanguage.french,
    'de' => TranslateLanguage.german,
    'es' => TranslateLanguage.spanish,
    'pt' => TranslateLanguage.portuguese,
    'it' => TranslateLanguage.italian,
    'ar' => TranslateLanguage.arabic,
    'zh' => TranslateLanguage.chinese,
    _ => null,
  };
}

/// ML Kit-backed [SubtitleTranslator]. One
/// [OnDeviceTranslator] per source language, created
/// lazily and reused; the language models are downloaded
/// on first use (they are ~30 MB per language and ML Kit
/// keeps them on the device afterwards).
class MlKitSubtitleTranslator implements SubtitleTranslator {
  final Map<String, OnDeviceTranslator> _translators = {};
  final Set<String> _modelsReady = {};
  final OnDeviceTranslatorModelManager _modelManager =
      OnDeviceTranslatorModelManager();

  Future<OnDeviceTranslator> _forSource(String sourceLanguage) async {
    final cached = _translators[sourceLanguage];
    if (cached != null) return cached;
    final source = mlKitLanguageFor(sourceLanguage);
    if (source == null) {
      throw UnsupportedError('No on-device model for $sourceLanguage');
    }
    if (!_modelsReady.contains(sourceLanguage)) {
      await _ensureModel(source.bcpCode);
      await _ensureModel(TranslateLanguage.chinese.bcpCode);
      _modelsReady.add(sourceLanguage);
    }
    final translator = OnDeviceTranslator(
      sourceLanguage: source,
      targetLanguage: TranslateLanguage.chinese,
    );
    _translators[sourceLanguage] = translator;
    return translator;
  }

  Future<void> _ensureModel(String bcpCode) async {
    try {
      if (await _modelManager.isModelDownloaded(bcpCode)) return;
      await _modelManager.downloadModel(bcpCode, isWifiRequired: false);
    } catch (e) {
      AnikumoLogger().w('SubtitleTranslate: model fetch failed', error: e);
      rethrow;
    }
  }

  @override
  Future<String> translate(
    String text, {
    required String sourceLanguage,
  }) async {
    final translator = await _forSource(sourceLanguage);
    return translator.translateText(text);
  }

  @override
  Future<void> close() async {
    for (final translator in _translators.values) {
      try {
        await translator.close();
      } catch (_) {
        // Already gone natively; nothing to release.
      }
    }
    _translators.clear();
  }
}
