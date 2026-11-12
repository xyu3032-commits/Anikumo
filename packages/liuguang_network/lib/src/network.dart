
import 'dart:async'; import 'dart:convert'; import 'dart:io';
class CancelToken { bool _c=false; bool get isCancelled=>_c; void cancel()=>_c=true; void throwIfCancelled(){ if(_c) throw CancelledException(); } }
class CancelledException implements Exception { @override String toString()=>'CancelledException'; }
class NetworkException implements Exception { final String message; final int? statusCode; NetworkException(this.message,{this.statusCode}); @override String toString()=>'NetworkException($statusCode): $message'; }
class HttpResponseData { final int statusCode; final String body; final Map<String,String> headers; const HttpResponseData(this.statusCode,this.body,this.headers); dynamic get jsonBody=>jsonDecode(body); }
abstract interface class HttpTransport { Future<HttpResponseData> send(String method, Uri uri, {Map<String,String> headers=const{}, String? body, Duration timeout=const Duration(seconds:15)}); }
class IoHttpTransport implements HttpTransport {
  final HttpClient _client; IoHttpTransport([HttpClient? c]):_client=c??HttpClient();
  @override Future<HttpResponseData> send(String method, Uri uri, {Map<String,String> headers=const{}, String? body, Duration timeout=const Duration(seconds:15)}) async {
    final req=await _client.openUrl(method,uri).timeout(timeout);
    headers.forEach((k,v)=>req.headers.set(k,v));
    if (body!=null) req.write(body);
    final resp=await req.close().timeout(timeout);
    final text=await resp.transform(utf8.decoder).join();
    final h=<String,String>{}; resp.headers.forEach((n,vs)=>h[n]=vs.join(','));
    return HttpResponseData(resp.statusCode,text,h);
  }
}
class CookieJar {
  final Map<String,Map<String,String>> _store={};
  void setFromHeader(String host, String? header){ if(header==null) return; for(final part in header.split(',')){ final kv=part.split(';').first.trim(); final i=kv.indexOf('='); if(i>0){ _store.putIfAbsent(host,()=>{})[kv.substring(0,i)]=kv.substring(i+1); } } }
  String? cookieHeader(String host){ final m=_store[host]; if(m==null||m.isEmpty) return null; return m.entries.map((e)=>'${e.key}=${e.value}').join('; '); }
  void setCookie(String host,String name,String value)=>_store.putIfAbsent(host,()=>{})[name]=value;
  void clear()=>_store.clear();
}
class LiuGuangHttpClient {
  final HttpTransport transport; final CookieJar cookies; final int maxRetries;
  LiuGuangHttpClient({HttpTransport? transport, CookieJar? cookies, this.maxRetries=2}): transport=transport??IoHttpTransport(), cookies=cookies??CookieJar();
  static String redactHeaders(Map<String,String> h)=> h.map((k,v)=> MapEntry(k, (k.toLowerCase()=='authorization'||k.toLowerCase()=='cookie')?'***':v)).toString();
  Future<HttpResponseData> request(String method, String url, {Map<String,String> headers=const{}, String? body, Duration timeout=const Duration(seconds:15), CancelToken? cancel, bool retry=true}) async {
    final uri=Uri.parse(url); Object? lastErr;
    for(int attempt=0; attempt<=(retry?maxRetries:0); attempt++){
      cancel?.throwIfCancelled();
      try{
        final h={...headers}; final c=cookies.cookieHeader(uri.host); if(c!=null && !h.containsKey('Cookie')) h['Cookie']=c;
        final r=await transport.send(method,uri,headers:h,body:body,timeout:timeout);
        final setCookie=r.headers['set-cookie'] ?? r.headers['Set-Cookie']; if(setCookie!=null) cookies.setFromHeader(uri.host,setCookie);
        if (r.statusCode>=500 && attempt<maxRetries) { lastErr=NetworkException('server error',statusCode:r.statusCode); await Future.delayed(Duration(milliseconds:50*(attempt+1))); continue; }
        if (r.statusCode>=400) throw NetworkException('HTTP ${r.statusCode}',statusCode:r.statusCode);
        return r;
      } on NetworkException { rethrow; } catch(e){ lastErr=e; if(attempt>=maxRetries) break; await Future.delayed(Duration(milliseconds:50*(attempt+1))); }
    }
    throw NetworkException('request failed: $lastErr');
  }
  Future<HttpResponseData> get(String url,{Map<String,String> headers=const{},CancelToken? cancel,Duration timeout=const Duration(seconds:15)})=>request('GET',url,headers:headers,cancel:cancel,timeout:timeout);
  Future<HttpResponseData> post(String url,{Map<String,String> headers=const{},String? body,CancelToken? cancel})=>request('POST',url,headers:headers,body:body,cancel:cancel);
  Future<dynamic> getJson(String url,{Map<String,String> headers=const{},CancelToken? cancel}) async => (await get(url,headers:headers,cancel:cancel)).jsonBody;
}
