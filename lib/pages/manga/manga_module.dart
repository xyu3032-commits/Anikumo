import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:anikumo/modules/manga/manga_item.dart';
import 'package:anikumo/pages/manga/manga_categories_page.dart';
import 'package:anikumo/pages/manga/manga_detail_page.dart';
import 'package:anikumo/pages/manga/manga_history_page.dart';
import 'package:anikumo/pages/manga/manga_diagnostics_page.dart';
import 'package:anikumo/pages/manga/manga_login_page.dart';
import 'package:anikumo/pages/manga/manga_explore_page.dart';
import 'package:anikumo/pages/manga/manga_verification_page.dart';
import 'package:anikumo/pages/manga/manga_main_page.dart';
import 'package:anikumo/pages/manga/manga_reader_page.dart';
import 'package:anikumo/pages/manga/manga_search_page.dart';
import 'package:anikumo/pages/manga/manga_settings_page.dart';
import 'package:anikumo/pages/manga/manga_sources_page.dart';
import 'package:anikumo/bean/theme/violet_glass.dart';
import 'package:anikumo/pages/route_error_page.dart';

/// Shared zone transition: a short fade with a gentle upward
/// drift, so entering/leaving manga pages feels fluid and clearly
/// distinct from the anime pages' transitions.
final _mangaTransition = CustomTransition(
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

final mangaModule = createModule(
  path: '/manga',
  register: (c) {
    // Batch 198: the MangaKit verification solver hook
    // (idempotent; also installed on zone entry).
    MangaVerification.install();
    c
      ..route(
        '/',
        child: (context, state) => const VioletZone(child: MangaMainPage()),
        transition: _mangaTransition,
      )
      ..route(
        '/search',
        child: (context, state) => VioletZone(
          child: MangaSearchPage(
            initialQuery: switch (state.arguments) {
              final MangaSearchRouteArgs args => args.query,
              final String query => query,
              _ => '',
            },
            initialTagSearch: state.arguments is MangaSearchRouteArgs &&
                (state.arguments as MangaSearchRouteArgs).tagSearch,
            initialOriginSourceId:
                state.arguments is MangaSearchRouteArgs
                    ? (state.arguments as MangaSearchRouteArgs).originSourceId
                    : null,
          ),
        ),
        transition: _mangaTransition,
      )
      ..route(
        '/source',
        child: (context, state) {
          final args = state.arguments;
          if (args is! String) {
            return const RouteErrorPage(message: '漫画源参数无效，请返回后重新打开。');
          }
          return VioletZone(child: MangaSourcePage(sourceId: args));
        },
        transition: _mangaTransition,
      )
      ..route(
        '/diagnostics',
        child: (context, state) =>
            const VioletZone(child: MangaDiagnosticsPage()),
        transition: _mangaTransition,
      )
      ..route(
        '/login',
        child: (context, state) {
          final args = state.arguments;
          if (args is! String) {
            return const RouteErrorPage(message: '漫画源参数无效，请返回后重新打开。');
          }
          return VioletZone(child: MangaLoginPage(sourceId: args));
        },
        transition: _mangaTransition,
      )
      ..route(
        '/history',
        child: (context, state) =>
            const VioletZone(child: MangaHistoryPage()),
        transition: _mangaTransition,
      )
      ..route(
        '/sources',
        child: (context, state) =>
            const VioletZone(child: MangaSourcesPage()),
        transition: _mangaTransition,
      )
      ..route(
        '/settings',
        child: (context, state) =>
            const VioletZone(child: MangaSettingsPage()),
        transition: _mangaTransition,
      )
      ..route(
        '/category',
        child: (context, state) {
          final args = state.arguments;
          if (args is! MangaCategoryArgs) {
            return const RouteErrorPage(message: '分类参数无效，请返回后重新打开。');
          }
          return VioletZone(child: MangaCategoryPage(args: args));
        },
        transition: _mangaTransition,
      )
      ..route(
        '/detail',
        child: (context, state) {
          final manga = state.arguments;
          if (manga is! MangaItem) {
            return const RouteErrorPage(message: '漫画详情参数无效，请返回后重新打开。');
          }
          return VioletZone(child: MangaDetailPage(manga: manga));
        },
        transition: _mangaTransition,
      )
      ..route(
        '/reader',
        child: (context, state) {
          final args = state.arguments;
          if (args is! MangaReaderArgs) {
            return const RouteErrorPage(message: '阅读参数无效，请返回后重新打开。');
          }
          return VioletZone(child: MangaReaderPage(args: args));
        },
        transition: _mangaTransition,
      );
  },
);
