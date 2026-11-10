/// Novel models for the 小说专区 (Legado book-source zone).
///
/// Identity is source-scoped, exactly like the manga zone:
/// [storageKey] = 'sourceId::bookUrl'. A book URL is the
/// Legado identity of a book, so it doubles as the item id.
class NovelItem {
  const NovelItem({
    required this.bookUrl,
    required this.title,
    this.author = '',
    this.coverUrl = '',
    this.intro = '',
    this.kind = '',
    this.lastChapter = '',
    this.wordCount = '',
    this.source = '',
    this.sourceName = '',
  });

  final String bookUrl;
  final String title;
  final String author;
  final String coverUrl;
  final String intro;
  final String kind;
  final String lastChapter;
  final String wordCount;

  /// Legado source id (its bookSourceUrl) that produced this
  /// item; detail/chapter/content calls always go back to it.
  final String source;
  final String sourceName;

  String get id => bookUrl;
  String get storageKey => '$source::$bookUrl';

  NovelItem copyWith({
    String? title,
    String? author,
    String? coverUrl,
    String? intro,
    String? kind,
    String? lastChapter,
    String? wordCount,
  }) {
    return NovelItem(
      bookUrl: bookUrl,
      title: title ?? this.title,
      author: author ?? this.author,
      coverUrl: coverUrl ?? this.coverUrl,
      intro: intro ?? this.intro,
      kind: kind ?? this.kind,
      lastChapter: lastChapter ?? this.lastChapter,
      wordCount: wordCount ?? this.wordCount,
      source: source,
      sourceName: sourceName,
    );
  }

  Map<String, dynamic> toJson() => {
        'bookUrl': bookUrl,
        'title': title,
        'author': author,
        'coverUrl': coverUrl,
        'intro': intro,
        'kind': kind,
        'lastChapter': lastChapter,
        'wordCount': wordCount,
        'source': source,
        'sourceName': sourceName,
      };

  static NovelItem? fromJson(Map<dynamic, dynamic> json) {
    final url = json['bookUrl']?.toString() ?? '';
    if (url.isEmpty) return null;
    return NovelItem(
      bookUrl: url,
      title: json['title']?.toString() ?? '',
      author: json['author']?.toString() ?? '',
      coverUrl: json['coverUrl']?.toString() ?? '',
      intro: json['intro']?.toString() ?? '',
      kind: json['kind']?.toString() ?? '',
      lastChapter: json['lastChapter']?.toString() ?? '',
      wordCount: json['wordCount']?.toString() ?? '',
      source: json['source']?.toString() ?? '',
      sourceName: json['sourceName']?.toString() ?? '',
    );
  }
}

/// One chapter of a novel: a title and the URL its content is
/// fetched from.
class NovelChapter {
  const NovelChapter({required this.title, required this.url, this.webView = false});

  final String title;
  final String url;

  /// The source declared this chapter WebView-only
  /// (`{"webView": true}` in the chapter URL options): its
  /// content is injected by page scripts and only a real
  /// browser rendering shows it (image chapters, typically).
  final bool webView;

  Map<String, dynamic> toJson() => {
        'title': title,
        'url': url,
        if (webView) 'webView': true,
      };

  static NovelChapter? fromJson(Map<dynamic, dynamic> json) {
    final url = json['url']?.toString() ?? '';
    if (url.isEmpty) return null;
    return NovelChapter(
      title: json['title']?.toString() ?? '',
      url: url,
      webView: json['webView'] == true,
    );
  }
}

/// One block of chapter content: a text paragraph or an
/// inline image (light novels carry illustrations; type-2
/// sources are image-only).
sealed class NovelBlock {
  const NovelBlock();
}

class NovelTextBlock extends NovelBlock {
  const NovelTextBlock(this.text);
  final String text;
}

class NovelImageBlock extends NovelBlock {
  const NovelImageBlock(this.url, {this.headers = const {}});
  final String url;
  final Map<String, String> headers;
}

/// Batch 184: a chapter's content plus its completeness
/// signal. [possiblyTruncated] means the engine stopped
/// following the chapter's own pagination before it ran
/// out (its page cap), so the blocks are real but the
/// chapter may continue beyond them — the reader must not
/// present such a chapter as verified-complete.
class NovelContentResult {
  const NovelContentResult(this.blocks, {this.possiblyTruncated = false});

  final List<NovelBlock> blocks;
  final bool possiblyTruncated;
}

/// Batch 184: does this block list carry anything a
/// reader can actually read? A list of whitespace-only
/// paragraphs is not content — treating list non-emptiness
/// as success is what let blank chapters render as a bare
/// chapter-end marker. Shared by the reader (empty-state
/// decision) and downloads (refusing to cache blank or
/// garbage chapters).
bool novelBlocksHaveContent(List<NovelBlock> blocks) => blocks.any(
      (b) => switch (b) {
        NovelTextBlock(:final text) => text.trim().isNotEmpty,
        NovelImageBlock(:final url) => url.isNotEmpty,
      },
    );

/// A named explore section of a source (from its exploreUrl
/// declaration).
class NovelExploreCategory {
  const NovelExploreCategory({
    required this.title,
    required this.url,
    this.flexBasis,
    this.flexGrow,
  });

  final String title;
  final String url;

  /// Batch 173: the kind's declared layout hints
  /// (style.layout_flexBasisPercent / layout_flexGrow) —
  /// dynamic explore scripts size group headers at 1.0 and
  /// item chips at 0.25, typically.
  final double? flexBasis;
  final double? flexGrow;

  /// A kind with no URL is a group header row in the
  /// reference, not a fetchable category.
  bool get isHeader => url.isEmpty;

  static double? _num(dynamic v) =>
      v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '');

  /// Build categories from decoded kind objects (the
  /// shape dynamic explore scripts return and static JSON
  /// declarations use). Entries keep their order; entries
  /// with an empty title are dropped, empty-URL entries
  /// stay as headers.
  static List<NovelExploreCategory> listFromKinds(List<dynamic> kinds) {
    final out = <NovelExploreCategory>[];
    for (final e in kinds) {
      if (e is! Map) continue;
      final title = e['title']?.toString() ?? '';
      if (title.isEmpty) continue;
      final style = e['style'];
      out.add(NovelExploreCategory(
        title: title,
        url: e['url']?.toString() ?? '',
        flexBasis: style is Map ? _num(style['layout_flexBasisPercent']) : null,
        flexGrow: style is Map ? _num(style['layout_flexGrow']) : null,
      ));
    }
    return out;
  }
}
