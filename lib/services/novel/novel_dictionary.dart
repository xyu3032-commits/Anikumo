import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

/// Batch 280 (#12): the offline dictionary behind the
/// novel reader's look-up panel (long-press a paragraph,
/// tap a word or character).
///
/// Data: a trimmed extract of the chinese-xinhua dataset
/// (https://github.com/pwxcoo/chinese-xinhua, MIT License,
/// © PWXCOO) — its single-character table (word.json) and
/// idiom table (idiom.json), reduced to
/// {word: [pinyin, explanation]} with citation lines and
/// etymology notes stripped and explanations capped, then
/// gzipped into assets/novel/dictionary.json.gz
/// (14,809 characters + 30,895 idioms, ~2.1 MB). Lookup is
/// fully offline; nothing is fetched at runtime.
class DictEntry {
  const DictEntry({
    required this.word,
    required this.pinyin,
    required this.explanation,
  });

  final String word;
  final String pinyin;
  final String explanation;
}

/// The outcome of one look-up: the whole-word (or whole-
/// character) entry when the dictionary has one, plus the
/// per-character entries — the fallback the panel shows
/// when no whole-word entry exists.
class DictLookup {
  const DictLookup({this.entry, this.charEntries = const []});

  final DictEntry? entry;
  final List<DictEntry> charEntries;

  bool get found => entry != null || charEntries.isNotEmpty;
}

/// Pure look-up over already-parsed tables: an exact hit
/// wins (the word table for 2+ characters, the character
/// table for a single character); every character of the
/// query that has its own entry rides along as the
/// per-character fallback.
DictLookup resolveDictLookup({
  required Map<String, DictEntry> words,
  required Map<String, DictEntry> chars,
  required String query,
}) {
  final q = query.trim();
  if (q.isEmpty) return const DictLookup();
  final entry = q.length == 1 ? chars[q] : (words[q] ?? chars[q]);
  final seen = <String>{};
  return DictLookup(
    entry: entry,
    charEntries: [
      if (q.length > 1)
        for (final ch in q.split(''))
          if (seen.add(ch) && chars[ch] != null) chars[ch]!,
    ],
  );
}

/// Greedy longest-match segmentation of [text] against
/// the word table (via [hasWord]): the chips the look-up
/// panel offers. Characters no word covers become single-
/// character segments, so every character stays tappable.
List<String> segmentTextForLookup(
  String text,
  bool Function(String word) hasWord, {
  int maxWordLen = 6,
}) {
  final segments = <String>[];
  var i = 0;
  while (i < text.length) {
    var matched = 0;
    final longest = maxWordLen < text.length - i
        ? maxWordLen
        : text.length - i;
    for (var len = longest; len >= 2; len--) {
      if (hasWord(text.substring(i, i + len))) {
        matched = len;
        break;
      }
    }
    if (matched > 0) {
      segments.add(text.substring(i, i + matched));
      i += matched;
    } else {
      segments.add(text[i]);
      i++;
    }
  }
  return segments;
}

/// The loaded dictionary. Loading is lazy and cached;
/// a missing or corrupt asset yields null and the panel
/// says so instead of inventing definitions.
class NovelDictionary {
  NovelDictionary._(this.words, this.chars);

  final Map<String, DictEntry> words;
  final Map<String, DictEntry> chars;

  static Future<NovelDictionary?>? _loading;

  static Future<NovelDictionary?> load() {
    return _loading ??= () async {
      try {
        final data = await rootBundle.load(
          'assets/novel/dictionary.json.gz',
        );
        final jsonText = utf8.decode(
          gzip.decode(data.buffer.asUint8List()),
        );
        final decoded = jsonDecode(jsonText);
        if (decoded is! Map) return null;
        Map<String, DictEntry> table(dynamic raw) {
          if (raw is! Map) return const {};
          return {
            for (final e in raw.entries)
              if (e.value is List && (e.value as List).length >= 2)
                e.key.toString(): DictEntry(
                  word: e.key.toString(),
                  pinyin: (e.value as List)[0].toString(),
                  explanation: (e.value as List)[1].toString(),
                ),
          };
        }

        return NovelDictionary._(table(decoded['w']), table(decoded['c']));
      } catch (_) {
        return null;
      }
    }();
  }

  DictLookup lookup(String query) => resolveDictLookup(
        words: words,
        chars: chars,
        query: query,
      );

  List<String> segment(String text) =>
      segmentTextForLookup(text, words.containsKey);
}
