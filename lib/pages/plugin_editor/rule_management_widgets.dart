import 'package:flutter/material.dart';

class RulePageIntro extends StatelessWidget {
  const RulePageIntro({
    super.key,
    required this.title,
    required this.description,
    required this.icon,
    this.actions = const [],
  });

  final String title;
  final String description;
  final IconData icon;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: colors.primaryContainer,
        borderRadius: BorderRadius.circular(32),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Text(title,
                  style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: colors.onPrimaryContainer)),
            ),
            const SizedBox(width: 16),
            Icon(icon, size: 32, color: colors.onPrimaryContainer),
          ]),
          const SizedBox(height: 8),
          Text(description,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: colors.onPrimaryContainer)),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 20),
            Wrap(spacing: 8, runSpacing: 8, children: actions),
          ],
        ],
      ),
    );
  }
}

class RuleSection extends StatelessWidget {
  const RuleSection({
    super.key,
    required this.title,
    required this.child,
    this.description,
    this.icon,
  });

  final String title;
  final String? description;
  final IconData? icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(28),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              if (icon != null) ...[
                Icon(icon, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
              ],
              Expanded(
                  child: Text(title,
                      style: theme.textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w600))),
            ]),
            if (description != null) ...[
              const SizedBox(height: 6),
              Text(description!,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ],
            const SizedBox(height: 24),
            child,
          ],
        ),
      ),
    );
  }
}

/// Batch 61: first-run guide under the empty state. There is
/// no built-in rule library anymore (batch 59), so a new user
/// lands on an empty page — this block explains what a rule
/// is and shows the three ways to add one, each with its own
/// icon and a plain-language line, tappable straight into
/// that flow (same icons and wording as the add dialog).
class RuleAddGuide extends StatelessWidget {
  const RuleAddGuide({super.key, required this.options});

  final List<RuleAddOption> options;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '规则就是一个站点的访问说明，App 靠它来搜索和播放番剧。'
            '没有内置规则库，用下面任一方式添加你自己的：',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          for (final option in options)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: colors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(12),
                clipBehavior: Clip.antiAlias,
                child: ListTile(
                  minVerticalPadding: 12,
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: colors.primaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(option.icon,
                        size: 20, color: colors.onPrimaryContainer),
                  ),
                  title: Text(option.title),
                  subtitle: Text(option.subtitle),
                  trailing:
                      const Icon(Icons.arrow_forward_rounded, size: 20),
                  onTap: option.onTap,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class RuleAddOption {
  const RuleAddOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
}

InputDecoration ruleInputDecoration(BuildContext context,
    {String? label, String? hint, Widget? prefix, Widget? suffix}) {
  final colors = Theme.of(context).colorScheme;
  return InputDecoration(
    labelText: label,
    hintText: hint,
    prefixIcon: prefix,
    suffixIcon: suffix,
    filled: true,
    fillColor: colors.surfaceContainerHighest,
    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
    border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
    enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
    focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: colors.primary, width: 2)),
  );
}
