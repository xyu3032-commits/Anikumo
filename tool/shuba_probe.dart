import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:anikumo/services/novel/legado_def.dart';
import 'package:anikumo/services/novel/legado_gbk.dart';
import 'package:anikumo/services/novel/novel_source.dart';

void main() {
  test('69shuba explore with GBK table injected', () async {
    Gb2312.debugLoadBytes(
      await File('assets/legado/gb2312.bin').readAsBytes(),
    );
    final text = await File('/tmp/xiu2.json').readAsString();
    final defs = (jsonDecode(text) as List).cast<Map<String, dynamic>>();
    final json = defs.firstWhere((d) => d['bookSourceName'] == '69书吧');
    final def = LegadoSourceDef.fromJson(json)!;
    final source = LegadoNovelSource(def);
    print('cats: ${source.exploreCategories.map((c) => c.title).toList()}');
    final cat = source.exploreCategories.first;
    try {
      final items = await source.explore(cat, page: 1);
      print('== [${cat.title}] ${items.length} items, first=${items.firstOrNull?.title}');
    } catch (e) {
      print('== ERROR>>> ${e.toString().replaceAll('\n', ' | ')}');
    }
  }, timeout: const Timeout(Duration(minutes: 4)));
}
