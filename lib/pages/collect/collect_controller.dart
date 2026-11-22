import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:anikumo/bean/dialog/dialog_helper.dart';
import 'package:anikumo/modules/bangumi/bangumi_item.dart';
import 'package:anikumo/modules/collect/collect_module.dart';
import 'package:anikumo/modules/collect/collect_type.dart';
import 'package:anikumo/services/sync/bangumi_sync_service.dart';
import 'package:anikumo/services/storage/storage.dart';
import 'package:anikumo/services/sync/webdav.dart';
import 'package:anikumo/repositories/collect_crud_repository.dart';
import 'package:mobx/mobx.dart';
import 'package:anikumo/services/logging/logger.dart';
import 'package:anikumo/services/i18n/app_strings.dart';

part 'collect_controller.g.dart';

enum _BangumiDeleteSyncAction {
  deleteLocalOnly,
  markAbandoned,
  openWeb,
  cancel,
}

class CollectController = _CollectController with _$CollectController;

abstract class _CollectController with Store {
  _CollectController(this._collectCrudRepository);

  final ICollectCrudRepository _collectCrudRepository;

  @observable
  ObservableList<CollectedBangumi> collectibles =
      ObservableList<CollectedBangumi>();

  void loadCollectibles() {
    collectibles.clear();
    collectibles.addAll(_collectCrudRepository.getAllCollectibles());
  }

  int getCollectType(BangumiItem bangumiItem) {
    return _collectCrudRepository.getCollectType(bangumiItem.id);
  }

  @action
  Future<void> addCollect(BangumiItem bangumiItem, {type = 1}) async {
    if (type == 0) {
      await deleteCollect(bangumiItem);
      return;
    }

    final bool syncSucceeded = await _syncBangumiCollectIfEnabled(
      bangumiItem.id,
      type,
    );
    if (!syncSucceeded) {
      return;
    }

    final int currentCollectType = getCollectType(bangumiItem);
    final int collectChangeAction = currentCollectType == 0 ? 1 : 2;

    await _collectCrudRepository.addCollectible(bangumiItem, type);
    await GStorage.appendCollectChange(
      bangumiId: bangumiItem.id,
      action: collectChangeAction,
      type: type,
    );
    loadCollectibles();
  }

  @action
  Future<void> deleteCollect(BangumiItem bangumiItem) async {
    final action = await _resolveBangumiDeleteSyncAction(bangumiItem);
    switch (action) {
      case _BangumiDeleteSyncAction.markAbandoned:
        await addCollect(
          bangumiItem,
          type: CollectType.abandoned.value,
        );
        return;

      case _BangumiDeleteSyncAction.openWeb:
        await _deleteCollectLocally(bangumiItem);
        await _openBangumiSubjectPage(bangumiItem.id);
        return;

      case _BangumiDeleteSyncAction.deleteLocalOnly:
        await _deleteCollectLocally(bangumiItem);
        return;

      case _BangumiDeleteSyncAction.cancel:
      case null:
        return;
    }
  }

  Future<void> _deleteCollectLocally(BangumiItem bangumiItem) async {
    await _collectCrudRepository.deleteCollectible(bangumiItem.id);
    await GStorage.appendCollectChange(
      bangumiId: bangumiItem.id,
      action: 3,
      type: 5,
    );
    loadCollectibles();
  }

  Future<_BangumiDeleteSyncAction?> _resolveBangumiDeleteSyncAction(
      BangumiItem bangumiItem) async {
    final bool syncEnable = GStorage.getSetting(SettingsKeys.bangumiSyncEnable);
    if (!syncEnable) {
      return _BangumiDeleteSyncAction.deleteLocalOnly;
    }

    return AnikumoDialog.show<_BangumiDeleteSyncAction>(
      clickMaskDismiss: true,
      builder: (context) => AlertDialog(
        title: Text(S.t('Bangumi 不支持删除收藏')),
        content: Text(
          S.t('因为安全考虑，Bangumi 未提供删除接口，您可以选择把本地和远端标记为“抛弃”，或者选择仅删除本地收藏并打开网页后手动删除 Bangumi 数据。'),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(_BangumiDeleteSyncAction.cancel);
            },
            child: Text(S.t('取消')),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(_BangumiDeleteSyncAction.openWeb);
            },
            child: Text(S.t('打开网页')),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop(_BangumiDeleteSyncAction.markAbandoned);
            },
            child: Text(S.t('标记为抛弃')),
          ),
        ],
      ),
    );
  }

  Future<void> _openBangumiSubjectPage(int bangumiId) async {
    final url = Uri.parse('https://bangumi.tv/subject/$bangumiId');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
      return;
    }
    AnikumoDialog.showToast(message: S.t('无法打开 Bangumi 网页'));
  }

  Future<bool> _syncBangumiCollectIfEnabled(
      int bangumiId, int localType) async {
    final bool syncEnable = GStorage.getSetting(SettingsKeys.bangumiSyncEnable);
    final bool showImmediateSyncToast =
        GStorage.getSetting(SettingsKeys.bangumiImmediateSyncToastEnable);

    if (!syncEnable) {
      return true;
    }

    final bangumi = BangumiSyncService();
    try {
      if (showImmediateSyncToast) {
        AnikumoDialog.showToast(message: S.t('正在同步到 Bangumi...'));
      }
      final bool synced =
          await bangumi.syncCollectibleWhenIdle(bangumiId, localType);
      if (synced && showImmediateSyncToast) {
        AnikumoDialog.showToast(message: S.t('已同步到 Bangumi'));
        return true;
      } else if (!synced) {
        AnikumoDialog.showToast(message: S.t('同步到 Bangumi 失败，已取消本次状态修改'));
        AnikumoLogger().w(
          'Bangumi: immediate collect sync did not complete. bangumiId=$bangumiId, type=$localType',
        );
        return false;
      }
      return true;
    } catch (e, stackTrace) {
      AnikumoDialog.showToast(
          message: S.f('同步到 Bangumi 失败，已取消本次状态修改：{}',
              [BangumiSyncService.describeError(e)]));
      AnikumoLogger().e(
        'Bangumi: immediate collect sync failed. bangumiId=$bangumiId, type=$localType',
        error: e,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  Future<void> updateLocalCollect(BangumiItem bangumiItem) async {
    await _collectCrudRepository.updateCollectible(bangumiItem);
    loadCollectibles();
  }

  /// Batch 283 (#22): batch status change from the
  /// collect page's multi-select mode. Deliberately a
  /// LOCAL write per item — the same repository write
  /// and change-log append the single-item local path
  /// performs, without the per-item Bangumi sync
  /// prompts (a batch of twenty cannot ask twenty
  /// questions); the appended changes ride the normal
  /// WebDAV/Bangumi change sync afterwards. Returns
  /// how many entries actually changed status.
  Future<int> applyBatchType(List<BangumiItem> items, int type) async {
    var changed = 0;
    for (final item in items) {
      final current = getCollectType(item);
      if (current == type) continue;
      await _collectCrudRepository.addCollectible(item, type);
      await GStorage.appendCollectChange(
        bangumiId: item.id,
        action: current == 0 ? 1 : 2,
        type: type,
      );
      changed++;
    }
    if (changed > 0) loadCollectibles();
    return changed;
  }

  /// Batch 283 (#22): batch removal, same local-write
  /// contract as [applyBatchType]. Returns how many
  /// entries were removed.
  Future<int> applyBatchRemove(List<BangumiItem> items) async {
    var removed = 0;
    for (final item in items) {
      if (getCollectType(item) == 0) continue;
      await _collectCrudRepository.deleteCollectible(item.id);
      await GStorage.appendCollectChange(
        bangumiId: item.id,
        action: 3,
        type: 5,
      );
      removed++;
    }
    if (removed > 0) loadCollectibles();
    return removed;
  }

  void _reportSyncError(String message, ValueChanged<String> onError,
      {Object? error}) {
    if (error != null) {
      AnikumoLogger().e(message, error: error);
    }
    onError(message);
  }

  Future<bool> _connectWebDav(ValueChanged<String> onError) async {
    final bool webDavCollectEnable =
        GStorage.getSetting(SettingsKeys.webDavEnableCollect);
    if (!webDavCollectEnable) {
      _reportSyncError(S.t('请开启 WebDAV 收藏同步'), onError);
      return false;
    }
    if (!WebDav().initialized) {
      _reportSyncError(S.t('WebDAV 未连接，请检查配置'), onError);
      return false;
    }
    try {
      await WebDav().ping();
    } catch (e) {
      _reportSyncError(S.t('WebDAV 连接失败，请检查网络或配置'), onError, error: e);
      return false;
    }
    return true;
  }

  Future<bool> syncCollectibles({
    required ValueChanged<String> onError,
  }) async {
    if (!await _connectWebDav(onError)) return false;
    try {
      await WebDav().syncCollectibles();
    } catch (e) {
      _reportSyncError(S.t('WebDAV 同步失败，请检查连接'), onError, error: e);
      return false;
    }
    loadCollectibles();
    return true;
  }

  // Upload without merging again after Bangumi updates the local collection.
  Future<bool> uploadCollectiblesToWebDav({
    required ValueChanged<String> onError,
  }) async {
    if (!await _connectWebDav(onError)) return false;
    try {
      await WebDav().updateCollectibles();
    } catch (e) {
      _reportSyncError(S.t('WebDAV 回传失败，请检查连接'), onError, error: e);
      return false;
    }
    return true;
  }

  Future<void> migrateCollect() async {
    final favorites = _collectCrudRepository.getFavorites();
    if (favorites.isNotEmpty) {
      int count = 0;
      for (BangumiItem bangumiItem in favorites) {
        // Migration must work before Bangumi is initialized.
        final int currentCollectType = getCollectType(bangumiItem);
        final int collectChangeAction = currentCollectType == 0 ? 1 : 2;
        await _collectCrudRepository.addCollectible(bangumiItem, 1);
        await GStorage.appendCollectChange(
          bangumiId: bangumiItem.id,
          action: collectChangeAction,
          type: 1,
        );
        count++;
      }
      await _collectCrudRepository.clearFavorites();
      loadCollectibles();
      AnikumoLogger().d(
          'GStorage: detected $count uncategorized favorites, migrated to collectibles');
    }
  }

  Future<bool> syncCollectiblesBangumi({
    required void Function(String message, int current, int total) onProgress,
    required ValueChanged<String> onError,
  }) async {
    final bool syncEnable = GStorage.getSetting(SettingsKeys.bangumiSyncEnable);
    if (!syncEnable) {
      _reportSyncError(S.t('请开启 Bangumi 同步'), onError);
      return false;
    }

    try {
      await BangumiSyncService().syncCollectibles(onProgress: onProgress);
    } catch (e) {
      _reportSyncError(BangumiSyncService.describeError(e), onError, error: e);
      return false;
    }
    loadCollectibles();
    return true;
  }
}
