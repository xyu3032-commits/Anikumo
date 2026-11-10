import 'package:flutter_modular/flutter_modular.dart';
import 'package:anikumo/pages/settings/tmdb/tmdb_settings.dart';

final tmdbModule = createModule(
  path: '/tmdb',
  register: (c) {
    c.route('/', child: (context, state) => const TmdbSettingsPage());
  },
);
