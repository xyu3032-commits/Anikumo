import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:anikumo/bean/dialog/dialog_helper.dart';
import 'package:anikumo/bean/widget/anikumo_icons.dart';
import 'package:anikumo/pages/video/video_playback_args.dart';
import 'package:anikumo/services/i18n/app_strings.dart';
import 'package:anikumo/services/player/history_playback_service.dart';
import 'package:anikumo/services/player/play_queue.dart';

/// Batch 277 (#1): plays one queued [entry] now.
///
/// Same work on the same source: switches episode in
/// place through [changeEpisode]. Any other work: the
/// entry is rebuilt into a history record and resolved by
/// the shared [HistoryPlaybackService], then pushed as a
/// new player page with the queued episode pinned (an
/// explicit pick beats history resume on the new page).
/// Returns false when a cross-work entry could not be
/// resolved; the failure toast has already been shown.
Future<bool> playPlayQueueEntry(
  BuildContext context, {
  required PlayQueueEntry entry,
  required int currentBangumiId,
  required String currentAdapterName,
  required Future<void> Function(int episode, {int currentRoad, int offset})
      changeEpisode,
}) async {
  final sameWork = entry.bangumiId == currentBangumiId &&
      entry.adapterName.isNotEmpty &&
      entry.adapterName == currentAdapterName;
  if (sameWork) {
    await changeEpisode(entry.episode, currentRoad: entry.road);
    return true;
  }
  final result = await inject<HistoryPlaybackService>()
      .open(PlayQueue.historyFor(entry));
  switch (result) {
    case HistoryPlaybackReady(:final args):
      var resolved = args;
      if (args is OnlineVideoPlaybackArgs) {
        resolved = OnlineVideoPlaybackArgs(
          bangumiItem: args.bangumiItem,
          plugin: args.plugin,
          title: args.title,
          src: args.src,
          roads: args.roads,
          initialEpisode: entry.episode,
          initialRoad: entry.road,
        );
      }
      if (!context.mounted) return false;
      await context.pushNamed('/video/', arguments: resolved);
      return true;
    case HistoryPlaybackUnavailable(:final reason):
      AnikumoDialog.showToast(message: reason);
      return false;
  }
}

/// Batch 277 (#1): the play-queue sheet — list, remove,
/// clear, play now. Opened from the player panel.
Future<void> showPlayQueueSheet(
  BuildContext context, {
  required int currentBangumiId,
  required String currentAdapterName,
  required Future<void> Function(int episode, {int currentRoad, int offset})
      changeEpisode,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => _PlayQueueSheet(
      anchorContext: context,
      currentBangumiId: currentBangumiId,
      currentAdapterName: currentAdapterName,
      changeEpisode: changeEpisode,
    ),
  );
}

class _PlayQueueSheet extends StatefulWidget {
  const _PlayQueueSheet({
    required this.anchorContext,
    required this.currentBangumiId,
    required this.currentAdapterName,
    required this.changeEpisode,
  });

  /// The player page's context, still mounted after this
  /// sheet closes — cross-work playback navigates from it.
  final BuildContext anchorContext;
  final int currentBangumiId;
  final String currentAdapterName;
  final Future<void> Function(int episode, {int currentRoad, int offset})
      changeEpisode;

  @override
  State<_PlayQueueSheet> createState() => _PlayQueueSheetState();
}

class _PlayQueueSheetState extends State<_PlayQueueSheet> {
  late List<PlayQueueEntry> _entries = PlayQueue.entries();

  Future<void> _removeAt(int index) async {
    final next = await PlayQueue.removeAt(index);
    if (mounted) setState(() => _entries = next);
  }

  Future<void> _clear() async {
    await PlayQueue.clear();
    if (mounted) setState(() => _entries = const []);
  }

  Future<void> _playNow(PlayQueueEntry entry) async {
    // Captured up front: this sheet's own context is dead
    // once it pops, playback navigates from the anchor.
    final anchorContext = widget.anchorContext;
    // Playing an entry consumes it, wherever it sits.
    final index = _entries.indexOf(entry);
    if (index >= 0) {
      await PlayQueue.removeAt(index);
    }
    if (!mounted) return;
    Navigator.of(context).pop();
    // The anchor is the player page's context, which
    // outlives this sheet; playPlayQueueEntry re-checks
    // its mounted state before navigating.
    // ignore: use_build_context_synchronously
    await playPlayQueueEntry(
      anchorContext,
      entry: entry,
      currentBangumiId: widget.currentBangumiId,
      currentAdapterName: widget.currentAdapterName,
      changeEpisode: widget.changeEpisode,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    S.t('播放队列'),
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                TextButton(
                  onPressed: _entries.isEmpty ? null : _clear,
                  child: Text(S.t('清空队列')),
                ),
              ],
            ),
            if (_entries.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(child: Text(S.t('队列是空的'))),
              )
            else
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.5,
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _entries.length,
                  itemBuilder: (context, index) {
                    final entry = _entries[index];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(AnikumoIcons.playlist_play_rounded),
                      title: Text(
                        entry.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        S.f('第{}集 · 线路 {}', [entry.episode, entry.road + 1]),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: S.t('立即播放'),
                            icon: const Icon(AnikumoIcons.play_arrow_rounded),
                            onPressed: () => _playNow(entry),
                          ),
                          IconButton(
                            tooltip: S.t('移除'),
                            icon: const Icon(AnikumoIcons.delete_outline),
                            onPressed: () => _removeAt(index),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
