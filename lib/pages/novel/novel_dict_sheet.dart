import 'package:flutter/material.dart';

import 'package:anikumo/services/i18n/app_strings.dart';
import 'package:anikumo/services/novel/novel_dictionary.dart';

/// Batch 280 (#12): the dictionary look-up panel. The
/// reader's paragraphs are plain Text (batch 32 removed
/// per-paragraph selection overlays for scroll
/// performance), so the entry point is a long-press on a
/// paragraph: this sheet segments the paragraph against
/// the dictionary's word table and lets the reader tap a
/// word — or any single character — for its pinyin and
/// definition. Fully offline (see novel_dictionary.dart).
Future<void> showNovelDictSheet(
  BuildContext context,
  String paragraph,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _NovelDictSheet(paragraph: paragraph),
  );
}

class _NovelDictSheet extends StatefulWidget {
  const _NovelDictSheet({required this.paragraph});

  final String paragraph;

  @override
  State<_NovelDictSheet> createState() => _NovelDictSheetState();
}

class _NovelDictSheetState extends State<_NovelDictSheet> {
  NovelDictionary? _dict;
  bool _failed = false;
  String? _selected;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final dict = await NovelDictionary.load();
    if (!mounted) return;
    if (dict == null) {
      setState(() => _failed = true);
      return;
    }
    // Preselect the first segment the dictionary knows.
    String? first;
    for (final segment in dict.segment(widget.paragraph)) {
      if (dict.lookup(segment).found) {
        first = segment;
        break;
      }
    }
    setState(() {
      _dict = dict;
      _selected = first;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  S.t('查词'),
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    S.t('点按词语或单字查看释义'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_failed)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(child: Text(S.t('词典加载失败'))),
              )
            else if (_dict == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              )
            else
              _content(theme),
          ],
        ),
      ),
    );
  }

  Widget _content(ThemeData theme) {
    final dict = _dict!;
    final segments = dict.segment(widget.paragraph);
    final lookup =
        _selected == null ? const DictLookup() : dict.lookup(_selected!);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 168),
          child: SingleChildScrollView(
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final segment in segments)
                  _chip(theme, segment, dict.lookup(segment).found),
              ],
            ),
          ),
        ),
        const Divider(height: 24),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 260),
          child: SingleChildScrollView(
            child: _result(theme, lookup),
          ),
        ),
      ],
    );
  }

  Widget _chip(ThemeData theme, String segment, bool known) {
    final selected = segment == _selected;
    return ChoiceChip(
      label: Text(segment),
      selected: selected,
      onSelected: known
          ? (_) => setState(() => _selected = segment)
          : null,
      labelStyle: TextStyle(
        color: known
            ? null
            : theme.colorScheme.outline.withValues(alpha: 0.6),
      ),
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _result(ThemeData theme, DictLookup lookup) {
    if (_selected == null || !lookup.found) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(S.t('词典里暂未收录')),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (lookup.entry != null) _entry(theme, lookup.entry!, head: true),
        for (final charEntry in lookup.charEntries) ...[
          if (lookup.entry != null || charEntry != lookup.charEntries.first)
            const SizedBox(height: 12),
          _entry(theme, charEntry, head: false),
        ],
      ],
    );
  }

  Widget _entry(ThemeData theme, DictEntry entry, {required bool head}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              entry.word,
              style: head
                  ? theme.textTheme.titleLarge
                  : theme.textTheme.titleMedium,
            ),
            const SizedBox(width: 8),
            if (entry.pinyin.isNotEmpty)
              Text(
                entry.pinyin,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(entry.explanation, style: theme.textTheme.bodyMedium),
      ],
    );
  }
}
