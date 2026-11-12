import 'package:flutter_modular/flutter_modular.dart';

import 'package:anikumo/pages/profile/profile_page.dart';
import 'package:anikumo/pages/profile/sync_explainer_page.dart';

/// Batch 257: the user center's pages — 个人信息 and the
/// sync explainer. Reachable from every zone through the
/// top-right avatar button.
final profileModule = createModule(
  path: '/profile',
  register: (c) {
    c
      ..route('/', child: (context, state) => const ProfilePage())
      ..route(
        '/about-sync',
        child: (context, state) => const SyncExplainerPage(),
      );
  },
);
