import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:anikumo/services/storage/cache_budget_trimmer.dart';

void main() {
  group('cache budget trimmer (batch 145)', () {
    late Directory dir;
    final now = DateTime(2026, 11, 9, 12);

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('anikumo_trim_test_');
    });

    tearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    Future<File> writeFile(String name, int bytes, DateTime modified) async {
      final file = File('${dir.path}/$name');
      await file.writeAsBytes(List.filled(bytes, 7));
      await file.setLastModified(modified);
      return file;
    }

    test('under budget frees nothing', () async {
      await writeFile('a.jpg', 100, now.subtract(const Duration(days: 1)));
      final freed = await trimDirectoryToBudget(dir, 1000, now: now);
      expect(freed, 0);
      expect(await File('${dir.path}/a.jpg').exists(), isTrue);
    });

    test('over budget deletes oldest first until under budget', () async {
      await writeFile('old.jpg', 100, now.subtract(const Duration(days: 3)));
      await writeFile('mid.jpg', 100, now.subtract(const Duration(days: 2)));
      await writeFile('new.jpg', 100, now.subtract(const Duration(days: 1)));
      final freed = await trimDirectoryToBudget(dir, 150, now: now);
      expect(freed, 200);
      expect(await File('${dir.path}/old.jpg').exists(), isFalse);
      expect(await File('${dir.path}/mid.jpg').exists(), isFalse);
      expect(await File('${dir.path}/new.jpg').exists(), isTrue);
    });

    test('recently written files are never touched', () async {
      await writeFile(
        'fresh.jpg',
        500,
        now.subtract(const Duration(minutes: 1)),
      );
      final freed = await trimDirectoryToBudget(dir, 100, now: now);
      expect(freed, 0);
      expect(await File('${dir.path}/fresh.jpg').exists(), isTrue);
    });

    test('metadata files are skipped even when old and huge', () async {
      await writeFile(
        'cacheObject.json',
        5000,
        now.subtract(const Duration(days: 30)),
      );
      await writeFile('page.jpg', 100, now.subtract(const Duration(days: 1)));
      final freed = await trimDirectoryToBudget(dir, 200, now: now);
      expect(freed, 0);
      expect(await File('${dir.path}/cacheObject.json').exists(), isTrue);
    });
  });
}
