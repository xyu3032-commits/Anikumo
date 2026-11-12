
import 'dart:async'; import 'package:liuguang_models/liuguang_models.dart';
enum PlaybackStatus { idle, opening, buffering, playing, paused, ended, error }
class PlaybackState { final PlaybackStatus status; final Duration position; final Duration duration; final double speed; final double volume; final bool muted; final String? subtitleId; final String? audioId; final String? errorMessage;
  const PlaybackState({this.status=PlaybackStatus.idle,this.position=Duration.zero,this.duration=Duration.zero,this.speed=1,this.volume=1,this.muted=false,this.subtitleId,this.audioId,this.errorMessage});
  PlaybackState copyWith({PlaybackStatus? status,Duration? position,Duration? duration,double? speed,double? volume,bool? muted,String? subtitleId,String? audioId,String? errorMessage})=>PlaybackState(status:status??this.status,position:position??this.position,duration:duration??this.duration,speed:speed??this.speed,volume:volume??this.volume,muted:muted??this.muted,subtitleId:subtitleId??this.subtitleId,audioId:audioId??this.audioId,errorMessage:errorMessage??this.errorMessage);
}
class PlaybackEvent { final String type; final PlaybackState state; const PlaybackEvent(this.type,this.state); }
class PlayerCapabilities { final bool hdr; final bool hardwareDecode; final bool subtitles; final bool multiAudio; final bool pictureInPicture; final bool backgroundPlay; final Set<String> formats;
  const PlayerCapabilities({this.hdr=false,this.hardwareDecode=false,this.subtitles=true,this.multiAudio=true,this.pictureInPicture=false,this.backgroundPlay=false,this.formats=const{'mp4','hls'}});
  bool supportsFormat(String f)=>formats.contains(f.toLowerCase());
}
class MediaPlaybackRequest { final VideoSource source; final Duration startPosition; final bool autoPlay; const MediaPlaybackRequest({required this.source,this.startPosition=Duration.zero,this.autoPlay=true}); }
class PlayerConfig { final String kernelId; const PlayerConfig({this.kernelId='memory'}); }
abstract interface class PlayerEngine {
  String get kernelId; PlayerCapabilities get capabilities;
  Future<void> initialize(PlayerConfig config);
  Future<void> open(MediaPlaybackRequest request);
  Future<void> play(); Future<void> pause(); Future<void> stop();
  Future<void> seek(Duration position); Future<void> setSpeed(double speed); Future<void> setVolume(double volume); Future<void> setMuted(bool muted);
  Future<void> selectSubtitle(String? trackId); Future<void> selectAudio(String trackId); Future<void> setSubtitleDelay(Duration delay);
  Stream<PlaybackState> get stateStream; Stream<PlaybackEvent> get eventStream; PlaybackState get currentState;
  Future<void> dispose();
}
/// Real in-memory engine: a periodic clock advances position while playing,
/// honoring speed/seek/pause; reaching duration transitions to ended.
class InMemoryPlayerEngine implements PlayerEngine {
  @override final String kernelId; final Duration mediaDuration;
  InMemoryPlayerEngine({this.kernelId='memory', this.mediaDuration=const Duration(minutes:24)});
  PlaybackState _state=const PlaybackState(); Timer? _timer; VideoSource? _source; Duration _subDelay=Duration.zero; bool _disposed=false;
  final _stateCtl=StreamController<PlaybackState>.broadcast(); final _eventCtl=StreamController<PlaybackEvent>.broadcast();
  @override PlayerCapabilities get capabilities=>const PlayerCapabilities(hdr:false,hardwareDecode:false,subtitles:true,multiAudio:true,pictureInPicture:false,backgroundPlay:false,formats:{'mp4','hls','dash','webm'});
  @override PlaybackState get currentState=>_state;
  @override Stream<PlaybackState> get stateStream=>_stateCtl.stream;
  @override Stream<PlaybackEvent> get eventStream=>_eventCtl.stream;
  Duration get subtitleDelay=>_subDelay; VideoSource? get currentSource=>_source;
  void _emit(String type){ if(_disposed) return; _stateCtl.add(_state); _eventCtl.add(PlaybackEvent(type,_state)); }
  void _set(PlaybackState s){ _state=s; }
  @override Future<void> initialize(PlayerConfig config) async { _set(const PlaybackState(status:PlaybackStatus.idle)); _emit('initialized'); }
  @override Future<void> open(MediaPlaybackRequest request) async {
    _source=request.source; _set(PlaybackState(status:PlaybackStatus.opening,duration:mediaDuration,position:request.startPosition)); _emit('opening');
    _set(_state.copyWith(status:request.autoPlay?PlaybackStatus.playing:PlaybackStatus.paused)); _emit('opened'); _syncTimer();
  }
  void _syncTimer(){ _timer?.cancel(); if(_state.status==PlaybackStatus.playing){ _timer=Timer.periodic(const Duration(milliseconds:50),(_){ final next=_state.position+Duration(milliseconds:(50*_state.speed).round()); if(next>=_state.duration){ _set(_state.copyWith(position:_state.duration,status:PlaybackStatus.ended)); _emit('ended'); _timer?.cancel(); } else { _set(_state.copyWith(position:next)); _emit('progress'); } }); } }
  @override Future<void> play() async { if(_state.status==PlaybackStatus.ended) _set(_state.copyWith(position:Duration.zero)); _set(_state.copyWith(status:PlaybackStatus.playing)); _emit('play'); _syncTimer(); }
  @override Future<void> pause() async { _set(_state.copyWith(status:PlaybackStatus.paused)); _emit('pause'); _syncTimer(); }
  @override Future<void> stop() async { _set(_state.copyWith(status:PlaybackStatus.idle,position:Duration.zero)); _emit('stop'); _syncTimer(); }
  @override Future<void> seek(Duration position) async { var p=position; if(p<Duration.zero)p=Duration.zero; if(p>_state.duration)p=_state.duration; _set(_state.copyWith(position:p)); _emit('seek'); }
  @override Future<void> setSpeed(double speed) async { if(speed<=0) throw ArgumentError('speed must be > 0'); _set(_state.copyWith(speed:speed)); _emit('speed'); }
  @override Future<void> setVolume(double volume) async { _set(_state.copyWith(volume:volume.clamp(0,1).toDouble())); _emit('volume'); }
  @override Future<void> setMuted(bool muted) async { _set(_state.copyWith(muted:muted)); _emit('muted'); }
  @override Future<void> selectSubtitle(String? trackId) async { if(!capabilities.subtitles) throw StateError('subtitles unsupported'); _set(_state.copyWith(subtitleId:trackId)); _emit('subtitle'); }
  @override Future<void> selectAudio(String trackId) async { if(!capabilities.multiAudio) throw StateError('multiAudio unsupported'); _set(_state.copyWith(audioId:trackId)); _emit('audio'); }
  @override Future<void> setSubtitleDelay(Duration delay) async { _subDelay=delay; _emit('subtitleDelay'); }
  @override Future<void> dispose() async { _disposed=true; _timer?.cancel(); await _stateCtl.close(); await _eventCtl.close(); }
}
typedef PlayerEngineFactory = PlayerEngine Function();
class PlayerRegistry {
  final Map<String,PlayerEngineFactory> _factories={}; final Map<String,PlayerCapabilities> _caps={};
  void register(String kernelId, PlayerEngineFactory factory, PlayerCapabilities capabilities){ _factories[kernelId]=factory; _caps[kernelId]=capabilities; }
  List<String> get kernelIds=>_factories.keys.toList();
  PlayerEngine create(String kernelId){ final f=_factories[kernelId]; if(f==null) throw StateError('unknown kernel $kernelId'); return f(); }
  PlayerEngine createWithFallback(List<String> preference){ Object? last; for(final id in preference){ try{ return create(id); } catch(e){ last=e; } } throw StateError('no kernel available: $last'); }
  PlayerCapabilities? capabilitiesOf(String id)=>_caps[id];
}
class PlaybackController {
  final PlayerRegistry registry; final Future<Duration?> Function(String mediaId,String? episodeId)? resumeResolver;
  List<VideoSource> _queue=[]; int _index=-1; PlayerEngine? _engine; bool autoNext=true;
  PlaybackController(this.registry,{this.resumeResolver});
  PlayerEngine? get engine=>_engine; int get currentIndex=>_index; List<VideoSource> get queue=>List.unmodifiable(_queue);
  VideoSource? get currentSource=> (_index>=0&&_index<_queue.length)?_queue[_index]:null;
  Future<PlayerEngine> openQueue(List<VideoSource> sources,{int startIndex=0,String kernelPreference='memory',bool resume=true}) async {
    if(sources.isEmpty) throw ArgumentError('empty queue');
    _queue=[...sources]; _index=startIndex;
    _engine=registry.createWithFallback([kernelPreference,'memory']);
    await _engine!.initialize(PlayerConfig(kernelId:kernelPreference));
    Duration start=Duration.zero;
    if(resume&&resumeResolver!=null){ start=await resumeResolver!(_queue[_index].mediaId,_queue[_index].episodeId)??Duration.zero; }
    await _engine!.open(MediaPlaybackRequest(source:_queue[_index],startPosition:start));
    _engine!.eventStream.listen((ev){ if(ev.type=='ended'&&autoNext){ next(); } });
    return _engine!;
  }
  Future<bool> next() async { if(_index+1>=_queue.length) return false; _index++; await _engine!.open(MediaPlaybackRequest(source:_queue[_index])); return true; }
  Future<bool> previous() async { if(_index<=0) return false; _index--; await _engine!.open(MediaPlaybackRequest(source:_queue[_index])); return true; }
  Future<void> dispose() async { await _engine?.dispose(); _engine=null; }
}
