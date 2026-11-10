import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:anikumo/bean/widget/anikumo_icons.dart';

/// Batch 131: the three zones of the app. Switching used to
/// mean digging through the 发现 page; now each zone's own
/// name mark in its home header (the masthead's ANIME label,
/// the manga 漫画 chip, the novel 小说 title) opens an
/// infinitely looping wheel — spin it, tap the centred card
/// to jump, tap anywhere else to go back to what you were
/// doing. Per the user's correction, the entry is the zone
/// mark, not the Anikumo wordmark or the app icon.
enum AppZone {
  anime('动漫', 'ANIME', AnikumoIcons.smart_display_rounded),
  manga('漫画', 'MANGA', AnikumoIcons.auto_stories_rounded),
  novel('小说', 'NOVEL', AnikumoIcons.menu_book_rounded);

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
      };
}

/// The zone shown at wheel position [index]. The wheel is
/// endless in both directions, so indices run far past the
/// zone count in either direction.
AppZone zoneForWheelIndex(int index) =>
    AppZone.values[index % AppZone.values.length];

/// The wheel page the switcher opens on: a large round
/// multiple of the zone count (so the modulo mapping stays
/// aligned) plus the current zone's own offset.
int zoneWheelInitialPage(AppZone current) => 3000 + current.index;

/// The colour a zone wears in the switcher (its card accent
/// and backdrop tint).
Color zoneAccent(AppZone zone, ColorScheme scheme) => switch (zone) {
      AppZone.anime => scheme.primary,
      AppZone.manga => scheme.tertiary,
      AppZone.novel => scheme.secondary,
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

/// Opens the wheel switcher as a dismissible overlay: any
/// tap outside the wheel closes it without switching.
Future<void> showZoneSwitcher(
  BuildContext context, {
  required AppZone current,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '切换专区',
    barrierColor: Colors.black.withValues(alpha: 0.55),
    transitionDuration: const Duration(milliseconds: 220),
    transitionBuilder: (context, animation, _, child) {
      final curved =
          CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.94, end: 1).animate(curved),
          child: child,
        ),
      );
    },
    pageBuilder: (dialogContext, _, _) =>
        _ZoneWheel(current: current, hostContext: context),
  );
}

class _ZoneWheel extends StatefulWidget {
  const _ZoneWheel({required this.current, required this.hostContext});

  final AppZone current;

  /// The page that opened the switcher. Zone navigation
  /// runs on this context after the dialog closes, because
  /// the dialog's own route is already gone by then.
  final BuildContext hostContext;

  @override
  State<_ZoneWheel> createState() => _ZoneWheelState();
}

class _ZoneWheelState extends State<_ZoneWheel> {
  late final PageController _controller = PageController(
    initialPage: zoneWheelInitialPage(widget.current),
    viewportFraction: 0.46,
  );

  // Batch 140: the page value lives in a notifier, not
  // setState — scrolling used to rebuild the whole dialog
  // (texts, cards, all of it) on every pixel. Now only the
  // backdrop and the visible cards' transforms listen.
  late final ValueNotifier<double> _pageNotifier =
      ValueNotifier(zoneWheelInitialPage(widget.current).toDouble());

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      if (_controller.hasClients) {
        _pageNotifier.value = _controller.page ?? _pageNotifier.value;
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
      final zone = zoneForWheelIndex(index);
      final host = widget.hostContext;
      Navigator.of(context).pop();
      if (zone != widget.current) {
        // Let the dialog finish closing before touching the
        // zone routes underneath it.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (host.mounted) switchAppZone(host, widget.current, zone);
        });
      }
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          // Batch 140: the backdrop wears the centred zone's
          // colour — a soft radial wash that follows the
          // wheel as it turns, so arriving at a zone feels
          // like entering its tint whether or not the viewer
          // taps in. (Decoration only: taps still fall
          // through to the barrier and dismiss.)
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
              animation: _pageNotifier,
              builder: (context, _) {
                final accent =
                    zoneWheelBackdropAccent(_pageNotifier.value, scheme);
                return DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(0, -0.05),
                      radius: 1.15,
                      colors: [
                        accent.withValues(alpha: 0.36),
                        accent.withValues(alpha: 0.12),
                        Colors.transparent,
                      ],
                    ),
                  ),
                );
              },
              ),
            ),
          ),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
          Text(
            '切换专区',
            style: theme.textTheme.titleMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '左右滑动转轮 · 点中间的卡片进入',
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.white.withValues(alpha: 0.75),
            ),
          ),
          const SizedBox(height: 26),
          SizedBox(
            height: 216,
            child: PageView.builder(
              controller: _controller,
              itemBuilder: (context, index) {
                final zone = zoneForWheelIndex(index);
                return AnimatedBuilder(
                  animation: _pageNotifier,
                  builder: (context, _) {
                    final page = _pageNotifier.value;
                    final delta = (index - page).clamp(-1.5, 1.5);
                    final scale = 1 - delta.abs() * 0.16;
                    final opacity = 1 - delta.abs() * 0.35;
                    return Transform.scale(
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
                    );
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 26),
          Text(
            '点任意空白处返回',
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.white.withValues(alpha: 0.6),
            ),
          ),
            ],
          ),
        ],
      ),
    );
  }
}

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
