import 'package:flutter_modular/flutter_modular.dart';
import 'package:anikumo/pages/search/scan_page.dart';
import 'package:anikumo/pages/search/search_controller.dart';
import 'package:anikumo/pages/search/search_page.dart';
import 'package:anikumo/utils/search_parser.dart';

void _provideSearchController(Scoped scoped) {
  scoped.add<SearchPageController>(SearchPageController.new);
}

final searchModule = createModule(
  path: '/search',
  register: (c) {
    c
      ..route(
        '/',
        provide: _provideSearchController,
        child: (context, state) => SearchPage(
          controller: context.read<SearchPageController>(),
          initialQuery: state.uri.queryParameters['query'] ?? '',
        ),
      )
      // Batch 284 (#19): the in-app scanner. Declared
      // before '/:tag' so 'scan' is never read as a tag.
      // The backup page passes arguments 'raw' to get the
      // code's raw text back instead of a dispatched
      // action (it is after a LAN transfer payload).
      ..route(
        '/scan',
        child: (context, state) =>
            ScanPage(rawResultOnly: state.arguments == 'raw'),
      )
      ..route(
        '/:tag',
        provide: _provideSearchController,
        child: (context, state) => SearchPage(
          controller: context.read<SearchPageController>(),
          initialQuery: SearchParser.fromFilterState(SearchFilterState(
              tags: [Uri.decodeComponent(state['tag'] ?? '')])),
        ),
      );
  },
);
