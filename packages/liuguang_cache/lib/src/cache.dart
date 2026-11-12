
class CacheStats { int hits=0; int misses=0; int evictions=0; int get size=>0; }
class _Entry<V>{ V value; DateTime expires; int bytes; _Entry(this.value,this.expires,this.bytes); }
class LruCache<K,V> {
  final int maxEntries; final Duration defaultTtl; final Map<K,_Entry<V>> _map={}; final CacheStats _stats=CacheStats(); int _bytes=0;
  LruCache({this.maxEntries=128, this.defaultTtl=const Duration(minutes:5)});
  CacheStats get stats=>_stats; int get length=>_map.length; int get byteSize=>_bytes; double get hitRate{ final t=_stats.hits+_stats.misses; return t==0?0:_stats.hits/t; }
  Map<String,dynamic> statsJson()=>{'hits':_stats.hits,'misses':_stats.misses,'evictions':_stats.evictions,'entries':length,'bytes':_bytes,'hitRate':hitRate};
  V? get(K key){ final e=_map[key]; if(e==null){_stats.misses++; return null;} if(DateTime.now().isAfter(e.expires)){ _bytes-=e.bytes; _map.remove(key); _stats.misses++; return null; } _map.remove(key); _map[key]=e; _stats.hits++; return e.value; }
  void put(K key,V value,{Duration? ttl,int byteSize=0}){ final old=_map.remove(key); if(old!=null) _bytes-=old.bytes; _map[key]=_Entry(value,DateTime.now().add(ttl??defaultTtl),byteSize); _bytes+=byteSize; while(_map.length>maxEntries){ final k=_map.keys.first; _bytes-=_map[k]!.bytes; _map.remove(k); _stats.evictions++; } }
  void remove(K key){ final e=_map.remove(key); if(e!=null) _bytes-=e.bytes; }
  void clear(){ _map.clear(); _bytes=0; }
  bool contains(K key)=> get(key)!=null;
}
