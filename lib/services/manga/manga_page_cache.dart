import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// Batch 51: the manga reader's own page cache.
///
/// Reader pages used to share CachedNetworkImage's default
/// cache manager with every cover in the app — capped at 200
/// objects for the WHOLE app. Heavy reading filled it with
/// full-size pages; browsing covers then evicted the pages
/// (and vice versa), so the more the app was used the more
/// re-download/re-decode churn every scroll hit. The reader
/// now has a dedicated store sized for reading: up to 1500
/// pages kept for two weeks. Covers keep the default store.
final CacheManager mangaPageCacheManager = CacheManager(
  Config(
    'anikumoMangaPages',
    stalePeriod: const Duration(days: 14),
    maxNrOfCacheObjects: 1500,
  ),
);
