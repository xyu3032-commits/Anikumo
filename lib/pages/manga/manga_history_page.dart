import 'package:anikumo/utils/tap_debouncer.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_modular/flutter_modular.dart';
import 'package:anikumo/modules/manga/manga_item.dart';
import 'package:anikumo/pages/manga/manga_widgets.dart';
import 'package:anikumo/services/manga/manga_library.dart';
import 'package:anikumo/utils/constants.dart';

/// Full reading-history list — where the home tab's 历史 card
/// leads. Most recently read first.
class MangaHistoryPage extends StatefulWidget {
  const MangaHistoryPage({super.key});

  @override
  State<MangaHistoryPage> createState() => _MangaHistoryPageState();
}

class _MangaHistoryPageState extends State<MangaHistoryPage> {
  @override
  Widget build(BuildContext context) {
    final progress = MangaLibraryStore.loadProgressList();
    return Scaffold(
      appBar: AppBar(title: Text('阅读历史（${progress.length}）')),
      body: progress.isEmpty
          ? const Center(child: Text('还没有阅读记录'))
          : ListView.builder(
        scrollCacheExtent: const ScrollCacheExtent.pixels(700),
              padding: const EdgeInsets.symmetric(
                horizontal: StyleString.pagePadding,
                vertical: 8,
              ),
              itemCount: progress.length,
              itemBuilder: (context, index) {
                final entry = progress[index];
                final item = MangaItem(
                  id: entry.mangaId,
                  title: entry.mangaTitle,
                  description: '',
                  coverUrl: entry.coverUrl,
                  author: '',
                  status: '',
                  year: null,
                  tags: const [],
                  source: entry.mangaSource,
                );
                return InkWell(
                  onTap: () {
                    if (TapDebouncer.accept(
                        'manga:${item.source}:${item.id}')) {
                      context
                          .pushNamed('/manga/detail', arguments: item)
                          .then((_) => mounted ? setState(() {}) : null);
                    }
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    child: Row(
                      children: [
                        MangaCover(
                          url: entry.coverUrl,
                          width: 44,
                          height: 62,
                          radius: 6,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                entry.mangaTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '读到 ${entry.chapterLabel} · 第 ${entry.page + 1} / ${entry.totalPages} 页',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color:
                                          Theme.of(context).colorScheme.primary,
                                    ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right_rounded),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
