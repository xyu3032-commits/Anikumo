import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:anikumo/services/storage/storage.dart';
import 'package:flutter/services.dart';
import 'package:anikumo/bean/dialog/dialog_helper.dart';
import 'package:anikumo/bean/widget/channel_glyphs.dart';
import 'package:anikumo/bean/widget/zone_switcher.dart';
import 'package:anikumo/services/ui/glass_style.dart';
import 'package:anikumo/bean/widget/embedded_native_control_area.dart';
import 'package:anikumo/navigation.dart';
import 'package:anikumo/pages/menu/route_visibility.dart';
import 'package:anikumo/pages/router.dart';
import 'package:anikumo/utils/device.dart';
import 'package:anikumo/services/platform/desktop_window_config.dart';
import 'package:window_manager/window_manager.dart';
import 'package:anikumo/bean/appbar/drag_to_move_bar.dart' as dtb;
import 'package:anikumo/bean/widget/anikumo_icons.dart';

class ScaffoldMenu extends StatefulWidget {
  const ScaffoldMenu({super.key, required this.location});

  final String location;

  @override
  State<ScaffoldMenu> createState() => _ScaffoldMenu();
}

/// Batch 44: the shell's channels, editorial style —
/// Batch 55: 工具箱 moved into Settings — seven channels.
/// Batch 62 (appendix): the glyphs are Anikumo's own
/// cat-ear set (bean/widget/channel_glyphs.dart), drawn
/// for this app — outline / filled pairs like the stock
/// Material icons they replace.
const _channels = <(String, String, String)>[
  ('推荐', ChannelGlyphs.homeOutline, ChannelGlyphs.homeFilled),
  ('精选', ChannelGlyphs.featuredOutline, ChannelGlyphs.featuredFilled),
  ('发现', ChannelGlyphs.discoverOutline, ChannelGlyphs.discoverFilled),
  ('时光', ChannelGlyphs.momentsOutline, ChannelGlyphs.momentsFilled),
  ('时间表', ChannelGlyphs.scheduleOutline, ChannelGlyphs.scheduleFilled),
  ('追番', ChannelGlyphs.followingOutline, ChannelGlyphs.followingFilled),
  ('我的', ChannelGlyphs.mineOutline, ChannelGlyphs.mineFilled),
];

class _ScaffoldMenu extends State<ScaffoldMenu> with RouteAware {
  final _outletKey = GlobalKey<RouterOutletState>();
  final _channelRailController = ScrollController();
  late int _selectedIndex = menu.indexForPath(widget.location);

  @override
  void initState() {
    super.initState();
    // Batch 15 (G3): default start tab — applied once, only when
    // the shell opens on its home location.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      // Batch 37: one-time remap of the stored start tab.
      // The shell inserted 工具箱（3) / 时光（4) after 发现， so
      // pre-37 values shift: 时间表 3->5, 追番 4->6, 我的 5->7,
      // 漫画 6->8. Values 0-2 are unchanged.
      if (!GStorage.getSetting(SettingsKeys.navTabsV2Migrated)) {
        final old = GStorage.getSetting(SettingsKeys.startTabIndex);
        const remap = {3: 5, 4: 6, 5: 7, 6: 8};
        if (remap.containsKey(old)) {
          await GStorage.putSetting(SettingsKeys.startTabIndex, remap[old]);
        }
        await GStorage.putSetting(SettingsKeys.navTabsV2Migrated, true);
      }
      // Batch 55: one-time remap after 工具箱 left the shell
      // for Settings. Old indices: 工具箱 3 -> 发现 2,
      // 时光 4->3, 时间表 5->4, 追番 6->5, 我的 7->6,
      // 漫画 8->7.
      if (!GStorage.getSetting(SettingsKeys.navTabsV3Migrated)) {
        final old = GStorage.getSetting(SettingsKeys.startTabIndex);
        const remap = {3: 2, 4: 3, 5: 4, 6: 5, 7: 6, 8: 7};
        if (remap.containsKey(old)) {
          await GStorage.putSetting(SettingsKeys.startTabIndex, remap[old]);
        }
        await GStorage.putSetting(SettingsKeys.navTabsV3Migrated, true);
      }
      if (!mounted) return;
      final start = GStorage.getSetting(SettingsKeys.startTabIndex);
      if (start == 7) {
        context.pushNamed('/manga/');
      } else if (start > 0 && start < 7 && _selectedIndex == 0) {
        _selectDestination(start);
      }
    });
  }
  DateTime? _lastExitPromptAt;

  /// The shell sits at the bottom of the root stack and stays mounted while
  /// other pages cover it, so it publishes that state for its subtree.
  bool _isCovered = false;

  @override
  void didUpdateWidget(covariant ScaffoldMenu oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.location != widget.location) {
      _selectedIndex = menu.indexForPath(widget.location);
      _scrollChannelIntoView(_selectedIndex);
    }
  }

  void _scrollChannelIntoView(int index) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_channelRailController.hasClients) return;
      final target = (index * 78.0 - 120).clamp(
        0.0,
        _channelRailController.position.maxScrollExtent,
      );
      _channelRailController.animateTo(
        target,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute<void>) {
      rootRouteObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    _channelRailController.dispose();
    rootRouteObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  void didPushNext() => _setCovered(true);

  @override
  void didPopNext() => _setCovered(false);

  void _setCovered(bool value) {
    if (!mounted || _isCovered == value) {
      return;
    }
    setState(() => _isCovered = value);
  }

  void _selectDestination(int index) {
    _lastExitPromptAt = null;
    if (index == _selectedIndex) {
      return;
    }
    final outlet = _outletKey.currentState;
    if (outlet == null) return;
    // Batch 21: tactile confirmation on tab switches.
    HapticFeedback.selectionClick();
    outlet.navigate('/tab${menu.getPath(index)}/');
    setState(() => _selectedIndex = index);
    _scrollChannelIntoView(index);
  }

  void _handleSystemBack(BuildContext context) {
    if (_outletKey.currentState?.maybePop() ?? false) {
      _lastExitPromptAt = null;
      return;
    }

    if (_selectedIndex != 0) {
      _selectDestination(0);
      return;
    }

    final now = DateTime.now();
    final lastPromptAt = _lastExitPromptAt;
    if (lastPromptAt == null ||
        now.difference(lastPromptAt) > const Duration(seconds: 2)) {
      _lastExitPromptAt = now;
      AnikumoDialog.showToast(message: '再按一次退出应用', context: context);
      return;
    }

    _lastExitPromptAt = null;
    SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    return RouteVisibility(
      isCovered: _isCovered,
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) {
            _handleSystemBack(context);
          }
        },
        child: OrientationBuilder(
          builder: (context, orientation) {
            return orientation == Orientation.portrait
                ? _portraitMenu(context, _selectedIndex)
                : _sideMenu(context, _selectedIndex);
          },
        ),
      ),
    );
  }

  Widget _outlet(BuildContext context, {BorderRadius? borderRadius}) {
    Widget child = NotificationListener<NavigationNotification>(
      // A non-poppable outlet must not override the shell's PopScope state.
      onNotification: (notification) => !notification.canHandlePop,
      child: RouterOutlet(key: _outletKey),
    );
    if (borderRadius != null) {
      child = ClipRRect(borderRadius: borderRadius, child: child);
    }
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: borderRadius,
      ),
      child: child,
    );
  }

  // Batch 44 shell: the bottom capsule bar is gone. The
  // shell is now a masthead （刊头） + a numbered channel
  // rail on top; content gets the full remaining height.
  // Glass style now frosts the masthead instead of the bar.
  Widget _portraitMenu(BuildContext context, int selectedIndex) {
    return Scaffold(
      body: Column(
        children: [
          _masthead(context, selectedIndex),
          Expanded(child: _outlet(context)),
        ],
      ),
    );
  }

  Widget _masthead(BuildContext context, int selectedIndex) {
    return ValueListenableBuilder<int>(
      valueListenable: GlassStyle.levelNotifier,
      builder: (context, level, _) {
        final glass = GlassStyle.isEnabled;
        final scheme = Theme.of(context).colorScheme;
        final theme = Theme.of(context);
        Widget header = Container(
          decoration: BoxDecoration(
            color: glass
                ? scheme.surface.withValues(
                    alpha: GlassStyle.navFillOpacity,
                  )
                : scheme.surface,
            border: Border(
              bottom: BorderSide(
                color: scheme.outlineVariant.withValues(alpha: 0.7),
              ),
            ),
          ),
          child: SafeArea(
            bottom: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 8, 2),
                  child: dtb.DragToMoveArea(
                    child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(7),
                        child: Image.asset(
                          'assets/images/logo/logo_rounded.png',
                          width: 27,
                          height: 27,
                          fit: BoxFit.cover,
                        ),
                      ),
                      const SizedBox(width: 9),
                      Text(
                        'Anikumo',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2.5,
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Batch 131 (user correction): the zone
                      // switcher entry is the ANIME mark itself,
                      // not the Anikumo wordmark — tapping it
                      // spins the zone wheel.
                      const ZoneWheelChip(
                        current: AppZone.anime,
                        english: true,
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: '搜索',
                        onPressed: () => context.pushNamed('/search/'),
                        icon: const Icon(AnikumoIcons.search),
                      ),
                      IconButton(
                        tooltip: '历史记录',
                        onPressed: () =>
                            context.pushNamed('/settings/history/'),
                        icon: const Icon(AnikumoIcons.history),
                      ),
                        if (isDesktop() &&
                            !DesktopWindowConfig.showWindowButton)
                          IconButton(
                            tooltip: '退出',
                            onPressed: () => windowManager.close(),
                            icon: const Icon(AnikumoIcons.close),
                          ),
                      ],
                    ),
                  ),
                ),
                _channelRail(context, selectedIndex),
              ],
            ),
          ),
        );
        // Batch 47: the masthead no longer wraps a live
        // BackdropFilter (style + smoothness: the frosted
        // look is the translucent fill alone now).
        return header;
      },
    );
  }

  Widget _channelRail(BuildContext context, int selectedIndex) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SizedBox(
      height: 56,
      child: ListView.builder(
        controller: _channelRailController,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: _channels.length,
        itemBuilder: (context, index) {
          final (label, icon, selectedIcon) = _channels[index];
          final selected = index == selectedIndex;
          return InkWell(
            onTap: () => _selectDestination(index),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 13),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        (index + 1).toString().padLeft(2, '0'),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color:
                              selected ? scheme.primary : scheme.outline,
                          fontWeight: FontWeight.w800,
                          fontSize: 10,
                        ),
                      ),
                      const SizedBox(width: 5),
                      ChannelGlyph(
                        svg: selected ? selectedIcon : icon,
                        size: 15,
                        color: selected
                            ? scheme.onSurface
                            : scheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight:
                          selected ? FontWeight.w800 : FontWeight.w500,
                      color: selected
                          ? scheme.onSurface
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    height: 3,
                    width: selected ? 30 : 0,
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // Batch 44: landscape keeps a left rail, but it speaks
  // the same editorial language as the portrait channel
  // rail — numbered channels down a hairline, not the
  // stock Material rail.
  Widget _sideMenu(BuildContext context, int selectedIndex) {
    const borderRadius = BorderRadius.only(
      topLeft: Radius.circular(16),
      bottomLeft: Radius.circular(16),
    );
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      backgroundColor: scheme.surfaceContainer,
      body: Row(
        children: [
          EmbeddedNativeControlArea(
            child: Container(
              width: 92,
              color: scheme.surfaceContainer,
              child: SafeArea(
                right: false,
                child: Column(
                  children: [
                    const SizedBox(height: 14),
                    // Batch 131: zone wheel entry on the rail too.
                    const ZoneWheelChip(
                      current: AppZone.anime,
                      english: true,
                    ),
                    const SizedBox(height: 12),
                    FloatingActionButton.small(
                      elevation: 0,
                      heroTag: null,
                      onPressed: () => context.pushNamed('/search/'),
                      child: const Icon(AnikumoIcons.search),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: ListView.builder(
                        itemCount: _channels.length,
                        itemBuilder: (context, index) {
                          final (label, icon, selectedIcon) =
                              _channels[index];
                          final selected = index == selectedIndex;
                          return InkWell(
                            onTap: () => _selectDestination(index),
                            child: Container(
                              decoration: BoxDecoration(
                                border: Border(
                                  left: BorderSide(
                                    color: selected
                                        ? scheme.primary
                                        : Colors.transparent,
                                    width: 3,
                                  ),
                                ),
                              ),
                              padding: const EdgeInsets.symmetric(
                                vertical: 9,
                              ),
                              child: Column(
                                children: [
                                  Text(
                                    (index + 1)
                                        .toString()
                                        .padLeft(2, '0'),
                                    style:
                                        theme.textTheme.labelSmall?.copyWith(
                                      color: selected
                                          ? scheme.primary
                                          : scheme.outline,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 9,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  ChannelGlyph(
                                    svg: selected ? selectedIcon : icon,
                                    size: 21,
                                    color: selected
                                        ? scheme.onSurface
                                        : scheme.onSurfaceVariant,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    label,
                                    style: theme.textTheme.labelMedium
                                        ?.copyWith(
                                      fontWeight: selected
                                          ? FontWeight.w800
                                          : FontWeight.w500,
                                      color: selected
                                          ? scheme.onSurface
                                          : scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(child: _outlet(context, borderRadius: borderRadius)),
        ],
      ),
    );
  }
}
