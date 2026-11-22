import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:scrollview_observer/scrollview_observer.dart';

import 'package:anikumo/bean/widget/empty_state_widget.dart';
import 'package:anikumo/modules/download/download_module.dart';
import 'package:anikumo/modules/roads/road_module.dart';
import 'package:anikumo/bean/widget/anikumo_icons.dart';
import 'package:anikumo/services/i18n/app_strings.dart';

class EpisodeSelectionPanel extends StatefulWidget {
  const EpisodeSelectionPanel({
    super.key,
    required this.title,
    required this.roads,
    required this.selectedRoad,
    required this.selectedEpisode,
    required this.onEpisodeSelected,
    required this.downloads,
    this.onDownload,
    this.onAddToQueue,
    this.isOffline = false,
    this.isPlaying = false,
    this.disableAnimations = false,
  });

  final String title;
  final List<Road> roads;
  final int selectedRoad;
  final int selectedEpisode;
  final void Function(int episode, int road) onEpisodeSelected;
  final ValueChanged<int>? onDownload;

  /// Batch 277 (#1): per-episode "add to play queue"
  /// action. Null hides the button (offline / external
  /// sessions cannot resolve queue entries later).
  final void Function(int episode, int road)? onAddToQueue;
  final Map<String, DownloadEpisode> downloads;
  final bool isOffline;
  final bool isPlaying;
  final bool disableAnimations;

  @override
  EpisodeSelectionPanelState createState() => EpisodeSelectionPanelState();
}

class EpisodeSelectionPanelState extends State<EpisodeSelectionPanel> {
  final _scrollController = ScrollController();
  late final _observerController =
      ListObserverController(controller: _scrollController)
        ..cacheJumpIndexOffset = false;
  late int _visibleRoad = widget.selectedRoad;

  bool get _canLocate =>
      widget.selectedRoad >= 0 &&
      widget.selectedRoad < widget.roads.length &&
      widget.selectedEpisode > 0 &&
      widget.selectedEpisode <= widget.roads[widget.selectedRoad].data.length;

  double get _toolbarHeight =>
      math.max(56, MediaQuery.textScalerOf(context).scale(20) + 8);

  void _selectRoad(int road) {
    if (_visibleRoad == road) return;
    setState(() => _visibleRoad = road);
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
  }

  Future<void> revealCurrentEpisode() async {
    if (!_canLocate) return;
    setState(() => _visibleRoad = widget.selectedRoad);
    // Wait for the observer to bind the new road's sliver after layout.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted ||
        !_scrollController.hasClients ||
        !_canLocate ||
        _visibleRoad != widget.selectedRoad) {
      return;
    }

    final index = widget.selectedEpisode - 1;
    final toolbarHeight = _toolbarHeight;
    final item = _observerController.observeItem(index: index);
    if (item != null) {
      final top = item.renderObject
          .localToGlobal(Offset.zero, ancestor: item.viewport)
          .dy;
      if (top >= toolbarHeight &&
          top + item.renderObject.size.height <= item.viewport.size.height) {
        return;
      }
    }
    await _observerController.jumpTo(
      index: index,
      offset: (_) => toolbarHeight,
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final road = _visibleRoad >= 0 && _visibleRoad < widget.roads.length
        ? widget.roads[_visibleRoad]
        : null;
    final count = road?.data.length ?? 0;

    return LayoutBuilder(builder: (context, constraints) {
      final textScaler = MediaQuery.textScalerOf(context);
      return ListViewObserver(
        controller: _observerController,
        child: Scrollbar(
          controller: _scrollController,
          child: CustomScrollView(
            controller: _scrollController,
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Semantics(
                        header: true,
                        child: Text(
                          widget.title.isEmpty ? S.t('剧集列表') : widget.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: colors.onSurface,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      _RoadSelector(
                        roads: widget.roads,
                        visibleRoad: _visibleRoad,
                        isOffline: widget.isOffline,
                        onChanged: _selectRoad,
                        disableAnimations: widget.disableAnimations,
                      ),
                    ],
                  ),
                ),
              ),
              SliverPersistentHeader(
                pinned: true,
                delegate: _EpisodeToolbar(
                  height: _toolbarHeight,
                  color: colors.surface,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            textScaler.scale(14) > 21 ||
                                    constraints.maxWidth < 320
                                ? S.f('{} 集', [count])
                                : widget.isOffline
                                    ? S.f('已缓存 · {} 集', [count])
                                    : S.f('全部剧集 · {} 集', [count]),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: S.t('定位当前集'),
                          onPressed: _canLocate ? revealCurrentEpisode : null,
                          icon: const Icon(AnikumoIcons.my_location_rounded, size: 20),
                        ),
                        if (!widget.isOffline)
                          IconButton.filledTonal(
                            tooltip: S.t('缓存剧集'),
                            onPressed: count > 0 && widget.onDownload != null
                                ? () => widget.onDownload!(_visibleRoad)
                                : null,
                            icon: const Icon(AnikumoIcons.download_rounded, size: 20),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              if (count == 0)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: GeneralEmptyState(
                    icon: AnikumoIcons.video_library_outlined,
                    title: S.t('这条线路暂无剧集'),
                  ),
                )
              else
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    0,
                    16,
                    16 + MediaQuery.paddingOf(context).bottom,
                  ),
                  sliver: SliverList.builder(
                    itemCount: count,
                    itemBuilder: (context, index) {
                      final episode = index + 1;
                      final name = index < road!.identifier.length &&
                              road.identifier[index].trim().isNotEmpty
                          ? road.identifier[index]
                          : S.f('第{}集', [episode]);
                      return _EpisodeRow(
                        key: ValueKey('$_visibleRoad:$episode'),
                        name: name,
                        first: index == 0,
                        last: index == count - 1,
                        selected: _visibleRoad == widget.selectedRoad &&
                            episode == widget.selectedEpisode,
                        isPlaying: widget.isPlaying,
                        isOffline: widget.isOffline,
                        download: widget.downloads[road.data[index]],
                        disableAnimations: widget.disableAnimations,
                        onTap: () =>
                            widget.onEpisodeSelected(episode, _visibleRoad),
                        onQueue: widget.onAddToQueue == null
                            ? null
                            : () => widget.onAddToQueue!(
                                  episode,
                                  _visibleRoad,
                                ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      );
    });
  }
}

class _EpisodeToolbar extends SliverPersistentHeaderDelegate {
  const _EpisodeToolbar({
    required this.height,
    required this.color,
    required this.child,
  });

  final double height;
  final Color color;
  final Widget child;

  @override
  double get minExtent => height;

  @override
  double get maxExtent => minExtent;

  @override
  Widget build(
          BuildContext context, double shrinkOffset, bool overlapsContent) =>
      // Fill minExtent even when desktop controls use a smaller touch target.
      SizedBox.expand(child: ColoredBox(color: color, child: child));

  @override
  bool shouldRebuild(covariant _EpisodeToolbar oldDelegate) =>
      height != oldDelegate.height ||
      color != oldDelegate.color ||
      child != oldDelegate.child;
}

class _RoadSelector extends StatefulWidget {
  const _RoadSelector({
    required this.roads,
    required this.visibleRoad,
    required this.isOffline,
    required this.onChanged,
    required this.disableAnimations,
  });

  final List<Road> roads;
  final int visibleRoad;
  final bool isOffline;
  final ValueChanged<int> onChanged;
  final bool disableAnimations;

  @override
  State<_RoadSelector> createState() => _RoadSelectorState();
}

class _RoadSelectorState extends State<_RoadSelector> {
  final _focusNode = FocusNode(debugLabel: 'Playback road selector');
  FocusNode? _focusBeforeOpen;
  bool _pointerActivation = false;

  String _name(int index) => index >= 0 && index < widget.roads.length
      ? (widget.roads[index].name.trim().isEmpty
          ? S.f('播放线路 {}', [index + 1])
          : widget.roads[index].name)
      : S.t('暂无线路');

  void _toggleMenu(MenuController controller) {
    final pointerActivation = _pointerActivation;
    _pointerActivation = false;
    if (controller.isOpen) {
      controller.close();
      return;
    }
    final previousFocus = FocusManager.instance.primaryFocus;
    _focusBeforeOpen =
        pointerActivation && previousFocus == _focusNode ? null : previousFocus;
    controller.open();
  }

  void _handleClose() {
    if (!mounted) return;
    final previousFocus = _focusBeforeOpen;
    _focusBeforeOpen = null;
    if (previousFocus == null ||
        previousFocus.context?.mounted != true ||
        !previousFocus.canRequestFocus) {
      _focusNode.unfocus(
          disposition: UnfocusDisposition.previouslyFocusedChild);
      return;
    }
    if (previousFocus is FocusScopeNode) {
      // Do not restore the scope's last child: it may be this menu button.
      previousFocus.requestScopeFocus();
    } else {
      previousFocus.requestFocus();
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  Widget _buildMenuItem(int index, double width) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final road = widget.roads[index];
    final selected = index == widget.visibleRoad;
    final last = index == widget.roads.length - 1;
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : 2),
      child: Semantics(
        selected: selected,
        inMutuallyExclusiveGroup: true,
        child: MenuItemButton(
          key: ValueKey('road-option-$index'),
          onPressed: () => widget.onChanged(index),
          style: ButtonStyle(
            minimumSize: WidgetStatePropertyAll(Size(width, 56)),
            padding: const WidgetStatePropertyAll(
                EdgeInsets.symmetric(horizontal: 16, vertical: 12)),
            visualDensity: VisualDensity.standard,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            backgroundColor: WidgetStatePropertyAll(
              selected ? colors.secondaryContainer : colors.surfaceContainerLow,
            ),
            foregroundColor: WidgetStatePropertyAll(
              selected ? colors.onSecondaryContainer : colors.onSurface,
            ),
            textStyle: WidgetStatePropertyAll(
              theme.textTheme.labelLarge?.copyWith(
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
            shape: WidgetStatePropertyAll(RoundedRectangleBorder(
              borderRadius: selected
                  ? BorderRadius.circular(20)
                  : BorderRadius.vertical(
                      top: Radius.circular(index == 0 ? 20 : 4),
                      bottom: Radius.circular(last ? 20 : 4),
                    ),
            )),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_name(index), maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 4),
              Text(
                S.f('{} 集', [road.data.length]),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: selected
                      ? colors.onSecondaryContainer
                      : colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final canSwitch = widget.roads.length > 1;
    final reduceMotion =
        widget.disableAnimations || MediaQuery.disableAnimationsOf(context);
    final duration =
        reduceMotion ? Duration.zero : const Duration(milliseconds: 200);

    return LayoutBuilder(builder: (context, constraints) {
      final width =
          math.min(constraints.maxWidth, MediaQuery.sizeOf(context).width - 32);
      return MenuAnchor(
        childFocusNode: _focusNode,
        crossAxisUnconstrained: false,
        consumeOutsideTap: true,
        animated: !reduceMotion,
        onClose: _handleClose,
        alignmentOffset: const Offset(0, 8),
        style: MenuStyle(
          alignment: AlignmentDirectional.bottomStart,
          backgroundColor: WidgetStatePropertyAll(colors.surfaceContainer),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          elevation: const WidgetStatePropertyAll(3),
          padding: const WidgetStatePropertyAll(EdgeInsets.all(8)),
          shape: WidgetStatePropertyAll(RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          )),
          minimumSize: WidgetStatePropertyAll(Size(width, 0)),
          maximumSize: WidgetStatePropertyAll(Size(
              width, math.min(400, MediaQuery.sizeOf(context).height - 32))),
          visualDensity: VisualDensity.standard,
        ),
        menuChildren: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Text(
              S.t('选择播放线路'),
              style: theme.textTheme.labelLarge?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
          for (var i = 0; i < widget.roads.length; i++)
            _buildMenuItem(i, width - 16),
        ],
        builder: (context, controller, child) {
          final open = controller.isOpen;
          final foreground =
              open ? colors.onSecondaryContainer : colors.onSurface;
          return Semantics(
            button: canSwitch,
            expanded: canSwitch ? open : null,
            label: canSwitch ? S.t('切换播放线路') : null,
            child: Material(
              animationDuration: duration,
              color:
                  open ? colors.secondaryContainer : colors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(open ? 16 : 20),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                focusNode: _focusNode,
                onTapUp: canSwitch ? (_) => _pointerActivation = true : null,
                onTap: canSwitch ? () => _toggleMenu(controller) : null,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.isOffline ? S.t('离线观看') : S.t('播放线路'),
                              style: theme.textTheme.labelMedium
                                  ?.copyWith(color: foreground),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _name(widget.visibleRoad),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: foreground,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (canSwitch) ...[
                        const SizedBox(width: 8),
                        AnimatedRotation(
                          turns: open ? 0.5 : 0,
                          duration: duration,
                          curve: Curves.easeOutCubic,
                          child: Icon(AnikumoIcons.keyboard_arrow_down_rounded,
                              color: foreground),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      );
    });
  }
}

class _EpisodeRow extends StatefulWidget {
  const _EpisodeRow({
    super.key,
    required this.name,
    required this.first,
    required this.last,
    required this.selected,
    required this.isPlaying,
    required this.isOffline,
    required this.disableAnimations,
    required this.onTap,
    this.download,
    this.onQueue,
  });

  final String name;
  final bool first;
  final bool last;
  final bool selected;
  final bool isPlaying;
  final bool isOffline;
  final bool disableAnimations;
  final VoidCallback onTap;
  final DownloadEpisode? download;

  /// Batch 277 (#1): queue-this-episode action; null
  /// hides the button.
  final VoidCallback? onQueue;

  @override
  State<_EpisodeRow> createState() => _EpisodeRowState();
}

class _EpisodeRowState extends State<_EpisodeRow>
    with SingleTickerProviderStateMixin {
  late final _press = AnimationController.unbounded(vsync: this);

  bool get _reduceMotion =>
      widget.disableAnimations || MediaQuery.disableAnimationsOf(context);

  void _setPressed(bool pressed) {
    final target = pressed ? 1.0 : 0.0;
    if (_reduceMotion) {
      _press.value = target;
      return;
    }
    _press.animateWith(SpringSimulation(
      SpringDescription.withDampingRatio(
        mass: 1,
        stiffness: 500,
        ratio: 0.8,
      ),
      _press.value,
      target,
      _press.velocity,
    ));
  }

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final foreground = widget.selected ? colors.onPrimary : colors.onSurface;
    final status =
        widget.isOffline ? DownloadStatus.completed : widget.download?.status;
    final downloadLabel = switch (status) {
      DownloadStatus.completed => S.t('已缓存'),
      DownloadStatus.downloading => S.t('正在缓存'),
      DownloadStatus.failed => S.t('缓存失败'),
      DownloadStatus.paused => S.t('缓存已暂停'),
      DownloadStatus.pending => S.t('等待缓存'),
      DownloadStatus.resolving => S.t('正在解析'),
      _ => null,
    };
    final playbackLabel =
        widget.selected ? (widget.isPlaying ? S.t('正在播放') : S.t('当前选集')) : S.t('播放');

    final supportingText = [
      if (widget.selected) playbackLabel,
      if (!widget.isOffline && downloadLabel != null)
        status == DownloadStatus.downloading
            ? S.f('缓存 {}%', [(widget.download!.progressPercent.clamp(0, 1) * 100).round()])
            : downloadLabel,
    ].join(' · ');

    return Semantics(
      button: true,
      onTap: widget.onTap,
      selected: widget.selected,
      inMutuallyExclusiveGroup: true,
      label: '${widget.name}，$playbackLabel'
          '${downloadLabel == null ? '' : '，$downloadLabel'}',
      child: Tooltip(
        message: '${widget.name} · $playbackLabel'
            '${downloadLabel == null ? '' : ' · $downloadLabel'}',
        excludeFromSemantics: true,
        child: AnimatedBuilder(
          animation: _press,
          builder: (context, child) {
            final restShape = widget.selected
                ? BorderRadius.circular(20)
                : BorderRadius.vertical(
                    top: Radius.circular(widget.first ? 20 : 4),
                    bottom: Radius.circular(widget.last ? 20 : 4),
                  );
            final press = _press.value.clamp(0.0, 1.0);
            return Padding(
              padding: EdgeInsets.only(bottom: widget.last ? 0 : 2),
              child: Material(
                animationDuration: _reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 200),
                color: widget.selected
                    ? colors.primary
                    : colors.surfaceContainerLow,
                borderRadius: BorderRadius.lerp(
                    restShape, BorderRadius.circular(12), press),
                clipBehavior: Clip.antiAlias,
                child: child,
              ),
            );
          },
          child: InkWell(
            onTap: widget.onTap,
            onHighlightChanged: _setPressed,
            excludeFromSemantics: true,
            overlayColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.pressed) ||
                  states.contains(WidgetState.focused)) {
                return foreground.withValues(alpha: 0.1);
              }
              if (states.contains(WidgetState.hovered)) {
                return foreground.withValues(alpha: 0.08);
              }
              return null;
            }),
            child: ExcludeSemantics(
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 56),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyLarge?.copyWith(
                                color: foreground,
                                fontWeight: widget.selected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                            ),
                            if (supportingText.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                supportingText,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: widget.selected
                                      ? foreground
                                      : status == DownloadStatus.failed
                                          ? colors.error
                                          : colors.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (widget.onQueue != null) ...[
                        const SizedBox(width: 8),
                        IconButton(
                          tooltip: S.t('加入队列'),
                          color: foreground,
                          icon: const Icon(
                            AnikumoIcons.playlist_add_outlined,
                            size: 20,
                          ),
                          onPressed: widget.onQueue,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
