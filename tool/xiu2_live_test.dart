import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:anikumo/services/novel/legado_def.dart';
import 'package:anikumo/services/novel/legado_gbk.dart';
import 'package:anikumo/services/novel/legado_parse.dart';
import 'package:anikumo/services/novel/novel_source.dart';

void main() {
  test('xiu2 bulk search probe', () async {
    Gb2312.debugLoadBytes(
      await File('assets/legado/gb2312.bin').readAsBytes(),
    );
    final text = await File('tool/xiu2_bundle.json').readAsString();
    final defs = LegadoParse.parseSourceArray(text);
    var ok = 0, empty = 0, failed = 0;
    for (final raw in defs) {
      final def = LegadoSourceDef.fromJson(raw);
      if (def == null) {
        stdout.writeln('PARSE-FAIL (unnamed)');
        failed++;
        continue;
      }
      final source = LegadoNovelSource(def);
      try {
        final results = await source
            .search('斗罗大陆')
            .timeout(const Duration(seconds: 25));
        if (results.isEmpty) {
          empty++;
          stdout.writeln('EMPTY   ${def.name}');
        } else {
          ok++;
          stdout.writeln(
              'OK(${results.length}) ${def.name} -> ${results.first.title}');
        }
      } catch (e) {
        failed++;
        final msg = e.toString().replaceAll('\n', ' ');
        stdout.writeln(
            'FAIL    ${def.name} :: ${msg.length > 130 ? msg.substring(0, 130) : msg}');
      }
    }
    stdout.writeln('SUMMARY ok=$ok empty=$empty failed=$failed');
  }, timeout: const Timeout(Duration(minutes: 12)));
}
