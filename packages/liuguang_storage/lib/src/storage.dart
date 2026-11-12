
import 'dart:convert'; import 'dart:io';
abstract interface class StorageAdapter {
  Future<void> put(String table,String key,Map<String,dynamic> value);
  Future<Map<String,dynamic>?> get(String table,String key);
  Future<List<Map<String,dynamic>>> all(String table);
  Future<void> delete(String table,String key);
  Future<void> clearTable(String table);
  Future<Map<String,dynamic>> exportAll();
  Future<void> importAll(Map<String,dynamic> data);
}
class MemoryStorageAdapter implements StorageAdapter {
  final Map<String,Map<String,Map<String,dynamic>>> _db={};
  @override Future<void> put(String t,String k,Map<String,dynamic> v) async { _db.putIfAbsent(t,()=>{})[k]=Map.from(v); }
  @override Future<Map<String,dynamic>?> get(String t,String k) async => _db[t]?[k]==null?null:Map.from(_db[t]![k]!);
  @override Future<List<Map<String,dynamic>>> all(String t) async => (_db[t]?.values??[]).map((e)=>Map<String,dynamic>.from(e)).toList();
  @override Future<void> delete(String t,String k) async { _db[t]?.remove(k); }
  @override Future<void> clearTable(String t) async { _db[t]?.clear(); }
  @override Future<Map<String,dynamic>> exportAll() async => {'version':1,'tables':_db.map((k,v)=>MapEntry(k,v.map((kk,vv)=>MapEntry(kk,Map<String,dynamic>.from(vv)))))};
  @override Future<void> importAll(Map<String,dynamic> data) async { if(data['version']!=1) throw FormatException('unsupported export version ${data['version']}'); _db.clear(); final tables=data['tables']; if(tables is Map){ tables.forEach((t,rows){ if(rows is Map){ _db[t.toString()]=rows.map((k,v)=>MapEntry(k.toString(),Map<String,dynamic>.from(v as Map))); } }); } }
}
class JsonFileStorageAdapter implements StorageAdapter {
  final File file; final MemoryStorageAdapter _mem=MemoryStorageAdapter(); bool _loaded=false;
  JsonFileStorageAdapter(String path): file=File(path);
  Future<void> _ensure() async { if(_loaded) return; _loaded=true; if(await file.exists()){ final txt=await file.readAsString(); if(txt.trim().isNotEmpty){ await _mem.importAll(jsonDecode(txt) as Map<String,dynamic>); } } }
  Future<void> _flush() async { await file.parent.create(recursive:true); await file.writeAsString(jsonEncode(await _mem.exportAll())); }
  @override Future<void> put(String t,String k,Map<String,dynamic> v) async { await _ensure(); await _mem.put(t,k,v); await _flush(); }
  @override Future<Map<String,dynamic>?> get(String t,String k) async { await _ensure(); return _mem.get(t,k); }
  @override Future<List<Map<String,dynamic>>> all(String t) async { await _ensure(); return _mem.all(t); }
  @override Future<void> delete(String t,String k) async { await _ensure(); await _mem.delete(t,k); await _flush(); }
  @override Future<void> clearTable(String t) async { await _ensure(); await _mem.clearTable(t); await _flush(); }
  @override Future<Map<String,dynamic>> exportAll() async { await _ensure(); return _mem.exportAll(); }
  @override Future<void> importAll(Map<String,dynamic> d) async { _loaded=true; await _mem.importAll(d); await _flush(); }
}
