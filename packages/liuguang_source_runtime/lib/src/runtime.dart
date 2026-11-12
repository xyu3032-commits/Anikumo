
import 'dart:async'; import 'package:liuguang_models/liuguang_models.dart'; import 'package:liuguang_source_sdk/liuguang_source_sdk.dart';
class RequestGate {
  final int maxConcurrentPerSource; final Duration minInterval; final Map<String,int> _inFlight={}; final Map<String,DateTime> _lastStart={}; final Map<String,List<Completer<void>>> _queues={};
  RequestGate({this.maxConcurrentPerSource=3,this.minInterval=const Duration(milliseconds:20)});
  int inFlight(String sourceId)=>_inFlight[sourceId]??0;
  Future<T> run<T>(String sourceId, Future<T> Function() task) async {
    while((_inFlight[sourceId]??0)>=maxConcurrentPerSource){ final c=Completer<void>(); _queues.putIfAbsent(sourceId,()=>[]).add(c); await c.future; }
    final last=_lastStart[sourceId]; if(last!=null){ final wait=minInterval-DateTime.now().difference(last); if(wait>Duration.zero) await Future.delayed(wait); }
    _inFlight[sourceId]=(_inFlight[sourceId]??0)+1; _lastStart[sourceId]=DateTime.now();
    try{ return await task(); } finally { _inFlight[sourceId]=(_inFlight[sourceId]??1)-1; final q=_queues[sourceId]; if(q!=null&&q.isNotEmpty) q.removeAt(0).complete(); }
  }
}
class SourceRegistry {
  final Map<String,MediaSourceProvider> _sources={}; final Map<String,bool> _enabled={}; final RequestGate gate; final Map<String,Future<dynamic>> _inflight={};
  SourceRegistry({RequestGate? gate}):gate=gate??RequestGate();
  void register(MediaSourceProvider p){ _sources[p.descriptor.id]=p; _enabled.putIfAbsent(p.descriptor.id,()=>true); }
  void unregister(String id){ _sources.remove(id); _enabled.remove(id); }
  List<SourceDescriptor> get descriptors=>_sources.values.map((e)=>e.descriptor).toList();
  List<MediaSourceProvider> get enabledProviders=>_sources.values.where((p)=>_enabled[p.descriptor.id]??true).toList();
  MediaSourceProvider? provider(String id)=>_sources[id];
  void setEnabled(String id,bool enabled){ if(!_sources.containsKey(id)) throw StateError('unknown source $id'); _enabled[id]=enabled; }
  bool isEnabled(String id)=>_enabled[id]??false;
  Future<Map<String,SourceHealth>> healthCheckAll() async { final out=<String,SourceHealth>{}; for(final p in _sources.values){ try{ out[p.descriptor.id]=await p.healthCheck(); } catch(e){ out[p.descriptor.id]=SourceHealth.fail(e.toString()); } } return out; }
  Future<T> deduped<T>(String key, Future<T> Function() task){ final existing=_inflight[key]; if(existing!=null) return existing as Future<T>; final f=task().whenComplete((){ _inflight.remove(key); }); _inflight[key]=f; return f; }
  Future<SearchPage> search(String sourceId, SearchRequest req,{SourceCancelToken? cancel}) async { final p=_sources[sourceId]; if(p==null) throw StateError('unknown source $sourceId'); if(!isEnabled(sourceId)) throw StateError('source disabled $sourceId'); return gate.run(sourceId,()=>p.search(req,cancel:cancel)); }
}
