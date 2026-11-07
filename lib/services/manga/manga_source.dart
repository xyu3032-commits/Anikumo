import 'package:anikumo/modules/manga/manga_item.dart';

/// One page of a chapter: an image URL plus any headers the
/// source's CDN requires to serve it.
class MangaPage {
  const MangaPage(this.url, {this.headers = const {}});

  final String url;
  final Map<String, String> headers;
}

/// Normalizes the many status spellings sources use into the
/// model's vocabulary (ongoing / completed / hiatus / cancelled).
String normalizeMangaStatus(String raw) {
  final value = raw.trim().toLowerCase();
  if (value.isEmpty) return '';
  if (value == 'ongoing' ||
      value.contains('连载') ||
      value.contains('連載')) {
    return 'ongoing';
  }
  if (value == 'completed' ||
      value.contains('完结') ||
      value.contains('完結') ||
      value.contains('已完')) {
    return 'completed';
  }
  if (value == 'hiatus') return 'hiatus';
  if (value == 'cancelled' || value.contains('腰斩')) return 'cancelled';
  return value;
}

/// A manga source — the zone's equivalent of one Anikumo rule
/// plugin or one Venera JS source. Implementations are either
/// native (hand-written against a documented API) or declarative
/// (built from a downloaded JSON definition).
abstract class MangaSource {
  String get id;
  String get name;
  String get description;

  /// Whether the 分类 tab can offer this source's tag list.
  bool get supportsTags => false;

  Future<List<MangaItem>> search(
    String keyword, {
    int limit = 30,
    int page = 1,
  });

  Future<List<MangaItem>> popular({int limit = 20, int page = 1});

  Future<List<MangaItem>> updated({int limit = 20, int page = 1});

  Future<List<MangaTag>> tags() async => const [];

  Future<List<MangaItem>> byTag(
    String tagId, {
    int limit = 30,
    int page = 1,
  }) async =>
      const [];

  /// The full chapter list for [manga], oldest first.
  Future<List<MangaChapter>> chapters(MangaItem manga);

  /// Page images for one chapter, in reading order.
  Future<List<MangaPage>> pages(MangaItem manga, MangaChapter chapter);

  /// Optional detail enrichment (description / tags the list
  /// endpoints don't carry). Null when the list data is complete.
  Future<MangaItem?> details(MangaItem manga) async => null;

  /// Batch 74: the source's account surface, or null when it
  /// has no account system. JS sources with an
  /// `account.login` function report one; other
  /// implementations return null.
  Future<MangaAccountInfo?> accountInfo() async => null;

  /// Signs in through the source's own login function.
  /// Only call when [accountInfo] reported a login.
  Future<void> login(String username, String password) async =>
      throw StateError('该源不支持账号登录');

  /// Signs out: the source's logout when it has one, plus
  /// clearing the session the host tracks.
  Future<void> logout() async {}
}

/// A snapshot of a source's account surface (batch 74).
class MangaAccountInfo {
  const MangaAccountInfo({
    required this.hasLogin,
    required this.hasLogout,
    required this.isLoggedIn,
    this.registerWebsite,
  });

  final bool hasLogin;
  final bool hasLogout;
  final bool isLoggedIn;

  /// Where the source wants users to register, if anywhere.
  final String? registerWebsite;
}
