import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:liuguang_core/liuguang_core.dart';

import 'package:anikumo/bean/dialog/dialog.dart';
import 'package:anikumo/bean/widget/anikumo_icons.dart';
import 'package:anikumo/modules/bangumi/bangumi_collection.dart';
import 'package:anikumo/modules/bangumi/bangumi_collection_type.dart';
import 'package:anikumo/pages/liuguang/film_widgets.dart';
import 'package:anikumo/request/apis/bangumi_api.dart';
import 'package:anikumo/services/liuguang/cms_api_source.dart';
import 'package:anikumo/services/liuguang/film_accounts.dart';
import 'package:anikumo/services/liuguang/video_engine.dart';

/// Batch 254: 我的云端片单 — the works the user keeps on
/// their TMDB and Bangumi accounts, pulled into the film
/// zone. Tapping one resolves it against the installed
/// sources and opens the in-app detail, where the usual
/// 收藏 / 下载 / 播放 actions take over.
class FilmCloudListsPage extends StatefulWidget {
  const FilmCloudListsPage({super.key});

  @override
  State<FilmCloudListsPage> createState() => _FilmCloudListsPageState();
}

class _FilmCloudListsPageState extends State<FilmCloudListsPage> {
  bool _loading = true;
  List<TmdbAccountItem> _tmdbWatchlist = const [];
  List<TmdbAccountItem> _tmdbFavorites = const [];
  List<BangumiCollection> _bgm = const [];
  String? _opening;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final results = await Future.wait<dynamic>([
      if (TmdbAccount.connected)
        TmdbAccount.fetchList('watchlist')
      else
        Future.value(const <TmdbAccountItem>[]),
      if (TmdbAccount.connected)
        TmdbAccount.fetchList('favorite')
      else
        Future.value(const <TmdbAccountItem>[]),
      _loadBangumi(),
    ]);
    if (!mounted) return;
    setState(() {
      _tmdbWatchlist = results[0] as List<TmdbAccountItem>;
      _tmdbFavorites = results[1] as List<TmdbAccountItem>;
      _bgm = results[2] as List<BangumiCollection>;
      _loading = false;
    });
  }

  Future<List<BangumiCollection>> _loadBangumi() async {
    if (!BangumiAccount.connected) return const [];
    try {
      var username = BangumiAccount.username;
      if (username.isEmpty) {
        username = await BangumiAccount.verify() ?? '';
      }
      if (username.isEmpty) return const [];
      final all = await BangumiApi.getBangumiCollectibles(
        username: username,
        includeBangumiTypes: const [
          BangumiCollectionType.watching,
          BangumiCollectionType.planToWatch,
          BangumiCollectionType.watched,
        ],
        limit: 50,
      );
      // Anime subjects (type 2 in Bangumi's own scheme
      // ride along in the same list); the film zone shows
      // everything the account holds — the source match
      // decides playability, not the shelf.
      return all;
    } catch (_) {
      return const [];
    }
  }

  Future<void> _open({
    required String title,
    required int? year,
    required bool isSeries,
    required String busyKey,
  }) async {
    if (_opening != null) return;
    setState(() => _opening = busyKey);
    try {
      final engine = await VideoEngineService.instance.engine();
      final page = await engine.search(SearchRequest(keyword: title));
      MediaItem? pick;
      for (final item in page.items) {
        if (cmsMatchesTmdbWork(
          item,
          title: title,
          year: year,
          isSeries: isSeries,
        )) {
          pick = item;
          break;
        }
      }
      if (!mounted) return;
      if (pick == null) {
        AnikumoDialog.showToast(
          context: context,
          message: '已装的接口里暂时没找到《$title》',
        );
        return;
      }
      openFilmDetail(context, pick);
    } catch (_) {
      if (mounted) {
        AnikumoDialog.showToast(context: context, message: '查找失败，请稍后重试');
      }
    } finally {
      if (mounted) setState(() => _opening = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bgmWatching = _bgm
        .where((c) => c.type == BangumiCollectionType.watching)
        .toList();
    final bgmPlan = _bgm
        .where((c) => c.type == BangumiCollectionType.planToWatch)
        .toList();
    final bgmWatched = _bgm
        .where((c) => c.type == BangumiCollectionType.watched)
        .toList();
    final empty =
        _tmdbWatchlist.isEmpty && _tmdbFavorites.isEmpty && _bgm.isEmpty;
    return Scaffold(
      appBar: AppBar(title: const Text('我的云端片单')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : empty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  '云端还没有片单。\n在 TMDB / Bangumi 上收藏或标记想看的作品，'
                  '就会出现在这里；点开任意一部即可在本应用里找源观看、下载。',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                if (_tmdbWatchlist.isNotEmpty) ...[
                  _header(context, 'TMDB · 想看'),
                  for (final item in _tmdbWatchlist) _tmdbRow(item),
                ],
                if (_tmdbFavorites.isNotEmpty) ...[
                  _header(context, 'TMDB · 收藏'),
                  for (final item in _tmdbFavorites) _tmdbRow(item),
                ],
                if (bgmWatching.isNotEmpty) ...[
                  _header(context, 'Bangumi · 在看'),
                  for (final c in bgmWatching) _bgmRow(c),
                ],
                if (bgmPlan.isNotEmpty) ...[
                  _header(context, 'Bangumi · 想看'),
                  for (final c in bgmPlan) _bgmRow(c),
                ],
                if (bgmWatched.isNotEmpty) ...[
                  _header(context, 'Bangumi · 看过'),
                  for (final c in bgmWatched) _bgmRow(c),
                ],
              ],
            ),
    );
  }

  Widget _header(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 16, 0, 8),
      child: Text(
        text,
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
      ),
    );
  }

  Widget _poster(String? url) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 46,
        height: 64,
        child: url == null || url.isEmpty
            ? const ColoredBox(color: Colors.black12, child: Icon(AnikumoIcons.movie_rounded))
            : CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                errorWidget: (_, _, _) =>
                    const ColoredBox(color: Colors.black12, child: Icon(AnikumoIcons.movie_rounded)),
              ),
      ),
    );
  }

  Widget _tmdbRow(TmdbAccountItem item) {
    final busy = _opening == 'tmdb-${item.tmdbId}';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: _poster(item.posterUrl),
      title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [
          if (item.year != null) '${item.year}',
          item.isSeries ? '剧集' : '电影',
          if (item.score > 0) 'TMDB ${item.score.toStringAsFixed(1)}',
        ].join(' · '),
      ),
      trailing: busy
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(AnikumoIcons.chevron_right_rounded),
      onTap: () => _open(
        title: item.title,
        year: item.year,
        isSeries: item.isSeries,
        busyKey: 'tmdb-${item.tmdbId}',
      ),
    );
  }

  Widget _bgmRow(BangumiCollection c) {
    final title = c.nameCn.isNotEmpty ? c.nameCn : c.name;
    final year = c.date != null && c.date!.length >= 4
        ? int.tryParse(c.date!.substring(0, 4))
        : null;
    final busy = _opening == 'bgm-${c.bangumiId}';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: _poster(c.images['common'] ?? c.images['medium']),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [
          if (year != null) '$year',
          if (c.score > 0) 'Bangumi ${c.score.toStringAsFixed(1)}',
          if (c.eps > 0) '全 ${c.eps} 集',
        ].join(' · '),
      ),
      trailing: busy
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(AnikumoIcons.chevron_right_rounded),
      onTap: () => _open(
        title: title,
        year: year,
        // Bangumi film-zone subjects span anime series
        // and live-action; series matching is the safer
        // default for episode-bearing works.
        isSeries: true,
        busyKey: 'bgm-${c.bangumiId}',
      ),
    );
  }
}
