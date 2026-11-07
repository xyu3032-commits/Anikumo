import 'package:flutter_modular/flutter_modular.dart';
import 'package:anikumo/pages/discover/achievements_page.dart';
import 'package:anikumo/pages/discover/coming_page.dart';
import 'package:anikumo/pages/discover/daily_page.dart';
import 'package:anikumo/pages/discover/discover_page.dart';
import 'package:anikumo/pages/discover/moments_page.dart';
import 'package:anikumo/pages/discover/my_lists_page.dart';
import 'package:anikumo/pages/discover/notes_page.dart';
import 'package:anikumo/pages/discover/random_page.dart';
import 'package:anikumo/pages/discover/rank_page.dart';
import 'package:anikumo/pages/discover/report_page.dart';
import 'package:anikumo/pages/discover/similar_page.dart';
import 'package:anikumo/pages/discover/today_page.dart';
import 'package:anikumo/pages/discover/updates_page.dart';
import 'package:anikumo/pages/discover/watch_stats_page.dart';

final discoverModule = createModule(
  path: '/discover',
  register: (c) {
    c
      ..route(
        '/',
        transition: TransitionType.none,
        child: (context, state) => const DiscoverPage(),
      )
      // Hub zone pages （内容发现 / 我的时光 / 工具箱 entries).
      ..route('/rank', child: (context, state) => const RankPage())
      ..route('/today', child: (context, state) => const TodayPage())
      ..route('/daily', child: (context, state) => const DailyPage())
      ..route('/updates', child: (context, state) => const UpdatesPage())
      ..route('/similar', child: (context, state) => const SimilarPage())
      ..route('/coming', child: (context, state) => const ComingPage())
      ..route('/random', child: (context, state) => const RandomPage())
      ..route('/my-lists', child: (context, state) => const MyListsPage())
      ..route(
        '/watch-stats',
        child: (context, state) => const WatchStatsPage(),
      )
      ..route('/report', child: (context, state) => const ReportPage())
      ..route(
        '/achievements',
        child: (context, state) => const AchievementsPage(),
      )
      ..route('/notes', child: (context, state) => const NotesPage());
      // Batch 55: /glass, /card-style and /backup moved with
      // the toolbox into Settings (/settings/toolbox/*).
  },
);

/// Batch 37: the 时光 tab module (split out of discover).
final momentsModule = createModule(
  path: '/moments',
  register: (c) {
    c.route(
      '/',
      transition: TransitionType.none,
      child: (context, state) => const MomentsPage(),
    );
  },
);
