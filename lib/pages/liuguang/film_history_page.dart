import 'package:flutter/material.dart';
import 'package:liuguang_core/liuguang_core.dart';

import 'package:anikumo/bean/widget/anikumo_icons.dart';
import 'package:anikumo/pages/liuguang/film_widgets.dart';
import 'package:anikumo/services/liuguang/video_engine.dart';

/// Batch 224: the film zone's watch history — the user
/// asked for it twice over: a 历史记录 entry at the top
/// right of the 电视剧 home, and the dramas they watch to
/// show up in the anime zone's 历史记录 page too. Both
/// surfaces host [FilmHistoryList]; this page is the film
/// zone's own full-screen home for it.
///
/// Engine history is one record per episode; the list
/// shows one row per title — its most recent episode —
/// which is the shape "continue watching" takes anywhere
/// else in the app.

/// One row per title: the latest record of each media id,
/// newest first.
List<PlaybackHistory> groupFilmHistory(List<PlaybackHistory> rows) {
  final latest = <String, PlaybackHistory>{};
  for (final row in rows) {
    final current = latest[row.mediaId];
    if (current == null || row.lastPlayedAt.isAfter(current.lastPlayedAt)) {
      latest[row.mediaId] = row;
    }
  }
  return latest.values.toList()
    ..sort((a, b) => b.lastPlayedAt.compareTo(a.lastPlayedAt));
}

/// '第 N 集' from a CMS episode id ('<mediaId>::<line>::<ep>',
/// zero-based tail), or '' when the id carries no episode.
String filmHistoryEpisodeLabel(String? episodeId) {
  if (episodeId == null || episodeId.isEmpty) return '';
  final tail = int.tryParse(episodeId.split('::').last);
  if (tail == null) return '';
  return '第 ${tail + 1} 集';
}

String _clock(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}

String _when(DateTime at, DateTime now) {
  final diff = now.difference(at);
  if (diff.inMinutes < 1) return '刚刚';
  if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
  if (diff.inHours < 24) return '${diff.inHours} 小时前';
  if (diff.inDays < 30) return '${diff.inDays} 天前';
  return '${at.month}月${at.day}日';
}

class FilmHistoryList extends StatefulWidget {
  const FilmHistoryList({super.key});

  @override
  State<FilmHistoryList> createState() => FilmHistoryListState();
}

class FilmHistoryListState extends State<FilmHistoryList> {
  List<PlaybackHistory> _allRows = [];
  List<PlaybackHistory> _titles = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> reload() => _load();

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final engine = await VideoEngineService.instance.engine();
      final rows = await engine.history.list(limit: 300);
      if (!mounted) return;
      setState(() {
        _allRows = rows;
        _titles = groupFilmHistory(rows);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '历史记录读取失败：$e';
        _loading = false;
      });
    }
  }

  Future<void> _deleteTitle(PlaybackHistory row) async {
    final engine = await VideoEngineService.instance.engine();
    for (final r in _allRows.where((r) => r.mediaId == row.mediaId)) {
      await engine.history.remove(r.mediaId, episodeId: r.episodeId);
    }
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return FilmEmptyState(
        icon: AnikumoIcons.history_rounded,
        title: '历史记录',
        message: _error!,
        actionLabel: '重试',
        onAction: _load,
      );
    }
    if (_titles.isEmpty) {
      return const FilmEmptyState(
        icon: AnikumoIcons.history_rounded,
        title: '还没有观看记录',
        message: '在影视区看过的电视剧、电影和综艺会出现在这里，点开就能接着看。',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
      itemCount: _titles.length,
      itemBuilder: (context, i) => _FilmHistoryTile(
        row: _titles[i],
        onDelete: () => _deleteTitle(_titles[i]),
      ),
    );
  }
}

class _FilmHistoryTile extends StatefulWidget {
  const _FilmHistoryTile({required this.row, required this.onDelete});

  final PlaybackHistory row;
  final VoidCallback onDelete;

  @override
  State<_FilmHistoryTile> createState() => _FilmHistoryTileState();
}

class _FilmHistoryTileState extends State<_FilmHistoryTile> {
  Future<MediaDetail?>? _detail;

  @override
  void initState() {
    super.initState();
    _detail = VideoEngineService.instance
        .engine()
        .then((engine) => engine.getDetail(widget.row.mediaId))
        .catchError((_) => null);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final row = widget.row;
    final label = filmHistoryEpisodeLabel(row.episodeId);
    final progress = row.duration.inMilliseconds > 0
        ? (row.position.inMilliseconds / row.duration.inMilliseconds).clamp(
            0.0,
            1.0,
          )
        : 0.0;
    final meta = [
      if (label.isNotEmpty) label,
      if (row.completed)
        '已看完'
      else if (row.duration > Duration.zero)
        '看到 ${_clock(row.position)} / ${_clock(row.duration)}',
      _when(row.lastPlayedAt, DateTime.now()),
    ].join(' · ');
    return FutureBuilder<MediaDetail?>(
      future: _detail,
      builder: (context, snapshot) {
        final item = snapshot.data?.item;
        return InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            if (item != null) {
              openFilmDetail(context, item);
            } else {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('暂时取不到这部内容，请稍后重试')));
            }
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 56,
                    height: 74,
                    child: item == null
                        ? Container(
                            color: theme.colorScheme.surfaceContainerHighest,
                            alignment: Alignment.center,
                            child: Icon(
                              AnikumoIcons.movie_rounded,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          )
                        : FilmCoverImage(
                            item: item,
                            decodeWidth: 168,
                            placeholder: Container(
                              color: theme.colorScheme.surfaceContainerHighest,
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        row.title.isNotEmpty
                            ? row.title
                            : (item?.title ?? '未知标题'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 3,
                          backgroundColor:
                              theme.colorScheme.surfaceContainerHighest,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: '删除这条记录',
                  icon: const Icon(AnikumoIcons.delete_outline_rounded),
                  onPressed: widget.onDelete,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The film zone's own history page (route '/film/history').
class FilmHistoryPage extends StatefulWidget {
  const FilmHistoryPage({super.key});

  @override
  State<FilmHistoryPage> createState() => _FilmHistoryPageState();
}

class _FilmHistoryPageState extends State<FilmHistoryPage> {
  final _listKey = GlobalKey<FilmHistoryListState>();

  Future<void> _clearAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('清空影视历史记录？'),
        content: const Text('将删除影视区全部观看记录，此操作无法撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('清空全部'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final engine = await VideoEngineService.instance.engine();
    await engine.history.clear();
    await _listKey.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('历史记录'),
        actions: [
          IconButton(
            tooltip: '清空全部历史记录',
            icon: const Icon(AnikumoIcons.delete_sweep_outlined),
            onPressed: _clearAll,
          ),
        ],
      ),
      body: SafeArea(child: FilmHistoryList(key: _listKey)),
    );
  }
}
