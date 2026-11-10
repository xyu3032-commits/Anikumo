import 'package:flutter_test/flutter_test.dart';

import 'package:anikumo/services/tmdb/tmdb_key.dart';

void main() {
  group('TMDB key obfuscation codec (batch 130)', () {
    test('roundtrips keys of representative shapes', () {
      for (final raw in [
        'a' * 32,
        '0123456789abcdef0123456789abcdef',
        'eyJhbGciOiJIUzI1NiJ9.long-jwt-style_token.with-dashes_and.dots',
        '短',
      ]) {
        final encoded = encodeTmdbKey(raw);
        expect(encoded, isNot(raw));
        expect(decodeTmdbKey(encoded), raw);
      }
    });

    test('empty stays empty in both directions', () {
      expect(encodeTmdbKey(''), '');
      expect(decodeTmdbKey(''), '');
      expect(builtinTmdbKey, isEmpty,
          reason: 'the source tree must never carry a built-in key');
    });

    test('garbage decodes to empty instead of throwing', () {
      expect(decodeTmdbKey('!!!not base64!!!'), '');
    });
  });
}
