
enum PluginType { source, player, metadata, search, storage, cache, network, ui, theme, tool }
enum PluginPermission { network, storageRead, storageWrite, clipboard, webview, filesystem }
PluginPermission? permissionFromName(String n)=> PluginPermission.values.where((e)=> e.name==n || (n=='storage.read'&&e==PluginPermission.storageRead)||(n=='storage.write'&&e==PluginPermission.storageWrite)).firstOrNull;
String permissionName(PluginPermission p)=> p==PluginPermission.storageRead?'storage.read':p==PluginPermission.storageWrite?'storage.write':p.name;
class PluginManifest {
  final String id; final String name; final String version; final PluginType type; final String apiRange; final Set<PluginPermission> permissions; final List<String> dependencies; final String entry;
  const PluginManifest({required this.id, required this.name, required this.version, required this.type, this.apiRange='>=0.1.0 <1.0.0', this.permissions=const{}, this.dependencies=const[], this.entry='main'});
  Map<String,dynamic> toJson()=>{'id':id,'name':name,'version':version,'type':type.name,'apiRange':apiRange,'permissions':permissions.map(permissionName).toList(),'dependencies':dependencies,'entry':entry};
  factory PluginManifest.fromJson(Map<String,dynamic> j){
    final errors=validate(j); if(errors.isNotEmpty) throw FormatException(errors.join('; '));
    return PluginManifest(id:j['id'].toString(), name:j['name'].toString(), version:j['version'].toString(), type:PluginType.values.firstWhere((e)=>e.name==j['type']), apiRange:j['apiRange']?.toString()??'>=0.1.0 <1.0.0', permissions:(j['permissions'] as List? ??[]).map((e)=>permissionFromName(e.toString())).whereType<PluginPermission>().toSet(), dependencies:(j['dependencies'] as List? ??[]).map((e)=>e.toString()).toList(), entry:j['entry']?.toString()??'main');
  }
  static List<String> validate(Map<String,dynamic> j){ final errs=<String>[]; if((j['id']?.toString()??'').isEmpty) errs.add('id required'); if((j['name']?.toString()??'').isEmpty) errs.add('name required'); if((j['version']?.toString()??'').isEmpty) errs.add('version required'); if(!PluginType.values.any((e)=>e.name==j['type'])) errs.add('unknown type ${j['type']}'); for(final p in (j['permissions'] as List? ??[])){ if(permissionFromName(p.toString())==null) errs.add('unknown permission $p'); } return errs; }
  bool get isValid => validate(toJson()).isEmpty;
}
bool versionInRange(String version,String range){
  List<int> parse(String v)=> v.split('.').map((e)=>int.tryParse(e.replaceAll(RegExp(r'[^0-9]'),''))??0).toList();
  int cmp(List<int> a,List<int> b){ for(int i=0;i<3;i++){ final d=(i<a.length?a[i]:0).compareTo(i<b.length?b[i]:0); if(d!=0) return d; } return 0; }
  final v=parse(version);
  for(final part in range.trim().split(RegExp(r'\s+'))){ if(part.isEmpty) continue; String op='=='; String ver=part; if(part.startsWith('>=')){op='>=';ver=part.substring(2);} else if(part.startsWith('<=')){op='<=';ver=part.substring(2);} else if(part.startsWith('>')){op='>';ver=part.substring(1);} else if(part.startsWith('<')){op='<';ver=part.substring(1);} else if(part.startsWith('^')){op='^';ver=part.substring(1);}
    final c=cmp(v,parse(ver)); bool ok=true;
    switch(op){ case '>=': ok=c>=0; break; case '<=': ok=c<=0; break; case '>': ok=c>0; break; case '<': ok=c<0; break; case '^': ok=c>=0 && v[0]==parse(ver)[0]; break; default: ok=c==0; }
    if(!ok) return false;
  } return true;
}
