
import 'package:liuguang_models/liuguang_models.dart'; import 'package:liuguang_storage/liuguang_storage.dart';
class HistoryRepository {
  final StorageAdapter storage; static const table='history';
  HistoryRepository(this.storage);
  String _key(String mediaId,String? episodeId)=>'$mediaId::${episodeId??''}';
  Future<void> record(PlaybackHistory h) async { await storage.put(table,_key(h.mediaId,h.episodeId),h.toJson()); }
  Future<void> updateProgress({required String mediaId,String? episodeId,String title='',required Duration position,required Duration duration,String playerKernelId='',DateTime? at}) async {
    final completed = duration.inMilliseconds>0 && position.inMilliseconds >= (duration.inMilliseconds*0.95).floor();
    await record(PlaybackHistory(mediaId:mediaId,episodeId:episodeId,title:title,position:position,duration:duration,lastPlayedAt:at??DateTime.now(),playerKernelId:playerKernelId,completed:completed));
  }
  Future<PlaybackHistory?> get(String mediaId,{String? episodeId}) async { final j=await storage.get(table,_key(mediaId,episodeId)); return j==null?null:PlaybackHistory.fromJson(j); }
  Future<Duration?> resumePosition(String mediaId,{String? episodeId}) async { final h=await get(mediaId,episodeId:episodeId); if(h==null||h.completed) return null; if(h.position<Duration(seconds:5)) return null; return h.position; }
  Future<List<PlaybackHistory>> list({int limit=50}) async { final rows=(await storage.all(table)).map(PlaybackHistory.fromJson).toList(); rows.sort((a,b)=>b.lastPlayedAt.compareTo(a.lastPlayedAt)); return rows.take(limit).toList(); }
  Future<List<PlaybackHistory>> continueWatching({int limit=20}) async => (await list(limit:200)).where((h)=>!h.completed && h.position>Duration.zero).take(limit).toList();
  Future<void> remove(String mediaId,{String? episodeId})=>storage.delete(table,_key(mediaId,episodeId));
  Future<void> clear()=>storage.clearTable(table);
}
