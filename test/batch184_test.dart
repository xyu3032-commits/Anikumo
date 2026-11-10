// Batch 184: novel content-stream hygiene — strict
// bridge-block typing in the facade, the shared
// has-content validity rule, and the reader's
// chapter-end tail decision. Non-content must never be
// disguised as chapter text, and a blank or truncated
// chapter must never present as a finished one.
import 'package:flutter_test/flutter_test.dart';

import 'package:anikumo/models/novel_item.dart';
import 'package:anikumo/pages/novel/novel_reader_page.dart';
import 'package:anikumo/services/novel/moyuan_engine.dart';

void main() {
  group('bridge block conversion (batch 184)', () {
    test('only text and image survive; everything else is dropped', () {
      final result = MoyuanEngine.blocksFromBridge({
        'blocks': [
          {'type': 'text', 'text': '正文一段'},
          {'type': 'image', 'url': 'https://i/1.jpg', 'headers': {'UA': 'x'}},
          // The pollution cases: an audio URL, an
          // error-shaped payload carrying text, an unknown
          // future type, a typeless entry, a non-map entry.
          {'type': 'audio', 'url': 'https://a/1.mp3'},
          {'type': 'error', 'text': 'Exception: HTTP 404 for https://x'},
          {'type': 'log', 'text': '[source-js] debug output'},
          {'type': 'video', 'text': '未知类型文本'},
          {'text': '没有类型的条目'},
          'junk',
          42,
          {'type': 'text', 'text': '正文二段'},
        ],
        'truncated': false,
      });
      expect(result.blocks.length, 3);
      expect(result.blocks[0], isA<NovelTextBlock>());
      expect((result.blocks[0] as NovelTextBlock).text, '正文一段');
      expect(result.blocks[1], isA<NovelImageBlock>());
      expect((result.blocks[1] as NovelImageBlock).url, 'https://i/1.jpg');
      expect((result.blocks[2] as NovelTextBlock).text, '正文二段');
      expect(result.possiblyTruncated, isFalse);
    });

    test('real words that look like logs stay (no keyword filtering)', () {
      final result = MoyuanEngine.blocksFromBridge({
        'blocks': [
          {'type': 'text', 'text': '系统日志里出现了一条 error 记录'},
          {'type': 'text', 'text': 'Exception 处理小组随后赶到现场'},
        ],
      });
      expect(result.blocks.length, 2);
    });

    test('blank paragraphs and empty images are dropped', () {
      final result = MoyuanEngine.blocksFromBridge({
        'blocks': [
          {'type': 'text', 'text': '   '},
          {'type': 'text', 'text': ''},
          {'type': 'image', 'url': ''},
          {'type': 'text', 'text': '  唯一的正文  '},
        ],
      });
      expect(result.blocks.length, 1);
      expect((result.blocks.single as NovelTextBlock).text, '唯一的正文');
    });

    test('truncated flag rides the new payload shape', () {
      final result = MoyuanEngine.blocksFromBridge({
        'blocks': [
          {'type': 'text', 'text': '未完待续'},
        ],
        'truncated': true,
      });
      expect(result.possiblyTruncated, isTrue);
      expect(result.blocks.length, 1);
    });

    test('legacy bare-list payloads still convert', () {
      final result = MoyuanEngine.blocksFromBridge([
        {'type': 'text', 'text': '旧形态'},
      ]);
      expect(result.blocks.length, 1);
      expect(result.possiblyTruncated, isFalse);
    });

    test('garbage payloads convert to an empty result, never a crash', () {
      expect(MoyuanEngine.blocksFromBridge(null).blocks, isEmpty);
      expect(MoyuanEngine.blocksFromBridge('text').blocks, isEmpty);
      expect(
        MoyuanEngine.blocksFromBridge({'blocks': 'nope'}).blocks,
        isEmpty,
      );
    });
  });

  group('has-content validity (batch 184)', () {
    test('empty and whitespace-only lists have no content', () {
      expect(novelBlocksHaveContent(const []), isFalse);
      expect(
        novelBlocksHaveContent(const [NovelTextBlock('   ')]),
        isFalse,
      );
      expect(
        novelBlocksHaveContent(const [NovelTextBlock('')]),
        isFalse,
      );
    });

    test('real text or an image counts as content', () {
      expect(
        novelBlocksHaveContent(const [NovelTextBlock('正')]),
        isTrue,
      );
      expect(
        novelBlocksHaveContent(const [NovelImageBlock('https://i/1.jpg')]),
        isTrue,
      );
      expect(
        novelBlocksHaveContent(const [NovelImageBlock('')]),
        isFalse,
      );
    });
  });

  group('chapter-end tail decision (batch 184)', () {
    test('no content renders no tail', () {
      expect(
        novelChapterTail(hasContent: false, possiblyTruncated: false),
        NovelChapterTail.none,
      );
      expect(
        novelChapterTail(hasContent: false, possiblyTruncated: true),
        NovelChapterTail.none,
      );
    });

    test('loaded content ends complete unless flagged truncated', () {
      expect(
        novelChapterTail(hasContent: true, possiblyTruncated: false),
        NovelChapterTail.complete,
      );
      expect(
        novelChapterTail(hasContent: true, possiblyTruncated: true),
        NovelChapterTail.truncated,
      );
    });
  });
}
