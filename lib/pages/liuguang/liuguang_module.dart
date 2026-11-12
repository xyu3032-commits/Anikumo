import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:liuguang_core/liuguang_core.dart';
import 'package:anikumo/bean/theme/violet_glass.dart';
import 'package:anikumo/pages/liuguang/film_detail_page.dart';
import 'package:anikumo/pages/liuguang/film_cloud_lists_page.dart';
import 'package:anikumo/pages/liuguang/film_discover_tab.dart';
import 'package:anikumo/pages/liuguang/film_history_page.dart';
import 'package:anikumo/pages/liuguang/film_downloads_page.dart';
import 'package:anikumo/pages/liuguang/film_feature_repo_page.dart';
import 'package:anikumo/pages/liuguang/film_main_page.dart';
import 'package:anikumo/pages/liuguang/film_search_page.dart';
import 'package:anikumo/pages/route_error_page.dart';

/// The 影视专区 module (Batch 203), powered by the vendored
/// 流光 LiuGuang engine. Same transition language as the
/// novel/manga zones. The route prefix is '/film' — plain
/// '/video' belongs to the anime zone's player module.
/// Detail / player / downloads routes join in Batches
/// 205–207 as their pages land.
final _filmTransition = CustomTransition(
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

final liuguangModule = createModule(
  path: '/film',
  register: (c) {
    c
      ..route(
        '/',
        child: (context, state) => const VioletZone(child: FilmMainPage()),
        transition: _filmTransition,
      )
      ..route(
        '/search',
        child: (context, state) => VioletZone(
          child: FilmSearchPage(
            initialQuery: state.arguments is String
                ? state.arguments as String
                : '',
          ),
        ),
        transition: _filmTransition,
      )
      ..route(
        '/detail',
        child: (context, state) {
          final args = state.arguments;
          if (args is! MediaItem) {
            return const RouteErrorPage(message: '详情参数无效，请返回后重新打开。');
          }
          return VioletZone(child: FilmDetailPage(item: args));
        },
        transition: _filmTransition,
      )
      // Batch 222: a home rail's 全部 opens the discover
      // wall pre-filtered, as its own page.
      ..route(
        '/all',
        child: (context, state) {
          final args = state.arguments;
          if (args is! FilmAllArgs) {
            return const RouteErrorPage(message: '参数无效，请返回后重新打开。');
          }
          return VioletZone(child: FilmAllPage(args: args));
        },
        transition: _filmTransition,
      )
      // Batch 224: the zone's watch-history page (the home
      // headline's top-right 历史记录 entry).
      ..route(
        '/history',
        child: (context, state) => const VioletZone(child: FilmHistoryPage()),
        transition: _filmTransition,
      )
      // Batch 232: the zone's feature repository.
      ..route(
        '/features',
        child: (context, state) =>
            const VioletZone(child: FilmFeatureRepoPage()),
        transition: _filmTransition,
      )
      // Batch 254: the cloud lists of the connected
      // TMDB / Bangumi accounts.
      ..route(
        '/cloud',
        child: (context, state) =>
            const VioletZone(child: FilmCloudListsPage()),
        transition: _filmTransition,
      )
      // Batch 208: no zone-local player route — playback
      // goes through the shared '/video/' player page.
      ..route(
        '/downloads',
        child: (context, state) => const VioletZone(child: FilmDownloadsPage()),
        transition: _filmTransition,
      );
  },
);
