
import 'dart:async';
import 'package:liuguang_models/liuguang_models.dart';
import 'package:liuguang_source_sdk/liuguang_source_sdk.dart';
import 'package:liuguang_source_runtime/liuguang_source_runtime.dart';
import 'package:liuguang_metadata/liuguang_metadata.dart';
import 'package:liuguang_search/liuguang_search.dart';
import 'package:liuguang_player_api/liuguang_player_api.dart';
import 'package:liuguang_history/liuguang_history.dart';
import 'package:liuguang_favorites/liuguang_favorites.dart';
import 'package:liuguang_storage/liuguang_storage.dart';
import 'package:liuguang_cache/liuguang_cache.dart';
import 'package:liuguang_plugin_manager/liuguang_plugin_manager.dart';
import 'package:liuguang_sync/liuguang_sync.dart';
import 'package:liuguang_download/liuguang_download.dart';
export 'package:liuguang_models/liuguang_models.dart';
export 'package:liuguang_source_sdk/liuguang_source_sdk.dart';
export 'package:liuguang_player_api/liuguang_player_api.dart';
export 'package:liuguang_sync/liuguang_sync.dart' show SyncEngine, SyncState, SyncStatus;
export 'package:liuguang_download/liuguang_download.dart' show DownloadManager, DownloadTask, DownloadStatus;

enum LiuGuangErrorCode { notInitialized, sourceNotFound, sourceDisabled, playbackFailed, metadataFailed, cancelled, unknown, notEnabled }
class LiuGuangException implements Exception {
  final LiuGuangErrorCode code; final String message; final Object? cause;
  LiuGuangException(this.code,this.message,{this.cause});
  @override String toString()=>'LiuGuangException(${code.name}): $message${cause!=null?' (cause: $cause)':''}';
}
class LiuGuangEngineConfig {
  final StorageAdapter? storage; final String deviceId;
  const LiuGuangEngineConfig({this.storage,this.deviceId=''});
}
class LiuGuangEvent { final String type; final Map<String,dynamic> data; const LiuGuangEvent(this.type,this.data); }

/// In-process facade — the ONLY integration surface. No server, no Flutter.
class LiuGuangMediaEngine {
  final LiuGuangEngineConfig config;
  late final HistoryRepository history;
  late final FavoritesRepository favorites;
  late final SourceRegistry sources;
  late final PlayerRegistry players;
  late final PluginManager plugins;
  final LruCache<String,SearchPage> searchCache=LruCache<String,SearchPage>(maxEntries:64,defaultTtl:Duration(minutes:2));
  final List<MetadataProvider> _metadataProviders=[];
  late final AggregatedSearch _search;
  final _events=StreamController<LiuGuangEvent>.broadcast();
  bool _initialized=false; bool _disposed=false;
  LiuGuangMediaEngine({LiuGuangEngineConfig? config}): config=config??const LiuGuangEngineConfig() {
    final storage=this.config.storage??MemoryStorageAdapter();
    history=HistoryRepository(storage); favorites=FavoritesRepository(storage,deviceId:this.config.deviceId);
    sources=SourceRegistry(); players=PlayerRegistry(); plugins=PluginManager();
    _search=AggregatedSearch(cache:searchCache);
    players.register('memory',()=>InMemoryPlayerEngine(),const PlayerCapabilities());
  }
  Stream<LiuGuangEvent> get events=>_events.stream;
  bool get isInitialized=>_initialized;
  List<MetadataProvider> get metadataProviders=>List.unmodifiable(_metadataProviders);
  MetadataRepository get metadataRepository=>MetadataRepository(_metadataProviders);
  void _requireInit(){ if(!_initialized||_disposed) throw LiuGuangException(LiuGuangErrorCode.notInitialized,'engine not initialized'); }
  Future<void> initialize() async { if(_initialized) return; _initialized=true; _events.add(LiuGuangEvent('initialized',{})); }
  void registerSource(MediaSourceProvider p){ sources.register(p); }
  void registerMetadataProvider(MetadataProvider p){ _metadataProviders.add(p); }
  void registerPlayerKernel(String id, PlayerEngineFactory f, PlayerCapabilities caps){ players.register(id,f,caps); }
  Future<SearchPage> search(SearchRequest request,{SourceCancelToken? cancel}) async { _requireInit(); try{ final page=await _search.search(sources.enabledProviders,request,cancel:cancel); _events.add(LiuGuangEvent('search',{'keyword':request.keyword,'count':page.items.length})); return page; } catch(e){ if(e is LiuGuangException) rethrow; throw LiuGuangException(LiuGuangErrorCode.unknown,'search failed',cause:e); } }
  Future<MediaDetail?> getDetail(String mediaId) async { _requireInit(); Object? last; for(final p in sources.enabledProviders){ try{ final d=await sources.gate.run(p.descriptor.id,()=>p.getDetail(mediaId)); if(d!=null) return d; } catch(e){ last=e; } } if(last!=null) throw LiuGuangException(LiuGuangErrorCode.unknown,'getDetail failed',cause:last); return null; }
  Future<List<Season>> getSeasons(String seriesId) async { _requireInit(); for(final p in sources.enabledProviders){ try{ final s=await sources.gate.run(p.descriptor.id,()=>p.getSeasons(seriesId)); if(s.isNotEmpty) return s; } catch(_){} } return []; }
  Future<List<Episode>> getEpisodes(String seasonId) async { _requireInit(); for(final p in sources.enabledProviders){ try{ final s=await sources.gate.run(p.descriptor.id,()=>p.getEpisodes(seasonId)); if(s.isNotEmpty) return s; } catch(_){} } return []; }
  Future<List<VideoSource>> getPlaybackSources(PlaybackQuery query) async { _requireInit(); final all=<VideoSource>[]; for(final p in sources.enabledProviders){ try{ all.addAll(await sources.gate.run(p.descriptor.id,()=>p.getPlaybackSources(query))); } catch(_){} } return all; }
  PlaybackController createPlaybackController(){ _requireInit(); return PlaybackController(players,resumeResolver:(m,ep)=>history.resumePosition(m,episodeId:ep)); }
  // ---- optional subsystems (sync / download): NOT enabled by default.
  // Calling their entry points without registering throws
  // LiuGuangException(notEnabled) — never a silent fake success.
  SyncEngine? _syncEngine; DownloadManager? _downloadManager;
  SyncEngine? get syncEngine=>_syncEngine;
  DownloadManager? get downloadManager=>_downloadManager;
  bool get syncEnabled=>_syncEngine!=null;
  bool get downloadsEnabled=>_downloadManager!=null;
  void registerSyncEngine(SyncEngine engine){ _syncEngine=engine; }
  void registerDownloadManager(DownloadManager manager){ _downloadManager=manager; }
  SyncEngine requireSync(){ _requireInit(); final e=_syncEngine; if(e==null) throw LiuGuangException(LiuGuangErrorCode.notEnabled,'sync is not enabled: call registerSyncEngine() with a SyncEngine first'); return e; }
  DownloadManager requireDownloads(){ _requireInit(); final m=_downloadManager; if(m==null) throw LiuGuangException(LiuGuangErrorCode.notEnabled,'downloads are not enabled: call registerDownloadManager() with a DownloadManager first'); return m; }
  Future<SyncState> syncNow() async { final state=await requireSync().sync(); _events.add(LiuGuangEvent('sync',{'status':state.status.name,'pushed':state.pushed,'pulled':state.pulled,'conflicts':state.conflicts})); return state; }
  Future<DownloadTask> enqueueDownload({required String url, required String targetPath, Map<String,String> headers=const{}}) async { final t=await requireDownloads().enqueue(url:url,targetPath:targetPath,headers:headers); _events.add(LiuGuangEvent('downloadEnqueued',{'id':t.id,'url':url})); return t; }
  Future<void> startDownload(String id) async { await requireDownloads().start(id); }
  Future<void> dispose() async { _disposed=true; _initialized=false; await _syncEngine?.dispose(); await _downloadManager?.dispose(); await _events.close(); }
}
