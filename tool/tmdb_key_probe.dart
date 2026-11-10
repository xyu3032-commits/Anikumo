import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:anikumo/services/tmdb/tmdb_key.dart';

/// Batch 130 probe: after the packaging injector runs, the
/// built-in key decoded from the obfuscated constant must
/// equal the secrets file content (passed via TMDB_EXPECT,
/// never printed). Run:
///   TMDB_EXPECT=$(cat ~/workspace/.tools/secrets/tmdb_api_key.txt) \
///     flutter test tool/tmdb_key_probe.dart
void main() {
  test('built-in TMDB key roundtrips through the obfuscation', () {
    final expected = Platform.environment['TMDB_EXPECT'] ?? '';
    expect(expected, isNotEmpty, reason: 'TMDB_EXPECT not set');
    expect(builtinTmdbKey, expected);
  });
}
