import 'package:flutter_test/flutter_test.dart';
import 'package:anikumo/services/manga/manga_sources.dart';

void main() {
  test('extracts name/key/version from double-quoted fields', () {
    const code = '''
class Hitomi extends ComicSource {
  name = "hitomi.la";
  key = "hitomi";
  version = "1.1.2";
}
''';
    final meta = MangaSources.extractJsMetadata(code);
    expect(meta.name, 'hitomi.la');
    expect(meta.key, 'hitomi');
    expect(meta.version, '1.1.2');
  });

  test('extracts from semicolon-free single-line fields', () {
    const code = '''
class Nhentai extends ComicSource {
    name = "nhentai"
    key = "nhentai"
    version = "1.1.0"
}
''';
    final meta = MangaSources.extractJsMetadata(code);
    expect(meta.name, 'nhentai');
    expect(meta.key, 'nhentai');
    expect(meta.version, '1.1.0');
  });

  test('top-level helper code cannot shadow class fields', () {
    const code = '''
const name = "helper";
function key() { return "x"; }
class Cool extends ComicSource {
  name = 'CoolSource';
  key = 'cool';
}
''';
    final meta = MangaSources.extractJsMetadata(code);
    expect(meta.name, 'CoolSource');
    expect(meta.key, 'cool');
    expect(meta.version, '1.0.0');
  });

  test('missing key falls back to sanitized class name', () {
    const code = '''
class MyCoolSource extends ComicSource {
  name = "Mine";
}
''';
    final meta = MangaSources.extractJsMetadata(code);
    expect(meta.key, 'mycoolsource');
    expect(meta.name, 'Mine');
    expect(meta.version, '1.0.0');
  });
}
