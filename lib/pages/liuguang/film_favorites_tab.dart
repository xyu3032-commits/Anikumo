import 'package:flutter/material.dart';
import 'package:liuguang_core/liuguang_core.dart';
import 'package:anikumo/bean/widget/anikumo_icons.dart';
import 'package:anikumo/pages/liuguang/film_widgets.dart';
import 'package:anikumo/services/liuguang/film_prefs.dart';
import 'package:anikumo/services/liuguang/film_auto_update.dart';
import 'package:anikumo/services/liuguang/video_engine.dart';

/// Batch 205: 收藏 — the engine favorites repository's
/// snapshots, as a poster grid. Long-press removes.
class FilmFavoritesTab extends StatefulWidget {
  const FilmFavoritesTab({super.key});

  @override
  State<FilmFavoritesTab> createState() => _FilmFavoritesTabState();
}

class _FilmFavoritesTabState extends State<FilmFavoritesTab> {
  List<MediaItem> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    VideoEngineService.instance.addListener(_reload);
    _reload();
  }

  @override
  void dispose() {
    VideoEngineService.instance.removeListener(_reload);
    super.dispose();
  }

  Future<void> _reload() async {
    try {
      final engine = await VideoEngineService.instance.engine();
      final favorites = await engine.favorites.list();
      _items = favorites
          .where((f) => f.mediaSnapshot.isNotEmpty)
          .map((f) => TVSeries.mediaFromJson(f.mediaSnapshot))
          .toList();
    } catch (_) {
      _items = [];
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _remove(MediaItem item) async {
    final engine = await VideoEngineService.instance.engine();
    await engine.favorites.remove(item.id);
    await _reload();
  }

  bool _checking = false;

  /// Batch 207 （自选功能）: 追剧更新检查 — compares each
  /// favorite's current remarks （更新至X集） against the
  /// stamp from the last check and reports what moved.
  /// First-ever check seeds the stamps silently.
  Future<void> _checkUpdates() async {
    if (_checking || _items.isEmpty) return;
    setState(() => _checking = true);
    try {
      final engine = await VideoEngineService.instance.engine();
      final stamps = FilmPrefs.favoriteStamps();
      final updated = <String>[];
      var seeded = 0;
      for (final item in _items) {
        final detail = await engine.getDetail(item.id);
        final remarks =
            detail?.item.raw['remarks']?.toString() ??
            item.raw['remarks']?.toString() ??
            '';
        final previous = stamps[item.id];
        if (previous == null) {
          stamps[item.id] = remarks;
          seeded++;
        } else if (previous != remarks && remarks.isNotEmpty) {
          updated.add('「${item.title}」$previous → $remarks');
          stamps[item.id] = remarks;
        }
      }
      await FilmPrefs.setFavoriteStamps(stamps);
      if (!mounted) return;
      final message = updated.isNotEmpty
          ? '有更新：\n${updated.join('\n')}'
          : seeded == _items.length && stamps.length <= _items.length
          ? '已记录当前进度，下次检查会对比是否有更新。'
          : '收藏的剧集暂时没有更新。';
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('追剧更新检查'),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('检查失败：$e')));
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_items.isEmpty) {
      return const FilmEmptyState(
        icon: AnikumoIcons.favorite_rounded,
        title: '还没有收藏',
        message: '在影片详情页点收藏后，会出现在这里。',
      );
    }
    return Column(
      children: [
        // Batch 221: editorial title bar.
        FilmEditorialTitle(
          eyebrow: 'COLLECTION · 收藏',
          title: filmHeadline(context, '收藏'),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 6, 8, 0),
          child: Row(
            children: [
              Text(
                '共 ${_items.length} 部',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _checking ? null : _checkUpdates,
                icon: _checking
                    ? const SizedBox(
                        width: 15,
                        height: 15,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(AnikumoIcons.system_update_rounded, size: 18),
                label: const Text('检查更新'),
              ),
            ],
          ),
        ),
        if (FilmAutoUpdate.pendingUpdates().isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
                child: Row(
                  children: [
                    const Icon(AnikumoIcons.system_update_rounded, size: 19),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '有更新：${FilmAutoUpdate.pendingUpdates().join('；')}',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                    TextButton(
                      onPressed: () async {
                        await FilmAutoUpdate.clearPending();
                        if (mounted) setState(() {});
                      },
                      child: const Text('知道了'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        Expanded(child: _grid(context)),
      ],
    );
  }

  Widget _grid(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 10,
        mainAxisSpacing: 12,
        childAspectRatio: 0.56,
      ),
      itemCount: _items.length,
      itemBuilder: (context, i) {
        final item = _items[i];
        return GestureDetector(
          onLongPress: () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (dialogContext) => AlertDialog(
                title: const Text('取消收藏'),
                content: Text('不再收藏「${item.title}」？'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(false),
                    child: const Text('保留'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(dialogContext).pop(true),
                    child: const Text('取消收藏'),
                  ),
                ],
              ),
            );
            if (ok == true) await _remove(item);
          },
          child: FilmPosterCard(
            item: item,
            onTap: () => openFilmDetail(context, item),
          ),
        );
      },
    );
  }
}
