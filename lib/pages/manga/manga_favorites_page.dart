import 'package:anikumo/utils/tap_debouncer.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_modular/flutter_modular.dart';
import 'package:anikumo/bean/dialog/dialog_helper.dart';
import 'package:anikumo/bean/theme/violet_glass.dart';
import 'package:anikumo/bean/widget/empty_state_widget.dart';
import 'package:anikumo/modules/manga/manga_item.dart';
import 'package:anikumo/bean/widget/motion_kit.dart';
import 'package:anikumo/pages/manga/manga_widgets.dart';
import 'package:anikumo/services/manga/manga_api.dart';
import 'package:anikumo/services/manga/manga_extras.dart';
import 'package:anikumo/services/manga/manga_library.dart';
import 'package:anikumo/services/storage/storage.dart';
import 'package:anikumo/utils/constants.dart';

/// 收藏 tab — favorites grid with batch-15 upgrades: update
/// badges （追新）, sorting + pinning, and a multi-select manage
/// mode (long-press).
class MangaFavoritesTab extends StatefulWidget {
  const MangaFavoritesTab({super.key});

  @override
  State<MangaFavoritesTab> createState() => _MangaFavoritesTabState();
}

class _MangaFavoritesTabState extends State<MangaFavoritesTab> {
  MangaFavoriteSort _sort = MangaFavoriteSort.recentRead;
  Set<String>? _selection;
  Map<String, int> _updates = const {};
  bool _checking = false;
  bool _checkedOnce = false;

  @override
  void initState() {
    super.initState();
    // Batch 37: rebuild when the library changes — this tab
    // stays mounted in the zone's cross-fade stack, and a
    // favorite added on a detail page never appeared here
    // until the app restarted.
    MangaLibraryStore.revision.addListener(_onLibraryChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_checkedOnce) {
        _checkedOnce = true;
        _checkUpdates();
      }
    });
  }

  @override
  void dispose() {
    MangaLibraryStore.revision.removeListener(_onLibraryChanged);
    super.dispose();
  }

  void _onLibraryChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _checkUpdates() async {
    if (_checking) return;
    final favorites = MangaLibraryStore.loadFavorites();
    if (favorites.isEmpty) return;
    setState(() => _checking = true);
    final targets = favorites.take(24).toList();
    final current = <String, int>{};
    // Small concurrency: chunks of 3 chapter-list fetches.
    for (var i = 0; i < targets.length; i += 3) {
      final chunk = targets.skip(i).take(3);
      await Future.wait([
        for (final favorite in chunk)
          () async {
            try {
              final chapters = await MangaApi.fetchChapters(
                MangaItem(
                  id: favorite.id,
                  title: favorite.title,
                  description: '',
                  coverUrl: favorite.coverUrl,
                  author: '',
                  status: '',
                  year: null,
                  tags: const [],
                  source: favorite.source,
                ),
                fresh: true,
              );
              if (chapters.isNotEmpty) {
                current[favorite.key] = chapters.length;
              }
            } catch (_) {
              // A failed fetch just skips this favorite.
            }
          }(),
      ]);
    }
    if (!mounted) return;
    final known = MangaExtrasStore.loadKnownChapterCounts();
    // First-seen favorites become baselines, not "updates".
    final merged = {...known};
    for (final entry in current.entries) {
      merged.putIfAbsent(entry.key, () => entry.value);
    }
    await MangaExtrasStore.saveKnownChapterCounts(merged);
    if (!mounted) return;
    setState(() {
      _updates = mangaUpdatesFor(known, current);
      _checking = false;
    });
  }

  Future<void> _deleteSelected() async {
    final selection = _selection;
    if (selection == null || selection.isEmpty) return;
    final remaining = [
      for (final f in MangaLibraryStore.loadFavorites())
        if (!selection.contains(f.key)) f,
    ];
    await GStorage.putSetting(
      SettingsKeys.mangaFavoritesJson,
      MangaLibraryCodec.encodeFavorites(remaining),
    );
    if (!mounted) return;
    setState(() => _selection = null);
    AnikumoDialog.showToast(message: '已删除 ${selection.length} 本');
  }

  Future<void> _pinSelected() async {
    final selection = _selection;
    if (selection == null || selection.isEmpty) return;
    final pinned = {...MangaExtrasStore.loadPinned()};
    final allPinned = selection.every(pinned.contains);
    if (allPinned) {
      pinned.removeAll(selection);
    } else {
      pinned.addAll(selection);
    }
    await MangaExtrasStore.savePinned(pinned);
    if (!mounted) return;
    setState(() => _selection = null);
    AnikumoDialog.showToast(message: allPinned ? '已取消置顶' : '已置顶');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final favorites = MangaLibraryStore.loadFavorites();
    final pinned = MangaExtrasStore.loadPinned();
    final sorted = sortFavorites(
      favorites,
      pinned: pinned,
      progress: MangaLibraryStore.loadProgressMap(),
      ratings: MangaExtrasStore.loadRatings(),
      mode: _sort,
    );
    final columns = GStorage.getSetting(SettingsKeys.mangaGridColumns);
    final selecting = _selection != null;
    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
            child: selecting
                ? Row(
                    children: [
                      Text(
                        '已选 ${_selection!.length} 本',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () => setState(() {
                          _selection = {
                            for (final f in sorted) f.key,
                          };
                        }),
                        child: const Text('全选'),
                      ),
                      IconButton(
                        icon: const Icon(Icons.push_pin_outlined),
                        tooltip: '置顶/取消置顶',
                        onPressed: _pinSelected,
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        tooltip: '删除所选',
                        onPressed: _deleteSelected,
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        tooltip: '取消',
                        onPressed: () => setState(() => _selection = null),
                      ),
                    ],
                  )
                : Row(
                    children: [
                      Container(
                        width: 4,
                        height: 24,
                        decoration: BoxDecoration(
                          gradient: VioletGlass.gradient,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '收藏',
                        style: theme.textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '${favorites.length} 本',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: theme.colorScheme.outline),
                      ),
                      if (_updates.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Chip(
                          label: Text('${_updates.length} 部有更新'),
                          visualDensity: VisualDensity.compact,
                          side: BorderSide.none,
                          backgroundColor:
                              theme.colorScheme.primaryContainer,
                        ),
                      ],
                      const Spacer(),
                      if (_checking)
                        const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          ),
                        )
                      else
                        IconButton(
                          icon: const Icon(Icons.update_rounded),
                          tooltip: '检查更新',
                          onPressed: _checkUpdates,
                        ),
                      PopupMenuButton<MangaFavoriteSort>(
                        icon: const Icon(Icons.sort_rounded),
                        tooltip: '排序',
                        initialValue: _sort,
                        onSelected: (mode) => setState(() => _sort = mode),
                        itemBuilder: (context) => const [
                          PopupMenuItem(
                            value: MangaFavoriteSort.recentRead,
                            child: Text('最近在读'),
                          ),
                          PopupMenuItem(
                            value: MangaFavoriteSort.title,
                            child: Text('标题'),
                          ),
                          PopupMenuItem(
                            value: MangaFavoriteSort.rating,
                            child: Text('我的评分'),
                          ),
                          PopupMenuItem(
                            value: MangaFavoriteSort.addedOrder,
                            child: Text('收藏顺序'),
                          ),
                        ],
                      ),
                    ],
                  ),
          ),
          Expanded(
            child: favorites.isEmpty
                ? const GeneralEmptyState(
                    icon: Icons.collections_bookmark_outlined,
                    title: '还没有收藏，在详情页点 ♥ 就会出现在这里',
                  )
                : GridView.builder(
                    scrollCacheExtent: const ScrollCacheExtent.pixels(500),
                    padding: const EdgeInsets.fromLTRB(
                      StyleString.pagePadding,
                      8,
                      StyleString.pagePadding,
                      StyleString.sectionSpace,
                    ),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      mainAxisSpacing: 14,
                      crossAxisSpacing: 12,
                      childAspectRatio: 0.52,
                    ),
                    itemCount: sorted.length,
                    itemBuilder: (context, index) {
                      final favorite = sorted[index];
                      final item = MangaItem(
                        id: favorite.id,
                        title: favorite.title,
                        description: '',
                        coverUrl: favorite.coverUrl,
                        author: '',
                        status: '',
                        year: null,
                        tags: const [],
                        source: favorite.source,
                      );
                      final selected =
                          _selection?.contains(favorite.key) ?? false;
                      final newChapters = _updates[favorite.key];
                      return RepaintBoundary(
                        child: ScaleIn(
                        delay: Duration(milliseconds: (index % 8) * 30),
                        child: GestureDetector(
                        onLongPress: () => setState(() {
                          _selection = {...?_selection, favorite.key};
                        }),
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: MangaRailCard(
                                item: item,
                                width: double.infinity,
                                onTap: () {
                                  if (_selection != null) {
                                    setState(() {
                                      if (selected) {
                                        _selection!.remove(favorite.key);
                                      } else {
                                        _selection!.add(favorite.key);
                                      }
                                    });
                                    return;
                                  }
                                  if (TapDebouncer.accept(
                                      'manga:${item.source}:${item.id}')) {
                                    context
                                        .pushNamed(
                                          '/manga/detail',
                                          arguments: item,
                                        )
                                        .then((_) => mounted
                                            ? setState(() {})
                                            : null);
                                  }
                                },
                              ),
                            ),
                            if (pinned.contains(favorite.key))
                              const Positioned(
                                top: 6,
                                left: 6,
                                child: ScaleIn(
                                  child: Icon(
                                  Icons.push_pin_rounded,
                                  size: 16,
                                  color: Colors.white,
                                    shadows: [
                                      Shadow(
                                        color: Colors.black54,
                                        blurRadius: 4,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            if (newChapters != null)
                              Positioned(
                                top: 4,
                                right: 4,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.primary,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '+$newChapters 话',
                                    style: theme.textTheme.labelSmall
                                        ?.copyWith(
                                      color: theme.colorScheme.onPrimary,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                            if (selecting)
                              Positioned(
                                bottom: 34,
                                right: 4,
                                child: Icon(
                                  selected
                                      ? Icons.check_circle_rounded
                                      : Icons.radio_button_unchecked,
                                  color: selected
                                      ? theme.colorScheme.primary
                                      : Colors.white70,
                                  size: 24,
                                ),
                              ),
                          ],
                        ),
                        ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
