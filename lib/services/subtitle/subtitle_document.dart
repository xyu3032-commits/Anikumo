/// Batch 278: subtitle file parsing/serialization for the
/// machine-translation pipeline.
///
/// The player mounts external subtitle files through mpv
/// directly (batch 273), so nothing parsed text cues until
/// now. Translation needs real cues: this file parses
/// SRT / WebVTT / ASS-SSA into [SubtitleCue]s, serializes
/// back to SRT (the one format every step downstream
/// accepts), and carries the script-based source-language
/// guess the translation entry gates on.
///
/// Everything here is pure and synchronous so the whole
/// pipeline is unit-testable without a translator.
library;

import 'dart:convert';

/// One subtitle cue: a time range plus its raw text
/// (markup still embedded; strip it with
/// [stripSubtitleMarkup] before handing text to a
/// translator).
class SubtitleCue {
  const SubtitleCue({
    required this.start,
    required this.end,
    required this.text,
  });

  final Duration start;
  final Duration end;
  final String text;

  SubtitleCue copyWithText(String next) =>
      SubtitleCue(start: start, end: end, text: next);
}

/// Parses [content] as the subtitle format named by
/// [format] ('srt', 'vtt', 'ass', 'ssa'; anything else is
/// tried as SRT). Malformed blocks are skipped, never
/// thrown on — a partially broken file still yields its
/// readable cues.
List<SubtitleCue> parseSubtitleDocument(String format, String content) {
  switch (format.toLowerCase().replaceAll('.', '')) {
    case 'vtt':
      return _parseVtt(content);
    case 'ass':
    case 'ssa':
      return _parseAss(content);
    default:
      return _parseSrt(content);
  }
}

Duration _parseClock(String raw, {bool centiseconds = false}) {
  var s = raw.trim().replaceAll('.', ',');
  final parts = s.split(':');
  try {
    if (parts.length == 3) {
      final sec = parts[2].split(',');
      final frac = sec.length > 1 ? sec[1] : '0';
      final ms = centiseconds
          ? (int.parse(frac.padRight(2, '0').substring(0, 2)) * 10)
          : int.parse(frac.padRight(3, '0').substring(0, 3));
      return Duration(
        hours: int.parse(parts[0]),
        minutes: int.parse(parts[1]),
        seconds: int.parse(sec[0]),
        milliseconds: ms,
      );
    }
    if (parts.length == 2) {
      final sec = parts[1].split(',');
      final frac = sec.length > 1 ? sec[1] : '0';
      return Duration(
        minutes: int.parse(parts[0]),
        seconds: int.parse(sec[0]),
        milliseconds: int.parse(frac.padRight(3, '0').substring(0, 3)),
      );
    }
  } catch (_) {
    // Fall through to zero.
  }
  return Duration.zero;
}

List<SubtitleCue> _parseSrt(String input) {
  final cues = <SubtitleCue>[];
  final blocks = input.replaceAll('\r\n', '\n').split(RegExp(r'\n\s*\n'));
  for (final block in blocks) {
    final lines = block.trim().split('\n');
    if (lines.isEmpty) continue;
    final idx = lines.indexWhere((l) => l.contains('-->'));
    if (idx < 0) continue;
    final times = lines[idx].split('-->');
    if (times.length < 2) continue;
    final text = lines.sublist(idx + 1).join('\n').trim();
    if (text.isEmpty) continue;
    cues.add(SubtitleCue(
      start: _parseClock(times[0]),
      end: _parseClock(times[1].trim().split(' ').first),
      text: text,
    ));
  }
  cues.sort((a, b) => a.start.compareTo(b.start));
  return cues;
}

List<SubtitleCue> _parseVtt(String input) {
  var s = input.replaceAll('\r\n', '\n');
  if (s.startsWith('\uFEFF')) s = s.substring(1);
  if (s.startsWith('WEBVTT')) {
    final firstBreak = s.indexOf('\n');
    if (firstBreak < 0) return const [];
    s = s.substring(firstBreak + 1);
  }
  final cues = <SubtitleCue>[];
  final blocks = s.split(RegExp(r'\n\s*\n'));
  for (final block in blocks) {
    final lines = block.trim().split('\n');
    if (lines.isEmpty) continue;
    final head = lines.first.trim().toUpperCase();
    if (head.startsWith('NOTE') || head.startsWith('STYLE') ||
        head.startsWith('REGION')) {
      continue;
    }
    final idx = lines.indexWhere((l) => l.contains('-->'));
    if (idx < 0) continue;
    final times = lines[idx].split('-->');
    if (times.length < 2) continue;
    final text = lines.sublist(idx + 1).join('\n').trim();
    if (text.isEmpty) continue;
    cues.add(SubtitleCue(
      start: _parseClock(times[0]),
      end: _parseClock(times[1].trim().split(' ').first),
      text: text,
    ));
  }
  cues.sort((a, b) => a.start.compareTo(b.start));
  return cues;
}

List<SubtitleCue> _parseAss(String input) {
  final cues = <SubtitleCue>[];
  // Default ASS field order; a [Events] Format: line can
  // reorder it, so track the indices when one shows up.
  var startIdx = 1, endIdx = 2, textIdx = 9;
  var inEvents = false;
  for (final rawLine in input.split('\n')) {
    final line = rawLine.trim();
    if (line.startsWith('[')) {
      inEvents = line.toLowerCase() == '[events]';
      continue;
    }
    if (inEvents && line.startsWith('Format:')) {
      final fields = line
          .substring('Format:'.length)
          .split(',')
          .map((f) => f.trim().toLowerCase())
          .toList();
      final s = fields.indexOf('start');
      final e = fields.indexOf('end');
      final t = fields.indexOf('text');
      if (s >= 0 && e >= 0 && t >= 0) {
        startIdx = s;
        endIdx = e;
        textIdx = t;
      }
      continue;
    }
    if (!line.startsWith('Dialogue:')) continue;
    final parts = line.substring('Dialogue:'.length).split(',');
    if (parts.length <= textIdx) continue;
    final text = parts.sublist(textIdx).join(',').trim();
    if (text.isEmpty) continue;
    cues.add(SubtitleCue(
      start: _parseClock(parts[startIdx], centiseconds: true),
      end: _parseClock(parts[endIdx], centiseconds: true),
      text: text,
    ));
  }
  cues.sort((a, b) => a.start.compareTo(b.start));
  return cues;
}

String _formatSrtClock(Duration d) {
  String two(int v) => v.toString().padLeft(2, '0');
  final ms = d.inMilliseconds;
  final hours = ms ~/ 3600000;
  final minutes = (ms % 3600000) ~/ 60000;
  final seconds = (ms % 60000) ~/ 1000;
  final millis = ms % 1000;
  return '${two(hours)}:${two(minutes)}:${two(seconds)},'
      '${millis.toString().padLeft(3, '0')}';
}

/// Serializes [cues] as a standard SRT document. Cue
/// timings are written back exactly as parsed — the
/// translation pipeline replaces text only, so a
/// parse→translate→serialize roundtrip preserves the
/// timeline bit for bit.
String serializeSrt(List<SubtitleCue> cues) {
  final buffer = StringBuffer();
  for (var i = 0; i < cues.length; i++) {
    final cue = cues[i];
    buffer
      ..writeln(i + 1)
      ..writeln(
        '${_formatSrtClock(cue.start)} --> ${_formatSrtClock(cue.end)}',
      )
      ..writeln(cue.text.trim())
      ..writeln();
  }
  return buffer.toString();
}

/// Decodes raw subtitle file bytes to text: UTF-8 (BOM
/// stripped), UTF-16LE/BE when their BOM says so, strict
/// UTF-8 next, and Latin-1 as the last resort (it maps
/// every byte, so decoding never throws — legacy
/// single-byte files survive with their accents intact,
/// though legacy double-byte encodings will not).
String decodeSubtitleBytes(List<int> bytes) {
  if (bytes.length >= 3 &&
      bytes[0] == 0xEF &&
      bytes[1] == 0xBB &&
      bytes[2] == 0xBF) {
    return utf8.decode(bytes.sublist(3), allowMalformed: true);
  }
  if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
    return _decodeUtf16(bytes.sublist(2), littleEndian: true);
  }
  if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
    return _decodeUtf16(bytes.sublist(2), littleEndian: false);
  }
  try {
    return utf8.decode(bytes);
  } on FormatException {
    return latin1.decode(bytes);
  }
}

String _decodeUtf16(List<int> bytes, {required bool littleEndian}) {
  final units = <int>[];
  for (var i = 0; i + 1 < bytes.length; i += 2) {
    units.add(littleEndian
        ? bytes[i] | (bytes[i + 1] << 8)
        : (bytes[i] << 8) | bytes[i + 1]);
  }
  return String.fromCharCodes(units);
}

final RegExp _assTagPattern = RegExp(r'\{[^}]*\}');
final RegExp _htmlTagPattern = RegExp(r'<[^>]+>');

/// Removes presentation markup (ASS override blocks,
/// HTML-ish tags) and normalizes hard line breaks, so a
/// translator sees — and returns — plain dialogue text.
String stripSubtitleMarkup(String text) {
  return text
      .replaceAll(_assTagPattern, '')
      .replaceAll(_htmlTagPattern, '')
      .replaceAll(r'\N', '\n')
      .replaceAll(r'\n', '\n')
      .trim();
}

final RegExp _letterPattern = RegExp(r'\p{L}', unicode: true);

/// True when [text] contains anything a translator could
/// work on (a letter in any script). Pure-symbol or
/// pure-number cues pass through translation unchanged.
bool hasTranslatableText(String text) => _letterPattern.hasMatch(text);

/// Script-based source-language guess for subtitle text.
///
/// Returns an ISO-639-1-ish code ('ja', 'ko', 'ru', 'ar',
/// 'zh', 'en', 'fr', 'de', 'es', 'pt', 'it') or null when
/// the sample is too small or too mixed to call. Kana
/// presence decides Japanese even mixed with Han (a
/// Chinese sample never contains kana); Latin samples go
/// through a small stopword vote before defaulting to
/// English.
///
/// [minLetters] is the smallest letter count trusted
/// for a verdict; whole files use the default, the live
/// overlay passes 1 so even a two-kana line gets called.
String? detectSubtitleLanguage(String sample, {int minLetters = 10}) {
  var kana = 0, hangul = 0, han = 0, cyrillic = 0, arabic = 0, latin = 0;
  final text = sample.length > 6000 ? sample.substring(0, 6000) : sample;
  for (final rune in text.runes) {
    if (rune >= 0x3040 && rune <= 0x30FF) {
      kana++;
    } else if ((rune >= 0xAC00 && rune <= 0xD7AF) ||
        (rune >= 0x1100 && rune <= 0x11FF)) {
      hangul++;
    } else if (rune >= 0x4E00 && rune <= 0x9FFF) {
      han++;
    } else if (rune >= 0x0400 && rune <= 0x04FF) {
      cyrillic++;
    } else if (rune >= 0x0600 && rune <= 0x06FF) {
      arabic++;
    } else if ((rune >= 0x41 && rune <= 0x5A) ||
        (rune >= 0x61 && rune <= 0x7A) ||
        (rune >= 0xC0 && rune <= 0x24F)) {
      latin++;
    }
  }
  final total = kana + hangul + han + cyrillic + arabic + latin;
  if (total < minLetters) return null;
  // Japanese: kana shows up in real quantity next to the
  // Han it borrows (a stray kana quoted inside a Chinese
  // sample must not flip the verdict).
  if (kana > 0 && kana * 8 >= han && kana + han >= hangul) {
    return 'ja';
  }
  final counts = <String, int>{
    'ko': hangul,
    'zh': han,
    'ru': cyrillic,
    'ar': arabic,
    'en': latin,
  };
  var best = 'en';
  var bestCount = -1;
  counts.forEach((code, count) {
    if (count > bestCount) {
      best = code;
      bestCount = count;
    }
  });
  if (best != 'en') return best;
  // Latin winner: give the big Romance/German languages a
  // chance via stopwords before settling on English.
  final words = text
      .toLowerCase()
      .split(RegExp(r"[^a-zà-ÿ]+"))
      .where((w) => w.isNotEmpty)
      .toSet();
  const stopwords = <String, List<String>>{
    'fr': ['le', 'la', 'les', 'des', 'est', 'je', 'tu', 'il', 'nous', 'vous', 'pas', 'sur', 'avec', 'pour', 'dans'],
    'de': ['der', 'die', 'das', 'und', 'ist', 'ich', 'nicht', 'ein', 'eine', 'mit', 'von', 'zu', 'den', 'sich', 'auf'],
    'es': ['el', 'la', 'los', 'las', 'una', 'que', 'de', 'en', 'es', 'por', 'con', 'para', 'del', 'está', 'esto'],
    'pt': ['o', 'a', 'os', 'as', 'um', 'uma', 'que', 'de', 'em', 'do', 'da', 'para', 'com', 'não', 'está'],
    'it': ['il', 'lo', 'la', 'gli', 'che', 'di', 'non', 'un', 'una', 'per', 'con', 'sono', 'del', 'della', 'questo'],
    'en': ['the', 'you', 'and', 'that', 'was', 'for', 'are', 'with', 'his', 'they', 'this', 'have', 'from', 'one'],
  };
  var latinBest = 'en';
  var latinScore = 0;
  stopwords.forEach((code, list) {
    final score = list.where(words.contains).length;
    if (score > latinScore) {
      latinScore = score;
      latinBest = code;
    }
  });
  return latinScore >= 2 ? latinBest : 'en';
}
