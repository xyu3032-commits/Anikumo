import 'dart:async';

import 'package:flutter/material.dart';
import 'package:anikumo/bean/widget/anikumo_icons.dart';
import 'package:anikumo/services/i18n/app_strings.dart';

/// Batch 277 (#4): full-surface touch shield shown while
/// the player's touch lock is on. The shield swallows
/// every gesture over the video area (taps, seeks,
/// brightness/volume drags all land on its no-op
/// handlers); the only way out is holding the lock chip
/// for [unlockHold] — a deliberate press a stray tap or
/// a pocket cannot fake.
class TouchLockOverlay extends StatefulWidget {
  const TouchLockOverlay({super.key, required this.onUnlock});

  final VoidCallback onUnlock;

  /// How long the unlock chip must be held.
  static const Duration unlockHold = Duration(milliseconds: 800);

  @override
  State<TouchLockOverlay> createState() => _TouchLockOverlayState();
}

class _TouchLockOverlayState extends State<TouchLockOverlay> {
  Timer? _holdTimer;
  bool _holding = false;

  void _beginHold() {
    _holdTimer?.cancel();
    if (mounted) setState(() => _holding = true);
    _holdTimer = Timer(TouchLockOverlay.unlockHold, () {
      _holdTimer = null;
      widget.onUnlock();
    });
  }

  void _cancelHold() {
    _holdTimer?.cancel();
    _holdTimer = null;
    if (mounted && _holding) setState(() => _holding = false);
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {},
            onDoubleTap: () {},
            onLongPress: () {},
            onHorizontalDragStart: (_) {},
            onVerticalDragStart: (_) {},
            child: const SizedBox.expand(),
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (_) => _beginHold(),
              onPointerUp: (_) => _cancelHold(),
              onPointerCancel: (_) => _cancelHold(),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: _holding ? 0.78 : 0.55),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      AnikumoIcons.lock_outline,
                      color: Colors.white,
                      size: 18,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      S.t('长按解锁'),
                      style:
                          const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
