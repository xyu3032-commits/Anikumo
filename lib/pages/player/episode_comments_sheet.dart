import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:anikumo/bean/dialog/dialog_helper.dart';
import 'package:anikumo/modules/bangumi/episode_item.dart';
import 'package:anikumo/pages/player/episode_comments_picker.dart';
import 'package:anikumo/pages/player/episode_comments_view.dart';
import 'package:anikumo/pages/video/video_controller.dart';
import 'package:anikumo/pages/video/video_playback_args.dart';
import 'package:anikumo/request/apis/bangumi_api.dart';

class EpisodeCommentsSheet extends StatefulWidget {
  const EpisodeCommentsSheet({
    super.key,
    required this.videoPageController,
    required this.episode,
    required this.selection,
  });

  final VideoPageController videoPageController;
  final int episode;
  final VideoEpisodeSelection selection;

  @override
  State<EpisodeCommentsSheet> createState() => _EpisodeCommentsSheetState();
}

class _EpisodeCommentsSheetState extends State<EpisodeCommentsSheet>
    with AnikumoDialogOwner {
  VideoPageController get _controller => widget.videoPageController;
  late int _selectedEpisode;
  bool _isLoading = false;
  bool _hasError = false;
  int _requestVersion = 0;
  final Map<int, EpisodeInfo> _episodeInfoByIndex = {};

  @override
  void initState() {
    super.initState();
    _resetAndScheduleRefresh();
  }

  @override
  void didUpdateWidget(covariant EpisodeCommentsSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    final controllerChanged =
        oldWidget.videoPageController != widget.videoPageController;
    if (controllerChanged) {
      _episodeInfoByIndex.clear();
    }
    if (oldWidget.selection != widget.selection ||
        controllerChanged ||
        (oldWidget.episode != widget.episode &&
            widget.episode != _selectedEpisode)) {
      _resetAndScheduleRefresh();
    }
  }

  /// Batch 244: an external session that lends reviews —
  /// its 评论 tab shows those instead of Bangumi episode
  /// comments (which external sessions cannot load).
  bool get _externalReviews =>
      _controller.isExternalPlayback &&
      _controller.externalReviewsLoader != null;

  void _resetAndScheduleRefresh() {
    dialogs.cancel();
    if (_externalReviews) {
      _isLoading = false;
      _hasError = false;
      return;
    }
    final version = ++_requestVersion;
    _selectedEpisode = widget.episode;
    _hasError = false;
    _isLoading = _controller.commentsEpisode != _selectedEpisode ||
        _controller.episodeCommentsList.isEmpty;
    if (_isLoading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && version == _requestVersion) {
          unawaited(_loadComments());
        }
      });
    }
  }

  Future<void> _loadComments() async {
    final version = ++_requestVersion;
    setState(() {
      _isLoading = true;
      _hasError = false;
    });
    try {
      final applied = await _controller.queryBangumiEpisodeCommentsByID(
          _controller.bangumiItem.id, _selectedEpisode);
      if (!mounted || version != _requestVersion || !applied) return;
      if (_controller.episodeInfo.id != 0) {
        _rememberEpisodeInfo(_selectedEpisode, _controller.episodeInfo);
      }
      setState(() => _isLoading = false);
    } catch (_) {
      if (!mounted || version != _requestVersion) return;
      setState(() {
        _isLoading = false;
        _hasError = true;
      });
    }
  }

  void _rememberEpisodeInfo(int index, EpisodeInfo info) {
    // Playback resets the controller's EpisodeInfo in place when switching.
    _episodeInfoByIndex[index] = EpisodeInfo(
      id: info.id,
      episode: info.episode,
      type: info.type,
      name: info.name,
      nameCn: info.nameCn,
      airDate: info.airDate,
    );
  }

  Future<void> _showEpisodeSelection() async {
    if (dialogs.isRunning) return;
    final controller = _controller;
    await dialogs.run((task) async {
      final episodes = await task.loading(
        message: '分集列表加载中',
        action: () =>
            BangumiApi.getBangumiEpisodesByID(controller.bangumiItem.id),
      );
      if (episodes.isEmpty) {
        AnikumoDialog.showToast(message: '未找到分集列表');
        return;
      }
      for (var index = 0; index < episodes.length; index++) {
        _rememberEpisodeInfo(index + 1, episodes[index]);
      }
      final selected = await task.show<int>(
        builder: (context) => EpisodeCommentsPicker(
          episodes: episodes,
          selectedEpisode: _selectedEpisode,
        ),
      );
      if (selected == _selectedEpisode) return;
      _selectedEpisode = selected;
      unawaited(_loadComments());
    }, errorMessage: '分集列表加载失败，请稍后重试');
  }

  @override
  Widget build(BuildContext context) {
    if (_externalReviews) {
      return _ExternalReviewsView(loader: _controller.externalReviewsLoader!);
    }
    return Observer(builder: (context) {
      final matchesEpisode = _controller.commentsEpisode == _selectedEpisode;
      final comments = _controller.episodeCommentsList.toList();
      return EpisodeCommentsView(
        episode: _selectedEpisode,
        episodeInfo: matchesEpisode && _controller.episodeInfo.id != 0
            ? _controller.episodeInfo
            : _episodeInfoByIndex[_selectedEpisode],
        comments: matchesEpisode ? comments : [],
        isLoading: _isLoading,
        hasError: _hasError,
        isAscending: _controller.isCommentsAscending,
        onToggleSort: _controller.toggleSortOrder,
        onSelectEpisode: _showEpisodeSelection,
        onRefresh: _loadComments,
      );
    });
  }
}

/// Batch 244: the 评论 tab for an external session that
/// lends work-level reviews (the film zone's TMDB
/// reviews). Loads once per sheet; the anime path never
/// builds this widget.
class _ExternalReviewsView extends StatefulWidget {
  const _ExternalReviewsView({required this.loader});

  final ExternalReviewsLoader loader;

  @override
  State<_ExternalReviewsView> createState() => _ExternalReviewsViewState();
}

class _ExternalReviewsViewState extends State<_ExternalReviewsView> {
  late final Future<List<ExternalReview>> _future = widget.loader();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<ExternalReview>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final reviews = snapshot.data ?? const <ExternalReview>[];
        if (reviews.isEmpty) {
          return const Center(child: Text('暂无影评'));
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          itemCount: reviews.length,
          separatorBuilder: (_, _) => const Divider(height: 20),
          itemBuilder: (context, index) {
            final review = reviews[index];
            final scheme = Theme.of(context).colorScheme;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        review.author.isEmpty ? '匿名' : review.author,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    // Batch 245: which source this review
                    // came from (the stream mixes TMDB and
                    // Bangumi comments).
                    if (review.source.isNotEmpty) ...[
                      Text(
                        review.source,
                        style: TextStyle(
                          color: scheme.primary,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    if (review.rating != null)
                      Text(
                        '★ ${review.rating!.toStringAsFixed(1)}',
                        style: TextStyle(
                          color: scheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    if (review.date.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Text(
                        review.date,
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 6),
                Text(review.content),
              ],
            );
          },
        );
      },
    );
  }
}
