import 'dart:async';

import 'package:anikumo/modules/bangumi/bangumi_item.dart';
import 'package:anikumo/modules/history/history_module.dart';
import 'package:anikumo/repositories/history_repository.dart';
import 'package:anikumo/services/anime/anime_features.dart';
import 'package:anikumo/services/sync/bangumi_sync_service.dart';
import 'package:mobx/mobx.dart';

part 'history_controller.g.dart';

class HistoryController = _HistoryController with _$HistoryController;

abstract class _HistoryController with Store {
  _HistoryController(this._historyRepository);

  final IHistoryRepository _historyRepository;

  @observable
  ObservableList<History> histories = ObservableList<History>();

  void init() {
    final temp = _historyRepository.getAllHistories();
    histories.clear();
    histories.addAll(temp);
  }

  Future<void> updateHistory(
    PlaybackHistoryIdentity identity,
    Duration progress, {
    Duration duration = Duration.zero,
  }) async {
    await _historyRepository.updateHistory(
      identity: identity,
      progress: progress,
      duration: duration,
    );
    init();
    // Batch 233 （单集进度同步 pack): an episode watched
    // past 95% is reported to Bangumi as watched. The
    // sync service re-checks every gate and the
    // already-sent set, so repeat ticks stay cheap.
    if (AnimeFeatures.isInstalled(AnimeFeatures.bgmProgressId) &&
        duration > Duration.zero &&
        progress.inMilliseconds >= duration.inMilliseconds * 0.95 &&
        identity.entryKind == HistoryEntryKind.online &&
        !AnimeBgmSyncedStore.contains(
          identity.bangumiItem.id,
          identity.episodeNumber,
        )) {
      unawaited(
        BangumiSyncService()
            .syncEpisodeProgress(
              identity.bangumiItem.id,
              identity.episodeNumber,
            )
            .catchError((_) => false),
      );
    }
  }

  Progress? lastWatching(
    BangumiItem bangumiItem,
    String adapterName, {
    String entryKind = HistoryEntryKind.online,
  }) {
    return _historyRepository.getLastWatchingProgress(
      bangumiItem,
      adapterName,
      entryKind: entryKind,
    );
  }

  Progress? findProgress(
    BangumiItem bangumiItem,
    String adapterName,
    int episode, {
    String entryKind = HistoryEntryKind.online,
  }) {
    return _historyRepository.findProgress(
      bangumiItem,
      adapterName,
      episode,
      entryKind: entryKind,
    );
  }

  Future<void> deleteHistory(History history) async {
    await _historyRepository.deleteHistory(history);
    init();
  }

  Future<void> clearAll() async {
    await _historyRepository.clearAllHistories();
    histories.clear();
  }
}
