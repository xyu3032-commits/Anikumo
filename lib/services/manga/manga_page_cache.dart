import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import 'package:anikumo/services/manga/manga_image_pipeline.dart';

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
    // Batch 87: cap the on-disk page cache tighter (1500 -> 800
    // objects, 14 -> 10 days). 800 pages still covers several
    // chapters of resume-reading headroom, while the worst-case
    // storage footprint roughly halves.
    stalePeriod: const Duration(days: 10),
    maxNrOfCacheObjects: 800,
    // Batch 185: downloads pass the image-magic check
    // before they may enter the store (see
    // MangaImageFileService) — a 200 HTML challenge page
    // is no longer cached as a page for ten days.
    fileService: MangaImageFileService(),
  ),
);
