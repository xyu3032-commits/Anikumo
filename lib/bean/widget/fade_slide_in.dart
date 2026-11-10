import 'dart:async';

import 'package:flutter/material.dart';
import 'package:anikumo/services/ui/app_extras.dart';
import 'package:anikumo/utils/constants.dart';

/// One-shot entrance: fades in while rising slightly. Used to stagger
/// section entrances so a page settles instead of popping in all at once.
class FadeSlideIn extends StatefulWidget {
  const FadeSlideIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
  });

  final Widget child;
  final Duration delay;

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

/// Batch 123: 3D entrance for the Top-5 rank rows. Each row
/// starts tipped back in perspective (rotateX with a slight
/// rotateY for depth), rises and fades in, staggered by
/// [index] — a cascade of cards flipping up toward the
/// viewer instead of the flat fade the rows had (they had
/// none). One-shot.
///
/// Batch 133: EXEMPT from SmoothMode. The user asked for
/// this entrance by name, then reported it missing — the
/// smooth-mode master switch had silently swallowed it
/// along with every other entrance. It plays once for half
/// a second over at most ten rows, so it costs fluency
/// nothing; the rest of the motion kit stays tamed.
class RankEntrance3D extends StatefulWidget {
  const RankEntrance3D({
    super.key,
    required this.index,
    required this.child,
  });

  final int index;
  final Widget child;

  @override
  State<RankEntrance3D> createState() => _RankEntrance3DState();
}

class _RankEntrance3DState extends State<RankEntrance3D>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  );
  late final Animation<double> _curve =
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);

  // Batch 138: the entrance starts when the row is actually
  // on screen, not when it is built. These rows live in
  // eagerly built sliver columns, so below-the-fold rows
  // used to burn their one-shot animation unseen — the
  // viewer then found "no 3D / no slide" on whichever list
  // they scrolled through afterwards.
  bool _started = false;
  ScrollPosition? _scrollPosition;
  Timer? _fallbackTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _arm());
  }

  void _arm() {
    if (!mounted || _started) return;
    if (_rowVisible()) {
      _start();
      return;
    }
    try {
      _scrollPosition = Scrollable.of(context).position;
      _scrollPosition!.addListener(_checkVisible);
    } catch (_) {
      // No scrollable ancestor: just play.
      _start();
      return;
    }
    // Safety net: never leave a row invisible if the checks
    // misfire (nested scrollables, transforms, ...).
    _fallbackTimer = Timer(const Duration(milliseconds: 1200), _start);
  }

  bool _rowVisible() {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return false;
    RenderBox? viewport;
    try {
      viewport =
          Scrollable.of(context).context.findRenderObject() as RenderBox?;
    } catch (_) {
      return true;
    }
    if (viewport == null || !viewport.hasSize) return true;
    final rowRect = box.localToGlobal(Offset.zero) & box.size;
    final viewRect = viewport.localToGlobal(Offset.zero) & viewport.size;
    return rowRect.intersect(viewRect).height > 24;
  }

  void _checkVisible() {
    if (_rowVisible()) _start();
  }

  void _start() {
    if (_started || !mounted) return;
    _started = true;
    _scrollPosition?.removeListener(_checkVisible);
    _scrollPosition = null;
    _fallbackTimer?.cancel();
    _fallbackTimer = null;
    final delay = Duration(milliseconds: 120 + 70 * widget.index);
    Future.delayed(delay, () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _scrollPosition?.removeListener(_checkVisible);
    _fallbackTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Batch 133: no SmoothMode gate here (see the class doc).
    return AnimatedBuilder(
      animation: _curve,
      builder: (context, child) {
        final t = _curve.value;
        final inv = 1 - t;
        return Opacity(
          opacity: t,
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.0011)
              ..rotateX(0.62 * inv)
              ..rotateY(-0.16 * inv),
            child: Transform.translate(
              offset: Offset(0, 30 * inv),
              child: child,
            ),
          ),
        );
      },
      child: widget.child,
    );
  }
}

class _FadeSlideInState extends State<FadeSlideIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: StyleString.animMedium,
  );
  late final Animation<double> _curve =
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);

  @override
  void initState() {
    super.initState();
    if (widget.delay == Duration.zero) {
      _controller.forward();
    } else {
      Future.delayed(widget.delay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Smooth mode (batch 15, G12): entrance motion off — the
    // child renders statically, no controller work at all.
    if (SmoothMode.enabled) return widget.child;
    return AnimatedBuilder(
      animation: _curve,
      builder: (context, child) {
        final t = _curve.value;
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, 10 * (1 - t)),
            child: child,
          ),
        );
      },
      // Batch 32: the entrance animates opacity/offset of
      // SECTION-sized subtrees (discover sections, detail
      // rails). Without a boundary every animation frame
      // re-rasterizes the whole section — a visible entry
      // stutter on cover-dense pages. The boundary rasterizes
      // the child once and lets the compositor move/fade the
      // cached layer; it repaints normally when the child
      // itself paints (scrolling lists included).
      child: RepaintBoundary(child: widget.child),
    );
  }
}
