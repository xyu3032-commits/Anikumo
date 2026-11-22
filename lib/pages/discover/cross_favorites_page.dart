import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:liuguang_models/liuguang_models.dart';
import 'package:anikumo/bean/appbar/sys_app_bar.dart';
import 'package:anikumo/bean/dialog/dialog_helper.dart';
import 'package:anikumo/bean/widget/anikumo_icons.dart';
import 'package:anikumo/modules/manga/manga_item.dart';
import 'package:anikumo/pages/liuguang/film_widgets.dart';
import 'package:anikumo/services/cross_zone/favorite_tags.dart';
import 'package:anikumo/services/i18n/app_strings.dart';
import 'package:anikumo/pages/discover/work_qr_dialog.dart';
import 'package:anikumo/services/privacy/app_lock.dart';
import 'package:anikumo/services/liuguang/video_engine.dart';
import 'package:anikumo/services/manga/manga_library.dart';
import 'package:anikumo/services/novel/novel_library.dart';
import 'package:anikumo/services/storage/storage.dart';
import 'package:anikumo/utils/constants.dart';

/// Batch 275 (#43): the cross-zone favorites overview —
/// every zone's favorites on one page, grouped by zone
/// with counts, each row opening that zone's own
/// detail page. Read-only aggregation; managing
/// favorites stays in each zone.
///
/// Batch 283 (#21): the one management power this page
/// does own — user tags. A filter chip row narrows
/// every section to one tag, and each row's tag button
/// edits that item's tags (see FavoriteTags). This is
/// the only surface with tags in this batch; the
/// zones' own favorites pages are untouched.
class CrossFavoritesPage extends StatefulWidget {
  const CrossFavoritesPage({super.key});

  @override
  State<CrossFavoritesPage> createState() => _CrossFavoritesPageState();
}

class _CrossFavoritesPageState extends State<CrossFavoritesPage> {
  List<Favorite> _filmFavorites = const [];
  bool _loaded = false;
  Map<String, List<String>> _tags = FavoriteTags.load();
  String? _tagFilter;

  @override
  void initState() {
    super.initState();
    VideoEngineService.instance.engine().then((engine) async {
      final favorites = await engine.favorites.list();
      if (mounted) {
        setState(() {
          _filmFavorites = favorites;
          _loaded = true;
        });
      }
    }).catchError((_) {
      if (mounted) setState(() => _loaded = true);
    });
  }

  bool _visible(Set<String>? filterKeys, String itemKey) =>
      filterKeys == null || filterKeys.contains(itemKey);

  Future<void> _editTags(String itemKey, String title) async {
    final original = {...FavoriteTags.tagsFor(_tags, itemKey)};
    final working = {...original};
    final known = FavoriteTags.allTags(_tags).toSet();
    final controller = TextEditingController();
    final saved = await AnikumoDialog.show<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final choices = {...known, ...working}.toList()..sort();
          return AlertDialog(
            title: Text(S.f('《{}》的标签', [title])),
            content: SizedBox(
              width: 320,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (choices.isEmpty)
                    Text(
                      S.t('还没有标签，在下面新建一个'),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).colorScheme.outline,
                          ),
                    )
                  else
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 240),
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                          for (final tag in choices)
                            CheckboxListTile(
                              dense: true,
                              title: Text(tag),
                              value: working.contains(tag),
                              onChanged: (value) => setDialogState(() {
                                if (value == true) {
                                  working.add(tag);
                                } else {
                                  working.remove(tag);
                                }
                              }),
                            ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: controller,
                          decoration: InputDecoration(
                            labelText: S.t('新建标签'),
                            isDense: true,
                          ),
                          onSubmitted: (value) {
                            final tag = value.trim();
                            if (tag.isEmpty) return;
                            setDialogState(() {
                              known.add(tag);
                              working.add(tag);
                            });
                            controller.clear();
                          },
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          final tag = controller.text.trim();
                          if (tag.isEmpty) return;
                          setDialogState(() {
                            known.add(tag);
                            working.add(tag);
                          });
                          controller.clear();
                        },
                        child: Text(S.t('添加')),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(S.t('取消')),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(S.t('保存')),
              ),
            ],
          );
        },
      ),
    );
    controller.dispose();
    if (saved != true || !mounted) return;
    var next = _tags;
    for (final tag in {...original, ...working}) {
      next = FavoriteTags.withTag(next, itemKey, tag, working.contains(tag));
    }
    await FavoriteTags.save(next);
    if (mounted) setState(() => _tags = next);
  }

  Widget _tagChips(String itemKey) {
    final tags = FavoriteTags.tagsFor(_tags, itemKey);
    if (tags.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 4,
      runSpacing: 2,
      children: [
        for (final tag in tags)
          Chip(
            label: Text(tag, style: const TextStyle(fontSize: 11)),
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            padding: EdgeInsets.zero,
            labelPadding: const EdgeInsets.symmetric(horizontal: 6),
          ),
      ],
    );
  }

  Widget _trailing(String itemKey, String title, VoidCallback onQr) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: S.t('编辑标签'),
          icon: const Icon(Icons.label_outline_rounded),
          onPressed: () => _editTags(itemKey, title),
        ),
        IconButton(
          tooltip: S.t('二维码互传'),
          icon: const Icon(Icons.qr_code_rounded),
          onPressed: onQr,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final anime = GStorage.collectibles.values.toList();
    final manga = MangaLibraryStore.loadFavorites();
    final novel = NovelLibraryStore.loadFavorites();
    final theme = Theme.of(context);
    // Batch 275 (#47): guest mode hides the shelves.
    if (PrivacyGate.guestMode) {
      return Scaffold(
        appBar: SysAppBar(title: Text(S.t('全部收藏'))),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
              S.t('访客模式下收藏已隐藏'),
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ),
        ),
      );
    }
    final allTags = FavoriteTags.allTags(_tags);
    if (_tagFilter != null && !allTags.contains(_tagFilter)) {
      _tagFilter = null;
    }
    final filterKeys =
        _tagFilter == null ? null : FavoriteTags.keysWithTag(_tags, _tagFilter!);
    return Scaffold(
      appBar: SysAppBar(title: Text(S.t('全部收藏'))),
      body: ListView(
        padding: const EdgeInsets.all(StyleString.pagePadding),
        children: [
          Text(
            S.f('动漫 {} 部 · 漫画 {} 部 · 小说 {} 部 · 影视 {} 部', [
              anime.length,
              manga.length,
              novel.length,
              _filmFavorites.length,
            ]),
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
          if (allTags.isNotEmpty) ...[
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  FilterChip(
                    label: Text(S.t('全部标签')),
                    selected: _tagFilter == null,
                    onSelected: (_) => setState(() => _tagFilter = null),
                  ),
                  for (final tag in allTags) ...[
                    const SizedBox(width: 6),
                    FilterChip(
                      label: Text(tag),
                      selected: _tagFilter == tag,
                      onSelected: (selected) =>
                          setState(() => _tagFilter = selected ? tag : null),
                    ),
                  ],
                ],
              ),
            ),
          ],
          const SizedBox(height: 8),
          _section(
            context,
            icon: AnikumoIcons.smart_display_rounded,
            title: '动漫区',
            emptyText: _tagFilter != null ? '没有带此标签的收藏' : '还没有追番收藏',
            children: [
              for (final collected in anime)
                if (_visible(
                  filterKeys,
                  FavoriteTags.animeKey(collected.bangumiItem.id),
                ))
                  ListTile(
                    title: Text(
                      collected.bangumiItem.nameCn.isNotEmpty
                          ? collected.bangumiItem.nameCn
                          : collected.bangumiItem.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: _tagChips(
                      FavoriteTags.animeKey(collected.bangumiItem.id),
                    ),
                    trailing: _trailing(
                      FavoriteTags.animeKey(collected.bangumiItem.id),
                      collected.bangumiItem.nameCn.isNotEmpty
                          ? collected.bangumiItem.nameCn
                          : collected.bangumiItem.name,
                      () => showWorkQrCode(
                        context,
                        title: collected.bangumiItem.nameCn.isNotEmpty
                            ? collected.bangumiItem.nameCn
                            : collected.bangumiItem.name,
                        bangumiId: collected.bangumiItem.id,
                      ),
                    ),
                    onTap: () => context.pushNamed(
                      '/info/',
                      arguments: collected.bangumiItem,
                    ),
                  ),
            ],
          ),
          _section(
            context,
            icon: AnikumoIcons.auto_stories_rounded,
            title: '漫画区',
            emptyText: _tagFilter != null ? '没有带此标签的收藏' : '还没有漫画收藏',
            children: [
              for (final favorite in manga)
                if (_visible(
                  filterKeys,
                  FavoriteTags.mangaKey(
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
                    ).storageKey,
                  ),
                ))
                  ListTile(
                    title: Text(
                      favorite.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: _tagChips(
                      FavoriteTags.mangaKey(
                        '${favorite.source}:${favorite.id}',
                      ),
                    ),
                    trailing: _trailing(
                      FavoriteTags.mangaKey(
                        '${favorite.source}:${favorite.id}',
                      ),
                      favorite.title,
                      () => showWorkQrCode(
                        context,
                        title: favorite.title,
                      ),
                    ),
                    onTap: () => context.pushNamed(
                      '/manga/detail',
                      arguments: MangaItem(
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
                    ),
                  ),
            ],
          ),
          _section(
            context,
            icon: AnikumoIcons.menu_book_rounded,
            title: '小说区',
            emptyText: _tagFilter != null ? '没有带此标签的收藏' : '还没有小说收藏',
            children: [
              for (final item in novel)
                if (_visible(filterKeys, FavoriteTags.novelKey(item.storageKey)))
                  ListTile(
                    title: Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: _tagChips(FavoriteTags.novelKey(item.storageKey)),
                    trailing: _trailing(
                      FavoriteTags.novelKey(item.storageKey),
                      item.title,
                      () => showWorkQrCode(
                        context,
                        title: item.title,
                      ),
                    ),
                    onTap: () => context.pushNamed(
                      '/novel/detail',
                      arguments: item,
                    ),
                  ),
            ],
          ),
          _section(
            context,
            icon: AnikumoIcons.movie_rounded,
            title: '影视区',
            emptyText: !_loaded
                ? '加载中…'
                : _tagFilter != null
                    ? '没有带此标签的收藏'
                    : '还没有影视收藏',
            children: [
              for (final favorite in _filmFavorites)
                if (favorite.mediaSnapshot.isNotEmpty &&
                    _visible(filterKeys, FavoriteTags.filmKey(favorite.mediaId)))
                  ListTile(
                    title: Text(
                      TVSeries.mediaFromJson(favorite.mediaSnapshot)
                          .title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: _tagChips(FavoriteTags.filmKey(favorite.mediaId)),
                    trailing: _trailing(
                      FavoriteTags.filmKey(favorite.mediaId),
                      TVSeries.mediaFromJson(favorite.mediaSnapshot).title,
                      () => showWorkQrCode(
                        context,
                        title: TVSeries
                            .mediaFromJson(favorite.mediaSnapshot)
                            .title,
                      ),
                    ),
                    onTap: () => openFilmDetail(
                      context,
                      TVSeries.mediaFromJson(favorite.mediaSnapshot),
                    ),
                  ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _section(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String emptyText,
    required List<Widget> children,
  }) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 4),
          child: Row(
            children: [
              Icon(icon, size: 20),
              const SizedBox(width: 8),
              Text(
                S.t(title),
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 8),
              Text(
                '${children.length}',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
            ],
          ),
        ),
        if (children.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              S.t(emptyText),
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
          )
        else
          ...children,
      ],
    );
  }
}
