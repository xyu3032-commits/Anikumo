import 'dart:convert';

import '../../models/novel_item.dart';
import 'legado_def.dart';
import 'moyuan_host.dart';

/// Batch 174: the per-source facade over the MoYuan
/// engine, shaped exactly like the calls
/// [LegadoNovelSource] makes. All novel book-source
/// traffic (search / explore / detail / chapters /
/// content) runs through the MoYuan JS engine via
/// [MoyuanHost]; this class only translates between the
/// bridge's JSON shapes and the app's models.
///
/// Item identity follows the engine's contract: a book
/// is its (source, bookUrl) pair, and the bridge's
/// kind field already carries the merged
/// classification/tag string the app's NovelItem.kind
/// holds.
class MoyuanEngine {
  MoyuanEngine(this.def);

  final LegadoSourceDef def;

  MoyuanHost get _host => MoyuanHost.instance;

  String get sourceId => def.id;

  Future<void> _sync() async {
    await _host.syncSourcesIfChanged();
    await _host.ensureSourceRegistered(def.raw);
  }

  /// One bridge call with sync-fetch replay (see
  /// MoyuanHost.callWithReplay).
  Future<dynamic> _bridge(String method, List<dynamic> args) {
    final encoded = args.map(jsonEncode).join(', ');
    return _host.callWithReplay(
      sourceId,
      '__moyuanBridge.$method($encoded)',
    );
  }

  static NovelItem _item(Map<String, dynamic> map, LegadoSourceDef def) {
    final item = NovelItem.fromJson(map);
    if (item == null) {
      return NovelItem(
        bookUrl: map['bookUrl']?.toString() ?? '',
        title: map['title']?.toString() ?? '',
        source: def.id,
        sourceName: def.name,
      );
    }
    if (item.source.isNotEmpty && item.sourceName.isNotEmpty) return item;
    return NovelItem(
      bookUrl: item.bookUrl,
      title: item.title,
      author: item.author,
      coverUrl: item.coverUrl,
      intro: item.intro,
      kind: item.kind,
      lastChapter: item.lastChapter,
      wordCount: item.wordCount,
      source: item.source.isEmpty ? def.id : item.source,
      sourceName: item.sourceName.isEmpty ? def.name : item.sourceName,
    );
  }

  static Map<String, dynamic> _itemJson(NovelItem item) => item.toJson();

  /// The item as this facade's calls must present it:
  /// the bridge resolves the owning source from the
  /// item, and an item restored or hand-built without
  /// its source stamp (stored reading state carries
  /// only bookUrl + title in places) would otherwise
  /// resolve to no source at all. This facade's def IS
  /// the owner, so stamp it in when missing.
  Map<String, dynamic> _ownedItemJson(NovelItem item) {
    final json = _itemJson(item);
    if ((json['source']?.toString() ?? '').isEmpty) {
      json['source'] = sourceId;
    }
    return json;
  }

  Future<List<NovelItem>> search(String key, {int page = 1}) async {
    await _sync();
    final out = await _bridge('search', [sourceId, key, page]);
    return [
      for (final e in (out as List? ?? const []))
        if (e is Map) _item(e.cast<String, dynamic>(), def),
    ];
  }

  Future<List<NovelItem>> explore(
    NovelExploreCategory category, {
    int page = 1,
  }) async {
    await _sync();
    final out = await _bridge('explore', [
      sourceId,
      {'title': category.title, 'url': category.url},
      page,
    ]);
    return [
      for (final e in (out as List? ?? const []))
        if (e is Map) _item(e.cast<String, dynamic>(), def),
    ];
  }

  /// Explore categories with their layout hints intact —
  /// the adapter (not the bridge) is the one that keeps
  /// each kind's style, and group headers ride along as
  /// empty-URL entries.
  Future<List<NovelExploreCategory>> exploreKinds() async {
    await _sync();
    final out = await _host.callWithReplay(
      sourceId,
      '__moyuanEngine.sources.get(${_js(sourceId)})'
      '.exploreCategories()',
    );
    return NovelExploreCategory.listFromKinds(
      (out as List? ?? const []).cast<dynamic>(),
    );
  }

  Future<NovelItem> bookInfo(NovelItem item) async {
    await _sync();
    final out = await _bridge('bookInfo', [_ownedItemJson(item)]);
    if (out is Map) return _item(out.cast<String, dynamic>(), def);
    return item;
  }

  Future<List<NovelChapter>> chapters(NovelItem item) async {
    await _sync();
    final out = await _bridge('chapters', [_ownedItemJson(item)]);
    final chapters = [
      for (final e in (out as List? ?? const []))
        if (e is Map) NovelChapter.fromJson(e.cast<String, dynamic>()),
    ].whereType<NovelChapter>().toList();
    // The contract the Dart engine kept (Batch 40): a
    // declared chapter-list rule that parses to nothing
    // is a failure, not an empty book — the reader page
    // must be able to tell the two apart.
    if (chapters.isEmpty &&
        (def.ruleToc['chapterList']?.toString().trim() ?? '')
            .isNotEmpty) {
      throw StateError(
        '目录页章节解析为空（${def.name}）：${item.bookUrl}',
      );
    }
    return chapters;
  }

  Future<List<NovelBlock>> content(
    NovelItem item,
    NovelChapter chapter,
  ) async =>
      (await contentDetailed(item, chapter)).blocks;

  Future<NovelContentResult> contentDetailed(
    NovelItem item,
    NovelChapter chapter,
  ) async {
    await _sync();
    final out = await _bridge('content', [
      _ownedItemJson(item),
      chapter.toJson(),
    ]);
    return blocksFromBridge(out);
  }

  /// Batch 184: strict conversion of the bridge's content
  /// payload ({blocks, truncated} since the same batch;
  /// a bare list is still accepted). Typing is exact:
  /// 'text' becomes a text block, 'image' an image block,
  /// and EVERYTHING else — unknown types, missing types,
  /// non-map entries — is dropped. The old default branch
  /// turned any non-image payload carrying a text field
  /// into a paragraph, which is how non-content (an audio
  /// URL from the bridge's old coercion, a diagnostic
  /// string, a future block type) could enter the reading
  /// stream disguised as chapter text. Blank paragraphs
  /// are dropped here too: a chapter of whitespace is an
  /// empty chapter, not a short one.
  static NovelContentResult blocksFromBridge(dynamic out) {
    var rawBlocks = const <dynamic>[];
    var truncated = false;
    if (out is Map) {
      final b = out['blocks'];
      if (b is List) rawBlocks = b;
      truncated = out['truncated'] == true;
    } else if (out is List) {
      rawBlocks = out;
    }
    final blocks = <NovelBlock>[];
    for (final e in rawBlocks) {
      if (e is! Map) continue;
      final map = e.cast<String, dynamic>();
      final type = map['type'];
      if (type == 'text') {
        final text = (map['text']?.toString() ?? '').trim();
        if (text.isNotEmpty) blocks.add(NovelTextBlock(text));
      } else if (type == 'image') {
        final url = map['url']?.toString() ?? '';
        if (url.isEmpty) continue;
        final headers = <String, String>{};
        final raw = map['headers'];
        if (raw is Map) {
          raw.forEach((k, v) {
            if (v != null) headers[k.toString()] = v.toString();
          });
        }
        blocks.add(NovelImageBlock(url, headers: headers));
      }
      // Unknown types fall through and are dropped.
    }
    return NovelContentResult(blocks, possiblyTruncated: truncated);
  }

  static String _js(String value) => jsonEncode(value);
}
