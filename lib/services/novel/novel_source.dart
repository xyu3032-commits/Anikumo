import 'package:flutter/foundation.dart';

import '../../models/novel_item.dart';
import 'legado_def.dart';
import 'moyuan_engine.dart';
import 'moyuan_host.dart';

/// A novel source in the 小说专区. Browsing calls (search /
/// explore) run on whichever source the caller picks;
/// detail calls always go back to the item's own source,
/// mirroring the manga zone's contract.
abstract class NovelSource {
  /// Batch 173: bumped whenever a source's dynamic
  /// explore kinds finish resolving.
  static final kindsRevision = ValueNotifier<int>(0);

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
  /// engine's requests via its cookie jar.
  String get loginUrl => '';

  Future<List<NovelItem>> search(String key, {int page = 1});
  List<NovelExploreCategory> get exploreCategories;

  /// Batch 173: dynamic explore declarations (a script
  /// exploreUrl) resolve asynchronously — [exploreCategories]
  /// only holds the resolved list after [ensureExploreKinds]
  /// completes; before that it holds the static reading,
  /// which for a script declaration is a bogus single entry
  /// and must not be fetched. UI surfaces check
  /// [hasDynamicExplore] / [exploreKindsResolved] and call
  /// [ensureExploreKinds], listening to [kindsRevision]
  /// for the swap.
  bool get hasDynamicExplore;
  bool get exploreKindsResolved;
  Future<void> ensureExploreKinds();

  Future<List<NovelItem>> explore(
    NovelExploreCategory category, {
    int page = 1,
  });
  Future<NovelItem> bookInfo(NovelItem item);
  Future<List<NovelChapter>> chapters(NovelItem item);
  Future<List<NovelBlock>> content(NovelItem item, NovelChapter chapter);
}

/// A [NovelSource] backed by a source definition.
/// Batch 174: the engine behind it is the MoYuan JS
/// engine (see moyuan_engine.dart) — the bridge resolves
/// each book's TOC internally on every call, so the old
/// Dart-side tocUrl cache is gone; chapters() never
/// depends on bookInfo having run first.
class LegadoNovelSource implements NovelSource {
  LegadoNovelSource(this.def) : engine = MoyuanEngine(def);

  final LegadoSourceDef def;
  final MoyuanEngine engine;

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

  /// Batch 173: script-resolved explore kinds, cached on
  /// the instance (registry instances are memoized, so
  /// this lives exactly as long as the installed def).
  List<NovelExploreCategory>? _kinds;
  Future<void>? _kindsFlight;
  bool _kindsFailed = false;

  @override
  bool get hasDynamicExplore {
    final raw = def.exploreUrlRaw.trim();
    return raw.startsWith('@js:') || raw.contains('<js>');
  }

  @override
  bool get exploreKindsResolved =>
      !hasDynamicExplore || _kinds != null || _kindsFailed;

  @override
  Future<void> ensureExploreKinds() {
    if (!hasDynamicExplore || _kinds != null) return Future.value();
    return _kindsFlight ??= () async {
      try {
        _kinds = await engine.exploreKinds();
        _kindsFailed = false;
      } catch (_) {
        // Resolution failed — no categories beats fetching
        // the bogus static entry as an address. The failure is
        // NOT cached as an empty success: the next visit may
        // retry, so a transient cold-start failure cannot cost
        // the whole session its categories.
        _kindsFailed = true;
      }
      _kindsFlight = null;
      NovelSource.kindsRevision.value++;
    }();
  }

  @override
  List<NovelExploreCategory> get exploreCategories =>
      _kinds ?? (_kindsFailed ? const [] : def.exploreCategories);

  @override
  Future<List<NovelItem>> explore(
    NovelExploreCategory category, {
    int page = 1,
  }) =>
      engine.explore(category, page: page);

  @override
  Future<NovelItem> bookInfo(NovelItem item) => engine.bookInfo(item);

  @override
  Future<List<NovelChapter>> chapters(NovelItem item) =>
      engine.chapters(item);

  @override
  Future<List<NovelBlock>> content(
    NovelItem item,
    NovelChapter chapter,
  ) =>
      guardDartStack(
        () => engine.content(item, chapter),
        'Dart 正文层',
        'source: ${def.name} (${def.id}), chapter: ${chapter.url}',
      );

  /// Batch 184: [content] with its completeness signal
  /// (see [NovelContentResult]). Deliberately NOT part of
  /// the [NovelSource] interface: sources implement that
  /// interface (they do not extend it), so a new member
  /// there would break every implementation; [NovelApi]
  /// routes here by type instead, and every other source
  /// keeps the unflagged default.
  Future<NovelContentResult> contentDetailed(
    NovelItem item,
    NovelChapter chapter,
  ) =>
      guardDartStack(
        () => engine.contentDetailed(item, chapter),
        'Dart 正文层',
        'source: ${def.name} (${def.id}), chapter: ${chapter.url}',
      );
}
