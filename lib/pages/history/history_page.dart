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
import 'package:anikumo/services/collect/batch_selection.dart';
import 'package:anikumo/services/storage/storage.dart';
import 'package:anikumo/bean/widget/search_stage.dart';
import 'package:anikumo/pages/history/history_list_view.dart';
import 'package:anikumo/pages/history/history_other_media.dart';
import 'package:anikumo/pages/liuguang/film_history_page.dart';
import 'package:anikumo/pages/history/history_record_tile.dart';
import 'package:anikumo/navigation.dart';
import 'package:anikumo/services/manga/manga_library.dart';
import 'package:anikumo/services/novel/novel_library.dart';
import 'package:anikumo/services/player/history_playback_service.dart';
import 'package:anikumo/services/plugin/rule_engine_models.dart'
    show RuleCancelToken;
import 'package:anikumo/bean/widget/anikumo_icons.dart';
import 'package:anikumo/utils/device.dart';
import 'package:anikumo/services/i18n/app_strings.dart';
import 'package:anikumo/services/privacy/app_lock.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key, required this.controller});

  final HistoryController controller;

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

/// Batch 224: the history page's own view switch. It used
/// to ride the cross-search mode enum; the film view the
/// user asked for （历史记录加上电视剧） is a history-only
/// surface, so the page keeps a local enum instead of
/// growing a dead mode in the search switch.
enum _HistoryView { all, anime, manga, novel, film }

class _HistoryPageState extends State<HistoryPage> with RouteAware {
  // Batch 80: 全部 / 动漫 / 漫画 / 小说 medium switch.
  // Batch 224: a 影视 view joins it.
  _HistoryView _view = _HistoryView.anime;
  bool _editing = false;
  bool _clearing = false;
  final Set<String> _deleting = {};

  // Batch 283 (#22): in editing mode the anime rows
  // are multi-selectable (tap toggles); the bottom bar
  // runs the batch delete / mark-watched actions.
  Set<String> _selectedKeys = {};
  bool _batchBusy = false;
  final CollectController _collectController = inject<CollectController>();

  void _setEditing(bool editing) {
    setState(() {
      _editing = editing;
      if (!editing) _selectedKeys = {};
    });
  }

  List<History> _selectedHistories(List<History> entries) => [
        for (final history in entries)
          if (_selectedKeys.contains(history.key)) history,
      ];

  Future<void> _batchDelete(List<History> entries) async {
    final selected = _selectedHistories(entries);
    if (selected.isEmpty || _batchBusy) return;
    final confirmed = await AnikumoDialog.show<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(S.t('删除所选记录？')),
        content: Text(S.f('将删除 {} 条观看记录。此操作无法撤销。', [selected.length])),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(S.t('取消')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(S.t('删除')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _batchBusy = true);
    var deleted = 0;
    try {
      for (final history in selected) {
        await widget.controller.deleteHistory(history);
        deleted++;
      }
    } catch (_) {
      if (mounted) {
        AnikumoDialog.showToast(
          context: context,
          message: S.t('批量删除失败，请稍后重试'),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _batchBusy = false;
          _selectedKeys = {};
        });
        if (deleted > 0) {
          AnikumoDialog.showToast(
            context: context,
            message: S.f('已删除 {} 条记录', [deleted]),
          );
        }
        if (widget.controller.histories.isEmpty) _setEditing(false);
      }
    }
  }

  Future<void> _batchMarkWatched(List<History> entries) async {
    final selected = _selectedHistories(entries);
    if (selected.isEmpty || _batchBusy) return;
    final collectedIds = {
      for (final c in GStorage.collectibles.values) c.bangumiItem.id,
    };
    final plan = planMarkWatched(
      selected.map((h) => h.bangumiItem.id),
      collectedIds,
    );
    setState(() => _batchBusy = true);
    try {
      final items = [
        for (final history in selected)
          if (plan.toMark.contains(history.bangumiItem.id))
            history.bangumiItem,
      ];
      final changed = await _collectController.applyBatchType(
        items,
        CollectType.watched.value,
      );
      if (!mounted) return;
      final parts = <String>[
        if (changed > 0) S.f('已标记 {} 部为看过', [changed]),
        if (plan.skipped > 0) S.f('{} 部未收藏已跳过', [plan.skipped]),
      ];
      AnikumoDialog.showToast(
        context: context,
        message: parts.isEmpty ? S.t('所选条目状态没有变化') : parts.join('，'),
      );
      setState(() => _selectedKeys = {});
    } catch (_) {
      if (mounted) {
        AnikumoDialog.showToast(
          context: context,
          message: S.t('批量标记失败，请稍后重试'),
        );
      }
    } finally {
      if (mounted) setState(() => _batchBusy = false);
    }
  }

  Widget _batchBar(BuildContext context, List<History> entries) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainer,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          child: Row(
            children: [
              Text(
                S.f('已选 {} 项', [_selectedKeys.length]),
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              TextButton(
                onPressed: _batchBusy
                    ? null
                    : () => setState(() {
                          _selectedKeys = BatchSelection.selectAll(
                            entries.map((h) => h.key),
                          );
                        }),
                child: Text(S.t('全选')),
              ),
              TextButton(
                onPressed: _batchBusy || _selectedKeys.isEmpty
                    ? null
                    : () => _batchMarkWatched(entries),
                child: Text(S.t('标记已看完')),
              ),
              TextButton(
                onPressed: _batchBusy || _selectedKeys.isEmpty
                    ? null
                    : () => _batchDelete(entries),
                child: Text(
                  S.t('批量删除'),
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

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
        _setEditing(false);
      }
    } catch (_) {
      if (mounted) {
        AnikumoDialog.showToast(context: context, message: S.t('删除失败，请稍后重试'));
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
        title: Text(S.t('清空历史记录？')),
        content: Text(
          S.f('将删除全部 {} 条观看记录，包括在线和缓存记录。此操作无法撤销。', [widget.controller.histories.length]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(S.t('取消')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(S.t('清空全部')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _clearing = true);
    try {
      await widget.controller.clearAll();
      if (mounted) _setEditing(false);
    } catch (_) {
      if (mounted) {
        AnikumoDialog.showToast(context: context, message: S.t('清空失败，请稍后重试'));
      }
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Observer(
      builder: (context) {
        final entries = widget.controller.histories.toList();
        // Batch 275 (#47): guest mode hides all history
        // views (the page covers every zone's progress).
        if (PrivacyGate.guestMode) {
          return Scaffold(
            appBar: SysAppBar(
              title: Text(
                S.t('历史记录'),
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
            body: Center(
              child: Text(
                S.t('访客模式下历史记录已隐藏'),
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
              ),
            ),
          );
        }
        return PopScope(
          canPop: !_editing,
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop && _editing) {
              _setEditing(false);
            }
          },
          child: Scaffold(
            bottomNavigationBar: _editing && _view == _HistoryView.anime
                ? _batchBar(context, entries)
                : null,
            appBar: SysAppBar(
              title: Text(
                S.t('历史记录'),
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              actions: [
                // Batch 80: edit / clear manage the ANIME
                // history; the other modes are views onto
                // their own zones' progress stores.
                if (_view == _HistoryView.anime && entries.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _editing
                        ? FilledButton.tonal(
                            onPressed: _clearing
                                ? null
                                : () => _setEditing(false),
                            child: Text(S.t('完成')),
                          )
                        : IconButton.filledTonal(
                            tooltip: S.t('管理历史记录'),
                            onPressed: () => _setEditing(true),
                            icon: const Icon(AnikumoIcons.edit_outlined),
                          ),
                  ),
                  if (_editing)
                    IconButton(
                      tooltip: S.t('清空全部历史记录'),
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
                      child: PillSwitch<_HistoryView>(
                        value: _view,
                        onChanged: (view) => setState(() {
                          _view = view;
                          if (view != _HistoryView.anime) {
                            _editing = false;
                            _selectedKeys = {};
                          }
                        }),
                        options: [
                          PillSwitchOption(
                            value: _HistoryView.all,
                            label: S.t('全部'),
                            icon: AnikumoIcons.dashboard_rounded,
                          ),
                          PillSwitchOption(
                            value: _HistoryView.anime,
                            label: S.t('动漫'),
                            icon: AnikumoIcons.smart_display_rounded,
                          ),
                          PillSwitchOption(
                            value: _HistoryView.manga,
                            label: S.t('漫画'),
                            icon: AnikumoIcons.menu_book_rounded,
                          ),
                          PillSwitchOption(
                            value: _HistoryView.novel,
                            label: S.t('小说'),
                            icon: AnikumoIcons.import_contacts_rounded,
                          ),
                          PillSwitchOption(
                            value: _HistoryView.film,
                            label: S.t('影视'),
                            icon: AnikumoIcons.live_tv_rounded,
                          ),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    child: switch (_view) {
                      _HistoryView.anime => HistoryListView(
                        entries: entries,
                        editing: _editing,
                        itemBuilder: (history, borderRadius) => _HistoryCard(
                          history: history,
                          borderRadius: borderRadius,
                          editing: _editing,
                          busy: _clearing || _deleting.contains(history.key),
                          onDelete: () => _deleteHistory(history),
                          selected: _editing
                              ? _selectedKeys.contains(history.key)
                              : null,
                          onToggleSelect: () => setState(() {
                            _selectedKeys = BatchSelection.toggle(
                              _selectedKeys,
                              history.key,
                            );
                          }),
                        ),
                      ),
                      _HistoryView.manga => const MangaHistoryList(),
                      _HistoryView.novel => const NovelHistoryList(),
                      _HistoryView.all => AllHistoryList(
                        animeHistories: entries,
                      ),
                      _HistoryView.film => const FilmHistoryList(),
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _HistoryCard extends StatefulWidget {
  const _HistoryCard({
    required this.history,
    required this.onDelete,
    required this.editing,
    required this.busy,
    required this.borderRadius,
    this.selected,
    this.onToggleSelect,
  });

  final History history;
  final bool editing;
  final bool busy;
  final Future<void> Function() onDelete;
  final BorderRadius borderRadius;

  /// Batch 283 (#22): batch selection state from the
  /// page (null outside editing mode).
  final bool? selected;
  final VoidCallback? onToggleSelect;

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
        message: S.t('获取中'),
        barrierDismissible: isDesktop(),
        onCancel: cancelToken.cancel,
        action: () =>
            _playbackService.open(widget.history, cancelToken: cancelToken),
      );
      switch (result) {
        case HistoryPlaybackReady(:final args):
          task.withContext(
            (context) => context.pushNamed('/video/', arguments: args),
          );
        case HistoryPlaybackUnavailable(:final reason):
          AnikumoDialog.showToast(message: reason);
      }
    }, errorMessage: S.t('暂时无法继续播放，请稍后重试'));
  }

  Future<void> _changeCollect(CollectType type) async {
    if (_updatingCollect) return;
    setState(() => _updatingCollect = true);
    try {
      await _collectController.addCollect(
        widget.history.bangumiItem,
        type: type.value,
      );
    } catch (_) {
      AnikumoDialog.showToast(message: S.t('修改收藏状态失败，请稍后重试'));
    } finally {
      if (mounted) setState(() => _updatingCollect = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Observer(
      builder: (context) {
        // getCollectType reads storage, so track the observable list explicitly.
        _collectController.collectibles.length;
        return HistoryRecordTile(
          history: widget.history,
          borderRadius: widget.borderRadius,
          editing: widget.editing,
          busy: widget.busy,
          selected: widget.selected,
          onToggleSelect: widget.onToggleSelect,
          onPlay: _play,
          onDelete: widget.onDelete,
          onDetails: () {
            if (TapDebouncer.accept('info:${widget.history.bangumiItem.id}')) {
              context.pushNamed(
                '/info/',
                arguments: widget.history.bangumiItem,
              );
            }
          },
          collectType: CollectType.fromValue(
            _collectController.getCollectType(widget.history.bangumiItem),
          ),
          onChangeCollect: _updatingCollect ? null : _changeCollect,
        );
      },
    );
  }
}
