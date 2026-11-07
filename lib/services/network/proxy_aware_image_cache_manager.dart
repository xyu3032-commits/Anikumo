import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:anikumo/services/network/image_file_service.dart';

class ProxyAwareImageCacheManager extends CacheManager with ImageCacheManager {
  static final ProxyAwareImageCacheManager instance =
      ProxyAwareImageCacheManager._(ImageFileService());

  ProxyAwareImageCacheManager._(this._fileService)
    : super(Config(
        DefaultCacheManager.key,
        stalePeriod: const Duration(days: 30),
        // Batch 23: the flutter_cache_manager default cap
        // is 200 objects — a few manga chapters (page images
        // plus covers) thrash it completely, so covers were
        // constantly re-downloaded. 1500 objects keeps weeks
        // of browsing resident. Same key: the existing
        // on-disk store is kept, only eviction relaxes.
        maxNrOfCacheObjects: 1500,
        fileService: _fileService,
      ));

  final ImageFileService _fileService;

  @override
  Future<void> dispose() async {
    _fileService.close();
    await super.dispose();
  }
}
