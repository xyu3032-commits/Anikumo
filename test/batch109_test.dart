// Batch 109: the user's standing rule — the app must not
// name the external formats/ecosystems it interoperates
// with, nor use crawler vocabulary, in anything it SAYS.
// This scans every Dart string literal under lib/ for the
// forbidden words (comments and code identifiers are not
// user-facing text and are out of scope, as are internal
// data ids). If a future batch reintroduces a name into a
// label, hint, toast or error, this fails.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('no user-facing string literal names a foreign format or crawler term',
      () {
    const forbidden = [
      'Legado',
      'Venera',
      'TVBox',
      'MacCMS',
      'Aniyomi',
      'read-cat',
      '爬虫',
      '嗅探',
    ];
    final offenders = <String>[];
    final libDir = Directory('lib');
    expect(libDir.existsSync(), isTrue);
    for (final entity
        in libDir.listSync(recursive: true).whereType<File>()) {
      if (!entity.path.endsWith('.dart')) continue;
      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        final trimmed = line.trimLeft();
        // Skip comment lines (doc and line comments).
        if (trimmed.startsWith('//') ||
            trimmed.startsWith('*') ||
            trimmed.startsWith('/*')) {
          continue;
        }
        // Collect quoted segments on this line.
        final segments = <String>[];
        var j = 0;
        while (j < line.length) {
          final ch = line[j];
          if (ch == "'" || ch == '"') {
            final end = line.indexOf(ch, j + 1);
            if (end < 0) break;
            segments.add(line.substring(j + 1, end));
            j = end + 1;
          } else {
            j++;
          }
        }
        for (final segment in segments) {
          for (final word in forbidden) {
            if (segment.contains(word)) {
              offenders.add('${entity.path}:${i + 1} contains "$word"');
            }
          }
        }
      }
    }
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });
}
