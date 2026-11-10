// moyuan — single-file bundle for Anikumo (QuickJS-class hosts).
// Zero dependencies. No DOM. No Node APIs. No fetch/localStorage assumptions:
// the host injects transport + storage (see tools/build-bundle.mjs
// header and docs/ANIKUMO_INTEGRATION.md for the exact global names).
// Globals after load: MoYuan, Novel, createNovelEngine (JsNovelEngine kept as a deprecated alias).

(function(global){
'use strict';
var __modules = {}; var __cache = {};
function __define(path, factory){ __modules[path] = factory; }
function __normalize(fromPath, rel){
  if (rel.charAt(0) !== '.') return rel;
  var parts = fromPath.split('/'); parts.pop();
  var segs = rel.split('/');
  for (var i = 0; i < segs.length; i++){ var s = segs[i]; if (s === '.' || s === '') continue; if (s === '..') parts.pop(); else parts.push(s); }
  var out = parts.join('/'); if (!/\.js$/.test(out)) out += '.js'; return out;
}
function __load(path){
  if (__cache[path]) return __cache[path].exports;
  var factory = __modules[path]; if (!factory) throw new Error('module not found: ' + path);
  var module = { exports: {} }; __cache[path] = module;
  factory(module, module.exports, function(rel){ return __load(__normalize(path, rel)); });
  return module.exports;
}
__define('src/adapters/AnikumoAdapter.js', function(module, exports, __require){
const { parseSourceArray } = __require('../source/SourceAdapter.js');
// Anikumo (Flutter) adapter — mirrors lib/models/novel_item.dart and
// lib/services/novel/novel_source.dart exactly (JSON shapes):
//   NovelItem    {bookUrl, title, author, coverUrl, intro, kind, lastChapter, wordCount, source, sourceName}
//                id == bookUrl, storageKey == "source::bookUrl"
//   NovelChapter {title, url, webView?}
//   NovelBlock   {type:'text', text} | {type:'image', url, headers}
//   NovelExploreCategory {title, url}
// Method names on the bridge match the Dart NovelSource interface.
// Audio chapters (bookSourceType 1) produce engine blocks {type:'audio'}.
// The Dart NovelBlock model has no audio kind today: by default the bridge
// degrades an audio block to {type:'text', text:url} so the link survives;
// pass {includeAudio:true} to contentToAnikumoBlocks to forward
// {type:'audio', url, headers} verbatim for a host that handles it (the
// current Dart side ignores unknown block types when decoding).
// kind <-> tags correspondence (confirmed semantics):
//   Anikumo's NovelItem.kind IS the classification/tag string — one field
//   carrying every tag, comma-joined. The engine keeps kind (primary
//   category string) and tags[] (array) apart, so the bridge merges on the
//   way out (kind segments + tags, deduplicated, order-stable) and splits
//   on the way in (first segment = primary kind, all segments = tags).
//   No tag is ever dropped in either direction.
//   The search/display headline is always the book TITLE — toAnikumoItem
//   takes title from book.title only, never from kind or any other field.
function splitKindTags(value) {
  if (Array.isArray(value)) return value.flatMap(v => splitKindTags(v));
  return String(value || '').split(/[,，、/；;]+/).map(x => x.trim()).filter(Boolean);
}
function mergeKindTags(book) {
  const out = [];
  const push = (v) => { for (const t of splitKindTags(v)) if (!out.includes(t)) out.push(t); };
  push(book && book.kind);
  push(book && book.tags);
  return out.join(',');
}
function toAnikumoItem(book) {
  if (!book) return null;
  return {
    bookUrl: book.url || book.bookUrl || '', title: book.title || '', author: book.author || '',
    coverUrl: book.cover || book.coverUrl || '', intro: book.description || book.intro || '',
    kind: mergeKindTags(book), lastChapter: book.latestChapter || book.lastChapter || '',
    wordCount: book.wordCount || '', source: book.sourceId || book.source || '', sourceName: book.sourceName || '',
    storageKey: (book.sourceId || book.source || '') + '::' + (book.url || book.bookUrl || ''),
  };
}
function fromAnikumoItem(item) {
  if (!item) return null;
  const url = item.bookUrl || item.url || '';
  const kindTags = splitKindTags(item.kind);
  return {
    id: (item.source || '') + ':' + url, // engine-internal id; url stays the identity inside the source
    title: item.title || '', author: item.author || '', cover: item.coverUrl || '', description: item.intro || '',
    sourceId: item.source || '', sourceName: item.sourceName || '', url,
    latestChapter: item.lastChapter || '', updateTime: item.updateTime || '', wordCount: item.wordCount || '',
    kind: kindTags[0] || '', tags: kindTags, metadata: {},
    _anikumoPassthroughId: url,
  };
}
function toAnikumoChapter(chapter) {
  const out = { title: chapter.title || '', url: chapter.url || '' };
  if (chapter.webView) out.webView = true;
  return out;
}
function fromAnikumoChapter(ch) {
  return { title: ch.title || '', url: ch.url || '', webView: !!ch.webView };
}
function contentToAnikumoBlocks(content, options = {}) {
  if (!content) return [];
  if (Array.isArray(content.blocks) && content.blocks.length) {
    // Batch 184: strict typing — only text becomes text and
    // only image becomes image. Audio passes through only
    // for a host that asked for it; it used to be coerced
    // into a text block carrying the raw URL, and every
    // unknown type fell into the same text default — both
    // put non-content into the reading stream. Unknown
    // types are dropped, never disguised as paragraphs.
    const out = [];
    for (const b of content.blocks) {
      if (!b || typeof b !== 'object') continue;
      if (b.type === 'image') out.push({ type: 'image', url: b.url, headers: b.headers || {} });
      else if (b.type === 'text') out.push({ type: 'text', text: b.text || '' });
      else if (b.type === 'audio' && options.includeAudio) out.push({ type: 'audio', url: b.url, headers: b.headers || {} });
    }
    return out;
  }
  const text = content.text || content.content || '';
  return text.split(/\n{2,}|\n/).map(l => l.trim()).filter(Boolean).map(t => ({ type: 'text', text: t }));
}
// ---- installed-source list migration (novelInstalledSourcesJson) ----
// Anikumo persists its installed book sources as a JSON array of the raw
// Legado definitions (prefs key novelInstalledSourcesJson). The engine's
// registry keeps exactly those raw definitions, so the two lists are the
// same document: export here, paste into Anikumo (or the reverse).
function toAnikumoInstalledJson(engine) {
  return JSON.stringify(engine.sources.exportDefs(), null, 2);
}
function importAnikumoInstalledJson(engine, jsonText) {
  const defs = parseSourceArray(jsonText);
  const reg = engine.sourceManager.registerMany(defs, { replace: true });
  return {
    total: defs.length, imported: reg.registered.length, failed: reg.failures.length,
    registered: reg.registered.map(a => engine.sources.info(a)), failures: reg.failures,
  };
}
function toAnikumoCategory(cat) { return { title: cat.title || '', url: cat.url || '' }; }

// Bridge whose method names/signatures mirror the Dart NovelSource interface.
// All params/returns are plain JSON-shaped values the Dart side can map 1:1.
function createAnikumoBridge(engine) {
  const needSource = (sourceId) => { const a = engine.sources.get(sourceId); if (!a) throw Object.assign(new Error('Source not found: ' + sourceId), { code: 'E_SOURCE_NOT_FOUND' }); return a; };
  return {
    // Dart: Future<List<NovelItem>> search(String key, {int page = 1})
    async search(sourceId, key, page = 1) {
      const items = await needSource(sourceId).search(key, { page });
      for (const b of items) engine._indexBook(b);
      return items.map(toAnikumoItem);
    },
    // Dart: List<NovelExploreCategory> get exploreCategories
    exploreCategories(sourceId) { return needSource(sourceId).exploreCategories().map(toAnikumoCategory); },
    // Dart: Future<List<NovelItem>> explore(NovelExploreCategory category, {int page = 1})
    async explore(sourceId, category, page = 1) {
      const items = await needSource(sourceId).explore({ title: category.title, url: category.url }, { page });
      for (const b of items) engine._indexBook(b);
      return items.map(toAnikumoItem);
    },
    // Dart: Future<NovelItem> bookInfo(NovelItem item)
    async bookInfo(item) {
      const book = fromAnikumoItem(item);
      // The engine keys books by its own id; re-key by source+url identity used here.
      const internal = { ...book, id: engineBookId(engine, book) };
      const info = await engine.getBookInfo(internal, { noCache: false });
      return toAnikumoItem(info);
    },
    // Dart: Future<List<NovelChapter>> chapters(NovelItem item)
    async chapters(item) {
      const book = fromAnikumoItem(item);
      const internal = { ...book, id: engineBookId(engine, book) };
      const chs = await engine.getChapters(internal);
      return chs.map(toAnikumoChapter);
    },
    // Dart: Future<List<NovelBlock>> content(NovelItem item, NovelChapter chapter)
    async content(item, chapter) {
      const book = fromAnikumoItem(item);
      const internal = { ...book, id: engineBookId(engine, book) };
      const chs = await engine.getChapters(internal);
      const match = chs.find(c => c.url === chapter.url) || { ...fromAnikumoChapter(chapter), id: chapter.url, bookId: internal.id, sourceId: internal.sourceId, index: 0 };
      const content = await engine.getChapterContentFor(internal, match);
      // Batch 184: the result also carries the truncation
      // flag (the page cap stopped a longer chapter), so
      // the host can avoid presenting partial content as a
      // completed chapter.
      return {
        blocks: contentToAnikumoBlocks(content),
        truncated: !!(content && content.metadata && content.metadata.truncated),
      };
    },
  };
}
// The engine's search-time id for a book is encodeId(sourceId, url); when the
// Dart side hands us an item that came from this bridge's search, the indexed
// copy is found by url; otherwise derive the same id the adapter would use.
function engineBookId(engine, book) {
  if (engine._bookIndex) for (const b of engine._bookIndex.values()) if (b.url === book.url && b.sourceId === book.sourceId) return b.id;
  return book.id;
}
module.exports.default = { toAnikumoItem, fromAnikumoItem, toAnikumoChapter, fromAnikumoChapter, contentToAnikumoBlocks, toAnikumoCategory, createAnikumoBridge, toAnikumoInstalledJson, importAnikumoInstalledJson, splitKindTags, mergeKindTags };

module.exports.splitKindTags = splitKindTags;
module.exports.mergeKindTags = mergeKindTags;
module.exports.toAnikumoItem = toAnikumoItem;
module.exports.fromAnikumoItem = fromAnikumoItem;
module.exports.toAnikumoChapter = toAnikumoChapter;
module.exports.fromAnikumoChapter = fromAnikumoChapter;
module.exports.contentToAnikumoBlocks = contentToAnikumoBlocks;
module.exports.toAnikumoInstalledJson = toAnikumoInstalledJson;
module.exports.importAnikumoInstalledJson = importAnikumoInstalledJson;
module.exports.toAnikumoCategory = toAnikumoCategory;
module.exports.createAnikumoBridge = createAnikumoBridge;

});
__define('src/adapters/QuickJSAdapter.js', function(module, exports, __require){
const { createNovelEngine } = __require('../core/NovelEngine.js');
// QuickJS adapter: the host (e.g. an Android JS engine) injects globals before
// loading the engine:  novelHostRequest(url, optionsJson) -> Promise<{status,headers,body}>
//                      novelHostStorageGet/Set/Delete/Keys (optional)
// Nothing here touches DOM, Node APIs, fetch or localStorage.
function quickJSRequestFromGlobals(g=globalThis){
  const fn=g.novelHostRequest||g.__novelRequest||null;
  if(!fn) return null;
  return async (url, options={})=>{ const r=await fn(url, JSON.stringify({method:options.method||'GET', headers:options.headers||{}, body:options.body??null})); return typeof r==='string'?JSON.parse(r):r; };
}
// Synchronous host transport for java.ajax & friends in rule JS:
// novelHostRequestSync(url, optionsJson) -> {status,headers,body} | JSON string | raw body string (blocking).
function quickJSSyncRequestFromGlobals(g=globalThis){
  const fn=g.novelHostRequestSync||null;
  if(typeof fn!=='function') return null;
  return (url, options={})=>{ const r=fn(url, JSON.stringify({method:options.method||'GET', headers:options.headers||{}, body:options.body??null})); if(typeof r!=='string') return r; try{ return JSON.parse(r); }catch(e){ return {status:200, headers:{}, body:r, url}; } };
}
function quickJSStorageFromGlobals(g=globalThis){
  if(typeof g.novelHostStorageGet!=='function') return undefined;
  return { get:async k=>g.novelHostStorageGet(k), set:async(k,v)=>g.novelHostStorageSet&&g.novelHostStorageSet(k,v), delete:async k=>g.novelHostStorageDelete&&g.novelHostStorageDelete(k), keys:async()=>{ const r=g.novelHostStorageKeys?await g.novelHostStorageKeys():[]; return typeof r==='string'?JSON.parse(r):r; }, clear:async()=>{} };
}
function createQuickJSEngine(options={}){ const g=options.globals||globalThis; return createNovelEngine({ request: options.request||quickJSRequestFromGlobals(g)||undefined, requestSync: options.requestSync||quickJSSyncRequestFromGlobals(g)||undefined, storage: options.storage||quickJSStorageFromGlobals(g), decodeText: options.decodeText||(g.novelHostDecodeText? (bytes, charset)=>g.novelHostDecodeText(bytes, charset): undefined), ...options }); }
module.exports.default = createQuickJSEngine;

module.exports.quickJSRequestFromGlobals = quickJSRequestFromGlobals;
module.exports.quickJSSyncRequestFromGlobals = quickJSSyncRequestFromGlobals;
module.exports.quickJSStorageFromGlobals = quickJSStorageFromGlobals;
module.exports.createQuickJSEngine = createQuickJSEngine;

});
__define('src/api/BookAPI.js', function(module, exports, __require){
class BookAPI{ constructor(engine){ this.engine=engine; } getBookInfo(bookOrId, options){ return this.engine.getBookInfo(bookOrId, options); } parseUrl(url){ return this.engine.parseUrl(url); } discover(sourceId){ return this.engine.discover(sourceId); } explore(sourceId, category, options){ return this.engine.explore(sourceId, category, options); } bookshelf(){ return this.engine.bookshelf(); } }
module.exports.default = BookAPI;

module.exports.BookAPI = BookAPI;

});
__define('src/api/CacheAPI.js', function(module, exports, __require){
class CacheAPI{ constructor(engine){ this.engine=engine; this.cache=engine.cache; }
  get(k){ return this.cache.get(k); } set(k,v,ttl){ return this.cache.set(k,v,ttl); } has(k){ return this.cache.has(k); } delete(k){ return this.cache.delete(k); }
  clear(){ return this.cache.clear(); } query(p){ return this.cache.query(p); } stats(){ return this.cache.stats(); } exportAll(){ return this.cache.exportAll(); } importAll(o){ return this.cache.importAll(o); } }
module.exports.default = CacheAPI;

module.exports.CacheAPI = CacheAPI;

});
__define('src/api/ChapterAPI.js', function(module, exports, __require){
class ChapterAPI{ constructor(engine){ this.engine=engine; } getChapters(bookOrId, options){ return this.engine.getChapters(bookOrId, options); } getChapterContent(chapterOrId, options){ return this.engine.getChapterContent(chapterOrId, options); } getChapterContentFor(book, chapter, options){ return this.engine.getChapterContentFor(book, chapter, options); } }
module.exports.default = ChapterAPI;

module.exports.ChapterAPI = ChapterAPI;

});
__define('src/api/DownloadAPI.js', function(module, exports, __require){
class DownloadAPI{ constructor(engine){ this.engine=engine; this.manager=engine.downloads; }
  async downloadBook(book, chapters, options){ const chs=chapters||await this.engine.getChapters(book); return this.manager.create(book, chs, options); }
  create(book, chapters, options){ return this.manager.create(book, chapters, options); } get(id){ return this.manager.get(id); } list(){ return this.manager.list(); }
  pause(id){ return this.manager.pause(id); } resume(id){ return this.manager.resume(id); } cancel(id){ return this.manager.cancel(id); } remove(id){ return this.manager.remove(id); } wait(id, t){ return this.manager.wait(id, t); } }
module.exports.default = DownloadAPI;

module.exports.DownloadAPI = DownloadAPI;

});
__define('src/api/SearchAPI.js', function(module, exports, __require){
class SearchAPI{ constructor(engine){ this.engine=engine; } search(keyword, options){ return this.engine.search(keyword, options); } searchPage(keyword, options){ return this.engine.searchEngine.searchPage(keyword, options); } }
module.exports.default = SearchAPI;

module.exports.SearchAPI = SearchAPI;

});
__define('src/api/SourceAPI.js', function(module, exports, __require){
class SourceAPI{ constructor(engine){ this.engine=engine; this.manager=engine.sourceManager; }
  register(source, opts){ return this.manager.register(source, opts); } registerMany(list, opts){ return this.manager.registerMany(list, opts); }
  importFromText(text, opts){ return this.manager.importFromText(text, opts); } importFromUrl(url, opts){ return this.manager.importFromUrl(url, opts); }
  list(){ return this.manager.list(); } get(id){ return this.manager.get(id); } enable(id){ return this.manager.enable(id); } disable(id){ return this.manager.disable(id); }
  remove(id){ return this.manager.remove(id); } edit(id, patch){ return this.manager.edit(id, patch); } search(q){ return this.manager.searchSources(q); }
  validate(source){ return this.manager.validate(source); } test(id, keyword){ return this.manager.testSource(id, keyword); }
  loginForm(id){ return this.manager.loginForm(id); } submitLoginForm(id, values){ return this.manager.submitLoginForm(id, values); }
  importRemote(url, opts){ return this.manager.importRemote(url, opts); }
  backup(){ return this.manager.backup(); } restore(text){ return this.manager.restore(text); } stats(){ return this.manager.stats(); } }
module.exports.default = SourceAPI;

module.exports.SourceAPI = SourceAPI;

});
__define('src/cache/CacheAdapter.js', function(module, exports, __require){
// Cache adapter interface: a StorageAdapter-shaped store used by CacheManager.
// Concrete default is MemoryStorage; persistent adapters come from StorageAdapter.
class CacheAdapter{
  constructor(storage){ this.storage=storage; }
  async get(k){ return this.storage.get('cache:'+k); }
  async set(k,v){ return this.storage.set('cache:'+k, v); }
  async delete(k){ return this.storage.delete('cache:'+k); }
  async keys(){ const ks=await this.storage.keys('cache:'); return ks.map(k=>k.slice(6)); }
}
module.exports.default = CacheAdapter;

module.exports.CacheAdapter = CacheAdapter;

});
__define('src/cache/CacheManager.js', function(module, exports, __require){
const { CacheAdapter } = __require('./CacheAdapter.js');
const { debugLog } = __require('../core/utils.js');
// Two-level cache: an in-memory LRU (default 200 entries, configurable
// via opts.maxEntries / engine config cacheMaxEntries) in front of the
// persistent adapter. The Map's insertion order IS the LRU order: get()
// and set() move the key to the most-recent end, and eviction drops the
// least-recently-used entries (from both levels, as before).
class CacheManager{
  constructor(storageAdapter, opts={}){ this.adapter=new CacheAdapter(storageAdapter); this.ttl=opts.ttl??3600000; this.maxEntries=opts.maxEntries??200; this.maxBytes=opts.maxBytes??5000000; this._mem=new Map(); this._memBytes=0; this._hits=0; this._misses=0; }
  // Reason for maxBytes: 200 chapter-sized strings can pin far more memory
  // than 200 small values; the cap estimates size by string length (key +
  // serialized value). A single oversized entry is kept (evicting it would
  // make set() useless for big chapters) — the cap bounds aggregate growth.
  _estBytes(key, raw){ let n=String(key).length; try{ const v=raw?raw.value:undefined; n+=typeof v==='string'?v.length:(JSON.stringify(v)||'').length; }catch(e){ /* unserializable: count the key only */ } return n; }
  _setMem(key, raw){ const old=this._mem.get(key); if(old!==undefined) this._memBytes-=this._estBytes(key, old); this._mem.delete(key); this._mem.set(key, raw); this._memBytes+=this._estBytes(key, raw); }
  _delMem(key){ const old=this._mem.get(key); if(old!==undefined){ this._memBytes-=this._estBytes(key, old); this._mem.delete(key); } }
  _wrap(value, ttl){ return {value, expires: Date.now()+ (ttl??this.ttl), at: Date.now()}; }
  _touch(key, raw){ this._mem.delete(key); this._mem.set(key, raw); }
  async _evictIfNeeded(){ while(this._mem.size>this.maxEntries||(this._memBytes>this.maxBytes&&this._mem.size>1)){ const k=this._mem.keys().next().value; if(k===undefined) break; this._delMem(k); try{ await this.adapter.delete(k); }catch(e){ debugLog('cache evict persist-delete failed for '+k, e); } } }
  async get(key){
    let raw=this._mem.get(key);
    if(raw!==undefined){ this._touch(key, raw); }
    else { raw=await this.adapter.get(key); if(raw!=null){ try{ raw=JSON.parse(raw); }catch(e){ raw=null; } if(raw){ this._setMem(key, raw); await this._evictIfNeeded(); } } }
    if(!raw){ this._misses++; return null; }
    if(raw.expires && raw.expires<Date.now()){ await this.delete(key); this._misses++; return null; }
    raw.at=Date.now(); this._hits++; return raw.value;
  }
  async set(key, value, ttl){
    const w=this._wrap(value, ttl); this._setMem(key, w);
    try{ await this.adapter.set(key, JSON.stringify(w)); }catch(e){ debugLog('cache persist failed for '+key, e); }
    await this._evictIfNeeded();
  }
  async has(key){ return (await this.get(key))!==null; }
  async delete(key){ this._delMem(key); try{ await this.adapter.delete(key); }catch(e){ debugLog('cache delete failed for '+key, e); } }
  async clear(){ this._mem.clear(); this._memBytes=0; for(const k of await this.adapter.keys()) await this.adapter.delete(k); }
  async query(prefix=''){ const out=[]; for(const k of await this.keys()) if(k.startsWith(prefix)) out.push({key:k, value:await this.get(k)}); return out; }
  async keys(){ const memKeys=[...this._mem.keys()]; const stored=await this.adapter.keys().catch(()=>[]); return [...new Set([...memKeys, ...stored])]; }
  stats(){ return {entries:this._mem.size, bytes:this._memBytes, hits:this._hits, misses:this._misses, ttl:this.ttl, maxEntries:this.maxEntries, maxBytes:this.maxBytes}; }
  async exportAll(){ const out={}; for(const k of await this.keys()){ const v=await this.get(k); if(v!==null) out[k]=v; } return out; }
  async importAll(obj){ for(const [k,v] of Object.entries(obj||{})) await this.set(k,v); return Object.keys(obj||{}).length; }
}
module.exports.default = CacheManager;

module.exports.CacheManager = CacheManager;

});
__define('src/core/ConfigManager.js', function(module, exports, __require){
const DEFAULTS={ timeout:15000, concurrency:5, retries:2, retryDelay:400, cacheTTL:3600000, cacheMaxEntries:200, jsTimeoutMs:5000, userAgent:'MoYuan/1.0', followRedirects:true, maxContentPages:100, maxTocPages:50, webJsHandler:null };
class ConfigManager{
  constructor(init={}){ this._c={...DEFAULTS,...init}; }
  get(k){ return k?this._c[k]:{...this._c}; }
  set(k,v){ if(typeof k==='object') Object.assign(this._c,k); else this._c[k]=v; return this; }
  snapshot(){ return {...this._c}; }
}
module.exports.default = ConfigManager;

module.exports.ConfigManager = ConfigManager;

});
__define('src/core/DebugTools.js', function(module, exports, __require){
const { TraceCollector } = __require('./TraceCollector.js');
const { NovelError, ERR } = __require('./errors.js');

// engine.debug — source debugging built on TraceCollector.
//   debug.debugSource(sourceId, {keyword, sampleChapters})
//     Runs the full chain for ONE source (search -> bookInfo -> chapters ->
//     first N contents; RSS sources: articles -> first article content)
//     and returns a structured report. It never throws for a broken source:
//     the failing stage lands in report.failedAt with the original error.
//   debug.trace(fn) / debug.run(fn)
//     Runs any callback with tracing attached; fn receives (engine,
//     collector). Returns { result, trace } where trace is the
//     TraceCollector (trace.steps / trace.summary()).
class DebugTools {
  constructor(engine) { this.engine = engine; }
  async trace(fn, opts = {}) {
    const { result, trace } = await this.engine.withTrace((collector) => fn(this.engine, collector), opts);
    return { result, trace };
  }
  run(fn, opts = {}) { return this.trace(fn, opts); }
  async debugSource(sourceId, opts = {}) {
    const { keyword = '测试', sampleChapters = 1 } = opts;
    const engine = this.engine;
    const collector = new TraceCollector();
    const started = Date.now();
    const report = { sourceId, sourceName: '', kind: 'book', ok: false, failedAt: null, durationMs: 0, counts: { search: 0, chapters: 0, contentChars: 0 }, steps: collector.steps, summary: null };
    const fail = (stage, err) => {
      report.failedAt = stage;
      if (err) report.error = errObj(err);
      collector.add({ stage, kind: 'conclusion', label: 'failed at ' + stage, error: err || undefined });
    };
    const prev = engine._swapTrace(collector);
    try {
      const adapter = engine.sources.get(sourceId);
      const rss = !adapter && engine.rss ? engine.rss.get(sourceId) : null;
      if (!adapter && !rss) {
        fail('lookup', new NovelError(ERR.SOURCE_NOT_FOUND, 'Source not found: ' + sourceId));
      } else if (rss) {
        report.kind = 'rss'; report.sourceName = rss.name;
        await this._debugRss(rss, report, collector, fail);
      } else {
        report.sourceName = adapter.name;
        await this._debugBook(adapter, report, collector, fail, { keyword, sampleChapters });
      }
    } finally {
      engine._swapTrace(prev);
      report.durationMs = Date.now() - started;
      report.steps = collector.steps;
      report.summary = collector.summary();
    }
    return report;
  }
  async _debugBook(adapter, report, collector, fail, { keyword, sampleChapters }) {
    collector.add({ stage: 'resolve', kind: 'stage', label: 'debug source ' + adapter.name + ' (' + adapter.id + ')' });
    if (adapter.kind === 'webview-html') {
      report.unsupported = true;
      collector.add({ stage: 'resolve', kind: 'conclusion', label: 'webview-html source has no rule surface; the rule engine cannot execute it — render def.html in a WebView host' });
      report.failedAt = 'resolve';
      report.error = { code: ERR.UNSUPPORTED, message: 'WebView HTML page source cannot be executed by the rule engine' };
      return;
    }
    if (adapter.def.type === 3) {
      report.unsupported = true;
      collector.add({ stage: 'resolve', kind: 'conclusion', label: 'bookSourceType 3 (file/video) is not executed by this engine' });
      report.failedAt = 'resolve';
      report.error = { code: ERR.UNSUPPORTED, message: 'bookSourceType 3 (file/video) sources are not supported' };
      return;
    }
    let results = null;
    try { results = await adapter.search(keyword, {}); } catch (e) { fail('search', e); return; }
    report.counts.search = results.length;
    if (!results.length) { fail('search', 'search returned no results for keyword "' + keyword + '"'); return; }
    let book = null;
    try { book = await adapter.bookInfo(results[0]); } catch (e) { fail('bookInfo', e); return; }
    let chapters = null;
    try { chapters = await adapter.chapters(book); } catch (e) { fail('chapters', e); return; }
    report.counts.chapters = chapters.length;
    if (!chapters.length) { fail('chapters', 'chapter list is empty'); return; }
    const n = Math.max(1, sampleChapters | 0);
    for (const ch of chapters.slice(0, n)) {
      try { const c = await adapter.content(book, ch); report.counts.contentChars += (c.text || '').length; }
      catch (e) { fail('content', e); return; }
    }
    report.ok = true;
    collector.add({ stage: 'done', kind: 'conclusion', label: 'full chain ok: search ' + report.counts.search + ', chapters ' + report.counts.chapters + ', content ' + report.counts.contentChars + ' chars' });
  }
  async _debugRss(src, report, collector, fail) {
    collector.add({ stage: 'rss', kind: 'stage', label: 'debug subscription ' + src.name + ' (' + src.id + ')' });
    let articles = null;
    try { articles = await src.articles({}); } catch (e) { fail('rss.articles', e); return; }
    report.counts.articles = articles.length;
    report.counts.search = articles.length;
    if (!articles.length) { fail('rss.articles', 'subscription returned no articles'); return; }
    try { const c = await src.articleContent(articles[0]); report.counts.contentChars = (c.text || '').length; }
    catch (e) { fail('rss.content', e); return; }
    report.ok = true;
    collector.add({ stage: 'done', kind: 'conclusion', label: 'subscription ok: ' + articles.length + ' articles, first content ' + report.counts.contentChars + ' chars' });
  }
}
function errObj(e) { if (!e) return null; return { code: e.code || null, message: e.message || String(e) }; }
module.exports.default = DebugTools;

module.exports.DebugTools = DebugTools;

});
__define('src/core/EventEmitter.js', function(module, exports, __require){
const { debugLog } = __require('./utils.js');
class EventEmitter {
  constructor(){ this._m=new Map(); }
  on(ev,fn){ if(!this._m.has(ev)) this._m.set(ev,[]); this._m.get(ev).push(fn); return ()=>this.off(ev,fn); }
  once(ev,fn){ const w=(...a)=>{ this.off(ev,w); fn(...a); }; return this.on(ev,w); }
  off(ev,fn){ const a=this._m.get(ev); if(a) this._m.set(ev,a.filter(f=>f!==fn)); }
  emit(ev,...args){ for(const f of [...(this._m.get(ev)||[])]){ try{f(...args);}catch(e){ debugLog('event listener error ('+ev+')', e); } } for(const f of [...(this._m.get('*')||[])]){ try{f(ev,...args);}catch(e){ debugLog('event listener error ('+ev+')', e); } } }
  removeAll(){ this._m.clear(); }
}
module.exports.default = EventEmitter;

module.exports.EventEmitter = EventEmitter;

});
__define('src/core/NovelEngine.js', function(module, exports, __require){
const { EventEmitter } = __require('./EventEmitter.js');
const { ConfigManager } = __require('./ConfigManager.js');
const { TaskManager, withTimeout } = __require('./TaskManager.js');
const { NovelError, ERR } = __require('./errors.js');
const { StorageAdapter } = __require('../storage/StorageAdapter.js');
const { CacheManager } = __require('../cache/CacheManager.js');
const { RequestManager } = __require('../network/RequestManager.js');
const { ParserEngine } = __require('../parser/ParserEngine.js');
const { SourceRegistry } = __require('../source/SourceRegistry.js');
const { SourceManager } = __require('../source/SourceManager.js');
const { RssRegistry } = __require('../source/RssAdapter.js');
const { RemoteRepository } = __require('../source/RemoteRepository.js');
const { SearchEngine } = __require('../search/SearchEngine.js');
const { PluginManager } = __require('../plugins/PluginManager.js');
const { DownloadManager } = __require('../download/DownloadManager.js');
const { setJsEvaluator: setJsEvaluatorImpl, setJsTimeoutMs: setJsTimeoutMsImpl } = __require('../parser/JSParser.js');
const { TraceCollector } = __require('./TraceCollector.js');
const { DebugTools } = __require('./DebugTools.js');
const { HealthChecker } = __require('../source/HealthChecker.js');
const { encodeId } = __require('./utils.js');

const ENGINE_VERSION = '1.0.0';

// Central orchestrator. All environment differences are injected here:
//   createNovelEngine({ request, storage, decodeText, config, logger })
// API convention (documented in README): methods return data directly and
// reject with NovelError ({code, message, sourceId}) on failure.
class NovelEngine {
  constructor(options = {}) {
    this.version = ENGINE_VERSION;
    this.config = new ConfigManager(options.config || {});
    setJsTimeoutMsImpl(this.config.get('jsTimeoutMs'));
    this.events = new EventEmitter();
    this.tasks = new TaskManager();
    this.logger = options.logger || console;
    this.storage = StorageAdapter.wrap(options.storage);
    this.cache = new CacheManager(this.storage, { ttl: this.config.get('cacheTTL'), maxEntries: this.config.get('cacheMaxEntries'), maxBytes: this.config.get('cacheMaxBytes') });
    this.requests = new RequestManager({ config: this.config, request: options.request, adapter: options.requestAdapter, decodeText: options.decodeText, headers: options.headers, storage: this.storage, logger: this.logger, trace: (kind, data) => this.traceStep(kind, data) });
    // Synchronous host transport for java.ajax & friends in rule JS:
    // (url, {method, headers, body}) => {status, headers, body, url} | string.
    // Falls back to the QuickJS host global novelHostRequestSync.
    this.requestSync = options.requestSync || null;
    this.jsEvaluator = null;
    if (options.jsEvaluator) this.setJsEvaluator(options.jsEvaluator);
    this.parser = new ParserEngine(this);
    this.sources = new SourceRegistry(this);
    this.sourceManager = new SourceManager(this);
    this.rss = new RssRegistry(this);
    this.remote = new RemoteRepository(this);
    // Host hook for ruleContent.webJs: (url, html, sourceId) => Promise<string>
    this.webJsHandler = options.webJsHandler || null;
    this.searchEngine = new SearchEngine(this);
    this.plugins = new PluginManager(this);
    this.downloads = new DownloadManager(this);
    // Debug tracing + health patrol. _trace is null outside a trace run:
    // every trace hook checks it first, so untraced calls are unaffected.
    this._trace = null;
    this.debug = new DebugTools(this);
    this.health = new HealthChecker(this, options.health || {});
    this._loginInfo = new Map();
    // Per-source variable store (source.get/put, java.get/put,
    // source getVariable/putVariable). One canonical object per
    // source, shared by reference with its adapter, so a value a
    // login script writes (e.g. Jiujiu's ijLine line selection)
    // is what the next search template reads — and a host can
    // seed/harvest the whole map for persistence (B176).
    this._sourceVars = new Map();
    this.bookshelfStore = { engine: this };
    // Facades used by DownloadManager / helpers
    this.chapters = {
      getContentById: async (chapterId, opts = {}) => this.getChapterContent(chapterId, opts),
    };
    if (options.sources) this.sourceManager.registerMany(options.sources, { replace: true });
  }
  // ---- debug tracing plumbing ----
  // traceStep is the single funnel for trace hooks across the engine. With
  // no active collector it returns immediately (near-zero overhead).
  traceStep(kind, data = {}) {
    const c = this._trace;
    if (!c) return null;
    const step = c.add({ kind, ...data });
    this.events.emit('debug:step', step);
    return step;
  }
  _swapTrace(collector) { const prev = this._trace; this._trace = collector || null; return prev; }
  // Runs fn with a TraceCollector attached; fn receives the collector.
  // Returns { result, trace }. Restores any outer collector afterwards, so
  // trace runs nest safely. NOTE: the active collector is a single slot —
  // concurrent traced runs on one engine interleave their steps.
  async withTrace(fn, opts = {}) {
    const collector = opts.collector || new TraceCollector(opts);
    const prev = this._swapTrace(collector);
    if (opts.label) collector.add({ stage: 'run', kind: 'stage', label: opts.label });
    try { const result = await fn(collector); return { result, trace: collector }; }
    finally { this._swapTrace(prev); }
  }
  async traceRun(label, fn) { return this.withTrace(fn, { label }); }
  on(ev, fn) { return this.events.on(ev, fn); }
  once(ev, fn) { return this.events.once(ev, fn); }
  off(ev, fn) { return this.events.off(ev, fn); }
  withTimeout(p, ms, task) { return withTimeout(p, ms, task); }
  setRequest(fn) { this.requests.setRequest(fn); return this; }
  setRequestSync(fn) { this.requestSync = typeof fn === 'function' ? fn : null; return this; }
  setStorage(storage) { this.storage = StorageAdapter.wrap(storage); this.cache = new CacheManager(this.storage, { ttl: this.config.get('cacheTTL'), maxEntries: this.config.get('cacheMaxEntries'), maxBytes: this.config.get('cacheMaxBytes') }); if (this.requests && this.requests.bindCookieStorage) this.requests.bindCookieStorage(this.storage); return this; }
  // Replace the JS rule evaluator: fn(code, scope, lib) => value receives
  // the raw rule code, the scope object and the source jsLib; its return
  // value is used verbatim for every evalJs / evalJsExpression / evalScoped
  // call. The evaluator is process-wide (it models the host's JS engine);
  // pass null to restore the built-in evaluator. With a custom evaluator,
  // JS execution timeouts are the host's responsibility.
  setJsEvaluator(fn) { if (fn != null && typeof fn !== 'function') throw new NovelError(ERR.VALIDATION, 'setJsEvaluator expects a function or null'); setJsEvaluatorImpl(fn || null); this.jsEvaluator = fn || null; return this; }
  setWebJsHandler(fn) { this.webJsHandler = typeof fn === 'function' ? fn : null; return this; }
  setLoginInfo(sourceId, info) { this._loginInfo.set(sourceId, info || {}); }
  loginInfo(sourceId) { return this._loginInfo.get(sourceId) || null; }
  // The canonical per-source variable object (created on first
  // use). Adapters hold this exact reference; hosts seed via
  // setSourceVars (merge, never replace) and harvest via
  // sourceVars/allSourceVars.
  varsFor(sourceId) { let v = this._sourceVars.get(sourceId); if (!v) { v = {}; this._sourceVars.set(sourceId, v); } return v; }
  setSourceVars(sourceId, vars) { const cur = this.varsFor(sourceId); if (vars && typeof vars === 'object') for (const [k, val] of Object.entries(vars)) cur[k] = val; return cur; }
  sourceVars(sourceId) { return this._sourceVars.get(sourceId) || {}; }
  allSourceVars() { const out = {}; for (const [k, v] of this._sourceVars) out[k] = v; return out; }
  createTask(label) { return this.tasks.create(label); }
  cancelTask(id) { this.tasks.abort(id); }
  _sourceFor(book) {
    const src = book && (book.sourceId || book.source);
    const adapter = src ? this.sources.get(src) : null;
    if (!adapter) throw new NovelError(ERR.SOURCE_NOT_FOUND, 'Source not found for book: ' + (src || '(none)'), { sourceId: src || null });
    return adapter;
  }
  async _hooks(stage, payload) { const { value } = await this.plugins.runHook(stage, payload); return value; }
  // ---- public data API ----
  async search(keyword, options = {}) { const out = await this.searchEngine.search(keyword, options); out.results = await this._hooks('afterSearch', out.results); for (const b of out.results) this._indexBook(b); return out; }
  async getBookInfo(bookOrId, options = {}) {
    const book = await this._resolveBook(bookOrId);
    const cacheKey = 'book:' + book.id;
    if (!options.noCache) { const c = await this.cache.get(cacheKey); if (c) return c; }
    const adapter = this._sourceFor(book);
    const info = await adapter.bookInfo(book);
    info.id = book.id; // id stays the search-time identity
    const final = await this._hooks('afterBookInfo', info);
    await this.cache.set(cacheKey, final);
    return final;
  }
  async getChapters(bookOrId, options = {}) {
    const book = await this._resolveBook(bookOrId);
    const cacheKey = 'toc:' + book.id;
    if (!options.noCache) { const c = await this.cache.get(cacheKey); if (c) { this.indexChapters(book, c); return c; } }
    const adapter = this._sourceFor(book);
    if (book.tocUrl && adapter._tocUrls && !adapter._tocUrls.has(book.url)) adapter._tocUrls.set(book.url, book.tocUrl);
    const chs = await adapter.chapters(book);
    this.indexChapters(book, chs);
    await this.cache.set(cacheKey, chs);
    return chs;
  }
  async getChapterContent(chapterOrId, options = {}) {
    let chapter = chapterOrId, book = options.book || null;
    if (typeof chapterOrId === 'string') {
      const cached = this._chapterIndex ? this._chapterIndex.get(chapterOrId) : null;
      if (!cached) throw new NovelError(ERR.CHAPTER_NOT_FOUND, 'Unknown chapter id (pass the chapter object or fetch chapters first): ' + chapterOrId);
      chapter = cached.chapter; book = cached.book;
    }
    if (!book) throw new NovelError(ERR.BOOK_NOT_FOUND, 'getChapterContent needs options.book when given a chapter object without book context — use getChapterContentFor(book, chapter)');
    return this.getChapterContentFor(book, chapter, options);
  }
  async getChapterContentFor(book, chapter, options = {}) {
    const cacheKey = 'content:' + chapter.id;
    if (!options.noCache) { const c = await this.cache.get(cacheKey); if (c) return c; }
    const adapter = this._sourceFor(book);
    let content = await adapter.content(book, chapter);
    content = await this._hooks('afterContent', content);
    await this.cache.set(cacheKey, content);
    return content;
  }
  async _resolveBook(bookOrId) {
    if (bookOrId && typeof bookOrId === 'object') { this._indexBook(bookOrId); return bookOrId; }
    const id = String(bookOrId || '');
    if (this._bookIndex && this._bookIndex.has(id)) return this._bookIndex.get(id);
    // Cache may hold it from an earlier info call
    const cached = await this.cache.get('book:' + id);
    if (cached) return cached;
    throw new NovelError(ERR.BOOK_NOT_FOUND, 'Unknown book id (pass the book object returned by search): ' + id);
  }
  _indexBook(book) {
    if (!book || !book.id) return;
    this._bookIndex = this._bookIndex || new Map(); this._bookIndex.set(book.id, book);
  }
  indexChapters(book, chapters) {
    this._indexBook(book);
    this._chapterIndex = this._chapterIndex || new Map();
    for (const ch of chapters || []) this._chapterIndex.set(ch.id, { book, chapter: ch });
  }
  async discover(sourceId) {
    const adapter = this.sources.get(sourceId);
    if (!adapter) throw new NovelError(ERR.SOURCE_NOT_FOUND, 'Source not found: ' + sourceId);
    return adapter.exploreCategories();
  }
  async explore(sourceId, category, options = {}) {
    const adapter = this.sources.get(sourceId);
    if (!adapter) throw new NovelError(ERR.SOURCE_NOT_FOUND, 'Source not found: ' + sourceId);
    const results = await adapter.explore(category, options);
    for (const b of results) this._indexBook(b);
    return results;
  }
  parseUrl(url) {
    for (const adapter of this.sources.list({ includeDisabled: true })) { const b = adapter.parseUrl(url); if (b) { this._indexBook(b); return { book: b, sourceId: adapter.id }; } }
    return null;
  }
  // ---- bookshelf (storage-backed) ----
  bookshelf() {
    const engine = this;
    return {
      async list() { return engine.storage.getJSON('bookshelf:items', []); },
      async add(book) { const items = await engine.storage.getJSON('bookshelf:items', []); if (!items.some(b => b.id === book.id)) items.push(book); await engine.storage.setJSON('bookshelf:items', items); engine._indexBook(book); return items; },
      async remove(bookId) { const items = (await engine.storage.getJSON('bookshelf:items', [])).filter(b => b.id !== bookId); await engine.storage.setJSON('bookshelf:items', items); return items; },
      async has(bookId) { return (await engine.storage.getJSON('bookshelf:items', [])).some(b => b.id === bookId); },
      async clear() { await engine.storage.setJSON('bookshelf:items', []); return []; },
    };
  }
}
function createNovelEngine(options) { return new NovelEngine(options); }
module.exports.default = NovelEngine;

module.exports.ENGINE_VERSION = ENGINE_VERSION;
module.exports.NovelEngine = NovelEngine;
module.exports.createNovelEngine = createNovelEngine;

});
__define('src/core/TaskManager.js', function(module, exports, __require){
const { debugLog, timerSet, timerClear, hasTimer, noteTimerUnavailable } = __require('./utils.js');
// Cancellable task registry + simple concurrency limiter. Pure JS, no deps.
class TaskManager{
  constructor(){ this._tasks=new Map(); this._seq=0; }
  create(label=''){
    const id='task-'+(++this._seq)+'-'+Date.now().toString(36);
    const ctrl={ id, label, aborted:false, listeners:[], onAbort(fn){ this.listeners.push(fn); }, abort(){ if(this.aborted) return; this.aborted=true; this.listeners.forEach(f=>{try{f();}catch(e){ debugLog('task abort listener error', e); }}); }, throwIfAborted(){ if(this.aborted){ const e=new Error('Task aborted'); e.code='E_ABORTED'; throw e; } } };
    this._tasks.set(id,ctrl); return ctrl;
  }
  abort(id){ const t=this._tasks.get(id); if(t) t.abort(); }
  abortAll(){ for(const t of this._tasks.values()) t.abort(); }
  done(id){ this._tasks.delete(id); }
  list(){ return [...this._tasks.values()].map(t=>({id:t.id,label:t.label,aborted:t.aborted})); }
}
// Run async fns with limited concurrency, preserving order, isolating failures.
async function runPool(items, limit, worker, task){
  const results=new Array(items.length); let idx=0;
  const runners=Array.from({length:Math.max(1,Math.min(limit||5,items.length||1))}, async()=>{
    while(idx<items.length){ if(task) task.throwIfAborted(); const i=idx++; try{ results[i]={status:'fulfilled',value:await worker(items[i],i)}; }catch(e){ results[i]={status:'rejected',reason:e}; } }
  });
  await Promise.all(runners); return results;
}
function delay(ms, task){ return new Promise((res,rej)=>{ const t=timerSet(res,ms); if(t==null){ noteTimerUnavailable('delay'); res(); } if(task) task.onAbort(()=>{ timerClear(t); const e=new Error('Aborted'); e.code='E_ABORTED'; rej(e);}); }); }
function withTimeout(promise, ms, task){
  if(!ms) return promise;
  // Reason: without any timer a deadline cannot be enforced. Rather than
  // throwing ReferenceError on the missing setTimeout, run the promise
  // unbounded (task abort still applies) and state once that timeouts
  // are unavailable in this runtime.
  if(!hasTimer()){
    noteTimerUnavailable('withTimeout');
    if(!task) return promise;
    return Promise.race([promise, new Promise((_,rej)=>{ task.onAbort(()=>rej(Object.assign(new Error('Aborted'),{code:'E_ABORTED'}))); })]);
  }
  return Promise.race([promise, new Promise((_,rej)=>{ const t=timerSet(()=>rej(Object.assign(new Error('Timeout after '+ms+'ms'),{code:'E_TIMEOUT'})),ms); promise.then(()=>timerClear(t),()=>timerClear(t)); if(task) task.onAbort(()=>{timerClear(t); rej(Object.assign(new Error('Aborted'),{code:'E_ABORTED'}));}); })]);
}

module.exports.TaskManager = TaskManager;
module.exports.runPool = runPool;
module.exports.delay = delay;
module.exports.withTimeout = withTimeout;

});
__define('src/core/TraceCollector.js', function(module, exports, __require){
const { debugLog } = __require('./utils.js');
// TraceCollector — rule-level execution tracing for source debugging.
//
// A collector is attached to an engine ONLY while a trace run is active
// (engine.withTrace / engine.debug.*). When no collector is attached every
// trace hook in the engine short-circuits, so normal calls pay ~nothing.
//
// Step shape (all summary fields are hard-truncated, see limits below):
//   { seq, ts, stage, kind, label, rule?, inputSummary?, outputSummary?,
//     excerpt?, durationMs?, error? }
//   kind: 'stage' | 'http' | 'rule' | 'js' | 'branch' | 'conclusion' | 'error'
//   stage: logical phase — 'search', 'ruleSearch', 'ruleBookInfo', 'ruleToc',
//          'ruleContent', 'network', 'rss', 'health', ...
//
// Hard limits (a debug run must never blow up memory on a hostile page):
//   - at most maxSteps steps kept (default 500); older steps are dropped
//     and counted in `dropped`
//   - input/output summaries truncated to 800 chars
//   - response body excerpts truncated to 1500 chars (whitespace collapsed)
//   - rule text truncated to 200 chars (JS code to 120)
//   - error text truncated to 1000 chars
const TRACE_LIMITS = { maxSteps: 500, summary: 800, excerpt: 1500, rule: 200, jsRule: 120, error: 1000 };

function squashWs(s) { return String(s == null ? '' : s).replace(/\s+/g, ' ').trim(); }
function truncate(s, max) {
  const t = String(s == null ? '' : s);
  if (t.length <= max) return t;
  return t.slice(0, Math.max(0, max - 12)) + '…(+' + (t.length - max + 12) + ')';
}
// Compact one-line summary of an arbitrary value (page body, rule result,
// element node, JSON value...). Never walks more than a few nodes.
function summarizeValue(value, max = TRACE_LIMITS.summary) {
  if (value == null) return '';
  if (typeof value === 'string') return truncate(squashWs(value) + (value.length > 40 ? ' [len ' + value.length + ']' : ''), max);
  if (typeof value === 'number' || typeof value === 'boolean') return String(value);
  if (Array.isArray(value)) {
    const first = value.length ? summarizeValue(value[0], 120) : '';
    return truncate('array(' + value.length + ')' + (first ? ' first: ' + first : ''), max);
  }
  if (typeof value === 'object') {
    if (value.type === 'element') {
      const text = elementText(value, 120);
      return truncate('element <' + (value.tag || '?') + '> "' + squashWs(text) + '"', max);
    }
    let json = '';
    try { json = JSON.stringify(value); } catch (e) { json = String(value); }
    return truncate(squashWs(json), max);
  }
  return truncate(squashWs(String(value)), max);
}
function elementText(node, cap) {
  let out = '';
  const walk = (n) => {
    if (!n || out.length >= cap) return;
    if (n.type === 'text') { out += n.text || ''; return; }
    for (const c of n.children || []) { walk(c); if (out.length >= cap) return; }
  };
  walk(node);
  return out.slice(0, cap);
}
// Excerpt of a raw response body: whitespace collapsed, hard cap.
function bodyExcerpt(body, max = TRACE_LIMITS.excerpt) { return truncate(squashWs(body), max); }
function errorText(e) {
  if (e == null) return '';
  if (typeof e === 'string') return e;
  const msg = e.message || String(e);
  return e.code ? e.code + ' ' + msg : msg;
}

class TraceCollector {
  constructor(opts = {}) {
    this.maxSteps = opts.maxSteps || TRACE_LIMITS.maxSteps;
    this.onStep = typeof opts.onStep === 'function' ? opts.onStep : null;
    this.steps = [];
    this.dropped = 0;
    this.seq = 0;
    this.startedAt = Date.now();
  }
  add(step = {}) {
    const kind = step.kind || 'step';
    const s = {
      seq: ++this.seq,
      ts: Date.now(),
      stage: step.stage || 'misc',
      kind,
      label: step.label ? truncate(squashWs(step.label), 200) : '',
    };
    if (step.rule != null && step.rule !== '') s.rule = truncate(squashWs(step.rule), kind === 'js' ? TRACE_LIMITS.jsRule : TRACE_LIMITS.rule);
    if (step.inputSummary != null && step.inputSummary !== '') s.inputSummary = summarizeValue(step.inputSummary);
    if (step.outputSummary != null && step.outputSummary !== '') s.outputSummary = summarizeValue(step.outputSummary);
    if (step.excerpt != null && step.excerpt !== '') s.excerpt = bodyExcerpt(step.excerpt);
    if (step.durationMs != null) s.durationMs = Math.max(0, Math.round(step.durationMs));
    if (step.error != null && step.error !== '') s.error = truncate(squashWs(errorText(step.error)), TRACE_LIMITS.error);
    if (this.steps.length >= this.maxSteps) { this.steps.shift(); this.dropped++; }
    this.steps.push(s);
    if (this.onStep) { try { this.onStep(s); } catch (e) { debugLog('trace onStep error', e); } }
    return s;
  }
  summary() {
    const byStage = {};
    for (const s of this.steps) byStage[s.stage] = (byStage[s.stage] || 0) + 1;
    const errors = this.steps.filter(s => s.error).map(s => ({ seq: s.seq, stage: s.stage, kind: s.kind, label: s.label, error: s.error }));
    const last = this.steps.length ? this.steps[this.steps.length - 1].ts : Date.now();
    return {
      totalSteps: this.seq,
      keptSteps: this.steps.length,
      dropped: this.dropped,
      durationMs: Math.max(0, last - this.startedAt),
      byStage,
      errors,
    };
  }
}
module.exports.default = TraceCollector;

module.exports.TRACE_LIMITS = TRACE_LIMITS;
module.exports.squashWs = squashWs;
module.exports.truncate = truncate;
module.exports.summarizeValue = summarizeValue;
module.exports.bodyExcerpt = bodyExcerpt;
module.exports.errorText = errorText;
module.exports.TraceCollector = TraceCollector;

});
__define('src/core/errors.js', function(module, exports, __require){
class NovelError extends Error {
  constructor(code,message,opts={}){ super(message); this.name='NovelError'; this.code=code; this.sourceId=opts.sourceId||null; this.cause=opts.cause||null; this.details=opts.details||null; }
  toJSON(){ return {name:this.name,code:this.code,message:this.message,sourceId:this.sourceId,details:this.details}; }
}
const ERR={ NETWORK:'E_NETWORK', TIMEOUT:'E_TIMEOUT', ABORTED:'E_ABORTED', PARSE:'E_PARSE', HTTP:'E_HTTP', SOURCE_NOT_FOUND:'E_SOURCE_NOT_FOUND', SOURCE_INVALID:'E_SOURCE_INVALID', BOOK_NOT_FOUND:'E_BOOK_NOT_FOUND', CHAPTER_NOT_FOUND:'E_CHAPTER_NOT_FOUND', PLUGIN:'E_PLUGIN', STORAGE:'E_STORAGE', UNSUPPORTED:'E_UNSUPPORTED', VALIDATION:'E_VALIDATION', TEMPLATE:'E_TEMPLATE', DECODE:'E_DECODE' };
function wrapError(e,code,msg){ if(e instanceof NovelError) return e; return new NovelError(code||ERR.PARSE, msg||(e&&e.message)||String(e), {cause:e}); }

module.exports.NovelError = NovelError;
module.exports.ERR = ERR;
module.exports.wrapError = wrapError;

});
__define('src/core/gbk-table-data.js', function(module, exports, __require){
// GENERATED by tools/gen-gbk-table.mjs — do not edit by hand.
// WHATWG GBK decode index as base64 of UTF-16LE code points
// (23940 entries, 23940 mapped). Regenerate: node tools/gen-gbk-table.mjs
const GBK_TABLE_B64 =
  'Ak4ETgVOBk4PThJOF04fTiBOIU4jTiZOKU4uTi9OMU4zTjVON048TkBOQU5CTkRORk5KTlFOVU5XTlpOW05iTmNOZE5lTmdOaE5q' +
  'TmtObE5tTm5Ob05yTnROdU52TndOeE55TnpOe058Tn1Of06AToFOgk6DToROhU6HTopOkE6WTpdOmU6cTp1Onk6jTqpOr06wTrFO' +
  'tE62TrdOuE65TrxOvU6+TshOzE7PTtBO0k7aTttO3E7gTuJO5k7nTulO7U7uTu9O8U70TvhO+U76TvxO/k4ATwJPA08ETwVPBk8H' +
  'TwhPC08MTxJPE08UTxVPFk8cTx1PIU8jTyhPKU8sTy1PLk8xTzNPNU83TzlPO08+Tz9PQE9BT0JPRE9FT0dPSE9JT0pPS09MT1JP' +
  'VE9WT2FPYk9mT2hPak9rT21Pbk9xT3JPdU93T3hPeU96T31PgE+BT4JPhU+GT4dPik+MT45PkE+ST5NPlU+WT5hPmU+aT5xPnk+f' +
  'T6FPok+kT6tPrU+wT7FPsk+zT7RPtk+3T7hPuU+6T7tPvE+9T75PwE/BT8JPxk/HT8hPyU/LT8xPzU/ST9NP1E/VT9ZP2U/bT+BP' +
  '4k/kT+VP50/rT+xP8E/yT/RP9U/2T/dP+U/7T/xP/U//TwBQAVACUANQBFAFUAZQB1AIUAlQClALUA5QEFARUBNQFVAWUBdQG1Ad' +
  'UB5QIFAiUCNQJFAnUCtQL1AwUDFQMlAzUDRQNVA2UDdQOFA5UDtQPVA/UEBQQVBCUERQRVBGUElQSlBLUE1QUFBRUFJQU1BUUFZQ' +
  'V1BYUFlQW1BdUF5QX1BgUGFQYlBjUGRQZlBnUGhQaVBqUGtQbVBuUG9QcFBxUHJQc1B0UHVQeFB5UHpQfFB9UIFQglCDUIRQhlCH' +
  'UIlQilCLUIxQjlCPUJBQkVCSUJNQlFCVUJZQl1CYUJlQmlCbUJxQnVCeUJ9QoFChUKJQpFCmUKpQq1CtUK5Qr1CwULFQs1C0ULVQ' +
  'tlC3ULhQuVC8UL1QvlC/UMBQwVDCUMNQxFDFUMZQx1DIUMlQylDLUMxQzVDOUNBQ0VDSUNNQ1FDVUNdQ2FDZUNtQ3FDdUN5Q31Dg' +
  'UOFQ4lDjUORQ5VDoUOlQ6lDrUO9Q8FDxUPJQ9FD2UPdQ+FD5UPpQ/FD9UP5Q/1AAUQFRAlEDUQRRBVEIUQlRClEMUQ1RDlEPURBR' +
  'EVETURRRFVEWURdRGFEZURpRG1EcUR1RHlEfUSBRIlEjUSRRJVEmUSdRKFEpUSpRK1EsUS1RLlEvUTBRMVEyUTNRNFE1UTZRN1E4' +
  'UTlROlE7UTxRPVE+UUJRR1FKUUxRTlFPUVBRUlFTUVdRWFFZUVtRXVFeUV9RYFFhUWNRZFFmUWdRaVFqUW9RclF6UX5Rf1GDUYRR' +
  'hlGHUYpRi1GOUY9RkFGRUZNRlFGYUZpRnVGeUZ9RoVGjUaZRp1GoUalRqlGtUa5RtFG4UblRulG+Ub9RwVHCUcNRxVHIUcpRzVHO' +
  'UdBR0lHTUdRR1VHWUddR2FHZUdpR3FHeUd9R4lHjUeVR5lHnUehR6VHqUexR7lHxUfJR9FH3Uf5RBFIFUglSC1IMUg9SEFITUhRS' +
  'FVIcUh5SH1IhUiJSI1IlUiZSJ1IqUixSL1IxUjJSNFI1UjxSPlJEUkVSRlJHUkhSSVJLUk5ST1JSUlNSVVJXUlhSWVJaUltSXVJf' +
  'UmBSYlJjUmRSZlJoUmtSbFJtUm5ScFJxUnNSdFJ1UnZSd1J4UnlSelJ7UnxSflKAUoNShFKFUoZSh1KJUopSi1KMUo1SjlKPUpFS' +
  'klKUUpVSllKXUphSmVKaUpxSpFKlUqZSp1KuUq9SsFK0UrVStlK3UrhSuVK6UrtSvFK9UsBSwVLCUsRSxVLGUshSylLMUs1SzlLP' +
  'UtFS01LUUtVS11LZUtpS21LcUt1S3lLgUuFS4lLjUuVS5lLnUuhS6VLqUutS7FLtUu5S71LxUvJS81L0UvVS9lL3UvhS+1L8Uv1S' +
  'AVMCUwNTBFMHUwlTClMLUwxTDlMRUxJTE1MUUxhTG1McUx5TH1MiUyRTJVMnUyhTKVMrUyxTLVMvUzBTMVMyUzNTNFM1UzZTN1M4' +
  'UzxTPVNAU0JTRFNGU0tTTFNNU1BTVFNYU1lTW1NdU2VTaFNqU2xTbVNyU3ZTeVN7U3xTfVN+U4BTgVODU4dTiFOKU45Tj1OQU5FT' +
  'klOTU5RTllOXU5lTm1OcU55ToFOhU6RTp1OqU6tTrFOtU69TsFOxU7JTs1O0U7VTt1O4U7lTulO8U71TvlPAU8NTxFPFU8ZTx1PO' +
  'U89T0FPSU9NT1VPaU9xT3VPeU+FT4lPnU/RT+lP+U/9TAFQCVAVUB1QLVBRUGFQZVBpUHFQiVCRUJVQqVDBUM1Q2VDdUOlQ9VD9U' +
  'QVRCVERURVRHVElUTFRNVE5UT1RRVFpUXVReVF9UYFRhVGNUZVRnVGlUalRrVGxUbVRuVG9UcFR0VHlUelR+VH9UgVSDVIVUh1SI' +
  'VIlUilSNVJFUk1SXVJhUnFSeVJ9UoFShVKJUpVSuVLBUslS1VLZUt1S5VLpUvFS+VMNUxVTKVMtU1lTYVNtU4FThVOJU41TkVOtU' +
  '7FTvVPBU8VT0VPVU9lT3VPhU+VT7VP5UAFUCVQNVBFUFVQhVClULVQxVDVUOVRJVE1UVVRZVF1UYVRlVGlUcVR1VHlUfVSFVJVUm' +
  'VShVKVUrVS1VMlU0VTVVNlU4VTlVOlU7VT1VQFVCVUVVR1VIVUtVTFVNVU5VT1VRVVJVU1VUVVdVWFVZVVpVW1VdVV5VX1VgVWJV' +
  'Y1VoVWlVa1VvVXBVcVVyVXNVdFV5VXpVfVV/VYVVhlWMVY1VjlWQVZJVk1WVVZZVl1WaVZtVnlWgVaFVolWjVaRVpVWmVahVqVWq' +
  'VatVrFWtVa5Vr1WwVbJVtFW2VbhVulW8Vb9VwFXBVcJVw1XGVcdVyFXKVctVzlXPVdBV1VXXVdhV2VXaVdtV3lXgVeJV51XpVe1V' +
  '7lXwVfFV9FX2VfhV+VX6VftV/FX/VQJWA1YEVgVWBlYHVgpWC1YNVhBWEVYSVhNWFFYVVhZWF1YZVhpWHFYdViBWIVYiViVWJlYo' +
  'VilWKlYrVi5WL1YwVjNWNVY3VjhWOlY8Vj1WPlZAVkFWQlZDVkRWRVZGVkdWSFZJVkpWS1ZPVlBWUVZSVlNWVVZWVlpWW1ZdVl5W' +
  'X1ZgVmFWY1ZlVmZWZ1ZtVm5Wb1ZwVnJWc1Z0VnVWd1Z4VnlWelZ9Vn5Wf1aAVoFWglaDVoRWh1aIVolWilaLVoxWjVaQVpFWklaU' +
  'VpVWllaXVphWmVaaVptWnFadVp5Wn1agVqFWolakVqVWplanVqhWqVaqVqtWrFatVq5WsFaxVrJWs1a0VrVWtla4VrlWula7Vr1W' +
  'vla/VsBWwVbCVsNWxFbFVsZWx1bIVslWy1bMVs1WzlbPVtBW0VbSVtNW1VbWVthW2VbcVuNW5VbmVudW6FbpVupW7FbuVu9W8lbz' +
  'VvZW91b4VvtW/FYAVwFXAlcFVwdXC1cMVw1XDlcPVxBXEVcSVxNXFFcVVxZXF1cYVxlXGlcbVx1XHlcgVyFXIlckVyVXJlcnVytX' +
  'MVcyVzRXNVc2VzdXOFc8Vz1XP1dBV0NXRFdFV0ZXSFdJV0tXUldTV1RXVVdWV1hXWVdiV2NXZVdnV2xXbldwV3FXcld0V3VXeFd5' +
  'V3pXfVd+V39XgFeBV4dXiFeJV4pXjVeOV49XkFeRV5RXlVeWV5dXmFeZV5pXnFedV55Xn1elV6hXqlesV69XsFexV7NXtVe2V7dX' +
  'uVe6V7tXvFe9V75Xv1fAV8FXxFfFV8ZXx1fIV8lXylfMV81X0FfRV9NX1lfXV9tX3FfeV+FX4lfjV+VX5lfnV+hX6VfqV+tX7Ffu' +
  'V/BX8VfyV/NX9Vf2V/dX+1f8V/5X/1cBWANYBFgFWAhYCVgKWAxYDlgPWBBYElgTWBRYFlgXWBhYGlgbWBxYHVgfWCJYI1glWCZY' +
  'J1goWClYK1gsWC1YLlgvWDFYMlgzWDRYNlg3WDhYOVg6WDtYPFg9WD5YP1hAWEFYQlhDWEVYRlhHWEhYSVhKWEtYTlhPWFBYUlhT' +
  'WFVYVlhXWFlYWlhbWFxYXVhfWGBYYVhiWGNYZFhmWGdYaFhpWGpYbVhuWG9YcFhxWHJYc1h0WHVYdlh3WHhYeVh6WHtYfFh9WH9Y' +
  'gliEWIZYh1iIWIpYi1iMWI1YjliPWJBYkViUWJVYlliXWJhYm1icWJ1YoFihWKJYo1ikWKVYplinWKpYq1isWK1YrlivWLBYsViy' +
  'WLNYtFi1WLZYt1i4WLlYuli7WL1Yvli/WMBYwljDWMRYxljHWMhYyVjKWMtYzFjNWM5Yz1jQWNJY01jUWNZY11jYWNlY2ljbWNxY' +
  '3VjeWN9Y4FjhWOJY41jlWOZY51joWOlY6ljtWO9Y8VjyWPRY9Vj3WPhY+lj7WPxY/Vj+WP9YAFkBWQNZBVkGWQhZCVkKWQtZDFkO' +
  'WRBZEVkSWRNZF1kYWRtZHVkeWSBZIVkiWSNZJlkoWSxZMFkyWTNZNVk2WTtZPVk+WT9ZQFlDWUVZRllKWUxZTVlQWVJZU1lZWVtZ' +
  'XFldWV5ZX1lhWWNZZFlmWWdZaFlpWWpZa1lsWW1ZbllvWXBZcVlyWXVZd1l6WXtZfFl+WX9ZgFmFWYlZi1mMWY5Zj1mQWZFZlFmV' +
  'WZhZmlmbWZxZnVmfWaBZoVmiWaZZp1msWa1ZsFmxWbNZtFm1WbZZt1m4WbpZvFm9Wb9ZwFnBWcJZw1nEWcVZx1nIWclZzFnNWc5Z' +
  'z1nVWdZZ2VnbWd5Z31ngWeFZ4lnkWeZZ51npWepZ61ntWe5Z71nwWfFZ8lnzWfRZ9Vn2WfdZ+Fn6WfxZ/Vn+WQBaAloKWgtaDVoO' +
  'Wg9aEFoSWhRaFVoWWhdaGVoaWhtaHVoeWiFaIlokWiZaJ1ooWipaK1osWi1aLlovWjBaM1o1WjdaOFo5WjpaO1o9Wj5aP1pBWkJa' +
  'Q1pEWkVaR1pIWktaTFpNWk5aT1pQWlFaUlpTWlRaVlpXWlhaWVpbWlxaXVpeWl9aYFphWmNaZFplWmZaaFppWmtabFptWm5ab1pw' +
  'WnFaclpzWnhaeVp7WnxafVp+WoBagVqCWoNahFqFWoZah1qIWolailqLWoxajVqOWo9akFqRWpNalFqVWpZal1qYWplanFqdWp5a' +
  'n1qgWqFaolqjWqRapVqmWqdaqFqpWqtarFqtWq5ar1qwWrFatFq2WrdauVq6WrtavFq9Wr9awFrDWsRaxVrGWsdayFrKWstazVrO' +
  'Ws9a0FrRWtNa1VrXWtla2lrbWt1a3lrfWuJa5FrlWuda6FrqWuxa7VruWu9a8FryWvNa9Fr1WvZa91r4Wvla+lr7Wvxa/Vr+Wv9a' +
  'AFsBWwJbA1sEWwVbBlsHWwhbClsLWwxbDVsOWw9bEFsRWxJbE1sUWxVbGFsZWxpbG1scWx1bHlsfWyBbIVsiWyNbJFslWyZbJ1so' +
  'WylbKlsrWyxbLVsuWy9bMFsxWzNbNVs2WzhbOVs6WztbPFs9Wz5bP1tBW0JbQ1tEW0VbRltHW0hbSVtKW0tbTFtNW05bT1tSW1Zb' +
  'XltgW2FbZ1toW2tbbVtuW29bclt0W3Zbd1t4W3lbe1t8W35bf1uCW4ZbiluNW45bkFuRW5JblFuWW59bp1uoW6lbrFutW65br1ux' +
  'W7Jbt1u6W7tbvFvAW8Fbw1vIW8lbylvLW81bzlvPW9Fb1FvVW9Zb11vYW9lb2lvbW9xb4FviW+Nb5lvnW+lb6lvrW+xb7VvvW/Fb' +
  '8lvzW/Rb9Vv2W/db/Vv+WwBcAlwDXAVcB1wIXAtcDFwNXA5cEFwSXBNcF1wZXBtcHlwfXCBcIVwjXCZcKFwpXCpcK1wtXC5cL1ww' +
  'XDJcM1w1XDZcN1xDXERcRlxHXExcTVxSXFNcVFxWXFdcWFxaXFtcXFxdXF9cYlxkXGdcaFxpXGpca1xsXG1ccFxyXHNcdFx1XHZc' +
  'd1x4XHtcfFx9XH5cgFyDXIRchVyGXIdciVyKXItcjlyPXJJck1yVXJ1cnlyfXKBcoVykXKVcplynXKhcqlyuXK9csFyyXLRctly5' +
  'XLpcu1y8XL5cwFzCXMNcxVzGXMdcyFzJXMpczFzNXM5cz1zQXNFc01zUXNVc1lzXXNhc2lzbXNxc3VzeXN9c4FziXONc51zpXOtc' +
  '7FzuXO9c8VzyXPNc9Fz1XPZc91z4XPlc+lz8XP1c/lz/XABdAV0EXQVdCF0JXQpdC10MXQ1dD10QXRFdEl0TXRVdF10YXRldGl0c' +
  'XR1dH10gXSFdIl0jXSVdKF0qXStdLF0vXTBdMV0yXTNdNV02XTddOF05XTpdO108XT9dQF1BXUJdQ11EXUVdRl1IXUldTV1OXU9d' +
  'UF1RXVJdU11UXVVdVl1XXVldWl1cXV5dX11gXWFdYl1jXWRdZV1mXWddaF1qXW1dbl1wXXFdcl1zXXVddl13XXhdeV16XXtdfF19' +
  'XX5df12AXYFdg12EXYVdhl2HXYhdiV2KXYtdjF2NXY5dj12QXZFdkl2TXZRdlV2WXZddmF2aXZtdnF2eXZ9doF2hXaJdo12kXaVd' +
  'pl2nXahdqV2qXatdrF2tXa5dr12wXbFdsl2zXbRdtV22XbhduV26XbtdvF29Xb5dv13AXcFdwl3DXcRdxl3HXchdyV3KXctdzF3O' +
  'Xc9d0F3RXdJd013UXdVd1l3XXdhd2V3aXdxd313gXeNd5F3qXexd7V3wXfVd9l34Xfld+l37Xfxd/10AXgReB14JXgpeC14NXg5e' +
  'El4TXhdeHl4fXiBeIV4iXiNeJF4lXiheKV4qXiteLF4vXjBeMl4zXjReNV42XjleOl4+Xj9eQF5BXkNeRl5HXkheSV5KXkteTV5O' +
  'Xk9eUF5RXlJeU15WXldeWF5ZXlpeXF5dXl9eYF5jXmReZV5mXmdeaF5pXmpea15sXm1ebl5vXnBecV51XndeeV5+XoFegl6DXoVe' +
  'iF6JXoxejV6OXpJemF6bXp1eoV6iXqNepF6oXqleql6rXqxerl6vXrBesV6yXrReul67XrxevV6/XsBewV7CXsNexF7FXsZex17I' +
  'XstezF7NXs5ez17QXtRe1V7XXthe2V7aXtxe3V7eXt9e4F7hXuJe417kXuVe5l7nXule617sXu1e7l7vXvBe8V7yXvNe9V74Xvle' +
  '+178Xv1eBV8GXwdfCV8MXw1fDl8QXxJfFF8WXxlfGl8cXx1fHl8hXyJfI18kXyhfK18sXy5fMF8yXzNfNF81XzZfN184XztfPV8+' +
  'Xz9fQV9CX0NfRF9FX0ZfR19IX0lfSl9LX0xfTV9OX09fUV9UX1lfWl9bX1xfXl9fX2BfY19lX2dfaF9rX25fb19yX3RfdV92X3hf' +
  'el99X35ff1+DX4ZfjV+OX49fkV+TX5Rfll+aX5tfnV+eX59foF+iX6NfpF+lX6Zfp1+pX6tfrF+vX7BfsV+yX7NftF+2X7hfuV+6' +
  'X7tfvl+/X8BfwV/CX8dfyF/KX8tfzl/TX9Rf1V/aX9tf3F/eX99f4l/jX+Vf5l/oX+lf7F/vX/Bf8l/zX/Rf9l/3X/lf+l/8Xwdg' +
  'CGAJYAtgDGAQYBFgE2AXYBhgGmAeYB9gImAjYCRgLGAtYC5gMGAxYDJgM2A0YDZgN2A4YDlgOmA9YD5gQGBEYEVgRmBHYEhgSWBK' +
  'YExgTmBPYFFgU2BUYFZgV2BYYFtgXGBeYF9gYGBhYGVgZmBuYHFgcmB0YHVgd2B+YIBggWCCYIVghmCHYIhgimCLYI5gj2CQYJFg' +
  'k2CVYJdgmGCZYJxgnmChYKJgpGClYKdgqWCqYK5gsGCzYLVgtmC3YLlgumC9YL5gv2DAYMFgwmDDYMRgx2DIYMlgzGDNYM5gz2DQ' +
  'YNJg02DUYNZg12DZYNtg3mDhYOJg42DkYOVg6mDxYPJg9WD3YPhg+2D8YP1g/mD/YAJhA2EEYQVhB2EKYQthDGEQYRFhEmETYRRh' +
  'FmEXYRhhGWEbYRxhHWEeYSFhImElYShhKWEqYSxhLWEuYS9hMGExYTJhM2E0YTVhNmE3YThhOWE6YTthPGE9YT5hQGFBYUJhQ2FE' +
  'YUVhRmFHYUlhS2FNYU9hUGFSYVNhVGFWYVdhWGFZYVphW2FcYV5hX2FgYWFhY2FkYWVhZmFpYWpha2FsYW1hbmFvYXFhcmFzYXRh' +
  'dmF4YXlhemF7YXxhfWF+YX9hgGGBYYJhg2GEYYVhhmGHYYhhiWGKYYxhjWGPYZBhkWGSYZNhlWGWYZdhmGGZYZphm2GcYZ5hn2Gg' +
  'YaFhomGjYaRhpWGmYaphq2GtYa5hr2GwYbFhsmGzYbRhtWG2YbhhuWG6YbthvGG9Yb9hwGHBYcNhxGHFYcZhx2HJYcxhzWHOYc9h' +
  '0GHTYdVh1mHXYdhh2WHaYdth3GHdYd5h32HgYeFh4mHjYeRh5WHnYehh6WHqYeth7GHtYe5h72HwYfFh8mHzYfRh9mH3Yfhh+WH6' +
  'Yfth/GH9Yf5hAGIBYgJiA2IEYgViB2IJYhNiFGIZYhxiHWIeYiBiI2ImYidiKGIpYitiLWIvYjBiMWIyYjViNmI4YjliOmI7Yjxi' +
  'QmJEYkViRmJKYk9iUGJVYlZiV2JZYlpiXGJdYl5iX2JgYmFiYmJkYmViaGJxYnJidGJ1YndieGJ6YntifWKBYoJig2KFYoZih2KI' +
  'YotijGKNYo5ij2KQYpRimWKcYp1inmKjYqZip2KpYqpirWKuYq9isGKyYrNitGK2YrdiuGK6Yr5iwGLBYsNiy2LPYtFi1WLdYt5i' +
  '4GLhYuRi6mLrYvBi8mL1Yvhi+WL6YvtiAGMDYwRjBWMGYwpjC2MMYw1jD2MQYxJjE2MUYxVjF2MYYxljHGMmYydjKWMsYy1jLmMw' +
  'YzFjM2M0YzVjNmM3YzhjO2M8Yz5jP2NAY0FjRGNHY0hjSmNRY1JjU2NUY1ZjV2NYY1ljWmNbY1xjXWNgY2RjZWNmY2hjamNrY2xj' +
  'b2NwY3Jjc2N0Y3VjeGN5Y3xjfWN+Y39jgWODY4RjhWOGY4tjjWORY5NjlGOVY5djmWOaY5tjnGOdY55jn2OhY6RjpmOrY69jsWOy' +
  'Y7VjtmO5Y7tjvWO/Y8BjwWPCY8NjxWPHY8hjymPLY8xj0WPTY9Rj1WPXY9hj2WPaY9tj3GPdY99j4mPkY+Vj5mPnY+hj62PsY+5j' +
  '72PwY/Fj82P1Y/dj+WP6Y/tj/GP+YwNkBGQGZAdkCGQJZApkDWQOZBFkEmQVZBZkF2QYZBlkGmQdZB9kImQjZCRkJWQnZChkKWQr' +
  'ZC5kL2QwZDFkMmQzZDVkNmQ3ZDhkOWQ7ZDxkPmRAZEJkQ2RJZEtkTGRNZE5kT2RQZFFkU2RVZFZkV2RZZFpkW2RcZF1kX2RgZGFk' +
  'YmRjZGRkZWRmZGhkamRrZGxkbmRvZHBkcWRyZHNkdGR1ZHZkd2R7ZHxkfWR+ZH9kgGSBZINkhmSIZIlkimSLZIxkjWSOZI9kkGST' +
  'ZJRkl2SYZJpkm2ScZJ1kn2SgZKFkomSjZKVkpmSnZKhkqmSrZK9ksWSyZLNktGS2ZLlku2S9ZL5kv2TBZMNkxGTGZMdkyGTJZMpk' +
  'y2TMZM9k0WTTZNRk1WTWZNlk2mTbZNxk3WTfZOBk4WTjZOVk52ToZOlk6mTrZOxk7WTuZO9k8GTxZPJk82T0ZPVk9mT3ZPhk+WT6' +
  'ZPtk/GT9ZP5k/2QBZQJlA2UEZQVlBmUHZQhlCmULZQxlDWUOZQ9lEGURZRNlFGUVZRZlF2UZZRplG2UcZR1lHmUfZSBlIWUiZSNl' +
  'JGUmZSdlKGUpZSplLGUtZTBlMWUyZTNlN2U6ZTxlPWVAZUFlQmVDZURlRmVHZUplS2VNZU5lUGVSZVNlVGVXZVhlWmVcZV9lYGVh' +
  'ZWRlZWVnZWhlaWVqZW1lbmVvZXFlc2V1ZXZleGV5ZXple2V8ZX1lfmV/ZYBlgWWCZYNlhGWFZYZliGWJZYpljWWOZY9lkmWUZZVl' +
  'lmWYZZplnWWeZaBlomWjZaZlqGWqZaxlrmWxZbJls2W0ZbVltmW3ZbhlumW7Zb5lv2XAZcJlx2XIZcllymXNZdBl0WXTZdRl1WXY' +
  'Zdll2mXbZdxl3WXeZd9l4WXjZeRl6mXrZfJl82X0ZfVl+GX5Zftl/GX9Zf5l/2UBZgRmBWYHZghmCWYLZg1mEGYRZhJmFmYXZhhm' +
  'GmYbZhxmHmYhZiJmI2YkZiZmKWYqZitmLGYuZjBmMmYzZjdmOGY5ZjpmO2Y9Zj9mQGZCZkRmRWZGZkdmSGZJZkpmTWZOZlBmUWZY' +
  'ZllmW2ZcZl1mXmZgZmJmY2ZlZmdmaWZqZmtmbGZtZnFmcmZzZnVmeGZ5ZntmfGZ9Zn9mgGaBZoNmhWaGZohmiWaKZotmjWaOZo9m' +
  'kGaSZpNmlGaVZphmmWaaZptmnGaeZp9moGahZqJmo2akZqVmpmapZqpmq2asZq1mr2awZrFmsmazZrVmtma3Zrhmuma7ZrxmvWa/' +
  'ZsBmwWbCZsNmxGbFZsZmx2bIZslmymbLZsxmzWbOZs9m0GbRZtJm02bUZtVm1mbXZthm2mbeZt9m4GbhZuJm42bkZuVm52boZupm' +
  '62bsZu1m7mbvZvFm9Wb2Zvhm+mb7Zv1mAWcCZwNnBGcFZwZnB2cMZw5nD2cRZxJnE2cWZxhnGWcaZxxnHmcgZyFnImcjZyRnJWcn' +
  'ZylnLmcwZzJnM2c2ZzdnOGc5ZztnPGc+Zz9nQWdEZ0VnR2dKZ0tnTWdSZ1RnVWdXZ1hnWWdaZ1tnXWdiZ2NnZGdmZ2dna2dsZ25n' +
  'cWd0Z3ZneGd5Z3pne2d9Z4BngmeDZ4VnhmeIZ4pnjGeNZ45nj2eRZ5Jnk2eUZ5ZnmWebZ59noGehZ6RnpmepZ6xnrmexZ7JntGe5' +
  'Z7pnu2e8Z71nvme/Z8BnwmfFZ8Znx2fIZ8lnymfLZ8xnzWfOZ9Vn1mfXZ9tn32fhZ+Nn5GfmZ+dn6GfqZ+tn7WfuZ/Jn9Wf2Z/dn' +
  '+Gf5Z/pn+2f8Z/5nAWgCaANoBGgGaA1oEGgSaBRoFWgYaBloGmgbaBxoHmgfaCBoImgjaCRoJWgmaCdoKGgraCxoLWguaC9oMGgx' +
  'aDRoNWg2aDpoO2g/aEdoS2hNaE9oUmhWaFdoWGhZaFpoW2hcaF1oXmhfaGpobGhtaG5ob2hwaHFocmhzaHVoeGh5aHpoe2h8aH1o' +
  'fmh/aIBogmiEaIdoiGiJaIpoi2iMaI1ojmiQaJFokmiUaJVolmiYaJlommibaJxonWieaJ9ooGihaKNopGilaKloqmiraKxormix' +
  'aLJotGi2aLdouGi5aLpou2i8aL1ovmi/aMFow2jEaMVoxmjHaMhoymjMaM5oz2jQaNFo02jUaNZo12jZaNto3GjdaN5o32jhaOJo' +
  '5GjlaOZo52joaOlo6mjraOxo7WjvaPJo82j0aPZo92j4aPto/Wj+aP9oAGkCaQNpBGkGaQdpCGkJaQppDGkPaRFpE2kUaRVpFmkX' +
  'aRhpGWkaaRtpHGkdaR5pIWkiaSNpJWkmaSdpKGkpaSppK2ksaS5pL2kxaTJpM2k1aTZpN2k4aTppO2k8aT5pQGlBaUNpRGlFaUZp' +
  'R2lIaUlpSmlLaUxpTWlOaU9pUGlRaVJpU2lVaVZpWGlZaVtpXGlfaWFpYmlkaWVpZ2loaWlpamlsaW1pb2lwaXJpc2l0aXVpdml6' +
  'aXtpfWl+aX9pgWmDaYVpimmLaYxpjmmPaZBpkWmSaZNplmmXaZlpmmmdaZ5pn2mgaaFpommjaaRppWmmaalpqmmsaa5pr2mwabJp' +
  's2m1abZpuGm5abppvGm9ab5pv2nAacJpw2nEacVpxmnHachpyWnLac1pz2nRadJp02nVadZp12nYadlp2mncad1p3mnhaeJp42nk' +
  'aeVp5mnnaehp6Wnqaetp7Gnuae9p8GnxafNp9Gn1afZp92n4aflp+mn7afxp/mkAagFqAmoDagRqBWoGagdqCGoJagtqDGoNag5q' +
  'D2oQahFqEmoTahRqFWoWahlqGmobahxqHWoeaiBqImojaiRqJWomaidqKWoraixqLWouajBqMmozajRqNmo3ajhqOWo6ajtqPGo/' +
  'akBqQWpCakNqRWpGakhqSWpKaktqTGpNak5qT2pRalJqU2pUalVqVmpXalpqXGpdal5qX2pgamJqY2pkamZqZ2poamlqampramxq' +
  'bWpuam9qcGpyanNqdGp1anZqd2p4anpqe2p9an5qf2qBaoJqg2qFaoZqh2qIaolqimqLaoxqjWqPapJqk2qUapVqlmqYaplqmmqb' +
  'apxqnWqeap9qoWqiaqNqpGqlaqZqp2qoaqpqrWquaq9qsGqxarJqs2q0arVqtmq3arhquWq6artqvGq9ar5qv2rAasFqwmrDasRq' +
  'xWrGasdqyGrJaspqy2rMas1qzmrPatBq0WrSatNq1GrVatZq12rYatlq2mrbatxq3Wreat9q4GrhauJq42rkauVq5mrnauhq6Wrq' +
  'autq7Grtau5q72rwavFq8mrzavRq9Wr2avdq+Gr5avpq+2r8av1q/mr/agBrAWsCawNrBGsFawZrB2sIawlrCmsLawxrDWsOaw9r' +
  'EGsRaxJrE2sUaxVrFmsXaxhrGWsaaxtrHGsdax5rH2slayZrKGspayprK2ssay1rLmsvazBrMWszazRrNWs2azhrO2s8az1rP2tA' +
  'a0FrQmtEa0VrSGtKa0trTWtOa09rUGtRa1JrU2tUa1VrVmtXa1hrWmtba1xrXWtea19rYGtha2hraWtra2xrbWtua29rcGtxa3Jr' +
  'c2t0a3Vrdmt3a3hremt9a35rf2uAa4VriGuMa45rj2uQa5FrlGuVa5drmGuZa5xrnWuea59roGuia6NrpGula6Zrp2uoa6lrq2us' +
  'a61rrmuva7BrsWuya7ZruGu5a7pru2u8a71rvmvAa8NrxGvGa8dryGvJa8przGvOa9Br0WvYa9pr3Gvda95r32vga+Jr42vka+Vr' +
  '5mvna+hr6Wvsa+1r7mvwa/Fr8mv0a/Zr92v4a/pr+2v8a/5r/2sAbAFsAmwDbARsCGwJbApsC2wMbA5sEmwXbBxsHWwebCBsI2wl' +
  'bCtsLGwtbDFsM2w2bDdsOWw6bDtsPGw+bD9sQ2xEbEVsSGxLbExsTWxObE9sUWxSbFNsVmxYbFlsWmxibGNsZWxmbGdsa2xsbG1s' +
  'bmxvbHFsc2x1bHdseGx6bHtsfGx/bIBshGyHbIpsi2yNbI5skWySbJVslmyXbJhsmmycbJ1snmygbKJsqGysbK9ssGy0bLVstmy3' +
  'bLpswGzBbMJsw2zGbMdsyGzLbM1szmzPbNFs0mzYbNls2mzcbN1s32zkbOZs52zpbOxs7WzybPRs+Wz/bABtAm0DbQVtBm0IbQlt' +
  'Cm0NbQ9tEG0RbRNtFG0VbRZtGG0cbR1tH20gbSFtIm0jbSRtJm0obSltLG0tbS9tMG00bTZtN204bTptP21AbUJtRG1JbUxtUG1V' +
  'bVZtV21YbVttXW1fbWFtYm1kbWVtZ21obWttbG1tbXBtcW1ybXNtdW12bXltem17bX1tfm1/bYBtgW2DbYRthm2HbYpti22NbY9t' +
  'kG2SbZZtl22YbZltmm2cbaJtpW2sba1tsG2xbbNttG22bbdtuW26bbttvG29bb5twW3CbcNtyG3JbcptzW3Obc9t0G3SbdNt1G3V' +
  'bddt2m3bbdxt323ibeNt5W3nbeht6W3qbe1t723wbfJt9G31bfZt+G36bf1t/m3/bQBuAW4CbgNuBG4GbgduCG4JbgtuD24SbhNu' +
  'FW4YbhluG24cbh5uH24ibiZuJ24obipuLG4ubjBuMW4zbjVuNm43bjluO248bj1uPm4/bkBuQW5CbkVuRm5HbkhuSW5KbktuTG5P' +
  'blBuUW5SblVuV25ZblpuXG5dbl5uYG5hbmJuY25kbmVuZm5nbmhuaW5qbmxubW5vbnBucW5ybnNudG51bnZud254bnluem57bnxu' +
  'fW6AboFugm6EboduiG6KbotujG6Nbo5ukW6SbpNulG6VbpZul26Zbppum26dbp5uoG6hbqNupG6mbqhuqW6rbqxurW6ubrBus261' +
  'brhuuW68br5uv27AbsNuxG7FbsZuyG7JbspuzG7Nbs5u0G7SbtZu2G7Zbttu3G7dbuNu527qbutu7G7tbu5u727wbvFu8m7zbvVu' +
  '9m73bvhu+m77bvxu/W7+bv9uAG8BbwNvBG8FbwdvCG8KbwtvDG8Nbw5vEG8RbxJvFm8XbxhvGW8abxtvHG8dbx5vH28hbyJvI28l' +
  'byZvJ28obyxvLm8wbzJvNG81bzdvOG85bzpvO288bz1vP29Ab0FvQm9Db0RvRW9Ib0lvSm9Mb05vT29Qb1FvUm9Tb1RvVW9Wb1dv' +
  'WW9ab1tvXW9fb2BvYW9jb2RvZW9nb2hvaW9qb2tvbG9vb3BvcW9zb3Vvdm93b3lve299b35vf2+Ab4Fvgm+Db4Vvhm+Hb4pvi2+P' +
  'b5BvkW+Sb5NvlG+Vb5Zvl2+Yb5lvmm+bb51vnm+fb6Bvom+jb6RvpW+mb6hvqW+qb6tvrG+tb65vr2+wb7Fvsm+0b7Vvt2+4b7pv' +
  'u2+8b71vvm+/b8Fvw2/Eb8Vvxm/Hb8hvym/Lb8xvzW/Ob89v0G/Tb9Rv1W/Wb9dv2G/Zb9pv22/cb91v32/ib+Nv5G/lb+Zv52/o' +
  'b+lv6m/rb+xv7W/wb/Fv8m/zb/Rv9W/2b/dv+G/5b/pv+2/8b/1v/m//bwBwAXACcANwBHAFcAZwB3AIcAlwCnALcAxwDXAOcA9w' +
  'EHAScBNwFHAVcBZwF3AYcBlwHHAdcB5wH3AgcCFwInAkcCVwJnAncChwKXAqcCtwLHAtcC5wL3AwcDFwMnAzcDRwNnA3cDhwOnA7' +
  'cDxwPXA+cD9wQHBBcEJwQ3BEcEVwRnBHcEhwSXBKcEtwTXBOcFBwUXBScFNwVHBVcFZwV3BYcFlwWnBbcFxwXXBfcGBwYXBicGNw' +
  'ZHBlcGZwZ3BocGlwanBucHFwcnBzcHRwd3B5cHpwe3B9cIFwgnCDcIRwhnCHcIhwi3CMcI1wj3CQcJFwk3CXcJhwmnCbcJ5wn3Cg' +
  'cKFwonCjcKRwpXCmcKdwqHCpcKpwsHCycLRwtXC2cLpwvnC/cMRwxXDGcMdwyXDLcMxwzXDOcM9w0HDRcNJw03DUcNVw1nDXcNpw' +
  '3HDdcN5w4HDhcOJw43DlcOpw7nDwcPFw8nDzcPRw9XD2cPhw+nD7cPxw/nD/cABxAXECcQNxBHEFcQZxB3EIcQtxDHENcQ5xD3ER' +
  'cRJxFHEXcRtxHHEdcR5xH3EgcSFxInEjcSRxJXEncShxKXEqcStxLHEtcS5xMnEzcTRxNXE3cThxOXE6cTtxPHE9cT5xP3FAcUFx' +
  'QnFDcURxRnFHcUhxSXFLcU1xT3FQcVFxUnFTcVRxVXFWcVdxWHFZcVpxW3FdcV9xYHFhcWJxY3FlcWlxanFrcWxxbXFvcXBxcXF0' +
  'cXVxdnF3cXlxe3F8cX5xf3GAcYFxgnGDcYVxhnGHcYhxiXGLcYxxjXGOcZBxkXGScZNxlXGWcZdxmnGbcZxxnXGecaFxonGjcaRx' +
  'pXGmcadxqXGqcatxrXGuca9xsHGxcbJxtHG2cbdxuHG6cbtxvHG9cb5xv3HAccFxwnHEccVxxnHHcchxyXHKcctxzHHNcc9x0HHR' +
  'cdJx03HWcddx2HHZcdpx23Hccd1x3nHfceFx4nHjceRx5nHocelx6nHrcexx7XHvcfBx8XHycfNx9HH1cfZx93H4cfpx+3H8cf1x' +
  '/nH/cQByAXICcgNyBHIFcgdyCHIJcgpyC3IMcg1yDnIPchByEXISchNyFHIVchZyF3IYchlyGnIbchxyHnIfciByIXIiciNyJHIl' +
  'ciZyJ3IpcityLXIuci9yMnIzcjRyOnI8cj5yQHJBckJyQ3JEckVyRnJJckpyS3JOck9yUHJRclNyVHJVcldyWHJaclxyXnJgcmNy' +
  'ZHJlcmhyanJrcmxybXJwcnFyc3J0cnZyd3J4cntyfHJ9coJyg3KFcoZyh3KIcolyjHKOcpBykXKTcpRylXKWcpdymHKZcppym3Kc' +
  'cp1ynnKgcqFyonKjcqRypXKmcqdyqHKpcqpyq3KucrFysnKzcrVyunK7crxyvXK+cr9ywHLFcsZyx3LJcspyy3LMcs9y0XLTctRy' +
  '1XLWcthy2nLbcsbkx+TI5MnkyuTL5MzkzeTO5M/k0OTR5NLk0+TU5NXk1uTX5Njk2eTa5Nvk3OTd5N7k3+Tg5OHk4uTj5OTk5eTm' +
  '5Ofk6OTp5Ork6+Ts5O3k7uTv5PDk8eTy5PPk9OT15Pbk9+T45Pnk+uT75Pzk/eT+5P/kAOUB5QLlA+UE5QXlBuUH5QjlCeUK5Qvl' +
  'DOUN5Q7lD+UQ5RHlEuUT5RTlFeUW5RflGOUZ5RrlG+Uc5R3lHuUf5SDlIeUi5SPlJOUl5QAwATACMLcAyQLHAqgAAzAFMBQgXv8W' +
  'ICYgGCAZIBwgHSAUMBUwCDAJMAowCzAMMA0wDjAPMBYwFzAQMBEwsQDXAPcANiInIigiESIPIioiKSIIIjciGiKlIiUiICISI5ki' +
  'KyIuImEiTCJIIj0iHSJgIm4ibyJkImUiHiI1IjQiQiZAJrAAMiAzIAMhBP+kAOD/4f8wIKcAFiEGJgUmyyXPJc4lxyXGJaEloCWz' +
  'JbIlOyCSIZAhkSGTIRMwJuUn5SjlKeUq5SvlLOUt5S7lL+Uw5THlMuUz5TTlNeU25TflOOU55TrlO+U85T3lPuU/5UDlQeVC5UPl' +
  'ROVF5UblR+VI5UnlSuVL5UzlTeVO5U/lUOVR5VLlU+VU5VXlVuVX5VjlWeVa5VvlXOVd5V7lX+Vg5WHlYuVj5WTlZeVm5WflaOVp' +
  '5Wrla+Vs5W3lbuVv5XDlceVy5XPldOV15Xbld+V45XnleuV75XzlfeV+5X/lgOWB5YLlg+WE5YXlcCFxIXIhcyF0IXUhdiF3IXgh' +
  'eSFm52fnaOdp52rna+eIJIkkiiSLJIwkjSSOJI8kkCSRJJIkkySUJJUkliSXJJgkmSSaJJskdCR1JHYkdyR4JHkkeiR7JHwkfSR+' +
  'JH8kgCSBJIIkgySEJIUkhiSHJGAkYSRiJGMkZCRlJGYkZyRoJGkkrCBt5yAyITIiMiMyJDIlMiYyJzIoMikybudv52AhYSFiIWMh' +
  'ZCFlIWYhZyFoIWkhaiFrIXDnceeG5YfliOWJ5Yrli+WM5Y3ljuWP5ZDlkeWS5ZPllOWV5Zbll+WY5ZnlmuWb5ZzlneWe5Z/loOWh' +
  '5aLlo+Wk5aXlpuWn5ajlqeWq5avlrOWt5a7lr+Ww5bHlsuWz5bTlteW25bfluOW55brlu+W85b3lvuW/5cDlweXC5cPlxOXF5cbl' +
  'x+XI5cnlyuXL5czlzeXO5c/l0OXR5dLl0+XU5dXl1uXX5djl2eXa5dvl3OXd5d7l3+Xg5eHl4uXj5eTlADAB/wL/A//l/wX/Bv8H' +
  '/wj/Cf8K/wv/DP8N/w7/D/8Q/xH/Ev8T/xT/Ff8W/xf/GP8Z/xr/G/8c/x3/Hv8f/yD/If8i/yP/JP8l/yb/J/8o/yn/Kv8r/yz/' +
  'Lf8u/y//MP8x/zL/M/80/zX/Nv83/zj/Of86/zv/PP89/z7/P/9A/0H/Qv9D/0T/Rf9G/0f/SP9J/0r/S/9M/03/Tv9P/1D/Uf9S' +
  '/1P/VP9V/1b/V/9Y/1n/Wv9b/1z/Xf/j/+bl5+Xo5enl6uXr5ezl7eXu5e/l8OXx5fLl8+X05fXl9uX35fjl+eX65fvl/OX95f7l' +
  '/+UA5gHmAuYD5gTmBeYG5gfmCOYJ5grmC+YM5g3mDuYP5hDmEeYS5hPmFOYV5hbmF+YY5hnmGuYb5hzmHeYe5h/mIOYh5iLmI+Yk' +
  '5iXmJuYn5ijmKeYq5ivmLOYt5i7mL+Yw5jHmMuYz5jTmNeY25jfmOOY55jrmO+Y85j3mPuY/5kDmQeZC5kPmROZF5kEwQjBDMEQw' +
  'RTBGMEcwSDBJMEowSzBMME0wTjBPMFAwUTBSMFMwVDBVMFYwVzBYMFkwWjBbMFwwXTBeMF8wYDBhMGIwYzBkMGUwZjBnMGgwaTBq' +
  'MGswbDBtMG4wbzBwMHEwcjBzMHQwdTB2MHcweDB5MHowezB8MH0wfjB/MIAwgTCCMIMwhDCFMIYwhzCIMIkwijCLMIwwjTCOMI8w' +
  'kDCRMJIwkzBy53PndOd153bnd+d453nneud753znRuZH5kjmSeZK5kvmTOZN5k7mT+ZQ5lHmUuZT5lTmVeZW5lfmWOZZ5lrmW+Zc' +
  '5l3mXuZf5mDmYeZi5mPmZOZl5mbmZ+Zo5mnmauZr5mzmbeZu5m/mcOZx5nLmc+Z05nXmduZ35njmeeZ65nvmfOZ95n7mf+aA5oHm' +
  'guaD5oTmheaG5ofmiOaJ5ormi+aM5o3mjuaP5pDmkeaS5pPmlOaV5pbml+aY5pnmmuab5pzmneae5p/moOah5qLmo+ak5qXmoTCi' +
  'MKMwpDClMKYwpzCoMKkwqjCrMKwwrTCuMK8wsDCxMLIwszC0MLUwtjC3MLgwuTC6MLswvDC9ML4wvzDAMMEwwjDDMMQwxTDGMMcw' +
  'yDDJMMowyzDMMM0wzjDPMNAw0TDSMNMw1DDVMNYw1zDYMNkw2jDbMNww3TDeMN8w4DDhMOIw4zDkMOUw5jDnMOgw6TDqMOsw7DDt' +
  'MO4w7zDwMPEw8jDzMPQw9TD2MH3nfud/54DngeeC54PnhOem5qfmqOap5qrmq+as5q3mruav5rDmseay5rPmtOa15rbmt+a45rnm' +
  'uua75rzmvea+5r/mwObB5sLmw+bE5sXmxubH5sjmyebK5svmzObN5s7mz+bQ5tHm0ubT5tTm1ebW5tfm2ObZ5trm2+bc5t3m3ubf' +
  '5uDm4ebi5uPm5Obl5ubm5+bo5unm6ubr5uzm7ebu5u/m8Obx5vLm8+b05vXm9ub35vjm+eb65vvm/Ob95v7m/+YA5wHnAucD5wTn' +
  'BeeRA5IDkwOUA5UDlgOXA5gDmQOaA5sDnAOdA54DnwOgA6EDowOkA6UDpgOnA6gDqQOF54bnh+eI54nniueL54znsQOyA7MDtAO1' +
  'A7YDtwO4A7kDugO7A7wDvQO+A78DwAPBA8MDxAPFA8YDxwPIA8kDEP4S/hH+E/4U/hX+Fv41/jb+Of46/j/+QP49/j7+Qf5C/kP+' +
  'RP4X/hj+O/48/jf+OP4x/hn+M/40/pfnmOeZ55rnm+ec553nnuef5wbnB+cI5wnnCucL5wznDecO5w/nEOcR5xLnE+cU5xXnFucX' +
  '5xjnGeca5xvnHOcd5x7nH+cg5yHnIucj5yTnJecm5yfnKOcp5yrnK+cs5y3nLucv5zDnMecy5zPnNOc15zbnN+c45znnOuc75zzn' +
  'Pec+5z/nQOdB50LnQ+dE50XnRudH50jnSedK50vnTOdN507nT+dQ51HnUudT51TnVedW51fnWOdZ51rnW+dc513nXudf52DnYedi' +
  '52PnZOdl5xAEEQQSBBMEFAQVBAEEFgQXBBgEGQQaBBsEHAQdBB4EHwQgBCEEIgQjBCQEJQQmBCcEKAQpBCoEKwQsBC0ELgQvBKDn' +
  'oeei56PnpOel56bnp+eo56nnquer56znreeu5zAEMQQyBDMENAQ1BFEENgQ3BDgEOQQ6BDsEPAQ9BD4EPwRABEEEQgRDBEQERQRG' +
  'BEcESARJBEoESwRMBE0ETgRPBK/nsOex57Lns+e057Xntue357jnuee657vnygLLAtkCEyAVICUgNSAFIQkhliGXIZghmSEVIh8i' +
  'IyJSImYiZyK/IlAlUSVSJVMlVCVVJVYlVyVYJVklWiVbJVwlXSVeJV8lYCVhJWIlYyVkJWUlZiVnJWglaSVqJWslbCVtJW4lbyVw' +
  'JXElciVzJYElgiWDJYQlhSWGJYcliCWJJYoliyWMJY0ljiWPJZMllCWVJbwlvSXiJeMl5CXlJQkmlSISMB0wHjC8573nvue/58Dn' +
  'wefC58PnxOfF58bnAQHhAM4B4AATAekAGwHoACsB7QDQAewATQHzANIB8gBrAfoA1AH5ANYB2AHaAdwB/ADqAFECPx5EAUgB+QFh' +
  'AsnnyufL58znBTEGMQcxCDEJMQoxCzEMMQ0xDjEPMRAxETESMRMxFDEVMRYxFzEYMRkxGjEbMRwxHTEeMR8xIDEhMSIxIzEkMSUx' +
  'JjEnMSgxKTHN587nz+fQ59Hn0ufT59Tn1efW59fn2OfZ59rn2+fc593n3uff5+Dn4echMCIwIzAkMCUwJjAnMCgwKTCjMo4zjzOc' +
  'M50znjOhM8QzzjPRM9Iz1TMw/uL/5P/i5yEhMTLj5xAg5Ofl5+bn/DCbMJww/TD+MAYwnTCeMEn+Sv5L/kz+Tf5O/k/+UP5R/lL+' +
  'VP5V/lb+V/5Z/lr+W/5c/l3+Xv5f/mD+Yf5i/mP+ZP5l/mb+aP5p/mr+a/4+MPAv8S/yL/Mv9C/1L/Yv9y/4L/kv+i/7Lwcw9Of1' +
  '5/bn9+f45/nn+uf75/zn/ef+5//nAOgAJQElAiUDJQQlBSUGJQclCCUJJQolCyUMJQ0lDiUPJRAlESUSJRMlFCUVJRYlFyUYJRkl' +
  'GiUbJRwlHSUeJR8lICUhJSIlIyUkJSUlJiUnJSglKSUqJSslLCUtJS4lLyUwJTElMiUzJTQlNSU2JTclOCU5JTolOyU8JT0lPiU/' +
  'JUAlQSVCJUMlRCVFJUYlRyVIJUklSiVLJQHoAugD6AToBegG6AfoCOgJ6AroC+gM6A3oDugP6Nxy3XLfcuJy43LkcuVy5nLncupy' +
  '63L1cvZy+XL9cv5y/3IAcwJzBHMFcwZzB3MIcwlzC3MMcw1zD3MQcxFzEnMUcxhzGXMacx9zIHMjcyRzJnMncyhzLXMvczBzMnMz' +
  'czVzNnM6cztzPHM9c0BzQXNCc0NzRHNFc0ZzR3NIc0lzSnNLc0xzTnNPc1FzU3NUc1VzVnNYc1lzWnNbc1xzXXNec19zYXNic2Nz' +
  'ZHNlc2ZzZ3Noc2lzanNrc25zcHNxcwDgAeAC4APgBOAF4AbgB+AI4AngCuAL4AzgDeAO4A/gEOAR4BLgE+AU4BXgFuAX4BjgGeAa' +
  '4BvgHOAd4B7gH+Ag4CHgIuAj4CTgJeAm4CfgKOAp4CrgK+As4C3gLuAv4DDgMeAy4DPgNOA14DbgN+A44DngOuA74DzgPeA+4D/g' +
  'QOBB4ELgQ+BE4EXgRuBH4EjgSeBK4EvgTOBN4E7gT+BQ4FHgUuBT4FTgVeBW4FfgWOBZ4FrgW+Bc4F3gcnNzc3RzdXN2c3dzeHN5' +
  'c3pze3N8c31zf3OAc4FzgnODc4VzhnOIc4pzjHONc49zkHOSc5NzlHOVc5dzmHOZc5pznHOdc55zoHOhc6NzpHOlc6Zzp3Ooc6pz' +
  'rHOtc7FztHO1c7ZzuHO5c7xzvXO+c79zwXPDc8RzxXPGc8dzy3PMc85z0nPTc9Rz1XPWc9dz2HPac9tz3HPdc99z4XPic+Nz5HPm' +
  'c+hz6nPrc+xz7nPvc/Bz8XPzc/Rz9XP2c/dzXuBf4GDgYeBi4GPgZOBl4GbgZ+Bo4GngauBr4GzgbeBu4G/gcOBx4HLgc+B04HXg' +
  'duB34HjgeeB64HvgfOB94H7gf+CA4IHgguCD4ITgheCG4IfgiOCJ4Irgi+CM4I3gjuCP4JDgkeCS4JPglOCV4Jbgl+CY4JngmuCb' +
  '4JzgneCe4J/goOCh4KLgo+Ck4KXgpuCn4KjgqeCq4KvgrOCt4K7gr+Cw4LHgsuCz4LTgteC24LfguOC54Lrgu+D4c/lz+nP7c/xz' +
  '/XP+c/9zAHQBdAJ0BHQHdAh0C3QMdA10DnQRdBJ0E3QUdBV0FnQXdBh0GXQcdB10HnQfdCB0IXQjdCR0J3QpdCt0LXQvdDF0MnQ3' +
  'dDh0OXQ6dDt0PXQ+dD90QHRCdEN0RHRFdEZ0R3RIdEl0SnRLdEx0TXROdE90UHRRdFJ0U3RUdFZ0WHRddGB0YXRidGN0ZHRldGZ0' +
  'Z3RodGl0anRrdGx0bnRvdHF0cnRzdHR0dXR4dHl0enS84L3gvuC/4MDgweDC4MPgxODF4Mbgx+DI4MngyuDL4MzgzeDO4M/g0ODR' +
  '4NLg0+DU4NXg1uDX4Njg2eDa4Nvg3ODd4N7g3+Dg4OHg4uDj4OTg5eDm4Ofg6ODp4Org6+Ds4O3g7uDv4PDg8eDy4PPg9OD14Pbg' +
  '9+D44Png+uD74Pzg/eD+4P/gAOEB4QLhA+EE4QXhBuEH4QjhCeEK4QvhDOEN4Q7hD+EQ4RHhEuET4RThFeEW4RfhGOEZ4Xt0fHR9' +
  'dH90gnSEdIV0hnSIdIl0inSMdI10j3SRdJJ0k3SUdJV0lnSXdJh0mXSadJt0nXSfdKB0oXSidKN0pHSldKZ0qnSrdKx0rXSudK90' +
  'sHSxdLJ0s3S0dLV0tnS3dLh0uXS7dLx0vXS+dL90wHTBdMJ0w3TEdMV0xnTHdMh0yXTKdMt0zHTNdM50z3TQdNF003TUdNV01nTX' +
  'dNh02XTadNt03XTfdOF05XTndOh06XTqdOt07HTtdPB08XTydBrhG+Ec4R3hHuEf4SDhIeEi4SPhJOEl4SbhJ+Eo4SnhKuEr4Szh' +
  'LeEu4S/hMOEx4TLhM+E04TXhNuE34TjhOeE64TvhPOE94T7hP+FA4UHhQuFD4UThReFG4UfhSOFJ4UrhS+FM4U3hTuFP4VDhUeFS' +
  '4VPhVOFV4VbhV+FY4VnhWuFb4VzhXeFe4V/hYOFh4WLhY+Fk4WXhZuFn4WjhaeFq4WvhbOFt4W7hb+Fw4XHhcuFz4XThdeF24Xfh' +
  '83T1dPh0+XT6dPt0/HT9dP50AHUBdQJ1A3UFdQZ1B3UIdQl1CnULdQx1DnUQdRJ1FHUVdRZ1F3UbdR11HnUgdSF1InUjdSR1JnUn' +
  'dSp1LnU0dTZ1OXU8dT11P3VBdUJ1Q3VEdUZ1R3VJdUp1TXVQdVF1UnVTdVV1VnVXdVh1XXVedV91YHVhdWJ1Y3VkdWd1aHVpdWt1' +
  'bHVtdW51b3VwdXF1c3V1dXZ1d3V6dXt1fHV9dX51gHWBdYJ1hHWFdYd1eOF54Xrhe+F84X3hfuF/4YDhgeGC4YPhhOGF4Ybhh+GI' +
  '4YnhiuGL4YzhjeGO4Y/hkOGR4ZLhk+GU4ZXhluGX4ZjhmeGa4ZvhnOGd4Z7hn+Gg4aHhouGj4aThpeGm4afhqOGp4arhq+Gs4a3h' +
  'ruGv4bDhseGy4bPhtOG14bbht+G44bnhuuG74bzhveG+4b/hwOHB4cLhw+HE4cXhxuHH4cjhyeHK4cvhzOHN4c7hz+HQ4dHh0uHT' +
  '4dTh1eGIdYl1inWMdY11jnWQdZN1lXWYdZt1nHWedaJ1pnWndah1qXWqda11tnW3dbp1u3W/dcB1wXXGdct1zHXOdc910HXRddN1' +
  '13XZddp13HXddd914HXhdeV16XXsde117nXvdfJ183X1dfZ193X4dfp1+3X9df51AnYEdgZ2B3YIdgl2C3YNdg52D3YRdhJ2E3YU' +
  'dhZ2GnYcdh12HnYhdiN2J3Yodix2LnYvdjF2MnY2djd2OXY6djt2PXZBdkJ2RHbW4dfh2OHZ4drh2+Hc4d3h3uHf4eDh4eHi4ePh' +
  '5OHl4ebh5+Ho4enh6uHr4ezh7eHu4e/h8OHx4fLh8+H04fXh9uH34fjh+eH64fvh/OH94f7h/+EA4gHiAuID4gTiBeIG4gfiCOIJ' +
  '4griC+IM4g3iDuIP4hDiEeIS4hPiFOIV4hbiF+IY4hniGuIb4hziHeIe4h/iIOIh4iLiI+Ik4iXiJuIn4ijiKeIq4iviLOIt4i7i' +
  'L+Iw4jHiMuIz4kV2RnZHdkh2SXZKdkt2TnZPdlB2UXZSdlN2VXZXdlh2WXZadlt2XXZfdmB2YXZidmR2ZXZmdmd2aHZpdmp2bHZt' +
  'dm52cHZxdnJ2c3Z0dnV2dnZ3dnl2enZ8dn92gHaBdoN2hXaJdop2jHaNdo92kHaSdpR2lXaXdph2mnabdpx2nXaedp92oHahdqJ2' +
  'o3aldqZ2p3aodql2qnardqx2rXavdrB2s3a1drZ2t3a4drl2una7drx2vXa+dsB2wXbDdkpVP5bDVyhjzlQJVcBUkXZMdjyF7nd+' +
  'go14MXKYlo2XKGyJW/pPCWOXZrhc+oBIaK6AAmbOdvlRVmWscfF/hIiyUGVZymGzb62CTGNSYu1TJ1QGe2tRpHX0XdRiy412l4pi' +
  'GYBdVziXYn84cn12z2d+dkZkcE8ljdxiF3qRZe1zLGRzYiyCgZh/Z0hybmLMYjRP43RKU55Syn6mkC5ehmicaYCB0X7SaMV4jIZR' +
  'lY1QJIzegt6ABVMSiWVSxHbHdsl2y3bMdtN21XbZdtp23Hbddt524HbhduJ243bkduZ253bodul26nbrdux27XbwdvN29Xb2dvd2' +
  '+nb7dv12/3YAdwJ3A3cFdwZ3CncMdw53D3cQdxF3EncTdxR3FXcWdxd3GHcbdxx3HXcedyF3I3ckdyV3J3cqdyt3LHcudzB3MXcy' +
  'dzN3NHc5dzt3PXc+dz93QndEd0V3RndId0l3SndLd0x3TXdOd093UndTd1R3VXdWd1d3WHdZd1x3hIX5lt1PIVhxmZ1bsWKlYrRm' +
  'eYyNnAZyb2eReLJgUVMXU4iPzIAdjaGUDVDIcgdZ62AZcauIVFnvgixnKHspXfd+LXX1bGaO+I88kDuf1GsZkRR7fF+neNaEPYXV' +
  'a9lr1msBXode+XXtlV1lCl/FX5+PwVjCgX+QW5atl7mPFn8sjUFiv0/YU15TqI+pj6uPTZAHaGpfmIFoiNaci2ErUip2bF+MZdJv' +
  '6G6+W0hkdVGwUcRnGU7JeXyZs3Bdd153X3dgd2R3Z3dpd2p3bXdud293cHdxd3J3c3d0d3V3dnd3d3h3end7d3x3gXeCd4N3hneH' +
  'd4h3iXeKd4t3j3eQd5N3lHeVd5Z3l3eYd5l3mnebd5x3nXeed6F3o3ekd6Z3qHerd613rnevd7F3sne0d7Z3t3e4d7l3une8d753' +
  'wHfBd8J3w3fEd8V3xnfHd8h3yXfKd8t3zHfOd8930HfRd9J303fUd9V31nfYd9l32nfdd95333fgd+F35HfFdXZeu3Pgg61k6GK1' +
  'lOJsWlPDUg9kwpSUey9PG142ghaBioEkbspsc5pVY1xT+lRliOBXDU4DXmVrP3zokBZg5mQcc8GIUGdNYiKNbHcpjseRaV/cgyGF' +
  'EJnCU5WGi2vtYOhgf3DNgjGC006nbM+FzWTZfP1p+WZJg5VTVnunT4xRS21CXG2O0mPJUyyDNoPlZ7R4PWTfW5Rc7l3ni8Zi9Gd6' +
  'jABkumNJh4uZF4wgf/KUp04QlqSYDGYWc+Z36Hfqd+938Hfxd/J39Hf1d/d3+Xf6d/t3/HcDeAR4BXgGeAd4CHgKeAt4DngPeBB4' +
  'E3gVeBl4G3geeCB4IXgieCR4KHgqeCt4LngveDF4MngzeDV4Nng9eD94QXhCeEN4RHhGeEh4SXhKeEt4TXhPeFF4U3hUeFh4WXha' +
  'eFt4XHheeF94YHhheGJ4Y3hkeGV4ZnhneGh4aXhveHB4cXhyeHN4dHh1eHZ4eHh5eHp4e3h9eH54f3iAeIF4gniDeDpXHVw4Xn+V' +
  'f1CggIJTXmVFdTFVIVCFjYRinpQdZzJWbm/iXTVUknBmj29ipGSjY3tfiG/0kOOBsI8YXGhm8V+JbEiWgY1siJFk8HnOV1lqEGJI' +
  'VFhOC3rpYIRv2ot/Yh6Qi5rkeQNU9HUBYxlTYGzfjxtfcJo7gH+fiE86XGSNxX+lZb1wRVGyUWuGB12gW71ibJF0dQyOIHoBYXl7' +
  'x074foV3EU7tgR1S+lFxaqhTh44Elc+WwW5kllpphHiFeIZ4iHiKeIt4j3iQeJJ4lHiVeJZ4mXideJ54oHiieKR4pnioeKl4qnir' +
  'eKx4rXiueK94tXi2eLd4uHi6eLt4vHi9eL94wHjCeMN4xHjGeMd4yHjMeM14znjPeNF40njTeNZ413jYeNp423jceN143njfeOB4' +
  '4XjieON45HjleOZ453jpeOp463jteO5473jwePF483j1ePZ4+Hj5ePt4/Hj9eP54/3gAeQJ5A3kEeQZ5B3kIeQl5CnkLeQx5QHio' +
  'UNd3EGTmiQRZ42PdXX96PWkgTzmCmFUyTq51l3piXope75UbUjlUinB2YySVglclZj9ph5EHVfNtr34iiDNi8H61dSiDwXjMlp6P' +
  'SGH3dM2LZGs6UlCNIWtqgHGE8VYGU85OG07RUZd8i5EHfMNPf47he5x6Z2QUXaxQBoEBdrl87G3gf1FnWFv4W8t4rmQTZKpjK2MZ' +
  'lS1kvo9Ueyl2U2InWUZUeWujUDRiJl6Ga+NON42LiIVfLpANeQ55D3kQeRF5EnkUeRV5FnkXeRh5GXkaeRt5HHkdeR95IHkheSJ5' +
  'I3kleSZ5J3koeSl5KnkreSx5LXkueS95MHkxeTJ5M3k1eTZ5N3k4eTl5PXk/eUJ5Q3lEeUV5R3lKeUt5THlNeU55T3lQeVF5UnlU' +
  'eVV5WHlZeWF5Y3lkeWZ5aXlqeWt5bHlueXB5cXlyeXN5dHl1eXZ5eXl7eXx5fXl+eX95gnmDeYZ5h3mIeYl5i3mMeY15jnmQeZF5' +
  'knkgYD2AxWI5TlVT+JC4Y8aA5mUubEZP7mDhbd6LOV/LhlNfIWNaUWGDY2gAUmNjSI4SUJtcd3n8WzBSO3q8YFOQ13a3X5dfhHZs' +
  'jm9we3ZJe6p381GTkCRYTk/0buqPTGUbe8RypG3ff+FatWKVXjBXgoQsex1eH18SkBR/oJiCY8dumHi5cHhRW5erVzV1Q084dZde' +
  '5mBgWcBtv2uJePxT1ZbLUQFSiWMKVJOUA4zMjTlyn3h2h+2PDYzgU5N5lHmVeZZ5l3mYeZl5m3mceZ15nnmfeaB5oXmieaN5pHml' +
  'eaZ5qHmpeap5q3msea15rnmvebB5sXmyebR5tXm2ebd5uHm8eb95wnnEecV5x3nIecp5zHnOec950HnTedR51nnXedl52nnbedx5' +
  '3XneeeB54XnieeV56Hnqeex57nnxefJ583n0efV59nn3efl5+nn8ef55/3kBegR6BXoHegh6CXoKegx6D3oQehF6EnoTehV6FnoY' +
  'ehl6G3ocegFO73buU4mUdpgOny2VmluiiyJOHE6sUWOEwmGoUgtol09rYLtRHm1cUZZil2VhlkaMF5DYdf2QY3fSa4py7HL7izVY' +
  'eXdMjVxnQJWagKZeIW6SWe967Xc7lbVrrWUOfwZYUVEflvlbqVgoVHKOZmV/mORWnZT+dkGQh2PGVBpZOlmbV7KONWf6jTWCQVLw' +
  'YBVY/oboXEWexE+dmLmLJVp2YIRTfGJPkAKRf5lpYAyAP1EzgBRcdZkxbYxOHXofeiF6InokeiV6Jnoneih6KXoqeit6LHotei56' +
  'L3owejF6Mno0ejV6Nno4ejp6PnpAekF6QnpDekR6RXpHekh6SXpKekt6THpNek56T3pQelJ6U3pUelV6VnpYell6Wnpbelx6XXpe' +
  'el96YHphemJ6Y3pkemV6Znpnemh6aXpqemt6bHptem56b3pxenJ6c3p1ent6fHp9en56gnqFeod6iXqKeot6jHqOeo96kHqTepR6' +
  'mXqaept6nnqheqJ6MI3RU1p/T3sQT09OAJbVbNBz6YUGXmp1+38Kav53kpRBfuFR5nDNU9SPA4Mpja9ybZnbbEpXs4K5ZaqAP2Iy' +
  'lqhZ/06/i7p+PmXyg16XYVXemKWAKlP9iyBUuoCfXrhsOY2sglqRKVQbbAZSt35fVxpxfmyJfEtZ/U7/XyRhqnwwTgFcq2cCh/Bc' +
  'C5XOmK91/XAikK9RHX+9i0lZ5FFbTyZUK1l3ZaSAdVt2YsJikI9FXh9sJnsPT9hPDWejeqR6p3qpeqp6q3queq96sHqxerJ6tHq1' +
  'erZ6t3q4erl6unq7erx6vXq+esB6wXrCesN6xHrFesZ6x3rIesl6ynrMes16znrPetB60XrSetN61HrVetd62Hraett63HrdeuF6' +
  '4nrkeud66Hrpeup663rseu568HrxevJ683r0evV69nr3evh6+3r8ev56AHsBewJ7BXsHewl7DHsNew57EHsSexN7FnsXexh7Gnsc' +
  'ex17H3sheyJ7I3sneyl7LXtubaptj3mxiBdfK3WaYoWP70/ckadlL4FRgZxeUIF0jW9SholLjQ1ZhVDYThyWNnJ5gR+NzFuji0SW' +
  'h1kaf5BUdlYOVuWLOWWCaZmU1naJbnJeGHVGZ9Fn/3qdgHaNH2HGeWJlY42IURpSopQ4f5uAsn6XXC9uYGfZe4t22JqPgZR/1Xwe' +
  'ZFCVP3pKVOVUTGsBZAhiPZ7zgJl1clJpl1uEPGjkhgGWlJbslCpOBFTZfjlo340VgPRmml65fy97MHsyezR7NXs2ezd7OXs7ez17' +
  'P3tAe0F7QntDe0R7RntIe0p7TXtOe1N7VXtXe1l7XHtee197YXtje2R7ZXtme2d7aHtpe2p7a3tse217b3twe3N7dHt2e3h7ent8' +
  'e317f3uBe4J7g3uEe4Z7h3uIe4l7inuLe4x7jnuPe5F7knuTe5Z7mHuZe5p7m3uee597oHuje6R7pXuue697sHuye7N7tXu2e7d7' +
  'uXu6e7t7vHu9e757v3vAe8J7w3vEe8JXP4CXaOVdO2WfUm1gmp+bT6yObFGrWxNf6V1ebPFiIY1xUamU/lKfbN+C13KiV4RnLY0f' +
  'WZyPx4OVVI17ME+9bGRb0VkTn+RTyoaomjeMoYBFZX6Y+lbHli5S3HRQUuFbAmMCiVZO0GIqYPpoc1GYW6BRwomhe4aZUH/vYExw' +
  'L41JUX9eG5BwdMSJLVdFeFJfn5/6lWiPPJvhi3h2QmjcZ+qNNY09UoqP2m7NaAWV7ZD9Vpxn+YjHj8hUxXvIe8l7ynvLe817znvP' +
  'e9B70nvUe9V71nvXe9h723vce95733vge+J743vke+d76Hvpe+t77Hvte+978Hvye/N79Hv1e/Z7+Hv5e/p7+3v9e/97AHwBfAJ8' +
  'A3wEfAV8BnwIfAl8CnwNfA58EHwRfBJ8E3wUfBV8F3wYfBl8GnwbfBx8HXwefCB8IXwifCN8JHwlfCh8KXwrfCx8LXwufC98MHwx' +
  'fDJ8M3w0fDV8Nnw3fDl8Onw7fDx8PXw+fEJ8uJppW3dtJmylTrNbh5pjkahhr5DplytUtW3SW/1RilVVf/B/vGRNY/FlvmGNYApx' +
  'V2xJbC9ZbWcqgtVYjlZqjOtr3ZB9WReA91NpbXVUnVV3g8+DOGi+eYxUVU8IVNJ2iYwClrNsuG1rjRCJZJ46jT9W0Z7VdYhf4HJo' +
  'YPxUqE4qamGIUmBwj8RU2HB5hj+eKm2PWxhfon6JVa9PNHM8VJpTGVAOVHxUTk79X1p09lhrhOGAdIfQcsp8Vm5DfER8RXxGfEd8' +
  'SHxJfEp8S3xMfE58T3xQfFF8UnxTfFR8VXxWfFd8WHxZfFp8W3xcfF18XnxffGB8YXxifGN8ZHxlfGZ8Z3xofGl8anxrfGx8bXxu' +
  'fG98cHxxfHJ8dXx2fHd8eHx5fHp8fnx/fIB8gXyCfIN8hHyFfIZ8h3yIfIp8i3yMfI18jnyPfJB8k3yUfJZ8mXyafJt8oHyhfKN8' +
  'pnynfKh8qXyrfKx8rXyvfLB8tHy1fLZ8t3y4fLp8u3wnX06GLFWkYpJOqmw3YrGC11ROUz5z0W47dRJSFlPdi9Bpil8AYO5tT1ci' +
  'a69zU2jYjxN/YmOjYCRV6nVijBVxo22mW3teUoNMYcSe+nhXhyd8h3bwUfZgTHFDZkxeTWAOjHBwJWOJj71fYmDUht5WwWuUYGdh' +
  'SVPgYGZmP439eRpP6XBHbLOL8ovYfmSDD2ZaWkKbUW33bUGMO20ZT2twt4MWYtFgDZcnjXh5+1E+V/pXOmd4dT1673mVe798wHzC' +
  'fMN8xHzGfMl8y3zOfM980HzRfNJ803zUfNh82nzbfN183nzhfOJ843zkfOV85nznfOl86nzrfOx87XzufPB88XzyfPN89Hz1fPZ8' +
  '93z5fPp8/Hz9fP58/3wAfQF9An0DfQR9BX0GfQd9CH0JfQt9DH0NfQ59D30QfRF9En0TfRR9FX0WfRd9GH0ZfRp9G30cfR19Hn0f' +
  'fSF9I30kfSV9Jn0ofSl9Kn0sfS19Ln0wfTF9Mn0zfTR9NX02fYyAZZn5j8BvpYshnuxZ6X4JfwlUgWfYaJGPTXzGlspTJWC+dXJs' +
  'c1PJWqd+JGPgUQqB8V3fhIBigFFjWw5PbXlCUrhgTm3EW8JboYuwi+JlzF9FlpNZ536qfglWt2c5WXNPtlugUlqDipg+jTJ1vpRH' +
  'UDx69062Z36awVp8a9F2WlcWXDp79JVOcXxRqYBwgnhZBH8ng8Bo7GexeHd442JhY4B77U9qUs9RUIPbaXSS9Y0xjcGJLpWte/ZO' +
  'N304fTl9On07fTx9PX0+fT99QH1BfUJ9Q31EfUV9Rn1HfUh9SX1KfUt9TH1NfU59T31QfVF9Un1TfVR9VX1WfVd9WH1ZfVp9W31c' +
  'fV19Xn1ffWB9YX1ifWN9ZH1lfWZ9Z31ofWl9an1rfWx9bX1vfXB9cX1yfXN9dH11fXZ9eH15fXp9e318fX19fn1/fYB9gX2CfYN9' +
  'hH2FfYZ9h32IfYl9in2LfYx9jX2OfY99kH2RfZJ9k32UfZV9ln2XfZh9ZVAwglFSb5kQboVup236XvVQ3FkGXEZtX2yGdYuEaGhW' +
  'WbKLIFNxkU2WSYUSaQF5JnH2gKROypBHbYSaB1q8VgVk8JTrd6VPGoHhctKJepk0f95+f1JZZXWRf4+Dj+tTlnrtY6Vjhnb4eVeI' +
  'NpYqYqtSgoJUaHBnd2Nrd+16AW3TfuOJ0FkSYsmFpYJMdR9Qy06ldeuLSlz+XUt7pGXRkcpOJW1fiSd9JpXFTiiM249zl0tmgXnR' +
  'j+xweG2ZfZp9m32cfZ19nn2ffaB9oX2ifaN9pH2lfad9qH2pfap9q32sfa19r32wfbF9sn2zfbR9tX22fbd9uH25fbp9u328fb19' +
  'vn2/fcB9wX3CfcN9xH3FfcZ9x33Ifcl9yn3Lfcx9zX3Ofc990H3RfdJ9033UfdV91n3Xfdh92X3afdt93H3dfd59333gfeF94n3j' +
  'feR95X3mfed96H3pfep9633sfe197n3vffB98X3yffN99H31ffZ99334ffl9+n09XLJSRoNiUQ6DW3d2ZricrE7KYL58s3zPfpVO' +
  'ZotvZoiYWZeDWGxlXJWEX8l1Vpffet56wFGvcJh66mN2eqB+lnPtl0VOeHBdTlKRqVNRZedl/IEFgo5UMVyadaCX2GLZcr11RVx5' +
  'msqDQFyAVOl3Pk6ubFqA0mJuY+hdd1HdjR6OL5XxT+VT52CscGdSUGNDnh9aJlA3d3dT4n6FZCtliWKYYxRQNXLJibNRwIvdfkdX' +
  'zIOnlJtRG1T7XPt9/H39ff59/30AfgF+An4DfgR+BX4Gfgd+CH4Jfgp+C34Mfg1+Dn4PfhB+EX4SfhN+FH4VfhZ+F34Yfhl+Gn4b' +
  'fhx+HX4efh9+IH4hfiJ+I34kfiV+Jn4nfih+KX4qfit+LH4tfi5+L34wfjF+Mn4zfjR+NX42fjd+OH45fjp+PH49fj5+P35AfkJ+' +
  'Q35EfkV+Rn5Ifkl+Sn5Lfkx+TX5Ofk9+UH5RflJ+U35UflV+Vn5Xflh+WX5aflt+XH5dfspP43pabeGQj5qAVZZUYVOvVABf6WN3' +
  'ae9RaGEKUipY2FJOVw14C3e3Xndh4HxbYpdiok6VcAOA92LkcGCXd1fbgu9n9WjVeJeY0XnzWLNU71M0bktRO1KiW/6Lr4BDVaZX' +
  'c2BRVy1UenpQYFRbp2OgYuNTY2LHW69n7VSfeuaCd5GTXuSIOFmuVw5j6I3vgFdXd3upT+tfvVs+ayFTUHvCckZo/3c2d/dltVGP' +
  'TtR2v1ylenWETllBm4BQXn5ffmB+YX5ifmN+ZH5lfmZ+Z35ofml+an5rfmx+bX5ufm9+cH5xfnJ+c350fnV+dn53fnh+eX56fnt+' +
  'fH59fn5+f36AfoF+g36EfoV+hn6Hfoh+iX6Kfot+jH6Nfo5+j36QfpF+kn6TfpR+lX6Wfpd+mH6Zfpp+nH6dfp5+rn60frt+vH7W' +
  'fuR+7H75fgp/EH8efzd/OX87fzx/PX8+fz9/QH9Bf0N/Rn9Hf0h/SX9Kf0t/TH9Nf05/T39Sf1N/iJknYYNuZFcGZkZj8FbsYmli' +
  '014UloNXyWKHVSGHSoGjj2ZVsYNlZ1aN3YRqWg9o5mLuexGWcFGcbzCM/WPIidJhBn/CcOVuBXSUafxyyl7OkBdnam1eY7NSYnIB' +
  'gGxP5VlqkdlwnW3SUlBO95ZtlX6FyngvfSFRklfCZIuAe3zqbPFoXmm3UZhTqGiBcs6e8Xv4crt5E28GdE5nzJGknDx5iYNUgw9U' +
  'F2g9TolTsVI+eIZTKVKIUItP0E9Wf1l/W39cf11/Xn9gf2N/ZH9lf2Z/Z39rf2x/bX9vf3B/c391f3Z/d394f3p/e398f31/f3+A' +
  'f4J/g3+Ef4V/hn+Hf4h/iX+Lf41/j3+Qf5F/kn+Tf5V/ln+Xf5h/mX+bf5x/oH+if6N/pX+mf6h/qX+qf6t/rH+tf65/sX+zf7R/' +
  'tX+2f7d/un+7f75/wH/Cf8N/xH/Gf8d/yH/Jf8t/zX/Pf9B/0X/Sf9N/1n/Xf9l/2n/bf9x/3X/ef+J/43/idct6knylbLaWm1KD' +
  'dOlU6U9UgLKD3o9wlcleHGCfbRheW2U4gf6US2C8cMN+rnzJUYFosXxvgiROho/PkX5mrk4FjKlkSoDaUJd1znHlW72PZm+GToJk' +
  'Y5XWXpllF1LCiMhwo1IOczN0l2f3eBaXNE67kN6cy23bUUGNHVTOYrJz8YP2loSfw5Q2T5p/zFF1cHWWrVyGmOZT5E6cbgl0tGlr' +
  'eI+ZWXUYUiR2QW3zZ21RmZ9LgJlUPHu/euR/53/of+p/63/sf+1/73/yf/R/9X/2f/d/+H/5f/p//X/+f/9/AoAHgAiACYAKgA6A' +
  'D4ARgBOAGoAbgB2AHoAfgCGAI4AkgCuALIAtgC6AL4AwgDKANIA5gDqAPIA+gECAQYBEgEWAR4BIgEmAToBPgFCAUYBTgFWAVoBX' +
  'gFmAW4BcgF2AXoBfgGCAYYBigGOAZIBlgGaAZ4BogGuAbIBtgG6Ab4BwgHKAc4B0gHWAdoB3gHiAeYB6gHuAfIB9gIaWhFfiYkeW' +
  'fGkEWgJk03sPb0uWpoJiU4WYkF6JcLNjZFNPhoGck56MeDKX741CjX+eXm+EeVVfRpYuYnSaFVTdlKNPxWVlXGFcFX9Rhi9si1+H' +
  'c+Ru/37mXBtjalvmbnVTcU6gY2V1oWJujyZP0U6mbLZ+uosdhLqHV387kCOVqXuhmviIPYQbbYaa3H6IWbuem3MBeIKGbJqCmhtW' +
  'F1TLV3BOpp5WU8iPCYGSd5KZ7obhbhOF/GZiYStvfoCBgIKAhYCIgIqAjYCOgI+AkICRgJKAlICVgJeAmYCegKOApoCngKiArICw' +
  'gLOAtYC2gLiAuYC7gMWAx4DIgMmAyoDLgM+A0IDRgNKA04DUgNWA2IDfgOCA4oDjgOaA7oD1gPeA+YD7gP6A/4AAgQGBA4EEgQWB' +
  'B4EIgQuBDIEVgReBGYEbgRyBHYEfgSCBIYEigSOBJIElgSaBJ4EogSmBKoErgS2BLoEwgTOBNIE1gTeBOYE6gTuBPIE9gT+BKYyS' +
  'giuD8nYTbNlfvYMrcwWDGpXba9t3xpRvUwKDklE9XoyMOI1ITqtzmmeFaHaRCZdkcaFsCXeSWkGVz2uOfydm0Fu5WZpa6JX3lexO' +
  'DISZhKxq33YwlRtzpmhfWy93mpFhl9x8948cjCVfc3zYecWJzGwch8ZbQl7JaCB39X6VUU1RyVIpWgV/YpfXgs9jhHfQhdJ5Om6Z' +
  'XplZEYVtcBFsv2K/dk9lr2D9lQ5mn4cjnu2UDVR9VCyMeGRAgUGBQoFDgUSBRYFHgUmBTYFOgU+BUoFWgVeBWIFbgVyBXYFegV+B' +
  'YYFigWOBZIFmgWiBaoFrgWyBb4FygXOBdYF2gXeBeIGBgYOBhIGFgYaBh4GJgYuBjIGNgY6BkIGSgZOBlIGVgZaBl4GZgZqBnoGf' +
  'gaCBoYGigaSBpYGngamBq4Gsga2BroGvgbCBsYGygbSBtYG2gbeBuIG5gbyBvYG+gb+BxIHFgceByIHJgcuBzYHOgc+B0IHRgdKB' +
  '04F5ZBGGIWqcgeh4aWRUm7liK2erg6hY2J6rbCBv3ltMlguMX3LQZ8diYXKpTsZZzWuTWK5mVV7fUlVhKGfudmZ3Z3JGev9i6lRQ' +
  'VKCUo5AcWrN+FmxDTnZZEIBIWVdTN3W+lspWIGMRgXxg+ZXWbWJUgZmFUela/YCuWROXKlDlbDxc32JgTz9Te4EGkLpuK4XIYnRe' +
  'vni1ZHtj9V8YWn+RH54/XE9jQoB9W25VSpVNlYVtqGDgZ95y3VGBW9SB1YHWgdeB2IHZgdqB24Hcgd2B3oHfgeCB4YHigeSB5YHm' +
  'geiB6YHrge6B74HwgfGB8oH1gfaB94H4gfmB+oH9gf+BA4IHggiCCYIKgguCDoIPghGCE4IVghaCF4IYghmCGoIdgiCCJIIlgiaC' +
  'J4Ipgi6CMoI6gjyCPYI/gkCCQYJCgkOCRYJGgkiCSoJMgk2CToJQglGCUoJTglSCVYJWgleCWYJbglyCXYJegmCCYYJigmOCZIJl' +
  'gmaCZ4Jpgudi3mxbcm1irpS9fhOBU22cUQRfdFmqUhJgc1mWZlCGn3UqY+Zh73z6i+ZUJ2slnrRr1YVVVHZQpGxqVbSNLHIVXhVg' +
  'NnTNYpJjTHKYX0NuPm0AZVhv2HbQePx2VHUkUttTU06eXsFlKoDWgJtihlQoUq5wjYjRjeFseFTagPlX9IhUjWqWTZFpT5tst1XG' +
  'djB4qGL5cI5vbV/shNpofHj3e6iBC2dPnmdjsHhvVxJ4OZd5YqtiiFI1dNdraoJrgmyCbYJxgnWCdoJ3gniCe4J8goCCgYKDgoWC' +
  'hoKHgomCjIKQgpOClIKVgpaCmoKbgp6CoIKigqOCp4KygrWCtoK6gruCvIK/gsCCwoLDgsWCxoLJgtCC1oLZgtqC3YLigueC6ILp' +
  'guqC7ILtgu6C8ILygvOC9YL2gviC+oL8gv2C/oL/ggCDCoMLgw2DEIMSgxODFoMYgxmDHYMegx+DIIMhgyKDI4MkgyWDJoMpgyqD' +
  'LoMwgzKDN4M7gz2DZFU+gbJ1rnY5U951+1BBXGyLx3tPUEdyl5rYmAJv4nRoeYdkpXf8YpGYK43BVFiAUk5qV/mCDYRzXu1R9nTE' +
  'i09cYVf8bIeYRlo0eESb64+VfFZSUWL6lMZOhoNhhOmDsoTUVzRnA1duZmZtMYzdZhFwH2c6axZoGmK7WQNOxFEGb9Jnj2x2Ucto' +
  'R1lna2Z1Dl0QgVCf12VIeUF5kZp3jYJcXk4BTy9UUVkMeGhWFGzEjwNffWzjbKuLkGM+gz+DQYNCg0SDRYNIg0qDS4NMg02DToNT' +
  'g1WDVoNXg1iDWYNdg2KDcINxg3KDc4N0g3WDdoN5g3qDfoN/g4CDgYOCg4ODhIOHg4iDioOLg4yDjYOPg5CDkYOUg5WDloOXg5mD' +
  'moOdg5+DoYOig6ODpIOlg6aDp4Osg62DroOvg7WDu4O+g7+DwoPDg8SDxoPIg8mDy4PNg86D0IPRg9KD04PVg9eD2YPag9uD3oPi' +
  'g+OD5IPmg+eD6IPrg+yD7YNwYD1tdXJmYo6UxZRDU8GPfnvfTiaMfk7UnrGUs5RNUlxvY5BFbTSMEVhMXSBrSWuqZ1tUVIGMf5lY' +
  'N4U6X6JiR2o5lXJlhGBlaKd3VE6oT+ddmJesZNh/7VzPT416B1IEgxROL2CDeqaUtU+yTuZ5NHTkUrmC0mS9ed1bgWxSl3uPImw+' +
  'UH9TBW7OZHRmMGzFYHeY94uGXjx0d3rLeRhOsZADdEJs2lZLkcVsi406U8aG8mavjkhccZogbu6D74Pzg/SD9YP2g/eD+oP7g/yD' +
  '/oP/gwCEAoQFhAeECIQJhAqEEIQShBOEFIQVhBaEF4QZhBqEG4QehB+EIIQhhCKEI4QphCqEK4QshC2ELoQvhDCEMoQzhDSENYQ2' +
  'hDeEOYQ6hDuEPoQ/hECEQYRChEOERIRFhEeESIRJhEqES4RMhE2EToRPhFCEUoRThFSEVYRWhFiEXYRehF+EYIRihGSEZYRmhGeE' +
  'aIRqhG6Eb4RwhHKEdIR3hHmEe4R8hNZTNlqLn6ONu1MIV6eYQ2ebkclsaFHKdfNirHI4Up1SOn+UcDh2dFNKnrdpbnjAltmIpH82' +
  'ccNxiVHTZ+R05FgYZbdWqYt2mXBi1X75YO1w7FjBTrpOzV/nl/tOpIsDUopZq35UYs1O5WUOYjiDyYRjg42HlHG2brlb0n6XUclj' +
  '1GeJgDmDFYgSUXpbglmxj3NOXWxlUSWJb48ulkqFXnQQlfCVpm3lgjFfkmQSbSiEboHDnF5YW40JTsFTfYR+hH+EgISBhIOEhISF' +
  'hIaEioSNhI+EkISRhJKEk4SUhJWEloSYhJqEm4SdhJ6En4SghKKEo4SkhKWEpoSnhKiEqYSqhKuErISthK6EsISxhLOEtYS2hLeE' +
  'u4S8hL6EwITChMOExYTGhMeEyITLhMyEzoTPhNKE1ITVhNeE2ITZhNqE24TchN6E4YTihOSE54TohOmE6oTrhO2E7oTvhPGE8oTz' +
  'hPSE9YT2hPeE+IT5hPqE+4T9hP6EAIUBhQKFHk9jZVFo01UnThRkmpprYsJaX3Rygqlt7mjnUI6DAnhAZzlSmWyxfrtQZVVecVt7' +
  'UmbKc+uCSWdxXCBSfXFriOqVVZbFZGGNs4GEVVVsR2Iuf5JYJE9GVU+NTGYKThpc84iiaE5jDXrncI2C+lL2lxFc6FS1kM1+YllK' +
  'jceGDIINgmaNRGQEXFFhiW0+eb6LN3gzdXtUOE+rjvFtIFrFfl55iGyhW3ZaGnW+gE5hF27wWB91JXVyckdT834DhQSFBYUGhQeF' +
  'CIUJhQqFC4UNhQ6FD4UQhRKFFIUVhRaFGIUZhRuFHIUdhR6FIIUihSOFJIUlhSaFJ4UohSmFKoUthS6FL4UwhTGFMoUzhTSFNYU2' +
  'hT6FP4VAhUGFQoVEhUWFRoVHhUuFTIVNhU6FT4VQhVGFUoVThVSFVYVXhViFWoVbhVyFXYVfhWCFYYVihWOFZYVmhWeFaYVqhWuF' +
  'bIVthW6Fb4VwhXGFc4V1hXaFd4V4hXyFfYV/hYCFgYUBd9t2aVLcgCNXCF4xWe5yvWV/bteLOFxxhkFT83f+YvZlwE7fmICGnlvG' +
  'i/JT4nd/T05cdprLWQ9fOnnrWBZO/2eLTu1ik4odkL9SL2bcVWxWApDVTo1PypFwmQ9sAl5DYKRbxonVizZlS2KWmYhb/1uIYy5V' +
  '11Mmdn1RLIWiZ7NoimuSYpOP1FMSgtFtj3VmTk6NcFufca+FkWbZZnJ/AIfNniCfXlwvZ/CPEWhfZw1i1nqFWLZecGUxb4KFg4WG' +
  'hYiFiYWKhYuFjIWNhY6FkIWRhZKFk4WUhZWFloWXhZiFmYWahZ2FnoWfhaCFoYWihaOFpYWmhaeFqYWrhayFrYWxhbKFs4W0hbWF' +
  'toW4hbqFu4W8hb2FvoW/hcCFwoXDhcSFxYXGhceFyIXKhcuFzIXNhc6F0YXShdSF1oXXhdiF2YXahduF3YXehd+F4IXhheKF44Xl' +
  'heaF54XoheqF64Xshe2F7oXvhfCF8YXyhfOF9IX1hfaF94X4hVVgN1INgFRkcIgpdQVeE2j0YhyXzFM9cgGMNGxhdw56LlSsd3qY' +
  'HIL0i1V4FGfBcK9llWQ2Vh1gwXn4Ux1Oe2uGgPpb41XbVjpPPE9ymfNdfmc4gAJggpgBkItbvIv1ixxkWILeZP1Vz4JlkddPIH0f' +
  'kJ9881BRWK9uv1vJi4OAeJGchJd7fYaLlo+W5X7Tmo54gVxXekKQp5ZfeVlbX2MLe9GErWgGVSl/EHQifQGVQGJMWNZOg1t5WVRY' +
  '+YX6hfyF/YX+hQCGAYYChgOGBIYGhgeGCIYJhgqGC4YMhg2GDoYPhhCGEoYThhSGFYYXhhiGGYYahhuGHIYdhh6GH4YghiGGIoYj' +
  'hiSGJYYmhiiGKoYrhiyGLYYuhi+GMIYxhjKGM4Y0hjWGNoY3hjmGOoY7hj2GPoY/hkCGQYZChkOGRIZFhkaGR4ZIhkmGSoZLhkyG' +
  'UoZThlWGVoZXhliGWYZbhlyGXYZfhmCGYYZjhmSGZYZmhmeGaIZphmqGbXMeY0uOD47OgNSCrGLwU/BsXpEqWQFgcGxNV0pkKo0r' +
  'duluW1eAavB1bW8tjAiMZlfva5KIs3iiY/lTrXBkbFhYKmQCWOBom4EQVdZ8GFC6jsxtn43rcI9jm23UbuZ+BIRDaAOQ2G12lqiL' +
  'V1l5cuSFfoG8dYqKr2hUUiKOEZXQY5iYRI58VVNP/2aPVtVglW1DUklcKVn7bWtYMHUcdWxgFIJGgRFjYWfijzp38400jcGUFl6F' +
  'UyxUw3Bthm+GcIZyhnOGdIZ1hnaGd4Z4hoOGhIaFhoaGh4aIhomGjoaPhpCGkYaShpSGloaXhpiGmYaahpuGnoafhqCGoYaihqWG' +
  'poarhq2GroayhrOGt4a4hrmGu4a8hr2Gvoa/hsGGwobDhsWGyIbMhs2G0obThtWG1obXhtqG3IbdhuCG4YbihuOG5YbmhueG6Ibq' +
  'huuG7IbvhvWG9ob3hvqG+4b8hv2G/4YBhwSHBYcGhwuHDIcOhw+HEIcRhxSHFodAbPdeXFCtTq1eOmNHghqQUGhukbN3DFTclGRf' +
  '5Xp2aEVjUnvfftt1d1CVYjRZD5D4UcN5gXr+VpJfFJCCbWBcH1cQVFRRTW7iVqhjk5h/gRWHKokAkB5Ub1zAgdZiWGIxgTWeQJZu' +
  'mnyaLWmlWdNiPlUWY8dU2YY8bQNa5nSciGprFllMjC9ffm6pc32YOE73cIxbl3g9Y1pmlnbLYJtbSVoHTlWBamyLc6FOiWdRf4Bf' +
  '+mUbZ9hfhFkBWhmHG4cdhx+HIIckhyaHJ4cohyqHK4cshy2HL4cwhzKHM4c1hzaHOIc5hzqHPIc9h0CHQYdCh0OHRIdFh0aHSodL' +
  'h02HT4dQh1GHUodUh1WHVodYh1qHW4dch12HXodfh2GHYodmh2eHaIdph2qHa4dsh22Hb4dxh3KHc4d1h3eHeId5h3qHf4eAh4GH' +
  'hIeGh4eHiYeKh4yHjoePh5CHkYeSh5SHlYeWh5iHmYeah5uHnIedh56HoIehh6KHo4ekh81drl9xU+aX3Y9FaPRWL1XfYDpOTW/0' +
  'fseCDoTUWR9PKk8+XKx+KmcahXNUT3XDgIJVT5tNTy1uE4wJXHBha1MfdiluioaHZfuVuX47VDN6Cn3uleFVwX/udB1jF4ehbZ16' +
  'EWKhZWdT4WODbOtdXFSolExOYWzsi0tc4GWcgqdoPlQ0VMtrZmuUTkJjSFMegg1Prk9eVwpi/pZkZmly/1KhUp9g74sUZplxkGd/' +
  'iVJ4/XdwZjtWOFQhlXpypYemh6eHqYeqh66HsIexh7KHtIe2h7eHuIe5h7uHvIe+h7+HwYfCh8OHxIfFh8eHyIfJh8yHzYfOh8+H' +
  '0IfUh9WH1ofXh9iH2Yfah9yH3Yfeh9+H4Yfih+OH5Ifmh+eH6Ifph+uH7Ifth++H8Ifxh/KH84f0h/WH9of3h/iH+of7h/yH/Yf/' +
  'hwCIAYgCiASIBYgGiAeICIgJiAuIDIgNiA6ID4gQiBGIEogUiBeIGIgZiBqIHIgdiB6IH4ggiCOIAHpvYAxeiWCdgRVZ3GCEce9w' +
  'qm5QbIByhGqtiC1eYE6zWpxV45QXbft8mZYPYsZ+jnd+hiNTHpeWj4dm4VygT+1yC06mUw9ZE1SAYyiVSFHZTpycpH64VCSNVIg3' +
  'gvKVjm0mX8xaPmZplrBzLnO/U3qBhZmhf6pbd5ZQlr9++HaiU3aVmZmxe0SJWG5hTtR/ZXnmi/NgzVSrTnmY911has9QEVRhjCeE' +
  'XXgEl0pS7lSjVgCViG21W8ZtU2YkiCWIJogniCiIKYgqiCuILIgtiC6IL4gwiDGIM4g0iDWINog3iDiIOog7iD2IPog/iEGIQohD' +
  'iEaIR4hIiEmISohLiE6IT4hQiFGIUohTiFWIVohYiFqIW4hciF2IXohfiGCIZohniGqIbYhviHGIc4h0iHWIdoh4iHmIeoh7iHyI' +
  'gIiDiIaIh4iJiIqIjIiOiI+IkIiRiJOIlIiViJeImIiZiJqIm4idiJ6In4igiKGIo4iliKaIp4ioiKmIqogPXF1bIWiWgHhVEXtI' +
  'ZVRpm05Ha06Hi5dPUx9jOmSqkJxlwYAQjJlRsGh4U/mHyGHEbPtsIoxRXKqFr4IMlSNrm4+wZftfw1/hT0WIH2ZlgSlz+mB0URFS' +
  'i1diX6KQTIiSkXheT2cnYNNZRFH2UfiACFN5bMSWinERT+5Pnn89Z8VVCJXAeZaI436fWAxiAJdahhhWe5iQX7iLxIRXkdlT7WWP' +
  'Xlx1ZGBufX9a6n7tfmmPp1WjW6xgy2WEc6yIroiviLCIsoiziLSItYi2iLiIuYi6iLuIvYi+iL+IwIjDiMSIx4jIiMqIy4jMiM2I' +
  'z4jQiNGI04jWiNeI2ojbiNyI3YjeiOCI4YjmiOeI6YjqiOuI7IjtiO6I74jyiPWI9oj3iPqI+4j9iP+IAIkBiQOJBIkFiQaJB4kI' +
  'iQmJC4kMiQ2JDokPiRGJFIkViRaJF4kYiRyJHYkeiR+JIIkiiSOJJIkmiSeJKIkpiSyJLYkuiS+JMYkyiTOJNYk3iQmQY3Ypd9p+' +
  'dJebhWZbdHrqlkCIy1KPcapf7GXii/tbb5rhXYlrW2yti6+LCpDFj4tTvGImni2eQFQrTr2CWXKchhZdWYivbcWW0VSaTraLCXG9' +
  'VAmW33D5bdB2JU4UeBKHqVz2XgCKnJgOlo5wv2xEWaljPHdNiBRvc4IwWNVxjFMaeMGWAVVmXzBxtFsajIyag2suWS+e53loZ2xi' +
  'b0+hdYp/C20zlids8E7SdXtRN2g+b4CQcIGWWXZ0OIk5iTqJO4k8iT2JPok/iUCJQolDiUWJRolHiUiJSYlKiUuJTIlNiU6JT4lQ' +
  'iVGJUolTiVSJVYlWiVeJWIlZiVqJW4lciV2JYIlhiWKJY4lkiWWJZ4loiWmJaolriWyJbYluiW+JcIlxiXKJc4l0iXWJdol3iXiJ' +
  'eYl6iXyJfYl+iYCJgomEiYWJh4mIiYmJiomLiYyJjYmOiY+JkImRiZKJk4mUiZWJlomXiZiJmYmaiZuJnImdiZ6Jn4mgiaGJR2Qn' +
  'XGWQkXojjNpZrFQAgm+DgYkAgDBpTlY2gDdyzpG2UV9OdZiWYxpO9lPzZkuBHFmybQBO+Vg7U9Zj8ZSdTwpPY4iQmDdZV5D7eepO' +
  '8ICRdYJsnFvoWV1fBWmBhhpQ8l1ZTuN35U56gpFiE2aRkHlcv055X8aBOJCEgKt1pk7UiA9hxWvGX0lOynaibuOLrosKjNGLAl/8' +
  'f8x/zn41g2uD4Fa3a/OXNJb7WR9U9pTrbcVbbpk5XBVfkJaiiaOJpImliaaJp4moiamJqomriayJrYmuia+JsImxibKJs4m0ibWJ' +
  'tom3ibiJuYm6ibuJvIm9ib6Jv4nAicOJzYnTidSJ1YnXidiJ2Ynbid2J34ngieGJ4onkieeJ6InpieqJ7Intie6J8InxifKJ9In1' +
  'ifaJ94n4ifmJ+on7ifyJ/Yn+if+JAYoCigOKBIoFigaKCIoJigqKC4oMig2KDooPihCKEYoSihOKFIoVihaKF4oYihmKGoobihyK' +
  'HYpwU/GCMWp0WnCelF4of7mDJIQlhGeDR4fOj2KNyHZxX5aYbHggZt9U5WJjT8OByHW4Xs2WCo75ho9U82yMbThsf2DHUih1fV4Y' +
  'T6Bg518kXDF1rpDAlLlyuWw4bkmRCWfLU/NTUU/JkfGLyFN8XsKP5G2OTsJ2hmlehhphBoJZT95PPpB8nAlhHW4UboWWiE4xWuiW' +
  'Dk5/XLl5h1vti71/iXPfV4uCwZABVEeQu1XqXKFfCGEya/FysoCJih6KH4ogiiGKIoojiiSKJYomiieKKIopiiqKK4osii2KLoov' +
  'ijCKMYoyijOKNIo1ijaKN4o4ijmKOoo7ijyKPYo/ikCKQYpCikOKRIpFikaKR4pJikqKS4pMik2KTopPilCKUYpSilOKVIpVilaK' +
  'V4pYilmKWopbilyKXYpeil+KYIphimKKY4pkimWKZopnimiKaYpqimuKbIptim6Kb4pwinGKcopzinSKdYp2ineKeIp6inuKfIp9' +
  'in6Kf4qAinRt01vViISYa4xtmjOeCm6kUUNRo1eBiJ9T9GOVj+1WWFQGVz9zkG4Yf9yP0YI/YShgYpbwZqZ+io3DjaWUs1ykfAhn' +
  'pmAFlhiAkU7nkABTaJZBUdCPdIVdkVVm9ZdVWx1TOHhCZz1oyVR+cLBbfY+NUShXsVQSZYJmXo1DjQ+BbIRtkN98/1H7haNn6WWh' +
  'b6SGgY5qViCQgnZ2cOVxI43pYhlS/Ww8jQ5gnliOYf5mYI1OYrNVI24tZ2ePgYqCioOKhIqFioaKh4qIiouKjIqNio6Kj4qQipGK' +
  'koqUipWKloqXipiKmYqaipuKnIqdip6Kn4qgiqGKooqjiqSKpYqmiqeKqIqpiqqKq4qsiq2KroqvirCKsYqyirOKtIq1iraKt4q4' +
  'irmKuoq7iryKvYq+ir+KwIrBisKKw4rEisWKxorHisiKyYrKisuKzIrNis6Kz4rQitGK0orTitSK1YrWiteK2IrZitqK24rcit2K' +
  '3orfiuCK4YriiuOK4ZT4lSh3BWioaYtUTU64cMiLWGSLZYVbhHo6UOhbu3fha3mKmHy+bM92qWWXjy1dVVw4hghoYFMYYtl6W279' +
  'fh9q4HpwXzNvIF+MY6htVmcIThBeJo3XTsCANHaclttiLWZ+YrxsdY1ncWl/RlGHgOxTbpCYYvJU8IaZjwWAF5UXhdmPWW3Nc59l' +
  'H3cEdSd4+4EejYiUpk+VZ7l1yosHly9jR5U1lriEI2NBd4Ff8HKJThRgdGXvYmNrP2XkiuWK5orniuiK6YrqiuuK7Irtiu6K74rw' +
  'ivGK8orzivSK9Yr2iveK+Ir5ivqK+4r8iv2K/or/igCLAYsCiwOLBIsFiwaLCIsJiwqLC4sMiw2LDosPixCLEYsSixOLFIsVixaL' +
  'F4sYixmLGosbixyLHYseix+LIIshiyKLI4skiyWLJ4soiymLKosriyyLLYsuiy+LMIsxizKLM4s0izWLNos3iziLOYs6izuLPIs9' +
  'iz6LP4tAi0GLQotDi0SLRYsnXsd10ZDBi52CnWcvZTFUGIfld6KAAoFBbEtOx35MgPR2DWmWa2diPFCET0BXB2Nia76N6lPoZbh+' +
  '118aY7dj84H0gW5/HF7ZXDZSembpeRp6KI2ZcNR13m67bJJ6LU7FduBfn5R3iMh+zXm/gM2R8k4XTx+CaFTeXTJtzIulfHSPmIAa' +
  'XpJUsXaZWzxmpJrgcypo24YxZypz+IvbixCQ+XrbcG5xxGKpdzFWO05XhPFnqVLAhi6N+JRRe0aLR4tIi0mLSotLi0yLTYtOi0+L' +
  'UItRi1KLU4tUi1WLVotXi1iLWYtai1uLXItdi16LX4tgi2GLYotji2SLZYtni2iLaYtqi2uLbYtui2+LcItxi3KLc4t0i3WLdot3' +
  'i3iLeYt6i3uLfIt9i36Lf4uAi4GLgouDi4SLhYuGi4eLiIuJi4qLi4uMi42LjouPi5CLkYuSi5OLlIuVi5aLl4uYi5mLmoubi5yL' +
  'nYuei5+LrIuxi7uLx4vQi+qLCYwejE9P6GxdeXuak2Iqcv1iE04WeGyPsGRajcZ7aWiEXsWIhlmeZO5YtnIOaSWV/Y9YjWBXAH8G' +
  'jMZRSWPZYlNTTGgidAGDTJFEVUB3fHBKbXlRqFREjf9Zy27EbVxbK33UTn18025QW+qBDW5XWwOb1Wgqjpdb/H47YLV+uZBwjU9Z' +
  'zWPfebONUlPPZVZ5xYs7lsR+u5SCfjRWiZEAZ2p/Clx1kChm5l1QT95nWlBcT1BXp14Q6BHoEugT6BToOIw5jDqMO4w8jD2MPow/' +
  'jECMQoxDjESMRYxIjEqMS4xNjE6MT4xQjFGMUoxTjFSMVoxXjFiMWYxbjFyMXYxejF+MYIxjjGSMZYxmjGeMaIxpjGyMbYxujG+M' +
  'cIxxjHKMdIx1jHaMd4x7jHyMfYx+jH+MgIyBjIOMhIyGjIeMiIyLjI2MjoyPjJCMkYySjJOMlYyWjJeMmYyajJuMnIydjJ6Mn4yg' +
  'jKGMooyjjKSMpYymjKeMqIypjKqMq4ysjK2MjU4MTkBREE7/XkVTFU6YTh5OMptsW2lWKE66eT9OFVNHTi1ZO3JuUxBs31bkgJeZ' +
  '02t+dxefNk6fThCfXE5pTpNOiIJbW2xVD1bETo1TnVOjU6VTrlNll12NGlP1UyZTLlM+U1yNZlNjUwJSCFIOUi1SM1I/UkBSTFJe' +
  'UmFSXFKvhH1SglKBUpBSk1KCUVR/u07DTslOwk7oTuFO607eThtP804iT2RP9U4lTydPCU8rT15PZ084ZVpPXU+ujK+MsIyxjLKM' +
  's4y0jLWMtoy3jLiMuYy6jLuMvIy9jL6Mv4zAjMGMwozDjMSMxYzGjMeMyIzJjMqMy4zMjM2MzozPjNCM0YzSjNOM1IzVjNaM14zY' +
  'jNmM2ozbjNyM3YzejN+M4IzhjOKM44zkjOWM5oznjOiM6YzqjOuM7IztjO6M74zwjPGM8ozzjPSM9Yz2jPeM+Iz5jPqM+4z8jP2M' +
  '/oz/jACNAY0CjQONBI0FjQaNB40IjQmNCo0LjQyNDY1fT1dPMk89T3ZPdE+RT4lPg0+PT35Pe0+qT3xPrE+UT+ZP6E/qT8VP2k/j' +
  'T9xP0U/fT/hPKVBMUPNPLFAPUC5QLVD+TxxQDFAlUChQflBDUFVQSFBOUGxQe1ClUKdQqVC6UNZQBlHtUOxQ5lDuUAdRC1HdTj1s' +
  'WE9lT85PoJ9GbHR8blH9XcmemJmBURRZ+VINUweKEFPrURlZVVGgTlZRs05uiKSItU4UgdKIgHk0WwOIuH+rUbFRvVG8UQ6ND40Q' +
  'jRGNEo0TjRSNFY0WjReNGI0ZjRqNG40cjSCNUY1SjVeNX41ljWiNaY1qjWyNbo1vjXGNco14jXmNeo17jXyNfY1+jX+NgI2CjYON' +
  'ho2HjYiNiY2MjY2Njo2PjZCNko2TjZWNlo2XjZiNmY2ajZuNnI2djZ6NoI2hjaKNpI2ljaaNp42ojamNqo2rjayNrY2uja+NsI2y' +
  'jbaNt425jbuNvY3AjcGNwo3FjceNyI3JjcqNzY3QjdKN043UjcdRllGiUaVRoIumi6eLqou0i7WLt4vCi8OLy4vPi86L0ovTi9SL' +
  '1ovYi9mL3Ivfi+CL5Ivoi+mL7ovwi/OL9ov5i/yL/4sAjAKMBIwHjAyMD4wRjBKMFIwVjBaMGYwbjBiMHYwfjCCMIYwljCeMKowr' +
  'jC6ML4wyjDOMNYw2jGlTelMdliKWIZYxliqWPZY8lkKWSZZUll+WZ5ZslnKWdJaIlo2Wl5awlpeQm5CdkJmQrJChkLSQs5C2kLqQ' +
  '1Y3YjdmN3I3gjeGN4o3ljeaN543pje2N7o3wjfGN8o30jfaN/I3+jf+NAI4BjgKOA44EjgaOB44IjguODY4OjhCOEY4SjhOOFY4W' +
  'jheOGI4ZjhqOG44cjiCOIY4kjiWOJo4njiiOK44tjjCOMo4zjjSONo43jjiOO448jj6OP45DjkWORo5Mjk2OTo5PjlCOU45UjlWO' +
  'Vo5XjliOWo5bjlyOXY5ejl+OYI5hjmKOY45kjmWOZ45ojmqOa45ujnGOuJCwkM+QxZC+kNCQxJDHkNOQ5pDikNyQ15DbkOuQ75D+' +
  'kASRIpEekSORMZEvkTmRQ5FGkQ1SQlmiUqxSrVK+Uv9U0FLWUvBS31Pucc139F71UfxRL5u2UwFfWnXvXUxXqVehV35YvFjFWNFY' +
  'KVcsVypXM1c5Vy5XL1dcVztXQldpV4VXa1eGV3xXe1doV21XdldzV61XpFeMV7JXz1enV7RXk1egV9VX2FfaV9lX0le4V/RX71f4' +
  'V+RX3VdzjnWOd454jnmOeo57jn2Ofo6AjoKOg46EjoaOiI6JjoqOi46Mjo2Ojo6RjpKOk46VjpaOl46YjpmOmo6bjp2On46gjqGO' +
  'oo6jjqSOpY6mjqeOqI6pjqqOrY6ujrCOsY6zjrSOtY62jreOuI65jruOvI69jr6Ov47AjsGOwo7DjsSOxY7GjseOyI7JjsqOy47M' +
  'js2Oz47QjtGO0o7TjtSO1Y7WjteO2I7ZjtqO247cjt2O3o7fjuCO4Y7ijuOO5I4LWA1Y/VftVwBYHlgZWERYIFhlWGxYgViJWJpY' +
  'gFiomRmf/2F5gn2Cf4KPgoqCqIKEgo6CkYKXgpmCq4K4gr6CsILIgsqC44KYgreCroLLgsyCwYKpgrSCoYKqgp+CxILOgqSC4YIJ' +
  'g/eC5IIPgweD3IL0gtKC2IIMg/uC04IRgxqDBoMUgxWD4ILVghyDUYNbg1yDCIOSgzyDNIMxg5uDXoMvg0+DR4NDg1+DQIMXg2CD' +
  'LYM6gzODZoNlg+WO5o7njuiO6Y7qjuuO7I7tju6O747wjvGO8o7zjvSO9Y72jveO+I75jvqO+478jv2O/o7/jgCPAY8CjwOPBI8F' +
  'jwaPB48IjwmPCo8LjwyPDY8Ojw+PEI8RjxKPE48UjxWPFo8XjxiPGY8ajxuPHI8djx6PH48gjyGPIo8jjySPJY8mjyePKI8pjyqP' +
  'K48sjy2PLo8vjzCPMY8yjzOPNI81jzaPN484jzmPOo87jzyPPY8+jz+PQI9Bj0KPQ49Ej2iDG4Npg2yDaoNtg26DsIN4g7ODtIOg' +
  'g6qDk4Ocg4WDfIO2g6mDfYO4g3uDmIOeg6iDuoO8g8GDAYTlg9iDB1gYhAuE3YP9g9aDHIQ4hBGEBoTUg9+DD4QDhPiD+YPqg8WD' +
  'wIMmhPCD4YNchFGEWoRZhHOEh4SIhHqEiYR4hDyERoRphHaEjISOhDGEbYTBhM2E0ITmhL2E04TKhL+EuoTghKGEuYS0hJeE5YTj' +
  'hAyFDXU4hfCEOYUfhTqFRY9Gj0ePSI9Jj0qPS49Mj02PTo9Pj1CPUY9Sj1OPVI9Vj1aPV49Yj1mPWo9bj1yPXY9ej1+PYI9hj2KP' +
  'Y49kj2WPao+Aj4yPko+dj6CPoY+ij6SPpY+mj6ePqo+sj62Pro+vj7KPs4+0j7WPt4+4j7qPu4+8j7+PwI/Dj8aPyY/Kj8uPzI/N' +
  'j8+P0o/Wj9eP2o/gj+GP44/nj+yP74/xj/KP9I/1j/aP+o/7j/yP/o//jweQCJAMkA6QE5AVkBiQVoU7hf+E/IRZhUiFaIVkhV6F' +
  'eoWid0OFcoV7haSFqIWHhY+FeYWuhZyFhYW5hbeFsIXThcGF3IX/hSeGBYYphhaGPIb+XghfPFlBWTeAVVlaWVhZD1MiXCVcLFw0' +
  'XExiamKfYrtiymLaYtdi7mIiY/ZiOWNLY0NjrWP2Y3FjemOOY7RjbWOsY4pjaWOuY7xj8mP4Y+Bj/2PEY95jzmNSZMZjvmNFZEFk' +
  'C2QbZCBkDGQmZCFkXmSEZG1klmQZkByQI5AkkCWQJ5AokCmQKpArkCyQMJAxkDKQM5A0kDeQOZA6kD2QP5BAkEOQRZBGkEiQSZBK' +
  'kEuQTJBOkFSQVZBWkFmQWpBckF2QXpBfkGCQYZBkkGaQZ5BpkGqQa5BskG+QcJBxkHKQc5B2kHeQeJB5kHqQe5B8kH6QgZCEkIWQ' +
  'hpCHkImQipCMkI2QjpCPkJCQkpCUkJaQmJCakJyQnpCfkKCQpJClkKeQqJCpkKuQrZCykLeQvJC9kL+QwJB6ZLdkuGSZZLpkwGTQ' +
  'ZNdk5GTiZAllJWUuZQtf0l8ZdRFfX1PxU/1T6VPoU/tTElQWVAZUS1RSVFNUVFRWVENUIVRXVFlUI1QyVIJUlFR3VHFUZFSaVJtU' +
  'hFR2VGZUnVTQVK1UwlS0VNJUp1SmVNNU1FRyVKNU1VS7VL9UzFTZVNpU3FSpVKpUpFTdVM9U3lQbVedUIFX9VBRV81QiVSNVD1UR' +
  'VSdVKlVnVY9VtVVJVW1VQVVVVT9VUFU8VcKQw5DGkMiQyZDLkMyQzZDSkNSQ1ZDWkNiQ2ZDakN6Q35DgkOOQ5JDlkOmQ6pDskO6Q' +
  '8JDxkPKQ85D1kPaQ95D5kPqQ+5D8kP+QAJEBkQORBZEGkQeRCJEJkQqRC5EMkQ2RDpEPkRCREZESkRORFJEVkRaRF5EYkRqRG5Ec' +
  'kR2RH5EgkSGRJJElkSaRJ5EokSmRKpErkSyRLZEukTCRMpEzkTSRNZE2kTeROJE6kTuRPJE9kT6RP5FAkUGRQpFEkTdVVlV1VXZV' +
  'd1UzVTBVXFWLVdJVg1WxVblViFWBVZ9VflXWVZFVe1XfVb1VvlWUVZlV6lX3VclVH1bRVetV7FXUVeZV3VXEVe9V5VXyVfNVzFXN' +
  'VehV9VXkVZSPHlYIVgxWAVYkViNW/lUAVidWLVZYVjlWV1YsVk1WYlZZVlxWTFZUVoZWZFZxVmtWe1Z8VoVWk1avVtRW11bdVuFW' +
  '9VbrVvlW/1YEVwpXCVccVw9eGV4UXhFeMV47XjxeRZFHkUiRUZFTkVSRVZFWkViRWZFbkVyRX5FgkWaRZ5FokWuRbZFzkXqRe5F8' +
  'kYCRgZGCkYORhJGGkYiRipGOkY+Rk5GUkZWRlpGXkZiRmZGckZ2RnpGfkaCRoZGkkaWRppGnkaiRqZGrkayRsJGxkbKRs5G2kbeR' +
  'uJG5kbuRvJG9kb6Rv5HAkcGRwpHDkcSRxZHGkciRy5HQkdKR05HUkdWR1pHXkdiR2ZHakduR3ZHekd+R4JHhkeKR45HkkeWRN15E' +
  'XlReW15eXmFejFx6XI1ckFyWXIhcmFyZXJFcmlycXLVcoly9XKxcq1yxXKNcwVy3XMRc0lzkXMtc5VwCXQNdJ10mXS5dJF0eXQZd' +
  'G11YXT5dNF09XWxdW11vXV1da11LXUpdaV10XYJdmV2dXXOMt13FXXNfd1+CX4dfiV+MX5VfmV+cX6hfrV+1X7xfYohhX61ysHK0' +
  'crdyuHLDcsFyznLNctJy6HLvculy8nL0cvdyAXPzcgNz+nLmkeeR6JHpkeqR65Hske2R7pHvkfCR8ZHykfOR9JH1kfaR95H4kfmR' +
  '+pH7kfyR/ZH+kf+RAJIBkgKSA5IEkgWSBpIHkgiSCZIKkguSDJINkg6SD5IQkhGSEpITkhSSFZIWkheSGJIZkhqSG5Ickh2SHpIf' +
  'kiCSIZIikiOSJJIlkiaSJ5IokimSKpIrkiySLZIuki+SMJIxkjKSM5I0kjWSNpI3kjiSOZI6kjuSPJI9kj6SP5JAkkGSQpJDkkSS' +
  'RZL7chdzE3MhcwpzHnMdcxVzInM5cyVzLHM4czFzUHNNc1dzYHNsc29zfnMbgiVZ55gkWQJZY5lnmWiZaZlqmWuZbJl0mXeZfZmA' +
  'mYSZh5mKmY2ZkJmRmZOZlJmVmYBekV6LXpZepV6gXrletV6+XrNeU43SXtFe217oXupeuoHEX8lf1l/PXwNg7l8EYOFf5F/+XwVg' +
  'BmDqX+1f+F8ZYDVgJmAbYA9gDWApYCtgCmA/YCFgeGB5YHtgemBCYEaSR5JIkkmSSpJLkkySTZJOkk+SUJJRklKSU5JUklWSVpJX' +
  'kliSWZJakluSXJJdkl6SX5JgkmGSYpJjkmSSZZJmkmeSaJJpkmqSa5Jskm2SbpJvknCScZJyknOSdZJ2kneSeJJ5knqSe5J8kn2S' +
  'fpJ/koCSgZKCkoOShJKFkoaSh5KIkomSipKLkoySjZKPkpCSkZKSkpOSlJKVkpaSl5KYkpmSmpKbkpySnZKekp+SoJKhkqKSo5Kk' +
  'kqWSppKnkmpgfWCWYJpgrWCdYINgkmCMYJtg7GC7YLFg3WDYYMZg2mC0YCBhJmEVYSNh9GAAYQ5hK2FKYXVhrGGUYadht2HUYfVh' +
  '3V+zlumV65XxlfOV9ZX2lfyV/pUDlgSWBpYIlgqWC5YMlg2WD5YSlhWWFpYXlhmWGpYsTj9yFWI1bFRsXGxKbKNshWyQbJRsjGxo' +
  'bGlsdGx2bIZsqWzQbNRsrWz3bPhs8WzXbLJs4GzWbPps62zubLFs02zvbP5sqJKpkqqSq5Kskq2Sr5KwkrGSspKzkrSStZK2kreS' +
  'uJK5krqSu5K8kr2SvpK/ksCSwZLCksOSxJLFksaSx5LJksqSy5LMks2SzpLPktCS0ZLSktOS1JLVktaS15LYktmS2pLbktyS3ZLe' +
  'kt+S4JLhkuKS45LkkuWS5pLnkuiS6ZLqkuuS7JLtku6S75LwkvGS8pLzkvSS9ZL2kveS+JL5kvqS+5L8kv2S/pL/kgCTAZMCkwOT' +
  'BJMFkwaTB5MIkwmTOW0nbQxtQ21IbQdtBG0ZbQ5tK21NbS5tNW0abU9tUm1UbTNtkW1vbZ5toG1ebZNtlG1cbWBtfG1jbRpux23F' +
  'bd5tDm6/beBtEW7mbd1t2W0WbqttDG6ubStubm5Obmtusm5fboZuU25UbjJuJW5Ebt9usW6YbuBuLW/ibqVup269brtut27XbrRu' +
  'z26PbsJun25ib0ZvR28kbxVv+W4vbzZvS290bypvCW8pb4lvjW+Mb3hvcm98b3pv0W8KkwuTDJMNkw6TD5MQkxGTEpMTkxSTFZMW' +
  'kxeTGJMZkxqTG5Mckx2THpMfkyCTIZMikyOTJJMlkyaTJ5MokymTKpMrkyyTLZMuky+TMJMxkzKTM5M0kzWTNpM3kziTOZM6kzuT' +
  'PJM9kz+TQJNBk0KTQ5NEk0WTRpNHk0iTSZNKk0uTTJNNk06TT5NQk1GTUpNTk1STVZNWk1eTWJNZk1qTW5Nck12TXpNfk2CTYZNi' +
  'k2OTZJNlk2aTZ5Nok2mTa5PJb6dvuW+2b8Jv4W/ub95v4G/vbxpwI3AbcDlwNXBPcF5wgFuEW5Vbk1ulW7hbL3WemjRk5FvuWzCJ' +
  '8FtHjgeLto/Tj9WP5Y/uj+SP6Y/mj/OP6I8FkASQC5AmkBGQDZAWkCGQNZA2kC2QL5BEkFGQUpBQkGiQWJBikFuQuWZ0kH2QgpCI' +
  'kIOQi5BQX1dfVl9YXztcq1RQXFlccVtjXGZcvH8qXylfLV90gjxfO5tuXIFZg1mNWalZqlmjWWyTbZNuk2+TcJNxk3KTc5N0k3WT' +
  'dpN3k3iTeZN6k3uTfJN9k36Tf5OAk4GTgpODk4SThZOGk4eTiJOJk4qTi5OMk42TjpOQk5GTkpOTk5STlZOWk5eTmJOZk5qTm5Oc' +
  'k52TnpOfk6CToZOik6OTpJOlk6aTp5Ook6mTqpOrk6yTrZOuk6+TsJOxk7KTs5O0k7WTtpO3k7iTuZO6k7uTvJO9k76Tv5PAk8GT' +
  'wpPDk8STxZPGk8eTyJPJk8uTzJPNk5dZylmrWZ5ZpFnSWbJZr1nXWb5ZBVoGWt1ZCFrjWdhZ+VkMWglaMlo0WhFaI1oTWkBaZ1pK' +
  'WlVaPFpiWnVa7ICqWptad1p6Wr5a61qyWtJa1Fq4WuBa41rxWtZa5lrYWtxaCVsXWxZbMls3W0BbFVwcXFpbZVtzW1FbU1tiW3Wa' +
  'd5p4mnqaf5p9moCagZqFmoiaipqQmpKak5qWmpiam5qcmp2an5qgmqKao5qlmqean36hfqN+pX6ofql+zpPPk9CT0ZPSk9OT1JPV' +
  'k9eT2JPZk9qT25Pck92T3pPfk+CT4ZPik+OT5JPlk+aT55Pok+mT6pPrk+yT7ZPuk++T8JPxk/KT85P0k/WT9pP3k/iT+ZP6k/uT' +
  '/JP9k/6T/5MAlAGUApQDlASUBZQGlAeUCJQJlAqUC5QMlA2UDpQPlBCUEZQSlBOUFJQVlBaUF5QYlBmUGpQblByUHZQelB+UIJQh' +
  'lCKUI5QklCWUJpQnlCiUKZQqlCuULJQtlC6UrX6wfr5+wH7BfsJ+yX7Lfsx+0H7Uftd+237gfuF+6H7rfu5+737xfvJ+DX/2fvp+' +
  '+37+fgF/An8Dfwd/CH8Lfwx/D38RfxJ/F38Zfxx/G38ffyF/In8jfyR/JX8mfyd/Kn8rfyx/LX8vfzB/MX8yfzN/NX96Xn91210+' +
  'dZWQjnORc65zonOfc89zwnPRc7dzs3PAc8lzyHPlc9lzfJgKdOlz53Pec7pz8nMPdCp0W3QmdCV0KHQwdC50LHQvlDCUMZQylDOU' +
  'NJQ1lDaUN5Q4lDmUOpQ7lDyUPZQ/lECUQZRClEOURJRFlEaUR5RIlEmUSpRLlEyUTZROlE+UUJRRlFKUU5RUlFWUVpRXlFiUWZRa' +
  'lFuUXJRdlF6UX5RglGGUYpRjlGSUZZRmlGeUaJRplGqUbJRtlG6Ub5RwlHGUcpRzlHSUdZR2lHeUeJR5lHqUe5R8lH2UfpR/lICU' +
  'gZSClIOUhJSRlJaUmJTHlM+U05TUlNqU5pT7lByVIJUbdBp0QXRcdFd0VXRZdHd0bXR+dJx0jnSAdIF0h3SLdJ50qHSpdJB0p3TS' +
  'dLp06pfrl+yXTGdTZ15nSGdpZ6Vnh2dqZ3NnmGenZ3VnqGeeZ61ni2d3Z3xn8GcJaNhnCmjpZ7BnDGjZZ7Vn2mezZ91nAGjDZ7hn' +
  '4mcOaMFn/WcyaDNoYGhhaE5oYmhEaGRog2gdaFVoZmhBaGdoQGg+aEpoSWgpaLVoj2h0aHdok2hraMJobmn8aB9pIGn5aCeVM5U9' +
  'lUOVSJVLlVWVWpVglW6VdJV1lXeVeJV5lXqVe5V8lX2VfpWAlYGVgpWDlYSVhZWGlYeViJWJlYqVi5WMlY2VjpWPlZCVkZWSlZOV' +
  'lJWVlZaVl5WYlZmVmpWblZyVnZWelZ+VoJWhlaKVo5WklaWVppWnlaiVqZWqlauVrJWtla6Vr5WwlbGVspWzlbSVtZW2lbeVuJW5' +
  'lbqVu5W8lb2VvpW/lcCVwZXClcOVxJXFlcaVx5XIlcmVypXLlSRp8GgLaQFpV2njaBBpcWk5aWBpQmldaYRpa2mAaZhpeGk0acxp' +
  'h2mIac5piWlmaWNpeWmbaadpu2mraa1p1GmxacFpymnfaZVp4GmNaf9pL2rtaRdqGGplavJpRGo+aqBqUGpbajVqjmp5aj1qKGpY' +
  'anxqkWqQaqlql2qrajdzUnOBa4Jrh2uEa5Jrk2uNa5prm2uha6pra49tj3GPco9zj3WPdo94j3ePeY96j3yPfo+Bj4KPhI+Hj4uP' +
  'zJXNlc6Vz5XQldGV0pXTldSV1ZXWldeV2JXZldqV25Xcld2V3pXfleCV4ZXileOV5JXlleaV55Xslf+VB5YTlhiWG5YeliCWI5Yk' +
  'liWWJpYnliiWKZYrliyWLZYvljCWN5Y4ljmWOpY+lkGWQ5ZKlk6WT5ZRllKWU5ZWlleWWJZZllqWXJZdll6WYJZjlmWWZpZrlm2W' +
  'bpZvlnCWcZZzlniWeZZ6lnuWfJZ9ln6Wf5aAloGWgpaDloSWh5aJloqWjY+Oj4+PmI+aj86OC2IXYhtiH2IiYiFiJWIkYixi54Hv' +
  'dPR0/3QPdRF1E3U0Ze5l72XwZQpmGWZyZwNmFWYAZoVw92YdZjRmMWY2ZjVmBoBfZlRmQWZPZlZmYWZXZndmhGaMZqdmnWa+Zttm' +
  '3GbmZulmMo0zjTaNO409jUCNRY1GjUiNSY1HjU2NVY1ZjceJyonLicyJzonPidCJ0Ylucp9yXXJmcm9yfnJ/coRyi3KNco9yknII' +
  'YzJjsGOMlo6WkZaSlpOWlZaWlpqWm5adlp6Wn5aglqGWopajlqSWpZamlqiWqZaqlquWrJatlq6Wr5axlrKWtJa1lreWuJa6lruW' +
  'v5bClsOWyJbKlsuW0JbRltOW1JbWlteW2JbZltqW25bclt2W3pbfluGW4pbjluSW5ZbmlueW65bslu2W7pbwlvGW8pb0lvWW+Jb6' +
  'lvuW/Jb9lv+WApcDlwWXCpcLlwyXEJcRlxKXFJcVlxeXGJcZlxqXG5cdlx+XIJc/ZNhkBIDqa/Nr/Wv1a/lrBWwHbAZsDWwVbBhs' +
  'GWwabCFsKWwkbCpsMmw1ZVVla2VNclJyVnIwcmKGFlKfgJyAk4C8gApnvYCxgKuArYC0gLeA54DogOmA6oDbgMKAxIDZgM2A14AQ' +
  'Z92A64DxgPSA7YANgQ6B8oD8gBVnEoFajDaBHoEsgRiBMoFIgUyBU4F0gVmBWoFxgWCBaYF8gX2BbYFngU1YtVqIgYKBkYHVbqOB' +
  'qoHMgSZnyoG7gSGXIpcjlySXJZcmlyeXKJcplyuXLJculy+XMZczlzSXNZc2lzeXOpc7lzyXPZc/l0CXQZdCl0OXRJdFl0aXR5dI' +
  'l0mXSpdLl0yXTZdOl0+XUJdRl1SXVZdXl1iXWpdcl12XX5djl2SXZpdnl2iXapdrl2yXbZdul2+XcJdxl3KXdZd3l3iXeZd6l3uX' +
  'fZd+l3+XgJeBl4KXg5eEl4aXh5eIl4mXipeMl46Xj5eQl5OXlZeWl5eXmZeal5uXnJedl8GBpoEkazdrOWtDa0ZrWWvRmNKY05jV' +
  'mNmY2piza0BfwmvziZBlUZ+TZbxlxmXEZcNlzGXOZdJl1mWAcJxwlnCdcLtwwHC3cKtwsXDocMpwEHETcRZxL3ExcXNxXHFocUVx' +
  'cnFKcXhxenGYcbNxtXGocaBx4HHUcedx+XEdcihybHAYcWZxuXE+Yj1iQ2JIYkliO3lAeUZ5SXlbeVx5U3laeWJ5V3lgeW95Z3l6' +
  'eYV5inmaead5s3nRX9Bfnpefl6GXopekl6WXppenl6iXqZeql6yXrpewl7GXs5e1l7aXt5e4l7mXupe7l7yXvZe+l7+XwJfBl8KX' +
  'w5fEl8WXxpfHl8iXyZfKl8uXzJfNl86Xz5fQl9GX0pfTl9SX1ZfWl9eX2JfZl9qX25fcl92X3pffl+CX4Zfil+OX5Jfll+iX7pfv' +
  'l/CX8Zfyl/SX95f4l/mX+pf7l/yX/Zf+l/+XAJgBmAKYA5gEmAWYBpgHmAiYCZgKmAuYDJgNmA6YPGBdYFpgZ2BBYFlgY2CrYAZh' +
  'DWFdYalhnWHLYdFhBmKAgH+Ak2z2bPxt9nf4dwB4CXgXeBh4EXirZS14HHgdeDl4Ong7eB94PHgleCx4I3gpeE54bXhWeFd4JnhQ' +
  'eEd4THhqeJt4k3iaeId4nHiheKN4sni5eKV41HjZeMl47HjyeAV59HgTeSR5Hnk0eZuf+Z77nvye8XYEdw13+XYHdwh3Gncidxl3' +
  'LXcmdzV3OHdQd1F3R3dDd1p3aHcPmBCYEZgSmBOYFJgVmBaYF5gYmBmYGpgbmByYHZgemB+YIJghmCKYI5gkmCWYJpgnmCiYKZgq' +
  'mCuYLJgtmC6YL5gwmDGYMpgzmDSYNZg2mDeYOJg5mDqYO5g8mD2YPpg/mECYQZhCmEOYRJhFmEaYR5hImEmYSphLmEyYTZhOmE+Y' +
  'UJhRmFKYU5hUmFWYVphXmFiYWZhamFuYXJhdmF6YX5hgmGGYYphjmGSYZZhmmGeYaJhpmGqYa5hsmG2Ybphid2V3f3eNd313gHeM' +
  'd5F3n3egd7B3tXe9dzp1QHVOdUt1SHVbdXJ1eXWDdVh/YX9ff0iKaH90f3F/eX+Bf35/zXbldjKIhZSGlIeUi5SKlIyUjZSPlJCU' +
  'lJSXlJWUmpSblJyUo5SklKuUqpStlKyUr5SwlLKUtJS2lLeUuJS5lLqUvJS9lL+UxJTIlMmUypTLlMyUzZTOlNCU0ZTSlNWU1pTX' +
  'lNmU2JTblN6U35TglOKU5JTllOeU6JTqlG+YcJhxmHKYc5h0mIuYjpiSmJWYmZijmKiYqZiqmKuYrJitmK6Yr5iwmLGYspizmLSY' +
  'tZi2mLeYuJi5mLqYu5i8mL2Yvpi/mMCYwZjCmMOYxJjFmMaYx5jImMmYypjLmMyYzZjPmNCY1JjWmNeY25jcmN2Y4JjhmOKY45jk' +
  'mOWY5pjpmOqY65jsmO2Y7pjvmPCY8ZjymPOY9Jj1mPaY95j4mPmY+pj7mPyY/Zj+mP+YAJkBmQKZA5kEmQWZBpkHmemU65TulO+U' +
  '85T0lPWU95T5lPyU/ZT/lAOVApUGlQeVCZUKlQ2VDpUPlRKVE5UUlRWVFpUYlRuVHZUelR+VIpUqlSuVKZUslTGVMpU0lTaVN5U4' +
  'lTyVPpU/lUKVNZVElUWVRpVJlUyVTpVPlVKVU5VUlVaVV5VYlVmVW5VelV+VXZVhlWKVZJVllWaVZ5VolWmVapVrlWyVb5VxlXKV' +
  'c5U6led37HfJltV57Xnjeet5BnpHXQN6AnoeehR6CJkJmQqZC5kMmQ6ZD5kRmRKZE5kUmRWZFpkXmRiZGZkamRuZHJkdmR6ZH5kg' +
  'mSGZIpkjmSSZJZkmmSeZKJkpmSqZK5ksmS2ZL5kwmTGZMpkzmTSZNZk2mTeZOJk5mTqZO5k8mT2ZPpk/mUCZQZlCmUOZRJlFmUaZ' +
  'R5lImUmZSplLmUyZTZlOmU+ZUJlRmVKZU5lWmVeZWJlZmVqZW5lcmV2ZXplfmWCZYZlimWSZZplzmXiZeZl7mX6ZgpmDmYmZOXo3' +
  'elF6z56lmXB6iHaOdpN2mXakdt504HQsdSCeIp4onimeKp4rniyeMp4xnjaeOJ43njmeOp4+nkGeQp5EnkaeR55InkmeS55Mnk6e' +
  'UZ5VnleeWp5bnlyeXp5jnmaeZ55onmmeap5rnmyecZ5tnnOeknWUdZZ1oHWddax1o3WzdbR1uHXEdbF1sHXDdcJ11nXNdeN16HXm' +
  'deR163XndQN28XX8df91EHYAdgV2DHYXdgp2JXYYdhV2GXaMmY6ZmpmbmZyZnZmemZ+ZoJmhmaKZo5mkmaaZp5mpmaqZq5msma2Z' +
  'rpmvmbCZsZmymbOZtJm1mbaZt5m4mbmZupm7mbyZvZm+mb+ZwJnBmcKZw5nEmcWZxpnHmciZyZnKmcuZzJnNmc6Zz5nQmdGZ0pnT' +
  'mdSZ1ZnWmdeZ2JnZmdqZ25ncmd2Z3pnfmeCZ4ZnimeOZ5JnlmeaZ55nomemZ6pnrmeyZ7Znume+Z8JnxmfKZ85n0mfWZ9pn3mfiZ' +
  '+Zkbdjx2InYgdkB2LXYwdj92NXZDdj52M3ZNdl52VHZcdlZ2a3Zvdsp/5np4enl6gHqGeoh6lXqmeqB6rHqoeq16s3pkiGmIcoh9' +
  'iH+IgoiiiMaIt4i8iMmI4ojOiOOI5YjxiBqJ/IjoiP6I8IghiRmJE4kbiQqJNIkriTaJQYlmiXuJi3XlgLJ2tHbcdxKAFIAWgByA' +
  'IIAigCWAJoAngCmAKIAxgAuANYBDgEaATYBSgGmAcYCDiXiYgJiDmPqZ+5n8mf2Z/pn/mQCaAZoCmgOaBJoFmgaaB5oImgmaCpoL' +
  'mgyaDZoOmg+aEJoRmhKaE5oUmhWaFpoXmhiaGZoamhuaHJodmh6aH5ogmiGaIpojmiSaJZommieaKJopmiqaK5osmi2aLpovmjCa' +
  'MZoymjOaNJo1mjaaN5o4mjmaOpo7mjyaPZo+mj+aQJpBmkKaQ5pEmkWaRppHmkiaSZpKmkuaTJpNmk6aT5pQmlGaUppTmlSaVZpW' +
  'mleaWJpZmomYjJiNmI+YlJiamJuYnpifmKGYopilmKaYTYZUhmyGboZ/hnqGfIZ7hqiGjYaLhqyGnYanhqOGqoaThqmGtobEhrWG' +
  'zoawhrqGsYavhsmGz4a0humG8Ybyhu2G84bQhhOH3ob0ht+G2IbRhgOHB4f4hgiHCocNhwmHI4c7hx6HJYcuhxqHPodIhzSHMYcp' +
  'hzeHP4eChyKHfYd+h3uHYIdwh0yHboeLh1OHY4d8h2SHWYdlh5OHr4eoh9KHWppbmlyaXZpeml+aYJphmmKaY5pkmmWaZppnmmia' +
  'aZpqmmuacpqDmomajZqOmpSalZqZmqaaqZqqmquarJqtmq6ar5qymrOatJq1mrmau5q9mr6av5rDmsSaxprHmsiayZrKms2azprP' +
  'mtCa0prUmtWa1prXmtma2prbmtya3ZremuCa4prjmuSa5Zrnmuia6Zrqmuya7prwmvGa8przmvSa9Zr2mvea+Jr6mvya/Zr+mv+a' +
  'AJsBmwKbBJsFmwabxoeIh4WHrYeXh4OHq4flh6yHtYezh8uH04e9h9GHwIfKh9uH6ofgh+6HFogTiP6HCogbiCGIOYg8iDZ/Qn9E' +
  'f0V/EIL6ev16CHsDewR7FXsKeyt7D3tHezh7KnsZey57MXsgeyV7JHszez57HntYe1p7RXt1e0x7XXtge257e3tie3J7cXuQe6Z7' +
  'p3u4e6x7nXuoe4V7qnuce6J7q3u0e9F7wXvMe9172nvle+Z76nsMfP57/HsPfBZ8C3wHmwmbCpsLmwybDZsOmxCbEZsSmxSbFZsW' +
  'mxebGJsZmxqbG5scmx2bHpsgmyGbIpskmyWbJpsnmyibKZsqmyubLJstmy6bMJsxmzObNJs1mzabN5s4mzmbOps9mz6bP5tAm0ab' +
  'SptLm0ybTptQm1KbU5tVm1abV5tYm1mbWptbm1ybXZtem1+bYJthm2KbY5tkm2WbZptnm2ibaZtqm2ubbJttm26bb5twm3Gbcptz' +
  'm3SbdZt2m3ebeJt5m3qbe5sffCp8Jnw4fEF8QHz+gQGCAoIEguyBRIghgiKCI4Itgi+CKIIrgjiCO4IzgjSCPoJEgkmCS4JPglqC' +
  'X4Jogn6IhYiIiNiI34heiZ1/n3+nf69/sH+yf3x8SWWRfJ18nHyefKJ8sny8fL18wXzHfMx8zXzIfMV813zofG6CqGa/f85/1X/l' +
  'f+F/5n/pf+5/83/4fHd9pn2ufUd+m364nrSec42EjZSNkY2xjWeNbY1HjEmMSpFQkU6RT5FkkXybfZt+m3+bgJuBm4Kbg5uEm4Wb' +
  'hpuHm4ibiZuKm4ubjJuNm46bj5uQm5GbkpuTm5SblZuWm5ebmJuZm5qbm5ucm52bnpufm6CboZuim6ObpJulm6abp5uom6mbqpur' +
  'm6ybrZuum6+bsJuxm7Kbs5u0m7Wbtpu3m7ibuZu6m7ubvJu9m76bv5vAm8GbwpvDm8SbxZvGm8ebyJvJm8qby5vMm82bzpvPm9Cb' +
  '0ZvSm9Ob1JvVm9ab15vYm9mb2pvbm2KRYZFwkWmRb5F9kX6RcpF0kXmRjJGFkZCRjZGRkaKRo5Gqka2RrpGvkbWRtJG6kVWMfp64' +
  'jeuNBY5ZjmmOtY2/jbyNuo3EjdaN143ajd6Nzo3PjduNxo3sjfeN+I3jjfmN+43kjQmO/Y0Ujh2OH44sji6OI44vjjqOQI45jjWO' +
  'PY4xjkmOQY5CjlGOUo5KjnCOdo58jm+OdI6Fjo+OlI6QjpyOno54jIKMioyFjJiMlIybZdaJ3onaidyJ3Jvdm96b35vgm+Gb4pvj' +
  'm+Sb5Zvmm+eb6Jvpm+qb65vsm+2b7pvvm/Cb8Zvym/Ob9Jv1m/ab95v4m/mb+pv7m/yb/Zv+m/+bAJwBnAKcA5wEnAWcBpwHnAic' +
  'CZwKnAucDJwNnA6cD5wQnBGcEpwTnBScFZwWnBecGJwZnBqcG5wcnB2cHpwfnCCcIZwinCOcJJwlnCacJ5wonCmcKpwrnCycLZwu' +
  'nC+cMJwxnDKcM5w0nDWcNpw3nDicOZw6nDuc5Ynrie+JPoomi1OX6Zbzlu+WBpcBlwiXD5cOlyqXLZcwlz6XgJ+Dn4Wfhp+Hn4if' +
  'iZ+Kn4yf/p4Lnw2fuZa8lr2WzpbSlr934JaOkq6SyJI+k2qTypOPkz6Ua5R/nIKchZyGnIeciJwjeoucjpyQnJGckpyUnJWcmpyb' +
  'nJ6cn5ygnKGcopyjnKWcppynnKicqZyrnK2crpywnLGcspyznLSctZy2nLecupy7nLycvZzEnMWcxpzHnMqcy5w8nD2cPpw/nECc' +
  'QZxCnEOcRJxFnEacR5xInEmcSpxLnEycTZxOnE+cUJxRnFKcU5xUnFWcVpxXnFicWZxanFucXJxdnF6cX5xgnGGcYpxjnGScZZxm' +
  'nGecaJxpnGqca5xsnG2cbpxvnHCccZxynHOcdJx1nHacd5x4nHmcepx7nH2cfpyAnIOchJyJnIqcjJyPnJOclpyXnJicmZydnKqc' +
  'rJyvnLmcvpy/nMCcwZzCnMicyZzRnNKc2pzbnOCc4ZzMnM2czpzPnNCc05zUnNWc15zYnNmc3JzdnN+c4px8l4WXkZeSl5SXr5er' +
  'l6OXspe0l7GasJq3mlietpq6mryawZrAmsWawprLmsya0ZpFm0ObR5tJm0ibTZtRm+iYDZkumVWZVJnfmuGa5prvmuua+5rtmvma' +
  'CJsPmxObH5sjm72evp47foKeh56Inouekp7Wk52en57bntye3Z7gnt+e4p7pnuee5Z7qnu+eIp8sny+fOZ83nz2fPp9En+Oc5Jzl' +
  'nOac55zonOmc6pzrnOyc7ZzunO+c8JzxnPKc85z0nPWc9pz3nPic+Zz6nPuc/Jz9nP6c/5wAnQGdAp0DnQSdBZ0GnQedCJ0JnQqd' +
  'C50MnQ2dDp0PnRCdEZ0SnROdFJ0VnRadF50YnRmdGp0bnRydHZ0enR+dIJ0hnSKdI50knSWdJp0nnSidKZ0qnSudLJ0tnS6dL50w' +
  'nTGdMp0znTSdNZ02nTedOJ05nTqdO508nT2dPp0/nUCdQZ1CnTTiNeI24jfiOOI54jriO+I84j3iPuI/4kDiQeJC4kPiROJF4kbi' +
  'R+JI4kniSuJL4kziTeJO4k/iUOJR4lLiU+JU4lXiVuJX4ljiWeJa4lviXOJd4l7iX+Jg4mHiYuJj4mTiZeJm4mfiaOJp4mria+Js' +
  '4m3ibuJv4nDiceJy4nPidOJ14nbid+J44nnieuJ74nzifeJ+4n/igOKB4oLig+KE4oXihuKH4ojiieKK4ovijOKN4o7ij+KQ4pHi' +
  'Q51EnUWdRp1HnUidSZ1KnUudTJ1NnU6dT51QnVGdUp1TnVSdVZ1WnVedWJ1ZnVqdW51cnV2dXp1fnWCdYZ1inWOdZJ1lnWadZ51o' +
  'nWmdap1rnWydbZ1unW+dcJ1xnXKdc510nXWddp13nXideZ16nXudfJ19nX6df52AnYGdgp2DnYSdhZ2GnYediJ2JnYqdi52MnY2d' +
  'jp2PnZCdkZ2SnZOdlJ2VnZadl52YnZmdmp2bnZydnZ2enZ+doJ2hnaKdkuKT4pTileKW4pfimOKZ4prim+Kc4p3inuKf4qDioeKi' +
  '4qPipOKl4qbip+Ko4qniquKr4qzireKu4q/isOKx4rLis+K04rXituK34rjiueK64rvivOK94r7iv+LA4sHiwuLD4sTixeLG4sfi' +
  'yOLJ4sriy+LM4s3izuLP4tDi0eLS4tPi1OLV4tbi1+LY4tni2uLb4tzi3eLe4t/i4OLh4uLi4+Lk4uXi5uLn4uji6eLq4uvi7OLt' +
  '4u7i7+KjnaSdpZ2mnaedqJ2pnaqdq52sna2drp2vnbCdsZ2ynbOdtJ21nbadt524nbmdup27nbydvZ2+nb+dwJ3BncKdw53EncWd' +
  'xp3HncidyZ3KncudzJ3Nnc6dz53QndGd0p3TndSd1Z3Wnded2J3Zndqd253cnd2d3p3fneCd4Z3ineOd5J3lnead553onemd6p3r' +
  'neyd7Z3une+d8J3xnfKd8530nfWd9p33nfid+Z36nfud/J39nf6d/50AngGeAp7w4vHi8uLz4vTi9eL24vfi+OL54vri++L84v3i' +
  '/uL/4gDjAeMC4wPjBOMF4wbjB+MI4wnjCuML4wzjDeMO4w/jEOMR4xLjE+MU4xXjFuMX4xjjGeMa4xvjHOMd4x7jH+Mg4yHjIuMj' +
  '4yTjJeMm4yfjKOMp4yrjK+Ms4y3jLuMv4zDjMeMy4zPjNOM14zbjN+M44znjOuM74zzjPeM+4z/jQONB40LjQ+NE40XjRuNH40jj' +
  'SeNK40vjTONN4wOeBJ4FngaeB54IngmeCp4LngyeDZ4Ong+eEJ4RnhKeE54UnhWeFp4XnhieGZ4anhueHJ4dnh6eJJ4nni6eMJ40' +
  'njuePJ5Ank2eUJ5SnlOeVJ5WnlmeXZ5fnmCeYZ5inmWebp5vnnKedJ51nnaed554nnmeep57nnyefZ6AnoGeg56EnoWehp6Jnoqe' +
  'jJ6Nno6ej56QnpGelJ6Vnpael56Ynpmemp6bnpyenp6gnqGeop6jnqSepZ6nnqieqZ6qnk7jT+NQ41HjUuNT41TjVeNW41fjWONZ' +
  '41rjW+Nc413jXuNf42DjYeNi42PjZONl42bjZ+No42njauNr42zjbeNu42/jcONx43Ljc+N043XjduN343jjeeN643vjfON9437j' +
  'f+OA44HjguOD44TjheOG44fjiOOJ44rji+OM443jjuOP45DjkeOS45PjlOOV45bjl+OY45njmuOb45zjneOe45/joOOh46Ljo+Ok' +
  '46XjpuOn46jjqeOq46vjq56snq2erp6vnrCesZ6ynrOetZ62nreeuZ66nryev57AnsGewp7DnsWexp7Hnsieyp7Lnsye0J7SntOe' +
  '1Z7Wntee2Z7ant6e4Z7jnuSe5p7onuue7J7tnu6e8J7xnvKe8570nvWe9p73nvie+p79nv+eAJ8BnwKfA58EnwWfBp8HnwifCZ8K' +
  'nwyfD58RnxKfFJ8VnxafGJ8anxufHJ8dnx6fH58hnyOfJJ8lnyafJ58onymfKp8rny2fLp8wnzGfrOOt467jr+Ow47HjsuOz47Tj' +
  'teO247fjuOO547rju+O8473jvuO/48DjwePC48PjxOPF48bjx+PI48njyuPL48zjzePO48/j0OPR49Lj0+PU49Xj1uPX49jj2ePa' +
  '49vj3OPd497j3+Pg4+Hj4uPj4+Tj5ePm4+fj6OPp4+rj6+Ps4+3j7uPv4/Dj8ePy4/Pj9OP14/bj9+P44/nj+uP74/zj/eP+4//j' +
  'AOQB5ALkA+QE5AXkBuQH5AjkCeQynzOfNJ81nzafOJ86nzyfP59An0GfQp9Dn0WfRp9Hn0ifSZ9Kn0ufTJ9Nn06fT59Sn1OfVJ9V' +
  'n1afV59Yn1mfWp9bn1yfXZ9en1+fYJ9hn2KfY59kn2WfZp9nn2ifaZ9qn2ufbJ9tn26fb59wn3Gfcp9zn3SfdZ92n3efeJ95n3qf' +
  'e598n32ffp+Bn4KfjZ+On4+fkJ+Rn5Kfk5+Un5Wflp+Xn5ifnJ+dn56foZ+in6OfpJ+lnyz5efmV+ef58fkK5AvkDOQN5A7kD+QQ' +
  '5BHkEuQT5BTkFeQW5BfkGOQZ5BrkG+Qc5B3kHuQf5CDkIeQi5CPkJOQl5CbkJ+Qo5CnkKuQr5CzkLeQu5C/kMOQx5DLkM+Q05DXk' +
  'NuQ35DjkOeQ65DvkPOQ95D7kP+RA5EHkQuRD5ETkReRG5EfkSORJ5ErkS+RM5E3kTuRP5FDkUeRS5FPkVORV5FbkV+RY5FnkWuRb' +
  '5FzkXeRe5F/kYORh5GLkY+Rk5GXkZuRn5Az6DfoO+g/6EfoT+hT6GPof+iD6Ifoj+iT6J/oo+in6gS4W6BfoGOiELnM0RzSILosu' +
  'tJ+eNRo2DjaMLpcubjkYObWfzznfOXM60Dm2n7efTjtuPOA8py4x6Lifqi5WQF9Bri43Q7Muti63LjvosUOsQ7su3UPWRGFGTEa5' +
  'nyNHKUd8R41Hyi5HSXpJfUmCSYNJhUmGSZ9Jm0m3SbZJup9V6KNMn0ygTKFMd0yiTBNNFE0VTRZNF00YTRlNrk27n2jkaeRq5Gvk' +
  'bORt5G7kb+Rw5HHkcuRz5HTkdeR25HfkeOR55Hrke+R85H3kfuR/5IDkgeSC5IPkhOSF5Ibkh+SI5InkiuSL5IzkjeSO5I/kkOSR' +
  '5JLkk+SU5JXkluSX5JjkmeSa5JvknOSd5J7kn+Sg5KHkouSj5KTkpeSm5KfkqOSp5Krkq+Ss5K3kruSv5LDkseSy5LPktOS15Lbk' +
  't+S45LnkuuS75LzkveS+5L/kwOTB5MLkw+TE5MXk';

module.exports.GBK_TABLE_B64 = GBK_TABLE_B64;

});
__define('src/core/gbk.js', function(module, exports, __require){
const { base64DecodeToBin } = __require('./utils.js');
const { GBK_TABLE_B64 } = __require('./gbk-table-data.js');
// Built-in GBK codec — the third-level decode fallback (host decodeText
// hook -> TextDecoder -> this) for runtimes with neither, e.g. bare
// QuickJS. Coverage: the full WHATWG GBK index (GB2312 complete, GBK
// extensions included); gb18030 4-byte sequences are NOT covered (their
// bytes degrade to U+FFFD per byte).
// Size cost: GBK_TABLE_B64 is 63,840 chars in the bundle (~62 KB); the
// table is materialized (23,940 code points) lazily on first use only.
let _table = null, _rev = null;
function table() {
  if (_table === null) {
    const bin = base64DecodeToBin(GBK_TABLE_B64);
    let s = '';
    for (let i = 0; i + 1 < bin.length; i += 2) s += String.fromCharCode(bin.charCodeAt(i) | (bin.charCodeAt(i + 1) << 8));
    _table = s;
  }
  return _table;
}
function trailIndex(t) { return t < 0x7F ? t - 0x40 : t - 0x41; }
function isGbkCharset(label) {
  const n = String(label || '').toLowerCase().replace(/[\s_]/g, '');
  return n === 'gbk' || n === 'gb2312' || n === 'gb-2312' || n === 'gb18030' || n === 'x-gbk' || n === 'chinese' || n === 'csgb2312' || n === 'iso-ir-58';
}
function decodeGbk(bytes) {
  const t = table();
  let out = '', i = 0;
  const n = bytes ? bytes.length : 0;
  while (i < n) {
    const b = bytes[i] & 0xff;
    if (b < 0x80) { out += String.fromCharCode(b); i++; continue; }
    if (b === 0x80) { out += '\u20AC'; i++; continue; } // WHATWG GBK: 0x80 is the euro sign
    if (i + 1 < n) {
      const tr = bytes[i + 1] & 0xff;
      if (tr >= 0x40 && tr <= 0xFE && tr !== 0x7F) { out += String.fromCharCode(t.charCodeAt((b - 0x81) * 190 + trailIndex(tr))); i += 2; continue; }
    }
    out += '\uFFFD'; i++;
  }
  return out;
}
function revMap() {
  if (_rev === null) {
    const t = table(); const map = new Map();
    for (let idx = 0; idx < t.length; idx++) { const cp = t.charCodeAt(idx); if (cp !== 0xFFFD && !map.has(cp)) map.set(cp, idx); }
    _rev = map;
  }
  return _rev;
}
// Unmappable characters become 0x3F ('?'), matching Java GBK encoders.
function encodeGbk(str) {
  const map = revMap();
  const out = []; const s = String(str == null ? '' : str);
  for (let i = 0; i < s.length; i++) {
    let cp = s.codePointAt(i); if (cp > 0xFFFF) i++;
    if (cp < 0x80) { out.push(cp); continue; }
    if (cp === 0x20AC) { out.push(0x80); continue; }
    const idx = map.get(cp);
    if (idx === undefined) { out.push(0x3F); continue; }
    out.push(0x81 + Math.floor(idx / 190));
    const ti = idx % 190;
    out.push(ti < 63 ? 0x40 + ti : 0x41 + ti);
  }
  return out;
}

module.exports.isGbkCharset = isGbkCharset;
module.exports.decodeGbk = decodeGbk;
module.exports.encodeGbk = encodeGbk;

});
__define('src/core/utils.js', function(module, exports, __require){
// Last-resort debug sink for swallowed errors: writes to console.debug
// when available (hosts decide verbosity). Never throws.
function debugLog(scope, err){ try{ const c=typeof console!=='undefined'?console:null; if(c&&typeof c.debug==='function') c.debug('[moyuan] '+scope+(err?': '+((err&&err.message)||err):'')); }catch(_){} }
function resolveUrl(base, rel){
if(!rel) return rel||''; rel=String(rel).trim();
if(/^(https?:)?\/\//i.test(rel)||/^(data:|javascript:|#)/i.test(rel)) return rel.startsWith('//')&&base? (base.split(':')[0]+':'+rel): rel;
if(!base) return rel;
if(typeof URL!=='undefined'){ try{ return new URL(rel, base).toString(); }catch(e){ /* invalid base: use the RFC 3986 fallback below */ } }
// Reason: runtimes without URL (bare QuickJS) previously got naive string
// concatenation, which kept dot segments and destroyed the base file name
// for query-only references. The fallback implements RFC 3986 §5.2.
return resolveUrlRfc3986(base, rel);
}
// RFC 3986 §5.2.4: remove dot segments from a path buffer.
function removeDotSegments(path){
let input=String(path), output='';
const popLast=()=>{ const i=output.lastIndexOf('/'); output=i>=0?output.slice(0,i):''; };
while(input.length){
if(input.startsWith('../')) input=input.slice(3);
else if(input.startsWith('./')) input=input.slice(2);
else if(input.startsWith('/./')) input='/'+input.slice(3);
else if(input==='/.' ) input='/';
else if(input.startsWith('/../')){ input='/'+input.slice(4); popLast(); }
else if(input==='/..'){ input='/'; popLast(); }
else if(input==='.'||input==='..') input='';
else { let end=input.indexOf('/', input[0]==='/'?1:0); if(end<0) end=input.length; output+=input.slice(0,end); input=input.slice(end); }
}
return output;
}
// RFC 3986 §5.2.2 reference resolution for http(s) bases without URL.
function resolveUrlRfc3986(base, rel){
const m=String(base).match(/^([a-zA-Z][a-zA-Z0-9+.-]*):\/\/([^/?#]*)([^?#]*)(?:\?([^#]*))?(?:#[\s\S]*)?$/);
if(!m) return rel;
const scheme=m[1], authority=m[2], basePath=m[3]||'', baseQuery=m[4];
let rest=String(rel), frag='', query;
const hi=rest.indexOf('#'); if(hi>=0){ frag=rest.slice(hi); rest=rest.slice(0,hi); }
const qi=rest.indexOf('?'); if(qi>=0){ query=rest.slice(qi+1); rest=rest.slice(0,qi); }
let path, q;
if(rest.startsWith('/')){ path=removeDotSegments(rest); q=query; }
else if(rest===''){ path=basePath||'/'; q=query!==undefined?query:baseQuery; }
else { const merged=(basePath?basePath.slice(0, basePath.lastIndexOf('/')+1):'/')+rest; path=removeDotSegments(merged); q=query; }
return scheme+'://'+authority+path+(q!==undefined?'?'+q:'')+frag;
}
// ---------- timers ----------
// Reason: bare QuickJS hosts may lack setTimeout/clearTimeout. All engine
// timing goes through timerSet/timerClear: an injected host timer wins,
// then the global timer, else null (callers degrade: delay resolves at
// once, withTimeout runs without a deadline and says so once).
let _timerHost=null; const _timerWarned=new Set();
function setTimerHost(host){ _timerHost=(host&&typeof host.setTimeout==='function')?host:null; }
function getTimerHost(){ return _timerHost; }
function hasTimer(){ return !!_timerHost||typeof setTimeout!=='undefined'; }
function timerSet(fn, ms){ if(_timerHost) return _timerHost.setTimeout(fn, ms); if(typeof setTimeout!=='undefined') return setTimeout(fn, ms); return null; }
function timerClear(id){ if(id==null) return; if(_timerHost&&typeof _timerHost.clearTimeout==='function'){ _timerHost.clearTimeout(id); return; } if(typeof clearTimeout!=='undefined') clearTimeout(id); }
function noteTimerUnavailable(what){ if(_timerWarned.has(what)) return; _timerWarned.add(what); debugLog(what+': no timer available (no injected host timer, no global setTimeout) — 超时不可用 / delay degraded to immediate'); }
function stripHtml(html){ return decodeEntities(String(html||'').replace(/<script[\s\S]*?<\/script>/gi,' ').replace(/<style[\s\S]*?<\/style>/gi,' ').replace(/<[^>]+>/g,' ')).replace(/\s+/g,' ').trim();}
const ENT={'&amp;':'&','&lt;':'<','&gt;':'>','&quot;':'"','&#39;':"'",'&apos;':"'",'&nbsp;':' '};
function decodeEntities(s){ return String(s||'').replace(/&(#x?[0-9a-fA-F]+|[a-zA-Z]+);/g,(m,g)=>{ if(g[0]==='#'){ const hex=g[1]==='x'||g[1]==='X'; const n=parseInt(g.slice(hex?2:1),hex?16:10); return isNaN(n)?m:String.fromCodePoint(n);} return ENT[m]||m;});}
function encodeId(sourceId, url){ const raw=sourceId+'\n'+url; let h=0; for(let i=0;i<raw.length;i++){ h=((h<<5)-h+raw.charCodeAt(i))|0;} return sourceId+':'+Math.abs(h).toString(36)+':'+base64UrlEncode(url);}
function base64UrlEncode(s){ const bytes=utf8Encode(String(s)); let bin=''; bytes.forEach(b=>bin+=String.fromCharCode(b)); const b64=(typeof btoa!=='undefined')?btoa(bin):base64EncodeBytes(bytes); return b64.replace(/\+/g,'-').replace(/\//g,'_').replace(/=+$/,'');}
function base64UrlDecode(s){ s=s.replace(/-/g,'+').replace(/_/g,'/'); while(s.length%4) s+='='; const bin=(typeof atob!=='undefined')?atob(s):base64DecodeToBin(s); const bytes=[]; for(let i=0;i<bin.length;i++) bytes.push(bin.charCodeAt(i)); return utf8Decode(bytes);}
function utf8Encode(str){ const out=[]; for(let i=0;i<str.length;i++){ let c=str.codePointAt(i); if(c>0xFFFF) i++; if(c<0x80) out.push(c); else if(c<0x800){ out.push(0xC0|(c>>6),0x80|(c&63));} else if(c<0x10000){ out.push(0xE0|(c>>12),0x80|((c>>6)&63),0x80|(c&63));} else { out.push(0xF0|(c>>18),0x80|((c>>12)&63),0x80|((c>>6)&63),0x80|(c&63));}} return out;}
function utf8Decode(bytes){ let s=''; let i=0; while(i<bytes.length){ const b=bytes[i++]; if(b<0x80) s+=String.fromCharCode(b); else if(b<0xE0) s+=String.fromCharCode(((b&31)<<6)|(bytes[i++]&63)); else if(b<0xF0) s+=String.fromCharCode(((b&15)<<12)|((bytes[i++]&63)<<6)|(bytes[i++]&63)); else { const cp=((b&7)<<18)|((bytes[i++]&63)<<12)|((bytes[i++]&63)<<6)|(bytes[i++]&63); s+=String.fromCodePoint(cp);}} return s;}
function cleanTitle(t){ return String(t||'').replace(/^\s*(第[一二三四五六七八九十百千\d]+\s*[章节回卷部篇])\s*/,'$1 ').replace(/\s+/g,' ').trim();}
function cleanContent(html){
let s=String(html||'');
// Batch 184: comments and noscript blocks are not chapter
// text either — comment bodies survived tag stripping as
// raw text before this.
s=s.replace(/<!--[\s\S]*?-->/g,'').replace(/<noscript[\s\S]*?<\/noscript>/gi,'');
s=s.replace(/<script[\s\S]*?<\/script>/gi,'').replace(/<style[\s\S]*?<\/style>/gi,'');
s=s.replace(/<br\s*\/?>/gi,'\n').replace(/<\/p>/gi,'\n\n').replace(/<\/div>/gi,'\n');
s=stripHtmlKeepBreaks(s);
return s.split('\n').map(l=>l.trim()).filter((l,i,a)=>l|| (a[i-1]&&a[i+1])).join('\n').trim();
}
function stripHtmlKeepBreaks(s){ return decodeEntities(s.replace(/<[^>]+>/g,'')).replace(/[ \t]+/g,' ');}
function renderTemplate(tpl, vars){
return String(tpl||'').replace(/\{\{([\s\S]*?)\}\}/g,(m,expr)=>{
expr=expr.trim();
// Support {{key}} {{page}} {{(page-1)*10}} style arithmetic over vars only
if(/^[a-zA-Z_$][\w$]*$/.test(expr)) return encodeURIComponent(vars[expr]??'');
if(/^[\w\s+\-*/%().]+$/.test(expr)){ try{ const fn=new Function(...Object.keys(vars),'return ('+expr+')'); return encodeURIComponent(fn(...Object.values(vars)));}catch(e){ return '';}}
return m;
});
}
function applyReplaceRegex(value, rule){
// Legado ##pattern##replacement##flags style (also ##pattern##replacement)
if(!rule||!rule.includes('##')) return value;
const parts=rule.split('##'); // ['', pattern, replacement, flags?]
if(parts.length<2) return value;
try{ const re=new RegExp(parts[1], parts[3]||''); return String(value).replace(re, parts[2]||'');}catch(e){ return value;}
}
function splitRule(rule){ // split trailing ##...## replace part
const s=String(rule||''); const i=s.indexOf('##'); if(i<0) return {main:s, replace:''}; return {main:s.slice(0,i), replace:s.slice(i)};}
function dedupeBy(arr, keyFn){ const seen=new Set(); const out=[]; for(const x of arr){ const k=keyFn(x); if(seen.has(k)) continue; seen.add(k); out.push(x);} return out;}
function normalizeTitle(t){ return String(t||'').toLowerCase().replace(/[\s《》「」()（）·・\-_:：，,。.!！?？]/g,'');}

const B64C='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
function base64EncodeBytes(bytes){ let out=''; for(let i=0;i<bytes.length;i+=3){ const a=bytes[i], b=bytes[i+1]||0, c=bytes[i+2]||0; const n=(a<<16)|(b<<8)|c; out+=B64C[(n>>18)&63]+B64C[(n>>12)&63]+(i+1<bytes.length?B64C[(n>>6)&63]:'=')+(i+2<bytes.length?B64C[n&63]:'='); } return out; }
function base64DecodeToBin(s){ const clean=String(s).replace(/[^A-Za-z0-9+/=]/g,''); let out=''; for(let i=0;i<clean.length;i+=4){ const e1=B64C.indexOf(clean[i]), e2=B64C.indexOf(clean[i+1]), e3=clean[i+2]==='='?0:B64C.indexOf(clean[i+2]), e4=clean[i+3]==='='?0:B64C.indexOf(clean[i+3]); const n=(e1<<18)|(e2<<12)|(e3<<6)|e4; out+=String.fromCharCode((n>>16)&255); if(clean[i+2]!=='=') out+=String.fromCharCode((n>>8)&255); if(clean[i+3]!=='=') out+=String.fromCharCode(n&255); } return out; }
function base64EncodeStr(str){ return base64EncodeBytes(utf8Encode(String(str))); }
function base64DecodeStr(b64){ const bin=base64DecodeToBin(String(b64)); const bytes=[]; for(let i=0;i<bin.length;i++) bytes.push(bin.charCodeAt(i)); return utf8Decode(bytes); }
function parseLooseObject(text){ if(text==null) return {}; if(typeof text==='object') return text; const t=String(text).trim(); if(!t) return {}; try{ const v=JSON.parse(t); return v&&typeof v==='object'?v:{}; }catch(e){ debugLog('parseLooseObject: not plain JSON, trying literal fix', e); } try{ const v=JSON.parse(literalToJson(t)); return v&&typeof v==='object'?v:{}; }catch(e){ return {}; } }
function literalToJson(input){ let out=''; let i=0; let expectKey=false; const stack=[]; while(i<input.length){ const ch=input[i]; if(ch==='{'){stack.push('{');expectKey=true;out+=ch;i++;} else if(ch==='['){stack.push('[');expectKey=false;out+=ch;i++;} else if(ch==='}'||ch===']'){ if(stack.length)stack.pop(); out=out.replace(/,\s*$/,''); out+=ch;i++; } else if(ch==="'"){ let sb='"'; i++; while(i<input.length&&input[i]!=="'"){ if(input[i]==='\\'&&i+1<input.length){sb+=input[i]+input[i+1];i+=2;} else if(input[i]==='"'){sb+='\\"';i++;} else {sb+=input[i];i++;} } i++; sb+='"'; out+=sb; } else if(ch==='"'){ let sb='"'; i++; while(i<input.length&&input[i]!=='"'){ if(input[i]==='\\'&&i+1<input.length){sb+=input[i]+input[i+1];i+=2;} else {sb+=input[i];i++;} } i++; sb+='"'; out+=sb; } else if(/[A-Za-z_$]/.test(ch)&&expectKey){ let j=i; while(j<input.length&&/[\w$-]/.test(input[j]))j++; const word=input.slice(i,j); let k=j; while(k<input.length&&/\s/.test(input[k]))k++; if(input[k]===':'){ out+='"'+word+'"'; } else out+=word; i=j; } else { out+=ch; if(ch===':')expectKey=false; if(ch===',')expectKey=stack[stack.length-1]==='{'; i++; } } return out; }
function parseUrlOption(rawUrl){ let url=String(rawUrl||'').trim(); let option=null; const idx=findOptionStart(url); if(idx>=0){ const optText=url.slice(idx+1).trim(); url=url.slice(0,idx).trim(); if(optText.startsWith('{')) option=parseLooseObject(optText); } return {url, option}; }
function findOptionStart(url){ // Legado: url,{...json...} — find ',{' whose remainder parses as object with known keys
 for(let i=0;i<url.length;i++){ if(url[i]===','&&url[i+1]==='{'){ const rest=url.slice(i+1); const o=parseLooseObject(rest); if(o&&(o.method||o.body||o.headers||o.charset||o.js||o.bodyJs||o.webView!==undefined||o.retry!==undefined||o.type)) return i; } } return -1; }

module.exports.debugLog = debugLog;
module.exports.resolveUrl = resolveUrl;
module.exports.removeDotSegments = removeDotSegments;
module.exports.resolveUrlRfc3986 = resolveUrlRfc3986;
module.exports.setTimerHost = setTimerHost;
module.exports.getTimerHost = getTimerHost;
module.exports.hasTimer = hasTimer;
module.exports.timerSet = timerSet;
module.exports.timerClear = timerClear;
module.exports.noteTimerUnavailable = noteTimerUnavailable;
module.exports.stripHtml = stripHtml;
module.exports.decodeEntities = decodeEntities;
module.exports.encodeId = encodeId;
module.exports.base64UrlEncode = base64UrlEncode;
module.exports.base64UrlDecode = base64UrlDecode;
module.exports.utf8Encode = utf8Encode;
module.exports.utf8Decode = utf8Decode;
module.exports.cleanTitle = cleanTitle;
module.exports.cleanContent = cleanContent;
module.exports.renderTemplate = renderTemplate;
module.exports.applyReplaceRegex = applyReplaceRegex;
module.exports.splitRule = splitRule;
module.exports.dedupeBy = dedupeBy;
module.exports.normalizeTitle = normalizeTitle;
module.exports.base64EncodeBytes = base64EncodeBytes;
module.exports.base64DecodeToBin = base64DecodeToBin;
module.exports.base64EncodeStr = base64EncodeStr;
module.exports.base64DecodeStr = base64DecodeStr;
module.exports.parseLooseObject = parseLooseObject;
module.exports.literalToJson = literalToJson;
module.exports.parseUrlOption = parseUrlOption;

});
__define('src/download/DownloadManager.js', function(module, exports, __require){
const { debugLog, timerSet } = __require('../core/utils.js');
// Download queue with concurrency, pause/resume/cancel, retry and persistence.
// Tasks persist their metadata (not content) to storage under 'download:tasks';
// content itself is written through the engine cache/content store.
class DownloadManager {
  constructor(engine) {
    this.engine = engine;
    this.tasks = new Map();
    this._seq = 0;
    this.concurrency = 2;
    this._running = 0;
    this._ready = this._load();
  }
  async _load() {
    try {
      const saved = await this.engine.storage.getJSON('download:tasks', []);
      for (const t of saved) { if (t.status !== 'running') this.tasks.set(t.id, { ...t, chapterIds: t.chapterIds || [] }); this._seq = Math.max(this._seq, parseInt(String(t.id).split('-')[1]) || 0); }
    } catch (e) { debugLog('download task load failed', e); }
  }
  async _persist() {
    const list = [...this.tasks.values()].map(t => ({ id: t.id, bookId: t.bookId, title: t.title, chapterIds: t.chapterIds, done: t.done, failed: t.failed, status: t.status, total: t.total, createdAt: t.createdAt }));
    try { await this.engine.storage.setJSON('download:tasks', list); } catch (e) { debugLog('download task persist failed', e); }
  }
  async create(book, chapters, options = {}) {
    await this._ready;
    const id = 'dl-' + (++this._seq) + '-' + Date.now().toString(36);
    const task = { id, bookId: book.id, book, title: book.title || '', chapterIds: chapters.map(c => c.id), chapters, done: 0, failed: 0, total: chapters.length, status: 'queued', createdAt: Date.now(), errors: [], retries: options.retries ?? 1 };
    this.tasks.set(id, task);
    await this._persist();
    this.engine.events.emit('download:created', { id, total: task.total });
    this._pump();
    return this.get(id);
  }
  get(id) { const t = this.tasks.get(id); if (!t) return null; return { id: t.id, bookId: t.bookId, title: t.title, status: t.status, total: t.total, done: t.done, failed: t.failed, progress: t.total ? t.done / t.total : 0, errors: t.errors.slice(0, 10) }; }
  list() { return [...this.tasks.values()].map(t => this.get(t.id)); }
  pause(id) { const t = this.tasks.get(id); if (t && t.status === 'running') { t.status = 'paused'; this.engine.events.emit('download:paused', { id }); this._persist(); } return this.get(id); }
  resume(id) { const t = this.tasks.get(id); if (t && (t.status === 'paused' || t.status === 'failed')) { t.status = 'queued'; this._pump(); } return this.get(id); }
  cancel(id) { const t = this.tasks.get(id); if (t) { t.status = 'cancelled'; this.engine.events.emit('download:cancelled', { id }); this._persist(); } return this.get(id); }
  async remove(id) { this.tasks.delete(id); await this._persist(); return true; }
  async wait(id, timeoutMs = 30000) {
    const start = Date.now();
    while (Date.now() - start < timeoutMs) { const t = this.get(id); if (!t) throw new Error('Download task not found: ' + id); if (['completed', 'failed', 'cancelled'].includes(t.status)) return t; await new Promise(r => setTimeout(r, 10)); }
    throw Object.assign(new Error('Download wait timeout'), { code: 'E_TIMEOUT' });
  }
  _pump() {
    while (this._running < this.concurrency) {
      const next = [...this.tasks.values()].find(t => t.status === 'queued');
      if (!next) return;
      next.status = 'running'; this._running++;
      this._runTask(next).finally(() => { this._running--; this._pump(); });
    }
  }
  async _runTask(task) {
    const engine = this.engine;
    try {
      for (let i = task.done + task.failed; i < task.chapters.length; i++) {
        if (task.status !== 'running') { await this._persist(); return; }
        const chapter = task.chapters[i];
        let ok = false, lastErr = null;
        for (let attempt = 0; attempt <= task.retries && !ok; attempt++) {
          try { const content = await engine.chapters.getContentById(chapter.id, { task: null }); await engine.cache.set('content:' + chapter.id, content); ok = true; }
          catch (e) { lastErr = e; }
        }
        if (ok) task.done++; else { task.failed++; task.errors.push({ chapterId: chapter.id, error: String(lastErr && lastErr.message || lastErr) }); }
        engine.events.emit('download:progress', { id: task.id, done: task.done, failed: task.failed, total: task.total });
        await this._persist();
      }
      if (task.status === 'running') task.status = task.failed && !task.done ? 'failed' : 'completed';
      engine.events.emit('download:' + task.status, { id: task.id, done: task.done, failed: task.failed, total: task.total });
    } catch (e) { task.status = 'failed'; task.errors.push({ error: String(e && e.message || e) }); }
    await this._persist();
  }
}
module.exports.default = DownloadManager;

module.exports.DownloadManager = DownloadManager;

});
__define('src/index.js', function(module, exports, __require){
const { NovelEngine, createNovelEngine, ENGINE_VERSION } = __require('./core/NovelEngine.js');

module.exports.NovelEngine = NovelEngine;
module.exports.createNovelEngine = createNovelEngine;
module.exports.ENGINE_VERSION = ENGINE_VERSION;
const __re_284361056 = __require('./core/EventEmitter.js');
module.exports.EventEmitter = __re_284361056.EventEmitter;
const __re_1235885862 = __require('./core/ConfigManager.js');
module.exports.ConfigManager = __re_1235885862.ConfigManager;
const __re_292922757 = __require('./core/TaskManager.js');
module.exports.TaskManager = __re_292922757.TaskManager;
module.exports.runPool = __re_292922757.runPool;
module.exports.delay = __re_292922757.delay;
module.exports.withTimeout = __re_292922757.withTimeout;
const __re_736617192 = __require('./core/errors.js');
module.exports.NovelError = __re_736617192.NovelError;
module.exports.ERR = __re_736617192.ERR;
module.exports.wrapError = __re_736617192.wrapError;
const __re_136236007 = __require('./core/TraceCollector.js');
module.exports.TraceCollector = __re_136236007.TraceCollector;
module.exports.TRACE_LIMITS = __re_136236007.TRACE_LIMITS;
module.exports.summarizeValue = __re_136236007.summarizeValue;
module.exports.bodyExcerpt = __re_136236007.bodyExcerpt;
const __re_1111557064 = __require('./core/DebugTools.js');
module.exports.DebugTools = __re_1111557064.DebugTools;
const __re_1823734954 = __require('./source/HealthChecker.js');
module.exports.HealthChecker = __re_1823734954.HealthChecker;
Object.assign(module.exports, __require('./core/utils.js'));
const __re_1195498630 = __require('./parser/ParserEngine.js');
module.exports.ParserEngine = __re_1195498630.ParserEngine;
const __re_692714735 = __require('./parser/LegadoParser.js');
module.exports.LegadoContext = __re_692714735.LegadoContext;
module.exports.legadoToCss = __re_692714735.legadoToCss;
module.exports.parseLegadoStep = __re_692714735.parseLegadoStep;
const __re_509946090 = __require('./parser/HtmlParser.js');
module.exports.parseHtml = __re_509946090.parseHtml;
module.exports.textOf = __re_509946090.textOf;
module.exports.htmlOf = __re_509946090.htmlOf;
const __re_1582782783 = __require('./parser/CSSParser.js');
module.exports.queryAll = __re_1582782783.queryAll;
module.exports.query = __re_1582782783.query;
const __re_1712465839 = __require('./parser/JSONPathParser.js');
module.exports.jsonPath = __re_1712465839.jsonPath;
module.exports.jsonPathAll = __re_1712465839.jsonPathAll;
const __re_1622895143 = __require('./parser/XPathParser.js');
module.exports.xpath = __re_1622895143.xpath;
const __re_1590992936 = __require('./parser/RegexParser.js');
module.exports.regexExtract = __re_1590992936.regexExtract;
module.exports.regexAll = __re_1590992936.regexAll;
const __re_2039238168 = __require('./parser/JSParser.js');
module.exports.evalJs = __re_2039238168.evalJs;
module.exports.evalJsExpression = __re_2039238168.evalJsExpression;
module.exports.evalScoped = __re_2039238168.evalScoped;
module.exports.createJavaShim = __re_2039238168.createJavaShim;
module.exports.md5 = __re_2039238168.md5;
module.exports.setJsEvaluator = __re_2039238168.setJsEvaluator;
module.exports.getJsEvaluator = __re_2039238168.getJsEvaluator;
module.exports.setJsTimeoutMs = __re_2039238168.setJsTimeoutMs;
module.exports.getJsTimeoutMs = __re_2039238168.getJsTimeoutMs;
module.exports.ajaxCacheKey = __re_2039238168.ajaxCacheKey;
module.exports.injectLoopGuards = __re_2039238168.injectLoopGuards;
module.exports.setLoopGuardEnabled = __re_2039238168.setLoopGuardEnabled;
module.exports.isLoopGuardEnabled = __re_2039238168.isLoopGuardEnabled;
module.exports.htmlFormatValue = __re_2039238168.htmlFormatValue;
const __re_1234903480 = __require('./core/gbk.js');
module.exports.decodeGbk = __re_1234903480.decodeGbk;
module.exports.encodeGbk = __re_1234903480.encodeGbk;
module.exports.isGbkCharset = __re_1234903480.isGbkCharset;
// setTimerHost / getTimerHost / hasTimer / timerSet / timerClear are
// exported via `Object.assign(module.exports, __require('./core/utils.js'));` above.
const __re_1868570953 = __require('./parser/CryptoLite.js');
module.exports.CryptoJS = __re_1868570953.CryptoJS;
module.exports.WordArrayLite = __re_1868570953.WordArrayLite;
module.exports.createSymmetricCrypto = __re_1868570953.createSymmetricCrypto;
module.exports.parseTransformation = __re_1868570953.parseTransformation;
module.exports.sha1 = __re_1868570953.sha1;
module.exports.sha256 = __re_1868570953.sha256;
module.exports.md5Bytes = __re_1868570953.md5Bytes;
module.exports.hmacBytes = __re_1868570953.hmacBytes;
module.exports.digestBytes = __re_1868570953.digestBytes;
module.exports.aesEncrypt = __re_1868570953.aesEncrypt;
module.exports.aesDecrypt = __re_1868570953.aesDecrypt;
module.exports.AesCipher = __re_1868570953.AesCipher;
module.exports.toBytes = __re_1868570953.toBytes;
module.exports.fromBytes = __re_1868570953.fromBytes;
module.exports.bytesToHex = __re_1868570953.bytesToHex;
module.exports.hexToBytes = __re_1868570953.hexToBytes;
module.exports.bytesToBase64 = __re_1868570953.bytesToBase64;
module.exports.base64ToBytes = __re_1868570953.base64ToBytes;
const __re_870500261 = __require('./parser/XmlLite.js');
module.exports.xmlTagBlocks = __re_870500261.xmlTagBlocks;
module.exports.xmlTagBlocksWithAttrs = __re_870500261.xmlTagBlocksWithAttrs;
module.exports.xmlSelfTags = __re_870500261.xmlSelfTags;
module.exports.xmlFieldText = __re_870500261.xmlFieldText;
module.exports.xmlFirstTag = __re_870500261.xmlFirstTag;
module.exports.xmlText = __re_870500261.xmlText;
module.exports.parseAttrs = __re_870500261.parseAttrs;
const __re_1379150147 = __require('./source/SourceAdapter.js');
module.exports.SourceAdapter = __re_1379150147.SourceAdapter;
module.exports.normalizeSourceDef = __re_1379150147.normalizeSourceDef;
module.exports.parseSourceArray = __re_1379150147.parseSourceArray;
module.exports.normalizeForeign = __re_1379150147.normalizeForeign;
module.exports.detectSourceKind = __re_1379150147.detectSourceKind;
module.exports.parseLoginUi = __re_1379150147.parseLoginUi;
module.exports.applyMediaType = __re_1379150147.applyMediaType;
const __re_5990966 = __require('./source/SourceManager.js');
module.exports.SourceManager = __re_5990966.SourceManager;
const __re_639132524 = __require('./source/SourceRegistry.js');
module.exports.SourceRegistry = __re_639132524.SourceRegistry;
const __re_1923662102 = __require('./source/SourceValidator.js');
module.exports.SourceValidator = __re_1923662102.SourceValidator;
const __re_741321483 = __require('./source/YioveRepository.js');
module.exports.YioveRepository = __re_741321483.YioveRepository;
module.exports.YIOVE_API = __re_741321483.YIOVE_API;
const __re_1019684580 = __require('./source/RemoteRepository.js');
module.exports.RemoteRepository = __re_1019684580.RemoteRepository;
const __re_1986631414 = __require('./source/RssAdapter.js');
module.exports.RssRegistry = __re_1986631414.RssRegistry;
module.exports.RssSource = __re_1986631414.RssSource;
module.exports.detectSubscriptionEntry = __re_1986631414.detectSubscriptionEntry;
module.exports.normalizeRssDef = __re_1986631414.normalizeRssDef;
module.exports.parseSortUrlText = __re_1986631414.parseSortUrlText;
module.exports.parseFeedArticles = __re_1986631414.parseFeedArticles;
const __re_1516208996 = __require('./source/LocalBook.js');
module.exports.parseTxtBook = __re_1516208996.parseTxtBook;
module.exports.splitTxtChapters = __re_1516208996.splitTxtChapters;
module.exports.chunkText = __re_1516208996.chunkText;
module.exports.parseEpubBook = __re_1516208996.parseEpubBook;
module.exports.readZipEntries = __re_1516208996.readZipEntries;
module.exports.makeLocalSource = __re_1516208996.makeLocalSource;
module.exports.isChapterHeading = __re_1516208996.isChapterHeading;
const __re_649314712 = __require('./source/OpdsCatalog.js');
module.exports.OpdsCatalog = __re_649314712.OpdsCatalog;
module.exports.parseOpdsFeed = __re_649314712.parseOpdsFeed;
module.exports.findOpdsSearch = __re_649314712.findOpdsSearch;
const __re_989878013 = __require('./search/SearchEngine.js');
module.exports.SearchEngine = __re_989878013.SearchEngine;
const __re_906322257 = __require('./search/SearchAggregator.js');
module.exports.SearchAggregator = __re_906322257.SearchAggregator;
const __re_717789531 = __require('./search/ResultDeduplicator.js');
module.exports.ResultDeduplicator = __re_717789531.ResultDeduplicator;
const __re_1488654791 = __require('./network/RequestManager.js');
module.exports.RequestManager = __re_1488654791.RequestManager;
const __re_1014536544 = __require('./network/RequestAdapter.js');
module.exports.CookieJar = __re_1014536544.CookieJar;
module.exports.RequestAdapter = __re_1014536544.RequestAdapter;
const __re_1880323157 = __require('./network/RetryManager.js');
module.exports.RetryManager = __re_1880323157.RetryManager;
const __re_633064589 = __require('./cache/CacheManager.js');
module.exports.CacheManager = __re_633064589.CacheManager;
const __re_1056503983 = __require('./cache/CacheAdapter.js');
module.exports.CacheAdapter = __re_1056503983.CacheAdapter;
const __re_501596710 = __require('./storage/StorageAdapter.js');
module.exports.StorageAdapter = __re_501596710.StorageAdapter;
const __re_918981196 = __require('./storage/MemoryStorage.js');
module.exports.MemoryStorage = __re_918981196.MemoryStorage;
const __re_904384899 = __require('./download/DownloadManager.js');
module.exports.DownloadManager = __re_904384899.DownloadManager;
const __re_482640167 = __require('./plugins/PluginManager.js');
module.exports.PluginManager = __re_482640167.PluginManager;
const __re_418217799 = __require('./plugins/PluginRegistry.js');
module.exports.PluginRegistry = __re_418217799.PluginRegistry;
const __re_1692132691 = __require('./api/SearchAPI.js');
module.exports.SearchAPI = __re_1692132691.SearchAPI;
const __re_1667046003 = __require('./api/BookAPI.js');
module.exports.BookAPI = __re_1667046003.BookAPI;
const __re_339796551 = __require('./api/ChapterAPI.js');
module.exports.ChapterAPI = __re_339796551.ChapterAPI;
const __re_1013729331 = __require('./api/SourceAPI.js');
module.exports.SourceAPI = __re_1013729331.SourceAPI;
const __re_215618639 = __require('./api/CacheAPI.js');
module.exports.CacheAPI = __re_215618639.CacheAPI;
const __re_1749749357 = __require('./api/DownloadAPI.js');
module.exports.DownloadAPI = __re_1749749357.DownloadAPI;
const __re_1245266560 = __require('./adapters/AnikumoAdapter.js');
module.exports.createAnikumoBridge = __re_1245266560.createAnikumoBridge;
module.exports.toAnikumoItem = __re_1245266560.toAnikumoItem;
module.exports.fromAnikumoItem = __re_1245266560.fromAnikumoItem;
module.exports.toAnikumoChapter = __re_1245266560.toAnikumoChapter;
module.exports.fromAnikumoChapter = __re_1245266560.fromAnikumoChapter;
module.exports.contentToAnikumoBlocks = __re_1245266560.contentToAnikumoBlocks;
module.exports.toAnikumoCategory = __re_1245266560.toAnikumoCategory;
module.exports.toAnikumoInstalledJson = __re_1245266560.toAnikumoInstalledJson;
module.exports.importAnikumoInstalledJson = __re_1245266560.importAnikumoInstalledJson;
module.exports.splitKindTags = __re_1245266560.splitKindTags;
module.exports.mergeKindTags = __re_1245266560.mergeKindTags;
const __re_1996416478 = __require('./adapters/QuickJSAdapter.js');
module.exports.createQuickJSEngine = __re_1996416478.createQuickJSEngine;
module.exports.quickJSRequestFromGlobals = __re_1996416478.quickJSRequestFromGlobals;
module.exports.quickJSSyncRequestFromGlobals = __re_1996416478.quickJSSyncRequestFromGlobals;
module.exports.quickJSStorageFromGlobals = __re_1996416478.quickJSStorageFromGlobals;

// Default shared engine + the `Novel` facade from the spec. Facade methods
// return data directly (same convention as NovelEngine) and reject with
// NovelError. Configure the shared engine via Novel.configure({...}) or
// Novel.setRequest(fn) / Novel.setStorage(storage) before first use.
let _default = null;
function defaultEngine() { if (!_default) _default = createNovelEngine(); return _default; }
function configureNovel(options) { _default = createNovelEngine(options); return _default; }

const Novel = {
  version: ENGINE_VERSION,
  configure(options) { return configureNovel(options); },
  engine() { return defaultEngine(); },
  setRequest(fn) { defaultEngine().setRequest(fn); return this; },
  setStorage(storage) { defaultEngine().setStorage(storage); return this; },
  on(ev, fn) { return defaultEngine().on(ev, fn); },
  async search(keyword, options) { return defaultEngine().search(keyword, options); },
  async getBookInfo(bookOrId, options) { return defaultEngine().getBookInfo(bookOrId, options); },
  async getChapters(bookOrId, options) { return defaultEngine().getChapters(bookOrId, options); },
  async getChapterContent(chapterOrId, options) { return defaultEngine().getChapterContent(chapterOrId, options); },
  async getChapterContentFor(book, chapter, options) { return defaultEngine().getChapterContentFor(book, chapter, options); },
  getSources() { return defaultEngine().sourceManager.list(); },
  registerSource(source, options) { const a = defaultEngine().sourceManager.register(source, options); return defaultEngine().sourceManager.registry.info(a); },
  async testSource(sourceId, keyword) { return defaultEngine().sourceManager.testSource(sourceId, keyword); },
  parseUrl(url) { return defaultEngine().parseUrl(url); },
  async discoverBooks(sourceId, category, options) { const e = defaultEngine(); if (category) return e.explore(sourceId, category, options); return e.discover(sourceId); },
  bookshelf() { return defaultEngine().bookshelf(); },
  cache() { const { CacheAPI } = _cacheApi(); return new CacheAPI(defaultEngine()); },
  download() { const { DownloadAPI } = _dlApi(); return new DownloadAPI(defaultEngine()); },
  plugins() { const e = defaultEngine(); return { register: (p) => e.plugins.register(p), enable: (id) => e.plugins.enable(id), disable: (id) => e.plugins.disable(id), unregister: (id) => e.plugins.unregister(id), list: () => e.plugins.list(), get: (id) => e.plugins.get(id) }; },
  request(url, options) { return defaultEngine().requests.request(url, options); },
  sources() { const { SourceAPI } = _srcApi(); return new SourceAPI(defaultEngine()); },
  rss() { return defaultEngine().rss; },
  remote() { return defaultEngine().remote; },
  debug() { return defaultEngine().debug; },
  health() { return defaultEngine().health; },
  opds() { const { OpdsCatalog } = _opds(); return new OpdsCatalog(defaultEngine()); },
};
const { CacheAPI: _CA } = __require('./api/CacheAPI.js');
const { DownloadAPI: _DA } = __require('./api/DownloadAPI.js');
const { SourceAPI: _SA } = __require('./api/SourceAPI.js');
const { OpdsCatalog: _OC } = __require('./source/OpdsCatalog.js');
function _cacheApi() { return { CacheAPI: _CA }; }
function _dlApi() { return { DownloadAPI: _DA }; }
function _srcApi() { return { SourceAPI: _SA }; }
function _opds() { return { OpdsCatalog: _OC }; }
module.exports.default = Novel;

module.exports.defaultEngine = defaultEngine;
module.exports.configureNovel = configureNovel;
module.exports.Novel = Novel;

});
__define('src/network/RequestAdapter.js', function(module, exports, __require){
const { debugLog } = __require('../core/utils.js');
// Cookie jar + request adapter interface.
// The jar stores cookie records {name, value, domain, path, expires,
// hostOnly} keyed by domain, with basic RFC 6265 handling:
//  - a Set-Cookie whose Domain attribute does not domain-match the
//    request host is rejected; without Domain the cookie is host-only;
//  - cookies are sent only when the request path prefix-matches the
//    cookie's Path (default: the directory of the request path);
//  - Expires / Max-Age are honored: expired cookies are dropped and an
//    already-expired Set-Cookie deletes the stored cookie.
// toJSON/fromJSON round-trip the records; fromJSON also accepts the
// legacy {host: {name: "value"}} string shape. `jar.onChange` (if set)
// fires after any mutation — RequestManager uses it for persistence.
class CookieJar{
  constructor(){ this._jar=new Map(); this.onChange=null; } // domain -> Map(key -> record), key = name + '\n' + path
  _host(url){ try{ return new URL(url).host; }catch(e){ const m=String(url).match(/^https?:\/\/([^/]+)/); return m?m[1]:''; } }
  _path(url){ try{ return new URL(url).pathname||'/'; }catch(e){ const m=String(url).match(/^https?:\/\/[^/]+(\/[^?#]*)?/); return (m&&m[1])||'/'; } }
  _domainMatch(host, domain){ return host===domain || host.endsWith('.'+domain); }
  _defaultPath(p){ if(!p||p[0]!=='/') return '/'; const idx=p.lastIndexOf('/'); return idx<=0?'/':p.slice(0,idx+1); }
  _key(name, path){ return name+'\n'+path; }
  _changed(){ if(typeof this.onChange==='function'){ try{ this.onChange(); }catch(e){ debugLog('cookie jar onChange error', e); } } }
  _store(domain, record){ if(!this._jar.has(domain)) this._jar.set(domain, new Map()); this._jar.get(domain).set(this._key(record.name, record.path), record); }
  _delete(domain, name, path){ const jar=this._jar.get(domain); if(jar) jar.delete(this._key(name, path)); }
  setFromHeaders(url, headers){
    if(!headers) return; const host=this._host(url); if(!host) return;
    let raw=headers['set-cookie']||headers['Set-Cookie']; if(!raw) return; if(!Array.isArray(raw)) raw=[raw];
    const reqPath=this._path(url); let changed=false;
    for(const line of raw){
      const parts=String(line).split(';'); const first=parts[0]; const eq=first.indexOf('='); if(eq<=0) continue;
      const name=first.slice(0,eq).trim(); const value=first.slice(eq+1).trim(); if(!name) continue;
      let domain=host, hostOnly=true, path=this._defaultPath(reqPath), expires=null, rejected=false;
      for(const attr of parts.slice(1)){
        const ai=attr.indexOf('='); const k=(ai<0?attr:attr.slice(0,ai)).trim().toLowerCase(); const v=ai<0?'':attr.slice(ai+1).trim();
        if(k==='domain'&&v){ const d=v.replace(/^\./,'').toLowerCase(); if(!this._domainMatch(host, d)){ rejected=true; break; } domain=d; hostOnly=false; }
        else if(k==='path'&&v.startsWith('/')) path=v;
        else if(k==='max-age'&&v!==''){ const sec=Number(v); if(Number.isFinite(sec)) expires=Date.now()+sec*1000; }
        else if(k==='expires'&&v&&expires==null){ const t=Date.parse(v); if(!isNaN(t)) expires=t; }
      }
      if(rejected) continue;
      if(expires!=null&&expires<=Date.now()){ this._delete(domain, name, path); changed=true; continue; }
      this._store(domain, {name, value, domain, path, expires, hostOnly}); changed=true;
    }
    if(changed) this._changed();
  }
  setCookie(url, name, value){ const host=this._host(url); if(!host) return; this._store(host, {name, value, domain:host, path:'/', expires:null, hostOnly:true}); this._changed(); }
  _matching(url){
    const host=this._host(url); const path=this._path(url); const now=Date.now(); const out=[]; let pruned=false;
    for(const [domain, jar] of this._jar){
      for(const [key, rec] of jar){
        if(rec.expires!=null&&rec.expires<=now){ jar.delete(key); pruned=true; continue; }
        if(rec.hostOnly?host!==domain:!this._domainMatch(host, domain)) continue;
        const cp=rec.path||'/';
        if(!(cp==='/'||path===cp||path.startsWith(cp.endsWith('/')?cp:cp+'/'))) continue;
        out.push(rec);
      }
      if(!jar.size) this._jar.delete(domain);
    }
    if(pruned) this._changed();
    return out;
  }
  getCookieHeader(url){ return this._matching(url).map(r=>r.name+'='+r.value).join('; '); }
  getCookies(url){ const out={}; for(const r of this._matching(url)) out[r.name]=r.value; return out; }
  removeCookie(url, name){ const jar=this._jar.get(this._host(url)); if(jar){ let changed=false; for(const [key, rec] of [...jar]) if(rec.name===name){ jar.delete(key); changed=true; } if(changed) this._changed(); } }
  clear(url){ if(url){ if(this._jar.delete(this._host(url))) this._changed(); } else if(this._jar.size){ this._jar.clear(); this._changed(); } }
  toJSON(){ const out={}; for(const [domain, jar] of this._jar){ out[domain]={}; for(const rec of jar.values()) out[domain][rec.name]={value:rec.value, path:rec.path, expires:rec.expires, hostOnly:rec.hostOnly}; } return out; }
  fromJSON(obj){ this._jar.clear(); for(const [domain, cookies] of Object.entries(obj||{})){ for(const [name, v] of Object.entries(cookies||{})){ if(typeof v==='string') this._store(domain, {name, value:v, domain, path:'/', expires:null, hostOnly:true}); else if(v&&typeof v==='object') this._store(domain, {name, value:String(v.value??''), domain, path:typeof v.path==='string'&&v.path?v.path:'/', expires:typeof v.expires==='number'?v.expires:null, hostOnly:v.hostOnly!==false}); } } return this; }
}
// A request adapter is any async fn (url, options) => {status, headers, body, url}
// or an object with .request(url, options). RequestManager normalizes both.
class RequestAdapter{
  constructor(fn){ this.fn=fn||null; }
  async request(url, options={}){
    if(!this.fn) throw Object.assign(new Error('No request adapter injected and no global fetch available'), {code:'E_UNSUPPORTED'});
    if(typeof this.fn==='function') return this.fn(url, options);
    return this.fn.request(url, options);
  }
}
module.exports.default = RequestAdapter;

module.exports.CookieJar = CookieJar;
module.exports.RequestAdapter = RequestAdapter;

});
__define('src/network/RequestManager.js', function(module, exports, __require){
const { CookieJar, RequestAdapter } = __require('./RequestAdapter.js');
const { RetryManager } = __require('./RetryManager.js');
const { withTimeout, delay } = __require('../core/TaskManager.js');
const { NovelError, ERR } = __require('../core/errors.js');
const { utf8Decode, timerSet, noteTimerUnavailable } = __require('../core/utils.js');
const { decodeGbk, isGbkCharset } = __require('../core/gbk.js');

// Unified network layer. Transport is injected (adapter fn) or, when the
// runtime offers fetch, a default fetch transport is used. No core code
// assumes fetch exists (QuickJS hosts inject their own transport).
//
// Behavior notes:
//  - HTTP status: 429 and 5xx responses are thrown as E_HTTP and retried
//    with exponential backoff (Retry-After honored when present); other
//    4xx responses throw E_HTTP immediately (noRetry). POST is not
//    retried unless options.retry === true (existing policy).
//  - Charset: an explicit options.charset wins; otherwise the charset is
//    detected from the Content-Type header, then from a <meta charset>
//    in the first bytes. A non-UTF-8 charset with raw bytes available is
//    decoded via the injected decodeText hook or TextDecoder; decoding
//    problems never throw — the undecided body is kept and logged.
//  - Cancellation: every attempt carries an AbortSignal-style `signal`
//    in the transport options. On timeout or task abort the signal is
//    aborted, and requests still queued for a concurrency slot are
//    dropped without ever calling the transport.
//  - Rate limiting: minInterval is tracked per host, and the timestamp
//    is stamped only when a request actually goes out (after its
//    concurrency slot is acquired), never when it starts queueing.
//  - Cookies: when storage is injected, the jar is loaded from storage
//    key 'moyuan:cookies' before the first request and saved back
//    (throttled, 500ms) after changes; persistence failures are logged
//    and never break requests.
const COOKIE_STORAGE_KEY = 'moyuan:cookies';
class RequestManager {
  constructor(opts = {}) {
    this.config = opts.config || null;
    this.adapter = opts.adapter ? (opts.adapter instanceof RequestAdapter ? opts.adapter : new RequestAdapter(opts.adapter)) : null;
    this.injected = opts.request ? new RequestAdapter(opts.request) : null;
    this.cookieJar = opts.cookieJar || new CookieJar();
    const cfgGet = (k) => { try { return this.config && typeof this.config.get === 'function' ? this.config.get(k) : undefined; } catch (e) { return undefined; } };
    this.retry = new RetryManager({ retries: opts.retries ?? cfgGet('retries'), retryDelay: opts.retryDelay ?? cfgGet('retryDelay') });
    this.decodeText = opts.decodeText || null; // (bytes, charset) => string, GBK hook
    this.trace = typeof opts.trace === 'function' ? opts.trace : null; // debug trace hook (kind, data) => void
    this.logger = opts.logger || null;
    this.logs = [];
    this.maxConcurrent = opts.maxConcurrent || 6;
    this.minInterval = opts.minInterval || 0;
    this._active = 0; this._waiters = []; this._lastAtByHost = new Map();
    this.defaultHeaders = opts.headers || {};
    this.storage = opts.storage || null;
    this.cookieKey = opts.cookieStorageKey || COOKIE_STORAGE_KEY;
    this._cookiesReady = null; this._cookieSaveTimer = null; this._cookieLoading = false;
    this.cookieJar.onChange = () => { if (!this._cookieLoading) this._scheduleCookieSave(); };
  }
  _debug(...a) { try { const l = this.logger; if (l && typeof l.debug === 'function') l.debug('[moyuan-request]', ...a); else if (l && typeof l.log === 'function') l.log('[moyuan-request]', ...a); } catch (e) { /* logging must not break requests */ } }
  setRequest(fn) { this.injected = new RequestAdapter(fn); }
  setAdapter(adapter) { this.adapter = adapter instanceof RequestAdapter ? adapter : new RequestAdapter(adapter); }
  setDecoder(fn) { this.decodeText = fn; }
  bindCookieStorage(storage) { this.storage = storage || null; this._cookiesReady = null; }
  async _ensureCookies() {
    if (!this.storage) return;
    if (!this._cookiesReady) {
      this._cookiesReady = (async () => {
        this._cookieLoading = true;
        try { const raw = await this.storage.get(this.cookieKey); if (raw) { const obj = typeof raw === 'string' ? JSON.parse(raw) : raw; if (obj) this.cookieJar.fromJSON(obj); } }
        catch (e) { this._debug('cookie load failed', e); }
        finally { this._cookieLoading = false; }
      })();
    }
    return this._cookiesReady;
  }
  _scheduleCookieSave() {
    if (!this.storage || this._cookieSaveTimer) return;
    // Reason: no timer (bare QuickJS without an injected host timer) must
    // not throw ReferenceError — persist immediately instead of delayed.
    const t = timerSet(() => { this._cookieSaveTimer = null; this._saveCookies(); }, 500);
    if (t == null) { noteTimerUnavailable('cookie save'); this._saveCookies(); return; }
    this._cookieSaveTimer = t;
    if (t && typeof t.unref === 'function') t.unref();
  }
  async _saveCookies() { if (!this.storage) return; try { await this.storage.set(this.cookieKey, JSON.stringify(this.cookieJar.toJSON())); } catch (e) { this._debug('cookie save failed', e); } }
  async _acquire(url, task, ctl) {
    if (this._active >= this.maxConcurrent) {
      await new Promise((res, rej) => {
        const w = { res, rej, settled: false };
        this._waiters.push(w);
        const cancel = () => { if (w.settled) return; w.settled = true; const i = this._waiters.indexOf(w); if (i >= 0) this._waiters.splice(i, 1); const e = new Error('Request aborted while queued'); e.code = 'E_ABORTED'; rej(e); };
        if (task) task.onAbort(cancel);
        if (ctl && ctl.signal && typeof ctl.signal.addEventListener === 'function') ctl.signal.addEventListener('abort', cancel);
        if ((task && task.aborted) || (ctl && ctl.signal.aborted)) cancel();
      });
    }
    this._active++;
    if (this.minInterval) {
      const host = hostKey(url);
      const last = this._lastAtByHost.get(host) || 0;
      const wait = last + this.minInterval - Date.now();
      try { if (wait > 0) await delay(wait, task); }
      catch (e) { this._release(); throw e; }
      this._lastAtByHost.set(host, Date.now()); // stamped at send time, after the slot
    }
  }
  _release() { this._active--; const w = this._waiters.shift(); if (w && !w.settled) { w.settled = true; w.res(); } }
  _transport() { return this.injected || this.adapter || (typeof fetch !== 'undefined' ? new RequestAdapter(defaultFetchTransport) : null); }
  _decodeBody(res, options) {
    const explicit = options.charset || null;
    let charset = explicit || charsetFromHeaders(res.headers) || null;
    if (!charset && res.bytes) charset = charsetFromMeta(bytesToAscii(res.bytes, 2048));
    if (!charset && res.body) charset = charsetFromMeta(String(res.body).slice(0, 2048));
    if (!charset || !res.bytes) return;
    const label = String(charset).trim();
    const isUtf8 = /^utf-?8$/i.test(label);
    // Decode order: host decodeText hook -> TextDecoder -> built-in GBK.
    // Reason for throwing past this point: a non-UTF-8 body that no level
    // can decode used to pass through as silent mojibake; callers now get
    // a precise E_DECODE (charset + url) instead of garbage text.
    if (this.decodeText && (explicit || !isUtf8)) {
      try { res.body = this.decodeText(res.bytes, charset); return; }
      catch (e) { this._debug('host decodeText failed (charset ' + charset + '), falling through', e); }
    }
    if (isUtf8) return;
    if (typeof TextDecoder !== 'undefined') {
      try { res.body = new TextDecoder(label).decode(res.bytes); return; }
      catch (e) { this._debug('TextDecoder failed (charset ' + charset + '), falling through', e); }
    }
    if (isGbkCharset(label)) { res.body = decodeGbk(res.bytes); return; }
    const err = new NovelError(ERR.DECODE, 'No decoder available for charset ' + label + ' at ' + (res.url || '') + ' (inject a decodeText hook or use a UTF-8/GBK page)', { details: { charset: label, url: res.url || '' } });
    err.noRetry = true;
    throw err;
  }
  async request(url, options = {}) {
    const task = options.task || null;
    if (task) task.throwIfAborted();
    await this._ensureCookies();
    const timeout = options.timeout ?? (this.config ? this.config.get('timeout') : 15000);
    const method = (options.method || 'GET').toUpperCase();
    const headers = { ...(this.config ? { 'User-Agent': this.config.get('userAgent') } : {}), ...this.defaultHeaders, ...(options.headers || {}) };
    const cookie = this.cookieJar.getCookieHeader(url);
    if (cookie && !headers.Cookie && !headers.cookie) headers.Cookie = cookie;
    if (options.cookie) headers.Cookie = options.cookie;
    const runOnce = async () => {
      const transport = this._transport();
      if (!transport) throw new NovelError(ERR.UNSUPPORTED, 'No request transport: inject one via createNovelEngine({request}) or an adapter');
      const ctl = createAbortControl();
      if (task) task.onAbort(() => ctl.abort());
      await this._acquire(url, task, ctl);
      try {
        const raw = await withTimeout(Promise.resolve(transport.request(url, { ...options, method, headers, signal: ctl.signal })), timeout, task);
        const res = normalizeResponse(raw, url);
        if (res.headers) this.cookieJar.setFromHeaders(res.url || url, res.headers);
        this._decodeBody(res, options);
        this.logs.push({ url, method, status: res.status, at: Date.now() });
        assertHttpStatus(res, url);
        return res;
      } catch (e) { ctl.abort(); throw e; }
      finally { this._release(); }
    };
    const traceStart = this.trace ? Date.now() : 0;
    try {
      const retryable = method === 'GET' || options.retry === true;
      const retries = typeof options.retries === 'number' ? options.retries : (retryable ? undefined : 0);
      const res = await this.retry.run(runOnce, { retries, task });
      if (this.trace) this.trace('http', { stage: 'network', label: method + ' ' + url, outputSummary: 'status ' + res.status + ' · ' + String(res.body || '').length + ' chars', excerpt: res.body, durationMs: Date.now() - traceStart });
      return res;
    } catch (e) {
      if (this.trace) this.trace('http', { stage: 'network', label: method + ' ' + url, durationMs: Date.now() - traceStart, error: e });
      if (e instanceof NovelError) throw e;
      throw new NovelError(e && e.code === 'E_TIMEOUT' ? ERR.TIMEOUT : (e && e.code === 'E_ABORTED' ? ERR.ABORTED : ERR.NETWORK), 'Request failed: ' + url + ' — ' + (e && e.message || e), { cause: e });
    }
  }
  get(url, options) { return this.request(url, { ...options, method: 'GET' }); }
  post(url, body, options = {}) { return this.request(url, { ...options, method: 'POST', body }); }
}
function hostKey(url) { try { return new URL(url).host; } catch (e) { const m = String(url).match(/^https?:\/\/([^/]+)/); return m ? m[1] : ''; } }
function charsetFromHeaders(headers) {
  if (!headers) return null;
  for (const [k, v] of Object.entries(headers)) {
    if (k.toLowerCase() === 'content-type') { const m = String(v).match(/charset\s*=\s*["']?([a-zA-Z0-9._-]+)/i); if (m) return m[1]; }
  }
  return null;
}
function charsetFromMeta(text) {
  if (!text) return null;
  const m = String(text).match(/<meta[^>]*?charset\s*=\s*["']?\s*([a-zA-Z0-9._-]+)/i);
  return m ? m[1] : null;
}
function bytesToAscii(bytes, limit) {
  const n = Math.min(bytes.length || 0, limit); let s = '';
  for (let i = 0; i < n; i += 512) { const chunk = []; const end = Math.min(i + 512, n); for (let j = i; j < end; j++) chunk.push(bytes[j] & 0xff); s += String.fromCharCode(...chunk); }
  return s;
}
function parseRetryAfter(headers) {
  if (!headers) return undefined;
  let v;
  for (const [k, val] of Object.entries(headers)) if (k.toLowerCase() === 'retry-after') { v = val; break; }
  if (v == null) return undefined;
  const sec = Number(v); if (Number.isFinite(sec)) return Math.min(Math.max(sec, 0) * 1000, 30000);
  const t = Date.parse(v); if (!isNaN(t)) return Math.min(Math.max(t - Date.now(), 0), 30000);
  return undefined;
}
function assertHttpStatus(res, url) {
  const status = res && typeof res.status === 'number' ? res.status : 0;
  if (!status) return;
  if (status === 429 || status >= 500) {
    const err = new NovelError(ERR.HTTP, 'HTTP ' + status + ' for ' + url, { details: { status, url } });
    err.status = status; err.retryAfterMs = parseRetryAfter(res.headers);
    throw err;
  }
  if (status >= 400) {
    const err = new NovelError(ERR.HTTP, 'HTTP ' + status + ' for ' + url, { details: { status, url } });
    err.status = status; err.noRetry = true;
    throw err;
  }
}
// AbortSignal-style control: a real AbortController when available,
// otherwise a minimal duck-typed signal ({aborted, addEventListener}).
function createAbortControl() {
  if (typeof AbortController !== 'undefined') { const c = new AbortController(); return { signal: c.signal, abort: () => { try { c.abort(); } catch (e) { /* already aborted */ } } }; }
  const listeners = [];
  const signal = { aborted: false, onabort: null, addEventListener: (t, f) => { if (t === 'abort') listeners.push(f); }, removeEventListener: (t, f) => { const i = listeners.indexOf(f); if (i >= 0) listeners.splice(i, 1); } };
  return { signal, abort: () => { if (signal.aborted) return; signal.aborted = true; for (const f of listeners) { try { f(); } catch (e) { /* listener errors are ignored */ } } if (typeof signal.onabort === 'function') { try { signal.onabort(); } catch (e) { /* ignored */ } } } };
}
function normalizeResponse(raw, reqUrl) {
  if (raw == null) return { status: 0, headers: {}, body: '', url: reqUrl };
  if (typeof raw === 'string') return { status: 200, headers: {}, body: raw, url: reqUrl };
  return { status: raw.status ?? raw.code ?? 200, headers: raw.headers || {}, body: raw.body != null ? String(raw.body) : '', url: raw.url || reqUrl, bytes: raw.bytes || null };
}
async function defaultFetchTransport(url, options = {}) {
  const init = { method: options.method || 'GET', headers: options.headers || {}, redirect: 'follow' };
  if (options.body != null && init.method !== 'GET') init.body = typeof options.body === 'string' ? options.body : JSON.stringify(options.body);
  let signal = options.signal || null;
  if (typeof AbortController !== 'undefined' && options.timeout) { const c = new AbortController(); if (signal && typeof signal.addEventListener === 'function') signal.addEventListener('abort', () => { try { c.abort(); } catch (e) { /* already aborted */ } }); timerSet(() => { try { c.abort(); } catch (e) { /* already aborted */ } }, options.timeout); signal = c.signal; }
  if (signal) init.signal = signal;
  const r = await fetch(url, init);
  const headers = {}; if (r.headers && r.headers.forEach) r.headers.forEach((v, k) => { headers[k] = v; });
  const buf = await r.arrayBuffer(); const bytes = new Uint8Array(buf);
  let body = '';
  if (typeof TextDecoder !== 'undefined') { try { body = new TextDecoder(options.charset || 'utf-8').decode(bytes); } catch (e) { body = ''; } }
  if (!body && bytes.length && typeof TextDecoder === 'undefined') { try { body = utf8Decode(Array.from(bytes)); } catch (e) { body = ''; } }
  return { status: r.status, headers, body, url: r.url || url, bytes };
}
module.exports.default = RequestManager;

module.exports.COOKIE_STORAGE_KEY = COOKIE_STORAGE_KEY;
module.exports.RequestManager = RequestManager;
module.exports.hostKey = hostKey;
module.exports.charsetFromHeaders = charsetFromHeaders;
module.exports.charsetFromMeta = charsetFromMeta;
module.exports.parseRetryAfter = parseRetryAfter;
module.exports.assertHttpStatus = assertHttpStatus;
module.exports.createAbortControl = createAbortControl;
module.exports.normalizeResponse = normalizeResponse;
module.exports.defaultFetchTransport = defaultFetchTransport;

});
__define('src/network/RetryManager.js', function(module, exports, __require){
const { delay } = __require('../core/TaskManager.js');
// Retry with exponential backoff: delay = base * 2^attempt. An error may
// carry `retryAfterMs` (e.g. from a Retry-After header) to override the
// computed delay for that attempt, or `noRetry: true` to fail immediately
// regardless of the remaining attempts.
class RetryManager{
  constructor(opts={}){ this.retries=opts.retries??2; this.delayMs=opts.retryDelay??400; this.shouldRetry=opts.shouldRetry||((e)=>{ const c=e&&e.code; return c!=='E_ABORTED' && c!=='E_UNSUPPORTED'; }); }
  async run(fn, opts={}){
    const max=opts.retries??this.retries; let lastErr;
    for(let attempt=0; attempt<=max; attempt++){
      try{ return await fn(attempt); }catch(e){ lastErr=e; if(attempt>=max||(e&&e.noRetry)||!this.shouldRetry(e)) throw e; const backoff=(opts.retryDelay??this.delayMs)*(2**attempt); await delay(e&&typeof e.retryAfterMs==='number'?e.retryAfterMs:backoff, opts.task); }
    }
    throw lastErr;
  }
}
module.exports.default = RetryManager;

module.exports.RetryManager = RetryManager;

});
__define('src/parser/CSSParser.js', function(module, exports, __require){
const { allElements, textOf } = __require('./HtmlParser.js');
// CSS selector subset: tag, .class, #id, [attr], [attr=v], descendant, child >, comma groups, :first-child-ish via .0 index handled by Legado layer
function matchSimple(el, simple){
  const parts=simple.match(/(^[a-zA-Z][\w-]*|\*)|([.#][\w-]+)|\[([^\]]+)\]/g)||[];
  for(const p of parts){
    if(p.startsWith('.')){ if(!(el.attrs.class||'').split(/\s+/).includes(p.slice(1))) return false; }
    else if(p.startsWith('#')){ if(el.attrs.id!==p.slice(1)) return false; }
    else if(p.startsWith('[')){ const inner=p.slice(1,-1); const eq=inner.indexOf('='); if(eq<0){ if(!(inner.trim() in el.attrs)) return false; } else { const k=inner.slice(0,eq).trim(), v=inner.slice(eq+1).trim().replace(/^["']|["']$/g,''); if(el.attrs[k]!==v) return false; } }
    else if(p!=='*'){ if(el.tag!==p.toLowerCase()) return false; }
  }
  return true;
}
function queryAll(root, selector){
  const groups=String(selector).split(',').map(s=>s.trim()).filter(Boolean); const out=[]; const seen=new Set();
  for(const g of groups){
    const steps=g.split(/\s*>\s*/).flatMap(part=>part.trim().split(/\s+/).filter(Boolean).map((s,i,arr)=>({s, comb: i===0?' ':' '})));
    // Simpler: handle descendant + child by sequential filtering
    const tokens=g.replace(/\s*>\s*/g,' > ').split(/\s+/).filter(Boolean);
    let current=[root];
    let comb=' ';
    for(const tok of tokens){
      if(tok==='>'){ comb='>'; continue; }
      const next=[];
      for(const ctx of current){
        const pool= comb==='>' ? (ctx.children||[]).filter(c=>c.type==='element') : allElements(ctx);
        for(const el of pool) if(matchSimple(el,tok)) next.push(el);
      }
      current=next; comb=' ';
    }
    for(const el of current) if(!seen.has(el)){ seen.add(el); out.push(el); }
  }
  return out;
}
function query(root, selector){ return queryAll(root, selector)[0]||null; }
module.exports.textOf = textOf;

module.exports.queryAll = queryAll;
module.exports.query = query;

});
__define('src/parser/CryptoLite.js', function(module, exports, __require){
// CryptoLite — pure-JS, zero-dependency crypto subset for Legado source rules:
//   SHA-1 / SHA-256 digests, HMAC-SHA1 / HMAC-SHA256, AES-128/192/256
//   (ECB / CBC, PKCS#7 padding), a CryptoJS-compatible subset, and a
//   Legado `createSymmetricCrypto` equivalent.
// Everything operates on Uint8Array; string encodings: 'utf8' | 'hex' | 'base64'.
// Verified against FIPS 197 / SP 800-38A / RFC 2202 / RFC 4231 vectors and
// cross-checked with node:crypto in tests/crypto.test.js.
//
// Honest differences vs the Legado original (Hutool/JCE):
//  - Only AES is implemented for symmetric crypto (DES / DESede throw
//    E_UNSUPPORTED instead of silently misbehaving).
//  - createSymmetricCrypto key strings are UTF-8 bytes; a key whose byte
//    length is not 16/24/32 is zero-padded to the next valid size (or
//    truncated to 32). JCE would throw for such keys, so sources relying on
//    exact-length keys behave identically; odd-length passwords get a
//    documented, deterministic fallback here instead of a crash.
const { utf8Encode, utf8Decode, base64EncodeBytes, base64DecodeToBin } = __require('../core/utils.js');
const { NovelError, ERR } = __require('../core/errors.js');

// ---------------- byte <-> string encodings ----------------
function bytesToHex(bytes) { let s = ''; for (const b of bytes) s += ('0' + b.toString(16)).slice(-2); return s; }
function hexToBytes(hex) {
  const clean = String(hex).replace(/[^0-9a-fA-F]/g, '');
  const out = new Uint8Array(Math.floor(clean.length / 2));
  for (let i = 0; i < out.length; i++) out[i] = parseInt(clean.slice(i * 2, i * 2 + 2), 16);
  return out;
}
function bytesToBase64(bytes) { return base64EncodeBytes(bytes); }
function base64ToBytes(b64) { const bin = base64DecodeToBin(String(b64)); const out = new Uint8Array(bin.length); for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i); return out; }
function toBytes(value, encoding = 'utf8') {
  if (value == null) return new Uint8Array(0);
  if (value instanceof Uint8Array) return value;
  if (Array.isArray(value)) return Uint8Array.from(value);
  const s = String(value);
  const enc = String(encoding || 'utf8').toLowerCase();
  if (enc === 'hex') return hexToBytes(s);
  if (enc === 'base64') return base64ToBytes(s);
  return Uint8Array.from(utf8Encode(s));
}
function fromBytes(bytes, encoding = 'utf8') {
  const enc = String(encoding || 'utf8').toLowerCase();
  if (enc === 'hex') return bytesToHex(bytes);
  if (enc === 'base64') return bytesToBase64(bytes);
  if (enc === 'bytes') return bytes;
  return utf8Decode(Array.from(bytes));
}
function isHexString(s) { return typeof s === 'string' && s.length > 0 && s.length % 2 === 0 && /^[0-9a-fA-F]+$/.test(s.trim()); }

// ---------------- MD5 (bytes; needed for EVP key derivation) ----------------
const MD5K = [0xd76aa478,0xe8c7b756,0x242070db,0xc1bdceee,0xf57c0faf,0x4787c62a,0xa8304613,0xfd469501,0x698098d8,0x8b44f7af,0xffff5bb1,0x895cd7be,0x6b901122,0xfd987193,0xa679438e,0x49b40821,0xf61e2562,0xc040b340,0x265e5a51,0xe9b6c7aa,0xd62f105d,0x02441453,0xd8a1e681,0xe7d3fbc8,0x21e1cde6,0xc33707d6,0xf4d50d87,0x455a14ed,0xa9e3e905,0xfcefa3f8,0x676f02d9,0x8d2a4c8a,0xfffa3942,0x8771f681,0x6d9d6122,0xfde5380c,0xa4beea44,0x4bdecfa9,0xf6bb4b60,0xbebfbc70,0x289b7ec6,0xeaa127fa,0xd4ef3085,0x04881d05,0xd9d4d039,0xe6db99e5,0x1fa27cf8,0xc4ac5665,0xf4292244,0x432aff97,0xab9423a7,0xfc93a039,0x655b59c3,0x8f0ccc92,0xffeff47d,0x85845dd1,0x6fa87e4f,0xfe2ce6e0,0xa3014314,0x4e0811a1,0xf7537e82,0xbd3af235,0x2ad7d2bb,0xeb86d391];
const MD5S = [7,12,17,22,7,12,17,22,7,12,17,22,7,12,17,22,5,9,14,20,5,9,14,20,5,9,14,20,5,9,14,20,4,11,16,23,4,11,16,23,4,11,16,23,4,11,16,23,6,10,15,21,6,10,15,21,6,10,15,21,6,10,15,21];
function md5Bytes(input) {
  const bytes = Array.from(input); const bitLen = bytes.length * 8;
  bytes.push(0x80); while (bytes.length % 64 !== 56) bytes.push(0);
  let lo = bitLen >>> 0, hi = Math.floor(bitLen / 4294967296) >>> 0;
  for (let i = 0; i < 4; i++) { bytes.push(lo & 255); lo >>>= 8; } for (let i = 0; i < 4; i++) { bytes.push(hi & 255); hi >>>= 8; }
  let a0 = 0x67452301, b0 = 0xefcdab89, c0 = 0x98badcfe, d0 = 0x10325476;
  const rotl = (x, s) => ((x << s) | (x >>> (32 - s))) >>> 0; const add = (x, y) => (x + y) >>> 0;
  for (let off = 0; off < bytes.length; off += 64) {
    const M = []; for (let j = 0; j < 16; j++) M[j] = (bytes[off + j * 4] | (bytes[off + j * 4 + 1] << 8) | (bytes[off + j * 4 + 2] << 16) | (bytes[off + j * 4 + 3] << 24)) >>> 0;
    let A = a0, B = b0, C = c0, D = d0;
    for (let i = 0; i < 64; i++) { let F, g; if (i < 16) { F = (B & C) | (~B & D); g = i; } else if (i < 32) { F = (D & B) | (~D & C); g = (5 * i + 1) % 16; } else if (i < 48) { F = B ^ C ^ D; g = (3 * i + 5) % 16; } else { F = C ^ (B | ~D); g = (7 * i) % 16; }
      const tmp = D; D = C; C = B; B = add(B, rotl(add(add(A, F >>> 0), add(MD5K[i], M[g])), MD5S[i])); A = tmp; }
    a0 = add(a0, A); b0 = add(b0, B); c0 = add(c0, C); d0 = add(d0, D);
  }
  const out = new Uint8Array(16); const words = [a0, b0, c0, d0];
  words.forEach((w, i) => { for (let j = 0; j < 4; j++) out[i * 4 + j] = (w >>> (j * 8)) & 255; });
  return out;
}

// ---------------- SHA-1 ----------------
function sha1(input) {
  const bytes = Array.from(input); const bitLen = bytes.length * 8;
  bytes.push(0x80); while (bytes.length % 64 !== 56) bytes.push(0);
  let hi = Math.floor(bitLen / 4294967296) >>> 0, lo = bitLen >>> 0;
  for (let i = 0; i < 4; i++) { bytes.push((hi >>> (24 - i * 8)) & 255); } for (let i = 0; i < 4; i++) { bytes.push((lo >>> (24 - i * 8)) & 255); }
  let h0 = 0x67452301, h1 = 0xEFCDAB89, h2 = 0x98BADCFE, h3 = 0x10325476, h4 = 0xC3D2E1F0;
  const rotl = (x, s) => ((x << s) | (x >>> (32 - s))) >>> 0;
  const W = new Array(80);
  for (let off = 0; off < bytes.length; off += 64) {
    for (let i = 0; i < 16; i++) W[i] = ((bytes[off + i * 4] << 24) | (bytes[off + i * 4 + 1] << 16) | (bytes[off + i * 4 + 2] << 8) | bytes[off + i * 4 + 3]) >>> 0;
    for (let i = 16; i < 80; i++) W[i] = rotl(W[i - 3] ^ W[i - 8] ^ W[i - 14] ^ W[i - 16], 1);
    let a = h0, b = h1, c = h2, d = h3, e = h4;
    for (let i = 0; i < 80; i++) {
      let f, k; if (i < 20) { f = (b & c) | (~b & d); k = 0x5A827999; } else if (i < 40) { f = b ^ c ^ d; k = 0x6ED9EBA1; } else if (i < 60) { f = (b & c) | (b & d) | (c & d); k = 0x8F1BBCDC; } else { f = b ^ c ^ d; k = 0xCA62C1D6; }
      const tmp = (rotl(a, 5) + f + e + k + W[i]) >>> 0; e = d; d = c; c = rotl(b, 30); b = a; a = tmp;
    }
    h0 = (h0 + a) >>> 0; h1 = (h1 + b) >>> 0; h2 = (h2 + c) >>> 0; h3 = (h3 + d) >>> 0; h4 = (h4 + e) >>> 0;
  }
  const out = new Uint8Array(20); [h0, h1, h2, h3, h4].forEach((h, i) => { for (let j = 0; j < 4; j++) out[i * 4 + j] = (h >>> (24 - j * 8)) & 255; });
  return out;
}

// ---------------- SHA-256 ----------------
// Constants are the fractional parts of sqrt/cbrt of the first primes
// (FIPS 180-4 §4.2) — generated at load instead of a hand-typed table,
// and pinned by the test vectors.
function firstPrimes(n) { const primes = []; let c = 2; while (primes.length < n) { let ok = true; for (const p of primes) { if (p * p > c) break; if (c % p === 0) { ok = false; break; } } if (ok) primes.push(c); c++; } return primes; }
const _primes = firstPrimes(64);
const _frac32 = (x) => Math.floor((x - Math.floor(x)) * 4294967296) >>> 0;
const SHA256_H0 = _primes.slice(0, 8).map(p => _frac32(Math.sqrt(p)));
const SHA256_K = _primes.map(p => _frac32(Math.cbrt(p)));
function sha256(input) {
  const bytes = Array.from(input); const bitLen = bytes.length * 8;
  bytes.push(0x80); while (bytes.length % 64 !== 56) bytes.push(0);
  let hi = Math.floor(bitLen / 4294967296) >>> 0, lo = bitLen >>> 0;
  for (let i = 0; i < 4; i++) bytes.push((hi >>> (24 - i * 8)) & 255); for (let i = 0; i < 4; i++) bytes.push((lo >>> (24 - i * 8)) & 255);
  const H = SHA256_H0.slice(); const W = new Array(64);
  const rotr = (x, s) => ((x >>> s) | (x << (32 - s))) >>> 0;
  for (let off = 0; off < bytes.length; off += 64) {
    for (let i = 0; i < 16; i++) W[i] = ((bytes[off + i * 4] << 24) | (bytes[off + i * 4 + 1] << 16) | (bytes[off + i * 4 + 2] << 8) | bytes[off + i * 4 + 3]) >>> 0;
    for (let i = 16; i < 64; i++) { const s0 = rotr(W[i - 15], 7) ^ rotr(W[i - 15], 18) ^ (W[i - 15] >>> 3); const s1 = rotr(W[i - 2], 17) ^ rotr(W[i - 2], 19) ^ (W[i - 2] >>> 10); W[i] = (W[i - 16] + s0 + W[i - 7] + s1) >>> 0; }
    let [a, b, c, d, e, f, g, h] = H;
    for (let i = 0; i < 64; i++) {
      const S1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25); const ch = (e & f) ^ (~e & g);
      const t1 = (h + S1 + ch + SHA256_K[i] + W[i]) >>> 0;
      const S0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22); const maj = (a & b) ^ (a & c) ^ (b & c);
      const t2 = (S0 + maj) >>> 0;
      h = g; g = f; f = e; e = (d + t1) >>> 0; d = c; c = b; b = a; a = (t1 + t2) >>> 0;
    }
    H[0] = (H[0] + a) >>> 0; H[1] = (H[1] + b) >>> 0; H[2] = (H[2] + c) >>> 0; H[3] = (H[3] + d) >>> 0; H[4] = (H[4] + e) >>> 0; H[5] = (H[5] + f) >>> 0; H[6] = (H[6] + g) >>> 0; H[7] = (H[7] + h) >>> 0;
  }
  const out = new Uint8Array(32); H.forEach((w, i) => { for (let j = 0; j < 4; j++) out[i * 4 + j] = (w >>> (24 - j * 8)) & 255; });
  return out;
}

// ---------------- digest / HMAC dispatch ----------------
function normalizeAlgoName(algorithm) {
  const a = String(algorithm || '').toLowerCase().replace(/[-_\s]/g, '');
  if (a === 'md5') return 'md5';
  if (a === 'sha1' || a === 'hmacsha1') return 'sha1';
  if (a === 'sha256' || a === 'hmacsha256') return 'sha256';
  return a;
}
function digestBytes(algorithm, dataBytes) {
  const a = normalizeAlgoName(algorithm);
  if (a === 'md5') return md5Bytes(dataBytes);
  if (a === 'sha1') return sha1(dataBytes);
  if (a === 'sha256') return sha256(dataBytes);
  throw new NovelError(ERR.UNSUPPORTED, 'digest algorithm not supported in CryptoLite: ' + algorithm + ' (supported: MD5, SHA-1, SHA-256)');
}
function hmacBytes(algorithm, keyBytes, dataBytes) {
  const a = normalizeAlgoName(algorithm);
  const hash = a === 'sha1' ? sha1 : a === 'sha256' ? sha256 : null;
  if (!hash) throw new NovelError(ERR.UNSUPPORTED, 'HMAC algorithm not supported in CryptoLite: ' + algorithm + ' (supported: HmacSHA1, HmacSHA256)');
  const blockSize = 64;
  let key = Uint8Array.from(keyBytes);
  if (key.length > blockSize) key = hash(key);
  const padded = new Uint8Array(blockSize); padded.set(key);
  const ipad = new Uint8Array(blockSize), opad = new Uint8Array(blockSize);
  for (let i = 0; i < blockSize; i++) { ipad[i] = padded[i] ^ 0x36; opad[i] = padded[i] ^ 0x5c; }
  const inner = new Uint8Array(blockSize + dataBytes.length); inner.set(ipad); inner.set(dataBytes, blockSize);
  const innerHash = hash(inner);
  const outer = new Uint8Array(blockSize + innerHash.length); outer.set(opad); outer.set(innerHash, blockSize);
  return hash(outer);
}

// ---------------- AES (FIPS 197) ----------------
// Build GF(2^8) tables with generator 3 (standard construction).
const GF = (() => {
  const exp = new Uint8Array(512), log = new Uint8Array(256);
  let x = 1;
  for (let i = 0; i < 255; i++) {
    exp[i] = x; log[x] = i;
    // multiply x by 3: x*3 = x*2 ^ x
    const x2 = ((x << 1) ^ ((x & 0x80) ? 0x1b : 0)) & 0xff;
    x = x2 ^ x;
  }
  for (let i = 255; i < 512; i++) exp[i] = exp[i - 255];
  const mul = (a, b) => (a === 0 || b === 0) ? 0 : exp[log[a] + log[b]];
  const inv = (a) => a === 0 ? 0 : exp[255 - log[a]];
  const rotl8 = (v, s) => ((v << s) | (v >>> (8 - s))) & 0xff;
  const sbox = new Uint8Array(256), invSbox = new Uint8Array(256);
  for (let i = 0; i < 256; i++) { const v = inv(i); const s = (v ^ rotl8(v, 1) ^ rotl8(v, 2) ^ rotl8(v, 3) ^ rotl8(v, 4) ^ 0x63) & 0xff; sbox[i] = s; invSbox[s] = i; }
  return { mul, sbox, invSbox };
})();
const RCON = [0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80, 0x1b, 0x36, 0x6c, 0xd8, 0xab, 0x4d];
function expandKey(key) {
  const Nk = key.length / 4; const Nr = Nk + 6;
  const w = new Uint8Array(16 * (Nr + 1));
  w.set(key);
  const temp = new Uint8Array(4);
  for (let i = Nk; i < 4 * (Nr + 1); i++) {
    temp.set(w.slice((i - 1) * 4, i * 4));
    if (i % Nk === 0) { const t = temp[0]; temp[0] = GF.sbox[temp[1]] ^ RCON[i / Nk - 1]; temp[1] = GF.sbox[temp[2]]; temp[2] = GF.sbox[temp[3]]; temp[3] = GF.sbox[t]; }
    else if (Nk > 6 && i % Nk === 4) { for (let j = 0; j < 4; j++) temp[j] = GF.sbox[temp[j]]; }
    for (let j = 0; j < 4; j++) w[i * 4 + j] = w[(i - Nk) * 4 + j] ^ temp[j];
  }
  return { roundKeys: w, Nr };
}
function addRoundKey(state, roundKeys, round) { for (let i = 0; i < 16; i++) state[i] ^= roundKeys[round * 16 + i]; }
function subBytes(state, box) { for (let i = 0; i < 16; i++) state[i] = box[state[i]]; }
function shiftRows(state) { const t = Uint8Array.from(state); for (let r = 1; r < 4; r++) for (let c = 0; c < 4; c++) state[r + 4 * c] = t[r + 4 * ((c + r) % 4)]; }
function invShiftRows(state) { const t = Uint8Array.from(state); for (let r = 1; r < 4; r++) for (let c = 0; c < 4; c++) state[r + 4 * c] = t[r + 4 * ((c - r + 4) % 4)]; }
function mixColumns(state) { for (let c = 0; c < 4; c++) { const i = 4 * c; const a0 = state[i], a1 = state[i + 1], a2 = state[i + 2], a3 = state[i + 3]; state[i] = GF.mul(a0, 2) ^ GF.mul(a1, 3) ^ a2 ^ a3; state[i + 1] = a0 ^ GF.mul(a1, 2) ^ GF.mul(a2, 3) ^ a3; state[i + 2] = a0 ^ a1 ^ GF.mul(a2, 2) ^ GF.mul(a3, 3); state[i + 3] = GF.mul(a0, 3) ^ a1 ^ a2 ^ GF.mul(a3, 2); } }
function invMixColumns(state) { for (let c = 0; c < 4; c++) { const i = 4 * c; const a0 = state[i], a1 = state[i + 1], a2 = state[i + 2], a3 = state[i + 3]; state[i] = GF.mul(a0, 14) ^ GF.mul(a1, 11) ^ GF.mul(a2, 13) ^ GF.mul(a3, 9); state[i + 1] = GF.mul(a0, 9) ^ GF.mul(a1, 14) ^ GF.mul(a2, 11) ^ GF.mul(a3, 13); state[i + 2] = GF.mul(a0, 13) ^ GF.mul(a1, 9) ^ GF.mul(a2, 14) ^ GF.mul(a3, 11); state[i + 3] = GF.mul(a0, 11) ^ GF.mul(a1, 13) ^ GF.mul(a2, 9) ^ GF.mul(a3, 14); } }
class AesCipher {
  constructor(keyBytes) {
    if (![16, 24, 32].includes(keyBytes.length)) throw new NovelError(ERR.VALIDATION, 'AES key must be 16/24/32 bytes, got ' + keyBytes.length);
    const { roundKeys, Nr } = expandKey(keyBytes); this.roundKeys = roundKeys; this.Nr = Nr;
  }
  encryptBlock(block) {
    const state = Uint8Array.from(block);
    addRoundKey(state, this.roundKeys, 0);
    for (let round = 1; round < this.Nr; round++) { subBytes(state, GF.sbox); shiftRows(state); mixColumns(state); addRoundKey(state, this.roundKeys, round); }
    subBytes(state, GF.sbox); shiftRows(state); addRoundKey(state, this.roundKeys, this.Nr);
    return state;
  }
  decryptBlock(block) {
    const state = Uint8Array.from(block);
    addRoundKey(state, this.roundKeys, this.Nr);
    for (let round = this.Nr - 1; round >= 1; round--) { invShiftRows(state); subBytes(state, GF.invSbox); addRoundKey(state, this.roundKeys, round); invMixColumns(state); }
    invShiftRows(state); subBytes(state, GF.invSbox); addRoundKey(state, this.roundKeys, 0);
    return state;
  }
}
function pkcs7Pad(data, blockSize = 16) { const pad = blockSize - (data.length % blockSize); const out = new Uint8Array(data.length + pad); out.set(data); out.fill(pad, data.length); return out; }
function pkcs7Unpad(data) {
  if (!data.length) return data;
  const pad = data[data.length - 1];
  if (pad < 1 || pad > 16 || pad > data.length) throw new NovelError(ERR.PARSE, 'Invalid PKCS7 padding');
  for (let i = data.length - pad; i < data.length; i++) if (data[i] !== pad) throw new NovelError(ERR.PARSE, 'Invalid PKCS7 padding');
  return data.slice(0, data.length - pad);
}
function aesEncrypt(dataBytes, keyBytes, options = {}) {
  const mode = String(options.mode || 'CBC').toUpperCase();
  const padding = String(options.padding || 'pkcs7').toLowerCase();
  const cipher = new AesCipher(keyBytes);
  const data = (padding === 'none' || padding === 'nopadding') ? dataBytes : pkcs7Pad(dataBytes);
  if (data.length % 16 !== 0) throw new NovelError(ERR.VALIDATION, 'AES input length must be a multiple of 16 when padding is off');
  const out = new Uint8Array(data.length);
  if (mode === 'ECB') { for (let i = 0; i < data.length; i += 16) out.set(cipher.encryptBlock(data.slice(i, i + 16)), i); return out; }
  if (mode === 'CBC') {
    const iv = options.iv ? Uint8Array.from(options.iv) : new Uint8Array(16);
    if (iv.length !== 16) throw new NovelError(ERR.VALIDATION, 'AES-CBC IV must be 16 bytes');
    let prev = iv;
    for (let i = 0; i < data.length; i += 16) { const block = data.slice(i, i + 16); for (let j = 0; j < 16; j++) block[j] ^= prev[j]; const enc = cipher.encryptBlock(block); out.set(enc, i); prev = enc; }
    return out;
  }
  throw new NovelError(ERR.UNSUPPORTED, 'AES mode not supported: ' + mode + ' (supported: CBC, ECB)');
}
function aesDecrypt(dataBytes, keyBytes, options = {}) {
  const mode = String(options.mode || 'CBC').toUpperCase();
  const padding = String(options.padding || 'pkcs7').toLowerCase();
  const cipher = new AesCipher(keyBytes);
  if (dataBytes.length % 16 !== 0) throw new NovelError(ERR.PARSE, 'AES ciphertext length must be a multiple of 16');
  const out = new Uint8Array(dataBytes.length);
  if (mode === 'ECB') { for (let i = 0; i < dataBytes.length; i += 16) out.set(cipher.decryptBlock(dataBytes.slice(i, i + 16)), i); }
  else if (mode === 'CBC') {
    const iv = options.iv ? Uint8Array.from(options.iv) : new Uint8Array(16);
    if (iv.length !== 16) throw new NovelError(ERR.VALIDATION, 'AES-CBC IV must be 16 bytes');
    let prev = iv;
    for (let i = 0; i < dataBytes.length; i += 16) { const block = dataBytes.slice(i, i + 16); const dec = cipher.decryptBlock(block); for (let j = 0; j < 16; j++) dec[j] ^= prev[j]; out.set(dec, i); prev = block; }
  } else throw new NovelError(ERR.UNSUPPORTED, 'AES mode not supported: ' + mode + ' (supported: CBC, ECB)');
  return (padding === 'none' || padding === 'nopadding') ? out : pkcs7Unpad(out);
}

// ---------------- Legado createSymmetricCrypto ----------------
function normalizeAesKeyBytes(raw) {
  if ([16, 24, 32].includes(raw.length)) return raw;
  if (raw.length > 32) return raw.slice(0, 32);
  const size = raw.length <= 16 ? 16 : raw.length <= 24 ? 24 : 32;
  const out = new Uint8Array(size); out.set(raw); return out;
}
function parseTransformation(transformation) {
  const parts = String(transformation || 'AES/CBC/PKCS5Padding').split('/');
  const algo = (parts[0] || 'AES').toUpperCase();
  const mode = (parts[1] || 'CBC').toUpperCase();
  const padRaw = (parts[2] || 'PKCS5Padding').toLowerCase();
  const padding = padRaw.startsWith('nopadding') || padRaw === 'none' ? 'none' : 'pkcs7';
  return { algo, mode, padding };
}
function createSymmetricCrypto(transformation, key, iv) {
  const { algo, mode, padding } = parseTransformation(transformation);
  if (algo !== 'AES') throw new NovelError(ERR.UNSUPPORTED, 'createSymmetricCrypto only supports AES in CryptoLite, got: ' + algo + ' (DES/DESede unsupported)');
  const keyBytes = normalizeAesKeyBytes(toBytes(key ?? '', 'utf8'));
  const ivBytes = iv == null || iv === '' ? null : toBytes(iv, 'utf8');
  const opts = { mode, padding, iv: ivBytes };
  const dataIn = (data) => data instanceof Uint8Array ? data : toBytes(data, 'utf8');
  const cipherTextIn = (data) => { if (data instanceof Uint8Array) return data; const s = String(data); return isHexString(s) ? hexToBytes(s) : base64ToBytes(s); };
  return {
    encrypt(data) { return aesEncrypt(dataIn(data), keyBytes, opts); },
    encryptBase64(data) { return bytesToBase64(aesEncrypt(dataIn(data), keyBytes, opts)); },
    encryptHex(data) { return bytesToHex(aesEncrypt(dataIn(data), keyBytes, opts)); },
    decrypt(data) { return aesDecrypt(cipherTextIn(data), keyBytes, opts); },
    decryptStr(data) { return utf8Decode(Array.from(aesDecrypt(cipherTextIn(data), keyBytes, opts))); },
    decryptBase64(data) { return aesDecrypt(base64ToBytes(String(data)), keyBytes, opts); },
  };
}

// ---------------- CryptoJS subset ----------------
class WordArrayLite {
  constructor(bytes) { this.bytes = bytes instanceof Uint8Array ? bytes : Uint8Array.from(bytes || []); this.sigBytes = this.bytes.length; this.words = []; for (let i = 0; i < this.bytes.length; i += 4) this.words.push(((this.bytes[i] || 0) << 24) | ((this.bytes[i + 1] || 0) << 16) | ((this.bytes[i + 2] || 0) << 8) | (this.bytes[i + 3] || 0)); }
  toString(encoder) { if (encoder && encoder.stringify) return encoder.stringify(this); return bytesToHex(this.bytes); }
  concat(other) { const o = other instanceof WordArrayLite ? other.bytes : toBytes(other); const out = new Uint8Array(this.bytes.length + o.length); out.set(this.bytes); out.set(o, this.bytes.length); return new WordArrayLite(out); }
}
const encUtf8 = { stringify: (wa) => utf8Decode(Array.from(wa.bytes)), parse: (s) => new WordArrayLite(toBytes(s, 'utf8')) };
const encHex = { stringify: (wa) => bytesToHex(wa.bytes), parse: (s) => new WordArrayLite(hexToBytes(s)) };
const encBase64 = { stringify: (wa) => bytesToBase64(wa.bytes), parse: (s) => new WordArrayLite(base64ToBytes(s)) };
const encLatin1 = { stringify: (wa) => { let s = ''; for (const b of wa.bytes) s += String.fromCharCode(b); return s; }, parse: (s) => { const out = new Uint8Array(s.length); for (let i = 0; i < s.length; i++) out[i] = s.charCodeAt(i) & 255; return new WordArrayLite(out); } };
function evpBytesToKey(passwordBytes, saltBytes, keyLen, ivLen) {
  const out = []; let prev = new Uint8Array(0); let total = 0;
  while (total < keyLen + ivLen) { const data = new Uint8Array(prev.length + passwordBytes.length + saltBytes.length); data.set(prev); data.set(passwordBytes, prev.length); data.set(saltBytes, prev.length + passwordBytes.length); prev = md5Bytes(data); out.push(prev); total += prev.length; }
  const joined = new Uint8Array(total); let off = 0; for (const chunk of out) { joined.set(chunk, off); off += chunk.length; }
  return { key: joined.slice(0, keyLen), iv: joined.slice(keyLen, keyLen + ivLen) };
}
function cryptoJsKeyIv(data, key, opts) {
  let salt = new Uint8Array(0);
  let ciphertext = null;
  if (data != null && typeof data === 'object' && data.ciphertext instanceof WordArrayLite) { ciphertext = data.ciphertext.bytes; if (data.salt instanceof WordArrayLite) salt = data.salt.bytes; }
  if (typeof data === 'string') { const raw = base64ToBytes(data); if (raw.length > 16 && utf8Decode(Array.from(raw.slice(0, 8))) === 'Salted__') { salt = raw.slice(8, 16); ciphertext = raw.slice(16); } else ciphertext = raw; }
  if (data instanceof WordArrayLite) ciphertext = data.bytes;
  if (data instanceof Uint8Array) ciphertext = data;
  let keyBytes, ivBytes;
  if (key instanceof WordArrayLite) { keyBytes = key.bytes; ivBytes = opts.iv instanceof WordArrayLite ? opts.iv.bytes : opts.iv ? toBytes(opts.iv) : new Uint8Array(16); }
  else { const derived = evpBytesToKey(toBytes(String(key ?? ''), 'utf8'), salt, 32, 16); keyBytes = derived.key; ivBytes = opts.iv ? (opts.iv instanceof WordArrayLite ? opts.iv.bytes : toBytes(opts.iv)) : derived.iv; }
  return { keyBytes, ivBytes, salt, ciphertext };
}
const CryptoJS = {
  enc: { Utf8: encUtf8, Hex: encHex, Base64: encBase64, Latin1: encLatin1 },
  mode: { CBC: { name: 'CBC' }, ECB: { name: 'ECB' } },
  pad: { Pkcs7: { name: 'pkcs7' }, NoPadding: { name: 'none' } },
  lib: { WordArray: { create: (bytes) => new WordArrayLite(bytes instanceof Uint8Array ? bytes : toBytes(bytes)) } },
  MD5: (s) => new WordArrayLite(md5Bytes(toBytes(s instanceof WordArrayLite ? s.bytes : s, 'utf8'))),
  SHA1: (s) => new WordArrayLite(sha1(toBytes(s instanceof WordArrayLite ? s.bytes : s, 'utf8'))),
  SHA256: (s) => new WordArrayLite(sha256(toBytes(s instanceof WordArrayLite ? s.bytes : s, 'utf8'))),
  AES: {
    encrypt(data, key, opts = {}) {
      const { keyBytes, ivBytes, salt } = cryptoJsKeyIv(null, key, opts);
      const plain = data instanceof WordArrayLite ? data.bytes : toBytes(data, 'utf8');
      const mode = opts.mode && opts.mode.name ? opts.mode.name : 'CBC';
      const padding = opts.padding && opts.padding.name === 'none' ? 'none' : 'pkcs7';
      const ct = aesEncrypt(plain, keyBytes, { mode, iv: ivBytes, padding });
      const params = { ciphertext: new WordArrayLite(ct), key: new WordArrayLite(keyBytes), iv: new WordArrayLite(ivBytes), salt: salt.length ? new WordArrayLite(salt) : undefined,
        toString() { if (salt.length) { const head = new Uint8Array(16); head.set(toBytes('Salted__', 'utf8')); head.set(salt, 8); const all = new Uint8Array(16 + ct.length); all.set(head); all.set(ct, 16); return bytesToBase64(all); } return bytesToBase64(ct); } };
      return params;
    },
    decrypt(data, key, opts = {}) {
      const { keyBytes, ivBytes, ciphertext } = cryptoJsKeyIv(data, key, opts);
      if (!ciphertext) throw new NovelError(ERR.PARSE, 'CryptoJS.AES.decrypt: no ciphertext given');
      const mode = opts.mode && opts.mode.name ? opts.mode.name : 'CBC';
      const padding = opts.padding && opts.padding.name === 'none' ? 'none' : 'pkcs7';
      return new WordArrayLite(aesDecrypt(ciphertext, keyBytes, { mode, iv: ivBytes, padding }));
    },
  },
};
module.exports.default = CryptoJS;

module.exports.bytesToHex = bytesToHex;
module.exports.hexToBytes = hexToBytes;
module.exports.bytesToBase64 = bytesToBase64;
module.exports.base64ToBytes = base64ToBytes;
module.exports.toBytes = toBytes;
module.exports.fromBytes = fromBytes;
module.exports.isHexString = isHexString;
module.exports.md5Bytes = md5Bytes;
module.exports.sha1 = sha1;
module.exports.sha256 = sha256;
module.exports.normalizeAlgoName = normalizeAlgoName;
module.exports.digestBytes = digestBytes;
module.exports.hmacBytes = hmacBytes;
module.exports.AesCipher = AesCipher;
module.exports.pkcs7Pad = pkcs7Pad;
module.exports.pkcs7Unpad = pkcs7Unpad;
module.exports.aesEncrypt = aesEncrypt;
module.exports.aesDecrypt = aesDecrypt;
module.exports.parseTransformation = parseTransformation;
module.exports.createSymmetricCrypto = createSymmetricCrypto;
module.exports.WordArrayLite = WordArrayLite;
module.exports.CryptoJS = CryptoJS;

});
__define('src/parser/HtmlParser.js', function(module, exports, __require){
const { decodeEntities } = __require('../core/utils.js');
// Minimal pure-JS HTML parser (no DOM). Produces node tree:
// { type:'element'|'text', tag, attrs:{}, children:[], parent, text }
const VOID=new Set(['br','img','hr','meta','link','input','area','base','col','embed','source','track','wbr']);
// HTML5 implied end tags (subset that matters for scraped novel pages):
// a start tag in CLOSES_P ends an open <p>. Without this, the classic
// unclosed-paragraph markup (<p>第一段<p>第二段…) nested every paragraph
// inside the previous one, and the recursive traversals below overflowed
// the JS stack on long chapters (QuickJS stacks are small: ~1000 unclosed
// paragraphs were enough). Sibling rules: li, dd/dt, tr, td/th, option,
// optgroup, thead/tbody and headings close their own kind.
const CLOSES_P=new Set(['address','article','aside','blockquote','details','div','dl','dd','dt','fieldset','figcaption','figure','footer','form','h1','h2','h3','h4','h5','h6','header','hgroup','hr','li','main','menu','nav','ol','p','pre','section','table','ul']);
const HEADINGS=new Set(['h1','h2','h3','h4','h5','h6']);
function impliedClose(cur, newTag, root){
  let n=cur;
  while(n!==root){
    const t=n.tag;
    const closes=(t==='p'&&CLOSES_P.has(newTag))
      ||(t==='li'&&newTag==='li')
      ||((t==='dd'||t==='dt')&&(newTag==='dd'||newTag==='dt'))
      ||((t==='td'||t==='th')&&(newTag==='td'||newTag==='th'||newTag==='tr'))
      ||(t==='tr'&&newTag==='tr')
      ||(t==='option'&&(newTag==='option'||newTag==='optgroup'))
      ||(t==='optgroup'&&newTag==='optgroup')
      ||((t==='thead'||t==='tbody')&&(newTag==='tbody'||newTag==='tfoot'))
      ||(HEADINGS.has(t)&&HEADINGS.has(newTag));
    if(!closes) break;
    n=n.parent||root;
  }
  return n;
}
// Hard cap on element nesting. Iterative traversals made depth
// heap-bound, but a pathological page (tens of thousands of nested
// unclosed tags) would still build an absurd tree; beyond the cap new
// elements flatten into siblings at the cap frontier instead of
// descending. 256 is far above any real page (legit depth is < 40).
const MAX_HTML_DEPTH=256;
function parseHtml(html){
  const root={type:'element',tag:'#root',attrs:{},children:[],parent:null,_depth:0};
  let cur=root; const s=String(html||''); let i=0;
  while(i<s.length){
    if(s.startsWith('<!--',i)){ const e=s.indexOf('-->',i); i=e<0?s.length:e+3; continue; }
    if(s[i]==='<'){
      const gt=s.indexOf('>',i); if(gt<0) break;
      let inside=s.slice(i+1,gt); i=gt+1;
      if(inside.startsWith('!')) continue;
      if(inside.startsWith('/')){ const tag=inside.slice(1).trim().toLowerCase(); let n=cur; while(n&&n.tag!==tag&&n!==root) n=n.parent; if(n&&n!==root) cur=n.parent||root; continue; }
      const selfClose=inside.endsWith('/'); if(selfClose) inside=inside.slice(0,-1);
      const m=inside.match(/^([a-zA-Z][\w-]*)([\s\S]*)$/); if(!m) continue;
      const tag=m[1].toLowerCase(); cur=impliedClose(cur, tag, root); const attrs={};
      const attrRe=/([\w-]+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+)))?/g; let am;
      while((am=attrRe.exec(m[2]))!==null){ attrs[am[1].toLowerCase()]=decodeEntities(am[2]??am[3]??am[4]??''); }
      const node={type:'element',tag,attrs,children:[],parent:cur,_depth:(cur._depth||0)+1}; cur.children.push(node);
      if(!VOID.has(tag)&&!selfClose&&node._depth<MAX_HTML_DEPTH) cur=node;
      if(tag==='script'||tag==='style'){ const close=s.toLowerCase().indexOf('</'+tag,i); const txt=close<0?s.slice(i):s.slice(i,close); node.children.push({type:'text',text:txt,parent:node}); i=close<0?s.length:close; }
      continue;
    }
    const lt=s.indexOf('<',i); const txt=s.slice(i, lt<0?s.length:lt); i=lt<0?s.length:lt;
    if(txt) cur.children.push({type:'text',text:decodeEntities(txt),parent:cur});
  }
  return root;
}
// Reason for iterative traversals: textOf/htmlOf/allElements used to be
// recursive, so tree DEPTH was bounded by the JS call stack. Malformed
// pages nest thousands deep even with implied closing fixed (e.g. pages
// of unclosed <div>); an explicit work stack keeps depth heap-bound.
function textOf(node){
  if(!node) return ''; if(node.type==='text') return node.text||'';
  let out=''; const stack=[node];
  while(stack.length){ const n=stack.pop(); if(n.type==='text'){ out+=n.text||''; continue; } const ch=n.children||[]; for(let i=ch.length-1;i>=0;i--) stack.push(ch[i]); }
  return out;
}
function htmlOf(node){
  if(!node) return ''; if(node.type==='text') return node.text||'';
  let out=''; const stack=[{n:node}];
  while(stack.length){
    const f=stack.pop();
    if(f.closeTag){ out+='</'+f.closeTag+'>'; continue; }
    const n=f.n;
    if(n.type==='text'){ out+=n.text||''; continue; }
    if(n.tag==='#root'){ const ch=n.children||[]; for(let i=ch.length-1;i>=0;i--) stack.push({n:ch[i]}); continue; }
    const attrs=Object.entries(n.attrs||{}).map(([k,v])=>` ${k}="${String(v).replace(/"/g,'&quot;')}"`).join('');
    if(VOID.has(n.tag)){ out+=`<${n.tag}${attrs}>`; continue; }
    out+=`<${n.tag}${attrs}>`; stack.push({closeTag:n.tag});
    const ch=n.children||[]; for(let i=ch.length-1;i>=0;i--) stack.push({n:ch[i]});
  }
  return out;
}
function allElements(root){
  const out=[]; if(!root) return out;
  const stack=[root];
  while(stack.length){ const n=stack.pop(); if(n!==root&&n.type==='element') out.push(n); const ch=n.children||[]; for(let i=ch.length-1;i>=0;i--) stack.push(ch[i]); }
  return out;
}

module.exports.MAX_HTML_DEPTH = MAX_HTML_DEPTH;
module.exports.parseHtml = parseHtml;
module.exports.textOf = textOf;
module.exports.htmlOf = htmlOf;
module.exports.allElements = allElements;

});
__define('src/parser/JSONPathParser.js', function(module, exports, __require){
// JSONPath subset: $.a.b[0], $.a[*], $..name, $.list[*].title, plain $.data
function jsonPath(data, path){
  if(!path||path==='$') return data;
  let p=String(path).trim(); if(p.startsWith('$')) p=p.slice(1);
  let current=[data];
  // Scanner tokenizer. The old regex could never emit a deep token:
  // for '$..name' it matched '.name' as a plain key, so recursive
  // descent silently degraded to a same-level lookup (real rules
  // like '$.author..name' and '$..txt_addr' depend on true descent).
  // A bare first segment ('results.list[*]', no leading '$') is a
  // root-relative key and is read the same way.
  const tokens=[];
  let i=0;
  const readName=()=>{ const m=/^[\w$-]+/.exec(p.slice(i)); if(m){ i+=m[0].length; return m[0]; } return null; };
  while(i<p.length){
    if(p.startsWith('..', i)){ i+=2; const name=readName(); if(name!=null) tokens.push({t:'deep',v:name}); }
    else if(p[i]==='.'){ i+=1; const name=readName(); if(name!=null) tokens.push({t:'key',v:name}); }
    else if(p[i]==='['){
      const close=p.indexOf(']', i); if(close<0) break;
      const inner=p.slice(i+1, close).trim(); i=close+1;
      if(inner==='*') tokens.push({t:'wildcard'});
      else if(/^\d+$/.test(inner)) tokens.push({t:'index',v:+inner});
      else { const q=/^'(.*)'$/.exec(inner)||/^"(.*)"$/.exec(inner); tokens.push({t:'key',v:q?q[1]:inner}); }
    }
    else { const name=readName(); if(name!=null) tokens.push({t:'key',v:name}); else i+=1; }
  }
  for(const tok of tokens){
    const next=[];
    for(const item of current){
      if(tok.t==='key'){ if(item&&typeof item==='object'&&tok.v in item) next.push(item[tok.v]); }
      else if(tok.t==='index'){ if(Array.isArray(item)&&item[tok.v]!==undefined) next.push(item[tok.v]); }
      else if(tok.t==='wildcard'){ const vals=Array.isArray(item)?item:(item&&typeof item==='object'?Object.values(item):[]); for(const v of vals) next.push(v); } // loop-push: spread overflows small stacks on wide arrays
      else if(tok.t==='deep'){ collectDeep(item,tok.v,next); }
    }
    current=next;
  }
  return current.length<=1? current[0] : current;
}
function collectDeep(obj,key,out){ if(!obj||typeof obj!=='object') return; if(key in obj) out.push(obj[key]); for(const v of Object.values(obj)) collectDeep(v,key,out); }
function jsonPathAll(data,path){ const r=jsonPath(data,path); return Array.isArray(r)?r:(r===undefined?[]:[r]); }

module.exports.jsonPath = jsonPath;
module.exports.jsonPathAll = jsonPathAll;

});
__define('src/parser/JSParser.js', function(module, exports, __require){
const { CryptoJS, createSymmetricCrypto, digestBytes, hmacBytes, toBytes, fromBytes, normalizeAlgoName, bytesToHex, hexToBytes, bytesToBase64, base64ToBytes } = __require('./CryptoLite.js');
const { resolveUrl, base64EncodeStr, base64DecodeStr, decodeEntities, utf8Encode, utf8Decode } = __require('../core/utils.js');
const { decodeGbk, encodeGbk, isGbkCharset } = __require('../core/gbk.js');
const { NovelError, ERR } = __require('../core/errors.js');
// JS rule evaluation for Legado-style sources.
//
// Evaluator: the default evaluator uses `new Function` with an explicit
// scope (result, java, source, book, chapter, baseUrl, key, page, cookie,
// cache, CryptoJS). A host may replace it via engine.setJsEvaluator(fn)
// (which forwards to setJsEvaluator below): fn(code, scope, lib) => value
// receives the raw rule code, the scope object and the source's jsLib, and
// its return value is used verbatim. setJsEvaluator(null) restores the
// default. The evaluator is process-wide (it models the host's JS engine),
// so the last registration wins.
//
// NON-STRICT execution: Legado runs source JS on Rhino (non-strict) and
// real-world sources assign to undeclared variables, read undeclared
// globals, etc. The wrappers below therefore deliberately omit
// "use strict" — Function-constructed bodies are non-strict unless they
// opt in. Trade-off: rule code gets sloppy-mode semantics (matching the
// original platform) instead of strict-mode safety.
//
// Single execution: the wrapper shape (expression vs statements, with or
// without the jsLib prefix) is chosen by COMPILING candidates first —
// `new Function` parses without running user code. The first candidate
// that compiles is executed exactly once; runtime errors propagate.
// (The previous implementation executed up to 5 times, duplicating side
// effects such as java.put / java.ajax calls.)
//
// Loop guard: with the default evaluator and a non-zero jsTimeoutMs
// (default 5000), while/for/do loop bodies get a __guard() call injected
// by a string/comment/template/regex-aware scanner; the guard throws
// E_TIMEOUT once the deadline passes, so a while(true){} rule cannot hang
// the host forever. Limitations: loops without a braced body are not
// instrumented, and a custom evaluator makes the timeout the host's
// responsibility. setJsTimeoutMs(0) disables the guard.
//
// java.ajax/get/post/ajaxAll are SYNCHRONOUS (Legado semantics — rule JS
// is sync and expects the response string, not a Promise). Resolution
// order: (1) the adapter's literal-URL prefetch cache (responses fetched
// asynchronously up front by SourceAdapter._ensureAjaxPrefetch), (2) a
// synchronous host transport — engine option `requestSync` or the
// QuickJS host global `novelHostRequestSync(url, optionsJson)`. When
// neither channel can serve a call it reports feature 'java.ajax-sync'
// (resp. java.get-sync / java.post-sync) through onUnsupported and
// returns an empty result — never a Promise masquerading as a string.
//
// WARNING: only run JS from sources the user installed — same trust model as Legado.

// ---------- evaluator / timeout configuration (process-wide) ----------
let _customEvaluator = null;
let _jsTimeoutMs = 5000;
function setJsEvaluator(fn) { _customEvaluator = typeof fn === 'function' ? fn : null; }
function getJsEvaluator() { return _customEvaluator; }
function setJsTimeoutMs(ms) { const n = Number(ms); if (Number.isFinite(n) && n >= 0) _jsTimeoutMs = n; }
function getJsTimeoutMs() { return _jsTimeoutMs; }

// ---------- scope plumbing ----------
const SCOPE_NAMES = ['result', 'java', 'source', 'book', 'chapter', 'baseUrl', 'key', 'page', 'cookie', 'cache', 'CryptoJS'];
function scopeVals(scope) { return SCOPE_NAMES.map(n => n === 'CryptoJS' ? (scope[n] || CryptoJS) : scope[n]); }

// ---------- loop guard ----------
function makeGuard(timeoutMs) {
  const deadline = Date.now() + timeoutMs; let n = 0;
  return function __guard() { if ((++n & 1023) === 0 && Date.now() > deadline) { const e = new Error('JS rule execution timed out after ' + timeoutMs + 'ms'); e.code = 'E_TIMEOUT'; throw e; } };
}
const REGEX_OK_KEYWORDS = new Set(['return', 'typeof', 'case', 'in', 'of', 'new', 'delete', 'void', 'instanceof', 'do', 'else', 'yield', 'await', 'throw']);
function skipWsAndComments(s, i) {
  const n = s.length;
  while (i < n) {
    const c = s[i];
    if (c === ' ' || c === '\t' || c === '\n' || c === '\r' || c === '\f' || c === '\v') { i++; continue; }
    if (c === '/' && s[i + 1] === '/') { const j = s.indexOf('\n', i); i = j < 0 ? n : j; continue; }
    if (c === '/' && s[i + 1] === '*') { const j = s.indexOf('*/', i + 2); i = j < 0 ? n : j + 2; continue; }
    break;
  }
  return i;
}
// Index just past the string/comment/template starting at i (s[i] is the
// opener), or -1 when unterminated.
function skipLiteral(s, i) {
  const n = s.length; const c = s[i];
  if (c === "'" || c === '"') { let j = i + 1; while (j < n) { if (s[j] === '\\') { j += 2; continue; } if (s[j] === c) return j + 1; if (s[j] === '\n') return -1; j++; } return -1; }
  if (c === '`') { let j = i + 1, depth = 0; while (j < n) { const ch = s[j]; if (ch === '\\') { j += 2; continue; } if (ch === '`' && depth === 0) return j + 1; if (ch === '$' && s[j + 1] === '{') { depth++; j += 2; continue; } if (ch === '}' && depth > 0) { depth--; j++; continue; } j++; } return -1; }
  if (c === '/') {
    if (s[i + 1] === '/') { const j = s.indexOf('\n', i); return j < 0 ? n : j; }
    if (s[i + 1] === '*') { const j = s.indexOf('*/', i + 2); return j < 0 ? n : j + 2; }
    let j = i + 1, inClass = false;
    while (j < n) { const ch = s[j]; if (ch === '\\') { j += 2; continue; } if (ch === '\n') return -1; if (ch === '[') inClass = true; else if (ch === ']') inClass = false; else if (ch === '/' && !inClass) { j++; while (j < n && /[a-z]/i.test(s[j])) j++; return j; } j++; }
    return -1;
  }
  return -1;
}
// Index of the ')' matching the '(' at i, skipping literals/comments.
function matchParen(s, i) {
  const n = s.length; let depth = 0, j = i;
  while (j < n) {
    const c = s[j];
    if (c === "'" || c === '"' || c === '`') { const e = skipLiteral(s, j); if (e < 0) return -1; j = e; continue; }
    if (c === '/' && (s[j + 1] === '/' || s[j + 1] === '*')) { const e = skipLiteral(s, j); if (e < 0) return -1; j = e; continue; }
    if (c === '(') depth++;
    else if (c === ')') { depth--; if (depth === 0) return j; }
    j++;
  }
  return -1;
}
// Master switch for loop instrumentation (default on). Hosts disable it
// when they enforce their own watchdog, or pass {enabled} per call.
let _loopGuardEnabled = true;
function setLoopGuardEnabled(on) { _loopGuardEnabled = !!on; }
function isLoopGuardEnabled() { return _loopGuardEnabled; }
// Insert `__guard();` at the start of every braced while/for/do loop body.
// Conservative scanner: strings, comments, template literals and regex
// literals are copied verbatim; loops without a braced body are skipped.
function injectLoopGuards(src, opts) {
  // Reason for the opt-out: a host with its own watchdog (or a test that
  // pins the exact source) can turn instrumentation off; text that merely
  // looks like a loop keyword inside strings, regexes, template literals
  // or comments is never rewritten (the scanner copies those verbatim).
  if ((opts && opts.enabled === false) || (!_loopGuardEnabled && !(opts && opts.enabled === true))) return String(src);
  const s = String(src); const n = s.length;
  let out = '', i = 0, prevCat = '', prevChar = '';
  const isIdStart = (c) => /[A-Za-z_$]/.test(c);
  const isIdChar = (c) => /[A-Za-z0-9_$]/.test(c);
  while (i < n) {
    const c = s[i];
    if (c === '/' && (s[i + 1] === '/' || s[i + 1] === '*')) { const e = skipLiteral(s, i); const end = e < 0 ? n : e; out += s.slice(i, end); i = end; continue; }
    if (c === "'" || c === '"' || c === '`') { const e = skipLiteral(s, i); const end = e < 0 ? n : e; out += s.slice(i, end); i = end; prevCat = 'val'; prevChar = c; continue; }
    if (c === '/' && (prevCat === '' || prevCat === 'op' || prevCat === 'kw')) { const e = skipLiteral(s, i); if (e > 0) { out += s.slice(i, e); i = e; prevCat = 'val'; prevChar = '/'; continue; } }
    if (isIdStart(c)) {
      let j = i + 1; while (j < n && isIdChar(s[j])) j++;
      const word = s.slice(i, j);
      if ((word === 'while' || word === 'for' || word === 'do') && prevChar !== '.') {
        if (word === 'do') {
          const k = skipWsAndComments(s, j);
          if (s[k] === '{') { out += s.slice(i, k + 1) + '__guard();'; i = k + 1; prevCat = 'op'; prevChar = '{'; continue; }
        } else {
          const k = skipWsAndComments(s, j);
          if (s[k] === '(') {
            const close = matchParen(s, k);
            if (close > 0) { const m = skipWsAndComments(s, close + 1); if (s[m] === '{') { out += s.slice(i, m + 1) + '__guard();'; i = m + 1; prevCat = 'op'; prevChar = '{'; continue; } }
          }
        }
      }
      out += word; i = j; prevCat = REGEX_OK_KEYWORDS.has(word) ? 'kw' : 'val'; prevChar = word[word.length - 1]; continue;
    }
    out += c;
    if (!/\s/.test(c)) { prevChar = c; prevCat = /[0-9]/.test(c) || c === ')' || c === ']' || c === '}' ? 'val' : 'op'; }
    i++;
  }
  return out;
}

// ---------- compile-probe, single-run evaluation ----------
function runCompiled(code, scope, lib, builders) {
  const guardOn = _jsTimeoutMs > 0;
  const srcCode = guardOn ? injectLoopGuards(code) : String(code);
  const srcLib = lib ? (guardOn ? injectLoopGuards(String(lib)) : String(lib)) : '';
  const prefix = srcLib ? srcLib + '\n;' : '';
  const names = guardOn ? [...SCOPE_NAMES, '__guard'] : SCOPE_NAMES;
  const vals = scopeVals(scope); if (guardOn) vals.push(makeGuard(_jsTimeoutMs));
  let fn = null, firstErr = null;
  for (const build of builders) {
    try { fn = new Function(...names, build(srcCode, prefix)); break; }
    catch (e) { if (!firstErr) firstErr = e; }
  }
  if (!fn) throw firstErr || new Error('JS rule could not be compiled');
  return fn(...vals);
}
function evalJs(code, scope = {}) {
  if (_customEvaluator) return _customEvaluator(code, scope, '');
  return runCompiled(code, scope, '', [(c) => c + '\n;return typeof result!=="undefined"?result:undefined;']);
}
function evalJsExpression(code, scope = {}) { // for @js: blocks that are expressions / statements returning value via last expr
  const t0 = Date.now();
  try {
    let v;
    if (_customEvaluator) v = _customEvaluator(code, scope, '');
    else {
      try {
        v = runCompiled(code, scope, '', [
          (c) => 'var __v=(function(){return eval(' + JSON.stringify(c) + ');})(); return __v!==undefined?__v:(typeof result!=="undefined"?result:undefined);',
          (c) => 'return (' + c + '\n);',
        ]);
      } catch (e2) {
        if (!(e2 instanceof SyntaxError)) throw e2;
        v = runCompiled(code, scope, '', [
          (c) => c + '\n;return typeof result!=="undefined"?result:undefined;',
        ]);
      }
    }
    traceJsEval(scope, code, t0, v, null); return v;
  } catch (e) { traceJsEval(scope, code, t0, undefined, e); throw e; }
}
// Debug tracing for JS evaluation: the trace callback rides in the scope as
// scope.__trace (set by LegadoContext.scope()). Absent => zero overhead.
// Traced once per public evaluation, on success AND on the throw path, so a
// broken @js rule shows its original error text in the trace (the collector
// truncates error text to 1000 chars).
function traceJsEval(scope, code, t0, value, error) {
  const t = scope && scope.__trace; if (typeof t !== 'function') return;
  try { t('js', { rule: String(code == null ? '' : code), outputSummary: error ? undefined : value, durationMs: Date.now() - t0, error: error || undefined }); } catch (e) { /* tracing must never break evaluation */ }
}
// Evaluate @js code: jsLib runs first (statements), then code as expression if possible,
// else as statements where assignments to `result` win. Never returns the raw input by accident
// for expression-style code (IIFE etc.). Wrapper chosen by compile probe; executed exactly once.
function evalScoped(code, scope = {}, lib = '') {
  const t0 = Date.now();
  try { const v = evalScopedInner(code, scope, lib); traceJsEval(scope, code, t0, v, null); return v; }
  catch (e) { traceJsEval(scope, code, t0, undefined, e); throw e; }
}
function evalScopedInner(code, scope = {}, lib = '') {
  if (_customEvaluator) return _customEvaluator(code, scope, lib);
  // Statement scripts: the value is the script's COMPLETION value
  // (Legado/Rhino semantics) — a trailing expression statement such
  // as `JSON.stringify(out);` IS the result. Direct eval inside the
  // generated function sees the scope params and the lib prefix's
  // declarations, so this covers statement code the expression
  // wrapper cannot even parse; an undefined completion (a script
  // ending in declarations) falls back to `result`.
  try {
    return runCompiled(code, scope, lib, [
      (c, p) => p + 'var __v=(' + c + '\n); return __v!==undefined?__v:result;',
      (c, p) => p + 'var __v=(function(){return eval(' + JSON.stringify(c) + ');})(); return __v!==undefined?__v:result;',
      (c) => 'var __v=(' + c + '\n); return __v!==undefined?__v:result;',
      (c) => 'var __v=(function(){return eval(' + JSON.stringify(c) + ');})(); return __v!==undefined?__v:result;',
    ]);
  } catch (e) {
    // The one script shape eval cannot parse at all is a top-level
    // `return` (a parse-time SyntaxError, thrown before anything
    // executed — safe to retry). Rhino accepts those, and real
    // sources use them, so fall back to running the code as the
    // generated function's body, where `return` is legal and an
    // assigned `result` is the value.
    if (e instanceof SyntaxError) {
      return runCompiled(code, scope, lib, [
        (c, p) => p + c + '\n;return result;',
        (c) => c + '\n;return result;',
      ]);
    }
    throw e;
  }
}

// ---------- synchronous HTTP for java.ajax & friends ----------
// Cache key shared with SourceAdapter's prefetch writer.
function ajaxCacheKey(method, url, body) { return String(method || 'GET').toUpperCase() + ' ' + String(url || '') + (body != null ? ' ' + String(body) : ''); }
function normalizeSyncResponse(raw, url) {
  if (raw == null) return { body: '', headers: {}, status: 0, url: String(url) };
  if (typeof raw === 'string') return { body: raw, headers: {}, status: 200, url: String(url) };
  return { body: raw.body != null ? String(raw.body) : '', headers: raw.headers || {}, status: raw.status ?? raw.code ?? 200, url: raw.url || String(url) };
}
function syncTransportOf(ctx) {
  if (ctx && typeof ctx.requestSync === 'function') return ctx.requestSync;
  const g = typeof globalThis !== 'undefined' ? globalThis : null;
  if (g && typeof g.novelHostRequestSync === 'function') return g.novelHostRequestSync;
  return null;
}
function reportUnsupported(ctx, feature) {
  if (ctx && Array.isArray(ctx.logs)) ctx.logs.push({ unsupported: feature, at: Date.now() });
  if (ctx && typeof ctx.onUnsupported === 'function') { try { ctx.onUnsupported(feature); } catch (e) { /* reporting must not break rules */ } }
}
function lookupPrefetch(ctx, method, url, body) {
  const cache = ctx && ctx.prefetch; if (!cache || typeof cache.get !== 'function') return null;
  const raw = String(url);
  const tries = [raw];
  if (ctx.baseUrl) { try { const r = resolveUrl(ctx.baseUrl, raw); if (r && r !== raw) tries.push(r); } catch (e) { /* fall through with the raw url only */ } }
  for (const u of tries) { const hit = cache.get(ajaxCacheKey(method, u, body)); if (hit) return hit; }
  return null;
}
// Returns a normalized {body, headers, status, url} or null when no
// synchronous channel can serve the call.
function syncFetch(ctx, method, url, opts = {}) {
  const hit = lookupPrefetch(ctx, method, url, opts.body);
  if (hit) return hit;
  const st = syncTransportOf(ctx);
  if (st) return normalizeSyncResponse(st(String(url), { method, headers: opts.headers || {}, body: opts.body ?? null }), url);
  return null;
}
function responseFacade(res) { return { body: () => res.body, headers: () => res.headers || {}, code: () => res.status || 200, url: () => res.url }; }
function emptyFacade(url) { return responseFacade({ body: '', headers: {}, status: 0, url: String(url) }); }

// ---------- shared java helpers ----------
function formatWithPattern(fmt, date, utc) {
  const p2 = (n, l = 2) => String(n).padStart(l, '0');
  const v = utc
    ? { y: date.getUTCFullYear(), M: date.getUTCMonth() + 1, d: date.getUTCDate(), H: date.getUTCHours(), m: date.getUTCMinutes(), s: date.getUTCSeconds(), ms: date.getUTCMilliseconds() }
    : { y: date.getFullYear(), M: date.getMonth() + 1, d: date.getDate(), H: date.getHours(), m: date.getMinutes(), s: date.getSeconds(), ms: date.getMilliseconds() };
  const map = { yyyy: String(v.y).padStart(4, '0'), MM: p2(v.M), dd: p2(v.d), HH: p2(v.H), mm: p2(v.m), ss: p2(v.s), SSS: p2(v.ms, 3) };
  return String(fmt).replace(/yyyy|SSS|MM|dd|HH|mm|ss/g, (t) => map[t]);
}
// Legado timeFormat accepts (time), (time, format) and (format, time);
// the format defaults to 'yyyy-MM-dd HH:mm:ss' in the default zone
// (SimpleDateFormat semantics in the original).
function parseTimeArgs(a, b) {
  let fmt = 'yyyy-MM-dd HH:mm:ss', time = a;
  const isTimeLike = (v) => typeof v === 'number' || v instanceof Date || (typeof v === 'string' && /^-?\d+$/.test(v.trim()));
  if (b !== undefined) {
    if (isTimeLike(a) && typeof b === 'string') { time = a; fmt = b; }
    else if (typeof a === 'string' && isTimeLike(b)) { fmt = a; time = b; }
  }
  return { fmt, time };
}
function toDate(time) {
  if (time instanceof Date) return time;
  if (typeof time === 'string' && /^-?\d+$/.test(time.trim())) return new Date(Number(time));
  return new Date(time);
}
function timeFormatValue(a, b) { const { fmt, time } = parseTimeArgs(a, b); const d = toDate(time); return isNaN(d.getTime()) ? '' : formatWithPattern(fmt, d, false); }
function timeFormatUtcValue(a, b, offsetHours) {
  const { fmt, time } = parseTimeArgs(a, b); const d = toDate(time); if (isNaN(d.getTime())) return '';
  const off = typeof offsetHours === 'number' ? offsetHours : (typeof b === 'number' ? b : 0);
  return formatWithPattern(fmt, new Date(d.getTime() + off * 3600000), true);
}

// ---------- charset-aware helpers for java.* encode methods ----------
// GBK goes through the built-in codec; other charsets fall back to UTF-8
// (documented gap: arbitrary Java charsets such as Big5 need a host).
function strToBytesWithCharset(str, charset) {
  const cs = charset || 'utf-8';
  if (isGbkCharset(cs)) return Uint8Array.from(encodeGbk(String(str == null ? '' : str)));
  return toBytes(String(str == null ? '' : str), 'utf8');
}
function bytesToStrWithCharset(bytes, charset) {
  const arr = bytes instanceof Uint8Array ? bytes : Uint8Array.from(bytes || []);
  const cs = charset || 'utf-8';
  if (isGbkCharset(cs)) return decodeGbk(arr);
  return utf8Decode(Array.from(arr));
}
// Java URLEncoder semantics: [A-Za-z0-9.-*_] stay, space becomes '+',
// everything else is %XX of the charset bytes.
function urlEncodeBytes(bytes) {
  let out = '';
  for (const b of bytes) { const c = String.fromCharCode(b); if (/[A-Za-z0-9.\-*_]/.test(c)) out += c; else if (b === 0x20) out += '+'; else out += '%' + ('0' + b.toString(16)).slice(-2).toUpperCase(); }
  return out;
}
function urlDecodeToBytes(str) {
  const s = String(str == null ? '' : str); const out = [];
  for (let i = 0; i < s.length; i++) {
    const c = s[i];
    if (c === '+') out.push(0x20);
    else if (c === '%' && /^[0-9a-fA-F]{2}$/.test(s.substr(i + 1, 2))) { out.push(parseInt(s.substr(i + 1, 2), 16)); i += 2; }
    else for (const b of utf8Encode(c)) out.push(b);
  }
  return Uint8Array.from(out);
}
function randomUuidValue() {
  const bytes = new Uint8Array(16);
  const c = typeof globalThis !== 'undefined' ? globalThis.crypto : null;
  if (c && typeof c.getRandomValues === 'function') c.getRandomValues(bytes);
  else for (let i = 0; i < 16; i++) bytes[i] = Math.floor(Math.random() * 256);
  bytes[6] = (bytes[6] & 0x0f) | 0x40; bytes[8] = (bytes[8] & 0x3f) | 0x80;
  const h = bytesToHex(bytes);
  return h.slice(0, 8) + '-' + h.slice(8, 12) + '-' + h.slice(12, 16) + '-' + h.slice(16, 20) + '-' + h.slice(20);
}
// Legado HtmlFormatter.format: block-level closers and <br> become line
// breaks, remaining tags are stripped, entities decoded.
function htmlFormatValue(html) {
  let s = String(html == null ? '' : html);
  s = s.replace(/<script[\s\S]*?<\/script>/gi, '').replace(/<style[\s\S]*?<\/style>/gi, '');
  s = s.replace(/<br\s*\/?>/gi, '\n').replace(/<\/(p|div|li|tr|table|h[1-6]|blockquote)>/gi, '\n');
  s = s.replace(/<[^>]+>/g, '');
  s = decodeEntities(s);
  return s.replace(/[ \t]+\n/g, '\n').replace(/\n{3,}/g, '\n\n').trim();
}

// ---------- java shims ----------
function createJavaShim(ctx = {}) { if (ctx && (ctx.evalElements || ctx.cookieJar || ctx.logs)) return createJavaShimFull(ctx);
  return {
    log: (...a) => { (ctx.logger || console).log?.('[source-js]', ...a); },
    ajax: (url) => { const r = syncFetch(ctx, 'GET', url); if (r) return r.body; reportUnsupported(ctx, 'java.ajax-sync'); return ''; },
    ajaxAll: (urls) => ajaxAllSync(ctx, urls),
    get: (url, headers) => { const r = syncFetch(ctx, 'GET', url, { headers }); if (r) return responseFacade(r); reportUnsupported(ctx, 'java.get-sync'); return emptyFacade(url); },
    post: (url, body, headers) => { const r = syncFetch(ctx, 'POST', url, { body, headers }); if (r) return responseFacade(r); reportUnsupported(ctx, 'java.post-sync'); return emptyFacade(url); },
    getString: (rule) => ctx.evalRule ? ctx.evalRule(rule) : '',
    md5: (s) => md5(String(s)),
    md5Encode16: (s) => md5(String(s)).slice(8, 24),
    base64Encode: (s) => base64EncodeStr(String(s)),
    base64Decode: (s) => base64DecodeStr(String(s)),
    base64DecodeToByteArray: (s) => base64ToBytes(String(s || '')),
    hexEncodeToString: (str, charset) => bytesToHex(strToBytesWithCharset(str, charset)),
    hexDecodeToString: (str, charset) => bytesToStrWithCharset(hexToBytes(String(str || '').trim()), charset),
    strToBytes: (str, charset) => strToBytesWithCharset(str, charset),
    bytesToStr: (bytes, charset) => bytesToStrWithCharset(bytes, charset),
    utf8ToGbk: (str, charset) => urlEncodeBytes(strToBytesWithCharset(str, charset || 'GBK')),
    gbkToUtf8: (str, charset) => bytesToStrWithCharset(urlDecodeToBytes(str), charset || 'GBK'),
    randomUUID: () => randomUuidValue(),
    htmlFormat: (str) => htmlFormatValue(str),
    timeFormat: (a, b) => timeFormatValue(a, b),
    t2s: (s) => { reportUnsupported(ctx, 'java.t2s'); return String(s); },
    s2t: (s) => { reportUnsupported(ctx, 'java.s2t'); return String(s); },
    put: (k, v) => { ctx.vars[k] = v; }, get: (k) => ctx.vars[k],
    getCookie: (u) => ctx.cookieJar ? ctx.cookieJar.getCookieHeader(u) : '',
  };
}
function ajaxAllSync(ctx, urls) {
  const out = []; let reported = false;
  for (const u of [].concat(urls || [])) {
    const r = syncFetch(ctx, 'GET', u);
    if (r) out.push({ body: r.body, url: r.url, headers: r.headers || {}, status: r.status || 200 });
    else { if (!reported) { reportUnsupported(ctx, 'java.ajax-sync'); reported = true; } out.push({ body: '', url: String(u), headers: {}, status: 0, error: true }); }
  }
  return out;
}
function createJavaShimFull(ctx) {
  const logs = ctx.logs || []; const unsupported = (name) => { reportUnsupported(ctx, name); return ''; };
  const enc = (str) => base64EncodeStr(String(str));
  const dec = (str) => base64DecodeStr(String(str));
  return {
    log: (...a) => { logs.push(a.map(String).join(' ')); (ctx.logger || console).log?.('[source-js]', ...a); return a.map(String).join(' '); },
    toast: (msg) => { logs.push({ toast: String(msg) }); return ''; },
    ajax: (url) => { const r = syncFetch(ctx, 'GET', url); if (r) return r.body; return unsupported('java.ajax-sync'); },
    ajaxAll: (urls) => ajaxAllSync(ctx, urls),
    get: (url, headers) => { const r = syncFetch(ctx, 'GET', url, { headers }); if (r) return responseFacade(r); unsupported('java.get-sync'); return emptyFacade(url); },
    post: (url, body, headers) => { const r = syncFetch(ctx, 'POST', url, { body, headers }); if (r) return responseFacade(r); unsupported('java.post-sync'); return emptyFacade(url); },
    getString: (rule, isUrl) => ctx.evalRule ? ctx.evalRule(rule) : '',
    getElements: (rule) => ctx.evalElements ? ctx.evalElements(rule) : [],
    getElement: (rule) => { const els = ctx.evalElements ? ctx.evalElements(rule) : []; return els[0] || null; },
    md5Encode: (s) => md5(String(s)), md5: (s) => md5(String(s)), md5Encode16: (s) => md5(String(s)).slice(8, 24),
    base64Encode: (s) => enc(s), base64Decode: (s) => dec(s),
    base64DecodeToByteArray: (s) => base64ToBytes(String(s || '')),
    hexEncodeToString: (str, charset) => bytesToHex(strToBytesWithCharset(str, charset)),
    hexDecodeToString: (str, charset) => bytesToStrWithCharset(hexToBytes(String(str || '').trim()), charset),
    strToBytes: (str, charset) => strToBytesWithCharset(str, charset),
    bytesToStr: (bytes, charset) => bytesToStrWithCharset(bytes, charset),
    utf8ToGbk: (str, charset) => urlEncodeBytes(strToBytesWithCharset(str, charset || 'GBK')),
    gbkToUtf8: (str, charset) => bytesToStrWithCharset(urlDecodeToBytes(str), charset || 'GBK'),
    randomUUID: () => randomUuidValue(),
    htmlFormat: (str) => htmlFormatValue(str),
    // Legado asks the user for a code on device; a headless runtime cannot,
    // so a host hook (ctx.getVerificationCode) wins, else report + ''.
    getVerificationCode: (prompt) => { if (typeof ctx.getVerificationCode === 'function') { try { return String(ctx.getVerificationCode(prompt) || ''); } catch (e) { /* fall through to unsupported */ } } return unsupported('java.getVerificationCode'); },
    queryTtf: (str) => unsupported('java.queryTtf'),
    // Font replacement rewrites book bytes: never fake it silently.
    replaceFont: (content, name, folder) => { reportUnsupported(ctx, 'java.replaceFont'); throw new NovelError(ERR.UNSUPPORTED, 'java.replaceFont: font replacement is not supported by this runtime'); },
    encodeURI: (s) => encodeURIComponent(String(s)), decodeURI: (s) => decodeURIComponent(String(s)),
    encodeURIComponent: (s) => encodeURIComponent(String(s)),
    timeFormat: (a, b) => timeFormatValue(a, b), timeFormatUTC: (a, b, off) => timeFormatUtcValue(a, b, off),
    put: (k, v) => { ctx.vars[k] = v; }, get: (k) => ctx.vars[k],
    getCookie: (u) => ctx.cookieJar ? ctx.cookieJar.getCookieHeader(u || ctx.baseUrl || '') : '',
    removeCookie: (u) => { if (ctx.cookieJar) ctx.cookieJar.clear(u || ctx.baseUrl || ''); return ''; },
    getLoginInfoMap: () => ctx.loginInfo || {}, getLoginInfo: () => ctx.loginInfo ? JSON.stringify(ctx.loginInfo) : null,
    getLoginHeaderMap: () => ctx.loginHeaders || {}, getLoginHeader: () => ctx.loginHeaders ? JSON.stringify(ctx.loginHeaders) : '',
    setContent: (html) => { if (ctx.setContent) ctx.setContent(html); return ''; },
    webView: () => unsupported('java.webView'), webViewGetSource: () => unsupported('java.webViewGetSource'),
    startBrowserAwait: () => unsupported('java.startBrowserAwait'), startBrowser: () => unsupported('java.startBrowser'),
    reGetBook: () => unsupported('java.reGetBook'), refreshTocUrl: () => unsupported('java.refreshTocUrl'),
    t2s: (s) => { reportUnsupported(ctx, 'java.t2s'); return String(s); },
    s2t: (s) => { reportUnsupported(ctx, 'java.s2t'); return String(s); },
    // Legado originals (JsEncodeUtils): digestHex(data, algorithm),
    // HMacHex(data, algorithm, key). The (algorithm, data) order seen in some
    // sources is also accepted when arg 1 names an algorithm.
    digestHex: (a, b) => { const { data, algorithm } = digestArgs(a, b); try { return fromBytes(digestBytes(algorithm, toBytes(data)), 'hex'); } catch (e) { return unsupported('java.digestHex:' + algorithm); } },
    digestBase64Str: (a, b) => { const { data, algorithm } = digestArgs(a, b); try { return fromBytes(digestBytes(algorithm, toBytes(data)), 'base64'); } catch (e) { return unsupported('java.digestBase64Str:' + algorithm); } },
    HMacHex: (data, algorithm, key) => { try { return fromBytes(hmacBytes(algorithm, toBytes(key), toBytes(data)), 'hex'); } catch (e) { return unsupported('java.HMacHex:' + algorithm); } },
    HMacBase64: (data, algorithm, key) => { try { return fromBytes(hmacBytes(algorithm, toBytes(key), toBytes(data)), 'base64'); } catch (e) { return unsupported('java.HMacBase64:' + algorithm); } },
    createSymmetricCrypto: (transformation, key, iv) => createSymmetricCrypto(transformation, key, iv),
    aesDecodeToString: (str, key, transformation, iv) => { try { return createSymmetricCrypto(transformation, key, iv).decryptStr(str); } catch (e) { return unsupported('java.aesDecodeToString'); } },
    aesBase64DecodeToString: (str, key, transformation, iv) => { try { return createSymmetricCrypto(transformation, key, iv).decryptStr(str); } catch (e) { return unsupported('java.aesBase64DecodeToString'); } },
    aesDecodeToByteArray: (str, key, transformation, iv) => { try { return createSymmetricCrypto(transformation, key, iv).decrypt(str); } catch (e) { reportUnsupported(ctx, 'java.aesDecodeToByteArray'); return new Uint8Array(0); } },
    aesEncodeToByteArray: (data, key, transformation, iv) => { try { return createSymmetricCrypto(transformation, key, iv).encrypt(data); } catch (e) { reportUnsupported(ctx, 'java.aesEncodeToByteArray'); return new Uint8Array(0); } },
    aesEncodeToBase64String: (data, key, transformation, iv) => { try { return createSymmetricCrypto(transformation, key, iv).encryptBase64(data); } catch (e) { return unsupported('java.aesEncodeToBase64String'); } },
    importScript: (path) => { unsupported('java.importScript (runtime call; literal call sites are preloaded by the adapter)'); return ''; }, cacheFile: (url) => { const r = syncFetch(ctx, 'GET', url); if (r) return r.body; return unsupported('java.cacheFile'); }, downloadFile: () => unsupported('java.downloadFile'),
    unsupportedLog: logs,
  };
}
function digestArgs(a, b) {
  const isAlgo = (v) => { const n = normalizeAlgoName(v); return n === 'md5' || n === 'sha1' || n === 'sha256'; };
  if (isAlgo(a) && !isAlgo(b)) return { algorithm: a, data: b };
  return { data: a, algorithm: b };
}

// MD5 (RFC 1321), pure JS, verified against RFC test vectors in tests.
const MD5K = [0xd76aa478, 0xe8c7b756, 0x242070db, 0xc1bdceee, 0xf57c0faf, 0x4787c62a, 0xa8304613, 0xfd469501, 0x698098d8, 0x8b44f7af, 0xffff5bb1, 0x895cd7be, 0x6b901122, 0xfd987193, 0xa679438e, 0x49b40821, 0xf61e2562, 0xc040b340, 0x265e5a51, 0xe9b6c7aa, 0xd62f105d, 0x02441453, 0xd8a1e681, 0xe7d3fbc8, 0x21e1cde6, 0xc33707d6, 0xf4d50d87, 0x455a14ed, 0xa9e3e905, 0xfcefa3f8, 0x676f02d9, 0x8d2a4c8a, 0xfffa3942, 0x8771f681, 0x6d9d6122, 0xfde5380c, 0xa4beea44, 0x4bdecfa9, 0xf6bb4b60, 0xbebfbc70, 0x289b7ec6, 0xeaa127fa, 0xd4ef3085, 0x04881d05, 0xd9d4d039, 0xe6db99e5, 0x1fa27cf8, 0xc4ac5665, 0xf4292244, 0x432aff97, 0xab9423a7, 0xfc93a039, 0x655b59c3, 0x8f0ccc92, 0xffeff47d, 0x85845dd1, 0x6fa87e4f, 0xfe2ce6e0, 0xa3014314, 0x4e0811a1, 0xf7537e82, 0xbd3af235, 0x2ad7d2bb, 0xeb86d391];
const MD5S = [7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21];
function md5(input) {
  const bin = unescape(encodeURIComponent(String(input))); const bytes = []; for (let i = 0; i < bin.length; i++) bytes.push(bin.charCodeAt(i) & 255);
  const bitLen = bytes.length * 8; bytes.push(0x80); while (bytes.length % 64 !== 56) bytes.push(0);
  let lo = bitLen >>> 0, hi = Math.floor(bitLen / 4294967296) >>> 0; for (let i = 0; i < 4; i++) { bytes.push(lo & 255); lo >>>= 8; } for (let i = 0; i < 4; i++) { bytes.push(hi & 255); hi >>>= 8; }
  let a0 = 0x67452301, b0 = 0xefcdab89, c0 = 0x98badcfe, d0 = 0x10325476;
  const rotl = (x, s) => ((x << s) | (x >>> (32 - s))) >>> 0; const add = (x, y) => (x + y) >>> 0;
  for (let off = 0; off < bytes.length; off += 64) {
    const M = []; for (let j = 0; j < 16; j++) M[j] = (bytes[off + j * 4] | (bytes[off + j * 4 + 1] << 8) | (bytes[off + j * 4 + 2] << 16) | (bytes[off + j * 4 + 3] << 24)) >>> 0;
    let A = a0, B = b0, C = c0, D = d0;
    for (let i = 0; i < 64; i++) { let F, g; if (i < 16) { F = (B & C) | (~B & D); g = i; } else if (i < 32) { F = (D & B) | (~D & C); g = (5 * i + 1) % 16; } else if (i < 48) { F = B ^ C ^ D; g = (3 * i + 5) % 16; } else { F = C ^ (B | ~D); g = (7 * i) % 16; }
      const tmp = D; D = C; C = B; B = add(B, rotl(add(add(A, F >>> 0), add(MD5K[i], M[g])), MD5S[i])); A = tmp; }
    a0 = add(a0, A); b0 = add(b0, B); c0 = add(c0, C); d0 = add(d0, D);
  }
  const hex = (n) => { let s = ''; for (let j = 0; j < 4; j++) { const byte = (n >> (j * 8)) & 255; s += ('0' + byte.toString(16)).slice(-2); } return s; };
  return hex(a0) + hex(b0) + hex(c0) + hex(d0);
}

module.exports.setJsEvaluator = setJsEvaluator;
module.exports.getJsEvaluator = getJsEvaluator;
module.exports.setJsTimeoutMs = setJsTimeoutMs;
module.exports.getJsTimeoutMs = getJsTimeoutMs;
module.exports.setLoopGuardEnabled = setLoopGuardEnabled;
module.exports.isLoopGuardEnabled = isLoopGuardEnabled;
module.exports.injectLoopGuards = injectLoopGuards;
module.exports.evalJs = evalJs;
module.exports.evalJsExpression = evalJsExpression;
module.exports.evalScoped = evalScoped;
module.exports.ajaxCacheKey = ajaxCacheKey;
module.exports.reportUnsupported = reportUnsupported;
module.exports.formatWithPattern = formatWithPattern;
module.exports.timeFormatValue = timeFormatValue;
module.exports.timeFormatUtcValue = timeFormatUtcValue;
module.exports.htmlFormatValue = htmlFormatValue;
module.exports.createJavaShim = createJavaShim;
module.exports.createJavaShimFull = createJavaShimFull;
module.exports.md5 = md5;

});
__define('src/parser/LegadoParser.js', function(module, exports, __require){
const { parseHtml, textOf, htmlOf, allElements } = __require('./HtmlParser.js');
const { queryAll } = __require('./CSSParser.js');
const { jsonPath, jsonPathAll } = __require('./JSONPathParser.js');
const { xpath } = __require('./XPathParser.js');
const { splitRule, applyReplaceRegex, resolveUrl, debugLog } = __require('../core/utils.js');
const { evalJsExpression, evalScoped, createJavaShim } = __require('./JSParser.js');

// The QuickJS host's sync-fetch suspension marker: the
// host-side novelHostRequestSync throws an Error whose
// message carries this prefix when a script's synchronous
// request has no primed response yet; the host then
// fetches for real, primes the adapter cache and replays
// the whole call. Rule-evaluation catches must rethrow it
// untouched — swallowing it would silently degrade the
// script to its no-data path and the replay would never
// happen.
function isSyncSuspension(e){
  return !!e && typeof e.message === 'string' && e.message.includes('MOYUAN_SYNC_FETCH:');
}

/**
 * Legado compatibility — SUPPORTED subset (honest scope, see docs/LEGADO_COMPAT.md):
 * - Selectors: class.name[.idx], tag.name[.idx], id.name, CSS selectors, XPath //..., JSONPath $. / @json:
 * - Extractors (after last @): text, textNodes, html, href/src/content/... attr, ownText
 * - Index suffix .0 .1 .-1 and Legado bare `text`/`href` meaning element itself (B172 lesson)
 * - Combinators inside a rule: @ chain, || fallback (top-level only, never inside @js:), && concat
 * - ##regex##replacement suffix, @js: blocks (whole-rule if prefix, suffix JS transform otherwise), <js>...</js>
 * - {{key}}/{{page}}/{{expr}} templates in URLs (in utils.renderTemplate)
 * NOT supported: Java-only classes, Rhino-specific syntax, WebView JS, login UI flows, TTS, etc.
 */
class LegadoContext{
  constructor(opts={}){ this.baseUrl=opts.baseUrl||''; this.vars=opts.vars||{}; this.request=opts.request||(async()=>({body:''})); this.requestSync=opts.requestSync||null; this.prefetch=opts.prefetch||null; this.logger=opts.logger||console; this.jsLib=opts.jsLib||''; this.source=opts.source||null; this.key=opts.key||''; this.page=opts.page||1; this.cookieJar=opts.cookieJar||null; this.loginInfo=opts.loginInfo||null; this.loginHeaders=opts.loginHeaders||null; this.logs=opts.logs||[]; this.onUnsupported=opts.onUnsupported||null; this._docOverride=null;
    // Debug tracing (optional): trace(kind, data) callback, traceStage is the
    // rule group being evaluated ('ruleSearch', 'ruleToc', ...), traceLabel
    // an optional field-level label ('ruleToc.chapterName') set by callers.
    this.trace=opts.trace||null; this.traceStage=opts.traceStage||opts.stage||'rule'; this.traceLabel=null; }
  _t(kind, data){ if(!this.trace) return; try{ this.trace(kind, data); }catch(e){ debugLog('trace callback error', e); } }
  java(result){ return createJavaShim({request:this.request, requestSync:this.requestSync, prefetch:this.prefetch, logger:this.logger, vars:this.vars, cookieJar:this.cookieJar, logs:this.logs, loginInfo:this.loginInfo, loginHeaders:this.loginHeaders, onUnsupported:this.onUnsupported, baseUrl:this.baseUrl, setContent:(html)=>{ this._docOverride=html; }, evalRule:(r)=>this.getString(result,r), evalElements:(r)=>this.getElements(result,r)}); }
  scope(result, extra={}){ const s={ result, java:this.java(result), source:this.source, book:extra.book||null, chapter:extra.chapter||null, baseUrl:this.baseUrl, key:this.key, page:this.page, cookie:this.cookieJar?this.cookieJar.getCookieHeader(this.baseUrl):'', cache:{get:(k)=>this.vars[k], put:(k,v)=>{this.vars[k]=v;}} };
    // JS evaluation tracing rides along in the scope (JSParser reads
    // scope.__trace); it is not one of the named Function parameters.
    if(this.trace) s.__trace=(kind, data)=>this._t(kind, { stage:this.traceStage, ...data });
    return s; }
  // Main entry: evaluate a Legado rule against a body (string). Returns string.
  getString(body, rule, extra={}){
    if(!this.trace || rule==null || rule==='') return this._getString(body, rule, extra);
    const t0=Date.now();
    try{ const v=this._getString(body, rule, extra); this._t('rule', { stage:this.traceStage, label:this.traceLabel||'', rule:String(rule), inputSummary:body, outputSummary:v, durationMs:Date.now()-t0 }); return v; }
    catch(e){ this._t('rule', { stage:this.traceStage, label:this.traceLabel||'', rule:String(rule), inputSummary:body, durationMs:Date.now()-t0, error:e }); throw e; }
  }
  _getString(body, rule, extra={}){
    if(rule==null||rule==='') return '';
    rule=String(rule);
    // <js>...</js> suffix
    const jsTag=rule.match(/<js>([\s\S]*?)<\/js>\s*$/);
    // @js: whole rule
    if(rule.trim().startsWith('@js:')){
      const code=rule.trim().slice(4);
      const v=evalScoped(code, this.scope(this._jsResult(body), extra), this.jsLib); return v==null?'':(typeof v==='object'?JSON.stringify(v):String(v));
    }
    // || alternatives bind LOOSER than a ## replace suffix:
    // split alternatives first and let each carry its own ##
    // (B176). The old order — splitRule on the whole rule
    // first — let the first ## swallow every later
    // alternative into the replace text: the real 22k title
    // rule 'p.style_h1@text##（[^）]*）||h1@text##…' lost its
    // h1 branch and the replace ran with a corrupted pattern.
    let value='';
    const alts=splitTopLevel(rule,'||');
    for(const alt of alts){
      const {main, replace}=splitRule(alt);
      const parts=splitTopLevel(main,'&&');
      if(parts.length>1){ value=parts.map(pp=>this._evalPart(body, pp.trim(), extra)).join(''); }
      else value=this._evalPart(body, main.trim(), extra);
      if(replace) value=applyReplaceRegex(value, replace);
      if(value) break;
    }
    if(jsTag){ const v=evalScoped(jsTag[1], this.scope(value, extra), this.jsLib); value=v==null?value:String(v); }
    // @js: suffix e.g. "class.x@text@js:result..."
    // handled inside _evalChain — see there
    return value==null?'':String(value);
  }
  // The `result` binding for JS evaluation. Android Legado hands
  // scripts a JSONObject whose toString() is the JSON text, so
  // sources routinely write JSON.parse(String(result)) at page
  // level. A plain JS object stringifies to '[object Object]' and
  // that parse explodes — so when the body is JSON text, keep the
  // parsed value for property access but give it a toString()
  // that returns the raw body text (B174 Fanqie kind/wordCount).
  _jsResult(body){
    const v=parseMaybe(body);
    if(v && typeof v==='object' && typeof body==='string'){
      try{ Object.defineProperty(v, 'toString', { value: () => body, writable: true, configurable: true, enumerable: false }); }catch(e){ /* frozen/sealed value: leave as-is */ }
    }
    return v;
  }
  // {{...}} template assembly (Legado's makeUpRule): field
  // rules freely mix literal text with {{segments}} —
  // bookUrl 'https://host/page/{{$.book_id}}' is the
  // canonical shape. A segment whose content starts with
  // '$.', '$[', '//' or '@' is a SUB-RULE evaluated against
  // the current value; anything else is a JS expression
  // evaluated with that value as `result`. '@get:{name}'
  // reads the source variable store. Without this, a
  // template rule fell through to the JSON evaluator,
  // which returned the whole element object — stringified
  // downstream to '[object Object]' and resolved against
  // the page URL (the B174 Fanqie chapters regression).
  _assembleTemplates(body, text, extra={}){
    const depth = (extra && extra.__tplDepth) || 0;
    let out=''; let i=0;
    const current = this._jsResult(body);
    while(i<text.length){
      if(text.startsWith('@get:{', i)){
        const end=text.indexOf('}', i+6);
        if(end<0){ out+=text.slice(i); break; }
        const name=text.slice(i+6, end).trim();
        out+= this.vars && this.vars[name]!=null ? String(this.vars[name]) : '';
        i=end+1; continue;
      }
      if(text.startsWith('{{', i)){
        // depth-aware scan for the matching '}}'
        let d=1, j=i+2;
        while(j<text.length && d>0){
          if(text.startsWith('{{', j)){ d++; j+=2; }
          else if(text.startsWith('}}', j)){ d--; if(d===0) break; j+=2; }
          else j++;
        }
        if(d!==0){ out+=text.slice(i); break; }
        const expr=text.slice(i+2, j).trim();
        out+=this._templateValue(body, current, expr, extra, depth);
        i=j+2; continue;
      }
      out+=text[i]; i++;
    }
    return out;
  }
  _templateValue(body, current, expr, extra, depth){
    if(!expr) return '';
    const isRule = expr.startsWith('$.') || expr.startsWith('$[') || expr.startsWith('//') || expr.startsWith('@');
    try{
      if(isRule){
        if(depth>=8) return '';
        const v=this._getString(body, expr, { ...extra, __tplDepth: depth+1 });
        return v==null?'':String(v);
      }
      const v=evalScoped(expr, this.scope(current, extra), this.jsLib);
      if(v==null) return '';
      return typeof v==='object' ? JSON.stringify(v) : String(v);
    }catch(e){
      // A sync-fetch suspension (the host primes the
      // response and replays the whole call) must never be
      // mistaken for a failed segment.
      if(isSyncSuspension(e)) throw e;
      return '';
    }
  }
  // One ||/&& part of a field rule: assemble templates
  // first; an assembled part that no longer looks like a
  // rule IS the value (a literal URL/text), one that does
  // (a path, an @js: suffix tail, …) goes through the
  // normal chain evaluator.
  _evalPart(body, part, extra={}){
    if(part.includes('{{') || part.includes('@get:{')){
      const assembled=this._assembleTemplates(body, part, extra);
      const ji=assembled.lastIndexOf('@js:');
      if(ji>0){
        const head=assembled.slice(0, ji), code=assembled.slice(ji+4);
        const headValue=this._looksLikeRule(head) ? this._evalChain(body, head, extra) : head;
        try{
          const v=evalScoped(code, this.scope(headValue, extra), this.jsLib);
          if(v!=null) return typeof v==='object' ? JSON.stringify(v) : String(v);
        }catch(e){ if(isSyncSuspension(e)) throw e; /* else fall through to the head value */ }
        return headValue;
      }
      if(!this._looksLikeRule(assembled)) return assembled;
      return this._evalChain(body, assembled, extra);
    }
    return this._evalChain(body, part, extra);
  }
  _looksLikeRule(s){
    const t=String(s||'').trim();
    return t.startsWith('$.') || t.startsWith('$[') || t.startsWith('@') || t.startsWith('//') || t.includes('<js>');
  }
  getElements(body, rule, extra={}){
    if(!this.trace || !rule) return this._getElements(body, rule, extra);
    const t0=Date.now();
    try{ const v=this._getElements(body, rule, extra); this._t('rule', { stage:this.traceStage, label:this.traceLabel||'', rule:String(rule), inputSummary:body, outputSummary:(Array.isArray(v)?v.length:0)+' elements', durationMs:Date.now()-t0 }); return v; }
    catch(e){ this._t('rule', { stage:this.traceStage, label:this.traceLabel||'', rule:String(rule), inputSummary:body, durationMs:Date.now()-t0, error:e }); throw e; }
  }
  _getElements(body, rule, extra={}){
    if(!rule) return [];
    rule=String(rule).trim();
    let reverse=false;
    if(rule.startsWith('-')){ reverse=true; rule=rule.slice(1); }
    else if(rule.startsWith('+')) rule=rule.slice(1);
    if(rule.startsWith('@js:')){ const v=evalScoped(rule.slice(4), this.scope(this._jsResult(body),extra), this.jsLib); const arr=Array.isArray(v)?v:[v].filter(Boolean); return reverse?arr.reverse():arr; }
    // List combinators at top level: && concat, %% interleave,
    // || first non-empty. Split them on the FULL rule, before
    // any ## stripping: a trailing ## on an early branch must
    // not swallow the later branches (B176, same defect as
    // _getString). Each branch re-enters and strips its own ##.
    for(const comb of ['&&','%%','||']){
      const parts=splitTopLevel(rule, comb);
      if(parts.length>1){
        const lists=parts.map(pp=>this.getElements(body, pp.trim(), extra));
        let out;
        if(comb==='&&') out=[].concat(...lists);
        else if(comb==='||') out=lists.find(l=>l.length)||[];
        else { out=[]; const max=Math.max(...lists.map(l=>l.length)); for(let i=0;i<max;i++) for(const l of lists) if(l[i]!==undefined) out.push(l[i]); }
        return reverse?out.reverse():out;
      }
    }
    const {main}=splitRule(rule);
    // JSON list
    if(isJsonBody(body)){
      const data=parseMaybe(body);
      let p=main.replace(/^@json:/,'');
      if(p.startsWith('$.')||p.startsWith('$[')||p==='$'||/^[A-Za-z_$][\w$-]*(\.|\[|$)/.test(p)){ const arr=jsonPathAll(data, p); return reverse?flattenDeep(arr).reverse():flattenDeep(arr); }
      if(p.includes('@')){ const head=p.split('@')[0]; if(head.startsWith('$.')||/^[A-Za-z_$][\w$-]*(\.|\[|$)/.test(head)){ const arr=jsonPathAll(data, head); return reverse?arr.reverse():arr; } }
      const arr=Array.isArray(data)?data:(data&&typeof data==='object'&&Array.isArray(data.data)?data.data:[]);
      return reverse?arr.slice().reverse():arr;
    }
    const doc=typeof body==='string'?parseHtml(body):body;
    // @css: prefix: the remainder is ONE jsoup-style
    // selector, not a Legado @ chain. Without this the
    // split below eats the '@' and the leftover 'css: …'
    // segment matches nothing (real-world toc/search
    // rules use this form heavily).
    if(main.trim().startsWith('@css:')){
      const found=queryAll(doc, main.trim().slice(5).trim());
      return reverse?found.reverse():found;
    }
    const steps=main.split('@').map(x=>x.trim()).filter(Boolean);
    let nodes=[doc];
    for(const step of steps){
      if(isExtractor(step)) break;
      if(step.startsWith('//')||step.startsWith('@xpath:')){ const res=xpath(doc, step.replace(/^@xpath:/,'')); nodes=Array.isArray(res)?res.filter(x=>x&&typeof x==='object'):[]; continue; }
      if(step.startsWith('text.')){ const want=step.slice(5); const found=[]; for(const n of nodes){ if(n&&n.children) for(const el of allElements(n)) if(textOf(el).trim()===want && !allElements(el).some(d=>textOf(d).trim()===want)) found.push(el); } nodes=found; continue; }
      const {selector, pick}=parseLegadoStep(step);
      const css=legadoToCss(selector);
      const found=[]; for(const n of nodes){ if(n&&n.children){ const r=queryAll(n, css); for(const el of r) found.push(el); } } // loop-push: spread of a huge result set overflows small stacks
      nodes=pick?pick(found):found;
      if(!nodes.length) break;
    }
    return reverse?nodes.reverse():nodes;
  }
  _evalChain(body, rule, extra){
    if(!rule) return '';
    // @js: suffix: split at last '@js:'
    let jsSuffix=null; const ji=rule.lastIndexOf('@js:');
    if(ji>0){ jsSuffix=rule.slice(ji+4); rule=rule.slice(0,ji); }
    let result;
    if(isJsonBody(body) || rule.startsWith('$.') || rule.startsWith('@json:')){
      const data=parseMaybe(body);
      result=this._evalJson(data, rule, extra);
    } else if(rule.startsWith('//')||rule.startsWith('@xpath:')){
      const doc=parseHtml(String(body)); const res=xpath(doc, rule.replace(/^@xpath:/,''));
      result=Array.isArray(res)? (typeof res[0]==='string'?res[0]:(res[0]?textOf(res[0]).trim():'')) : res;
    } else {
      result=this._evalHtml(body, rule, extra);
    }
    if(jsSuffix){ const v=evalScoped(jsSuffix, this.scope(result,extra), this.jsLib); result=v==null?result:v; }
    return result==null?'':String(result).trim();
  }
  _evalJson(data, rule, extra){
    const parts=rule.split('@').map(s=>s.trim());
    let cur=data;
    for(const part of parts){
      if(!part) continue;
      if(part.startsWith('$.')||part.startsWith('$[')||part==='$'||/^[A-Za-z_$][\w$-]*(\.|\[|$)/.test(part)) cur=jsonPath(cur, part);
      else if(part==='json'||part.startsWith('json:')) cur=jsonPath(cur, part.slice(part.indexOf(':')+1));
      // extractors on JSON values are no-ops (already scalar)
    }
    if(Array.isArray(cur)) cur=cur[0];
    return cur==null?'':cur;
  }
  _evalHtml(body, rule, extra){
    const doc=typeof body==='string'?parseHtml(body):body;
    // @css: prefix (see _getElements): one selector plus
    // an optional trailing @extractor.
    const trimmedRule=rule.trim();
    if(trimmedRule.startsWith('@css:')){
      let rest=trimmedRule.slice(5).trim();
      let extractor='';
      const at=rest.lastIndexOf('@');
      if(at>0 && isExtractor(rest.slice(at+1).trim())){ extractor=rest.slice(at+1).trim(); rest=rest.slice(0,at).trim(); }
      const els=queryAll(doc, rest);
      if(!els.length) return '';
      return extractor?extract(els[0], extractor):textOf(els[0]).trim();
    }
    const segs=rule.split('@');
    let nodes=[doc]; let scalar='';
    segs.forEach((seg,idx)=>{
      seg=seg.trim(); const isLast=idx===segs.length-1;
      if(isExtractor(seg)&&nodes.length){
        const el=nodes[0]; if(!el||el.tag==='#root'){ scalar=''; return; }
        scalar=extract(el, seg); return;
      }
      if(seg==='' ) return;
      if(seg.startsWith('text.')){ const want=seg.slice(5); const found=[]; for(const n of nodes) for(const el of allElements(n)) if(textOf(el).trim()===want && !allElements(el).some(d=>textOf(d).trim()===want)) found.push(el); nodes=found; if(isLast && nodes.length) scalar=textOf(nodes[0]).trim(); return; }
      const {selector, pick}=parseLegadoStep(seg);
      const css=legadoToCss(selector);
      const found=[]; for(const n of nodes){ const r=queryAll(n, css); for(const el of r) found.push(el); } // loop-push: see above
      nodes=pick?pick(found):found;
      if(isLast && nodes.length && nodes[0].tag!=='#root') scalar=textOf(nodes[0]).trim();
    });
    return scalar;
  }
}
function splitTopLevel(s, sep){
  // Split on sep not inside [], (), {}, quotes, or after @js: (caller guarantees whole-@js handled)
  const out=[]; let depth=0, q=null, cur='';
  for(let i=0;i<s.length;i++){ const c=s[i];
    if(q){ cur+=c; if(c===q) q=null; continue; }
    if(c==='"'||c==="'"){ q=c; cur+=c; continue; }
    if('([{'.includes(c)) depth++; if(')]}'.includes(c)) depth--;
    if(depth===0 && s.startsWith(sep,i)){ out.push(cur); cur=''; i+=sep.length-1; continue; }
    cur+=c;
  }
  out.push(cur); return out;
}
function isJsonBody(body){ if(typeof body!=='string') return false; const t=body.trim(); return (t.startsWith('{')||t.startsWith('[')); }
function parseMaybe(body){ if(typeof body!=='string') return body; if(isJsonBody(body)){ try{ return JSON.parse(body); }catch(e){ return body; } } return body; }
const EXTRACTORS=new Set(['text','textnodes','html','owntext','all','href','src','alt','title','content','value','data-src','data-original']);
function isExtractor(seg){ return EXTRACTORS.has(seg.toLowerCase()); }
function extract(el, seg){
  const k=seg.toLowerCase();
  if(k==='text'||k==='owntext') return textOf(el).trim();
  if(k==='textnodes') return (el.children||[]).filter(c=>c.type==='text').map(c=>c.text).join(' ').trim();
  if(k==='html'||k==='all') return htmlOf(el);
  return el.attrs?.[k]??el.attrs?.[seg]??'';
}
// Parse a Legado selector step incl. index specs:
//   class.x.0 / tag.a.-1 (single), class.x.0:3 / class.x.:3 (colon interval),
//   class.x.!1 (exclude), class.x[0,2] / class.x[0:2] (bracket list/interval)
function parseLegadoStep(seg){
  let s=seg.trim(); let pick=null;
  let m=s.match(/\[([\-0-9,:\s!]+)\]$/);
  if(m){ s=s.slice(0,m.index); pick=indexSpec('['+m[1]+']'); return {selector:s, pick}; }
  m=s.match(/\.(-?\d*):(-?\d*)$/);
  if(m && /^(class|tag|id)\./.test(s)){ s=s.slice(0,m.index); pick=indexSpec(m[1]+':'+m[2]); return {selector:s, pick}; }
  m=s.match(/\.\!(-?\d+)$/);
  if(m && /^(class|tag|id)\./.test(s)){ const ex=parseInt(m[1],10); s=s.slice(0,m.index); pick=(arr)=>arr.filter((_,i)=>{ const idx=ex<0?arr.length+ex:ex; return i!==idx; }); return {selector:s, pick}; }
  m=s.match(/\.(-?\d+)$/);
  if(m && /^(class|tag|id)\./.test(s)){ const idx=parseInt(m[1],10); s=s.slice(0,m.index); pick=(arr)=>{ const i=idx<0?arr.length+idx:idx; return arr[i]?[arr[i]]:[]; }; return {selector:s, pick}; }
  return {selector:s, pick};
}
function indexSpec(spec){
  const inner=String(spec).replace(/^\[|\]$/g,'').trim();
  if(inner.includes(':')){ const [a,b]=inner.split(':'); return (arr)=>{ let start=a===''?0:parseInt(a,10); if(start<0) start=arr.length+start; let end=b===''||b===undefined?arr.length:parseInt(b,10); if(end<0) end=arr.length+end+1; return arr.slice(start, end); }; }
  const idxs=inner.split(',').map(x=>x.trim()).filter(Boolean).map(x=>parseInt(x,10));
  return (arr)=>idxs.map(i=>arr[i<0?arr.length+i:i]).filter(x=>x!==undefined);
}
function flattenDeep(arr){ // iterative: deeply nested chapter lists must not recurse
  const out=[]; const stack=[];
  for(let i=arr.length-1;i>=0;i--) stack.push(arr[i]);
  while(stack.length){ const x=stack.pop(); if(Array.isArray(x)){ for(let i=x.length-1;i>=0;i--) stack.push(x[i]); } else out.push(x); }
  return out;
}
function legadoToCss(seg){
  if(seg.startsWith('class.')) return '.'+seg.slice(6).split('.')[0];
  if(seg.startsWith('id.')) return '#'+seg.slice(3).split('.')[0];
  if(seg.startsWith('tag.')) return seg.slice(4).split('.')[0];
  if(seg.startsWith('@css:')) return seg.slice(5);
  return seg; // assume CSS already
}
function resolveChapterUrl(base, href){ return resolveUrl(base, href); }

module.exports.isSyncSuspension = isSyncSuspension;
module.exports.LegadoContext = LegadoContext;
module.exports.isJsonBody = isJsonBody;
module.exports.parseMaybe = parseMaybe;
module.exports.parseLegadoStep = parseLegadoStep;
module.exports.indexSpec = indexSpec;
module.exports.flattenDeep = flattenDeep;
module.exports.legadoToCss = legadoToCss;
module.exports.resolveChapterUrl = resolveChapterUrl;

});
__define('src/parser/ParserEngine.js', function(module, exports, __require){
const { parseHtml, textOf, htmlOf } = __require('./HtmlParser.js');
const { queryAll } = __require('./CSSParser.js');
const { jsonPath } = __require('./JSONPathParser.js');
const { xpath } = __require('./XPathParser.js');
const { regexExtract } = __require('./RegexParser.js');
const { LegadoContext } = __require('./LegadoParser.js');

class ParserEngine{
  constructor(engine){ this.engine=engine; this.custom=new Map(); }
  registerParser(name, fn){ this.custom.set(name, fn); }
  parse(body, rule, ctxOpts={}){
    if(this.custom.has(ctxOpts.parser)) return this.custom.get(ctxOpts.parser)(body, rule, ctxOpts);
    if(rule==null) return '';
    const r=String(rule);
    if(r.startsWith('@css:')){ const doc=parseHtml(body); const els=queryAll(doc, r.slice(5)); return els[0]?textOf(els[0]).trim():''; }
    if(r.startsWith('@xpath:')){ const doc=parseHtml(body); const res=xpath(doc, r.slice(7)); return Array.isArray(res)?(typeof res[0]==='string'?res[0]:textOf(res[0]||{children:[]}).trim()):res; }
    if(r.startsWith('@json:')){ return jsonPath(JSON.parse(body), r.slice(6)); }
    if(r.startsWith('@regex:')){ return regexExtract(body, r.slice(7)); }
    const ctx=new LegadoContext({ baseUrl:ctxOpts.baseUrl, request:ctxOpts.request, source:ctxOpts.source, key:ctxOpts.key, page:ctxOpts.page, jsLib:ctxOpts.jsLib, logger:ctxOpts.logger });
    return ctx.getString(body, r, ctxOpts);
  }
  parseList(body, rule, ctxOpts={}){
    const ctx=new LegadoContext({ baseUrl:ctxOpts.baseUrl, request:ctxOpts.request, source:ctxOpts.source, key:ctxOpts.key, page:ctxOpts.page, jsLib:ctxOpts.jsLib, logger:ctxOpts.logger });
    return ctx.getElements(body, rule, ctxOpts);
  }
  // Extract a field from a list element (node or JSON object)
  fieldFromElement(el, rule, ctxOpts={}){
    if(el==null||!rule) return '';
    if(typeof el==='object' && el.type!=='element'){
      // JSON element: rule is JSONPath or plain key
      const r=String(rule); if(r.startsWith('$.')) return jsonPath(el, r)??'';
      if(el[r]!==undefined) return el[r];
      const ctx=new LegadoContext(ctxOpts); return ctx.getString(JSON.stringify(el), r, ctxOpts);
    }
    const body=htmlOf(el);
    // Re-root: Legado field rules are relative to element; our chain works from doc root of fragment — acceptable for supported selectors.
    const ctx=new LegadoContext({ baseUrl:ctxOpts.baseUrl, request:ctxOpts.request, source:ctxOpts.source, jsLib:ctxOpts.jsLib, logger:ctxOpts.logger });
    // For simple extractor-only rules (text/href) apply directly
    const rr=String(rule).trim();
    if(/^(text|href|src|html|title|content)$/i.test(rr)){ const { textOf:to, htmlOf:ho }= {textOf, htmlOf}; return rr.toLowerCase()==='text'?to(el).trim(): rr.toLowerCase()==='html'?ho(el): (el.attrs?.[rr]||el.attrs?.[rr.toLowerCase()]||''); }
    return ctx.getString(body, rr, ctxOpts);
  }
}
module.exports.default = ParserEngine;

module.exports.ParserEngine = ParserEngine;

});
__define('src/parser/RegexParser.js', function(module, exports, __require){
function regexExtract(text, pattern, group=1){
  try{ const re=pattern instanceof RegExp?pattern:new RegExp(pattern); const m=String(text||'').match(re); return m? (m[group]??m[0]??'') : ''; }catch(e){ return ''; }
}
function regexAll(text, pattern){
  try{ const re=new RegExp(pattern,'g'); const out=[]; let m; const s=String(text||''); while((m=re.exec(s))!==null) out.push(m); return out; }catch(e){ return []; }
}

module.exports.regexExtract = regexExtract;
module.exports.regexAll = regexAll;

});
__define('src/parser/XPathParser.js', function(module, exports, __require){
const { allElements, textOf } = __require('./HtmlParser.js');
// XPath subset: //tag, //tag[@attr='v'], //tag/text(), //tag/@attr, /a/b, //a//b, //*[contains(@class,'x')]
function xpath(root, expr){
  let e=String(expr||'').trim(); let attr=null; let wantText=false;
  if(e.endsWith('/text()')){ wantText=true; e=e.slice(0,-8); }
  else { const am=e.match(/\/@([\w-]+)$/); if(am){ attr=am[1]; e=e.slice(0,am.index); } }
  const steps=e.split(/\/+/).filter(Boolean);
  let current=[root];
  for(const step of steps){
    const m=step.match(/^([\w* -]+)(?:\[(.+)\])?$/); if(!m) continue;
    const tag=m[1].trim().toLowerCase(); const pred=m[2]; const next=[];
    for(const ctx of current){
      for(const el of allElements(ctx)){
        if(tag!=='*'&&el.tag!==tag) continue;
        if(pred){
          const cm=pred.match(/contains\(@([\w-]+),\s*'([^']*)'\)/);
          const em=pred.match(/@([\w-]+)\s*=\s*'([^']*)'/);
          const nm=pred.match(/^(\d+)$/);
          if(cm){ if(!String(el.attrs[cm[1]]||'').includes(cm[2])) continue; }
          else if(em){ if(el.attrs[em[1]]!==em[2]) continue; }
          else if(nm){ /* positional handled loosely: keep all, caller indexes */ }
        }
        next.push(el);
      }
    }
    current=next;
  }
  if(attr) return current.map(el=>el.attrs[attr]||'');
  if(wantText) return current.map(el=>textOf(el).trim());
  return current;
}
module.exports.textOf = textOf;

module.exports.xpath = xpath;

});
__define('src/parser/XmlLite.js', function(module, exports, __require){
// XmlLite — deliberately small, regex-level XML helpers for feed-shaped
// documents (RSS / Atom / OPDS / EPUB container+OPF). Feed XML is regular
// enough for tag-level extraction; this is NOT a general XML parser:
// no namespaces beyond prefix tolerance, no DTD, no mixed-content fidelity.
// Text fields: CDATA unwrapped, inner markup stripped, entities decoded.
const { decodeEntities } = __require('../core/utils.js');

const escRe = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

function stripCdata(text) {
  let t = String(text || '').trim();
  if (t.startsWith('<![CDATA[') && t.endsWith(']]>')) t = t.slice(9, -3);
  return t;
}
function xmlText(raw) {
  let t = stripCdata(raw);
  t = t.replace(/<[^>]+>/g, ' ');
  return decodeEntities(t).replace(/\s+/g, ' ').trim();
}
// Inner contents of every <tag ...>...</tag> block (prefix-tolerant: matches
// <dc:title> when asked for 'title' too, via local-name comparison is NOT done
// — pass the exact tag as it appears, or rely on callers passing both forms).
function xmlTagBlocks(xml, tag) {
  const out = [];
  const re = new RegExp('<' + escRe(tag) + '(\\s[^>]*)?>([\\s\\S]*?)</' + escRe(tag) + '>', 'gi');
  let m; const src = String(xml || '');
  while ((m = re.exec(src))) out.push(m[2]);
  return out;
}
function xmlTagBlocksWithAttrs(xml, tag) {
  const out = [];
  const re = new RegExp('<' + escRe(tag) + '((?:\\s[^>]*)?)>([\\s\\S]*?)</' + escRe(tag) + '>', 'gi');
  let m; const src = String(xml || '');
  while ((m = re.exec(src))) out.push({ attrs: parseAttrs(m[1] || ''), inner: m[2] });
  return out;
}
function xmlSelfTags(xml, tag) {
  const out = [];
  const re = new RegExp('<' + escRe(tag) + '((?:\\s[^>]*?)?)/?>', 'gi');
  let m; const src = String(xml || '');
  while ((m = re.exec(src))) { if (!/\/>$/.test(m[0]) && new RegExp('</' + escRe(tag) + '>', 'i').test(src.slice(m.index))) { /* paired tag start, still report attrs */ } out.push({ attrs: parseAttrs(m[1] || ''), raw: m[0] }); }
  return out;
}
function parseAttrs(attrText) {
  const out = {};
  const re = /([\w:.-]+)\s*=\s*(?:"([^"]*)"|'([^']*)')/g;
  let m; while ((m = re.exec(String(attrText || '')))) out[m[1]] = decodeEntities(m[2] !== undefined ? m[2] : m[3]);
  return out;
}
// First non-empty text among the given tags inside a block.
function xmlFieldText(block, tags) {
  for (const tag of tags) {
    const blocks = xmlTagBlocks(block, tag);
    if (blocks.length) { const t = xmlText(blocks[0]); if (t) return t; }
  }
  return '';
}
function xmlFirstTag(xml, tag) {
  const re = new RegExp('<' + escRe(tag) + '((?:\\s[^>]*)?)>([\\s\\S]*?)</' + escRe(tag) + '>', 'i');
  const m = String(xml || '').match(re);
  if (m) return { attrs: parseAttrs(m[1] || ''), inner: m[2] };
  const self = String(xml || '').match(new RegExp('<' + escRe(tag) + '((?:\\s[^>]*)?)/>', 'i'));
  if (self) return { attrs: parseAttrs(self[1] || ''), inner: '' };
  return null;
}
module.exports.default = { xmlTagBlocks, xmlTagBlocksWithAttrs, xmlSelfTags, xmlFieldText, xmlFirstTag, xmlText, stripCdata, parseAttrs };

module.exports.stripCdata = stripCdata;
module.exports.xmlText = xmlText;
module.exports.xmlTagBlocks = xmlTagBlocks;
module.exports.xmlTagBlocksWithAttrs = xmlTagBlocksWithAttrs;
module.exports.xmlSelfTags = xmlSelfTags;
module.exports.parseAttrs = parseAttrs;
module.exports.xmlFieldText = xmlFieldText;
module.exports.xmlFirstTag = xmlFirstTag;

});
__define('src/plugins/PluginManager.js', function(module, exports, __require){
const { PluginRegistry } = __require('./PluginRegistry.js');
// Plugin lifecycle with error isolation: a throwing plugin never crashes the engine;
// the failure is recorded on the entry and emitted as 'plugin:error'.
class PluginManager{
  constructor(engine){ this.engine=engine||null; this.registry=new PluginRegistry(); }
  register(plugin){
    const entry=this.registry.register(plugin);
    if(plugin.dependencies) for(const dep of plugin.dependencies) if(!this.registry.has(dep)) { entry.error=new Error('Missing dependency: '+dep); }
    this._emit('plugin:registered', {id:entry.id});
    return this.get(plugin.id);
  }
  async enable(id){
    const entry=this.registry.get(id); if(!entry) throw Object.assign(new Error('Plugin not found: '+id), {code:'E_PLUGIN'});
    for(const dep of entry.dependencies) if(!this.registry.has(dep)||!this.registry.get(dep).enabled) throw Object.assign(new Error('Dependency not enabled: '+dep), {code:'E_PLUGIN'});
    try{ if(entry.plugin.onEnable) await entry.plugin.onEnable(this._api(entry)); if(entry.plugin.install) await entry.plugin.install(this._api(entry)); entry.enabled=true; entry.error=null; }
    catch(e){ entry.error=e; entry.enabled=false; this._emit('plugin:error', {id, error:e}); throw Object.assign(new Error('Plugin enable failed: '+id+': '+(e.message||e)), {code:'E_PLUGIN', cause:e}); }
    this._emit('plugin:enabled', {id}); return this.get(id);
  }
  async disable(id){
    const entry=this.registry.get(id); if(!entry) throw Object.assign(new Error('Plugin not found: '+id), {code:'E_PLUGIN'});
    try{ if(entry.plugin.onDisable) await entry.plugin.onDisable(this._api(entry)); }catch(e){ entry.error=e; this._emit('plugin:error', {id, error:e}); }
    entry.enabled=false; this._emit('plugin:disabled', {id}); return this.get(id);
  }
  unregister(id){ const ok=this.registry.unregister(id); this._emit('plugin:unregistered', {id}); return ok; }
  get(id){ const l=this.list(); return l.find(p=>p.id===id)||null; }
  list(){ return this.registry.list(); }
  enabled(){ return this.registry.list().filter(p=>p.enabled); }
  _api(entry){
    const engine=this.engine;
    return {
      engine, pluginId: entry.id,
      capabilities: entry.capabilities,
      registerParser:(name, fn)=>{ if(!entry.capabilities.includes('parser')) throw new Error('Plugin lacks parser capability'); engine.parser.registerParser(name, fn); },
      registerSource:(source)=>{ if(!entry.capabilities.includes('source')) throw new Error('Plugin lacks source capability'); return engine.sources.register(source); },
      on:(ev, fn)=>engine.events.on(ev, fn),
      log:(...a)=>engine.events.emit('plugin:log', {id:entry.id, args:a}),
    };
  }
  // Run plugin hooks for a pipeline stage, isolating errors per plugin.
  async runHook(stage, payload){
    let current=payload; const errors=[];
    for(const meta of this.enabled()){
      const entry=this.registry.get(meta.id); const hook=entry.plugin.hooks&&entry.plugin.hooks[stage];
      if(typeof hook!=='function') continue;
      try{ const v=await hook(current, this._api(entry)); if(v!==undefined) current=v; }
      catch(e){ entry.error=e; errors.push({id:meta.id, error:e}); this._emit('plugin:error', {id:meta.id, stage, error:e}); }
    }
    return {value:current, errors};
  }
  _emit(ev, data){ if(this.engine&&this.engine.events) this.engine.events.emit(ev, data); }
}
module.exports.default = PluginManager;

module.exports.PluginManager = PluginManager;

});
__define('src/plugins/PluginRegistry.js', function(module, exports, __require){
class PluginRegistry{
  constructor(){ this._plugins=new Map(); }
  register(plugin){
    if(!plugin||!plugin.id) throw Object.assign(new Error('Plugin must have an id'), {code:'E_VALIDATION'});
    if(this._plugins.has(plugin.id)) throw Object.assign(new Error('Plugin already registered: '+plugin.id), {code:'E_PLUGIN'});
    const entry={ id:plugin.id, name:plugin.name||plugin.id, version:plugin.version||'0.0.0', description:plugin.description||'', capabilities:plugin.capabilities||[], permissions:plugin.permissions||[], dependencies:plugin.dependencies||[], plugin, enabled:false, error:null };
    this._plugins.set(plugin.id, entry); return entry;
  }
  unregister(id){ const e=this._plugins.get(id); if(e&&e.enabled) throw Object.assign(new Error('Disable plugin before unregister: '+id), {code:'E_PLUGIN'}); return this._plugins.delete(id); }
  get(id){ return this._plugins.get(id)||null; }
  list(){ return [...this._plugins.values()].map(e=>({id:e.id,name:e.name,version:e.version,description:e.description,capabilities:e.capabilities,permissions:e.permissions,dependencies:e.dependencies,enabled:e.enabled,error:e.error?String(e.error.message||e.error):null})); }
  has(id){ return this._plugins.has(id); }
}
module.exports.default = PluginRegistry;

module.exports.PluginRegistry = PluginRegistry;

});
__define('src/search/ResultDeduplicator.js', function(module, exports, __require){
const { normalizeTitle, dedupeBy } = __require('../core/utils.js');
// Dedup exact (sourceId+url) first, then merge same title+author across sources
// keeping the first (priority order) and recording merged sources in metadata.
class ResultDeduplicator{
  dedupe(results){
    const byId=dedupeBy(results, r=>r.sourceId+'\n'+r.url);
    const seen=new Map(); const out=[];
    for(const r of byId){
      const key=normalizeTitle(r.title)+'\n'+String(r.author||'').trim().toLowerCase();
      if(key.trim() && seen.has(key)){
        const kept=seen.get(key); kept.metadata=kept.metadata||{}; kept.metadata.alsoFrom=kept.metadata.alsoFrom||[]; kept.metadata.alsoFrom.push({sourceId:r.sourceId, sourceName:r.sourceName, id:r.id, url:r.url});
        if(!kept.cover&&r.cover) kept.cover=r.cover; if(!kept.latestChapter&&r.latestChapter) kept.latestChapter=r.latestChapter;
        continue;
      }
      if(key.trim()) seen.set(key, r); out.push(r);
    }
    return out;
  }
}
module.exports.default = ResultDeduplicator;

module.exports.ResultDeduplicator = ResultDeduplicator;

});
__define('src/search/SearchAggregator.js', function(module, exports, __require){
const { runPool } = __require('../core/TaskManager.js');
const { ResultDeduplicator } = __require('./ResultDeduplicator.js');
// Parallel multi-source search: failure of one source never fails the search.
class SearchAggregator{
  constructor(engine){ this.engine=engine; this.dedup=new ResultDeduplicator(); }
  async search(keyword, options={}){
    const engine=this.engine; const task=options.task||engine.tasks.create('search:'+keyword);
    const sources=engine.sources.resolve(options.sources);
    const concurrency=options.concurrency||engine.config.get('concurrency')||5;
    const timeout=options.timeout||engine.config.get('timeout');
    // The cache key fingerprints each source's variable store:
    // a line switch (source.put('ijLine', ...) from a login
    // hook) changes the fingerprint, so results gathered on the
    // old line are never served after the switch (B176).
    const fp=(s)=>{ try{ const v=engine.sourceVars?engine.sourceVars(s.id):null; return v&&Object.keys(v).length?JSON.stringify(v):''; }catch(e){ return ''; } };
    const cacheKey='search:'+keyword+':'+sources.map(s=>s.id+'@'+fp(s)).join(',');
    if(!options.noCache){ const cached=await engine.cache.get(cacheKey); if(cached) return {...cached, fromCache:true}; }
    let done=0;
    const settled=await runPool(sources, concurrency, async (source)=>{
      engine.events.emit('search:progress', {keyword, sourceId:source.id, status:'start', done, total:sources.length});
      try{
        const items=await engine.withTimeout(source.search(keyword, {page:options.page||1, task}), timeout, task);
        done++; engine.events.emit('search:progress', {keyword, sourceId:source.id, status:'ok', count:items.length, done, total:sources.length});
        return items;
      }catch(e){
        done++; engine.events.emit('search:progress', {keyword, sourceId:source.id, status:'error', error:e, done, total:sources.length});
        engine.events.emit('source:error', {sourceId:source.id, stage:'search', error:e});
        return [];
      }
    }, task);
    let results=[]; for(const s of settled) if(s.status==='fulfilled'&&Array.isArray(s.value)) results.push(...s.value);
    results=this.dedup.dedupe(results);
    results.sort((a,b)=> (b.metadata?.priority||0)-(a.metadata?.priority||0));
    const out={keyword, results, total:results.length, page:options.page||1, sourcesQueried:sources.length};
    if(!options.noCache) await engine.cache.set(cacheKey, out);
    if(!options.task) engine.tasks.done(task.id);
    return out;
  }
}
module.exports.default = SearchAggregator;

module.exports.SearchAggregator = SearchAggregator;

});
__define('src/search/SearchEngine.js', function(module, exports, __require){
const { SearchAggregator } = __require('./SearchAggregator.js');
class SearchEngine{
  constructor(engine){ this.engine=engine; this.aggregator=new SearchAggregator(engine); }
  search(keyword, options={}){ return this.aggregator.search(keyword, options); }
  async searchPage(keyword, options={}){ const page=options.page||1; const pageSize=options.pageSize||20; const all=await this.search(keyword, {...options, page}); const start=(page-1)*pageSize; return {...all, page, pageSize, results:all.results.slice(start, start+pageSize)}; }
}
module.exports.default = SearchEngine;

module.exports.SearchEngine = SearchEngine;

});
__define('src/source/HealthChecker.js', function(module, exports, __require){
const { runPool } = __require('../core/TaskManager.js');
const { ERR } = __require('../core/errors.js');
const { debugLog } = __require('../core/utils.js');

// engine.health — batch health checks ("patrol") for installed sources.
//
// check(sourceId, {keyword='测试', deep=false}) classifies one source:
//   ok          search returned results (deep: also chapters > 0 and
//               content > 0 chars on the first chapter/article)
//   empty       requests succeeded but produced 0 results / 0 chapters /
//               0 content chars
//   error       the check threw (entry.error = {code, message})
//   unsupported the engine cannot execute this source at all
//               (E_UNSUPPORTED, webview-html, bookSourceType 3, ...)
//   disabled    the source is currently disabled (not probed)
// RSS subscription sources are checked through rss.articles() and carry
// kind:'rss' in their entries.
//
// Every check is appended to the source's history in engine storage under
// 'moyuan:health:<sourceId>' (last 10 kept). When the trailing run of
// failures (error/empty) reaches the suspect threshold (default 3,
// configurable via createNovelEngine({health:{threshold}})), the entry is
// marked suspect:true and a 'health:suspect' event fires (on the transition
// only). Suspects are NEVER auto-disabled unless checkAll is called with
// {autoDisableSuspects:true}.
const HISTORY_PREFIX = 'moyuan:health:';
const HISTORY_KEEP = 10;

class HealthChecker {
  constructor(engine, opts = {}) {
    this.engine = engine;
    this.threshold = opts.threshold || (engine.config ? engine.config.get('healthSuspectThreshold') : null) || 3;
  }
  async check(sourceId, opts = {}) {
    const { keyword = '测试', deep = false } = opts;
    const engine = this.engine;
    const adapter = engine.sources.get(sourceId);
    const rss = !adapter && engine.rss ? engine.rss.get(sourceId) : null;
    if (!adapter && !rss) {
      return { sourceId, kind: 'book', status: 'error', latencyMs: 0, checkedAt: new Date().toISOString(), detail: {}, error: { code: ERR.SOURCE_NOT_FOUND, message: 'Source not found: ' + sourceId }, suspect: false };
    }
    const started = Date.now();
    const entry = { sourceId, kind: rss ? 'rss' : 'book', status: 'error', latencyMs: 0, checkedAt: new Date().toISOString(), detail: {}, suspect: false };
    try {
      if (rss) await this._probeRss(rss, entry, { deep });
      else await this._probeBook(adapter, entry, { keyword, deep });
    } catch (e) {
      if (e && e.code === ERR.UNSUPPORTED) { entry.status = 'unsupported'; entry.detail.reason = e.message || String(e); }
      else { entry.status = 'error'; entry.error = { code: (e && e.code) || 'E_UNKNOWN', message: (e && e.message) || String(e) }; }
    }
    entry.latencyMs = Date.now() - started;
    entry.suspect = await this._record(entry);
    return entry;
  }
  async _probeBook(adapter, entry, { keyword, deep }) {
    if (!adapter.enabled) { entry.status = 'disabled'; entry.detail.reason = 'source is disabled'; return; }
    if (adapter.kind === 'webview-html') { entry.status = 'unsupported'; entry.detail.reason = 'webview-html source: no rule surface to probe'; return; }
    if (adapter.def.type === 3) { entry.status = 'unsupported'; entry.detail.reason = 'bookSourceType 3 (file/video) is not executed by this engine'; return; }
    const results = await adapter.search(keyword, {});
    entry.detail.searchCount = results.length;
    if (!results.length) { entry.status = 'empty'; return; }
    if (!deep) { entry.status = 'ok'; return; }
    const book = await adapter.bookInfo(results[0]);
    const chapters = await adapter.chapters(book);
    entry.detail.chapters = chapters.length;
    if (!chapters.length) { entry.status = 'empty'; return; }
    const content = await adapter.content(book, chapters[0]);
    entry.detail.contentChars = (content.text || '').length;
    if (!entry.detail.contentChars && !(content.blocks || []).length) { entry.status = 'empty'; return; }
    entry.status = 'ok';
  }
  async _probeRss(src, entry, { deep }) {
    const articles = await src.articles({});
    entry.detail.searchCount = articles.length;
    entry.detail.articles = articles.length;
    if (!articles.length) { entry.status = 'empty'; return; }
    if (deep) {
      const content = await src.articleContent(articles[0]);
      entry.detail.contentChars = (content.text || '').length;
      if (!entry.detail.contentChars) { entry.status = 'empty'; return; }
    }
    entry.status = 'ok';
  }
  async checkAll(opts = {}) {
    const { concurrency = 3, keyword = '测试', deep = false, onProgress = null, autoDisableSuspects = false } = opts;
    const engine = this.engine;
    const ids = [];
    for (const a of engine.sources.list({ includeDisabled: true })) ids.push(a.id);
    if (engine.rss) for (const info of engine.rss.list()) ids.push(info.id);
    const results = new Array(ids.length);
    let done = 0;
    await runPool(ids, Math.max(1, concurrency | 0), async (id, i) => {
      const entry = await this.check(id, { keyword, deep });
      results[i] = entry;
      done++;
      if (typeof onProgress === 'function') { try { onProgress(done, ids.length, entry); } catch (e) { debugLog('health onProgress error', e); } }
      return entry;
    });
    const totals = { ok: 0, empty: 0, error: 0, unsupported: 0, disabled: 0 };
    for (const r of results) totals[r.status] = (totals[r.status] || 0) + 1;
    const report = { checkedAt: new Date().toISOString(), totals, results };
    if (autoDisableSuspects) {
      const disabled = [];
      for (const r of results) {
        if (r.suspect && r.kind === 'book') {
          const a = engine.sources.get(r.sourceId);
          if (a && a.enabled) { engine.sources.disable(r.sourceId); disabled.push(r.sourceId); }
        }
      }
      report.autoDisabled = disabled;
    }
    return report;
  }
  async history(sourceId) { return this.engine.storage.getJSON(HISTORY_PREFIX + sourceId, []); }
  // Appends the entry to storage history; returns whether the source is now
  // suspect (trailing error/empty run >= threshold). Fires 'health:suspect'
  // on the transition into suspect.
  async _record(entry) {
    const key = HISTORY_PREFIX + entry.sourceId;
    let hist = [];
    try { hist = await this.engine.storage.getJSON(key, []); } catch (e) { hist = []; }
    if (!Array.isArray(hist)) hist = [];
    const wasSuspect = trailingFailures(hist) >= this.threshold;
    const stored = { ...entry };
    hist = [...hist, stored].slice(-HISTORY_KEEP);
    const suspect = trailingFailures(hist) >= this.threshold;
    stored.suspect = suspect;
    try { await this.engine.storage.setJSON(key, hist); } catch (e) { debugLog('health history save failed', e); }
    if (suspect && !wasSuspect) this.engine.events.emit('health:suspect', { sourceId: entry.sourceId, status: entry.status, failures: trailingFailures(hist), threshold: this.threshold });
    return suspect;
  }
}
function trailingFailures(hist) {
  let n = 0;
  for (let i = hist.length - 1; i >= 0; i--) { if (hist[i].status === 'error' || hist[i].status === 'empty') n++; else break; }
  return n;
}
module.exports.default = HealthChecker;

module.exports.HealthChecker = HealthChecker;

});
__define('src/source/LocalBook.js', function(module, exports, __require){
// LocalBook — turn local files into registerable MoYuan sources.
//
// TXT: chapter splitting by common heading lines (第X章/节/回/卷…, Chapter N).
//   A non-empty preamble becomes a 序章 chapter. When no heading exists at
//   all, the text is cut into fixed-size volumes whose titles say so.
// EPUB: a minimal hand-written ZIP reader (stored entries verbatim; deflate
//   entries need an inflate implementation — opts.inflate(bytes), or the
//   runtime's DecompressionStream('deflate-raw') when present; Node hosts
//   can pass node:zlib's inflateRawSync). Container/OPF are parsed at regex
//   level via XmlLite. ZIP CRCs are not verified. No DRM, no NCX nav beyond
//   spine order, chapter titles from the first heading/title in each XHTML.
// The result's `source` is a custom-source definition: register it with
// engine.sourceManager.register(book.source) and search/read it like any
// other source. Chapter texts live in memory with the definition object.
const { xmlFirstTag, xmlSelfTags, xmlText, xmlFieldText } = __require('../parser/XmlLite.js');
const { utf8Decode, cleanContent } = __require('../core/utils.js');
const { NovelError, ERR } = __require('../core/errors.js');

const HEADING_RE = /^第[零一二三四五六七八九十百千万两\d]+[章节回卷部篇]/;
function isChapterHeading(line) {
  const t = String(line || '').trim();
  if (!t || t.length > 60) return false;
  // A body line can also start with 第X章 (e.g. repeating the title in prose);
  // real heading lines never contain a full stop 。
  if (t.includes('。')) return false;
  return HEADING_RE.test(t) || /^chapter\s+\d+/i.test(t);
}
function splitTxtChapters(text) {
  const lines = String(text || '').replace(/\r\n?/g, '\n').split('\n');
  const chapters = []; let current = null;
  const flush = () => { if (current) { current.text = current.parts.join('\n').trim(); delete current.parts; if (current.text || chapters.length === 0) chapters.push(current); } };
  for (const line of lines) {
    if (isChapterHeading(line)) { flush(); current = { title: line.trim(), parts: [] }; }
    else { if (!current) current = { title: '序章', parts: [] }; current.parts.push(line); }
  }
  flush();
  return chapters.filter(c => c.text);
}
function chunkText(text, size = 10000) {
  const out = []; let rest = String(text || '');
  while (rest.length > size) {
    let cut = rest.lastIndexOf('\n', size);
    if (cut < size * 0.5) cut = size;
    out.push(rest.slice(0, cut)); rest = rest.slice(cut).replace(/^\n+/, '');
  }
  if (rest.trim()) out.push(rest);
  return out;
}
function slug(s) { let h = 0; const raw = String(s || 'book'); for (let i = 0; i < raw.length; i++) h = ((h << 5) - h + raw.charCodeAt(i)) | 0; return Math.abs(h).toString(36); }
function makeLocalSource(book) {
  const id = 'local:' + book.format + ':' + slug(book.title + '|' + (book.author || ''));
  const bookUrl = id + '://book';
  return {
    id, name: book.title,
    custom: {
      search: async () => [{ title: book.title, author: book.author || '', url: bookUrl, description: book.description || '' }],
      bookInfo: async (item) => item,
      chapters: async () => book.chapters.map((c, i) => ({ title: c.title, url: id + '://chapter/' + i })),
      content: async (item, chapter) => { const idx = parseInt(String(chapter.url || '').split('/').pop(), 10); const c = book.chapters[idx]; return c ? c.text : ''; },
    },
  };
}
function parseTxtBook(text, options = {}) {
  const title = options.title || '本地书籍';
  let chapters = splitTxtChapters(text);
  let autoChunked = false;
  if (chapters.length <= 1 && String(text || '').length > (options.chunkSize || 10000)) {
    chapters = chunkText(text, options.chunkSize || 10000).map((t, i) => ({ title: '第' + (i + 1) + '卷（无章节标题，自动分卷）', text: t.trim() }));
    autoChunked = true;
  }
  const book = { kind: 'local', format: 'txt', title, author: options.author || '', description: options.description || '', chapters, autoChunked };
  book.source = makeLocalSource(book);
  return book;
}

// ---------------- minimal ZIP reader ----------------
function u16(b, o) { return b[o] | (b[o + 1] << 8); }
function u32(b, o) { return (b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24)) >>> 0; }
async function inflateRawBytes(data, opts) {
  if (opts && typeof opts.inflate === 'function') { const out = await opts.inflate(data); return out instanceof Uint8Array ? out : Uint8Array.from(out); }
  if (typeof DecompressionStream !== 'undefined' && typeof Blob !== 'undefined' && typeof Response !== 'undefined') {
    const stream = new Blob([data]).stream().pipeThrough(new DecompressionStream('deflate-raw'));
    return new Uint8Array(await new Response(stream).arrayBuffer());
  }
  throw new NovelError(ERR.UNSUPPORTED, 'EPUB entry is deflate-compressed but no inflate implementation is available: pass opts.inflate(bytes) (e.g. node:zlib inflateRawSync) or run where DecompressionStream exists');
}
async function readZipEntries(bytes, opts = {}) {
  const b = bytes instanceof Uint8Array ? bytes : Uint8Array.from(bytes || []);
  let eocd = -1;
  for (let i = b.length - 22; i >= Math.max(0, b.length - 22 - 65557); i--) { if (u32(b, i) === 0x06054b50) { eocd = i; break; } }
  if (eocd < 0) throw new NovelError(ERR.PARSE, 'Not a ZIP file (end of central directory not found)');
  const count = u16(b, eocd + 10); let off = u32(b, eocd + 16);
  const entries = new Map();
  for (let n = 0; n < count; n++) {
    if (u32(b, off) !== 0x02014b50) break;
    const method = u16(b, off + 10); const compSize = u32(b, off + 20);
    const nameLen = u16(b, off + 28), extraLen = u16(b, off + 30), commentLen = u16(b, off + 32);
    const localOff = u32(b, off + 42);
    const name = utf8Decode(Array.from(b.slice(off + 46, off + 46 + nameLen)));
    const lNameLen = u16(b, localOff + 26), lExtraLen = u16(b, localOff + 28);
    const dataStart = localOff + 30 + lNameLen + lExtraLen;
    const raw = b.slice(dataStart, dataStart + compSize);
    let data;
    if (method === 0) data = raw;
    else if (method === 8) data = await inflateRawBytes(raw, opts);
    else throw new NovelError(ERR.UNSUPPORTED, 'ZIP compression method not supported: ' + method + ' (entry ' + name + ')');
    entries.set(name, data);
    off += 46 + nameLen + extraLen + commentLen;
  }
  return entries;
}
function normalizePath(p) {
  const out = [];
  for (const seg of String(p).split('/')) { if (seg === '' || seg === '.') continue; if (seg === '..') out.pop(); else out.push(seg); }
  return out.join('/');
}
async function parseEpubBook(bytes, options = {}) {
  const entries = await readZipEntries(bytes, options);
  const containerBytes = entries.get('META-INF/container.xml');
  if (!containerBytes) throw new NovelError(ERR.PARSE, 'EPUB missing META-INF/container.xml');
  const container = utf8Decode(Array.from(containerBytes));
  const rootfile = container.match(/full-path="([^"]+)"/);
  if (!rootfile) throw new NovelError(ERR.PARSE, 'EPUB container.xml has no rootfile');
  const opfPath = rootfile[1];
  const opfBytes = entries.get(opfPath);
  if (!opfBytes) throw new NovelError(ERR.PARSE, 'EPUB OPF not found: ' + opfPath);
  const opf = utf8Decode(Array.from(opfBytes));
  const title = xmlFieldText(opf, ['dc:title']) || options.title || 'EPUB 书籍';
  const author = xmlFieldText(opf, ['dc:creator']);
  const manifest = new Map();
  for (const item of xmlSelfTags(opf, 'item')) { if (item.attrs.id && item.attrs.href) manifest.set(item.attrs.id, item.attrs); }
  const opfDir = opfPath.includes('/') ? opfPath.slice(0, opfPath.lastIndexOf('/') + 1) : '';
  const chapters = [];
  for (const ref of xmlSelfTags(opf, 'itemref')) {
    const item = manifest.get(ref.attrs.idref);
    if (!item) continue;
    const mediaType = item['media-type'] || '';
    if (mediaType && mediaType !== 'application/xhtml+xml') continue;
    const entryName = normalizePath(opfDir + decodeURIComponent(item.href));
    const data = entries.get(entryName);
    if (!data) continue;
    const xhtml = utf8Decode(Array.from(data));
    const heading = xhtml.match(/<h[1-3][^>]*>([\s\S]*?)<\/h[1-3]>/i);
    const titleTag = xmlFirstTag(xhtml, 'title');
    const chTitle = (heading ? xmlText(heading[1]) : '') || (titleTag ? xmlText(titleTag.inner) : '') || ('第' + (chapters.length + 1) + '章');
    const text = cleanContent(xhtml);
    if (text) chapters.push({ title: chTitle, text });
  }
  if (!chapters.length) throw new NovelError(ERR.PARSE, 'EPUB spine produced no readable chapters');
  const book = { kind: 'local', format: 'epub', title: options.title || title, author: options.author || author, description: '', chapters };
  book.source = makeLocalSource(book);
  return book;
}
module.exports.default = { parseTxtBook, splitTxtChapters, parseEpubBook, readZipEntries, makeLocalSource };

module.exports.isChapterHeading = isChapterHeading;
module.exports.splitTxtChapters = splitTxtChapters;
module.exports.chunkText = chunkText;
module.exports.makeLocalSource = makeLocalSource;
module.exports.parseTxtBook = parseTxtBook;
module.exports.readZipEntries = readZipEntries;
module.exports.parseEpubBook = parseEpubBook;

});
__define('src/source/OpdsCatalog.js', function(module, exports, __require){
// OpdsCatalog — OPDS 1.x catalog browsing (Atom feeds with acquisition
// links). Directory listing + OpenSearch-based search only; no DRM, no
// downloading (acquisition URLs are handed back to the host).
const { xmlTagBlocks, xmlSelfTags, xmlFieldText } = __require('../parser/XmlLite.js');
const { resolveUrl } = __require('../core/utils.js');
const { NovelError, ERR } = __require('../core/errors.js');

function parseOpdsFeed(xml, baseUrl) {
  const out = [];
  for (const entry of xmlTagBlocks(xml, 'entry')) {
    const authorBlock = xmlTagBlocks(entry, 'author')[0] || '';
    let acquisitionUrl = '', format = '';
    for (const link of xmlSelfTags(entry, 'link')) {
      const rel = link.attrs.rel || '';
      if (rel.includes('opds-spec.org/acquisition')) { acquisitionUrl = resolveUrl(baseUrl, link.attrs.href || ''); format = link.attrs.type || ''; break; }
    }
    out.push({
      title: xmlFieldText(entry, ['title']),
      author: xmlFieldText(authorBlock, ['name']),
      summary: xmlFieldText(entry, ['summary', 'content']),
      acquisitionUrl, format,
    });
  }
  return out;
}
// An OpenSearch template is either a feed-level search link whose href
// already carries {searchTerms}, or a search-description document URL
// (rel="search", type="application/opds-searchdescription+xml").
function findOpdsSearch(xml) {
  for (const link of xmlSelfTags(xml, 'link')) {
    if ((link.attrs.rel || '') !== 'search') continue;
    const href = link.attrs.href || '';
    if (href.includes('{searchTerms')) return { template: href };
    if ((link.attrs.type || '').includes('opds-searchdescription')) return { descriptionUrl: href };
  }
  return null;
}
function parseSearchDescription(xml) {
  for (const u of xmlSelfTags(xml, 'Url')) {
    const type = u.attrs.type || '';
    if (type.includes('atom+xml') && (u.attrs.template || '').includes('{searchTerms')) return u.attrs.template;
  }
  return null;
}
class OpdsCatalog {
  constructor(engine) { this.engine = engine; }
  async _get(url) { const res = await this.engine.requests.request(url, { headers: { Accept: 'application/atom+xml,application/xml,*/*' } }); return { body: res.body, url: res.url || url }; }
  async fetchCatalog(url) { const { body, url: finalUrl } = await this._get(url); return parseOpdsFeed(body, finalUrl); }
  async search(url, terms) {
    const { body, url: finalUrl } = await this._get(url);
    const found = findOpdsSearch(body);
    if (!found) throw new NovelError(ERR.UNSUPPORTED, 'OPDS catalog exposes no OpenSearch template (no rel="search" link)');
    let template = found.template;
    if (!template && found.descriptionUrl) {
      const desc = await this._get(resolveUrl(finalUrl, found.descriptionUrl));
      template = parseSearchDescription(desc.body);
      if (!template) throw new NovelError(ERR.UNSUPPORTED, 'OPDS search description has no atom+xml {searchTerms} template');
    }
    const searchUrl = resolveUrl(finalUrl, template).replace('{searchTerms}', encodeURIComponent(String(terms || '')));
    const res = await this._get(searchUrl);
    return parseOpdsFeed(res.body, res.url);
  }
}
module.exports.default = OpdsCatalog;

module.exports.parseOpdsFeed = parseOpdsFeed;
module.exports.findOpdsSearch = findOpdsSearch;
module.exports.parseSearchDescription = parseSearchDescription;
module.exports.OpdsCatalog = OpdsCatalog;

});
__define('src/source/RemoteRepository.js', function(module, exports, __require){
// RemoteRepository — one generic import path for ANY remote source
// collection: yckceo 源仓库 endpoints, nyasama, GitHub raw files, gists, or
// a self-hosted JSON. The file is fetched through the engine's injected
// request, parsed with parseSourceArray (arrays, or objects wrapping the
// array under sources|bookSources|data|list|items), and every entry is
// classified and reported individually — never all-or-nothing:
//   (a) Legado book source  -> registered with the engine
//   (b) subscription entry  -> routed to engine.rss (sourceName/sourceUrl only)
//   (c) webview-html source -> skipped (rule engine cannot execute it)
//   (d) bookSourceType 3 (file/video) -> skipped by default (skipTypes option)
//   (e) anything else       -> failed with the reason
// Verified shapes (2026-11-10): yckceo shuyuan/rss/rsss JSON files,
// nyasama-style Legado arrays, GitHub raw Legado collections, Yiove-style
// object wrappers. See docs/ADAPTERS.md.
const { parseSourceArray, detectSourceKind } = __require('./SourceAdapter.js');
const { detectSubscriptionEntry } = __require('./RssAdapter.js');

class RemoteRepository {
  constructor(engine) { this.engine = engine; }
  async importFromUrl(url, options = {}) {
    const res = await this.engine.requests.request(url, { headers: { Accept: 'application/json,text/plain,*/*', ...(options.headers || {}) } });
    return this.importFromText(res.body, { ...options, originUrl: url });
  }
  importFromText(text, options = {}) {
    const skipTypes = options.skipTypes || [3];
    const defs = parseSourceArray(text);
    const results = []; let imported = 0, skipped = 0, failed = 0, subscriptions = 0;
    for (const def of defs) {
      const name = (def && (def.bookSourceName || def.sourceName || def.name)) || '';
      try {
        if (detectSubscriptionEntry(def)) {
          const src = this.engine.rss.register(def, { replace: true });
          results.push({ name, status: 'subscription', sourceId: src.id }); subscriptions++; continue;
        }
        if (detectSourceKind(def) === 'webview-html') {
          results.push({ name, status: 'skipped', reason: 'webview-html source (single html page app, no rule surface): rule engine cannot execute it, host WebView only' }); skipped++; continue;
        }
        const type = parseInt(def && def.bookSourceType != null ? def.bookSourceType : 0, 10) || 0;
        if (skipTypes.includes(type)) {
          results.push({ name, status: 'skipped', reason: 'bookSourceType ' + type + ' skipped (file/video)' }); skipped++; continue;
        }
        const reg = this.engine.sourceManager.registerMany([def], { replace: true });
        if (reg.registered.length) { results.push({ name, status: 'imported', sourceId: reg.registered[0].id, sourceName: reg.registered[0].name }); imported++; }
        else { results.push({ name, status: 'failed', reason: (reg.failures[0] && reg.failures[0].error) || 'validator rejected' }); failed++; }
      } catch (e) { results.push({ name, status: 'failed', reason: String(e.message || e) }); failed++; }
    }
    return { total: defs.length, imported, skipped, failed, subscriptions, results };
  }
}
module.exports.default = RemoteRepository;

module.exports.RemoteRepository = RemoteRepository;

});
__define('src/source/RssAdapter.js', function(module, exports, __require){
// RssAdapter — Legado subscription (RSS) sources for MoYuan.
//
// A subscription entry names itself with sourceName/sourceUrl and carries
// ARTICLE rules (ruleArticles/ruleTitle/ruleLink/ruleContent...) instead of
// book rules (Anikumo B167 classification, mirrored by detectSubscriptionEntry).
// Articles are parsed with the same Legado rule engine as book sources;
// when a source declares no usable rules and the fetched document is a real
// feed, a built-in RSS/Atom item parser takes over (same fallback the
// Anikumo Dart rss_engine performs). Honest v1 limits (documented):
// nextPageUrl following is capped, login flows are not performed (stored
// login info / cookies still apply through the shared request layer).
const { LegadoContext } = __require('../parser/LegadoParser.js');
const { textOf, htmlOf } = __require('../parser/HtmlParser.js');
const { evalScoped } = __require('../parser/JSParser.js');
const { resolveUrl, cleanContent } = __require('../core/utils.js');
const { parseHeaders } = __require('./SourceAdapter.js');
const { xmlTagBlocks, xmlFieldText } = __require('../parser/XmlLite.js');
const { NovelError, ERR } = __require('../core/errors.js');

// ---------- classification / definition ----------
function detectSubscriptionEntry(input) {
  if (!input || typeof input !== 'object') return false;
  const name = String(input.sourceName || '').trim();
  const url = String(input.sourceUrl || '').trim();
  if (!name || !url) return false;
  if (input.bookSourceName) return false;
  // Book-capability guard: foreign book formats also use sourceName — an
  // entry that can search books stays a book source.
  const hasBookCapability = !!(input.searchUrl || (input.ruleSearch && typeof input.ruleSearch === 'object' && Object.keys(input.ruleSearch).length));
  if (hasBookCapability) return false;
  return true;
}
function normalizeRssDef(input) {
  if (!detectSubscriptionEntry(input)) throw new NovelError(ERR.SOURCE_INVALID, 'Not a subscription entry (needs sourceName/sourceUrl and no book-source fields)');
  const url = String(input.sourceUrl).trim();
  return {
    id: url, name: String(input.sourceName).trim(), url,
    group: String(input.sourceGroup || ''), icon: String(input.sourceIcon || ''),
    headers: parseHeaders(input.header), jsLib: input.jsLib ? String(input.jsLib) : '',
    loginUrl: input.loginUrl ? String(input.loginUrl) : '', loginCheckJs: input.loginCheckJs ? String(input.loginCheckJs) : '',
    sortUrl: input.sortUrl ? String(input.sortUrl) : '', singleUrl: input.singleUrl === true,
    articleStyle: input.articleStyle != null ? Number(input.articleStyle) || 0 : 0,
    rules: {
      articles: String(input.ruleArticles || ''), title: String(input.ruleTitle || ''),
      link: String(input.ruleLink || ''), description: String(input.ruleDescription || ''),
      pubDate: String(input.rulePubDate || ''), image: String(input.ruleImage || ''),
      content: String(input.ruleContent || ''), nextPage: String(input.nextPageUrl || ''),
    },
    raw: input,
  };
}
// "name::url" lines (split by newline or &&), URLs resolved against base.
function parseSortUrlText(text, baseUrl) {
  const out = [];
  for (const chunk of String(text || '').split('\n')) {
    for (const part of chunk.split('&&')) {
      const t = part.trim(); if (!t) continue;
      const sep = t.indexOf('::'); if (sep < 0) continue;
      const title = t.slice(0, sep).trim(); const url = t.slice(sep + 2).trim();
      if (title && url) out.push({ title, url: resolveUrl(baseUrl, url) });
    }
  }
  return out;
}
// Standard feed fallback: RSS <item> / Atom <entry> read off the raw text
// (NOT through the HTML parser, which mangles feed documents).
function parseFeedArticles(xml, baseUrl) {
  let chunks = xmlTagBlocks(xml, 'item');
  if (!chunks.length) chunks = xmlTagBlocks(xml, 'entry');
  const out = [];
  for (const chunk of chunks) {
    let link = xmlFieldText(chunk, ['link']);
    if (!link) {
      const m = chunk.match(/<link[^>]*href=["']([^"']+)["']/i);
      link = m ? m[1] : xmlFieldText(chunk, ['guid']);
    }
    out.push({
      title: xmlFieldText(chunk, ['title']),
      link: link ? resolveUrl(baseUrl, link) : '',
      description: xmlFieldText(chunk, ['description', 'summary', 'content']),
      pubDate: xmlFieldText(chunk, ['pubDate', 'published', 'updated', 'date', 'dc:date']),
      image: '',
    });
  }
  return out;
}

// ---------- one subscription source ----------
class RssSource {
  constructor(def, engine) { this.def = def; this.engine = engine; this.id = def.id; this.name = def.name; this._vars = {}; }
  info() { return { id: this.id, name: this.name, url: this.def.url, group: this.def.group, icon: this.def.icon, hasArticleRules: !!this.def.rules.articles, hasSort: !!this.def.sortUrl, singleUrl: this.def.singleUrl, articleStyle: this.def.articleStyle }; }
  _ctx(body, baseUrl) {
    const def = this.def;
    const tracing = !!this.engine._trace;
    return new LegadoContext({
      baseUrl: baseUrl || this.id, jsLib: def.jsLib,
      source: { ...def.raw, sourceUrl: def.id, sourceName: def.name },
      logger: this.engine.logger, cookieJar: this.engine.requests.cookieJar, logs: [],
      loginInfo: this.engine.loginInfo ? this.engine.loginInfo(this.id) : null,
      vars: this._vars,
      trace: tracing ? (kind, data) => this.engine.traceStep(kind, data) : null,
      traceStage: 'rss',
      onUnsupported: (name) => this.engine.events.emit('source:unsupported', { sourceId: this.id, feature: name }),
      request: async (url, opts) => this._fetch(url, opts || {}),
      requestSync: this.engine.requestSync || null,
    });
  }
  _trace(kind, data) { return this.engine.traceStep(kind, data); }
  async _fetch(url, opts = {}) {
    const res = await this.engine.requests.request(resolveUrl(this.id, url), { headers: { ...this.def.headers, ...(opts.headers || {}) }, method: opts.method, body: opts.body });
    if (this.def.loginCheckJs && res.body) {
      try {
        const strRes = { body: res.body, url: res.url || url, headers: res.headers || {}, status: res.status, bodyText: res.body, toString: () => res.body };
        const ctx = this._ctx(res.body, res.url || url);
        const v = evalScoped(this.def.loginCheckJs, ctx.scope(strRes, {}), this.def.jsLib);
        if (typeof v === 'string' && v) return { ...res, body: v };
        if (v && typeof v === 'object' && typeof v.body === 'string') return { ...res, body: v.body, url: v.url || res.url };
      } catch (e) { this.engine.events.emit('source:error', { sourceId: this.id, stage: 'loginCheckJs', error: e }); }
    }
    return res;
  }
  // Category tabs from sortUrl: literal "name::url" text, or @js:/<js>
  // returning such text (original semantics) or a [{name|title, url}] array.
  async categories() {
    const sort = (this.def.sortUrl || '').trim();
    if (!sort) return [];
    if (sort.startsWith('@js:') || sort.includes('<js>')) {
      let code = sort; if (code.startsWith('@js:')) code = code.slice(4);
      const tag = code.match(/<js>([\s\S]*?)<\/js>/); if (tag) code = tag[1];
      try {
        const ctx = this._ctx('', this.id);
        const v = evalScoped(code, ctx.scope('', {}), this.def.jsLib);
        if (typeof v === 'string') return parseSortUrlText(v, this.id);
        if (Array.isArray(v)) return v.map(c => ({ title: String((c && (c.title || c.name)) || ''), url: c && c.url ? resolveUrl(this.id, String(c.url)) : '' })).filter(c => c.title && c.url);
        return [];
      } catch (e) { this.engine.events.emit('source:error', { sourceId: this.id, stage: 'sortUrl', error: e }); return []; }
    }
    return parseSortUrlText(sort, this.id);
  }
  _field(ctx, el, rule, pageUrl) {
    if (!rule) return '';
    if (el != null && typeof el === 'object' && el.type === 'element') {
      const bare = String(rule).trim();
      if (/^(text|textnodes|html|owntext|all)$/i.test(bare)) return bare.toLowerCase() === 'html' || bare.toLowerCase() === 'all' ? htmlOf(el) : textOf(el).trim();
      if (/^(href|src|alt|title|content|value)$/i.test(bare)) return el.attrs?.[bare.toLowerCase()] || '';
      return ctx.getString(htmlOf(el), rule);
    }
    if (el != null && typeof el === 'object') return ctx.getString(JSON.stringify(el), rule);
    return ctx.getString(el == null ? '' : String(el), rule);
  }
  // Articles for one category ({title,url} object, a raw URL string, or
  // omitted for the source home URL). Follows nextPageUrl up to 5 pages.
  async articles(options = {}) {
    this._trace('stage', { stage: 'rss', label: this.name + ' articles' });
    const category = options.category || null;
    let pageUrl = category ? (typeof category === 'string' ? resolveUrl(this.id, category) : resolveUrl(this.id, category.url || '')) : this.id;
    const rules = this.def.rules;
    const all = []; const seen = new Set(); let pages = 0;
    while (pageUrl && pages < 5) {
      if (seen.has(pageUrl)) break; seen.add(pageUrl); pages++;
      const res = await this._fetch(pageUrl);
      const body = res.body; const base = res.url || pageUrl;
      let items = [];
      if (rules.articles) {
        const ctx = this._ctx(body, base);
        const els = ctx.getElements(body, rules.articles, {});
        for (const el of els) {
          const title = this._field(ctx, el, rules.title, base);
          let link = this._field(ctx, el, rules.link, base);
          link = link ? resolveUrl(base, link) : '';
          const image = this._field(ctx, el, rules.image, base);
          items.push({ title, link, description: this._field(ctx, el, rules.description, base), pubDate: this._field(ctx, el, rules.pubDate, base), image: image ? resolveUrl(base, image) : '', sourceId: this.id });
        }
        items = items.filter(a => a.title || a.link);
        if (rules.nextPage) { const next = ctx.getString(body, rules.nextPage, {}); pageUrl = next ? resolveUrl(base, next) : null; if (pageUrl && !seen.has(pageUrl)) this._trace('branch', { stage: 'rss', label: 'follow nextPageUrl (page ' + (pages + 1) + ')', outputSummary: pageUrl }); } else pageUrl = null;
      }
      if (!items.length && /<(item|entry)[\s>]/i.test(body)) { items = parseFeedArticles(body, base).map(a => ({ ...a, sourceId: this.id })); if (items.length) this._trace('branch', { stage: 'rss', label: 'rule result empty — fell back to built-in RSS/Atom feed parser', outputSummary: items.length + ' articles' }); }
      all.push(...items);
      if (!rules.articles) break;
    }
    return all;
  }
  // Full text of one article ({link} object from articles(), or a URL string).
  async articleContent(article) {
    this._trace('stage', { stage: 'rss', label: this.name + ' articleContent ' + ((article && article.link) || '') });
    const link = typeof article === 'string' ? article : (article && article.link) || '';
    const title = (article && article.title) || '';
    if (!link) throw new NovelError(ERR.VALIDATION, 'articleContent needs an article with a link');
    if (!this.def.rules.content) return { title, link, text: '', paragraphs: [], sourceId: this.id };
    const res = await this._fetch(link);
    const ctx = this._ctx(res.body, res.url || link);
    const rule = this.def.rules.content;
    let raw = ctx.getString(res.body, rule, {});
    // A bare element rule yields flattened text (paragraph boundaries lost);
    // re-read as HTML so cleanContent can restore them (the Dart engine
    // reads the element's innerHtml the same way).
    if (raw && !/<\w/.test(raw) && !/^\s*@?js:/.test(rule) && !rule.includes('@js:')) {
      const htmlRaw = ctx.getString(res.body, rule.trim() + '@html', {});
      if (/<\w/.test(htmlRaw)) raw = htmlRaw;
    }
    const text = cleanContent(raw || '');
    return { title, link, text, paragraphs: text.split(/\n+/).map(s => s.trim()).filter(Boolean), sourceId: this.id };
  }
}

// ---------- registry: engine.rss ----------
class RssRegistry {
  constructor(engine) { this.engine = engine; this._map = new Map(); }
  register(input, opts = {}) {
    const def = normalizeRssDef(input);
    if (this._map.has(def.id) && !opts.replace) throw new NovelError(ERR.SOURCE_INVALID, 'Subscription source already registered: ' + def.id);
    const src = new RssSource(def, this.engine);
    this._map.set(def.id, src);
    this.engine.events.emit('rss:registered', { sourceId: def.id, name: def.name });
    return src;
  }
  registerMany(inputs, opts = {}) { const registered = []; const failures = []; for (const input of inputs || []) { try { registered.push(this.register(input, opts)); } catch (e) { failures.push({ name: (input && (input.sourceName || input.sourceUrl)) || '', error: String(e.message || e) }); } } return { registered, failures }; }
  get(id) { return this._map.get(id) || null; }
  has(id) { return this._map.has(id); }
  remove(id) { return this._map.delete(id); }
  list() { return [...this._map.values()].map(s => s.info()); }
  _require(id) { const s = this._map.get(id); if (!s) throw new NovelError(ERR.SOURCE_NOT_FOUND, 'Subscription source not found: ' + id); return s; }
  async categories(sourceId) { return this._require(sourceId).categories(); }
  async articles(sourceId, options = {}) { return this._require(sourceId).articles(options); }
  async articleContent(article) {
    if (!article || !article.sourceId) throw new NovelError(ERR.VALIDATION, 'articleContent needs an article returned by rss.articles() (with sourceId)');
    return this._require(article.sourceId).articleContent(article);
  }
}
module.exports.default = RssRegistry;

module.exports.detectSubscriptionEntry = detectSubscriptionEntry;
module.exports.normalizeRssDef = normalizeRssDef;
module.exports.parseSortUrlText = parseSortUrlText;
module.exports.parseFeedArticles = parseFeedArticles;
module.exports.RssSource = RssSource;
module.exports.RssRegistry = RssRegistry;

});
__define('src/source/SourceAdapter.js', function(module, exports, __require){
const { LegadoContext } = __require('../parser/LegadoParser.js');
const { parseHtml, textOf, htmlOf } = __require('../parser/HtmlParser.js');
const { evalScoped, ajaxCacheKey } = __require('../parser/JSParser.js');
const { resolveUrl, renderTemplate, parseLooseObject, parseUrlOption, cleanContent, cleanTitle, encodeId, applyReplaceRegex, dedupeBy, literalToJson, debugLog } = __require('../core/utils.js');
const { NovelError, ERR } = __require('../core/errors.js');

// ---------- definition normalization ----------
function ruleMap(value) {
  if (value == null) return {};
  if (typeof value === 'string') value = parseLooseObject(value);
  if (Array.isArray(value)) return {};
  if (typeof value !== 'object') return {};
  const out = {};
  for (const [k, v] of Object.entries(value)) if (v != null && String(v) !== '') out[k] = String(v);
  return out;
}
function parseHeaders(header) {
  if (!header) return {};
  if (typeof header === 'object') { const out = {}; for (const [k, v] of Object.entries(header)) out[k] = String(v); return out; }
  const obj = parseLooseObject(header);
  const out = {}; for (const [k, v] of Object.entries(obj)) out[k] = String(v); return out;
}
// Port of the Dart normalization for classic flat (YueDu) shapes: only missing
// pieces are synthesized; Legado-shaped sources pass through untouched.
function normalizeForeign(json) {
  const s = (k) => json[k] != null ? String(json[k]) : '';
  const typeText = s('bookSourceType');
  const typeValue = typeText === '漫画' ? 2 : (typeText === '音频' || typeText === '听书') ? 1 : typeText === '小说' ? 0 : null;
  const isYuedu = 'ruleSearchList' in json || 'ruleSearchUrl' in json || 'ruleChapterList' in json;
  if (!isYuedu && typeValue == null) return json;
  const out = { ...json };
  if (typeValue != null) out.bookSourceType = typeValue;
  if (!isYuedu) return out;
  const pick = (fields) => { const o = {}; for (const [k, v] of Object.entries(fields)) if (v) o[k] = v; return o; };
  const searchRules = () => pick({ bookList: s('ruleSearchList'), name: s('ruleSearchName'), author: s('ruleSearchAuthor'), coverUrl: s('ruleSearchCoverUrl'), kind: s('ruleSearchKind'), lastChapter: s('ruleSearchLastChapter'), bookUrl: s('ruleSearchNoteUrl') });
  if ('enable' in json) out.enabled = json.enable;
  if (!out.header && s('httpUserAgent')) out.header = JSON.stringify({ 'User-Agent': s('httpUserAgent') });
  if (out.searchUrl == null && s('ruleSearchUrl')) out.searchUrl = s('ruleSearchUrl').replaceAll('searchKey', '{{key}}').replaceAll('searchPage', '{{page}}');
  if (out.exploreUrl == null && s('ruleFindUrl')) out.exploreUrl = s('ruleFindUrl').replace(/\r\n/g, '\n').replace(/\r/g, '\n');
  if (!(out.ruleSearch instanceof Object) && s('ruleSearchList')) out.ruleSearch = searchRules();
  if (!(out.ruleExplore instanceof Object)) out.ruleExplore = s('ruleFindList') ? pick({ bookList: s('ruleFindList'), name: s('ruleFindName'), author: s('ruleFindAuthor'), coverUrl: s('ruleFindCoverUrl'), kind: s('ruleFindKind'), lastChapter: s('ruleFindLastChapter'), bookUrl: s('ruleFindNoteUrl'), intro: s('ruleFindIntroduce') }) : (s('ruleSearchList') ? searchRules() : out.ruleExplore);
  if (!(out.ruleBookInfo instanceof Object)) out.ruleBookInfo = pick({ name: s('ruleBookName'), author: s('ruleBookAuthor'), coverUrl: s('ruleCoverUrl'), intro: s('ruleIntroduce'), kind: s('ruleBookKind'), lastChapter: s('ruleBookLastChapter'), tocUrl: s('ruleContentUrl') });
  if (!(out.ruleToc instanceof Object)) out.ruleToc = pick({ chapterList: s('ruleChapterList'), chapterName: s('ruleChapterName'), chapterUrl: s('ruleChapterUrl'), nextTocUrl: s('ruleChapterUrlNext') });
  if (!(out.ruleContent instanceof Object)) out.ruleContent = pick({ content: s('ruleBookContent'), nextContentUrl: s('ruleContentUrlNext') });
  if (out.bookUrlPattern == null && s('ruleBookUrlPattern')) out.bookUrlPattern = s('ruleBookUrlPattern');
  return out;
}
// ---------- source-kind detection ----------
// A "webview-html" source carries its whole app as one `html` page (a UI the
// user operates inside a WebView, borrowing only CookieJar/screen size from
// the host via flutter_inappwebview) and declares NO rule surface at all:
// no searchUrl/exploreUrl, no ruleSearch.bookList, no ruleToc.chapterList,
// no ruleContent.content. A rule engine cannot execute it — it can only be
// recognized, classified and handed to a WebView host. Example (probed
// 2026-11-10): 光遇聚合 from yckceo id/239.json, a single 186KB html field.
function detectSourceKind(input) {
  if (!input || typeof input !== 'object') return 'unknown';
  if (input.custom) return 'custom';
  if (input.kind === 'webview-html' || input.kind === 'legado') return input.kind; // already normalized
  const html = typeof input.html === 'string' ? input.html : '';
  const looksLikePage = /<!doctype html|<html[\s>]/i.test(html) || (html.includes('<script') && html.length > 2000);
  if (!looksLikePage) return 'legado';
  const ruleSearch = input.ruleSearch && typeof input.ruleSearch === 'object' ? input.ruleSearch : {};
  const ruleToc = input.ruleToc && typeof input.ruleToc === 'object' ? input.ruleToc : {};
  const ruleContent = input.ruleContent && typeof input.ruleContent === 'object' ? input.ruleContent : {};
  const hasRuleSurface = !!(input.searchUrl || input.exploreUrl || ruleSearch.bookList || ruleToc.chapterList || ruleContent.content);
  return hasRuleSurface ? 'legado' : 'webview-html';
}
function normalizeSourceDef(input) {
  if (!input || typeof input !== 'object') throw new NovelError(ERR.SOURCE_INVALID, 'Source definition must be an object');
  if (input.custom && typeof input.custom === 'object') {
    const c = input.custom;
    return { id: input.id || input.bookSourceUrl || ('custom:' + (input.name || 'unnamed')), name: input.name || 'Custom source', kind: 'custom', html: '', type: -1, group: input.group || '', comment: '', raw: input, searchUrl: '', exploreUrl: '', bookUrlPattern: '', headers: input.headers || {}, jsLib: '', loginUrl: '', loginUi: null, loginCheckJs: '', ruleSearch: {}, ruleExplore: {}, ruleBookInfo: {}, ruleToc: {}, ruleContent: {}, ruleReview: {}, enabled: input.enabled !== false, weight: 0, customOrder: 0, custom: c, priority: input.priority || 0, tags: input.tags || [] };
  }
  const json = normalizeForeign({ ...input });
  const url = String(json.bookSourceUrl ?? json.sourceUrl ?? json.url ?? '').trim();
  const name = String(json.bookSourceName ?? json.sourceName ?? json.name ?? '').trim();
  if (!url || !name) throw new NovelError(ERR.SOURCE_INVALID, 'Source requires bookSourceName and bookSourceUrl');
  let exploreUrl = json.exploreUrl ?? '';
  if (Array.isArray(exploreUrl)) exploreUrl = JSON.stringify(exploreUrl);
  const kind = detectSourceKind(json);
  return {
    id: url, name, kind, html: kind === 'webview-html' ? String(json.html || '') : '',
    type: parseInt(json.bookSourceType ?? 0, 10) || 0,
    group: String(json.bookSourceGroup || ''), comment: String(json.bookSourceComment || ''),
    raw: json, searchUrl: String(json.searchUrl || ''), exploreUrl: String(exploreUrl || ''),
    bookUrlPattern: String(json.bookUrlPattern || ''), headers: parseHeaders(json.header),
    jsLib: json.jsLib ? String(json.jsLib) : '', loginUrl: json.loginUrl ? String(json.loginUrl) : '',
    loginUi: json.loginUi || null, loginCheckJs: json.loginCheckJs ? String(json.loginCheckJs) : '',
    ruleSearch: ruleMap(json.ruleSearch), ruleExplore: ruleMap(json.ruleExplore),
    ruleBookInfo: ruleMap(json.ruleBookInfo), ruleToc: ruleMap(json.ruleToc),
    ruleContent: ruleMap(json.ruleContent), ruleReview: ruleMap(json.ruleReview),
    enabled: json.enabled !== false, weight: Number(json.weight) || 0, customOrder: Number(json.customOrder) || 0,
    priority: Number(json.customOrder) || 0, tags: String(json.bookSourceGroup || '').split(/[,，]/).map(x => x.trim()).filter(Boolean),
    enabledExplore: json.enabledExplore !== false, enabledCookieJar: json.enabledCookieJar !== false,
    respondTime: Number(json.respondTime) || 0, variables: {},
  };
}
function parseSourceArray(text) {
  let decoded = String(text || '').trim();
  if (decoded.charCodeAt(0) === 0xFEFF) decoded = decoded.slice(1);
  let value;
  try { value = JSON.parse(decoded); } catch (e) { try { value = JSON.parse(literalFix(decoded)); } catch (e2) { throw new NovelError(ERR.SOURCE_INVALID, 'Source payload is not JSON: ' + e.message); } }
  if (Array.isArray(value)) return value.filter(x => x && typeof x === 'object');
  if (value && typeof value === 'object') {
    for (const key of ['sources', 'bookSources', 'data', 'list', 'items']) if (Array.isArray(value[key])) return value[key].filter(x => x && typeof x === 'object');
    return [value];
  }
  return [];
}
function literalFix(t) { return t.replace(/\/\/[^\n]*/g, '').replace(/,\s*([}\]])/g, '$1'); }

// ---------- adapter ----------
class SourceAdapter {
  constructor(def, engine) {
    this.def = def; this.engine = engine; this.id = def.id; this.name = def.name;
    this.logs = []; this.errors = []; this._tocUrls = new Map();
    // Variable store: the engine's canonical per-source object
    // when available (shared across adapter re-registration and
    // seed/harvest by the host), else a private one (B176).
    this._vars = engine && typeof engine.varsFor === 'function' ? engine.varsFor(def.id) : {};
    this._ajaxCache = new Map(); // literal java.ajax/get/post prefetch (see _ensureAjaxPrefetch)
    this.stats = { searches: 0, errors: 0, lastUsed: 0 };
  }
  get enabled() { return this.def.enabled !== false; }
  get kind() { return this.def.kind || detectSourceKind(this.def.raw || this.def); }
  get isExecutable() { return this.kind !== 'webview-html'; }
  // WebView-html sources have no callable rule surface: fail loudly with a
  // stable error code instead of silently returning empty results.
  _assertExecutable(op) {
    if (this.kind !== 'webview-html') return;
    this.engine.events.emit('source:unsupported', { sourceId: this.id, feature: 'sourceKind:webview-html', op });
    throw new NovelError(ERR.UNSUPPORTED, 'WebView HTML page source cannot be executed by the rule engine (op: ' + op + '); render def.html in a WebView host instead', { sourceId: this.id });
  }
  setEnabled(v) { this.def.enabled = !!v; }
  get priority() { return this.def.priority || 0; }
  sourceProxy() {
    const def = this.def;
    return { ...def.raw, bookSourceUrl: def.id, bookSourceName: def.name, bookSourceGroup: def.group, bookSourceType: def.type,
      getVariable: () => { const v = this._vars.variable; return v == null ? '' : String(v); }, putVariable: (v) => { this._vars.variable = v; },
      // Legado source.get/put: the per-source variable store —
      // the same object java.get/put write. Line-switching
      // sources (Jiujiu's source.get('ijLine')) silently fell
      // back to their default line for as long as these were
      // missing: the call threw inside the source's own
      // try/catch and the stored line was never seen (B176).
      get: (k) => { const v = this._vars[String(k)]; return v === undefined ? '' : v; },
      put: (k, v) => { this._vars[String(k)] = v; },
      getLoginInfoMap: () => this.engine.loginInfo?.(this.id) || {}, getLoginHeaderMap: () => ({}), };
  }
  _lib() { return this._resolvedJsLib != null ? this._resolvedJsLib : this.def.jsLib; }
  // importScript preload: synchronous script loading is impossible here, so
  // literal importScript('url') call sites found in jsLib / rules are fetched
  // once, up front, and prepended to the effective jsLib. Dynamic (non-literal)
  // call sites still hit the shim's unsupported marker at run time.
  async _ensureJsLib() {
    if (this._jsLibPromise) return this._jsLibPromise;
    this._jsLibPromise = (async () => {
      const texts = [this.def.jsLib, this.def.searchUrl, this.def.exploreUrl, this.def.loginCheckJs, this.def.loginUrl,
        ...Object.values(this.def.ruleSearch || {}), ...Object.values(this.def.ruleExplore || {}),
        ...Object.values(this.def.ruleBookInfo || {}), ...Object.values(this.def.ruleToc || {}), ...Object.values(this.def.ruleContent || {})];
      const urls = []; const re = /importScript\(\s*['"]([^'"]+)['"]\s*\)/g;
      for (const t of texts) { if (!t) continue; let m; re.lastIndex = 0; while ((m = re.exec(String(t)))) { const u = resolveUrl(this.id, m[1]); if (!urls.includes(u)) urls.push(u); } }
      if (!urls.length) { this._resolvedJsLib = this.def.jsLib; return; }
      const parts = [];
      for (const u of urls) {
        try { const res = await this.engine.requests.request(u, { headers: { ...this.def.headers } }); if (res.body) parts.push(String(res.body)); }
        catch (e) { this.engine.events.emit('source:unsupported', { sourceId: this.id, feature: 'importScript preload failed: ' + u }); }
      }
      this._resolvedJsLib = parts.length ? parts.join('\n;\n') + '\n' + this.def.jsLib : this.def.jsLib;
    })();
    return this._jsLibPromise;
  }
  _ctx(body, extra = {}) {
    // Trace hooks are wired ONLY when a trace run is active on the engine,
    // so untraced calls keep the exact old code paths in the parser.
    const tracing = !!this.engine._trace;
    return new LegadoContext({
      baseUrl: extra.baseUrl || this.id, jsLib: this._lib(), source: this.sourceProxy(),
      key: extra.key || '', page: extra.page || 1, logger: this.engine.logger,
      cookieJar: this.engine.requests.cookieJar, logs: this.logs,
      loginInfo: this.engine.loginInfo ? this.engine.loginInfo(this.id) : null,
      vars: this._vars,
      trace: tracing ? (kind, data) => this.engine.traceStep(kind, data) : null,
      traceStage: extra.stage || 'rule',
      onUnsupported: (name) => this.engine.events.emit('source:unsupported', { sourceId: this.id, feature: name }),
      request: async (url, opts) => this.fetch(url, opts || {}),
      requestSync: this.engine.requestSync || null,
      prefetch: this._ajaxCache,
    });
  }
  // java.ajax prefetch: rule JS is synchronous, so literal
  // java.ajax('url') / java.get('url') / java.post('url','body') /
  // java.ajaxAll(['url',...]) call sites found in jsLib / rules are fetched
  // once, up front (same trick as importScript preload), and the shim
  // answers synchronously from this._ajaxCache. Non-literal URLs are not
  // prefetched; they fall back to the host sync transport or report
  // 'java.ajax-sync' as unsupported. Failures are recorded, never fatal.
  async _ensureAjaxPrefetch() {
    if (this._ajaxPromise) return this._ajaxPromise;
    this._ajaxPromise = (async () => {
      // Prefetch is only a fallback: when a synchronous host transport
      // exists (engine.requestSync or the novelHostRequestSync global),
      // the shim answers live and prefetching would just waste requests.
      if (this.engine.requestSync || (typeof globalThis !== 'undefined' && typeof globalThis.novelHostRequestSync === 'function')) return;
      const texts = [this.def.jsLib, this.def.searchUrl, this.def.exploreUrl, this.def.loginCheckJs, this.def.loginUrl,
        ...Object.values(this.def.ruleSearch || {}), ...Object.values(this.def.ruleExplore || {}),
        ...Object.values(this.def.ruleBookInfo || {}), ...Object.values(this.def.ruleToc || {}), ...Object.values(this.def.ruleContent || {})];
      const jobs = new Map();
      const add = (method, url, body) => { if (!url) return; const resolved = resolveUrl(this.id, url); const key = ajaxCacheKey(method, resolved, body); if (!jobs.has(key)) jobs.set(key, { key, method, url: resolved, body }); };
      const scan = (re, fn) => { for (const t of texts) { if (!t) continue; let m; re.lastIndex = 0; const s = String(t); while ((m = re.exec(s))) fn(m); } };
      scan(/\bajaxAll\(\s*\[([^\]]*)\]/g, (m) => { const q = /['"]([^'"]+)['"]/g; let x; while ((x = q.exec(m[1]))) add('GET', x[1]); });
      scan(/\bajax\(\s*(['"])((?:(?!\1).)*)\1\s*\)/g, (m) => add('GET', m[2]));
      scan(/\bjava\.get\(\s*(['"])((?:(?!\1).)*)\1\s*\)/g, (m) => add('GET', m[2]));
      scan(/\bjava\.post\(\s*(['"])((?:(?!\1).)*)\1\s*(?:,\s*(['"])((?:(?!\3).)*)\3\s*)?\)/g, (m) => add('POST', m[2], m[4]));
      for (const job of jobs.values()) {
        try { const res = await this.fetch(job.url, { method: job.method, body: job.body, baseUrl: this.id }); this._ajaxCache.set(job.key, { body: res.body, headers: res.headers || {}, status: res.status || 200, url: res.url || job.url }); }
        catch (e) { this.logs.push({ ajaxPrefetchFailed: job.url, error: String(e && e.message || e) }); }
      }
    })();
    return this._ajaxPromise;
  }
  async _prepare() { await this._ensureJsLib(); await this._ensureAjaxPrefetch(); }
  _trace(kind, data) { return this.engine.traceStep(kind, data); }
  async _runLoginCheck(res, url) {
    if (!this.def.loginCheckJs) return res;
    try {
      const strRes = { body: res.body, url: res.url || url, headers: res.headers || {}, status: res.status, bodyText: res.body, toString: () => res.body };
      const ctx = this._ctx(res.body, { baseUrl: url, stage: 'loginCheckJs' });
      const scope = ctx.scope(strRes, {});
      const v = evalScoped(this.def.loginCheckJs, scope, this._lib());
      if (typeof v === 'string' && v) this._trace('branch', { stage: 'loginCheckJs', label: 'loginCheckJs replaced response body' });
      if (typeof v === 'string' && v) return { ...res, body: v };
      if (v && typeof v === 'object' && typeof v.body === 'string') return { ...res, body: v.body, url: v.url || res.url };
    } catch (e) { this.engine.events.emit('source:error', { sourceId: this.id, stage: 'loginCheckJs', error: e }); }
    return res;
  }
  async fetch(rawUrl, opts = {}) {
    let urlText = String(rawUrl || '');
    // URL-level JS: full-URL @js: / <js> forms produce the real URL.
    if (urlText.trim().startsWith('@js:')) { const ctx = this._ctx('', { stage: 'url' }); urlText = ctx.getString('', urlText.trim()); }
    const { url, option } = parseUrlOption(urlText);
    let finalUrl = resolveUrl(opts.baseUrl || this.id, url);
    const headers = { ...this.def.headers, ...(opts.headers || {}) };
    let method = opts.method || 'GET', body = opts.body, charset = opts.charset;
    if (option) {
      if (option.headers) { const h = typeof option.headers === 'object' ? option.headers : parseLooseObject(option.headers); for (const [k, v] of Object.entries(h)) headers[k] = String(v); }
      if (option.method) method = String(option.method).toUpperCase();
      if (option.charset) charset = option.charset;
      if (option.body !== undefined) body = typeof option.body === 'object' ? JSON.stringify(option.body) : String(option.body);
      if (option.bodyJs) { const ctx = this._ctx('', { baseUrl: finalUrl, stage: 'url' }); const v = evalScoped(String(option.bodyJs), ctx.scope(finalUrl, {}), this._lib()); if (v != null) body = typeof v === 'object' ? JSON.stringify(v) : String(v); }
      if (option.js) { const ctx = this._ctx('', { baseUrl: finalUrl, stage: 'url' }); const v = evalScoped(String(option.js), ctx.scope(finalUrl, {}), this._lib()); if (typeof v === 'string' && v) finalUrl = resolveUrl(this.id, v); }
      if (option.webView) this.engine.events.emit('source:unsupported', { sourceId: this.id, feature: 'UrlOption.webView (fetched without WebView)' });
    }
    if (opts.charset) charset = opts.charset;
    // Template-residue guard (B176): a final URL still carrying
    // '{{' or '}}' means a template segment never evaluated.
    // Sending it produces a nonsense request (the B174 Jiujiu
    // shape: script text as URL, DNS failure on the base host).
    // Fail loudly with a classifiable error instead.
    if (finalUrl.includes('{{') || finalUrl.includes('}}')) {
      this.engine.events.emit('source:unsupported', { sourceId: this.id, feature: 'url-template-residue' });
      throw new NovelError(ERR.TEMPLATE, 'URL template was not fully evaluated: ' + finalUrl, { sourceId: this.id });
    }
    const res = await this.engine.requests.request(finalUrl, { method, headers, body, charset, timeout: opts.timeout, task: opts.task });
    return this._runLoginCheck(res, finalUrl);
  }
  _renderUrl(tpl, vars) {
    let t = String(tpl || '');
    if (t.trim().startsWith('@js:') || /<js>[\s\S]*<\/js>/.test(t)) { const ctx = this._ctx('', { ...vars, stage: 'url' }); const v = ctx.getString('', t, vars); return v; }
    // Two phases, mirroring Legado's AnalyzeUrl/makeUpRule:
    //  1. renderTemplate substitutes the simple segments ({{key}},
    //     {{page}}, arithmetic over them) WITHOUT JS evaluation —
    //     hosts may install a custom jsEvaluator (setJsEvaluator)
    //     that must only ever see real rule JS, never a bare
    //     variable name (pinned by tests/p0-jsparser P0.3).
    //  2. Any {{...}} still standing afterwards is a complex JS
    //     segment — up to a full {{(function(){...})()}} whose
    //     java.ajax probes pick the real address (B174 Jiujiu) —
    //     and is evaluated by assembling on the parser directly
    //     (not via getString), so the UrlOption JSON's single
    //     braces and '&' are never mistaken for rule syntax.
    // The returned string is NOT resolved here: fetch() splits
    // the UrlOption first and resolves after — resolving first
    // would percent-encode the option's braces and destroy the
    // ',{' marker (B174 22k search).
    const rendered = renderTemplate(t, vars);
    if (!rendered.includes('{{')) return rendered;
    const ctx = this._ctx('', { ...vars, stage: 'url' });
    return ctx._assembleTemplates('', rendered, vars);
  }
  // extra._label (e.g. 'ruleToc.chapterName') tags the trace steps produced
  // while evaluating this field; it is stripped before reaching the parser.
  _field(ctx, el, rule, extra = {}) {
    if (extra && extra._label) {
      const { _label, _stage, ...rest } = extra;
      const prev = ctx.traceLabel; ctx.traceLabel = _label;
      // Bare extractors (text/href/...) are served by a fast path that never
      // reaches LegadoContext, so no rule step is produced there. If the
      // inner call produced no step, emit one here to keep the field visible.
      const traceCol = this.engine._trace;
      const before = traceCol ? traceCol.steps.length : -1;
      const t0 = Date.now();
      try {
        const v = this._fieldInner(ctx, el, rule, rest);
        if (traceCol && rule && traceCol.steps.length === before) this._trace('rule', { stage: ctx.traceStage, label: _label, rule: String(rule), outputSummary: v, durationMs: Date.now() - t0 });
        return v;
      } finally { ctx.traceLabel = prev; }
    }
    return this._fieldInner(ctx, el, rule, extra);
  }
  _fieldInner(ctx, el, rule, extra = {}) {
    if (!rule) return '';
    if (el != null && typeof el === 'object' && el.type !== 'element') {
      const v = ctx.getString(JSON.stringify(el), rule, extra);
      return v;
    }
    if (el != null && typeof el === 'object' && el.type === 'element') {
      // Standalone field rules are written with the
      // extractor's '@' ('@text', '@href'); the bare-word
      // fast path must see through it or every chapter in
      // an HTML toc comes back untitled and unlinked.
      const bare = String(rule).trim().replace(/^@/, '');
      if (/^(text|textnodes|html|owntext|all)$/i.test(bare)) return bare.toLowerCase() === 'html' || bare.toLowerCase() === 'all' ? htmlOf(el) : textOf(el).trim();
      if (/^(href|src|alt|title|content|value)$/i.test(bare)) return el.attrs?.[bare.toLowerCase()] || '';
      return ctx.getString(htmlOf(el), rule, extra);
    }
    return ctx.getString(el == null ? '' : String(el), rule, extra);
  }
  _mapBook(ctx, el, rules, baseUrl, extra = {}) {
    const stage = extra._stage || 'rule';
    const f = (key) => this._field(ctx, el, rules[key], { ...extra, _label: stage + '.' + key });
    const title = f('name');
    if (!title) return null;
    let bookUrl = f('bookUrl');
    bookUrl = bookUrl ? resolveUrl(baseUrl, bookUrl) : baseUrl;
    const kind = f('kind');
    const book = {
      id: encodeId(this.id, bookUrl), title: cleanTitle(title), author: f('author'), cover: '',
      description: f('intro'), sourceId: this.id, sourceName: this.name, url: bookUrl,
      latestChapter: f('lastChapter'), updateTime: f('updateTime'), tags: kind ? kind.split(/[,，/、\s]+/).filter(Boolean) : [],
      kind, wordCount: f('wordCount'), metadata: { priority: this.priority },
    };
    const cover = f('coverUrl'); book.cover = cover ? resolveUrl(baseUrl, cover) : '';
    return book;
  }
  async _listPage(url, rules, vars, stage = 'ruleSearch') {
    const res = await this.fetch(url, { baseUrl: this.id });
    const ctx = this._ctx(res.body, { ...vars, stage });
    const prevLabel = ctx.traceLabel; ctx.traceLabel = stage + '.bookList';
    let els;
    try { els = ctx.getElements(res.body, rules.bookList, vars); }
    finally { ctx.traceLabel = prevLabel; }
    const books = [];
    for (const el of els) { const b = this._mapBook(ctx, el, rules, res.url || url, { ...vars, _stage: stage }); if (b) books.push(b); }
    return books;
  }
  async search(keyword, options = {}) {
    this._assertExecutable('search');
    this._trace('stage', { stage: 'search', label: this.name + ' search "' + keyword + '"' });
    this.stats.searches++; this.stats.lastUsed = Date.now();
    if (this.def.custom) {
      if (typeof this.def.custom.search !== 'function') throw new NovelError(ERR.UNSUPPORTED, 'Custom source has no search()');
      const items = await this.def.custom.search(keyword, options);
      return (items || []).map(b => this._normalizeCustomBook(b));
    }
    if (!this.def.searchUrl) return [];
    await this._prepare();
    if (this.def.ruleSearch.checkKeyWord) { const probe = await this._listPage(this._renderUrl(this.def.searchUrl, { key: this.def.ruleSearch.checkKeyWord, page: 1 }), this.def.ruleSearch, { key: this.def.ruleSearch.checkKeyWord, page: 1 }); if (!probe.length) this.engine.events.emit('source:error', { sourceId: this.id, stage: 'checkKeyWord', error: new Error('checkKeyWord returned no results') }); }
    const url = this._renderUrl(this.def.searchUrl, { key: keyword, page: options.page || 1 });
    const books = await this._listPage(url, this.def.ruleSearch, { key: keyword, page: options.page || 1 });
    if (this.def.bookUrlPattern) { try { const re = new RegExp(this.def.bookUrlPattern); for (const b of books) b.metadata.directInfo = re.test(b.url); } catch (e) { debugLog('bookUrlPattern invalid in search', e); } }
    return books;
  }
  _normalizeCustomBook(b) {
    const url = b.url || b.bookUrl || b.id || '';
    return { id: b.id && String(b.id).includes(':') ? b.id : encodeId(this.id, url), title: b.title || b.name || '', author: b.author || '', cover: b.cover || b.coverUrl || '', description: b.description || b.intro || '', sourceId: this.id, sourceName: this.name, url, latestChapter: b.latestChapter || b.lastChapter || '', updateTime: b.updateTime || '', tags: b.tags || [], kind: b.kind || '', wordCount: b.wordCount || '', metadata: b.metadata || {} };
  }
  exploreCategories() {
    if (this.def.custom) return this.def.custom.exploreCategories ? this.def.custom.exploreCategories() : [];
    const raw = this.def.exploreUrl;
    if (!raw) return [];
    const trimmed = raw.trim();
    if (trimmed.startsWith('@js:') || trimmed.startsWith('<js>')) {
      const ctx = this._ctx('', { stage: 'ruleExplore' });
      const v = ctx.getString('', trimmed);
      return parseCategories(v, raw);
    }
    if (trimmed.startsWith('[')) { try { const arr = JSON.parse(trimmed); return arr.map(c => ({ title: String(c.title || c.name || ''), url: String(c.url || ''), type: c.type, style: c.style, chars: c.chars, action: c.action, viewName: c.viewName })).filter(c => c.title); } catch (e) { return []; } }
    return parseCategories(trimmed, raw);
  }
  async explore(category, options = {}) {
    this._assertExecutable('explore');
    this._trace('stage', { stage: 'explore', label: this.name + ' explore "' + (category && category.title || '') + '"' });
    if (this.def.custom) { if (typeof this.def.custom.explore !== 'function') throw new NovelError(ERR.UNSUPPORTED, 'Custom source has no explore()'); const items = await this.def.custom.explore(category, options); return (items || []).map(b => this._normalizeCustomBook(b)); }
    await this._prepare();
    const rules = Object.keys(this.def.ruleExplore).length ? this.def.ruleExplore : this.def.ruleSearch;
    if (!rules.bookList) return [];
    const page = options.page || 1;
    const url = this._renderUrl(category.url, { page, key: '' });
    return this._listPage(url, rules, { page }, 'ruleExplore');
  }
  async bookInfo(item) {
    this._assertExecutable('bookInfo');
    this._trace('stage', { stage: 'bookInfo', label: this.name + ' bookInfo ' + (item.url || '') });
    if (this.def.custom) { if (typeof this.def.custom.bookInfo !== 'function') return item; const b = await this.def.custom.bookInfo(item); return { ...item, ...this._normalizeCustomBook({ ...b, url: (b && (b.url || b.bookUrl)) || item.url }), tocUrl: (b && b.tocUrl) || item.url }; }
    await this._prepare();
    const res = await this.fetch(item.url, { baseUrl: item.url });
    let body = res.body;
    const rules = this.def.ruleBookInfo;
    const ctx = this._ctx(body, { baseUrl: res.url || item.url, book: item, stage: 'ruleBookInfo' });
    const f = (key) => { const prev = ctx.traceLabel; ctx.traceLabel = 'ruleBookInfo.' + key; try { return ctx.getString(body, rules[key], { book: item }); } finally { ctx.traceLabel = prev; } };
    if (rules.init) {
      try {
        // Batch 183: init selects the element the remaining
        // fields are read from, so it must be evaluated as
        // an element, not a string: getString stringifies
        // an object result to '[object Object]', silently
        // emptying every init-scoped field (name/author
        // fell back to the search item, masking it) while
        // tocUrl — no fallback — came out with its
        // {{templates}} unresolved (the Mangacopy
        // '/book//volumes' 404). The string form remains
        // as the fallback for inits that match no element.
        const prevLabel = ctx.traceLabel; ctx.traceLabel = 'ruleBookInfo.init';
        let els = null;
        try { els = ctx.getElements(body, rules.init, { book: item }); } finally { ctx.traceLabel = prevLabel; }
        if (els && els.length) body = els[0];
        else { const v = f('init'); if (v) body = v; }
      } catch (e) { this.engine.events.emit('source:error', { sourceId: this.id, stage: 'ruleBookInfo.init', error: e }); }
    }
    let tocUrl = f('tocUrl');
    tocUrl = tocUrl ? resolveUrl(res.url || item.url, tocUrl) : item.url;
    this._tocUrls.set(item.url, tocUrl);
    const kind = f('kind');
    const enriched = {
      ...item,
      title: f('name') || item.title, author: f('author') || item.author,
      cover: f('coverUrl') ? resolveUrl(res.url || item.url, f('coverUrl')) : item.cover,
      description: f('intro') || item.description, kind: kind || item.kind,
      tags: kind ? kind.split(/[,，/、\s]+/).filter(Boolean) : item.tags,
      latestChapter: f('lastChapter') || item.latestChapter, wordCount: f('wordCount') || item.wordCount,
      updateTime: f('updateTime') || item.updateTime, tocUrl,
      metadata: { ...(item.metadata || {}), downloadUrls: f('downloadUrls'), canReName: rules.canReName ? f('canReName') : '' },
    };
    return enriched;
  }
  async chapters(item) {
    this._assertExecutable('chapters');
    this._trace('stage', { stage: 'chapters', label: this.name + ' chapters ' + (item.url || '') });
    if (this.def.custom) { if (typeof this.def.custom.chapters !== 'function') throw new NovelError(ERR.UNSUPPORTED, 'Custom source has no chapters()'); const chs = await this.def.custom.chapters(item); return (chs || []).map((c, i) => ({ id: encodeId(this.id, c.url || ''), bookId: item.id, title: c.title || '', index: i, url: resolveUrl(this.id, c.url || ''), sourceId: this.id, isVip: !!c.isVip, webView: !!c.webView, metadata: {} })); }
    await this._prepare();
    // ruleToc.preUpdateJs (D7): runs before the toc fetch with `book` bound.
    // The script may mutate book in place (book.tocUrl = ...) or return an
    // object whose fields are merged into the book. Failures are reported
    // and never block the toc fetch (same policy as loginCheckJs).
    if (this.def.ruleToc.preUpdateJs) {
      const beforeToc = item.tocUrl;
      try {
        const ctx = this._ctx('', { baseUrl: item.url, book: item, stage: 'ruleToc' });
        const v = evalScoped(this.def.ruleToc.preUpdateJs, ctx.scope(item, { book: item }), this._lib());
        if (v && typeof v === 'object') {
          const merged = { ...item };
          if (v.title || v.name) merged.title = v.title || v.name;
          if (v.author) merged.author = v.author;
          if (v.kind) merged.kind = v.kind;
          if (v.cover || v.coverUrl) merged.cover = v.cover || v.coverUrl;
          if (v.description || v.intro) merged.description = v.description || v.intro;
          if (v.latestChapter || v.lastChapter) merged.latestChapter = v.latestChapter || v.lastChapter;
          if (v.wordCount) merged.wordCount = v.wordCount;
          if (v.tocUrl) merged.tocUrl = resolveUrl(item.url, String(v.tocUrl));
          item = merged;
        }
        if (item.tocUrl && item.tocUrl !== beforeToc) this._tocUrls.set(item.url, item.tocUrl);
      } catch (e) { this.engine.events.emit('source:error', { sourceId: this.id, stage: 'ruleToc.preUpdateJs', error: e }); }
    }
    let tocUrl = this._tocUrls.get(item.url) || item.tocUrl || null;
    if (!tocUrl) { const info = await this.bookInfo(item); tocUrl = info.tocUrl; }
    const maxPages = this.engine.config.get('maxTocPages') || 50;
    const seen = new Set(); const chapters = []; let pageUrl = tocUrl; let pageBody = null; let pages = 0;
    while (pageUrl && pages < maxPages) {
      if (seen.has(pageUrl)) break; seen.add(pageUrl); pages++;
      let body, base;
      if (pageBody != null) { body = pageBody; base = pageUrl; pageBody = null; } else { const res = await this.fetch(pageUrl, { baseUrl: tocUrl }); body = res.body; base = res.url || pageUrl; }
      const ctx = this._ctx(body, { baseUrl: base, book: item, stage: 'ruleToc' });
      const rules = this.def.ruleToc;
      const prevLabel = ctx.traceLabel; ctx.traceLabel = 'ruleToc.chapterList';
      let els;
      try { els = ctx.getElements(body, rules.chapterList, { book: item }); }
      finally { ctx.traceLabel = prevLabel; }
      for (const el of els) {
        let title = this._field(ctx, el, rules.chapterName, { book: item, _label: 'ruleToc.chapterName' });
        let cUrl = this._field(ctx, el, rules.chapterUrl, { book: item, _label: 'ruleToc.chapterUrl' });
        cUrl = cUrl ? resolveUrl(base, cUrl) : '';
        if (!cUrl) continue;
        title = cleanTitle(title) || cUrl;
        if (rules.formatJs) { try { const idx = chapters.length; const scope = ctx.scope(title, { book: item }); scope.index = idx; scope.gInt = idx; const v = evalScoped(rules.formatJs, { ...scope, result: title, index: idx, gInt: idx, title }, this._lib()); if (v) title = String(v); } catch (e) { debugLog('ruleToc.formatJs error', e); } }
        chapters.push({ id: encodeId(this.id, cUrl), bookId: item.id, title, index: chapters.length, url: cUrl, sourceId: this.id, isVip: truthy(this._field(ctx, el, rules.isVip, { book: item, _label: 'ruleToc.isVip' })), isPay: truthy(this._field(ctx, el, rules.isPay, { book: item, _label: 'ruleToc.isPay' })), updateTime: rules.updateTime ? this._field(ctx, el, rules.updateTime, { book: item, _label: 'ruleToc.updateTime' }) : '', webView: false, metadata: {} });
      }
      let next = '';
      if (rules.nextTocUrl) { const pl = ctx.traceLabel; ctx.traceLabel = 'ruleToc.nextTocUrl'; try { next = ctx.getString(body, rules.nextTocUrl, { book: item }); } finally { ctx.traceLabel = pl; } }
      pageUrl = next ? resolveUrl(base, next) : null;
      if (pageUrl && !seen.has(pageUrl)) this._trace('branch', { stage: 'ruleToc', label: 'follow nextTocUrl (page ' + (pages + 1) + ')', outputSummary: pageUrl });
    }
    return dedupeBy(chapters, c => c.url).map((c, i) => ({ ...c, index: i }));
  }
  async content(item, chapter) {
    // Reason for the wrapper: a raw "Stack Overflow" from the JS engine
    // says nothing about which source, chapter or rule produced it. When
    // (and only when) the failure is a stack overflow, rethrow it with
    // that context attached, so the next occurrence is diagnosable at a
    // glance and the needed evidence (the raw chapter HTML) is named.
    const stats = { bytes: 0, pages: 0 };
    try { return await this._contentInner(item, chapter, stats); }
    catch (e) {
      const msg = String((e && e.message) || e || '');
      const isStack = (typeof RangeError !== 'undefined' && e instanceof RangeError) || /stack overflow/i.test(msg);
      if (!isStack) throw e;
      const rule = String((this.def.ruleContent && this.def.ruleContent.content) || '');
      const err = new NovelError((e && e.code) || ERR.PARSE,
        'Stack overflow while loading chapter content — source: ' + this.name + ' (' + this.id + ')'
        + ', chapter: ' + ((chapter && chapter.url) || '')
        + ', ruleContent.content: ' + rule.slice(0, 200)
        + ', page size: ' + stats.bytes + ' chars (page ' + stats.pages + ')'
        + '. The raw chapter HTML is needed to confirm the cause.',
        { cause: e, details: { sourceId: this.id, sourceName: this.name, chapterUrl: (chapter && chapter.url) || '', rule, pageChars: stats.bytes, pages: stats.pages } });
      try { if (this.engine && this.engine.events) this.engine.events.emit('source:error', { sourceId: this.id, stage: 'content', error: err }); } catch (_) { /* reporting must not mask the error */ }
      throw err;
    }
  }
  async _contentInner(item, chapter, stats) {
    this._assertExecutable('content');
    this._trace('stage', { stage: 'content', label: this.name + ' content ' + (chapter.url || '') });
    if (this.def.custom) { if (typeof this.def.custom.content !== 'function') throw new NovelError(ERR.UNSUPPORTED, 'Custom source has no content()'); const raw = await this.def.custom.content(item, chapter); return normalizeContentResult(this, item, chapter, typeof raw === 'string' ? raw : (raw.text || raw.content || ''), typeof raw === 'string' ? null : raw.html); }
    await this._prepare();
    const maxPages = this.engine.config.get('maxContentPages') || 100;
    const seen = new Set(); let pageUrl = chapter.url; let htmlParts = []; let pages = 0; let contentTitle = ''; let lastBody = '';
    const rules = this.def.ruleContent;
    // ruleContent.webJs: executed only when the host injected a webJsHandler
    // (engine option `webJsHandler(url, html, sourceId)` — e.g. a WebView in
    // the host app). Without a handler it stays honestly unsupported.
    const webJsHandler = this.engine.webJsHandler || (this.engine.config ? this.engine.config.get('webJsHandler') : null);
    if (rules.webJs && typeof webJsHandler !== 'function') this.engine.events.emit('source:unsupported', { sourceId: this.id, feature: 'ruleContent.webJs (no host webJsHandler injected)' });
    if (rules.sourceRegex) this.engine.events.emit('source:unsupported', { sourceId: this.id, feature: 'ruleContent.sourceRegex' });
    while (pageUrl && pages < maxPages) {
      if (seen.has(pageUrl)) break; seen.add(pageUrl); pages++;
      const res = await this.fetch(pageUrl, { baseUrl: chapter.url });
      lastBody = res.body;
      if (stats) { stats.bytes = (res.body || '').length; stats.pages = pages; }
      const ctx = this._ctx(res.body, { baseUrl: res.url || pageUrl, book: item, chapter, stage: 'ruleContent' });
      const labeled = (label, fn) => { const prev = ctx.traceLabel; ctx.traceLabel = label; try { return fn(); } finally { ctx.traceLabel = prev; } };
      const part = labeled('ruleContent.content', () => ctx.getString(res.body, rules.content, { book: item, chapter }));
      if (part) htmlParts.push(part);
      if (rules.title && !contentTitle) { try { contentTitle = labeled('ruleContent.title', () => ctx.getString(res.body, rules.title, { book: item, chapter })); } catch (e) { debugLog('ruleContent.title error', e); } }
      let next = rules.nextContentUrl ? labeled('ruleContent.nextContentUrl', () => ctx.getString(res.body, rules.nextContentUrl, { book: item, chapter })) : '';
      pageUrl = next ? resolveUrl(res.url || pageUrl, next) : null;
      if (pageUrl && !seen.has(pageUrl)) this._trace('branch', { stage: 'ruleContent', label: 'follow nextContentUrl (page ' + (pages + 1) + ')', outputSummary: pageUrl });
    }
    let fullHtml = htmlParts.join('\n');
    if (rules.webJs && typeof webJsHandler === 'function') {
      try { const out = await webJsHandler(chapter.url, lastBody, this.id); if (typeof out === 'string' && out) { fullHtml = out; this._trace('branch', { stage: 'ruleContent', label: 'ruleContent.webJs applied via host webJsHandler', outputSummary: out }); } }
      catch (e) { this.engine.events.emit('source:error', { sourceId: this.id, stage: 'ruleContent.webJs', error: e }); }
    }
    // Batch 184: leaving the loop because the page cap hit
    // while a next page was still pending means the chapter
    // is TRUNCATED — say so on the result instead of letting
    // the host present a partial chapter as complete.
    const hitPageCap = pages >= maxPages && !!pageUrl;
    const result = normalizeContentResult(this, item, chapter, null, fullHtml);
    if (hitPageCap) result.metadata.truncated = true;
    if (rules.replaceRegex) {
      if (rules.replaceRegex.includes('##')) result.text = applyReplaceRegex(result.text, rules.replaceRegex);
      else { try { const re = new RegExp(rules.replaceRegex, 'g'); result.text = result.text.replace(re, ''); } catch (e) { debugLog('ruleContent.replaceRegex invalid', e); } }
      result.blocks = textToBlocks(result.text);
      result.content = result.text;
    }
    applyMediaType(this, result, fullHtml, chapter.url);
    if (contentTitle) result.metadata.contentTitle = contentTitle;
    return result;
  }
  // loginUi data layer: the field list a host needs to render a login form.
  // Rendering stays with the host; values come back via submitLoginForm().
  getLoginForm() { return parseLoginUi(this.def.loginUi); }
  async submitLoginForm(values = {}) {
    await this._prepare();
    const merged = { ...(this.engine.loginInfo ? this.engine.loginInfo(this.id) : {}), ...values };
    if (this.engine.setLoginInfo) this.engine.setLoginInfo(this.id, merged);
    const loginUrl = (this.def.loginUrl || '').trim();
    if (!loginUrl) return { stored: true, hookExecuted: false };
    const isScript = loginUrl.startsWith('@js:') || loginUrl.includes('<js>') || !/^https?:\/\//i.test(loginUrl);
    if (!isScript) return { stored: true, hookExecuted: false, needsWebLogin: true, url: loginUrl };
    let code = loginUrl;
    if (code.startsWith('@js:')) code = code.slice(4);
    const tag = code.match(/<js>([\s\S]*?)<\/js>/); if (tag) code = tag[1];
    try {
      const ctx = this._ctx('', { baseUrl: this.id, stage: 'login' });
      evalScoped(code + '\n; if (typeof login === "function") login();', ctx.scope('', {}), this._lib());
      return { stored: true, hookExecuted: true };
    } catch (e) { return { stored: true, hookExecuted: false, error: String(e && e.message || e) }; }
  }
  parseUrl(url) {
    if (!this.def.bookUrlPattern) return null;
    try { if (new RegExp(this.def.bookUrlPattern).test(url)) return { id: encodeId(this.id, url), title: '', author: '', cover: '', description: '', sourceId: this.id, sourceName: this.name, url, latestChapter: '', updateTime: '', tags: [], metadata: { direct: true } }; } catch (e) { debugLog('bookUrlPattern invalid in parseUrl', e); }
    return null;
  }
  async test(keyword) {
    const steps = [];
    try { const results = await this.search(keyword || this.def.ruleSearch.checkKeyWord || '小说', {}); steps.push({ step: 'search', ok: true, count: results.length }); if (!results.length) return { ok: false, sourceId: this.id, steps, error: 'search returned no results' };
      const book = await this.bookInfo(results[0]); steps.push({ step: 'bookInfo', ok: !!book.title, title: book.title });
      const chs = await this.chapters(book); steps.push({ step: 'chapters', ok: chs.length > 0, count: chs.length }); if (!chs.length) return { ok: false, sourceId: this.id, steps, error: 'no chapters' };
      const content = await this.content(book, chs[0]); steps.push({ step: 'content', ok: !!(content.text || content.blocks.length), length: (content.text || '').length });
      return { ok: steps.every(s => s.ok), sourceId: this.id, steps };
    } catch (e) { steps.push({ step: 'error', ok: false, error: String(e.message || e) }); return { ok: false, sourceId: this.id, steps, error: String(e.message || e) }; }
  }
}
function truthy(v) { if (v === true) return true; const s = String(v || '').toLowerCase(); return s === 'true' || s === '1' || s === 'yes'; }
// Parse a Legado loginUi definition (JSON string or array) into host-renderable
// field descriptors: [{name, type:'text'|'password'|'select'|'button', chars?, action?, default?}]
function parseLoginUi(loginUi) {
  if (!loginUi) return [];
  let arr = loginUi;
  if (typeof loginUi === 'string') {
    const t = loginUi.trim(); if (!t) return [];
    try { arr = JSON.parse(t); } catch (e) { try { arr = JSON.parse(literalToJson(t)); } catch (e2) { return []; } }
  }
  if (!Array.isArray(arr)) return [];
  return arr.map(f => {
    if (!f || typeof f !== 'object' || !f.name) return null;
    const rawType = String(f.type || 'text').toLowerCase();
    const type = ['text', 'password', 'select', 'button'].includes(rawType) ? rawType : 'text';
    const out = { name: String(f.name), type };
    if (f.chars != null) out.chars = Array.isArray(f.chars) ? f.chars.map(String) : String(f.chars).split(/[,，]/).map(s => s.trim()).filter(Boolean);
    if (f.action) out.action = String(f.action);
    if (f.default != null) out.default = String(f.default);
    return out;
  }).filter(Boolean);
}
// bookSourceType-driven content shaping:
//  type 2 (image/manga): the chapter is an ordered image list — images come
//    from <img> in the content HTML, result.images, or a plain-text list of
//    image URLs (one per line), in document order.
//  type 1 (audio): the content rule resolves to an audio URL (direct link,
//    <audio>/<source> src) — returned as a single audio block.
const AUDIO_EXT_RE = /\.(mp3|m4a|aac|ogg|opus|wav|flac)(\?\S*)?$/i;
function applyMediaType(adapter, result, html, chapterUrl) {
  const type = adapter.def.type;
  if (type === 2) {
    const urls = []; const push = (u) => { const v = u ? resolveUrl(chapterUrl || adapter.id, String(u).trim()) : ''; if (v && !urls.includes(v)) urls.push(v); };
    for (const u of result.images || []) push(u);
    for (const tok of String(result.text || '').split(/\s+/)) if (/^https?:\/\/\S+$/i.test(tok)) push(tok);
    if (urls.length) {
      result.blocks = urls.map(u => ({ type: 'image', url: u, headers: { ...adapter.def.headers } }));
      result.images = urls; result.text = ''; result.content = '';
    }
    result.metadata.mediaType = 'image';
  } else if (type === 1) {
    let audio = '';
    const tag = String(html || '').match(/<(?:audio|source)[^>]+src=["']([^"']+)["']/i);
    if (tag) audio = tag[1];
    if (!audio) { const m = String(result.text || '').match(/https?:\/\/\S+?\.(?:mp3|m4a|aac|ogg|opus|wav|flac)(?:\?\S*)?/i); if (m) audio = m[0]; }
    if (!audio && /^\s*https?:\/\/\S+\s*$/i.test(result.text || '')) audio = String(result.text).trim();
    if (audio) {
      const url = resolveUrl(chapterUrl || adapter.id, audio);
      result.blocks = [{ type: 'audio', url, headers: { ...adapter.def.headers } }];
      result.images = []; result.text = ''; result.content = '';
      result.metadata.mediaType = 'audio';
    }
  }
  return result;
}
function parseCategories(text, raw) {
  const t = String(text || '').trim();
  if (!t) return [];
  if (t.startsWith('[')) { try { return JSON.parse(t).map(c => ({ title: String(c.title || c.name || ''), url: String(c.url || ''), type: c.type, style: c.style, chars: c.chars, action: c.action, viewName: c.viewName })).filter(c => c.title); } catch (e) { debugLog('explore categories JSON parse failed', e); } }
  const parts = t.split(/&&|\n/).map(x => x.trim()).filter(Boolean);
  const out = [];
  for (const part of parts) { const idx = part.indexOf('::'); if (idx > 0) out.push({ title: part.slice(0, idx).trim(), url: part.slice(idx + 2).trim() }); else out.push({ title: part, url: '' }); }
  return out.filter(c => c.title);
}
function textToBlocks(text) { return String(text || '').split(/\n{2,}|\n/).map(l => l.trim()).filter(Boolean).map(t => ({ type: 'text', text: t })); }
function normalizeContentResult(adapter, item, chapter, text, html) {
  const rawHtml = html || '';
  let cleanText = text != null ? text : cleanContent(rawHtml);
  const blocks = []; const images = [];
  if (rawHtml) {
    const imgRe = /<img[^>]+src=["']([^"']+)["'][^>]*>/gi; let last = 0, m; let found = false;
    while ((m = imgRe.exec(rawHtml)) !== null) { found = true; const before = cleanContent(rawHtml.slice(last, m.index)); for (const b of textToBlocks(before)) blocks.push(b); const src = resolveUrl(chapter.url, m[1]); images.push(src); blocks.push({ type: 'image', url: src, headers: { ...adapter.def.headers } }); last = m.index + m[0].length; }
    if (found) { const after = cleanContent(rawHtml.slice(last)); for (const b of textToBlocks(after)) blocks.push(b); }
  }
  if (!blocks.length) for (const b of textToBlocks(cleanText)) blocks.push(b);
  if (!cleanText && images.length) cleanText = '';
  return { id: chapter.id, bookId: item.id, chapterId: chapter.id, title: chapter.title, content: cleanText, text: cleanText, html: rawHtml, blocks, images, sourceId: adapter.id, metadata: {} };
}
module.exports.default = SourceAdapter;

module.exports.ruleMap = ruleMap;
module.exports.parseHeaders = parseHeaders;
module.exports.normalizeForeign = normalizeForeign;
module.exports.detectSourceKind = detectSourceKind;
module.exports.normalizeSourceDef = normalizeSourceDef;
module.exports.parseSourceArray = parseSourceArray;
module.exports.SourceAdapter = SourceAdapter;
module.exports.parseLoginUi = parseLoginUi;
module.exports.applyMediaType = applyMediaType;
module.exports.parseCategories = parseCategories;
module.exports.textToBlocks = textToBlocks;
module.exports.normalizeContentResult = normalizeContentResult;

});
__define('src/source/SourceManager.js', function(module, exports, __require){
const { parseSourceArray, normalizeSourceDef } = __require('./SourceAdapter.js');
const { NovelError, ERR } = __require('../core/errors.js');
const { RemoteRepository } = __require('./RemoteRepository.js');
class SourceManager{
  constructor(engine){ this.engine=engine; this.registry=engine.sources; }
  register(source, opts){ return this.registry.register(source, opts); }
  registerMany(list, opts){ return this.registry.registerMany(list, opts); }
  importFromText(text, opts={}){ const defs=parseSourceArray(text); return this.registry.registerMany(defs, opts); }
  importFromObject(obj, opts={}){ const defs=Array.isArray(obj)?obj:[obj]; return this.registry.registerMany(defs, opts); }
  async importFromUrl(url, opts={}){ const res=await this.engine.requests.request(url, {headers:{Accept:'application/json,text/plain,*/*'}}); return this.importFromText(res.body, opts); }
  async importBatch(urls, opts={}){ const out={registered:[], failures:[]}; for(const url of urls||[]){ try{ const r=await this.importFromUrl(url, opts); out.registered.push(...r.registered); out.failures.push(...r.failures); }catch(e){ out.failures.push({url, error:String(e.message||e)}); } } return out; }
  get(id){ return this.registry.get(id); }
  list(opts){ return this.registry.infos(); }
  infos(){ return this.registry.infos(); }
  enable(id){ return this.registry.enable(id); }
  disable(id){ return this.registry.disable(id); }
  remove(id){ return this.registry.remove(id); }
  edit(id, patch){ return this.registry.edit(id, patch); }
  searchSources(q){ return this.registry.search(q); }
  validate(source){ const adapter=typeof source==='string'?this.registry.get(source):null; if(adapter) return this.registry.validator.validate(adapter.def); try{ return this.registry.validator.validate(normalizeSourceDef(source)); }catch(e){ return {valid:false, errors:[String(e.message||e)], warnings:[], unsupported:[]}; } }
  async testSource(id, keyword){ const a=this.registry.get(id); if(!a) throw new NovelError(ERR.SOURCE_NOT_FOUND, 'Source not found: '+id); const r=await a.test(keyword); a.errors.push(...(r.ok?[]:[{at:Date.now(), error:r.error||'test failed'}])); return r; }
  loginForm(id){ const a=this.registry.get(id); if(!a) throw new NovelError(ERR.SOURCE_NOT_FOUND, 'Source not found: '+id); return a.getLoginForm(); }
  async submitLoginForm(id, values){ const a=this.registry.get(id); if(!a) throw new NovelError(ERR.SOURCE_NOT_FOUND, 'Source not found: '+id); return a.submitLoginForm(values||{}); }
  async importRemote(url, opts={}){ return new RemoteRepository(this.engine).importFromUrl(url, opts); }
  backup(){ return JSON.stringify(this.registry.exportDefs(), null, 2); }
  restore(text){ return this.importFromText(text, {replace:true}); }
  stats(){ return this.registry.stats(); }
  async persist(){ return this.registry.persist(); }
  async loadPersisted(){ return this.registry.restore(); }
}
module.exports.default = SourceManager;

module.exports.SourceManager = SourceManager;

});
__define('src/source/SourceRegistry.js', function(module, exports, __require){
const { SourceAdapter, normalizeSourceDef } = __require('./SourceAdapter.js');
const { SourceValidator } = __require('./SourceValidator.js');
const { NovelError, ERR } = __require('../core/errors.js');
class SourceRegistry{
  constructor(engine){ this.engine=engine; this._map=new Map(); this.validator=new SourceValidator(); this.errors=[]; }
  register(input, opts={}){
    let def;
    try{ def=normalizeSourceDef(input); }catch(e){ if(opts.collectErrors){ this.errors.push({input: String(input&&input.bookSourceName||''), error:e}); return null; } throw e; }
    if(this._map.has(def.id) && !opts.replace) throw new NovelError(ERR.SOURCE_INVALID, 'Source already registered: '+def.id);
    const adapter=new SourceAdapter(def, this.engine);
    this._map.set(def.id, adapter);
    this.engine.events.emit('source:registered', {sourceId:def.id, name:def.name});
    return adapter;
  }
  registerMany(inputs, opts={}){ const out=[]; const failures=[]; for(const input of inputs||[]){ try{ const a=this.register(input, opts); if(a) out.push(a); }catch(e){ failures.push({name: input&&(input.bookSourceName||input.name)||'', error:String(e.message||e)}); } } return {registered: out, failures}; }
  unregister(id){ const ok=this._map.delete(id); if(ok) this.engine.events.emit('source:unregistered', {sourceId:id}); return ok; }
  get(id){ return this._map.get(id)||null; }
  has(id){ return this._map.has(id); }
  list(opts={}){ let arr=[...this._map.values()]; if(!opts.includeDisabled) arr=arr.filter(a=>a.enabled); return arr.sort((a,b)=> (b.priority-a.priority)|| (b.def.weight-a.def.weight)|| a.name.localeCompare(b.name)); }
  resolve(ids){ if(!ids||!ids.length) return this.list(); const out=[]; for(const id of ids){ const a=this._map.get(id); if(a&&a.enabled) out.push(a); } return out; }
  enable(id){ const a=this._require(id); a.setEnabled(true); return this.info(a); }
  disable(id){ const a=this._require(id); a.setEnabled(false); return this.info(a); }
  remove(id){ return this.unregister(id); }
  edit(id, patch){ const a=this._require(id); const merged={...a.def.raw, ...patch}; this.unregister(id); return this.register(merged); }
  search(query){ const q=String(query||'').toLowerCase(); return this.list({includeDisabled:true}).filter(a=> a.name.toLowerCase().includes(q)||a.def.group.toLowerCase().includes(q)||a.def.tags.some(t=>t.toLowerCase().includes(q))).map(a=>this.info(a)); }
  byTag(tag){ return this.list({includeDisabled:true}).filter(a=>a.def.tags.includes(tag)).map(a=>this.info(a)); }
  info(adapter){ const a=typeof adapter==='string'?this._require(adapter):adapter; return {id:a.id, name:a.name, kind:a.kind, executable:a.isExecutable, type:a.def.type, group:a.def.group, comment:a.def.comment, tags:a.def.tags, enabled:a.enabled, priority:a.priority, hasSearch:!!a.def.searchUrl||!!a.def.custom, hasExplore:!!a.def.exploreUrl, stats:a.stats, validation:this.validator.validate(a.def)}; }
  infos(){ return this.list({includeDisabled:true}).map(a=>this.info(a)); }
  stats(){ const all=this.list({includeDisabled:true}); return {total:all.length, enabled:all.filter(a=>a.enabled).length, disabled:all.filter(a=>!a.enabled).length, errors:this.errors.length}; }
  exportDefs(){ return this.list({includeDisabled:true}).map(a=>a.def.raw); }
  async persist(){ await this.engine.storage.setJSON('sources:defs', this.exportDefs()); }
  async restore(){ const defs=await this.engine.storage.getJSON('sources:defs', []); return this.registerMany(defs, {replace:true}); }
  _require(id){ const a=this._map.get(id); if(!a) throw new NovelError(ERR.SOURCE_NOT_FOUND, 'Source not found: '+id); return a; }
}
module.exports.default = SourceRegistry;

module.exports.SourceRegistry = SourceRegistry;

});
__define('src/source/SourceValidator.js', function(module, exports, __require){
// Validates a normalized (or raw) source definition. Never throws on shape
// surprises: malformed pieces become errors/warnings, not crashes.
const { detectSourceKind } = __require('./SourceAdapter.js');
const UNSUPPORTED_FEATURES = [
  { key: 'ruleReview', label: 'ruleReview (review rules)', support: 'unsupported' },
  { key: 'ruleContent.webJs', label: 'ruleContent.webJs (needs a host webJsHandler; runs when one is injected)', support: 'partial' },
  { key: 'ruleContent.sourceRegex', label: 'ruleContent.sourceRegex', support: 'unsupported' },
  { key: 'ruleContent.subContent', label: 'ruleContent.subContent', support: 'unsupported' },
  { key: 'loginUi', label: 'loginUi login form (data layer supported — fields/submit via sourceManager.loginForm/submitLoginForm; rendering is the host\u2019s job)', support: 'partial' },
  { key: 'eventListener', label: 'eventListener', support: 'unsupported' },
];
class SourceValidator {
  validate(def) {
    const errors = [], warnings = [], unsupported = [];
    if (!def || typeof def !== 'object') return { valid: false, kind: 'unknown', executable: false, errors: ['source definition is not an object'], warnings, unsupported };
    const kind = def.kind || detectSourceKind(def.raw || def);
    if (kind === 'webview-html') {
      // Well-formed but not executable by a rule engine: say so in exactly
      // one place instead of emitting misleading "rules are empty" warnings.
      unsupported.push({ feature: 'sourceKind:webview-html', label: 'WebView HTML page source (single html app, no rule surface)', support: 'unsupported' });
      warnings.push('WebView HTML page source: the rule engine cannot search/read it; a host must render its html page in a WebView');
      const raw0 = def.raw || def;
      if (!raw0.bookSourceName && !def.name) errors.push('missing bookSourceName');
      if (!raw0.bookSourceUrl && !def.id) errors.push('missing bookSourceUrl');
      return { valid: errors.length === 0, kind, executable: false, errors, warnings, unsupported };
    }
    const raw = def.raw || def;
    const url = def.id || raw.bookSourceUrl || '';
    const name = def.name || raw.bookSourceName || '';
    if (!name) errors.push('missing bookSourceName');
    if (!url) errors.push('missing bookSourceUrl');
    if (url && !/^https?:\/\//i.test(url) && !def.custom) warnings.push('bookSourceUrl is not an http(s) URL: ' + url);
    const type = def.type ?? raw.bookSourceType ?? 0;
    if (![0, 1, 2, 3].includes(Number(type))) warnings.push('unknown bookSourceType: ' + type);
    const hasSearch = !!(def.searchUrl || raw.searchUrl || def.custom);
    const ruleSearch = def.ruleSearch || raw.ruleSearch || {};
    if (hasSearch && !ruleSearch.bookList && !def.custom) warnings.push('searchUrl present but ruleSearch.bookList is empty');
    if (!hasSearch && !def.exploreUrl && !def.custom) warnings.push('no searchUrl, exploreUrl or custom implementation');
    const ruleToc = def.ruleToc || raw.ruleToc || {};
    if (!ruleToc.chapterList && !def.custom) warnings.push('ruleToc.chapterList is empty — chapters will fail');
    const ruleContent = def.ruleContent || raw.ruleContent || {};
    if (!ruleContent.content && !def.custom) warnings.push('ruleContent.content is empty — content will fail');
    for (const f of UNSUPPORTED_FEATURES) {
      const [section, field] = f.key.split('.');
      const rawVal = field ? (raw[section] && raw[section][field]) || (def[section] && def[section][field]) : raw[f.key] || def[f.key];
      const present = rawVal && (typeof rawVal !== 'object' || Object.keys(rawVal).length > 0) && String(rawVal).trim() !== '';
      if (present) unsupported.push({ feature: f.key, label: f.label, support: f.support });
    }
    if (raw.loginUrl && typeof raw.loginUrl === 'string' && raw.loginUrl.trim().startsWith('@js:')) unsupported.push({ feature: 'loginUrl(@js:)', label: 'JS-form loginUrl execution', support: 'partial' });
    if (raw.exploreUrl && Array.isArray(raw.exploreUrl)) unsupported.push({ feature: 'exploreUrl(array form)', label: 'exploreUrl array form', support: 'partial' });
    return { valid: errors.length === 0, kind, executable: true, errors, warnings, unsupported };
  }
}
module.exports.default = SourceValidator;

module.exports.UNSUPPORTED_FEATURES = UNSUPPORTED_FEATURES;
module.exports.SourceValidator = SourceValidator;

});
__define('src/source/YioveRepository.js', function(module, exports, __require){
const { parseSourceArray, detectSourceKind } = __require('./SourceAdapter.js');
// Yiove book-source repository (https://shuyuan.yiove.com).
// Real API (probed 2026-11-10): list GET {api}/shuyuan/book-sources?page=&page_size=
// detail GET {api}/shuyuan/book-source/{id} with origin_json = stringified source JSON.
// All network goes through the injected request function — tests never hit the network.
const YIOVE_API='https://shuyuan-api.yiove.com';
class YioveRepository{
  constructor(engine, opts={}){ this.engine=engine; this.apiBase=(opts.apiBase||YIOVE_API).replace(/\/$/,''); this.siteBase=opts.siteBase||'https://shuyuan.yiove.com'; }
  async _getJson(url){ const res=await this.engine.requests.request(url, {headers:{Accept:'application/json'}}); try{ return JSON.parse(res.body); }catch(e){ throw Object.assign(new Error('Yiove API did not return JSON: '+url), {code:'E_PARSE', cause:e}); } }
  async listBookSources(page=1, pageSize=20){
    const data=await this._getJson(`${this.apiBase}/shuyuan/book-sources?page=${page}&page_size=${pageSize}`);
    const items=(data.items||data.data||[]).map(it=>({id:String(it.id), name:it.name||'', url:it.url||'', description:it.description||'', isValid: it.is_valid!==false, createTime: it.create_time, viewTotal: it.view_total||0}));
    return {items, total: data.total||items.length, page: data.page||page, pageSize: data.size||pageSize, pages: data.pages||Math.ceil((data.total||items.length)/pageSize)};
  }
  async fetchBookSource(id){
    const data=await this._getJson(`${this.apiBase}/shuyuan/book-source/${encodeURIComponent(id)}`);
    if(!data||!data.origin_json) throw Object.assign(new Error('Yiove detail has no origin_json: '+id), {code:'E_PARSE'});
    const defs=parseSourceArray(data.origin_json);
    if(!defs.length) throw Object.assign(new Error('Yiove origin_json contained no source: '+id), {code:'E_PARSE'});
    return {detail:{id:String(data.id||id), name:data.name||'', url:data.url||'', isValid:data.is_valid!==false}, defs};
  }
  importUrlForPage(page, pageSize){ return `${this.siteBase}/import/book-sources/${page}-${pageSize}`; }
  importUrlForId(id){ return `${this.siteBase}/import/book-source/${id}`; }
  // Shared per-definition import logic for importPage / importByIds:
  // classify each def (webview-html and skipped types are reported, never
  // registered), register the rest, and accumulate per-item results.
  // `shape.includeName` / `shape.rejectedReason` preserve the two callers'
  // historical result shapes exactly.
  importDefs(id, name, defs, options={}, shape={}){
    const skipTypes=options.skipTypes||[3];
    const base=shape.includeName?{id, name}:{id};
    const out={imported:0, skipped:0, failed:0, results:[]};
    for(const def of defs){
      const type=parseInt(def.bookSourceType??0,10)||0;
      if(detectSourceKind(def)==='webview-html'){ out.results.push({...base, status:'skipped', reason:'webview-html source (single html page app, no rule surface): rule engine cannot execute it, host WebView only'}); out.skipped++; continue; }
      if(skipTypes.includes(type)){ out.results.push({...base, status:'skipped', reason:'bookSourceType '+type+' skipped (file/video)'}); out.skipped++; continue; }
      const reg=this.engine.sourceManager.registerMany([def], {replace:true});
      if(reg.registered.length){ const entry={...base, status:'imported', sourceId:reg.registered[0].id}; if(shape.includeName) entry.sourceName=reg.registered[0].name; out.results.push(entry); out.imported++; }
      else { out.results.push({...base, status:'failed', reason:(reg.failures[0]&&reg.failures[0].error)||shape.rejectedReason||'validator rejected'}); out.failed++; }
    }
    return out;
  }
  // Import one list page: fetch each item's detail and register it.
  // Default skipTypes is [3] only (file/video): type 1 (audio) and type 2
  // (image/manga) sources are imported and executed with media-shaped
  // content. Invalid/failed items are reported per-item, never fatal.
  async importPage(page=1, pageSize=20, options={}){
    const onlyValid=options.onlyValid!==false;
    const list=await this.listBookSources(page, pageSize);
    const results=[]; let imported=0, skipped=0, failed=0;
    for(const item of list.items){
      if(onlyValid && !item.isValid){ results.push({id:item.id, name:item.name, status:'skipped', reason:'is_valid=false in Yiove list'}); skipped++; continue; }
      try{
        const {defs}=await this.fetchBookSource(item.id);
        const r=this.importDefs(item.id, item.name, defs, options, {includeName:true, rejectedReason:'validator rejected'});
        results.push(...r.results); imported+=r.imported; skipped+=r.skipped; failed+=r.failed;
      }catch(e){ results.push({id:item.id, name:item.name, status:'failed', reason:String(e.message||e)}); failed++; }
    }
    return {page, pageSize, total:list.total, imported, skipped, failed, results};
  }
  async importByIds(ids, options={}){ const results=[]; let imported=0, skipped=0, failed=0;
    for(const id of ids||[]){
      try{
        const {defs}=await this.fetchBookSource(id);
        const r=this.importDefs(id, undefined, defs, options, {includeName:false, rejectedReason:'rejected'});
        results.push(...r.results); imported+=r.imported; skipped+=r.skipped; failed+=r.failed;
      }catch(e){ results.push({id, status:'failed', reason:String(e.message||e)}); failed++; }
    }
    return {imported, skipped, failed, results};
  }
}
module.exports.default = YioveRepository;

module.exports.YIOVE_API = YIOVE_API;
module.exports.YioveRepository = YioveRepository;

});
__define('src/storage/MemoryStorage.js', function(module, exports, __require){
class MemoryStorage{
  constructor(){ this._m=new Map(); }
  async get(key){ return this._m.has(key)?this._m.get(key):null; }
  async set(key, value){ this._m.set(key, value); }
  async delete(key){ this._m.delete(key); }
  async keys(prefix=''){ return [...this._m.keys()].filter(k=>k.startsWith(prefix)); }
  async clear(){ this._m.clear(); }
}
module.exports.default = MemoryStorage;

module.exports.MemoryStorage = MemoryStorage;

});
__define('src/storage/StorageAdapter.js', function(module, exports, __require){
const { MemoryStorage } = __require('./MemoryStorage.js');
const { NovelError, ERR } = __require('../core/errors.js');
// Uniform storage adapter: wraps any {get,set,delete,keys?,clear?} (sync or async),
// a Map, or a plain object. Values are stored as strings by the adapter's JSON helpers.
class StorageAdapter{
  constructor(impl){ this.impl=impl||new MemoryStorage(); }
  static wrap(impl){ return impl instanceof StorageAdapter?impl:new StorageAdapter(impl); }
  async get(key){
    try{
      if(typeof this.impl.get==='function') return await this.impl.get(key);
      if(this.impl instanceof Map) return this.impl.get(key)??null;
      return this.impl[key]??null;
    }catch(e){ throw new NovelError(ERR.STORAGE, 'storage get failed: '+key, {cause:e}); }
  }
  async set(key, value){
    try{
      if(typeof this.impl.set==='function') return await this.impl.set(key, value);
      if(this.impl instanceof Map) { this.impl.set(key,value); return; }
      this.impl[key]=value;
    }catch(e){ throw new NovelError(ERR.STORAGE, 'storage set failed: '+key, {cause:e}); }
  }
  async delete(key){
    try{
      if(typeof this.impl.delete==='function') return await this.impl.delete(key);
      if(this.impl instanceof Map) { this.impl.delete(key); return; }
      delete this.impl[key];
    }catch(e){ throw new NovelError(ERR.STORAGE, 'storage delete failed: '+key, {cause:e}); }
  }
  async keys(prefix=''){
    if(typeof this.impl.keys==='function'){ const ks=await this.impl.keys(prefix); return [...ks].filter(k=>String(k).startsWith(prefix)); }
    if(this.impl instanceof Map) return [...this.impl.keys()].filter(k=>k.startsWith(prefix));
    return Object.keys(this.impl).filter(k=>k.startsWith(prefix));
  }
  async clear(){ if(typeof this.impl.clear==='function') await this.impl.clear(); else { for(const k of await this.keys('')) await this.delete(k); } }
  async getJSON(key, fallback=null){ const v=await this.get(key); if(v==null) return fallback; if(typeof v!=='string') return v; try{ return JSON.parse(v); }catch(e){ return fallback; } }
  async setJSON(key, value){ await this.set(key, JSON.stringify(value)); }
}
module.exports.default = StorageAdapter;

module.exports.StorageAdapter = StorageAdapter;

});

var __index = __load('src/index.js');
global.MoYuan = __index;
global.JsNovelEngine = __index; // deprecated alias, pre-rename name
global.Novel = __index.Novel;
global.createNovelEngine = __index.createNovelEngine;
})(typeof globalThis !== 'undefined' ? globalThis : this);
