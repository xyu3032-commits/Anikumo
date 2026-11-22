import 'dart:io';

import 'package:home_widget/home_widget.dart';
import 'package:liuguang_core/liuguang_core.dart';
import 'package:anikumo/request/apis/bangumi_api.dart';
import 'package:anikumo/services/cross_zone/cross_zone_library.dart';
import 'package:anikumo/services/i18n/app_strings.dart';
import 'package:anikumo/services/liuguang/tvmaze_calendar.dart';
import 'package:anikumo/services/liuguang/video_engine.dart';
import 'package:anikumo/services/logging/logger.dart';
import 'package:anikumo/services/platform/calendar_widget_data.dart';

/// Batch 276 (#61): publishes the freshest continue-
/// watching entry to the Android home-screen widget
/// (ContinueWidgetProvider). Runs deferred after
/// startup; Android only, everything failure-silent —
/// a phone without the widget placed simply stores
/// the values.
String _zoneLabel(String zone) => switch (zone) {
      'manga' => '漫画区',
      'novel' => '小说区',
      'film' => '影视区',
      _ => '动漫区',
    };

abstract final class HomeWidgetPublisher {
  static Future<void> publishContinue() async {
    if (!Platform.isAndroid) return;
    try {
      final entries = await CrossZoneLibrary.continueEntries();
      final top = entries.isEmpty ? null : entries.first;
      await HomeWidget.saveWidgetData<String>(
        'hw_title',
        top?.title ?? 'Anikumo',
      );
      await HomeWidget.saveWidgetData<String>(
        'hw_subtitle',
        top == null
            ? S.t('打开 App 继续你的观看')
            : '${S.t(_zoneLabel(top.zone))} · ${top.subtitle}',
      );
      await HomeWidget.updateWidget(
        qualifiedAndroidName: 'com.anikumo.app.ContinueWidgetProvider',
      );
    } catch (e) {
      AnikumoLogger().w('HomeWidget: publish failed', error: e);
    }
  }

  /// Batch 284 (#32): publishes today's schedule to the
  /// calendar widget (CalendarWidgetProvider) — the anime
  /// zone's 今日放送 slice plus today's TVmaze episodes
  /// for favorited series, merged by
  /// [calendarWidgetLines] into at most four lines. Each
  /// source fails silently on its own; the widget keeps
  /// whatever could be gathered.
  static Future<void> publishCalendar() async {
    if (!Platform.isAndroid) return;
    try {
      final entries = <CalendarWidgetEntry>[];
      try {
        final calendar = await BangumiApi.getCalendar();
        final todayIndex = DateTime.now().weekday - 1;
        if (todayIndex < calendar.length) {
          for (final item in calendar[todayIndex]) {
            entries.add(
              CalendarWidgetEntry(
                item.nameCn.isNotEmpty ? item.nameCn : item.name,
                '',
              ),
            );
          }
        }
      } catch (_) {}
      try {
        final engine = await VideoEngineService.instance.engine();
        final favorites = await engine.favorites.list();
        final titles = <String>[];
        for (final favorite in favorites) {
          if (favorite.mediaSnapshot.isEmpty) continue;
          final item = TVSeries.mediaFromJson(favorite.mediaSnapshot);
          if (item.mediaType == MediaType.series) titles.add(item.title);
        }
        if (titles.isNotEmpty) {
          final episodes = await TvmazeCalendar.upcoming(titles: titles, days: 0);
          for (final episode in episodes) {
            entries.add(
              CalendarWidgetEntry(episode.showTitle, episode.airTime),
            );
          }
        }
      } catch (_) {}
      final lines = calendarWidgetLines(entries: entries);
      final now = DateTime.now();
      await HomeWidget.saveWidgetData<String>(
        'cw_title',
        S.f('今日放送 · {}月{}日', [now.month, now.day]),
      );
      await HomeWidget.saveWidgetData<String>(
        'cw_lines',
        lines.isEmpty ? S.t('今天暂无放送安排') : lines.join('\n'),
      );
      await HomeWidget.updateWidget(
        qualifiedAndroidName: 'com.anikumo.app.CalendarWidgetProvider',
      );
    } catch (e) {
      AnikumoLogger().w('HomeWidget: calendar publish failed', error: e);
    }
  }
}
