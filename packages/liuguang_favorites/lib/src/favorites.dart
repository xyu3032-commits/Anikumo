
import 'package:liuguang_models/liuguang_models.dart'; import 'package:liuguang_storage/liuguang_storage.dart';
class FavoritesRepository {
  final StorageAdapter storage; final String deviceId; static const table='favorites'; static const collectionsTable='collections';
  FavoritesRepository(this.storage,{this.deviceId=''});
  Future<Favorite> add(MediaItem item,{String collectionId='default',String note=''}) async {
    final existing=await get(item.id); final now=DateTime.now();
    final f=Favorite(mediaId:item.id,collectionId:collectionId,note:note,createdAt:existing?.createdAt??now,revision:(existing?.revision??0)+1,updatedAt:now,deviceId:deviceId,mediaSnapshot:item.toJson());
    await storage.put(table,item.id,f.toJson()); return f;
  }
  Future<Favorite?> get(String mediaId) async { final j=await storage.get(table,mediaId); return j==null?null:Favorite.fromJson(j); }
  Future<bool> isFavorite(String mediaId) async => (await get(mediaId))!=null;
  Future<void> remove(String mediaId)=>storage.delete(table,mediaId);
  Future<List<Favorite>> list({String? collectionId}) async { var rows=(await storage.all(table)).map(Favorite.fromJson).toList(); if(collectionId!=null) rows=rows.where((f)=>f.collectionId==collectionId).toList(); rows.sort((a,b)=>b.updatedAt.compareTo(a.updatedAt)); return rows; }
  Future<Collection> createCollection(String name) async { final c=Collection(id:'col-${DateTime.now().microsecondsSinceEpoch}',name:name,createdAt:DateTime.now()); await storage.put(collectionsTable,c.id,c.toJson()); return c; }
  Future<List<Collection>> collections() async => (await storage.all(collectionsTable)).map(Collection.fromJson).toList();
  Future<void> deleteCollection(String id) async { await storage.delete(collectionsTable,id); for(final f in await list(collectionId:id)){ await storage.put(table,f.mediaId,f.copyWith(collectionId:'default',revision:f.revision+1,updatedAt:DateTime.now()).toJson()); } }
}
