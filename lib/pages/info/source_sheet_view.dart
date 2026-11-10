part of 'source_sheet.dart';

class _SourceSearchGroup {
  const _SourceSearchGroup({
    required this.name,
    required this.keyword,
    required this.status,
    required this.results,
  });

  final String name;
  final String keyword;
  final PluginSearchStatus status;
  final List<SearchItem> results;

  bool get isSearching => status == PluginSearchStatus.pending;
  bool get hasResults =>
      status == PluginSearchStatus.success && results.isNotEmpty;

  String get statusLabel => switch (status) {
        PluginSearchStatus.pending => '检索中…',
        PluginSearchStatus.success =>
          results.isEmpty ? '无结果' : '${results.length} 个结果',
        PluginSearchStatus.noResult => '无结果',
        PluginSearchStatus.error => '检索失败',
        PluginSearchStatus.captcha => '需要验证',
        PluginSearchStatus.circuitOpen => '暂时熔断',
        PluginSearchStatus.timeout => '检索超时',
      };
}

enum _SourceDisplay { preview, expanded, collapsed }

class _SourceSheetView extends StatefulWidget {
  const _SourceSheetView({
    this.pickedEpisode,
    this.onBackToEpisodes,
    required this.keyword,
    required this.groups,
    required this.firstResultSource,
    required this.onSourceSearch,
    required this.onSourceAliasSearch,
    required this.onRetry,
    required this.onVerify,
    required this.onOpenBrowser,
    required this.onPlay,
    required this.onClose,
  });

  final String keyword;
  /// Batch 137: in the episode-first flow, the episode the
  /// viewer already picked (the list below chooses its
  /// source/line); null in the classic source-first mode.
  final int? pickedEpisode;

  /// Batch 137: back to the episode grid (episode-first flow
  /// only); renders the slim context bar above the header.
  final VoidCallback? onBackToEpisodes;

  final List<_SourceSearchGroup> groups;
  final String? firstResultSource;
  final ValueChanged<String> onSourceSearch;
  final ValueChanged<String> onSourceAliasSearch;
  final ValueChanged<String> onRetry;
  final ValueChanged<String> onVerify;
  final ValueChanged<String> onOpenBrowser;
  final void Function(String sourceName, SearchItem result) onPlay;

  /// Batch 149: null in the embedded （选集 tab) mode — there
  /// is no sheet to close, so the header shows no ✕.
  final VoidCallback? onClose;

  @override
  State<_SourceSheetView> createState() => _SourceSheetViewState();
}

class _SourceSheetViewState extends State<_SourceSheetView> {
  final _scrollController = ScrollController();
  final _display = <String, _SourceDisplay>{};
  final _headerKeys = <String, GlobalKey>{};
  bool _autoExpansionHandled = false;

  @override
  void initState() {
    super.initState();
    _autoExpandFirstResult();
  }

  @override
  void didUpdateWidget(covariant _SourceSheetView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final names = widget.groups.map((group) => group.name).toSet();
    _display.removeWhere((name, _) => !names.contains(name));
    _headerKeys.removeWhere((name, _) => !names.contains(name));
    _autoExpandFirstResult();
  }

  void _autoExpandFirstResult() {
    final name = widget.firstResultSource;
    if (_autoExpansionHandled || name == null) return;
    _autoExpansionHandled = true;
    _display[name] = _SourceDisplay.preview;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _setDisplay(String name, _SourceDisplay display) {
    setState(() {
      _autoExpansionHandled = true;
      _display[name] = display;
    });
  }

  void _collapseFromFooter(String name) {
    final headerContext = _headerKeys[name]?.currentContext;
    if (headerContext != null) {
      // Anchor before shrinking, while the header is still laid out.
      Scrollable.ensureVisible(headerContext, alignment: 0);
    }
    _setDisplay(name, _SourceDisplay.collapsed);
  }

  Widget _animateSize(Widget child) => MediaQuery.disableAnimationsOf(context)
      ? child
      : AnimatedSize(
          duration: splitListMotionDuration,
          curve: splitListMotionCurve,
          alignment: Alignment.topCenter,
          child: child,
        );

  @override
  Widget build(BuildContext context) {
    final pending = widget.groups.where((group) => group.isSearching).length;
    final resultCount = widget.groups
        .where((group) => group.hasResults)
        .fold(0, (sum, group) => sum + group.results.length);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          if (widget.onBackToEpisodes != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 16, 0),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(AnikumoIcons.arrow_back_rounded, size: 20),
                    tooltip: '重选集数',
                    onPressed: widget.onBackToEpisodes,
                  ),
                  Expanded(
                    child: Text(
                      '已选第${widget.pickedEpisode}集 · 下面选来源和线路',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          MaterialBottomSheetHeader(
            title: '播放来源',
            description: pending > 0
                ? '检索中 ${widget.groups.length - pending}/${widget.groups.length} · $resultCount 个结果'
                : '${widget.groups.length} 个来源 · $resultCount 个结果',
            compact: true,
            onClose: widget.onClose,
          ),
          Expanded(
            child: Scrollbar(
              controller: _scrollController,
              child: CustomScrollView(
                controller: _scrollController,
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    sliver: SliverList.builder(
                      itemCount: widget.groups.length,
                      findChildIndexCallback: (key) {
                        final index = widget.groups
                            .indexWhere((group) => ValueKey(group.name) == key);
                        return index < 0 ? null : index;
                      },
                      itemBuilder: (context, index) {
                        final group = widget.groups[index];
                        return Padding(
                          key: ValueKey(group.name),
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _buildSourceGroup(group),
                        );
                      },
                    ),
                  ),
                  const SliverToBoxAdapter(
                    child: SafeArea(top: false, child: SizedBox(height: 24)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSourceGroup(_SourceSearchGroup group) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final display = _display[group.name] ?? _SourceDisplay.collapsed;
    final collapsed = display == _SourceDisplay.collapsed;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : splitListMotionDuration;

    void toggle() => _setDisplay(group.name,
        collapsed ? _SourceDisplay.preview : _SourceDisplay.collapsed);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KeyedSubtree(
          key: _headerKeys.putIfAbsent(group.name, GlobalKey.new),
          child: Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  button: true,
                  expanded: !collapsed,
                  label: '来源规则：${group.name}，${group.statusLabel}',
                  onTap: toggle,
                  excludeSemantics: true,
                  child: Material(
                    type: MaterialType.transparency,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: toggle,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 48),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                          child: Row(
                            children: [
                              Expanded(
                                  child: Text(
                                group.name,
                                style: theme.textTheme.labelLarge?.copyWith(
                                  color: colors.onSurfaceVariant,
                                ),
                              )),
                              const SizedBox(width: 8),
                              Text(
                                group.statusLabel,
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(width: 8),
                              AnimatedRotation(
                                turns: collapsed ? 0 : 0.5,
                                duration: duration,
                                curve: splitListMotionCurve,
                                child: Icon(AnikumoIcons.expand_more_rounded,
                                    size: 20, color: colors.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              _buildSourceMenu(group),
            ],
          ),
        ),
        if (!collapsed && group.keyword != widget.keyword)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Text(
              '检索词：${group.keyword}',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: colors.onSurfaceVariant),
            ),
          ),
        _animateSize(
          collapsed
              ? const SizedBox.shrink()
              : _buildSourceBody(group,
                  showAll: display == _SourceDisplay.expanded),
        ),
      ],
    );
  }

  Widget _buildSourceBody(_SourceSearchGroup group, {required bool showAll}) {
    if (!group.hasResults) {
      return SplitListRow(
        topRadius: splitListOuterRadius,
        bottomRadius: splitListOuterRadius,
        child: switch (group.status) {
          PluginSearchStatus.pending => _buildSearching(),
          PluginSearchStatus.success ||
          PluginSearchStatus.noResult =>
            GeneralEmptyState(
              icon: AnikumoIcons.search_off_rounded,
              title: '没有找到匹配结果',
              compact: true,
              actions: [
                StateActionButton.tonal(
                  onPressed: () => widget.onSourceSearch(group.name),
                  text: '修改检索词',
                ),
                TextButton(
                  onPressed: () => widget.onSourceAliasSearch(group.name),
                  child: const Text('使用别名'),
                ),
              ],
            ),
          PluginSearchStatus.captcha =>
            _buildSourceIssue(group.name, requiresVerification: true),
          PluginSearchStatus.error ||
          PluginSearchStatus.circuitOpen ||
          PluginSearchStatus.timeout =>
            _buildSourceIssue(group.name, requiresVerification: false),
        },
      );
    }

    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final visibleCount = showAll ? group.results.length : 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < visibleCount; index++) ...[
          if (index > 0) const SizedBox(height: splitListRowGap),
          _buildResult(group, index),
        ],
        if (group.results.length > 1) ...[
          const SizedBox(height: splitListRowGap),
          SplitListRow(
            bottomRadius: splitListOuterRadius,
            onTap: () => showAll
                ? _collapseFromFooter(group.name)
                : _setDisplay(group.name, _SourceDisplay.expanded),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        showAll ? '收起全部条目' : '展开全部 ${group.results.length} 个结果',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.labelLarge
                            ?.copyWith(color: primary),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      showAll
                          ? AnikumoIcons.unfold_less_rounded
                          : AnikumoIcons.expand_more_rounded,
                      size: 20,
                      color: primary,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSourceMenu(_SourceSearchGroup group) => TooltipVisibility(
        visible: false,
        child: AnikumoMenuButton(
          animated: true,
          builder: (context, toggle) => IconButton(
            tooltip: '${group.name} 的更多操作',
            icon: const Icon(AnikumoIcons.more_horiz_rounded, size: 20),
            onPressed: toggle,
          ),
          menuChildren: [
            AnikumoMenuItem(
              label: '修改此来源的检索词',
              onPressed: () => widget.onSourceSearch(group.name),
            ),
            AnikumoMenuItem(
              label: '使用别名检索此来源',
              onPressed: () => widget.onSourceAliasSearch(group.name),
            ),
            AnikumoMenuItem(
              label: '重新检索此来源',
              onPressed: () => widget.onRetry(group.name),
            ),
            AnikumoMenuItem(
              label: '在浏览器中打开',
              onPressed: () => widget.onOpenBrowser(group.name),
            ),
          ],
        ),
      );

  Widget _buildResult(_SourceSearchGroup group, int index) {
    final theme = Theme.of(context);
    final result = group.results[index];
    return SplitListRow(
      topRadius: index == 0 ? splitListOuterRadius : splitListInnerRadius,
      bottomRadius: group.results.length == 1
          ? splitListOuterRadius
          : splitListInnerRadius,
      onTap: () => widget.onPlay(group.name, result),
      child: Semantics(
        button: true,
        label: '播放 ${result.name}，来源 ${group.name}',
        excludeSemantics: true,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Expanded(
                  child: Text(result.name,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.onSurface,
                      )),
                ),
                const SizedBox(width: 16),
                Icon(AnikumoIcons.play_arrow_rounded,
                    color: theme.colorScheme.primary),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearching() => ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 64),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              const LoadingIndicator(size: 20, semanticsLabel: '正在检索'),
              const SizedBox(width: 12),
              Expanded(
                  child: Text('正在检索…',
                      style: Theme.of(context).textTheme.bodyMedium)),
            ],
          ),
        ),
      );

  Widget _buildSourceIssue(String sourceName,
      {required bool requiresVerification}) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final (icon, title, hint, action, onAction) = requiresVerification
        ? (
            AnikumoIcons.verified_user_outlined,
            '需要验证',
            '完成网站验证后继续检索。',
            '进行验证',
            () => widget.onVerify(sourceName),
          )
        : (
            AnikumoIcons.error_outline_rounded,
            '检索失败',
            '可以重试，或打开网站检查是否可用。',
            '重试',
            () => widget.onRetry(sourceName),
          );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  icon,
                  size: 20,
                  color: requiresVerification
                      ? colors.onSurfaceVariant
                      : colors.error,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        )),
                    const SizedBox(height: 2),
                    Text(hint,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        )),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              FilledButton.tonal(onPressed: onAction, child: Text(action)),
              TextButton(
                onPressed: () => widget.onOpenBrowser(sourceName),
                child: const Text('打开网站'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Batch 134: the brief holding view while the episode
/// picker auto-loads the remembered (or first available)
/// line. Manual source picking stays one tap away.
class _EpisodeAutoLoadView extends StatelessWidget {
  const _EpisodeAutoLoadView({
    required this.onManual,
    required this.onClose,
    this.label = '正在准备选集…',
  });

  final VoidCallback onManual;

  /// Batch 149: null when embedded in the 选集 tab (no ✕).
  final VoidCallback? onClose;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: SizedBox(
        height: 250,
        child: Column(
          children: [
            if (onClose != null)
              Row(
                children: [
                  const Spacer(),
                  IconButton(
                    icon: const Icon(AnikumoIcons.close_rounded),
                    tooltip: '关闭',
                    onPressed: onClose,
                  ),
                ],
              ),
            const SizedBox(height: 18),
            const LoadingIndicator(),
            const SizedBox(height: 16),
            Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            TextButton(
              onPressed: onManual,
              child: const Text('手动选择来源'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Batch 134: full-card placeholder for an episode card
/// whose image is missing or failed to load.
Widget _episodeImageFallback(ThemeData theme) {
  return Container(
    color: theme.colorScheme.surfaceContainerHigh,
    alignment: Alignment.center,
    child: Icon(
      AnikumoIcons.movie_outlined,
      size: 26,
      color: theme.colorScheme.onSurfaceVariant,
    ),
  );
}

/// Batch 137: the episode-first picker. The grid opens the
/// sheet — no source or line has been chosen yet — so every
/// entry is built from source-independent metadata: the
/// Bangumi title, the TMDB still when matched, and the
/// newest record's watched fill. Tapping an episode moves
/// on to choosing its source and line.
class _EpisodePickerView extends StatelessWidget {
  const _EpisodePickerView({
    required this.title,
    required this.episodeCount,
    required this.coverUrl,
    required this.episodeTitles,
    required this.stills,
    required this.watched,
    required this.onEpisode,
    required this.onClose,
  });

  final String title;
  final int episodeCount;
  final String coverUrl;
  final Map<int, String> episodeTitles;

  /// Batch 129: TMDB stills by episode number (may be empty).
  final Map<int, TmdbEpisodeStill> stills;

  /// Batch 134/137: watched durations by episode number from
  /// the newest history record (empty when never watched).
  final Map<int, Duration> watched;
  final ValueChanged<int> onEpisode;

  /// Batch 149: null when embedded in the 选集 tab (no ✕).
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 4, 0),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        '共 $episodeCount 集 · 先选集，再选线路',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (onClose != null)
                  IconButton(
                    icon: const Icon(AnikumoIcons.close_rounded),
                    tooltip: '关闭',
                    onPressed: onClose,
                  ),
              ],
            ),
          ),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 2.35,
              ),
              itemCount: episodeCount,
              itemBuilder: (context, index) {
                final episode = index + 1;
                // Batch 129: a TMDB still beats the series
                // cover; the Bangumi title still beats TMDB's
                // episode name; air date rides along as a meta
                // line when TMDB has it.
                final still = stills[episode];
                final cardImage = (still != null && still.imageUrl.isNotEmpty)
                    ? still.imageUrl
                    : coverUrl;
                final subtitle = episodeTitles[episode] ??
                    (still != null && still.name.isNotEmpty
                        ? still.name
                        : '');
                // Batch 134: the runtime sits beside the
                // episode number (with the watched position);
                // the meta line keeps only the air date.
                final meta = still == null ? '' : still.airDate;
                final watchedDuration = watched[episode];
                final totalMinutes = still?.runtimeMinutes ?? 0;
                final fraction = watchedDuration == null
                    ? 0.0
                    : watchFraction(watchedDuration, totalMinutes);
                final durationLabel = episodeDurationLabel(
                  watched: watchedDuration,
                  totalMinutes: totalMinutes,
                );
                final isWatched = watchedDuration != null;
                return Material(
                  color: theme.colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => onEpisode(episode),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          // Batch 134 (user revision): the
                          // episode image fills the whole card
                          // as its background.
                          if (cardImage.isNotEmpty)
                            CachedNetworkImage(
                              imageUrl: cardImage,
                              fit: BoxFit.cover,
                              fadeInDuration: Duration.zero,
                              fadeOutDuration: Duration.zero,
                              errorWidget: (context, _, _) =>
                                  _episodeImageFallback(theme),
                            )
                          else
                            _episodeImageFallback(theme),
                          // Scrim so the text stays readable
                          // over any still.
                          const DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.black38,
                                  Colors.transparent,
                                  Colors.black87,
                                ],
                                stops: [0, 0.45, 1],
                              ),
                            ),
                          ),
                          // Batch 134: watched episodes carry a
                          // grey sweep over the image, in from
                          // the left as far as the watched share
                          // of the runtime reaches.
                          if (fraction > 0)
                            Align(
                              alignment: Alignment.centerLeft,
                              child: FractionallySizedBox(
                                widthFactor: fraction,
                                heightFactor: 1,
                                child: ColoredBox(
                                  color: Colors.grey.withValues(alpha: 0.45),
                                ),
                              ),
                            ),
                          Padding(
                            padding: const EdgeInsets.all(9),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      '第$episode集',
                                      style: theme.textTheme.titleSmall
                                          ?.copyWith(
                                        fontWeight: FontWeight.w700,
                                        color: isWatched
                                            ? Colors.white70
                                            : Colors.white,
                                      ),
                                    ),
                                    const Spacer(),
                                    if (durationLabel.isNotEmpty)
                                      Text(
                                        durationLabel,
                                        style: theme.textTheme.labelSmall
                                            ?.copyWith(color: Colors.white70),
                                      ),
                                  ],
                                ),
                                const Spacer(),
                                if (subtitle.isNotEmpty)
                                  Text(
                                    subtitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                if (meta.isNotEmpty)
                                  Text(
                                    meta,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.labelSmall
                                        ?.copyWith(color: Colors.white60),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Batch 137: the line step of the episode-first flow — the
/// viewer already picked the episode and a source; when that
/// source offers several lines, they pick the exact one
/// here and playback starts.
class _LineRoadsView extends StatelessWidget {
  const _LineRoadsView({
    required this.episode,
    required this.pluginName,
    required this.roads,
    required this.onRoad,
    required this.onBack,
    required this.onClose,
  });

  final int episode;
  final String pluginName;
  final List<Road> roads;
  final ValueChanged<int> onRoad;
  final VoidCallback onBack;

  /// Batch 149: null when embedded in the 选集 tab (no ✕).
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(AnikumoIcons.arrow_back_rounded),
                  tooltip: '换个源',
                  onPressed: onBack,
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '第$episode集',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        '$pluginName · 选择线路',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (onClose != null)
                  IconButton(
                    icon: const Icon(AnikumoIcons.close_rounded),
                    tooltip: '关闭',
                    onPressed: onClose,
                  ),
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              itemCount: roads.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final road = roads[index];
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  leading: const Icon(AnikumoIcons.play_circle_outline_rounded),
                  title: Text(road.name),
                  subtitle: Text('${road.data.length} 集'),
                  trailing: const Icon(AnikumoIcons.chevron_right_rounded),
                  onTap: () => onRoad(index),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
