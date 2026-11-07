import 'dart:typed_data';

import 'package:flutter/services.dart';

/// GB2312 codec for Legado sources (batch 31). A large share
/// of Chinese novel sites (the jieqiCMS family especially)
/// still serve GBK/GB2312 pages and expect GBK-encoded
/// search keywords; without a codec those sources returned
/// nothing at all or garbled text.
///
/// The decode table is a bundled asset: assets/legado/
/// gb2312.bin holds 94×94 uint16 code points for the
/// double-byte grid (lead/trail bytes 0xA1–0xFE), generated
/// from the standard GB2312 mapping (7,445 assigned cells).
/// GBK-extension characters outside GB2312 decode as U+FFFD
/// — an accepted degradation, they are rare in body text.
class Gb2312 {
  Gb2312._();

  static Uint16List? _table;
  static Map<int, List<int>>? _reverse;
  static Future<void>? _loading;

  static Future<void> ensureLoaded() {
    if (_table != null) return Future.value();
    return _loading ??= _load();
  }

  static Future<void> _load() async {
    final data = await rootBundle.load('assets/legado/gb2312.bin');
    _table = data.buffer.asUint16List(data.offsetInBytes, 8836);
  }

  /// Test/tool seam: inject the table without the asset
  /// bundle (live probes run without a widget binding, whose
  /// mock HttpClient would otherwise intercept requests).
  static void debugLoadBytes(Uint8List bytes) {
    _table = bytes.buffer.asUint16List(bytes.offsetInBytes, 8836);
  }

  static bool get isLoaded => _table != null;

  static int _index(int lead, int trail) =>
      (lead - 0xA1) * 94 + (trail - 0xA1);

  /// Decode GBK/GB2312 bytes. ASCII passes through; valid
  /// double-byte pairs map through the table; anything else
  /// becomes U+FFFD.
  static String decode(List<int> bytes) {
    final table = _table;
    if (table == null) {
      // Caller forgot ensureLoaded — degrade to a lossy
      // latin1 so text still shows instead of throwing.
      return String.fromCharCodes(
        bytes.map((b) => b < 0x80 ? b : 0xFFFD),
      );
    }
    final out = StringBuffer();
    var i = 0;
    while (i < bytes.length) {
      final b = bytes[i];
      if (b < 0x80) {
        out.writeCharCode(b);
        i++;
      } else if (b >= 0xA1 && b <= 0xFE && i + 1 < bytes.length) {
        final t = bytes[i + 1];
        if (t >= 0xA1 && t <= 0xFE) {
          final cp = table[_index(b, t)];
          out.writeCharCode(cp == 0 ? 0xFFFD : cp);
          i += 2;
        } else {
          out.writeCharCode(0xFFFD);
          i++;
        }
      } else {
        out.writeCharCode(0xFFFD);
        i++;
      }
    }
    return out.toString();
  }

  static Map<int, List<int>> _reverseMap() {
    if (_reverse != null) return _reverse!;
    final map = <int, List<int>>{};
    final table = _table!;
    for (var lead = 0xA1; lead <= 0xFE; lead++) {
      for (var trail = 0xA1; trail <= 0xFE; trail++) {
        final cp = table[_index(lead, trail)];
        if (cp != 0) map[cp] = [lead, trail];
      }
    }
    return _reverse = map;
  }

  /// Encode a string to GB2312 bytes (unmappable characters
  /// become '?'), for request bodies/queries.
  static List<int> encode(String text) {
    final reverse = _reverseMap();
    final out = <int>[];
    for (final rune in text.runes) {
      if (rune < 0x80) {
        out.add(rune);
      } else {
        final pair = reverse[rune];
        if (pair != null) {
          out.addAll(pair);
        } else {
          out.add(0x3F);
        }
      }
    }
    return out;
  }

  /// Percent-encode the non-ASCII characters of a form body
  /// or URL query string using GB2312 bytes (ASCII structure
  /// — &, =, +, existing %XX — is preserved verbatim).
  static String percentEncodeNonAscii(String input) {
    final out = StringBuffer();
    for (final rune in input.runes) {
      if (rune < 0x80) {
        out.writeCharCode(rune);
      } else {
        for (final byte in encode(String.fromCharCode(rune))) {
          out.write('%');
          out.write(byte.toRadixString(16).toUpperCase().padLeft(2, '0'));
        }
      }
    }
    return out.toString();
  }
}
