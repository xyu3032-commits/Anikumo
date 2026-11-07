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
