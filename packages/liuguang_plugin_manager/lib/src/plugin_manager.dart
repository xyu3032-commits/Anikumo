
import 'package:liuguang_plugin_api/liuguang_plugin_api.dart';
class PermissionDeniedException implements Exception { final String pluginId; final PluginPermission permission; PermissionDeniedException(this.pluginId,this.permission); @override String toString()=>'PermissionDeniedException: $pluginId lacks ${permissionName(permission)}'; }
class PluginEntry { final PluginManifest manifest; bool enabled; PluginEntry(this.manifest,{this.enabled=true}); }
class PluginManager {
  final String hostApiVersion; final Map<String,PluginEntry> _plugins={};
  PluginManager({this.hostApiVersion='0.1.0'});
  List<PluginEntry> get plugins=>_plugins.values.toList();
  PluginEntry register(PluginManifest manifest){
    if(!versionInRange(hostApiVersion, manifest.apiRange)) throw FormatException('plugin ${manifest.id} apiRange ${manifest.apiRange} incompatible with host $hostApiVersion');
    for(final dep in manifest.dependencies){ if(!_plugins.containsKey(dep)) throw FormatException('plugin ${manifest.id} missing dependency $dep'); }
    final e=PluginEntry(manifest); _plugins[manifest.id]=e; return e;
  }
  void unregister(String id)=>_plugins.remove(id);
  void enable(String id)=>_entry(id).enabled=true;
  void disable(String id)=>_entry(id).enabled=false;
  bool isEnabled(String id)=>_plugins[id]?.enabled??false;
  PluginEntry _entry(String id){ final e=_plugins[id]; if(e==null) throw StateError('plugin not found: $id'); return e; }
  void requirePermission(String pluginId, PluginPermission permission){
    final e=_entry(pluginId); if(!e.enabled) throw StateError('plugin disabled: $pluginId');
    if(!e.manifest.permissions.contains(permission)) throw PermissionDeniedException(pluginId,permission);
  }
  T guard<T>(String pluginId, PluginPermission permission, T Function() action){ requirePermission(pluginId,permission); return action(); }
}
