part of 'timeline_page.dart';

/// Batch 44: the week selector is no longer a pill TabBar —
/// it is an editorial date strip: a giant day numeral (the
/// real calendar date when the current season is showing)
/// over the weekday and the day's count, with an ink bar
/// under the selected day. It still drives the same
/// TabController, so swiping the day pages and tapping the
/// strip stay in sync.
class _TimelineWeekSelector extends StatelessWidget {
  const _TimelineWeekSelector({
    required this.counts,
    this.todayIndex,
    this.isLoading = false,
    this.weekDates,
  });

  final List<int> counts;
  final int? todayIndex;
  final bool isLoading;

  /// Real dates for the seven days, present only when the
  /// current season is selected (other seasons have no
  /// single calendar week to point at).
  final List<DateTime>? weekDates;

  static const _weekdays = ['一', '二', '三', '四', '五', '六', '日'];

  static double heightFor(TextScaler scaler) =>
      46 + scaler.scale(26) + scaler.scale(15);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final scaler = MediaQuery.textScalerOf(context);
    return LayoutBuilder(builder: (context, constraints) {
      final minTabWidth = (scaler.scale(14) * 2 + 16).clamp(48.0, 112.0);
      final scrollable = constraints.maxWidth - 8 < minTabWidth * 7;
      return TabBar(
        isScrollable: scrollable,
        tabAlignment: scrollable ? TabAlignment.start : TabAlignment.fill,
        dividerHeight: 0,
        indicatorSize: TabBarIndicatorSize.tab,
        indicator: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: colors.primary, width: 3),
          ),
        ),
        labelColor: colors.onSurface,
        unselectedLabelColor: colors.onSurfaceVariant,
        labelPadding: const EdgeInsets.symmetric(horizontal: 4),
        overlayColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.hovered) ||
                    states.contains(WidgetState.focused)
                ? colors.primary.withValues(alpha: .08)
                : null),
        splashBorderRadius: BorderRadius.circular(8),
        tabs: [
          for (var day = 0; day < 7; day++)
            Tab(
              height: heightFor(scaler) - 8,
              child: Semantics(
                label: '星期${_weekdays[day]}'
                    '${day == todayIndex ? '，今天' : ''}'
                    '${isLoading ? '，加载中' : '，${counts[day]}部'}',
                excludeSemantics: true,
                child: SizedBox(
                  width: scrollable ? minTabWidth : null,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        weekDates != null
                            ? '${weekDates![day].day}'
                            : _weekdays[day],
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: day == todayIndex
                              ? colors.primary
                              : null,
                          height: 1,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${day == todayIndex ? '今天' : '周${_weekdays[day]}'}'
                        ' · ${isLoading ? '—' : '${counts[day]}部'}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      );
    });
  }
}
