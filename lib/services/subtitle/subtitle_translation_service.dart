import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:anikumo/services/subtitle/subtitle_document.dart';
import 'package:anikumo/services/subtitle/subtitle_translator.dart';

/// Batch 278: why a file translation stopped, in terms
/// the subtitle sheet can phrase for the user.
enum SubtitleTranslationFailure {
  /// The source already reads as Chinese.
  alreadyChinese,

  /// No cues could be parsed out of the file.
  emptyDocument,

  /// The translator itself failed (model download,
  /// platform, unsupported language...).
  translatorFailed,
}

class SubtitleTranslationException implements Exception {
  const SubtitleTranslationException(this.failure, [this.cause]);

  final SubtitleTranslationFailure failure;
  final Object? cause;

  @override
  String toString() => 'SubtitleTranslationException($failure, $cause)';
}

/// Batch 278: whole-file subtitle machine translation.
///
/// Parses an external subtitle file, translates every
/// cue into Chinese through the injected
/// [SubtitleTranslator], and writes the result as SRT.
/// The timeline is never touched — only cue text is
/// replaced — and the output is cached under the SHA-256
/// of the source bytes, so reopening the same file later
/// (or re-picking it after an app restart) costs no
/// translation at all.
class SubtitleTranslationService {
  SubtitleTranslationService({
    required this.translator,
    Future<Directory> Function()? cacheDirectory,
  }) : _cacheDirectory = cacheDirectory ?? _defaultCacheDirectory;

  final SubtitleTranslator translator;
  final Future<Directory> Function() _cacheDirectory;

  static Future<Directory> _defaultCacheDirectory() async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory(p.join(support.path, 'subtitle_translations'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// The cache key a source file's bytes map to.
  static String cacheKeyForBytes(List<int> bytes) =>
      sha256.convert(bytes).toString();

  /// The file a completed translation of [bytes] lives
  /// at inside [cacheDir] — present only after a
  /// successful run.
  static File cacheFileFor(Directory cacheDir, List<int> bytes) =>
      File(p.join(cacheDir.path, '${cacheKeyForBytes(bytes)}.zh.srt'));

  /// Translates [source] end to end and returns the SRT
  /// file to mount. [onProgress] reports (done, total)
  /// cue counts as translation advances; a cache hit
  /// returns immediately without progress calls.
  ///
  /// Throws [SubtitleTranslationException] for the
  /// expected failure modes; anything else propagates.
  Future<File> translateFile(
    File source, {
    void Function(int done, int total)? onProgress,
  }) async {
    final bytes = await source.readAsBytes();
    final cacheDir = await _cacheDirectory();
    final cached = cacheFileFor(cacheDir, bytes);
    if (await cached.exists() && await cached.length() > 0) {
      return cached;
    }

    final content = decodeSubtitleBytes(bytes);
    final format = p.extension(source.path).replaceAll('.', '');
    final cues = parseSubtitleDocument(format, content);
    if (cues.isEmpty) {
      throw const SubtitleTranslationException(
        SubtitleTranslationFailure.emptyDocument,
      );
    }

    final sample = StringBuffer();
    for (final cue in cues) {
      sample.write(stripSubtitleMarkup(cue.text));
      sample.write('\n');
      if (sample.length > 6000) break;
    }
    final detected = detectSubtitleLanguage(sample.toString());
    if (detected == 'zh') {
      throw const SubtitleTranslationException(
        SubtitleTranslationFailure.alreadyChinese,
      );
    }
    // Unidentified samples still get a judgement call at
    // tap time: English is the safest default source.
    final sourceLanguage = detected ?? 'en';

    final translatedByText = <String, String>{};
    final out = <SubtitleCue>[];
    var done = 0;
    try {
      for (final cue in cues) {
        final plain = stripSubtitleMarkup(cue.text);
        if (!hasTranslatableText(plain)) {
          out.add(cue.copyWithText(plain));
        } else {
          var translated = translatedByText[plain];
          if (translated == null) {
            translated = await translator.translate(
              plain,
              sourceLanguage: sourceLanguage,
            );
            translatedByText[plain] = translated;
          }
          out.add(cue.copyWithText(translated.trim()));
        }
        done++;
        onProgress?.call(done, cues.length);
      }
    } catch (e) {
      throw SubtitleTranslationException(
        SubtitleTranslationFailure.translatorFailed,
        e,
      );
    }

    await cached.writeAsString(serializeSrt(out));
    return cached;
  }
}
