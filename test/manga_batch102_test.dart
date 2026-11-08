// Batch 102: onResponse transform plumbing (pure parts),
// the cover concurrency gate, and local CBZ import.
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anikumo/modules/manga/manga_item.dart';
import 'package:anikumo/services/manga/js/js_manga_source.dart';
import 'package:anikumo/services/manga/local_manga_source.dart';
import 'package:anikumo/services/manga/manga_image_pipeline.dart';
import 'package:anikumo/services/manga/manga_source.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('applyImageConfigs transform flag', () {
    const pages = [
      MangaPage('https://cdn.example/p1.jpg'),
      MangaPage('https://cdn.example/p2.jpg'),
    ];

    test('transform config marks the page with its original url', () {
      final out = applyImageConfigs(pages, [
        {
          'url': 'https://cdn.example/p1.jpg?signed=1',
          'transform': true,
        },
        {'url': 'https://cdn.example/p2.jpg?signed=1'},
      ]);
      expect(out[0].url, 'https://cdn.example/p1.jpg?signed=1');
      expect(out[0].transformOf, 'https://cdn.example/p1.jpg');
      expect(out[1].transformOf, isNull);
    });

    test('no flag, no marker', () {
      final out = applyImageConfigs(pages, const [null, null]);
      expect(out[0].transformOf, isNull);
      expect(out[1].transformOf, isNull);
    });
  });

  group('applyThumbnailConfigs transform flag', () {
    const item = MangaItem(
      id: 'm1',
      title: 't',
      description: '',
      coverUrl: 'https://cdn.example/cover.jpg',
      author: '',
      status: '',
      year: null,
      tags: [],
      source: 'js:x',
    );

    test('transform-only config still marks the cover', () {
      // No url change, no headers: before batch 102 this
      // config was dropped by the "nothing changed" return.
      final out = applyThumbnailConfigs([item], [
        {'transform': true},
      ]);
      expect(out[0].coverUrl, item.coverUrl);
      expect(out[0].coverTransformOf, item.coverUrl);
    });

    test('snapshot round-trips the marker; legacy snapshots lack it', () {
      final marked = applyThumbnailConfigs([item], [
        {'transform': true},
      ]).first;
      final restored = MangaItem.fromSnapshot(marked.toSnapshot());
      expect(restored.coverTransformOf, item.coverUrl);
      final legacy = MangaItem.fromSnapshot(item.toSnapshot());
      expect(legacy.coverTransformOf, isNull);
    });
  });

  group('MangaImageGate', () {
    test('never exceeds the concurrency cap and drains the queue', () async {
      final gate = MangaImageGate(maxConcurrent: 3);
      var running = 0;
      var peak = 0;
      final results = await Future.wait([
        for (var i = 0; i < 10; i++)
          gate.run(() async {
            running++;
            if (running > peak) peak = running;
            await Future<void>.delayed(const Duration(milliseconds: 10));
            running--;
            return i;
          }),
      ]);
      expect(peak, 3);
      expect(results, [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]);
    });

    test('a throwing task releases its slot', () async {
      final gate = MangaImageGate(maxConcurrent: 1);
      await expectLater(
        gate.run(() async => throw StateError('boom')),
        throwsStateError,
      );
      final after = await gate.run(() async => 42);
      expect(after, 42);
      expect(gate.running, 0);
    });
  });

  group('local manga helpers', () {
    test('naturalCompare orders page names by number value', () {
      final names = ['page_10.jpg', 'Page_2.jpg', 'page_1.jpg', 'page_02.jpg'];
      names.sort(naturalCompare);
      expect(names, ['page_1.jpg', 'Page_2.jpg', 'page_02.jpg', 'page_10.jpg']);
      expect(naturalCompare('a', 'a1'), lessThan(0));
      expect(naturalCompare('ch2', 'ch10'), lessThan(0));
      expect(naturalCompare('same', 'same'), 0);
    });

    test('isLocalMangaImageName filters archive junk', () {
      expect(isLocalMangaImageName('vol1/001.JPG'), isTrue);
      expect(isLocalMangaImageName('p.WEBP'), isTrue);
      expect(isLocalMangaImageName('__MACOSX/001.jpg'), isFalse);
      expect(isLocalMangaImageName('.hidden.jpg'), isFalse);
      expect(isLocalMangaImageName('ComicInfo.xml'), isFalse);
      expect(isLocalMangaImageName('folder/'), isFalse);
    });
  });

  group('local CBZ import', () {
    late Directory root;

    setUpAll(() async {
      root = await Directory.systemTemp.createTemp('batch102_local');
      PathProviderPlatform.instance = _TestPaths(root.path);
    });

    test('import extracts pages in reading order; source serves them',
        () async {
      List<int> page(String s) => s.codeUnits;
      final archive = Archive()
        ..addFile(ArchiveFile('book/p10.jpg', 4, page('P10!')))
        ..addFile(ArchiveFile('book/p2.jpg', 3, page('P2!')))
        ..addFile(ArchiveFile('book/p1.jpg', 3, page('P1!')))
        ..addFile(ArchiveFile('ComicInfo.xml', 4, page('<x/>')))
        ..addFile(ArchiveFile('__MACOSX/junk.jpg', 3, page('BAD')));
      final zipFile = File('${root.path}/testbook.cbz');
      await zipFile.writeAsBytes(ZipEncoder().encode(archive));

      final book = await LocalMangaLibrary.importArchive(zipFile.path);
      expect(book.title, 'testbook');
      expect(book.pages, 3);
      expect(book.coverFile, '0001.jpg');
      expect(
        await File('${book.dirPath}/0001.jpg').readAsString(),
        'P1!',
      );
      expect(
        await File('${book.dirPath}/0002.jpg').readAsString(),
        'P2!',
      );
      expect(
        await File('${book.dirPath}/0003.jpg').readAsString(),
        'P10!',
      );

      final source = LocalMangaSource.instance;
      final items = await source.popular();
      expect(items.length, 1);
      expect(items.single.source, 'local');
      expect(items.single.coverUrl, startsWith('file://'));
      final chapters = await source.chapters(items.single);
      expect(chapters.length, 1);
      expect(chapters.single.pages, 3);
      final pages = await source.pages(items.single, chapters.single);
      expect(pages.length, 3);
      expect(pages[0].url, endsWith('0001.jpg'));
      expect(pages[2].url, endsWith('0003.jpg'));
      final searchHits = await source.search('test');
      expect(searchHits.length, 1);
      expect(await source.search('nope'), isEmpty);

      await LocalMangaLibrary.deleteBook(book.id);
      expect(await Directory(book.dirPath).exists(), isFalse);
      expect(await source.popular(), isEmpty);
    });

    test('an archive without images is rejected and cleaned up', () async {
      final archive = Archive()
        ..addFile(ArchiveFile('readme.txt', 3, 'abc'.codeUnits));
      final zipFile = File('${root.path}/emptybook.zip');
      await zipFile.writeAsBytes(ZipEncoder().encode(archive));
      await expectLater(
        LocalMangaLibrary.importArchive(zipFile.path),
        throwsFormatException,
      );
      final libraryDir = Directory('${root.path}/manga_local');
      final leftovers = await libraryDir
          .list()
          .where((e) => e is Directory)
          .length;
      expect(leftovers, 0);
    });
  });
}
