import 'package:flutter/material.dart';

/// Batch 32: state rows for the cross-zone companion sections
/// （配套漫画 / 配套小说 / 配套动漫） on the detail pages.
///
/// The sections used to render ONLY when they had results, so
/// "no counterpart exists" was indistinguishable from "the
/// feature is missing" — the ninth-build feedback ("anime has
/// manga but no novels", "novels have no manga/anime") was
/// exactly that. Now every companion section always renders:
/// a loading row while searching, the rail when found, and
/// this empty row — with a deep-link into the other zone's
/// search — when nothing matched.
///
/// Presentation only: the row knows nothing about any zone;
/// callers pass the copy and the navigation callback, keeping
/// each zone's logic in its own layer.
class CompanionLoadingRow extends StatelessWidget {
  const CompanionLoadingRow({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: 10),
        Text(
          label,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class CompanionEmptyRow extends StatelessWidget {
  const CompanionEmptyRow({
    super.key,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(Icons.search_off_rounded,
              size: 20, color: scheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ),
          TextButton(onPressed: onAction, child: Text(actionLabel)),
        ],
      ),
    );
  }
}
