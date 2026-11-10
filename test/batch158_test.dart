// Batch 158: the novel feature repository — TXT/EPUB
// parsing for local books, speech chunking, install-state
// persistence, the local source flow, and the TTS queue
// state machine over a mocked platform channel.
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:anikumo/models/novel_item.dart';
import 'package:anikumo/services/novel/local_books.dart';
import 'package:anikumo/services/novel/novel_features.dart';
import 'package:anikumo/services/novel/tts_service.dart';
import 'package:anikumo/services/storage/storage.dart';

class _TestPaths extends PathProviderPlatform {
  _TestPaths(this.root);
  final String root;
  @override
  Future<String?> getApplicationDocumentsPath() async => root;
  @override
  Future<String?> getApplicationSupportPath() async => root;
  @override
  Future<String?> getTemporaryPath() async => root;
}

List<int> buildEpub() {
  final archive = Archive();
  void add(String name, String content) {
    final bytes = utf8.encode(content);
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }

  add('META-INF/container.xml',
      '<?xml version="1.0"?><container><rootfiles>'
      '<rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>'
      '</rootfiles></container>');
  add('OEBPS/content.opf',
      '<?xml version="1.0"?><package><metadata>'
      '<dc:title>测试之书</dc:title><dc:creator>某作者</dc:creator></metadata>'
      '<manifest>'
      '<item id="c1" href="c1.xhtml" media-type="application/xhtml+xml"/>'
      '<item id="c2" href="c2.xhtml" media-type="application/xhtml+xml"/>'
      '</manifest><spine><itemref idref="c1"/><itemref idref="c2"/></spine></package>');
  add('OEBPS/c1.xhtml',
      '<html><head><title>x</title></head><body>'
      '<h1>第一章 起始</h1><p>第一段文字。</p><p>第二段文字。</p></body></html>');
  add('OEBPS/c2.xhtml',
      '<html><body><h1>第二章 推进</h1><p>后续内容。</p></body></html>');
  return ZipEncoder().encode(archive);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('splitTxtChapters (batch 158)', () {
    test('splits on chapter headings', () {
      final chapters = splitTxtChapters(
        '第一章 出发\n内容甲。\n第二章 到达\n内容乙。\n第三章 归途\n内容丙。',
      );
      expect(chapters, hasLength(3));
      expect(chapters[0].title, '第一章 出发');
      expect(chapters[0].text, contains('内容甲'));
      expect(chapters[2].title, '第三章 归途');
    });

    test('a short preamble joins the first chapter', () {
      final chapters = splitTxtChapters('简介一行。\n第一章 正题\n正文来了。');
      expect(chapters, hasLength(1));
      expect(chapters.single.text, contains('简介一行'));
      expect(chapters.single.text, contains('正文来了'));
    });

    test('no headings means one chapter', () {
      final chapters = splitTxtChapters('只是一整篇散文，没有任何章节标记。');
      expect(chapters, hasLength(1));
      expect(chapters.single.text, contains('散文'));
    });
  });

  group('EPUB parsing (batch 158)', () {
    test('reads spine chapters and metadata', () {
      final bytes = buildEpub();
      final chapters = parseEpubChapters(bytes);
      expect(chapters, hasLength(2));
      expect(chapters[0].title, '第一章 起始');
      expect(chapters[0].text, contains('第一段文字'));
      expect(chapters[0].text, contains('第二段文字'));
      expect(chapters[1].title, '第二章 推进');
      final meta = epubMetadata(bytes);
      expect(meta.title, '测试之书');
      expect(meta.author, '某作者');
    });
  });

  group('splitTextForSpeech (batch 158)', () {
    test('long paragraphs chunk at sentence boundaries', () {
      final sentence = '这是一个用于测试分段朗读的句子，长度适中。';
      final text = List.filled(60, sentence).join();
      final chunks = splitTextForSpeech(text);
      expect(chunks.length, greaterThan(1));
      for (final c in chunks) {
        expect(c.length, lessThanOrEqualTo(501));
      }
      expect(chunks.join(), text);
    });

    test('short text stays whole, blank lines drop', () {
      expect(splitTextForSpeech('一句话。\n\n另一句。'), ['一句话。', '另一句。']);
    });
  });

  group('feature installs and local books (batch 158)', () {
    setUpAll(() async {
      final dir = await Directory.systemTemp.createTemp('batch158');
      PathProviderPlatform.instance = _TestPaths(dir.path);
      Hive.init(dir.path);
      await GStorage.init();
    });

    test('install state persists', () async {
      expect(NovelFeatures.isInstalled(NovelFeatures.ttsId), isFalse);
      await NovelFeatures.setInstalled(NovelFeatures.ttsId, true);
      expect(NovelFeatures.isInstalled(NovelFeatures.ttsId), isTrue);
      await NovelFeatures.setInstalled(NovelFeatures.ttsId, false);
      expect(NovelFeatures.isInstalled(NovelFeatures.ttsId), isFalse);
    });

    test('TXT import flows through the local source', () async {
      final bytes = utf8.encode('第一章 开始\n你好，世界。\n第二章 继续\n第二章正文。');
      final book = await LocalBookStore.importBytes('小书.txt', bytes);
      expect(book, isNotNull);
      expect(book!.chapterCount, 2);
      expect(book.title, '小书');
      final again = await LocalBookStore.importBytes('小书.txt', bytes);
      expect(again, isNull, reason: 'same content is a duplicate');

      const source = LocalNovelSource();
      final found = await source.search('小书');
      expect(found, hasLength(1));
      final chapters = await source.chapters(found.single);
      expect(chapters, hasLength(2));
      final blocks = await source.content(found.single, chapters[1]);
      expect(blocks, hasLength(1));
      expect((blocks.single as NovelTextBlock).text, contains('第二章正文'));
    });
  });

  group('TtsPlayer queue (batch 158)', () {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final spoken = <Map<String, dynamic>>[];

    setUpAll(() {
      messenger.setMockMethodCallHandler(TtsPlayer.channel, (call) async {
        if (call.method == 'speak') {
          spoken.add((call.arguments as Map).cast<String, dynamic>());
        }
        if (call.method == 'isAvailable') return true;
        return null;
      });
    });

    tearDownAll(() {
      messenger.setMockMethodCallHandler(TtsPlayer.channel, null);
    });

    Future<void> platformSay(String method, String id) async {
      final data = const StandardMethodCodec()
          .encodeMethodCall(MethodCall(method, id));
      await messenger.handlePlatformMessage(
        'com.anikumo.app/novel_tts',
        data,
        (_) {},
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
    }

    test('queue advances on utterance completion', () async {
      spoken.clear();
      final player = TtsPlayer.instance;
      var finished = false;
      player.onQueueFinished = () => finished = true;
      await player.speakParagraphs(['第一段。', '第二段。']);
      expect(player.speaking, isTrue);
      expect(player.totalChunks, 2);
      expect(spoken, hasLength(1));
      await platformSay('onUtteranceDone', spoken[0]['id'] as String);
      expect(spoken, hasLength(2));
      expect(player.currentChunk, 1);
      await platformSay('onUtteranceDone', spoken[1]['id'] as String);
      expect(finished, isTrue);
      expect(player.speaking, isFalse);
      player.onQueueFinished = null;
    });

    test('stop invalidates late callbacks', () async {
      spoken.clear();
      final player = TtsPlayer.instance;
      await player.speakParagraphs(['唯一一段。', '还有一段。']);
      final staleId = spoken[0]['id'] as String;
      await player.stop();
      expect(player.speaking, isFalse);
      await platformSay('onUtteranceDone', staleId);
      expect(spoken, hasLength(1), reason: 'no further utterance starts');
    });
  });
}
