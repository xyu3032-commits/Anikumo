// Manga models parsed from the MangaDex API.
//
// The parsing half is pure and unit-tested: MangaDex entities carry
// localized maps for title/description and relationships for the
// cover file and author, all normalized here into flat models.

/// Picks a display string from a MangaDex localized text map,
/// preferring Simplified Chinese, then Traditional, English,
/// Japanese, then any available value.
String pickLocalizedText(Map<dynamic, dynamic>? texts) {
  if (texts == null || texts.isEmpty) return '';
  for (final key in const ['zh', 'zh-hk', 'en', 'ja', 'ko']) {
    final value = texts[key];
    if (value is String && value.trim().isNotEmpty) return value;
  }
  for (final value in texts.values) {
    if (value is String && value.trim().isNotEmpty) return value;
  }
  return '';
}

class MangaItem {
  const MangaItem({
    required this.id,
    required this.title,
    required this.description,
    required this.coverUrl,
    required this.author,
    required this.status,
    required this.year,
    required this.tags,
    this.source = 'mangadex',
    this.headers = const {},
    this.coverTransformOf,
  });

  final String id;
  final String title;
  final String description;

  /// 512px cover image URL ('' when the entry has no cover).
  final String coverUrl;
  final String author;

  /// ongoing / completed / hiatus / cancelled / '' when unknown.
  final String status;
  final int? year;
  final List<String> tags;

  /// Which source this entry belongs to ('mangadex', 'zaimanhua',
  /// 'komiic', or an installed source's id). Identity is scoped by
  /// source: the same numeric id in two sources is two manga.
  final String source;

  /// Extra HTTP headers needed to load this entry's images
  /// (e.g. a Referer some CDNs require); empty for most sources.
  final Map<String, String> headers;

  /// Batch 102: when the source's `onThumbnailLoad` config
  /// carried an `onResponse` byte transform, the ORIGINAL
  /// cover url the hook was called with (the engine-side
  /// registry key); cover widgets download [coverUrl], run
  /// the bytes through the transform, and display the result.
  /// Persisted in snapshots so stored favorites keep working.
  final String? coverTransformOf;

  /// Headers for loading the cover: the entry's own headers, or
  /// the source's well-known defaults when none were stored.
  Map<String, String> get coverHeaders {
    if (headers.isNotEmpty) return headers;
    return switch (source) {
      'komiic' => const {'Referer': 'https://komiic.com/'},
      _ => const {},
    };
  }

  /// Storage identity: source-scoped so ids can collide freely
  /// across sources.
  String get storageKey => '$source:$id';

  MangaItem copyWith({
    String? title,
    String? description,
    String? coverUrl,
    String? author,
    String? status,
    int? year,
    List<String>? tags,
    Map<String, String>? headers,
    String? coverTransformOf,
  }) {
    return MangaItem(
      id: id,
      title: title ?? this.title,
      description: description ?? this.description,
      coverUrl: coverUrl ?? this.coverUrl,
      author: author ?? this.author,
      status: status ?? this.status,
      year: year ?? this.year,
      tags: tags ?? this.tags,
      source: source,
      headers: headers ?? this.headers,
      coverTransformOf: coverTransformOf ?? this.coverTransformOf,
    );
  }

  /// Batch 25: flat snapshot form for the disk SWR store
  /// (home-section popular lists). Mirrors every field so a
  /// restored item is indistinguishable from a fresh one.
  Map<String, dynamic> toSnapshot() => {
        'id': id,
        'title': title,
        'description': description,
        'coverUrl': coverUrl,
        'author': author,
        'status': status,
        'year': year,
        'tags': tags,
        'source': source,
        'headers': headers,
        if (coverTransformOf != null)
          'coverTransformOf': coverTransformOf,
      };

  factory MangaItem.fromSnapshot(Map<String, dynamic> json) {
    return MangaItem(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      coverUrl: json['coverUrl'] as String? ?? '',
      author: json['author'] as String? ?? '',
      status: json['status'] as String? ?? '',
      year: (json['year'] as num?)?.toInt(),
      tags: (json['tags'] as List?)?.whereType<String>().toList() ??
          const [],
      source: json['source'] as String? ?? 'mangadex',
      headers: (json['headers'] as Map?)?.map(
            (k, v) => MapEntry(k.toString(), v.toString()),
          ) ??
          const {},
      coverTransformOf: json['coverTransformOf'] as String?,
    );
  }

  String get statusLabel => switch (status) {
        'ongoing' => '连载中',
        'completed' => '已完结',
        'hiatus' => '休刊',
        'cancelled' => '已取消',
        _ => '',
      };

  factory MangaItem.fromApi(Map<String, dynamic> json) {
    final attributes =
        (json['attributes'] as Map?)?.cast<String, dynamic>() ?? const {};
    var title = pickLocalizedText(
      (attributes['title'] as Map?)?.cast<dynamic, dynamic>(),
    );
    if (title.isEmpty) {
      final altTitles = attributes['altTitles'];
      if (altTitles is List) {
        for (final alt in altTitles) {
          if (alt is Map) {
            title = pickLocalizedText(alt.cast<dynamic, dynamic>());
            if (title.isNotEmpty) break;
          }
        }
      }
    }
    final id = json['id']?.toString() ?? '';

    var coverFile = '';
    var author = '';
    final relationships = json['relationships'];
    if (relationships is List) {
      for (final rel in relationships) {
        if (rel is! Map) continue;
        final relAttributes = (rel['attributes'] as Map?)
                ?.cast<String, dynamic>() ??
            const <String, dynamic>{};
        if (rel['type'] == 'cover_art' && coverFile.isEmpty) {
          coverFile = relAttributes['fileName']?.toString() ?? '';
        }
        if (rel['type'] == 'author' && author.isEmpty) {
          author = relAttributes['name']?.toString() ?? '';
        }
      }
    }

    final tags = <String>[];
    final rawTags = attributes['tags'];
    if (rawTags is List) {
      for (final tag in rawTags) {
        if (tag is! Map) continue;
        final tagAttributes =
            (tag['attributes'] as Map?)?.cast<String, dynamic>() ?? const {};
        final name = pickLocalizedText(
          (tagAttributes['name'] as Map?)?.cast<dynamic, dynamic>(),
        );
        if (name.isNotEmpty) tags.add(name);
      }
    }

    return MangaItem(
      id: id,
      title: title,
      description: pickLocalizedText(
        (attributes['description'] as Map?)?.cast<dynamic, dynamic>(),
      ),
      coverUrl: coverFile.isEmpty
          ? ''
          : 'https://uploads.mangadex.org/covers/$id/$coverFile.512.jpg',
      author: author,
      status: attributes['status']?.toString() ?? '',
      year: (attributes['year'] as num?)?.toInt(),
      tags: tags,
    );
  }
}

class MangaChapter {
  const MangaChapter({
    required this.id,
    required this.volume,
    required this.chapter,
    required this.title,
    required this.language,
    required this.pages,
    required this.publishedAt,
  });

  final String id;
  final String? volume;

  /// Chapter number as a string ('12.5' is legal); null for oneshots.
  final String? chapter;
  final String title;
  final String language;
  final int pages;
  final DateTime? publishedAt;

  String get displayLabel {
    final number = chapter;
    final base = number == null || number.isEmpty ? '番外/单话' : '第 $number 话';
    return title.isEmpty ? base : '$base $title';
  }

  /// Subtitle for the detail page's chapter list (batch 25):
  /// the page count only when the source actually knows it
  /// (JS sources learn it per chapter when opened, so they
  /// report 0 — showing "0 页" was a device-reported bug),
  /// plus the language when reported; empty when neither.
  String get detailSubtitle => [
        if (pages > 0) '$pages 页',
        if (languageLabel.isNotEmpty) languageLabel,
      ].join(' · ');

  String get languageLabel => switch (language) {
        'zh' => '简中',
        'zh-hk' => '繁中',
        'en' => 'English',
        'ja' => '日本語',
        _ => language,
      };

  factory MangaChapter.fromApi(Map<String, dynamic> json) {
    final attributes =
        (json['attributes'] as Map?)?.cast<String, dynamic>() ?? const {};
    return MangaChapter(
      id: json['id']?.toString() ?? '',
      volume: attributes['volume']?.toString(),
      chapter: attributes['chapter']?.toString(),
      title: attributes['title']?.toString() ?? '',
      language: attributes['translatedLanguage']?.toString() ?? '',
      pages: (attributes['pages'] as num?)?.toInt() ?? 0,
      publishedAt: DateTime.tryParse(
        attributes['publishAt']?.toString() ?? '',
      ),
    );
  }

  /// A chapter is readable on MangaDex itself only when it has pages
  /// and is not a redirect to an external site.
  bool get isReadable => pages > 0;
}

/// Builds full page image URLs from an at-home server response:
/// `{baseUrl}/data/{hash}/{fileName}` for the original-quality files,
/// or `{baseUrl}/data-saver/{hash}/{fileName}` for the compressed
/// data-saver renditions.
List<String> buildChapterPageUrls(
  String baseUrl,
  String hash,
  List<dynamic> fileNames, {
  bool saver = false,
}) {
  final segment = saver ? 'data-saver' : 'data';
  return [
    for (final name in fileNames) '$baseUrl/$segment/$hash/$name',
  ];
}

/// A MangaDex content tag, used by the 分类 (categories) tab.
class MangaTag {
  const MangaTag({
    required this.id,
    required this.name,
    required this.group,
  });

  final String id;
  final String name;

  /// genre / theme / format / content.
  final String group;

  String get groupLabel => switch (group) {
        'genre' => '题材',
        'theme' => '主题',
        'format' => '形式',
        'content' => '内容',
        _ => '其他',
      };

  factory MangaTag.fromApi(Map<String, dynamic> json) {
    final attributes =
        (json['attributes'] as Map?)?.cast<String, dynamic>() ?? const {};
    return MangaTag(
      id: json['id']?.toString() ?? '',
      name: pickLocalizedText(
        (attributes['name'] as Map?)?.cast<dynamic, dynamic>(),
      ),
      group: attributes['group']?.toString() ?? '',
    );
  }
}
