import 'package:anikumo/utils/tap_debouncer.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_modular/flutter_modular.dart';

import 'package:anikumo/bean/dialog/dialog_helper.dart';
import 'package:anikumo/bean/widget/state_presentation.dart';
import 'package:anikumo/modules/bangumi/bangumi_item.dart';
import 'package:anikumo/modules/bangumi/sync_priority.dart';
import 'package:anikumo/modules/collect/collect_layout.dart';
import 'package:anikumo/modules/collect/collect_sync_plan.dart';
import 'package:anikumo/modules/collect/collect_type.dart';
import 'package:anikumo/pages/collect/collect_controller.dart';
import 'package:anikumo/pages/collect/collect_library_view.dart';
import 'package:anikumo/pages/collect/collect_sync_dialog.dart';
import 'package:anikumo/services/anime/anime_auto_update.dart';
import 'package:anikumo/services/anime/anime_features.dart';
import 'package:anikumo/services/collect/batch_selection.dart';
import 'package:anikumo/services/storage/storage.dart';
import 'package:anikumo/bean/widget/anikumo_icons.dart';
import 'package:anikumo/services/i18n/app_strings.dart';

class CollectPage extends StatefulWidget {
  const CollectPage({
    super.key,
    required this.controller,
  });

  final CollectController controller;

  @override
  State<CollectPage> createState() => _CollectPageState();
}

class _CollectPageState extends State<CollectPage> with AnikumoDialogOwner {
  CollectController get collectController => widget.controller;
  bool get _syncDialogOpen => dialogs.isRunning;
  final Set<int> _pendingIds = {};
  late CollectLayout _layout;

  // Batch 283 (#22): multi-select mode (long press to
  // enter). Selection is by bangumi id and survives
  // category switches inside the library view.
  bool _selectionMode = false;
  Set<int> _selectedIds = {};
  bool _batchBusy = false;

  void _enterSelection(BangumiItem item) {
    if (_syncDialogOpen) return;
    setState(() {
      _selectionMode = true;
      _selectedIds = {item.id};
    });
  }

  void _toggleSelect(BangumiItem item) {
    setState(() {
      _selectedIds = BatchSelection.toggle(_selectedIds, item.id);
    });
  }

  void _exitSelection() {
    setState(() {
      _selectionMode = false;
      _selectedIds = {};
    });
  }

  List<BangumiItem> get _selectedItems => [
        for (final entry in collectController.collectibles)
          if (_selectedIds.contains(entry.bangumiItem.id)) entry.bangumiItem,
      ];

  Future<void> _batchSetType(CollectType type) async {
    final items = _selectedItems;
    if (items.isEmpty || _batchBusy) return;
    setState(() => _batchBusy = true);
    try {
      final changed =
          await collectController.applyBatchType(items, type.value);
      if (!mounted) return;
      AnikumoDialog.showToast(
        context: context,
        message: changed > 0
            ? S.f('已将 {} 部改为「{}」', [changed, S.t(type.label)])
            : S.t('所选条目状态没有变化'),
      );
      _exitSelection();
    } catch (_) {
      if (mounted) {
        AnikumoDialog.showToast(
          context: context,
          message: S.t('批量修改失败，请稍后重试'),
        );
      }
    } finally {
      if (mounted) setState(() => _batchBusy = false);
    }
  }

  Future<void> _batchRemove() async {
    final items = _selectedItems;
    if (items.isEmpty || _batchBusy) return;
    final confirmed = await AnikumoDialog.show<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(S.t('移除所选收藏？')),
        content: Text(S.f('将从收藏中移除 {} 部番剧。此操作无法撤销。', [items.length])),
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
            child: Text(S.t('移除')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _batchBusy = true);
    try {
      final removed = await collectController.applyBatchRemove(items);
      if (!mounted) return;
      AnikumoDialog.showToast(
        context: context,
        message: S.f('已移除 {} 部收藏', [removed]),
      );
      _exitSelection();
    } catch (_) {
      if (mounted) {
        AnikumoDialog.showToast(
          context: context,
          message: S.t('批量移除失败，请稍后重试'),
        );
      }
    } finally {
      if (mounted) setState(() => _batchBusy = false);
    }
  }

  Widget _batchBar(BuildContext context) {
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
                S.f('已选 {} 项', [_selectedIds.length]),
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              TextButton(
                onPressed: _batchBusy
                    ? null
                    : () => setState(() {
                          _selectedIds = BatchSelection.selectAll(
                            collectController.collectibles
                                .map((e) => e.bangumiItem.id),
                          );
                        }),
                child: Text(S.t('全选')),
              ),
              MenuAnchor(
                builder: (context, controller, _) => TextButton(
                  onPressed: _batchBusy || _selectedIds.isEmpty
                      ? null
                      : () =>
                          controller.isOpen ? controller.close() : controller.open(),
                  child: Text(S.t('改状态')),
                ),
                menuChildren: [
                  for (final type
                      in CollectType.values.where((t) => t.isCollected))
                    MenuItemButton(
                      onPressed: () => _batchSetType(type),
                      child: Text(S.t(type.label)),
                    ),
                ],
              ),
              TextButton(
                onPressed:
                    _batchBusy || _selectedIds.isEmpty ? null : _batchRemove,
                child: Text(
                  S.t('移除'),
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
              IconButton(
                tooltip: S.t('退出多选'),
                onPressed: _batchBusy ? null : _exitSelection,
                icon: const Icon(AnikumoIcons.close_rounded),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<bool> _syncStep(
    CollectSyncStep step, {
    required ValueChanged<String> onError,
    required void Function(String message, int current, int total) onProgress,
  }) =>
      switch (step) {
        CollectSyncStep.webDav => collectController.syncCollectibles(
            onError: onError,
          ),
        CollectSyncStep.bangumi => collectController.syncCollectiblesBangumi(
            onError: onError,
            onProgress: onProgress,
          ),
        CollectSyncStep.upload => collectController.uploadCollectiblesToWebDav(
            onError: onError,
          ),
      };

  @override
  void initState() {
    super.initState();
    // Read once; page switches never change the saved default.
    _layout = CollectLayout.fromValue(
      GStorage.getSetting(SettingsKeys.defaultCollectLayout),
    );
    collectController.loadCollectibles();
  }

  void _changeLayout(CollectLayout layout) {
    if (_layout == layout) return;
    setState(() => _layout = layout);
  }

  Future<void> _changeType(BangumiItem item, CollectType type) async {
    if (_syncDialogOpen || _pendingIds.contains(item.id)) return;
    setState(() => _pendingIds.add(item.id));
    try {
      await collectController.addCollect(item, type: type.value);
    } catch (_) {
      AnikumoDialog.showToast(message: S.t('修改收藏状态失败，请稍后重试'));
    } finally {
      if (mounted) setState(() => _pendingIds.remove(item.id));
    }
  }

  Future<void> _sync() async {
    if (_syncDialogOpen || _pendingIds.isNotEmpty) return;
    final plan = CollectSyncPlan(
      webDavEnabled: GStorage.getSetting(SettingsKeys.webDavEnable),
      webDavCollectiblesEnabled:
          GStorage.getSetting(SettingsKeys.webDavEnableCollect),
      bangumiEnabled: GStorage.getSetting(SettingsKeys.bangumiSyncEnable),
    );
    await dialogs.run((task) async {
      final destination = await task.show<CollectSyncDestination>(
        builder: (_) => CollectSyncDialog(
          plan: plan,
          priority: BangumiSyncPriority.fromValue(
            GStorage.getSetting(SettingsKeys.bangumiSyncPriority),
          ),
          onSync: _syncStep,
        ),
      );
      task.withContext((context) => context.pushNamed(switch (destination) {
            CollectSyncDestination.webDavSettings => '/settings/webdav/',
            CollectSyncDestination.bangumiSettings => '/settings/bangumi/',
          }));
    }, errorMessage: S.t('同步未完成，请稍后重试'));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      bottomNavigationBar: _selectionMode ? _batchBar(context) : null,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Batch 233 （追番自动更新 pack): pending update
            // notices sit above the page head.
            ValueListenableBuilder<int>(
              valueListenable: AnimeFeatures.revision,
              builder: (context, _, __) {
                final pending = AnimeAutoUpdate.pendingUpdates();
                if (pending.isEmpty) return const SizedBox.shrink();
                return MaterialBanner(
                  content: Text(pending.join('；')),
                  leading: const Icon(Icons.fiber_new_rounded),
                  actions: [
                    TextButton(
                      onPressed: () async {
                        await AnimeAutoUpdate.clearPending();
                        AnimeFeatures.revision.value++;
                      },
                      child: Text(S.t('知道了')),
                    ),
                  ],
                );
              },
            ),
            // Batch 44: editorial page head — same sync
            // action, same enable rules, no app bar.
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    S.t('COLLECTION · 我的追番'),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.outline,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2.4,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        S.t('追番'),
                        style: theme.textTheme.headlineMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const Spacer(),
                      Tooltip(
                        message: S.t('同步收藏'),
                        child: StateActionButton.tonal(
                          text: S.t('同步'),
                          onPressed: _selectionMode ||
                                  _syncDialogOpen ||
                                  _pendingIds.isNotEmpty
                              ? null
                              : _sync,
                          icon: AnikumoIcons.sync_rounded,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: Observer(
                builder: (context) => CollectLibraryView(
                  entries: collectController.collectibles.toList(),
                  showRating:
                      GStorage.getSetting(SettingsKeys.showRating),
                  layout: _layout,
                  onLayoutChanged: _changeLayout,
                  selectionMode: _selectionMode,
                  selectedIds: _selectedIds,
                  onToggleSelect: _toggleSelect,
                  onLongPressItem: _enterSelection,
                  canEdit: (item) =>
                      !_selectionMode &&
                      !_syncDialogOpen &&
                      !_pendingIds.contains(item.id),
                  onOpen: (item) {
                    if (TapDebouncer.accept('info:${item.id}')) {
                      context.pushNamed('/info/', arguments: item);
                    }
                  },
                  onChangeType: (item, type) =>
                      unawaited(_changeType(item, type)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
