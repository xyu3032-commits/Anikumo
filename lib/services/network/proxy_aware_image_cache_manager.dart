import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:anikumo/services/network/image_file_service.dart';

class ProxyAwareImageCacheManager extends CacheManager with ImageCacheManager {
  static final ProxyAwareImageCacheManager instance =
      ProxyAwareImageCacheManager._(ImageFileService());

  ProxyAwareImageCacheManager._(this._fileService)
    : super(Config(
        DefaultCacheManager.key,
        // Batch 103: tightened 30 days / 1500 objects ->
        // 14 days / 800. The batch-23 bump existed because
        // manga page images thrashed this shared store;
        // since then the manga zone got its own page store
        // (batch 51) and cover store (batch 102), so what
        // remains here — mostly anime art — no longer needs
        // the headroom, and the worst-case disk footprint
        // roughly halves. Same key: the on-disk store is
        // kept, eviction just tightens to the new caps.
        stalePeriod: const Duration(days: 14),
        maxNrOfCacheObjects: 800,
        fileService: _fileService,
      ));

  final ImageFileService _fileService;

  @override
  Future<void> dispose() async {
    _fileService.close();
    await super.dispose();
  }
}
