import 'package:flutter_test/flutter_test.dart';
import 'package:anikumo/services/novel/legado_def.dart';
import 'package:anikumo/services/novel/legado_dom.dart';
import 'package:html/parser.dart' as html_parser;

// Batch 36 regressions for the two engine defects behind
// the v11 device screenshot: whole XIU2 source families
// dead on the novel home explore sections.
void main() {
  group('exploreCategories formats', () {
    LegadoSourceDef defWith(String exploreUrl) {
      return LegadoSourceDef.fromJson({
        'bookSourceName': '测试源',
        'bookSourceUrl': 'https://example.com',
        'bookSourceType': 0,
        'exploreUrl': exploreUrl,
      })!;
    }

    test('line format 标题::地址 splits into categories', () {
      final def = defWith(
        '全部分类::/blist/class/0/{{page}}.htm\n'
        '玄幻魔法::/blist/class/1/{{page}}.htm\n'
        '修真武侠::/blist/class/2/{{page}}.htm',
      );
      final cats = def.exploreCategories;
      expect(cats.map((c) => c.title), ['全部分类', '玄幻魔法', '修真武侠']);
      expect(cats.first.url, '/blist/class/0/{{page}}.htm');
    });

    test('JSON array format still works, empty urls skipped', () {
      final def = defWith(
        '[{"title":"排行榜","url":""},'
        '{"title":"月点击榜","url":"https://example.com/top/{{page}}.html"}]',
      );
      final cats = def.exploreCategories;
      expect(cats.length, 1);
      expect(cats.single.title, '月点击榜');
    });

    test('bare single url stays one 发现 category', () {
      final def = defWith('https://example.com/find/{{page}}.html');
      final cats = def.exploreCategories;
      expect(cats.length, 1);
      expect(cats.single.title, '发现');
    });
  });

  group('fieldElements bare @attr', () {
    test('reads the context element own onclick attribute', () {
      final doc = html_parser.parse(
        '<div class="v-list-item" onclick="gotoPage(\'/b/1.html\')">'
        '<span class="v-title">书名</span></div>',
      );
      final item = doc.querySelector('.v-list-item')!;
      final (els, attr) = LegadoDom.fieldElements(item, '@onclick');
      expect(attr, 'onclick');
      expect(els, [item]);
      expect(
        LegadoDom.extract(els.first, attr),
        "gotoPage('/b/1.html')",
      );
    });

    test('chained attr still resolves through the chain', () {
      final doc = html_parser.parse(
        '<div class="item"><a href="/b/2.html">x</a></div>',
      );
      final item = doc.querySelector('.item')!;
      final (els, attr) = LegadoDom.fieldElements(item, 'a@href');
      expect(attr, 'href');
      expect(LegadoDom.extract(els.first, attr), '/b/2.html');
    });
  });
}
