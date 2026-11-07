// Batch 36 probe: run explore() for every XIU2 source's
// first categories through the production Legado engine and
// print full errors (the device UI truncates them).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:anikumo/services/novel/legado_def.dart';
import 'package:anikumo/services/novel/novel_source.dart';

void main() {
  test('xiu2 explore probe', () async {
    final text = await File('/tmp/xiu2.json').readAsString();
    final defs = (jsonDecode(text) as List).cast<Map<String, dynamic>>();
    for (final json in defs) {
      final def = LegadoSourceDef.fromJson(json);
      if (def == null) continue;
      final source = LegadoNovelSource(def);
      final cats = source.exploreCategories;
      if (cats.isEmpty) {
        print('== ${def.name}: no explore categories');
        continue;
      }
      for (final cat in cats.take(3)) {
        try {
          final items = await source.explore(cat, page: 1);
          print('== ${def.name} [${cat.title}]: ${items.length} items');
        } catch (e) {
          print('== ${def.name} [${cat.title}]: ERROR: $e');
        }
      }
    }
  }, timeout: const Timeout(Duration(minutes: 8)));
}
