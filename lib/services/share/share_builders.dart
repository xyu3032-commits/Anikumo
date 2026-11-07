import 'package:anikumo/modules/bangumi/bangumi_item.dart';
import 'package:anikumo/services/library/user_library.dart';

/// Builds the plain-text version of a custom list for sharing:
/// a title line, then numbered entries with scores. Plain text goes
/// anywhere — chat apps, notes, forums — without attachments.
String buildListShareText(String listName, List<BangumiItem> items) {
  final buffer = StringBuffer()
    ..writeln('片单「$listName」（共 ${items.length} 部）');
  for (var i = 0; i < items.length; i++) {
    final item = items[i];
    final score =
        item.ratingScore > 0 ? ' · 评分 ${item.ratingScore.toStringAsFixed(1)}' : '';
    buffer.writeln('${i + 1}. ${bangumiDisplayTitle(item)}$score');
  }
  buffer.write('—— 来自 anikumo 我的榜单');
  return buffer.toString();
}

const _weekdayCodes = ['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU'];

/// Builds an iCalendar (.ics) document with one weekly recurring
/// event per show, at 20:00 local floating time, starting from the
/// show's next airing day on or after [fromDate]. Importing the file
/// into any calendar app turns the watchlist into airing reminders.
String buildBangumiCalendarIcs(
  List<({BangumiItem item, int weekday})> shows, {
  required DateTime fromDate,
}) {
  String escape(String text) => text
      .replaceAll('\\', '\\\\')
      .replaceAll(';', '\\;')
      .replaceAll(',', '\\,')
      .replaceAll('\n', ' ');

  String dateStamp(DateTime date) =>
      '${date.year}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}';

  final buffer = StringBuffer()
    ..writeln('BEGIN:VCALENDAR')
    ..writeln('VERSION:2.0')
    ..writeln('PRODID:-//anikumo//bangumi-calendar//CN');
  for (final show in shows) {
    if (show.weekday < 1 || show.weekday > 7) continue;
    var date = DateTime(fromDate.year, fromDate.month, fromDate.day);
    while (date.weekday != show.weekday) {
      date = date.add(const Duration(days: 1));
    }
    buffer
      ..writeln('BEGIN:VEVENT')
      ..writeln('UID:bangumi-${show.item.id}@anikumo')
      ..writeln('DTSTART:${dateStamp(date)}T200000')
      ..writeln('DURATION:PT30M')
      ..writeln(
        'RRULE:FREQ=WEEKLY;BYDAY=${_weekdayCodes[show.weekday - 1]}',
      )
      ..writeln('SUMMARY:${escape(bangumiDisplayTitle(show.item))} 更新')
      ..writeln('END:VEVENT');
  }
  buffer.writeln('END:VCALENDAR');
  return buffer.toString();
}
