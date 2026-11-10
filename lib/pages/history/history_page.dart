import 'package:anikumo/utils/tap_debouncer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:anikumo/bean/appbar/sys_app_bar.dart';
import 'package:anikumo/bean/dialog/dialog_helper.dart';
import 'package:anikumo/modules/collect/collect_type.dart';
import 'package:anikumo/modules/history/history_module.dart';
import 'package:anikumo/pages/collect/collect_controller.dart';
import 'package:anikumo/pages/history/history_controller.dart';
import 'package:anikumo/pages/history/history_list_view.dart';
import 'package:anikumo/pages/history/history_other_media.dart';
import 'package:anikumo/pages/search/cross_search_widgets.dart';
import 'package:anikumo/services/manga/cross_media.dart';
import 'package:anikumo/pages/history/history_record_tile.dart';
import 'package:anikumo/navigation.dart';
import 'package:anikumo/services/manga/manga_library.dart';
import 'package:anikumo/services/novel/novel_library.dart';
import 'package:anikumo/services/player/history_playback_service.dart';
import 'package:anikumo/services/plugin/rule_engine_models.dart'
    show RuleCancelToken;
import 'package:anikumo/bean/widget/anikumo_icons.dart';
import 'package:anikumo/utils/device.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key, required this.controller});

  final HistoryController controller;

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> with RouteAware {
  // Batch 80: 全部 / 动漫 / 漫画 / 小说 medium switch.
  CrossSearchMode _mode = CrossSearchMode.anime;
  bool _editing = false;
  bool _clearing = false;
  final Set<String> _deleting = {};

  @override
  void initState() {
    super.initState();
    widget.controller.init();
    // Batch 106: the cross-media lists read the manga /
    // novel stores at build time; deletions made on OTHER
    // pages (the manga zone's history page above all)
    // bumped no signal this page could hear, so coming
    // back here kept showing the deleted records. Both
    // stores' revision ticks now rebuild the page.
    MangaLibraryStore.revision.addListener(_onStoresChanged);
    NovelLibraryStore.revision.addListener(_onStoresChanged);
  }

  @override
  void dispose() {
    rootRouteObserver.unsubscribe(this);
    MangaLibraryStore.revision.removeListener(_onStoresChanged);
    NovelLibraryStore.revision.removeListener(_onStoresChanged);
    super.dispose();
  }

  void _onStoresChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute<void>) {
      rootRouteObserver.subscribe(this, route);
    }
  }

  /// Batch 106: returning from a detail / reader / player
  /// route re-reads the anime histories (progress moved,
  /// records may have been deleted from the other side)
  /// and rebuilds the cross-media lists.
  @override
  void didPopNext() {
    widget.controller.init();
    if (mounted) setState(() {});
  }

  Future<void> _deleteHistory(History history) async {
    if (_clearing || _deleting.contains(history.key)) return;
    setState(() => _deleting.add(history.key));
    try {
      await widget.controller.deleteHistory(history);
      if (mounted && widget.controller.histories.isEmpty) {
        setState(() => _editing = false);
      }
    } catch (_) {
      if (mounted) {
        AnikumoDialog.showToast(context: context, message: '删除失败，请稍后重试');
      }
    } finally {
      if (mounted) setState(() => _deleting.remove(history.key));
    }
  }

  Future<void> _clearHistory() async {
    if (_clearing || _deleting.isNotEmpty) return;
    final confirmed = await AnikumoDialog.show<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(AnikumoIcons.delete_sweep_outlined),
        title: const Text('清空历史记录？'),
        content: Text(
            '将删除全部 ${widget.controller.histories.length} 条观看记录，包括在线和缓存记录。此操作无法撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Theme.of(context).colorScheme.onError),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('清空全部'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _clearing = true);
    try {
      await widget.controller.clearAll();
      if (mounted) setState(() => _editing = false);
    } catch (_) {
      if (mounted) {
        AnikumoDialog.showToast(context: context, message: '清空失败，请稍后重试');
      }
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Observer(builder: (context) {
      final entries = widget.controller.histories.toList();
      return PopScope(
        canPop: !_editing,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop && _editing) {
            setState(() => _editing = false);
          }
        },
        child: Scaffold(
          appBar: SysAppBar(
            title: Text('历史记录',
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w700)),
            actions: [
              // Batch 80: edit / clear manage the ANIME
              // history; the other modes are views onto
              // their own zones' progress stores.
              if (_mode == CrossSearchMode.anime && entries.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _editing
                      ? FilledButton.tonal(
                          onPressed: _clearing
                              ? null
                              : () => setState(() => _editing = false),
                          child: const Text('完成'),
                        )
                      : IconButton.filledTonal(
                          tooltip: '管理历史记录',
                          onPressed: () => setState(() => _editing = true),
                          icon: const Icon(AnikumoIcons.edit_outlined),
                        ),
                ),
                if (_editing)
                  IconButton(
                    tooltip: '清空全部历史记录',
                    onPressed: _clearing || _deleting.isNotEmpty
                        ? null
                        : _clearHistory,
                    icon: const Icon(AnikumoIcons.delete_sweep_outlined),
                  ),
              ],
            ],
          ),
          body: SafeArea(
            top: false,
            bottom: false,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: CrossSearchModeSwitch(
                      mode: _mode,
                      onChanged: (mode) => setState(() {
                        _mode = mode;
                        if (mode != CrossSearchMode.anime) {
                          _editing = false;
                        }
                      }),
                    ),
                  ),
                ),
                Expanded(
                  child: switch (_mode) {
                    CrossSearchMode.anime => HistoryListView(
                        entries: entries,
                        editing: _editing,
                        itemBuilder: (history, borderRadius) =>
                            _HistoryCard(
                          history: history,
                          borderRadius: borderRadius,
                          editing: _editing,
                          busy:
                              _clearing || _deleting.contains(history.key),
                          onDelete: () => _deleteHistory(history),
                        ),
                      ),
                    CrossSearchMode.manga => const MangaHistoryList(),
                    CrossSearchMode.novel => const NovelHistoryList(),
                    CrossSearchMode.all =>
                      AllHistoryList(animeHistories: entries),
                  },
                ),
              ],
            ),
          ),
        ),
      );
    });
  }
}

class _HistoryCard extends StatefulWidget {
  const _HistoryCard({
    required this.history,
    required this.onDelete,
    required this.editing,
    required this.busy,
    required this.borderRadius,
  });

  final History history;
  final bool editing;
  final bool busy;
  final Future<void> Function() onDelete;
  final BorderRadius borderRadius;

  @override
  State<_HistoryCard> createState() => _HistoryCardState();
}

class _HistoryCardState extends State<_HistoryCard> with AnikumoDialogOwner {
  final CollectController _collectController = inject<CollectController>();
  final HistoryPlaybackService _playbackService =
      inject<HistoryPlaybackService>();
  bool _updatingCollect = false;

  Future<void> _play() async {
    if (widget.editing || widget.busy || dialogs.isRunning) return;
    await dialogs.run((task) async {
      final cancelToken = RuleCancelToken();
      final result = await task.loading(
        message: '获取中',
        barrierDismissible: isDesktop(),
        onCancel: cancelToken.cancel,
        action: () =>
            _playbackService.open(widget.history, cancelToken: cancelToken),
      );
      switch (result) {
        case HistoryPlaybackReady(:final args):
          task.withContext(
              (context) => context.pushNamed('/video/', arguments: args));
        case HistoryPlaybackUnavailable(:final reason):
          AnikumoDialog.showToast(message: reason);
      }
    }, errorMessage: '暂时无法继续播放，请稍后重试');
  }

  Future<void> _changeCollect(CollectType type) async {
    if (_updatingCollect) return;
    setState(() => _updatingCollect = true);
    try {
      await _collectController.addCollect(widget.history.bangumiItem,
          type: type.value);
    } catch (_) {
      AnikumoDialog.showToast(message: '修改收藏状态失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _updatingCollect = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Observer(builder: (context) {
      // getCollectType reads storage, so track the observable list explicitly.
      _collectController.collectibles.length;
      return HistoryRecordTile(
        history: widget.history,
        borderRadius: widget.borderRadius,
        editing: widget.editing,
        busy: widget.busy,
        onPlay: _play,
        onDelete: widget.onDelete,
        onDetails: () {
          if (TapDebouncer.accept(
              'info:${widget.history.bangumiItem.id}')) {
            context.pushNamed('/info/',
                arguments: widget.history.bangumiItem);
          }
        },
        collectType: CollectType.fromValue(
            _collectController.getCollectType(widget.history.bangumiItem)),
        onChangeCollect: _updatingCollect ? null : _changeCollect,
      );
    });
  }
}
