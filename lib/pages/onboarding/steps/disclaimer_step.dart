import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'package:anikumo/bean/widget/loading_indicator.dart';
import 'package:anikumo/bean/widget/tonal_card.dart';
import 'package:anikumo/pages/onboarding/onboarding_step_layout.dart';
import 'package:anikumo/services/logging/logger.dart';
import 'package:anikumo/bean/widget/anikumo_icons.dart';

/// First-launch disclaimer (batch 55 polish). The legal
/// text itself is unchanged and still comes verbatim from
/// assets/statements/statements.txt; what changed is the
/// presentation: a three-point summary up top so the gist
/// lands in seconds, the clauses as a numbered list with
/// badges instead of a wall of paragraphs, and the closing
/// "use equals agreement" line as a highlighted note. If
/// the asset's format ever stops matching the numbered
/// layout, rendering falls back to plain paragraphs.
class DisclaimerStep extends StatefulWidget {
  const DisclaimerStep({super.key});

  @override
  State<DisclaimerStep> createState() => _DisclaimerStepState();
}

class _DisclaimerStepState extends State<DisclaimerStep> {
  String? _statementsText;

  @override
  void initState() {
    super.initState();
    _loadStatements();
  }

  Future<void> _loadStatements() async {
    String text;
    try {
      text = await rootBundle.loadString('assets/statements/statements.txt');
    } catch (error, stackTrace) {
      AnikumoLogger().e(
        'Onboarding: failed to load statements',
        error: error,
        stackTrace: stackTrace,
      );
      text = '免责声明加载失败，请退出后重试。';
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _statementsText = text;
    });
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return OnboardingStepLayout(
      leading: const OnboardingStepIcon(icon: AnikumoIcons.waving_hand_rounded),
      title: '欢迎来到 Anikumo',
      child: TonalCard(
        padding: const EdgeInsets.all(24),
        child: _statementsText == null
            ? const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: LoadingIndicator()),
              )
            : _buildContent(context, textTheme),
      ),
    );
  }

  Widget _buildContent(BuildContext context, TextTheme textTheme) {
    final colors = Theme.of(context).colorScheme;
    final parsed = _parseStatements(_statementsText!);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Icon(AnikumoIcons.description_outlined, color: colors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text('免责声明',
                style:
                    textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
          ),
        ]),
        const SizedBox(height: 6),
        Text(
          '开始使用前，请花一分钟读完。',
          style:
              textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
        ),
        const SizedBox(height: 20),
        if (parsed != null) ...[
          _summary(context),
          const SizedBox(height: 24),
          Text(
            '条款全文',
            style: textTheme.labelLarge?.copyWith(
              color: colors.primary,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            parsed.intro,
            style: textTheme.bodyMedium?.copyWith(height: 1.7),
          ),
          const SizedBox(height: 4),
          for (var i = 0; i < parsed.clauses.length; i++) ...[
            if (i > 0)
              Divider(height: 1, color: colors.outlineVariant.withAlpha(120)),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: colors.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '${i + 1}',
                      style: textTheme.labelMedium?.copyWith(
                        color: colors.onPrimaryContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      parsed.clauses[i],
                      style: textTheme.bodyMedium?.copyWith(height: 1.7),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: colors.secondaryContainer.withAlpha(140),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(AnikumoIcons.info_outline_rounded,
                    size: 20, color: colors.onSecondaryContainer),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    parsed.closing,
                    style: textTheme.bodyMedium?.copyWith(
                      height: 1.6,
                      color: colors.onSecondaryContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ] else
          // Fallback: the asset no longer matches the
          // numbered format — show it verbatim, as before.
          for (final paragraph in _statementsText!.trim().split('\n'))
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(paragraph.trim(),
                  style: textTheme.bodyMedium?.copyWith(height: 1.7)),
            ),
      ],
    );
  }

  /// The three points a first-time user actually needs,
  /// faithfully distilled from clauses 1, 7 and 2/3/6.
  Widget _summary(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    const points = [
      (
        AnikumoIcons.code_rounded,
        '免费开源',
        '本软件免费获取和使用；若是付费买来的，请向卖家索赔。',
      ),
      (
        AnikumoIcons.privacy_tip_outlined,
        '不收集个人信息',
        '不会收集、存储或使用你的个人信息。',
      ),
      (
        AnikumoIcons.balance_rounded,
        '合法使用 · 责任自负',
        '仅供学习交流；请遵守法律法规，使用行为与结果由你自行承担。',
      ),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withAlpha(110),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          for (var i = 0; i < points.length; i++) ...[
            if (i > 0)
              Divider(height: 1, color: colors.outlineVariant.withAlpha(120)),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: colors.primaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(points[i].$1,
                        size: 20, color: colors.onPrimaryContainer),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          points[i].$2,
                          style: textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          points[i].$3,
                          style: textTheme.bodySmall?.copyWith(
                            height: 1.5,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ParsedStatements {
  const _ParsedStatements({
    required this.intro,
    required this.clauses,
    required this.closing,
  });

  final String intro;
  final List<String> clauses;
  final String closing;
}

/// Splits statements.txt into intro / numbered clauses /
/// closing line. Returns null when the text does not
/// follow that shape (fewer than three numbered clauses).
_ParsedStatements? _parseStatements(String raw) {
  final lines = raw
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();
  if (lines.length < 5) return null;
  final clausePattern = RegExp(r'^\d+、\s*');
  final clauses = <String>[];
  var closing = '';
  for (final line in lines.skip(1)) {
    if (clausePattern.hasMatch(line)) {
      clauses.add(line.replaceFirst(clausePattern, ''));
    } else {
      closing = line;
    }
  }
  if (clauses.length < 3 || closing.isEmpty) return null;
  return _ParsedStatements(
    intro: lines.first,
    clauses: clauses,
    closing: closing,
  );
}
