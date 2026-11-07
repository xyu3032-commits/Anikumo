import '../../models/novel_item.dart';
import 'legado_def.dart';
import 'legado_engine.dart';

/// A novel source in the 小说专区. Browsing calls (search /
/// explore) run on whichever source the caller picks;
/// detail calls always go back to the item's own source,
/// mirroring the manga zone's contract.
abstract class NovelSource {
  String get id;
  String get name;
  bool get builtin;
  int get type;

  /// The source's declared request headers (User-Agent
  /// especially) — the WebView reader mode presents them so
  /// the site treats it like the client the source expects.
  Map<String, String> get headers;

  /// Batch 68: the source's login page, when it declares
  /// one. Login-gated sources need the user to sign in once
  /// in a WebView; the harvested cookies then ride on the
  /// engine's requests via the LegadoHttp jar.
  String get loginUrl => '';

  Future<List<NovelItem>> search(String key, {int page = 1});
  List<NovelExploreCategory> get exploreCategories;
  Future<List<NovelItem>> explore(
    NovelExploreCategory category, {
    int page = 1,
  });
  Future<NovelItem> bookInfo(NovelItem item);
  Future<List<NovelChapter>> chapters(NovelItem item);
  Future<List<NovelBlock>> content(NovelItem item, NovelChapter chapter);
}

/// A [NovelSource] backed by a Legado definition + engine.
class LegadoNovelSource implements NovelSource {
  LegadoNovelSource(this.def) : engine = LegadoEngine(def);

  final LegadoSourceDef def;
  final LegadoEngine engine;

  /// TOC URLs learned from bookInfo, per book URL — the
  /// chapter list often lives on a different page than the
  /// info page.
  final Map<String, String> _tocUrls = {};

  @override
  String get id => def.id;

  @override
  String get name => def.name;

  @override
  bool get builtin => def.builtin;

  @override
  int get type => def.type;

  @override
  Map<String, String> get headers => def.headers;

  @override
  String get loginUrl => def.raw['loginUrl']?.toString() ?? '';

  @override
  Future<List<NovelItem>> search(String key, {int page = 1}) =>
      engine.search(key, page: page);

  @override
  List<NovelExploreCategory> get exploreCategories =>
      def.exploreCategories;

  @override
  Future<List<NovelItem>> explore(
    NovelExploreCategory category, {
    int page = 1,
  }) =>
      engine.explore(category, page: page);

  @override
  Future<NovelItem> bookInfo(NovelItem item) async {
    final (enriched, tocUrl) = await engine.bookInfo(item);
    _tocUrls[item.bookUrl] = tocUrl;
    return enriched;
  }

  @override
  Future<List<NovelChapter>> chapters(NovelItem item) async {
    // Batch 40: do not depend on bookInfo having run first.
    // The detail page loads info and chapters in parallel,
    // so the cache could still be cold (or bookInfo failed
    // silently) and chapters then parsed the INFO page as
    // if it were the TOC page — sources whose chapter list
    // lives on a separate page （速读谷 etc.) came back
    // empty. Resolve the TOC URL here when it is unknown.
    var tocUrl = _tocUrls[item.bookUrl];
    if (tocUrl == null) {
      final (_, resolved) = await engine.bookInfo(item);
      tocUrl = resolved;
      _tocUrls[item.bookUrl] = resolved;
    }
    return engine.chapters(item, tocUrl: tocUrl);
  }

  @override
  Future<List<NovelBlock>> content(
    NovelItem item,
    NovelChapter chapter,
  ) =>
      engine.content(chapter);
}
