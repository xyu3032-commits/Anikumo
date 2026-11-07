// Batch 63: GitHub link handling for the novel/manga
// import flows — file pages rewrite to raw, repository
// addresses parse into owner/repo/branch/subpath, and
// contents listings keep files only.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:anikumo/utils/github_links.dart';

void main() {
  group('rawFileUrl', () {
    test('blob page rewrites to raw', () {
      expect(
        GithubLinks.rawFileUrl(
            'https://github.com/venera-app/venera-configs/blob/main/comic_source.js'),
        'https://raw.githubusercontent.com/venera-app/venera-configs/main/comic_source.js',
      );
    });

    test('blob page in a subfolder keeps the path', () {
      expect(
        GithubLinks.rawFileUrl(
            'https://github.com/o/r/blob/dev/sources/x.json'),
        'https://raw.githubusercontent.com/o/r/dev/sources/x.json',
      );
    });

    test('raw addresses pass through; other hosts are null', () {
      const raw = 'https://raw.githubusercontent.com/o/r/main/x.json';
      expect(GithubLinks.rawFileUrl(raw), raw);
      expect(GithubLinks.rawFileUrl('https://example.com/x.json'), isNull);
      expect(GithubLinks.rawFileUrl('https://github.com/o/r'), isNull);
    });
  });

  group('parseRepo', () {
    test('bare repo address has no branch (resolved later)', () {
      final ref = GithubLinks.parseRepo('https://github.com/o/r');
      expect(ref, isNotNull);
      expect(ref!.owner, 'o');
      expect(ref.repo, 'r');
      expect(ref.branch, isNull);
      expect(ref.subpath, '');
    });

    test('tree address carries branch and subpath', () {
      final ref =
          GithubLinks.parseRepo('https://github.com/o/r/tree/dev/src');
      expect(ref!.branch, 'dev');
      expect(ref.subpath, 'src');
    });

    test('.git suffix is stripped', () {
      expect(GithubLinks.parseRepo('https://github.com/o/r.git')!.repo, 'r');
    });

    test('file pages and in-repo pages are not repos', () {
      expect(
        GithubLinks.parseRepo('https://github.com/o/r/blob/main/x.js'),
        isNull,
      );
      expect(GithubLinks.parseRepo('https://github.com/o/r/issues'), isNull);
      expect(GithubLinks.parseRepo('https://example.com/o/r'), isNull);
    });
  });

  group('parseContents', () {
    const ref = GithubRepoRef(owner: 'o', repo: 'r');

    test('keeps files, skips directories, uses download_url', () {
      final files = GithubLinks.parseContents(
        jsonEncode([
          {'type': 'dir', 'name': 'sub'},
          {
            'type': 'file',
            'name': 'a.js',
            'download_url': 'https://raw.githubusercontent.com/o/r/main/a.js',
          },
          {'type': 'file', 'name': 'b.json', 'download_url': null},
        ]),
        ref: ref,
        branch: 'main',
      );
      expect(files.map((f) => f.name), ['a.js', 'b.json']);
      expect(
        files.last.downloadUrl,
        'https://raw.githubusercontent.com/o/r/main/b.json',
      );
    });

    test('a non-array payload throws', () {
      expect(
        () => GithubLinks.parseContents('{"message":"Not Found"}',
            ref: ref, branch: 'main'),
        throwsFormatException,
      );
    });
  });

  group('listFiles', () {
    test('resolves the default branch, then lists', () async {
      final calls = <String>[];
      final files = await GithubLinks.listFiles(
        const GithubRepoRef(owner: 'o', repo: 'r'),
        fetcher: (url) async {
          calls.add(url);
          if (url.endsWith('/repos/o/r')) {
            return '{"default_branch":"dev"}';
          }
          return '[{"type":"file","name":"x.json","download_url":"https://dl/x.json"}]';
        },
      );
      expect(calls.first, 'https://api.github.com/repos/o/r');
      expect(calls.last, contains('ref=dev'));
      expect(files.single.downloadUrl, 'https://dl/x.json');
    });
  });
}
