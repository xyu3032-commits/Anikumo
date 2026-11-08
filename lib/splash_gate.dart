import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Batch 93: animated launch intro.
///
/// Until now a cold start was the OS splash (a plain white
/// field) followed by the app — no designed moment at all.
/// The native launch background now carries the brand
/// (deep-violet night + emblem), and this gate continues
/// the same palette in Flutter: two soft violet glows
/// breathe behind the emblem, which scales/fades in with
/// a slight overshoot, then the name rises in and the
/// three zone words fade up. The real app builds
/// UNDERNEATH the overlay the whole time (routing, first
/// page, everything), so the intro costs no startup time
/// beyond its own ~1.6 s; a tap skips it, and the system
/// "reduce motion" setting collapses it to a brief static
/// card. It plays once per process.
class SplashGate extends StatefulWidget {
  const SplashGate({super.key, required this.child});

  final Widget child;

  @override
  State<SplashGate> createState() => _SplashGateState();
}

double _phase(double t, double start, double end) =>
    ((t - start) / (end - start)).clamp(0.0, 1.0);

double _easeOutCubic(double x) => 1 - math.pow(1 - x, 3).toDouble();

double _easeOutBack(double x) {
  const c1 = 1.70158;
  const c3 = c1 + 1;
  final u = x - 1;
  return 1 + c3 * u * u * u + c1 * u * u;
}

class _SplashGateState extends State<SplashGate>
    with TickerProviderStateMixin {
  static bool _played = false;

  late final AnimationController _intro;
  late final AnimationController _pulse;
  Timer? _leaveTimer;
  bool _started = false;
  bool _leaving = false;
  bool _gone = false;
  bool _reduced = false;

  @override
  void initState() {
    super.initState();
    _gone = _played;
    _intro = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started || _gone) return;
    _started = true;
    _played = true;
    _reduced = MediaQuery.disableAnimationsOf(context);
    if (_reduced) {
      _intro.value = 1;
      _leaveTimer = Timer(const Duration(milliseconds: 450), _startLeaving);
    } else {
      _intro.forward();
      _pulse.repeat();
      _leaveTimer =
          Timer(const Duration(milliseconds: 1700), _startLeaving);
    }
  }

  void _startLeaving() {
    if (!mounted || _gone || _leaving) return;
    setState(() => _leaving = true);
    _leaveTimer = Timer(const Duration(milliseconds: 380), () {
      if (mounted) setState(() => _gone = true);
    });
  }

  @override
  void dispose() {
    _leaveTimer?.cancel();
    _intro.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (!_gone)
          Positioned.fill(
            child: IgnorePointer(
              ignoring: _leaving,
              child: AnimatedOpacity(
                opacity: _leaving ? 0 : 1,
                duration: const Duration(milliseconds: 350),
                child: GestureDetector(
                  onTap: _startLeaving,
                  child: AnimatedBuilder(
                    animation: Listenable.merge([_intro, _pulse]),
                    builder: (context, _) => _SplashVisual(
                      t: _intro.value,
                      pulse: _pulse.value,
                      reduced: _reduced,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _SplashVisual extends StatelessWidget {
  const _SplashVisual({
    required this.t,
    required this.pulse,
    required this.reduced,
  });

  /// Intro progress 0..1.
  final double t;

  /// Breathing cycle 0..1 (repeating).
  final double pulse;

  final bool reduced;

  @override
  Widget build(BuildContext context) {
    final logoPhase = _phase(t, 0.0, 0.55);
    final logoScale = reduced ? 1.0 : 0.82 + 0.18 * _easeOutBack(logoPhase);
    final logoOpacity = _easeOutCubic(_phase(t, 0.0, 0.4));
    final namePhase = _easeOutCubic(_phase(t, 0.35, 0.8));
    final subOpacity = _easeOutCubic(_phase(t, 0.6, 1.0));
    final glow = reduced
        ? 1.0
        : 0.82 + 0.18 * math.sin(pulse * math.pi * 2);
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1E1338), Color(0xFF0D0A18)],
        ),
      ),
      child: Stack(
        children: [
          // Two soft violet glows breathing behind the emblem.
          Positioned(
            top: -70,
            right: -50,
            child: _Glow(size: 300, alpha: 0.30 * glow),
          ),
          Positioned(
            bottom: -90,
            left: -60,
            child: _Glow(size: 340, alpha: 0.22 * glow),
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Opacity(
                  opacity: logoOpacity,
                  child: Transform.scale(
                    scale: logoScale,
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(26),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF7A5CFF)
                                .withValues(alpha: 0.45 * glow),
                            blurRadius: 44,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(26),
                        child: Image.asset(
                          'assets/images/logo/logo_rounded.png',
                          width: 96,
                          height: 96,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Opacity(
                  opacity: namePhase,
                  child: Transform.translate(
                    offset: Offset(0, 14 * (1 - namePhase)),
                    child: const Text(
                      'Anikumo',
                      style: TextStyle(
                        fontSize: 31,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 7,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Opacity(
                  opacity: subOpacity,
                  child: const Text(
                    '动 漫 · 漫 画 · 小 说',
                    style: TextStyle(
                      fontSize: 12.5,
                      letterSpacing: 3,
                      color: Colors.white60,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 54,
            child: Opacity(
              opacity: subOpacity,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < 3; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3.5),
                      child: _Dot(phase: pulse, offset: i / 3),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.size, required this.alpha});

  final double size;
  final double alpha;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              const Color(0xFF7A5CFF).withValues(alpha: alpha),
              const Color(0xFF7A5CFF).withValues(alpha: 0),
            ],
          ),
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.phase, required this.offset});

  final double phase;
  final double offset;

  @override
  Widget build(BuildContext context) {
    final wave =
        0.35 + 0.65 * (0.5 + 0.5 * math.sin((phase + offset) * math.pi * 2));
    return Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: wave),
      ),
    );
  }
}
