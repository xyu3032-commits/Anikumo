import 'package:flutter_modular/flutter_modular.dart';
import 'package:anikumo/pages/featured/featured_more_page.dart';
import 'package:anikumo/pages/featured/featured_page.dart';
import 'package:anikumo/pages/route_error_page.dart';

final featuredModule = createModule(
  path: '/featured',
  register: (c) {
    c
      ..route(
        '/',
        transition: TransitionType.none,
        child: (context, state) => const FeaturedPage(),
      )
      ..route(
        '/more',
        child: (context, state) {
          final args = state.arguments;
          if (args is! String) {
            return const RouteErrorPage(message: '精选参数无效，请返回后重新打开。');
          }
          return FeaturedMorePage(sectionId: args);
        },
      );
  },
);
