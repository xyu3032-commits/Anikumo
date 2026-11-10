import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:anikumo/bean/dialog/dialog_helper.dart';
import 'package:anikumo/bean/dialog/material_bottom_sheet.dart';
import 'package:anikumo/bean/widget/anikumo_menu.dart';
import 'package:anikumo/bean/widget/loading_indicator.dart';
import 'package:anikumo/bean/widget/empty_state_widget.dart';
import 'package:anikumo/bean/widget/split_list_row.dart';
import 'package:anikumo/bean/widget/state_presentation.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:anikumo/bean/widget/mini_player_overlay.dart';
import 'package:anikumo/modules/roads/road_module.dart';
import 'package:anikumo/modules/search/plugin_search_module.dart';
import 'package:anikumo/pages/collect/collect_controller.dart';
import 'package:anikumo/request/apis/bangumi_api.dart';
import 'package:anikumo/services/tmdb/tmdb_episodes.dart';
import 'package:anikumo/pages/info/episode_plan.dart';
import 'package:anikumo/pages/info/info_controller.dart';
import 'package:anikumo/pages/video/video_playback_args.dart';
import 'package:anikumo/services/player/mini_player_session.dart';
import 'package:anikumo/services/player/watch_history_lookup.dart';
import 'package:anikumo/services/storage/storage.dart';
import 'package:anikumo/plugins/anti_crawler_config.dart';
import 'package:anikumo/plugins/plugins.dart';
import 'package:anikumo/plugins/plugins_controller.dart';
import 'package:anikumo/services/logging/logger.dart';
import 'package:anikumo/services/plugin/captcha_verification_service.dart';
import 'package:anikumo/services/plugin/plugin_search_service.dart';
import 'package:anikumo/services/plugin/rule_engine_models.dart'
    show RuleCancelToken;
import 'package:anikumo/bean/widget/anikumo_icons.dart';
import 'package:anikumo/utils/device.dart';
import 'package:url_launcher/url_launcher.dart';

part 'source_alias_dialog.dart';
part 'source_captcha_flow.dart';
part 'source_sheet_view.dart';

class SourceSheet extends StatefulWidget {
  const SourceSheet({
    super.key,
    required this.infoController,
    this.onPicked,
    this.pickEpisode = false,
    this.embedded = false,
  });

  final InfoController infoController;

  /// Batch 149: embedded in the info page's 选集 tab instead
  /// of living in a modal sheet (user call: no extra popup
  /// window — the area below the tab strip switches in
  /// place, like the other tabs). There is no route to pop:
  /// "close" affordances disappear, and starting playback
  /// navigates without popping anything first.
  final bool embedded;

  /// Batch 116: when set (the player page's source switcher), a
  /// pick is handed back to the caller instead of navigating to a
  /// new player page, and the sheet closes itself.
  final ValueChanged<OnlineVideoPlaybackArgs>? onPicked;

  /// Batch 127: episode quick-pick mode (the info page's 选集
  /// button). Picking a search result loads its roads and then
  /// shows the episode grid INSIDE the sheet; tapping an
  /// episode starts the player at exactly that episode.
  final bool pickEpisode;

  @override
  State<SourceSheet> createState() => _SourceSheetState();
}

class _SourceSheetState extends State<SourceSheet> with AnikumoDialogOwner {
  final CollectController _collectController = inject<CollectController>();
  final PluginsController _pluginsController = inject<PluginsController>();
  final Map<String, String> _sourceKeywords = {};

  /// Batch 137: episode-first pick state. The sheet opens on
  /// the episode grid (built from source-independent
  /// metadata); [_pickedEpisode] is the chosen episode,
  /// [_lineArgs] the playback args of the source chosen for
  /// it (multi-line sources detour through the line list),
  /// and [_episodeCount] the grid size resolved from Bangumi
  /// titles / TMDB stills / the local record book.
  int? _pickedEpisode;
  OnlineVideoPlaybackArgs? _lineArgs;

  /// Batch 144: while the sheet tries to reopen the source
  /// and line a watched anime was last played on, the manual
  /// list waits behind a slim veil. [_autoLineAttempt] is a
  /// token: cancelling (or picking again) invalidates the
  /// in-flight attempt so its result is dropped.
  bool _autoLineBusy = false;
  int _autoLineAttempt = 0;
  int _episodeCount = 0;
  bool _episodeMetaDone = false;
  bool _episodeGridSkipped = false;
  Map<int, String> _episodeTitles = const {};

  /// Batch 152: Bangumi air dates by episode number, from
  /// the same episodes payload as the titles — the TMDB
  /// service's alignment key when a season cannot be
  /// matched by number.
  Map<int, String> _episodeDates = const {};

  /// Batch 153: the resolved episode plan (episode_plan
  /// .dart) — its size once known, its sort → local-number
  /// map for translating watch history, and whether the
  /// numbering was scoped (sliced to the stated season or
  /// renumbered from a non-1 sort start).
  int _planCount = 0;
  Map<int, int> _sortToLocal = const {};
  bool _numberingScoped = false;

  /// Batch 129: per-episode stills/metadata from TMDB
  /// (empty unless the user set their API key and a match
  /// resolved).
  Map<int, TmdbEpisodeStill> _episodeStills = const {};

  late final String _keyword;
  late final PluginSearchService _searchService;
  late final _SourceCaptchaFlow _captchaFlow;

  @override
  void initState() {
    super.initState();
    final item = widget.infoController.bangumiItem;
    _keyword = item.nameCn.isEmpty ? item.name : item.nameCn;
    _searchService = PluginSearchService(
      infoController: widget.infoController,
      pluginsController: _pluginsController,
    );
    _captchaFlow = _SourceCaptchaFlow(
      onVerified: _showVerifiedResult,
      onCancelled: (plugin) => _retry(plugin.name),
    );
    _searchService.queryAllSource(_keyword);
    if (widget.pickEpisode && widget.onPicked == null) {
      unawaited(_loadEpisodeMeta());
    }
  }

  bool get _episodeFirst => widget.pickEpisode && widget.onPicked == null;

  /// Batch 137: resolve how many episodes the grid shows
  /// without any source: the local record book gives a floor
  /// for watched anime, Bangumi episode titles the real
  /// count, TMDB stills a cross-check. Each source only ever
  /// grows the count; when all three come up empty the sheet
  /// falls back to the classic source-first list.
  Future<void> _loadEpisodeMeta() async {
    final item = widget.infoController.bangumiItem;
    final record = latestOnlineHistory(GStorage.histories.values, item.id);
    var count = 0;
    if (record != null) {
      for (final progress in record.progresses.values) {
        if (progress.episode > count) count = progress.episode;
      }
      if (record.lastWatchEpisode > count) {
        count = record.lastWatchEpisode;
      }
    }
    if (count > 0 && mounted) setState(() => _episodeCount = count);
    await _loadEpisodeTitles();
    if (!mounted) return;
    if (_planCount > 0) {
      // Batch 153: a resolved episode plan is the count's
      // authority — the history floor above and the still
      // keys below live in other numberings and must not
      // re-inflate the scoped grid.
      setState(() => _episodeCount = _planCount);
    } else {
      for (final episode in _episodeTitles.keys) {
        if (episode > _episodeCount) {
          setState(() => _episodeCount = episode);
        }
      }
    }
    await _loadEpisodeStills(_episodeCount);
    if (!mounted) return;
    if (_planCount == 0) {
      for (final episode in _episodeStills.keys) {
        if (episode > _episodeCount) {
          setState(() => _episodeCount = episode);
        }
      }
    }
    if (mounted) setState(() => _episodeMetaDone = true);
  }

  @override
  void dispose() {
    _searchService.cancel();
    _captchaFlow.dispose();
    super.dispose();
  }

  String _keywordFor(String name) => _sourceKeywords[name] ?? _keyword;

  Plugin _pluginFor(String name) =>
      _pluginsController.pluginList.firstWhere((plugin) => plugin.name == name);

  void _querySource(String keyword, String pluginName) {
    final trimmed = keyword.trim();
    if (!mounted || trimmed.isEmpty) return;
    setState(() => _sourceKeywords[pluginName] = trimmed);
    _searchService.querySource(trimmed, pluginName);
  }

  void _retry(String name) => _querySource(_keywordFor(name), name);

  /// Batch 149: pops the hosting sheet before navigating —
  /// a no-op in the embedded tab mode, where there is no
  /// sheet route on the stack.
  void _closeSelf() {
    if (widget.embedded) return;
    Navigator.of(context).pop();
  }

  void _showVerifiedResult(Plugin plugin, String pageHtml) {
    if (!mounted) return;
    if (_searchService.applyHarvestedSearchResult(plugin.name, pageHtml)) {
      AnikumoDialog.showToast(message: '验证成功');
      return;
    }
    _captchaFlow.showSuccess(
      plugin.name,
      onComplete: () => _retry(plugin.name),
    );
  }

  Future<void> _openInBrowser(String name) async {
    final plugin = _pluginFor(name);
    final targetUrl = plugin.usesApiSearch
        ? plugin.baseUrl
        : plugin.searchURL.replaceAll(
            '@keyword',
            Uri.encodeQueryComponent(_keywordFor(name)),
          );
    try {
      if (await launchUrl(Uri.parse(targetUrl),
          mode: LaunchMode.externalApplication)) {
        return;
      }
    } catch (error) {
      AnikumoLogger().w('SourceSheet: failed to open browser', error: error);
    }
    if (mounted) AnikumoDialog.showToast(message: '无法打开浏览器，请稍后重试');
  }

  Future<void> _openSearchItem(String name, SearchItem searchItem) async {
    if (dialogs.isRunning) return;
    final plugin = _pluginFor(name);
    // Batch 116: an explicit pick of a DIFFERENT source for the
    // anime the mini player is playing is a deliberate switch —
    // the mini session ends so the pick is honoured (the module's
    // same-anime resume would otherwise force the old source).
    // Player mode (onPicked) handles its session itself.
    if (widget.onPicked == null) {
      final session = MiniPlayerSession.instance;
      final sessionArgs = session.args;
      if (sessionArgs is OnlineVideoPlaybackArgs &&
          sessionArgs.bangumiItem.id ==
              widget.infoController.bangumiItem.id &&
          sessionArgs.plugin.name != plugin.name) {
        await session.close();
      }
    }
    await dialogs.run((task) async {
      final cancelToken = RuleCancelToken();
      final roads = await task.loading(
        message: '正在获取播放列表',
        barrierDismissible: isDesktop(),
        onCancel: cancelToken.cancel,
        action: () =>
            plugin.queryChapterRoads(searchItem.src, cancelToken: cancelToken),
      );
      if (roads.isEmpty) throw ChapterErrorException(plugin.name);
      final args = OnlineVideoPlaybackArgs(
        bangumiItem: widget.infoController.bangumiItem,
        plugin: plugin,
        title: searchItem.name,
        src: searchItem.src,
        roads: roads,
      );
      // Batch 137: in episode-first mode the episode is
      // already picked — this result only supplies the line.
      // A single-line source plays at once; a multi-line one
      // detours through the line list so the viewer picks
      // the exact line for their episode.
      if (widget.pickEpisode && widget.onPicked == null) {
        if (roads.length == 1) {
          final episode = _pickedEpisode ?? 1;
          task.withContext((context) {
            _closeSelf();
            pushPlayerPageFromOverlay(OnlineVideoPlaybackArgs(
              bangumiItem: args.bangumiItem,
              plugin: args.plugin,
              title: args.title,
              src: args.src,
              roads: args.roads,
              initialEpisode: episode,
              initialRoad: 0,
            ));
          });
        } else if (mounted) {
          setState(() => _lineArgs = args);
        }
        return;
      }
      final onPicked = widget.onPicked;
      if (onPicked != null) {
        task.withContext((context) {
          _closeSelf();
          onPicked(args);
        });
        return;
      }
      task.withContext((context) => context.pushNamed(
            '/video/',
            arguments: args,
          ));
    }, onError: (error, stackTrace) {
      AnikumoLogger().w('SourceSheet: failed to query playlist', error: error);
      AnikumoDialog.showToast(message: '未能获取播放列表，请重试或选择其他结果');
    });
  }

  void _showAliasPicker(String pluginName) {
    if (widget.infoController.bangumiItem.alias.isEmpty) {
      AnikumoDialog.showToast(message: '无可用别名，试试修改检索关键词');
      return;
    }
    _showAliasPickerDialog(
      sourceName: pluginName,
      aliases: widget.infoController.bangumiItem.alias,
      onAliasSelected: (alias) => _querySource(alias, pluginName),
      onAliasesChanged: () => _collectController
          .updateLocalCollect(widget.infoController.bangumiItem),
    );
  }

  void _showCustomKeyword(String pluginName) => _showCustomKeywordDialog(
        initialKeyword: _keywordFor(pluginName),
        sourceName: pluginName,
        onSubmit: (keyword) {
          final item = widget.infoController.bangumiItem;
          if (!item.alias.contains(keyword)) {
            item.alias.add(keyword);
            _collectController.updateLocalCollect(item);
          }
          _querySource(keyword, pluginName);
        },
      );

  /// Batch 127: Bangumi episode titles for the quick-pick
  /// grid (main episodes only), keyed by episode number.
  /// Best-effort — the grid falls back to bare 第N集 labels.
  /// Batch 153: the episodes are first resolved into a
  /// picker plan (episode_plan.dart — season slicing and
  /// renumbering); titles and air dates are keyed by the
  /// plan's LOCAL numbers from here on.
  Future<void> _loadEpisodeTitles() async {
    try {
      final episodes = await BangumiApi.getBangumiEpisodesByID(
        widget.infoController.bangumiItem.id,
      );
      if (!mounted) return;
      final item = widget.infoController.bangumiItem;
      final plan = planEpisodes(
        episodes: episodes,
        statedSeason: statedSeasonNumber(item.nameCn) ??
            statedSeasonNumber(item.name),
      );
      setState(() {
        if (plan.episodes.isNotEmpty) {
          _planCount = plan.count;
          _sortToLocal = plan.sortToNumber;
          _numberingScoped = plan.scoped;
        }
        _episodeTitles = {
          for (final e in plan.episodes) e.number: e.title,
        };
        _episodeDates = {
          for (final e in plan.episodes)
            if (e.airDate.isNotEmpty) e.number: e.airDate,
        };
      });
    } catch (_) {
      // Titles are decoration; the picker works without them.
    }
  }

  /// Batch 153: watch history is recorded in Bangumi sort
  /// space; under a scoped plan the grid's numbers are
  /// local, so watched fills are translated through the
  /// plan (episodes outside the plan drop out of view).
  Map<int, Duration> _remapWatched(Map<int, Duration> bySort) {
    if (!_numberingScoped) return bySort;
    return {
      for (final entry in bySort.entries)
        if (_sortToLocal[entry.key] != null)
          _sortToLocal[entry.key]!: entry.value,
    };
  }

  /// Batch 129: per-episode stills from TMDB (the user's own
  /// key; silently empty without one). [episodeCount] is the
  /// first road's length — the season-match hint.
  Future<void> _loadEpisodeStills(int episodeCount) async {
    final stills = await TmdbEpisodeService.stillsFor(
      widget.infoController.bangumiItem,
      episodeCount: episodeCount,
      episodeDates: _episodeDates,
    );
    if (!mounted || stills.isEmpty) return;
    setState(() => _episodeStills = stills);
  }

  /// Batch 144: an episode was picked. Watched anime get one
  /// automatic shot at the source + line they were last
  /// played on (the batch-137 flow made even re-watching a
  /// known anime re-pick everything by hand); unwatched
  /// anime, and any failure, land on the manual source list
  /// exactly as before.
  void _pickEpisode(int episode) {
    setState(() => _pickedEpisode = episode);
    unawaited(_tryAutoLine(episode));
  }

  Future<void> _tryAutoLine(int episode) async {
    final item = widget.infoController.bangumiItem;
    final record = latestOnlineHistory(GStorage.histories.values, item.id);
    if (record == null || record.lastSrc.isEmpty) return;
    Plugin? plugin;
    for (final candidate in _pluginsController.pluginList) {
      if (candidate.name == record.adapterName) {
        plugin = candidate;
        break;
      }
    }
    if (plugin == null) return;
    final attempt = ++_autoLineAttempt;
    setState(() => _autoLineBusy = true);
    try {
      final roads = await plugin.queryChapterRoads(record.lastSrc);
      if (!mounted ||
          attempt != _autoLineAttempt ||
          _pickedEpisode != episode) {
        return;
      }
      if (roads.isEmpty) return;
      var road = preferredRoadIndex(record, roads.length);
      if (episode > roads[road].data.length) {
        // The remembered line does not carry this episode;
        // take any line that does, else fall back to manual.
        var found = -1;
        for (var i = 0; i < roads.length; i++) {
          if (roads[i].data.length >= episode) {
            found = i;
            break;
          }
        }
        if (found < 0) return;
        road = found;
      }
      if (_numberingScoped && roads[road].data.length != _episodeCount) {
        // Batch 153: the remembered line was recorded in
        // sort space; under the scoped numbering its
        // positions name different episodes. Auto-play
        // only when the line's length matches the scoped
        // grid exactly (in practice, the same season's
        // entry); any other line waits for a manual pick
        // rather than opening the wrong episode.
        return;
      }
      final args = OnlineVideoPlaybackArgs(
        bangumiItem: item,
        plugin: plugin,
        title: item.nameCn.isEmpty ? item.name : item.nameCn,
        src: record.lastSrc,
        roads: roads,
        initialEpisode: episode,
        initialRoad: road,
      );
      _closeSelf();
      pushPlayerPageFromOverlay(args);
    } catch (_) {
      // Any failure lands on the manual source list, which is
      // already waiting behind the veil.
    } finally {
      if (mounted && attempt == _autoLineAttempt) {
        setState(() => _autoLineBusy = false);
      }
    }
  }

  void _cancelAutoLine() {
    _autoLineAttempt++;
    setState(() => _autoLineBusy = false);
  }

  /// Batch 137: start the player at the picked episode on
  /// the picked line. The sheet pops first; navigation goes
  /// through the root navigator's context (the batch-121
  /// helper) because this sheet's own context dies with the
  /// pop.
  void _playPickedEpisode(int road) {
    final base = _lineArgs;
    final episode = _pickedEpisode;
    if (base == null || episode == null) return;
    final args = OnlineVideoPlaybackArgs(
      bangumiItem: base.bangumiItem,
      plugin: base.plugin,
      title: base.title,
      src: base.src,
      roads: base.roads,
      initialEpisode: episode,
      initialRoad: road,
    );
    _closeSelf();
    pushPlayerPageFromOverlay(args);
  }

  @override
  Widget build(BuildContext context) => Observer(
        builder: (context) {
          // Batch 137: episode-first flow for every anime,
          // watched or not: episode grid first, then the
          // source list, then (for multi-line sources) the
          // line list. No history auto-loads remain.
          if (_episodeFirst) {
            final item = widget.infoController.bangumiItem;
            final lineArgs = _lineArgs;
            if (lineArgs != null) {
              return _LineRoadsView(
                episode: _pickedEpisode ?? 1,
                pluginName: lineArgs.plugin.name,
                roads: lineArgs.roads,
                onRoad: _playPickedEpisode,
                onBack: () => setState(() => _lineArgs = null),
                onClose: widget.embedded ? null : () => Navigator.of(context).pop(),
              );
            }
            if (_autoLineBusy) {
              return _EpisodeAutoLoadView(
                label: '正在打开上次的线路…',
                onManual: _cancelAutoLine,
                onClose: widget.embedded ? null : () => Navigator.of(context).pop(),
              );
            }
            if (_pickedEpisode == null && !_episodeGridSkipped) {
              if (_episodeCount > 0) {
                final record = latestOnlineHistory(
                  GStorage.histories.values,
                  item.id,
                );
                return _EpisodePickerView(
                  title: item.nameCn.isEmpty ? item.name : item.nameCn,
                  episodeCount: _episodeCount,
                  coverUrl:
                      item.images['large'] ?? item.images['common'] ?? '',
                  episodeTitles: _episodeTitles,
                  stills: _episodeStills,
                  watched: record == null
                      ? const <int, Duration>{}
                      : _remapWatched(watchedDurations(
                          record,
                          preferredRoadIndex(record, 1 << 20),
                        )),
                  onEpisode: _pickEpisode,
                  onClose: widget.embedded ? null : () => Navigator.of(context).pop(),
                );
              }
              if (!_episodeMetaDone) {
                return _EpisodeAutoLoadView(
                  onManual: () =>
                      setState(() => _episodeGridSkipped = true),
                  onClose: widget.embedded ? null : () => Navigator.of(context).pop(),
                );
              }
              // Metadata came up empty — fall through to the
              // classic source-first list below.
            }
          }
          // Snapshot observable values here; lazy list builders are not tracked.
          final groupsByName = {
            for (final plugin in _pluginsController.pluginList)
              plugin.name: _SourceSearchGroup(
                name: plugin.name,
                keyword: _keywordFor(plugin.name),
                status: widget.infoController.pluginSearchStatus[plugin.name] ??
                    PluginSearchStatus.pending,
                results: <SearchItem>[],
              ),
          };
          final seenBySource = <String, Set<String>>{};
          String? firstResultSource;
          // Responses follow completion order; groups keep configured order.
          for (final response
              in widget.infoController.pluginSearchResponseList) {
            final group = groupsByName[response.pluginName];
            if (group == null) continue;
            final seen = seenBySource.putIfAbsent(group.name, () => <String>{});
            for (final result in response.data) {
              if (seen.add(result.src)) group.results.add(result);
            }
            if (group.hasResults) firstResultSource ??= group.name;
          }
          // Batch 160: lead each group with the result for
          // the season THIS subject states. Plugin sites
          // list newest first and the group preview shows
          // only the top result, so a second-season subject
          // used to present its third season as the default.
          final bangumiItem = widget.infoController.bangumiItem;
          final statedSeason = statedSeasonNumber(bangumiItem.nameCn) ??
              statedSeasonNumber(bangumiItem.name);
          if (statedSeason != null) {
            for (final group in groupsByName.values) {
              if (group.results.length > 1) {
                final ordered = orderByStatedSeason<SearchItem>(
                  group.results,
                  statedSeason: statedSeason,
                  titleOf: (result) => result.name,
                );
                group.results
                  ..clear()
                  ..addAll(ordered);
              }
            }
          }
          return _SourceSheetView(
            pickedEpisode: _episodeFirst ? _pickedEpisode : null,
            onBackToEpisodes: _episodeFirst && _pickedEpisode != null
                ? () => setState(() => _pickedEpisode = null)
                : null,
            keyword: _keyword,
            groups: groupsByName.values.toList(),
            firstResultSource: firstResultSource,
            onSourceSearch: _showCustomKeyword,
            onSourceAliasSearch: _showAliasPicker,
            onRetry: _retry,
            onVerify: (name) =>
                _captchaFlow.start(_pluginFor(name), _keywordFor(name)),
            onOpenBrowser: _openInBrowser,
            onPlay: _openSearchItem,
            onClose: widget.embedded ? null : () => Navigator.of(context).pop(),
          );
        },
      );
}
