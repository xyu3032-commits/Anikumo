import 'package:flutter/material.dart';

/// Batch 110: the shared search-stage kit — the visual
/// overhaul of every search page in the app. Pages keep
/// their own fields, state and search logic; this kit
/// supplies the common stage dressing: a focus-reactive
/// hero shell for the search field, an animated pill
/// switch for modes/scopes, section bars with count
/// badges, and staggered result entrances. Colors come
/// from the ambient [ColorScheme], so each zone's theme
/// (editorial anime zone, Violet Glass manga/novel zones)
/// tints the same shapes its own way.

/// One option of a [PillSwitch].
class PillSwitchOption<T> {
  const PillSwitchOption({
    required this.value,
    required this.label,
    this.icon,
  });

  final T value;
  final String label;
  final IconData? icon;
}

/// Animated pill switch: flat colors only (batch 112 —
/// the batch-110 gradient/shadow dressing read as gaudy;
/// the user asked for plain). The selection still
/// animates (200 ms), per the standing mode-switch rule.
class PillSwitch<T> extends StatelessWidget {
  const PillSwitch({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
  });

  final List<PillSwitchOption<T>> options;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(
          color: colors.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final option in options)
            InkWell(
              borderRadius: BorderRadius.circular(22),
              onTap: () => onChanged(option.value),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                padding:
                    const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
                decoration: BoxDecoration(
                  color: option.value == value
                      ? colors.primary
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (option.icon != null) ...[
                      Icon(
                        option.icon,
                        size: 17,
                        color: option.value == value
                            ? colors.onPrimary
                            : colors.onSurfaceVariant,
                      ),
                      const SizedBox(width: 5),
                    ],
                    Text(
                      option.label,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: option.value == value
                            ? colors.onPrimary
                            : colors.onSurfaceVariant,
                        fontWeight: option.value == value
                            ? FontWeight.w800
                            : FontWeight.w500,
                      ),
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

/// Plain shell for a search field (batch 112: flat fill,
/// thin rim; the rim takes the primary color while the
/// field has focus — a state cue, not decoration). Wrap
/// the page's existing field row — behaviour untouched.
class SearchHeroShell extends StatefulWidget {
  const SearchHeroShell({
    super.key,
    required this.child,
    this.focusNode,
    this.radius = 999,
    this.padding = const EdgeInsets.symmetric(horizontal: 14),
  });

  final Widget child;
  final FocusNode? focusNode;
  final double radius;
  final EdgeInsetsGeometry padding;

  @override
  State<SearchHeroShell> createState() => _SearchHeroShellState();
}

class _SearchHeroShellState extends State<SearchHeroShell> {
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode?.addListener(_onFocusChange);
    _focused = widget.focusNode?.hasFocus ?? false;
  }

  @override
  void didUpdateWidget(SearchHeroShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode?.removeListener(_onFocusChange);
      widget.focusNode?.addListener(_onFocusChange);
      _focused = widget.focusNode?.hasFocus ?? false;
    }
  }

  @override
  void dispose() {
    widget.focusNode?.removeListener(_onFocusChange);
    super.dispose();
  }

  void _onFocusChange() {
    final focused = widget.focusNode?.hasFocus ?? false;
    if (focused != _focused && mounted) {
      setState(() => _focused = focused);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      padding: widget.padding,
      decoration: BoxDecoration(
        color: colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(widget.radius),
        border: Border.all(
          color: _focused
              ? colors.primary.withValues(alpha: 0.55)
              : colors.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: widget.child,
    );
  }
}
