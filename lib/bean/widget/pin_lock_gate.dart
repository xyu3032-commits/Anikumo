import 'package:flutter/material.dart';
import 'package:anikumo/services/ui/app_extras.dart';
import 'package:anikumo/bean/widget/anikumo_icons.dart';

/// PIN app-lock gate (batch 15, G10). When a PIN is set, the
/// app opens on this pad; a correct entry unlocks for the rest
/// of the process session.
class PinLockGate extends StatefulWidget {
  const PinLockGate({super.key, required this.child});

  final Widget child;

  @override
  State<PinLockGate> createState() => _PinLockGateState();
}

class _PinLockGateState extends State<PinLockGate> {
  String _entered = '';
  bool _error = false;

  bool get _locked => PinLock.isEnabled && !PinLock.unlockedThisSession;

  void _press(String digit) {
    if (_entered.length >= 6) return;
    final next = _entered + digit;
    setState(() {
      _entered = next;
      _error = false;
    });
    // PINs are 4-6 digits; try as soon as a plausible length is
    // reached — a stored hash only matches the exact PIN.
    if (next.length >= 4 && PinLock.verify(next)) {
      PinLock.unlockedThisSession = true;
      setState(() => _entered = '');
    } else if (next.length >= 6) {
      setState(() {
        _error = true;
        _entered = '';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_locked) return widget.child;
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              AnikumoIcons.lock_rounded,
              size: 44,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 14),
            Text(
              _error ? 'PIN 不对，再试一次' : '输入 PIN 解锁 anikumo',
              style: theme.textTheme.titleMedium?.copyWith(
                color: _error ? theme.colorScheme.error : null,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < 6; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    curve: Curves.easeOut,
                    width: i < _entered.length ? 15 : 13,
                    height: i < _entered.length ? 15 : 13,
                    margin: const EdgeInsets.symmetric(horizontal: 5),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i < _entered.length
                          ? theme.colorScheme.primary
                          : theme.colorScheme.outlineVariant,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 26),
            for (final row in const [
              ['1', '2', '3'],
              ['4', '5', '6'],
              ['7', '8', '9'],
              ['', '0', '⌫'],
            ])
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final key in row)
                    SizedBox(
                      width: 76,
                      height: 60,
                      child: key.isEmpty
                          ? const SizedBox()
                          : TextButton(
                              onPressed: () {
                                if (key == '⌫') {
                                  setState(() {
                                    if (_entered.isNotEmpty) {
                                      _entered = _entered.substring(
                                        0,
                                        _entered.length - 1,
                                      );
                                    }
                                  });
                                } else {
                                  _press(key);
                                }
                              },
                              child: Text(
                                key,
                                style: theme.textTheme.headlineSmall,
                              ),
                            ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
