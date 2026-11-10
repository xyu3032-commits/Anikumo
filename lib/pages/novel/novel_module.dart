import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:anikumo/models/novel_item.dart';
import 'package:anikumo/pages/novel/novel_detail_page.dart';
import 'package:anikumo/pages/novel/novel_diagnostics_page.dart';
import 'package:anikumo/pages/novel/novel_feature_repo_page.dart';
import 'package:anikumo/pages/novel/novel_local_page.dart';
import 'package:anikumo/pages/novel/novel_login_page.dart';
import 'package:anikumo/pages/novel/novel_downloads_page.dart';
import 'package:anikumo/pages/novel/novel_explore_tab.dart';
import 'package:anikumo/pages/novel/novel_main_page.dart';
import 'package:anikumo/pages/novel/novel_reader_page.dart';
import 'package:anikumo/pages/novel/novel_rss_page.dart';
import 'package:anikumo/pages/novel/novel_search_page.dart';
import 'package:anikumo/bean/theme/violet_glass.dart';
import 'package:anikumo/pages/route_error_page.dart';

/// The 小说专区 module (same transition language as manga).
final _novelTransition = CustomTransition(
  duration: const Duration(milliseconds: 260),
  transitionsBuilder: (context, animation, secondaryAnimation, child) {
    final curved = CurvedAnimation(parent: animation, curve: Curves.easeOut);
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.02),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  },
);

final novelModule = createModule(
  path: '/novel',
  register: (c) {
    c
      ..route(
        '/',
        child: (context, state) => const VioletZone(child: NovelMainPage()),
        transition: _novelTransition,
      )
      ..route(
        '/search',
        child: (context, state) => VioletZone(
          child: NovelSearchPage(
            initialQuery: state.arguments is String
                ? state.arguments as String
                : '',
          ),
        ),
        transition: _novelTransition,
      )
      ..route(
        '/source',
        child: (context, state) {
          final args = state.arguments;
          if (args is! String) {
            return const RouteErrorPage(message: '书源参数无效，请返回后重新打开。');
          }
          return VioletZone(child: NovelSourcePage(sourceId: args));
        },
        transition: _novelTransition,
      )
      ..route(
        '/category',
        child: (context, state) {
          final args = state.arguments;
          if (args is! NovelCategoryArgs) {
            return const RouteErrorPage(message: '分类参数无效，请返回后重新打开。');
          }
          return VioletZone(child: NovelCategoryPage(args: args));
        },
        transition: _novelTransition,
      )
      ..route(
        '/detail',
        child: (context, state) {
          final novel = state.arguments;
          if (novel is! NovelItem) {
            return const RouteErrorPage(message: '小说详情参数无效，请返回后重新打开。');
          }
          return VioletZone(child: NovelDetailPage(novel: novel));
        },
        transition: _novelTransition,
      )
      ..route(
        '/diagnostics',
        child: (context, state) =>
            const VioletZone(child: NovelDiagnosticsPage()),
        transition: _novelTransition,
      )
      ..route(
        '/login',
        child: (context, state) {
          final args = state.arguments;
          if (args is! String) {
            return const RouteErrorPage(message: '书源参数无效，请返回后重新打开。');
          }
          return VioletZone(child: NovelLoginPage(sourceId: args));
        },
        transition: _novelTransition,
      )
      ..route(
        '/downloads',
        child: (context, state) =>
            const VioletZone(child: NovelDownloadsPage()),
        transition: _novelTransition,
      )
      ..route(
        '/features',
        child: (context, state) =>
            const VioletZone(child: NovelFeatureRepoPage()),
        transition: _novelTransition,
      )
      ..route(
        '/local',
        child: (context, state) =>
            const VioletZone(child: NovelLocalPage()),
        transition: _novelTransition,
      )
      ..route(
        '/reader',
        child: (context, state) {
          final args = state.arguments;
          if (args is! NovelReaderArgs) {
            return const RouteErrorPage(message: '阅读参数无效，请返回后重新打开。');
          }
          return VioletZone(child: NovelReaderPage(args: args));
        },
        transition: _novelTransition,
      )
      ..route(
        '/rss',
        child: (context, state) {
          final args = state.arguments;
          if (args is! String) {
            return const RouteErrorPage(message: '订阅源参数无效，请返回后重新打开。');
          }
          return VioletZone(child: RssArticlesPage(sourceId: args));
        },
        transition: _novelTransition,
      )
      ..route(
        '/rss-reader',
        child: (context, state) {
          final args = state.arguments;
          if (args is! RssReaderArgs) {
            return const RouteErrorPage(message: '订阅文章参数无效，请返回后重新打开。');
          }
          return VioletZone(child: RssReaderPage(args: args));
        },
        transition: _novelTransition,
      );
  },
);
