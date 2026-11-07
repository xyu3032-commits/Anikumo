import 'package:flutter/material.dart';
import 'package:anikumo/services/ui/app_extras.dart';

/// Batch 15 motion kit: the reusable effect widgets behind the
/// "36 effects" pass. Every widget here degrades to a static
/// render under SmoothMode, so the fluency switch tames them
/// all at once.

/// Scale-in entrance (cards, chips, badges).
class ScaleIn extends StatefulWidget {
  const ScaleIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.from = 0.92,
  });

  final Widget child;
  final Duration delay;
  final double from;

  @override
  State<ScaleIn> createState() => _ScaleInState();
}

class _ScaleInState extends State<ScaleIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
  );

  @override
  void initState() {
    super.initState();
    if (SmoothMode.enabled) {
      _controller.value = 1;
    } else if (widget.delay == Duration.zero) {
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
    if (SmoothMode.enabled) return widget.child;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = Curves.easeOutBack.transform(_controller.value);
        final scale = widget.from + (1 - widget.from) * t;
        return Opacity(
          opacity: _controller.value.clamp(0.0, 1.0),
          child: Transform.scale(scale: scale, child: child),
        );
      },
      child: widget.child,
    );
  }
}

/// Horizontal slide-in (rows entering from a side).
class SlideInX extends StatefulWidget {
  const SlideInX({
    super.key,
    required this.child,
    this.fromRight = true,
    this.delay = Duration.zero,
  });

  final Widget child;
  final bool fromRight;
  final Duration delay;

  @override
  State<SlideInX> createState() => _SlideInXState();
}

class _SlideInXState extends State<SlideInX>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
  );

  @override
  void initState() {
    super.initState();
    if (SmoothMode.enabled) {
      _controller.value = 1;
    } else if (widget.delay == Duration.zero) {
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
    if (SmoothMode.enabled) return widget.child;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = Curves.easeOutCubic.transform(_controller.value);
        final dx = (widget.fromRight ? 1 : -1) * 24 * (1 - t);
        return Opacity(
          opacity: t,
          child: Transform.translate(offset: Offset(dx, 0), child: child),
        );
      },
      child: widget.child,
    );
  }
}

/// Animated number that counts toward [value] (stats, badges).
class CountUpNumber extends StatelessWidget {
  const CountUpNumber({
    super.key,
    required this.value,
    this.style,
    this.duration = const Duration(milliseconds: 600),
  });

  final int value;
  final TextStyle? style;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    if (SmoothMode.enabled) return Text('$value', style: style);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value.toDouble()),
      duration: duration,
      curve: Curves.easeOut,
      builder: (context, animated, _) =>
          Text('${animated.round()}', style: style),
    );
  }
}

/// Progress bar that animates to [value] instead of jumping.
class AnimatedBar extends StatelessWidget {
  const AnimatedBar({
    super.key,
    required this.value,
    this.height = 5,
  });

  /// 0..1
  final double value;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: value.clamp(0.0, 1.0)),
        duration: SmoothMode.enabled
            ? Duration.zero
            : const Duration(milliseconds: 500),
        curve: Curves.easeOut,
        builder: (context, animated, _) => LinearProgressIndicator(
          value: animated,
          minHeight: height,
          backgroundColor: theme.colorScheme.surfaceContainerHighest,
        ),
      ),
    );
  }
}

/// Soft pulsing placeholder block (loading shimmer substitute
/// without a gradient sweep's cost).
class PulseBox extends StatefulWidget {
  const PulseBox({super.key, this.height = 16, this.radius = 8});

  final double height;
  final double radius;

  @override
  State<PulseBox> createState() => _PulseBoxState();
}

class _PulseBoxState extends State<PulseBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
    if (!SmoothMode.enabled) _controller.repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).colorScheme.surfaceContainerHighest;
    if (SmoothMode.enabled) {
      return Container(
        height: widget.height,
        decoration: BoxDecoration(
          color: base,
          borderRadius: BorderRadius.circular(widget.radius),
        ),
      );
    }
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => Container(
        height: widget.height,
        decoration: BoxDecoration(
          color: base.withValues(alpha: 0.45 + 0.35 * _controller.value),
          borderRadius: BorderRadius.circular(widget.radius),
        ),
      ),
    );
  }
}

/// Batch 21: press feedback — a subtle scale-down while the
/// child is pressed. The GestureDetector only listens (it
/// never claims the gesture), so the child's own InkWell
/// ripple and tap keep working untouched. Static under
/// SmoothMode, like the rest of the kit.
class PressableScale extends StatefulWidget {
  const PressableScale({
    super.key,
    required this.child,
    this.scale = 0.97,
  });

  final Widget child;
  final double scale;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 150),
    reverseDuration: const Duration(milliseconds: 220),
  );
  late final Animation<double> _scaleAnimation = Tween<double>(
    begin: 1,
    end: widget.scale,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (SmoothMode.enabled) return widget.child;
    return GestureDetector(
      behavior: HitTestBehavior.deferToChild,
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) => _controller.reverse(),
      onTapCancel: () => _controller.reverse(),
      child: ScaleTransition(scale: _scaleAnimation, child: widget.child),
    );
  }
}
