import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:anikumo/bean/widget/anikumo_icons.dart';
import 'package:anikumo/services/storage/storage.dart';

/// The zones of the app. Each zone's own name mark in its
/// home header (the masthead's ANIME label, the manga 漫画
/// chip, the novel 小说 title) opens the switcher. Batch 131
/// made it a left/right wheel; Batch 203 (user direction)
/// replaced the wheel with a pull-up panel: the panel rises
/// from the bottom, video zones （动漫/影视） grouped
/// together, and a tap jumps. Per the user's correction, the
/// entry is the zone mark, not the Anikumo wordmark or the
/// app icon.
enum AppZone {
  anime('动漫', 'ANIME', AnikumoIcons.smart_display_rounded),
  manga('漫画', 'MANGA', AnikumoIcons.auto_stories_rounded),
  novel('小说', 'NOVEL', AnikumoIcons.menu_book_rounded),
  // Batch 203: the 影视 zone (TV series & movies), powered by
  // the vendored 流光 LiuGuang engine. It is a video zone like
  // anime — the pull-up switcher groups the two together.
  video('影视', 'VIDEO', AnikumoIcons.movie_rounded);

  const AppZone(this.label, this.english, this.icon);

  final String label;
  final String english;
  final IconData icon;

  /// The pushed route that hosts this zone; the anime zone
  /// is the root shell and has none.
  String? get route => switch (this) {
        AppZone.anime => null,
        AppZone.manga => '/manga/',
        AppZone.novel => '/novel/',
        // '/film/' — plain '/video' is the anime zone's
        // player module (pages/video), taken long before
        // this zone existed.
        AppZone.video => '/film/',
      };

  /// Batch 203 (user direction): the switcher groups zones
  /// by kind — the two video zones together, the two reading
  /// zones together — in a pull-up panel instead of the old
  /// left/right wheel.
  bool get isVideoKind => this == AppZone.anime || this == AppZone.video;
}

/// The switcher panel's groups, in display order: video
/// zones first （动漫/影视）, then reading zones （漫画/小说）.
const List<(String, List<AppZone>)> zoneSwitcherGroups = [
  ('视频', [AppZone.anime, AppZone.video]),
  ('阅读', [AppZone.manga, AppZone.novel]),
];

/// The zone shown at wheel position [index]. The wheel is
/// endless in both directions, so indices run far past the
/// zone count in either direction.
AppZone zoneForWheelIndex(int index) =>
    AppZone.values[index % AppZone.values.length];

/// The wheel page the switcher opens on: a large round
/// multiple of the zone count (so the modulo mapping stays
/// aligned) plus the current zone's own offset.
int zoneWheelInitialPage(AppZone current) => 3000 + current.index;

/// Batch 240 (user direction): the switcher is no longer
/// one fixed presentation — the user picks the style in
/// 外观设置. The Batch 203 pull-up panel stays the default;
/// the Batch 131 wheel returns as an option; a flat
/// left/right slide pager, a 2×2 grid and a segmented-pill
/// layout join it. All five live in the same sheet host
/// (same drag-to-close, backdrop and jump flow); only the
/// body differs.
enum ZoneSwitcherStyle {
  panel('panel', '上拉面板', '分组列表，点按进入'),
  wheel('wheel', '圆形滚轮', '左右转动滚轮，点中间的卡片进入'),
  slide('slide', '左右滑移', '左右滑动大卡片，点中间的进入'),
  grid('grid', '四宫格', '四个大块平铺，点按进入'),
  segment('segment', '分段胶囊', '分组胶囊按钮，点按切换');

  const ZoneSwitcherStyle(this.key, this.label, this.hint);

  final String key;
  final String label;

  /// The one-line explanation shown under the sheet title
  /// and in the settings list.
  final String hint;

  static ZoneSwitcherStyle fromKey(String key) => values.firstWhere(
    (s) => s.key == key,
    orElse: () => ZoneSwitcherStyle.panel,
  );
}

/// The user's chosen switcher style. Guarded like every
/// other late storage read: an uninitialised store reads
/// as the panel default.
ZoneSwitcherStyle currentZoneSwitcherStyle() {
  try {
    return ZoneSwitcherStyle.fromKey(
      GStorage.getSetting(SettingsKeys.zoneSwitcherStyle),
    );
  } catch (_) {
    return ZoneSwitcherStyle.panel;
  }
}

Future<void> setZoneSwitcherStyle(ZoneSwitcherStyle style) =>
    GStorage.putSetting(SettingsKeys.zoneSwitcherStyle, style.key);

/// The colour a zone wears in the switcher (its card accent
/// and backdrop tint).
Color zoneAccent(AppZone zone, ColorScheme scheme) => switch (zone) {
      AppZone.anime => scheme.primary,
      AppZone.manga => scheme.tertiary,
      AppZone.novel => scheme.secondary,
      // A cinema amber the scheme doesn't carry; darker in
      // light mode so it stays legible on pale surfaces.
      AppZone.video =>
        scheme.brightness == Brightness.dark ? const Color(0xFFF2B33D) : const Color(0xFFB45309),
    };

/// Batch 140: the wheel backdrop's accent at a fractional
/// [page] — lerped between the two neighbouring zones, so
/// the background tracks the wheel continuously and already
/// wears the arriving zone's colour when it centres,
/// whether or not the viewer ends up entering it.
Color zoneWheelBackdropAccent(double page, ColorScheme scheme) {
  final lower = page.floor();
  final t = (page - lower).clamp(0.0, 1.0).toDouble();
  final a = zoneAccent(zoneForWheelIndex(lower), scheme);
  if (t == 0) return a;
  final b = zoneAccent(zoneForWheelIndex(lower + 1), scheme);
  return Color.lerp(a, b, t) ?? a;
}

/// Performs the zone jump from a page inside [from]. The
/// manga and novel zones are routes pushed over the anime
/// shell, so leaving one is a pop; entering one is a push.
void switchAppZone(BuildContext context, AppZone from, AppZone target) {
  if (target == from) return;
  if (from != AppZone.anime) {
    context.pop();
  }
  final route = target.route;
  if (route != null) {
    context.pushNamed(route);
  }
}

/// Batch 131 (user correction): the switcher entry is the
/// zone's own name mark — the masthead's ANIME label, the
/// manga header's 漫画 chip, the novel header's 小说 title —
/// not the Anikumo wordmark or the app icon. This chip is
/// that mark in the headers that have no title of their own.
class ZoneWheelChip extends StatelessWidget {
  const ZoneWheelChip({
    super.key,
    required this.current,
    this.english = false,
  });

  final AppZone current;

  /// Show the zone's English name (ANIME / MANGA / NOVEL)
  /// instead of the Chinese label — the masthead style.
  final bool english;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: '切换专区',
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () => showZoneSwitcher(context, current: current),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.9),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                english ? current.english : current.label,
                style: TextStyle(
                  fontSize: english ? 10.5 : 12.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: english ? 2.5 : 1,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 3),
              Icon(
                AnikumoIcons.unfold_more_rounded,
                size: 13,
                color: scheme.outline,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Batch 203 (user direction, replacing the Batch 131 wheel):
/// the switcher is now a pull-up panel. It rises from the
/// bottom of the screen — the two video zones （动漫/影视）
/// grouped together, then the two reading zones — and a tap
/// on a row jumps straight there; no more left/right wheel.
///
/// Animation is a first-class requirement here (the user
/// called it out explicitly), so the motion is layered:
///  * the sheet itself is drag-driven — it follows the
///    finger 1:1, and on release it either settles open or
///    dismisses by position + velocity, springing with
///    easeOutCubic; opening uses the same curve so a flick
///    and a tap feel identical;
///  * the backdrop fades in with the sheet and its tint is
///    the *current* zone's accent, cross-fading to the
///    tapped zone's accent the moment a row is chosen;
///  * rows stagger in — each group header and row rises
///    14px and fades with a 45ms-per-item delay, driven by
///    one controller so nothing rebuilds per frame;
///  * choosing a row plays a short "press" scale, closes
///    the sheet, and only then performs the zone jump, so
///    the two transitions never fight.
Future<void> showZoneSwitcher(
  BuildContext context, {
  required AppZone current,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '切换专区',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 300),
    transitionBuilder: (context, animation, _, child) => child,
    pageBuilder: (dialogContext, _, _) => _ZoneSheet(
      current: current,
      hostContext: context,
      style: currentZoneSwitcherStyle(),
    ),
  );
}

class _ZoneSheet extends StatefulWidget {
  const _ZoneSheet({
    required this.current,
    required this.hostContext,
    required this.style,
  });

  final AppZone current;

  /// Batch 240: which body the sheet hosts (see
  /// [ZoneSwitcherStyle]); the shell — drag, backdrop,
  /// close-then-jump — is shared by all five.
  final ZoneSwitcherStyle style;

  /// The page that opened the switcher. Zone navigation runs
  /// on this context after the sheet closes, because the
  /// dialog's own route is already gone by then.
  final BuildContext hostContext;

  @override
  State<_ZoneSheet> createState() => _ZoneSheetState();
}

class _ZoneSheetState extends State<_ZoneSheet>
    with SingleTickerProviderStateMixin {
  /// 0 = fully open, 1 = fully closed (translated down).
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
    value: 1,
  );

  /// Accent the backdrop wears; cross-fades to the chosen
  /// zone's accent on selection.
  late Color _backdropAccent;

  double _dragOffset = 0;
  bool _leaving = false;

  /// How far the sheet travels between closed and open, in
  /// pixels. Starts at an estimate and is corrected to the
  /// measured sheet height after the first layout (reading
  /// a render object's size during build is illegal, so the
  /// build path only ever reads this field).
  double _travel = 430;

  void _measure() {
    final size = _sheetKey.currentContext?.size;
    if (size != null && size.height > 0) _travel = size.height;
  }

  @override
  void initState() {
    super.initState();
    _ctrl.animateTo(
      0,
      duration: const Duration(milliseconds: 340),
      curve: Curves.easeOutCubic,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _backdropAccent = zoneAccent(widget.current, Theme.of(context).colorScheme);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _close() async {
    if (_leaving) return;
    _leaving = true;
    await _ctrl.animateTo(
      1,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeInCubic,
    );
    if (mounted) Navigator.of(context).pop();
  }

  void _select(AppZone zone) {
    if (_leaving) return;
    final host = widget.hostContext;
    setState(() {
      _backdropAccent = zoneAccent(zone, Theme.of(context).colorScheme);
    });
    _close().then((_) {
      if (zone != widget.current) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (host.mounted) switchAppZone(host, widget.current, zone);
        });
      }
    });
  }

  /// Batch 240: while the wheel / slide bodies turn, the
  /// backdrop tint follows the centred zone (the Batch 140
  /// behaviour, now hosted by the sheet).
  void _focusAccent(AppZone zone) {
    if (_leaving) return;
    final accent = zoneAccent(zone, Theme.of(context).colorScheme);
    if (accent != _backdropAccent) {
      setState(() => _backdropAccent = accent);
    }
  }

  String get _subtitle => switch (widget.style) {
    ZoneSwitcherStyle.panel => '点按进入 · 下拉面板关闭',
    ZoneSwitcherStyle.wheel => '左右转动滚轮 · 点中间的卡片进入',
    ZoneSwitcherStyle.slide => '左右滑动 · 点中间的卡片进入',
    ZoneSwitcherStyle.grid => '点按进入 · 下拉面板关闭',
    ZoneSwitcherStyle.segment => '点按切换 · 下拉面板关闭',
  };

  void _onDragUpdate(DragUpdateDetails d) {
    if (_leaving) return;
    _measure();
    // Finger-follow: only downward drags move the sheet; the
    // controller value maps the sheet's own height range.
    if (_travel <= 0) return;
    _dragOffset = (_dragOffset + d.delta.dy).clamp(0, _travel);
    _ctrl.value = _dragOffset / _travel;
  }

  void _onDragEnd(DragEndDetails d) {
    if (_leaving) return;
    final velocity = d.primaryVelocity ?? 0;
    final pastHalf = _travel > 0 && _dragOffset > _travel * 0.38;
    if (velocity > 550 || pastHalf) {
      _close();
    } else {
      _dragOffset = 0;
      _ctrl.animateTo(
        0,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    }
  }

  final GlobalKey _sheetKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      type: MaterialType.transparency,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          final t = _ctrl.value; // 1 closed → 0 open
          return Stack(
            children: [
              // Backdrop: tap anywhere outside dismisses.
              Positioned.fill(
                child: GestureDetector(
                  onTap: _close,
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.55 * (1 - t)),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: const Alignment(0, 0.9),
                          radius: 1.2,
                          colors: [
                            _backdropAccent.withValues(alpha: 0.22 * (1 - t)),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: Transform.translate(
                  offset: Offset(0, t * (_travel + 40)),
                  child: _sheet(theme, scheme),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _sheet(ThemeData theme, ColorScheme scheme) {
    return GestureDetector(
      key: _sheetKey,
      onVerticalDragUpdate: _onDragUpdate,
      onVerticalDragEnd: _onDragEnd,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: scheme.surfaceContainer,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 32,
              offset: const Offset(0, -8),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4.5,
                    decoration: BoxDecoration(
                      color: scheme.outlineVariant,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                _stagger(
                  0,
                  Text(
                    '切换专区',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                _stagger(
                  1,
                  Text(
                    _subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                if (widget.style == ZoneSwitcherStyle.panel) ...[
                for (var g = 0; g < zoneSwitcherGroups.length; g++) ...[
                  _stagger(
                    2 + g * 3,
                    Padding(
                      padding: const EdgeInsets.only(top: 10, bottom: 6),
                      child: Text(
                        zoneSwitcherGroups[g].$1,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: scheme.outline,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      for (var i = 0;
                          i < zoneSwitcherGroups[g].$2.length;
                          i++) ...[
                        if (i > 0) const SizedBox(width: 12),
                        Expanded(
                          child: _stagger(
                            3 + g * 3 + i,
                            _ZoneRow(
                              zone: zoneSwitcherGroups[g].$2[i],
                              isCurrent:
                                  zoneSwitcherGroups[g].$2[i] == widget.current,
                              onTap: () =>
                                  _select(zoneSwitcherGroups[g].$2[i]),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ]
                ] else if (widget.style == ZoneSwitcherStyle.wheel)
                  _stagger(
                    2,
                    _ZoneWheelBody(
                      current: widget.current,
                      onSelect: _select,
                      onFocused: _focusAccent,
                    ),
                  )
                else if (widget.style == ZoneSwitcherStyle.slide)
                  _stagger(
                    2,
                    _ZoneSlideBody(
                      current: widget.current,
                      onSelect: _select,
                      onFocused: _focusAccent,
                    ),
                  )
                else if (widget.style == ZoneSwitcherStyle.grid)
                  _stagger(
                    2,
                    _ZoneGridBody(current: widget.current, onSelect: _select),
                  )
                else
                  _stagger(
                    2,
                    _ZoneSegmentBody(
                      current: widget.current,
                      onSelect: _select,
                    ),
                  ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// One staggered entrance: item [index] rises and fades in
  /// on the shared controller, 45ms after the previous one.
  /// Driven by the same 0→1 progress as the sheet so a drag
  /// scrubs the stagger too — no extra tickers, no rebuilds
  /// beyond this AnimatedBuilder.
  Widget _stagger(int index, Widget child) {
    return AnimatedBuilder(
      animation: _ctrl,
      child: child,
      builder: (context, child) {
        // _ctrl runs 1 (closed) → 0 (open); invert to progress.
        final progress = 1 - _ctrl.value;
        final start = (index * 0.07).clamp(0.0, 0.6);
        final local =
            ((progress - start) / (1 - start)).clamp(0.0, 1.0).toDouble();
        final curved = Curves.easeOutCubic.transform(local);
        return Opacity(
          opacity: curved,
          child: Transform.translate(
            offset: Offset(0, 14 * (1 - curved)),
            child: child,
          ),
        );
      },
    );
  }
}

class _ZoneRow extends StatefulWidget {
  const _ZoneRow({
    required this.zone,
    required this.isCurrent,
    required this.onTap,
  });

  final AppZone zone;
  final bool isCurrent;
  final VoidCallback onTap;

  @override
  State<_ZoneRow> createState() => _ZoneRowState();
}

class _ZoneRowState extends State<_ZoneRow> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accent = zoneAccent(widget.zone, scheme);
    return AnimatedScale(
      scale: _pressed ? 0.965 : 1,
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      child: Material(
        color: widget.isCurrent
            ? accent.withValues(alpha: 0.13)
            : scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: widget.onTap,
          onHighlightChanged: (v) => setState(() => _pressed = v),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: widget.isCurrent
                    ? accent.withValues(alpha: 0.8)
                    : scheme.outlineVariant.withValues(alpha: 0.45),
                width: widget.isCurrent ? 1.6 : 1,
              ),
            ),
            child: Row(
              children: [
                if (widget.zone == AppZone.anime)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(11),
                    child: Image.asset(
                      'assets/images/logo/logo_rounded.png',
                      width: 42,
                      height: 42,
                      fit: BoxFit.cover,
                    ),
                  )
                else
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(widget.zone.icon, size: 24, color: accent),
                  ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.zone.label,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        widget.zone.english,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.outline,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 2.5,
                        ),
                      ),
                    ],
                  ),
                ),
                if (widget.isCurrent)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '你在这里',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: accent,
                      ),
                    ),
                  )
                else
                  Icon(
                    AnikumoIcons.arrow_forward_ios_rounded,
                    size: 13,
                    color: scheme.outline,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Batch 240: the Batch 131 wheel, restored as a sheet
/// body — cards ride an arc (they dip and tilt as they
/// leave the centre, like a wheel rolling), the centred
/// is the tappable one, and the backdrop accent follows
/// the centred zone through the sheet's callback.
class _ZoneWheelBody extends StatefulWidget {
  const _ZoneWheelBody({
    required this.current,
    required this.onSelect,
    required this.onFocused,
  });

  final AppZone current;
  final ValueChanged<AppZone> onSelect;
  final ValueChanged<AppZone> onFocused;

  @override
  State<_ZoneWheelBody> createState() => _ZoneWheelBodyState();
}

class _ZoneWheelBodyState extends State<_ZoneWheelBody> {
  late final PageController _controller = PageController(
    initialPage: zoneWheelInitialPage(widget.current),
    viewportFraction: 0.46,
  );
  late final ValueNotifier<double> _pageNotifier = ValueNotifier(
    zoneWheelInitialPage(widget.current).toDouble(),
  );
  int _lastCentred = -1;

  @override
  void initState() {
    super.initState();
    _lastCentred = zoneWheelInitialPage(widget.current);
    _controller.addListener(() {
      if (!_controller.hasClients) return;
      final page = _controller.page ?? _pageNotifier.value;
      _pageNotifier.value = page;
      final centred = page.round();
      if (centred != _lastCentred) {
        _lastCentred = centred;
        widget.onFocused(zoneForWheelIndex(centred));
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _pageNotifier.dispose();
    super.dispose();
  }

  void _onCardTap(int index) {
    if (index == _pageNotifier.value.round()) {
      widget.onSelect(zoneForWheelIndex(index));
    } else {
      _controller.animateToPage(
        index,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 216,
      child: PageView.builder(
        controller: _controller,
        itemBuilder: (context, index) {
          final zone = zoneForWheelIndex(index);
          return AnimatedBuilder(
            animation: _pageNotifier,
            builder: (context, _) {
              final page = _pageNotifier.value;
              final delta = (index - page).clamp(-1.5, 1.5).toDouble();
              final scale = 1 - delta.abs() * 0.16;
              final opacity = 1 - delta.abs() * 0.35;
              // The arc: off-centre cards sink and tilt,
              // which is what makes it read as a wheel
              // rather than a flat strip.
              final dip = (1 - math.cos(delta * 0.9)) * 30;
              return Transform.translate(
                offset: Offset(0, dip),
                child: Transform.rotate(
                  angle: delta * 0.10,
                  child: Transform.scale(
                    scale: scale,
                    child: Opacity(
                      opacity: opacity,
                      child: _ZoneCard(
                        zone: zone,
                        isCurrent: zone == widget.current,
                        isCentred: index == page.round(),
                        onTap: () => _onCardTap(index),
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// The wheel's card (restored from Batch 131/140).
class _ZoneCard extends StatelessWidget {
  const _ZoneCard({
    required this.zone,
    required this.isCurrent,
    required this.isCentred,
    required this.onTap,
  });

  final AppZone zone;
  final bool isCurrent;
  final bool isCentred;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accent = zoneAccent(zone, scheme);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 8),
      child: Material(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(24),
        elevation: isCentred ? 10 : 2,
        shadowColor: accent.withValues(alpha: 0.45),
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: isCentred
                    ? accent.withValues(alpha: 0.85)
                    : scheme.outlineVariant.withValues(alpha: 0.5),
                width: isCentred ? 2 : 1,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (zone == AppZone.anime)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.asset(
                      'assets/images/logo/logo_rounded.png',
                      width: 58,
                      height: 58,
                      fit: BoxFit.cover,
                    ),
                  )
                else
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(zone.icon, size: 32, color: accent),
                  ),
                const SizedBox(height: 12),
                Text(
                  zone.label,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  zone.english,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.outline,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 3,
                  ),
                ),
                const SizedBox(height: 8),
                if (isCurrent)
                  _badge(scheme, '你在这里', scheme.outline)
                else if (isCentred)
                  _badge(scheme, '点击进入', accent),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _badge(ColorScheme scheme, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

/// Batch 240: the flat left/right slide style — wide
/// banner cards that glide horizontally (no arc, no
/// tilt; the content parallaxes slightly inside the
/// card), with position dots under the pager. Tapping
/// the centred card enters; tapping a side card slides
/// it to the centre first.
class _ZoneSlideBody extends StatefulWidget {
  const _ZoneSlideBody({
    required this.current,
    required this.onSelect,
    required this.onFocused,
  });

  final AppZone current;
  final ValueChanged<AppZone> onSelect;
  final ValueChanged<AppZone> onFocused;

  @override
  State<_ZoneSlideBody> createState() => _ZoneSlideBodyState();
}

class _ZoneSlideBodyState extends State<_ZoneSlideBody> {
  late final PageController _controller = PageController(
    initialPage: zoneWheelInitialPage(widget.current),
    viewportFraction: 0.8,
  );
  late final ValueNotifier<double> _pageNotifier = ValueNotifier(
    zoneWheelInitialPage(widget.current).toDouble(),
  );
  int _lastCentred = -1;

  @override
  void initState() {
    super.initState();
    _lastCentred = zoneWheelInitialPage(widget.current);
    _controller.addListener(() {
      if (!_controller.hasClients) return;
      final page = _controller.page ?? _pageNotifier.value;
      _pageNotifier.value = page;
      final centred = page.round();
      if (centred != _lastCentred) {
        _lastCentred = centred;
        widget.onFocused(zoneForWheelIndex(centred));
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _pageNotifier.dispose();
    super.dispose();
  }

  void _onCardTap(int index) {
    if (index == _pageNotifier.value.round()) {
      widget.onSelect(zoneForWheelIndex(index));
    } else {
      _controller.animateToPage(
        index,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 132,
          child: PageView.builder(
            controller: _controller,
            itemBuilder: (context, index) {
              final zone = zoneForWheelIndex(index);
              return AnimatedBuilder(
                animation: _pageNotifier,
                builder: (context, _) {
                  final page = _pageNotifier.value;
                  final delta = (index - page).clamp(-1.0, 1.0).toDouble();
                  final accent = zoneAccent(zone, scheme);
                  return Opacity(
                    opacity: 1 - delta.abs() * 0.45,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 6,
                      ),
                      child: Material(
                        color: zone == widget.current
                            ? accent.withValues(alpha: 0.14)
                            : scheme.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(22),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(22),
                          onTap: () => _onCardTap(index),
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(22),
                              border: Border.all(
                                color: delta.abs() < 0.5
                                    ? accent.withValues(alpha: 0.8)
                                    : scheme.outlineVariant.withValues(
                                        alpha: 0.45,
                                      ),
                                width: delta.abs() < 0.5 ? 1.6 : 1,
                              ),
                            ),
                            child: Transform.translate(
                              offset: Offset(delta * -14, 0),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  if (zone == AppZone.anime)
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(13),
                                      child: Image.asset(
                                        'assets/images/logo/logo_rounded.png',
                                        width: 52,
                                        height: 52,
                                        fit: BoxFit.cover,
                                      ),
                                    )
                                  else
                                    Container(
                                      width: 52,
                                      height: 52,
                                      decoration: BoxDecoration(
                                        color: accent.withValues(alpha: 0.16),
                                        borderRadius: BorderRadius.circular(
                                          13,
                                        ),
                                      ),
                                      child: Icon(
                                        zone.icon,
                                        size: 28,
                                        color: accent,
                                      ),
                                    ),
                                  const SizedBox(width: 14),
                                  Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        zone.label,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleLarge
                                            ?.copyWith(
                                              fontWeight: FontWeight.w900,
                                            ),
                                      ),
                                      Text(
                                        zone.english,
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelSmall
                                            ?.copyWith(
                                              color: scheme.outline,
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: 3,
                                            ),
                                      ),
                                    ],
                                  ),
                                  if (zone == widget.current) ...[
                                    const SizedBox(width: 12),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: accent.withValues(alpha: 0.16),
                                        borderRadius: BorderRadius.circular(
                                          999,
                                        ),
                                      ),
                                      child: Text(
                                        '你在这里',
                                        style: TextStyle(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w700,
                                          color: accent,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
        const SizedBox(height: 6),
        AnimatedBuilder(
          animation: _pageNotifier,
          builder: (context, _) {
            final centred = zoneForWheelIndex(_pageNotifier.value.round());
            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final zone in AppZone.values)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: zone == centred ? 18 : 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: zone == centred
                          ? zoneAccent(zone, scheme)
                          : scheme.outlineVariant,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// Batch 240: the grid style — the four zones as big
/// square tiles in the panel's grouping (video row,
/// reading row), one tap to enter.
class _ZoneGridBody extends StatelessWidget {
  const _ZoneGridBody({required this.current, required this.onSelect});

  final AppZone current;
  final ValueChanged<AppZone> onSelect;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var g = 0; g < zoneSwitcherGroups.length; g++) ...[
          if (g > 0) const SizedBox(height: 12),
          Row(
            children: [
              for (var i = 0; i < zoneSwitcherGroups[g].$2.length; i++) ...[
                if (i > 0) const SizedBox(width: 12),
                Expanded(
                  child: _ZoneGridTile(
                    zone: zoneSwitcherGroups[g].$2[i],
                    isCurrent: zoneSwitcherGroups[g].$2[i] == current,
                    onTap: () => onSelect(zoneSwitcherGroups[g].$2[i]),
                  ),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }
}

class _ZoneGridTile extends StatelessWidget {
  const _ZoneGridTile({
    required this.zone,
    required this.isCurrent,
    required this.onTap,
  });

  final AppZone zone;
  final bool isCurrent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accent = zoneAccent(zone, scheme);
    return Material(
      color: isCurrent
          ? accent.withValues(alpha: 0.13)
          : scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: isCurrent
                  ? accent.withValues(alpha: 0.8)
                  : scheme.outlineVariant.withValues(alpha: 0.45),
              width: isCurrent ? 1.6 : 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (zone == AppZone.anime)
                ClipRRect(
                  borderRadius: BorderRadius.circular(13),
                  child: Image.asset(
                    'assets/images/logo/logo_rounded.png',
                    width: 48,
                    height: 48,
                    fit: BoxFit.cover,
                  ),
                )
              else
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(zone.icon, size: 27, color: accent),
                ),
              const SizedBox(height: 10),
              Text(
                zone.label,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                zone.english,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.outline,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2.5,
                ),
              ),
              if (isCurrent) ...[
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2.5,
                  ),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '你在这里',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: accent,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Batch 240: the segmented-pill style — each group is a
/// pill track with two big segments; the current zone's
/// segment wears its accent, tapping the other segment
/// switches. The most compact of the five.
class _ZoneSegmentBody extends StatelessWidget {
  const _ZoneSegmentBody({required this.current, required this.onSelect});

  final AppZone current;
  final ValueChanged<AppZone> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var g = 0; g < zoneSwitcherGroups.length; g++) ...[
          Padding(
            padding: EdgeInsets.only(top: g == 0 ? 2 : 14, bottom: 7),
            child: Text(
              zoneSwitcherGroups[g].$1,
              style: theme.textTheme.labelMedium?.copyWith(
                color: scheme.outline,
                fontWeight: FontWeight.w700,
                letterSpacing: 2,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              children: [
                for (var i = 0; i < zoneSwitcherGroups[g].$2.length; i++) ...[
                  if (i > 0) const SizedBox(width: 5),
                  Expanded(
                    child: _segment(
                      context,
                      zoneSwitcherGroups[g].$2[i],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _segment(BuildContext context, AppZone zone) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accent = zoneAccent(zone, scheme);
    final isCurrent = zone == current;
    return Material(
      color: isCurrent ? accent : Colors.transparent,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () => onSelect(zone),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                zone.icon,
                size: 19,
                color: isCurrent ? Colors.white : accent,
              ),
              const SizedBox(width: 7),
              Text(
                zone.label,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: isCurrent ? Colors.white : scheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
