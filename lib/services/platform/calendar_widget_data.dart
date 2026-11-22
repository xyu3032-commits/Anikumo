/// Batch 284 (#32): shaping for the 今日放送 home-screen
/// widget (CalendarWidgetProvider).
///
/// One display entry: a show title plus its air time when
/// known ('HH:mm' style); anime calendar entries carry
/// no time of day, so their label stays empty.
class CalendarWidgetEntry {
  const CalendarWidgetEntry(this.title, this.timeLabel);

  final String title;
  final String timeLabel;
}

/// Merges today's entries into at most [max] widget
/// lines. Timed entries (film episodes) come first in
/// air-time order — they are the ones with a schedule to
/// keep — then untimed anime titles in source order.
/// A line reads 'HH:mm 标题', or just the title when no
/// time is known. Pure, so the merge is unit-testable.
List<String> calendarWidgetLines({
  required List<CalendarWidgetEntry> entries,
  int max = 4,
}) {
  final timed = [
    for (final e in entries)
      if (e.timeLabel.isNotEmpty) e,
  ]..sort((a, b) => a.timeLabel.compareTo(b.timeLabel));
  final untimed = [
    for (final e in entries)
      if (e.timeLabel.isEmpty) e,
  ];
  return [
    for (final e in [...timed, ...untimed].take(max))
      e.timeLabel.isEmpty ? e.title : '${e.timeLabel} ${e.title}',
  ];
}
