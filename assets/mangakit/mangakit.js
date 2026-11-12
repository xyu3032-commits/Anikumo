// mangakit — single-file bundle for QuickJS-class hosts.
// Zero dependencies. No DOM. No Node APIs. The host injects
// one bridge object (global __mangakitHost or createMangaKit
// argument): http / store / cookies / ui / image / log.
// Globals after load: MangaKit (engine api), Manga
// (source-facing defineSource namespace).
(function (global) {
'use strict';
var __modules = {}; var __cache = {};
function __define(path, factory) { __modules[path] = factory; }
function __normalize(fromPath, rel) {
  if (rel.charAt(0) !== '.') return rel;
  var parts = fromPath.split('/'); parts.pop();
  var segs = rel.split('/');
  for (var i = 0; i < segs.length; i++) {
    var s = segs[i];
    if (s === '.' || s === '') continue;
    if (s === '..') parts.pop(); else parts.push(s);
  }
  var out = parts.join('/');
  if (!/\.js$/.test(out)) out += '.js';
  return out;
}
function __load(path) {
  if (__cache[path]) return __cache[path].exports;
  var factory = __modules[path];
  if (!factory) throw new Error('module not found: ' + path);
  var module = { exports: {} };
  __cache[path] = module;
  factory(module, module.exports, function (rel) { return __load(__normalize(path, rel)); });
  return module.exports;
}

__define('src/compat/venera.js', function (module, exports, __require) {
// Venera Compatibility Adapter — a SEPARATE layer that lets
// Venera-style source files (class X extends ComicSource)
// run on MangaKit without the core knowing anything about
// that API. It works by:
//   1. evaluating the source file with compat globals
//      (ComicSource, Network, Convert, HtmlDocument, APP,
//      randomInt, createUuid, getRandomText, fetch),
//   2. wrapping the resulting instance in an autonomous
//      MangaKit definition whose handlers translate call
//      shapes both ways.
// Incompatibilities are reported as diagnostics, never
// papered over: unmapped surfaces (favorites, comments,
// webview login) are listed on the returned registration.
//
// Known semantic notes (deliberate, documented):
//  - loadData/loadSetting are synchronous in the reference
//    API, so the compat layer preloads the source's data
//    bucket and settings snapshot at registration and serves
//    reads from memory; writes update memory synchronously
//    and persist through the bridge asynchronously.
//  - init() failures are warnings, not registration
//    failures (several real sources probe domains in init).
//  - Network calls bind to the source whose handler is
//    currently executing (the reference runtime does the
//    same); the binding is captured synchronously per call.
const { ERR, MkError } = __require('../core/errors.js');
const { Convert: BaseConvert, toBytes } = __require('../parser/convert.js');
const { parseHtml } = __require('../parser/html.js');
const { HttpClient } = __require('../network/http.js');

function toArrayBuffer(bytes) {
  const b = toBytes(bytes);
  return b.buffer.slice(b.byteOffset, b.byteOffset + b.byteLength);
}

// Image bridge for modifyImage snippets. The reference
// runtime's Image class talks to a SYNCHRONOUS host image
// registry (decoded images live host-side; ops are pure CPU
// work there). A MangaKit host that wants hook execution
// injects `globalThis.__mkImageSync(jsonString) ->
// jsonString` speaking the same op protocol
// ({method:'image', function, ...} -> {ok, v, fmt}); hosts
// without it get clean failures from the image hook kinds,
// never wrong pixels.
function mkImageCall(payload) {
  const fn = globalThis.__mkImageSync;
  if (typeof fn !== 'function') return { ok: false };
  try {
    const env = JSON.parse(fn(JSON.stringify(payload)));
    return env && typeof env === 'object' ? env : { ok: false };
  } catch (e) {
    return { ok: false };
  }
}

function mkImageOp(payload) {
  const env = mkImageCall(payload);
  return env.ok ? env.v : null;
}

/// The reference Image API (used inside modifyImage code):
/// a handle to a host-side decoded image.
class MkImage {
  constructor(key) { this.key = key; }

  copyRange(x, y, width, height) {
    const key = mkImageOp({
      method: 'image', function: 'copyRange',
      key: this.key, x, y, width, height,
    });
    return key == null ? null : new MkImage(key);
  }

  copyAndRotate90() {
    const key = mkImageOp({
      method: 'image', function: 'copyAndRotate90', key: this.key,
    });
    return key == null ? null : new MkImage(key);
  }

  fillImageAt(x, y, image) {
    mkImageOp({
      method: 'image', function: 'fillImageAt',
      key: this.key, x, y, image: image && image.key,
    });
  }

  fillImageRangeAt(x, y, image, srcX, srcY, width, height) {
    mkImageOp({
      method: 'image', function: 'fillImageRangeAt',
      key: this.key, x, y, image: image && image.key,
      srcX, srcY, width, height,
    });
  }

  get width() {
    return mkImageOp({ method: 'image', function: 'getWidth', key: this.key });
  }

  get height() {
    return mkImageOp({ method: 'image', function: 'getHeight', key: this.key });
  }

  static empty(width, height) {
    const key = mkImageOp({
      method: 'image', function: 'emptyImage', width, height,
    });
    return new MkImage(key);
  }
}

// Convert with the reference API's ArrayBuffer returns.
const CompatConvert = {
  ...BaseConvert,
  encodeUtf8: (v) => toArrayBuffer(BaseConvert.encodeUtf8(v)),
  decodeBase64: (v) => toArrayBuffer(BaseConvert.decodeBase64(v)),
  md5: (v) => toArrayBuffer(BaseConvert.md5(v)),
  sha1: (v) => toArrayBuffer(BaseConvert.sha1(v)),
  sha256: (v) => toArrayBuffer(BaseConvert.sha256(v)),
  hmac: (k, v, h) => toArrayBuffer(BaseConvert.hmac(k, v, h)),
  encryptAesEcb: (d, k) => toArrayBuffer(BaseConvert.encryptAesEcb(d, k)),
  decryptAesEcb: (d, k) => toArrayBuffer(BaseConvert.decryptAesEcb(d, k)),
  encryptAesCbc: (d, k, iv) => toArrayBuffer(BaseConvert.encryptAesCbc(d, k, iv)),
  decryptAesCbc: (d, k, iv) => toArrayBuffer(BaseConvert.decryptAesCbc(d, k, iv)),
};

// ---- HtmlDocument compat -----------------------------------
class CompatElement {
  constructor(node) { this._node = node; }

  get text() { return this._node ? this._node.text : ''; }
  get innerHTML() { return this._node ? this._node.innerHTML : ''; }
  get outerHTML() { return this._node ? this._node.outerHTML : ''; }
  get attributes() { return this._node ? this._node.attributes : {}; }
  get classNames() { return this._node ? this._node.classNames : []; }
  get children() { return this._node ? this._node.children.map((c) => new CompatElement(c)) : []; }

  querySelector(sel) {
    const el = this._node ? this._node.querySelector(sel) : null;
    return el ? new CompatElement(el) : null;
  }

  querySelectorAll(sel) {
    return this._node ? this._node.querySelectorAll(sel).map((el) => new CompatElement(el)) : [];
  }

  getElementById(id) {
    const el = this._node ? this._node.getElementById(id) : null;
    return el ? new CompatElement(el) : null;
  }
}

class CompatHtmlDocument {
  constructor(html) { this._doc = parseHtml(html); }

  dispose() { /* parser trees are GC-managed; nothing to free */ }

  querySelector(sel) {
    const el = this._doc.querySelector(sel);
    return el ? new CompatElement(el) : null;
  }

  querySelectorAll(sel) {
    return this._doc.querySelectorAll(sel).map((el) => new CompatElement(el));
  }

  getElementById(id) {
    const el = this._doc.getElementById(id);
    return el ? new CompatElement(el) : null;
  }
}

// ---- per-engine compat state --------------------------------
class VeneraCompat {
  constructor(engine, { appVersion = '1.6.5', platform = 'android' } = {}) {
    this.engine = engine;
    this.appVersion = appVersion;
    this.platform = platform;
    this.holders = new Map(); // sourceKey -> holder
    this.current = null;      // holder whose handler is running
    this._globalsInstalled = false;
  }

  _httpFor(holder) {
    if (holder.activeCtx) return holder.activeCtx.http;
    return new HttpClient(this.engine.bridge, { sourceKey: holder.key, logger: this.engine.logger });
  }

  _installGlobals() {
    if (this._globalsInstalled) return;
    this._globalsInstalled = true;
    const compat = this;
    const holder = () => {
      if (!compat.current) throw new Error('compat: no source is currently executing');
      return compat.current;
    };

    class ComicSource {
      loadSetting(key) {
        const h = this.__mkHolder || holder();
        return h.settings[key];
      }

      saveSetting(key, value) {
        const h = this.__mkHolder || holder();
        h.settings[key] = value;
        compat.engine.writeSetting(h.key, key, value).catch(() => {});
      }

      loadData(key) {
        const h = this.__mkHolder || holder();
        return h.data[key];
      }

      saveData(key, value) {
        const h = this.__mkHolder || holder();
        h.data[key] = value;
        h.persistData(key, value);
      }

      deleteData(key) {
        const h = this.__mkHolder || holder();
        delete h.data[key];
        h.deleteData(key);
      }

      loadSubData(sub, key) {
        const h = this.__mkHolder || holder();
        const bucket = h.data[`sub:${sub}`];
        return bucket ? bucket[key] : undefined;
      }

      saveSubData(sub, key, value) {
        const h = this.__mkHolder || holder();
        const bucket = { ...(h.data[`sub:${sub}`] || {}), [key]: value };
        h.data[`sub:${sub}`] = bucket;
        h.persistData(`sub:${sub}`, bucket);
      }
    }

    const Network = {
      get: async (url, headers) => {
        const h = holder();
        const res = await compat._httpFor(h).get(url, { headers: headers || {} });
        return { status: res.status, headers: res.headers, body: res.body };
      },
      post: async (url, headers, data) => {
        const h = holder();
        const res = await compat._httpFor(h).post(url, { headers: headers || {}, data });
        return { status: res.status, headers: res.headers, body: res.body };
      },
      sendRequest: async (method, url, headers, data) => {
        const h = holder();
        const res = await compat._httpFor(h).request(method, url, { headers: headers || {}, data });
        return { status: res.status, headers: res.headers, body: res.body };
      },
      put: async (url, headers, data) => Network.sendRequest('PUT', url, headers, data),
      delete: async (url, headers, data) => Network.sendRequest('DELETE', url, headers, data),
      patch: async (url, headers, data) => Network.sendRequest('PATCH', url, headers, data),
      fetchBytes: async (url, headers) => {
        const h = holder();
        const bytes = await compat._httpFor(h).fetchBytes(url, { headers: headers || {} });
        return toArrayBuffer(bytes);
      },
      setCookies: async (url, cookies) => {
        const h = holder();
        const list = (cookies || []).map((c) => (typeof c === 'string' ? c : `${c.name}=${c.value}`));
        await compat.engine.bridge.call('cookies', 'set', h.key, { url, cookies: list });
      },
      getCookies: async (url) => {
        const h = holder();
        const header = await compat.engine.bridge.call('cookies', 'get', h.key, { url });
        if (!header || typeof header !== 'string') return [];
        return header.split(';').map((p) => {
          const i = p.indexOf('=');
          return i === -1
            ? { name: p.trim(), value: '' }
            : { name: p.slice(0, i).trim(), value: p.slice(i + 1).trim() };
        }).filter((c) => c.name);
      },
      deleteCookies: async (url) => {
        const h = holder();
        try { await compat.engine.bridge.call('cookies', 'delete', h.key, { url }); } catch (_) {}
      },
    };

    const fetchShim = async (url, opts = {}) => {
      const h = holder();
      const res = await compat._httpFor(h).request(opts.method || 'GET', String(url), {
        headers: opts.headers || {}, data: opts.body,
      });
      return {
        status: res.status,
        ok: res.status >= 200 && res.status < 300,
        url: String(url),
        headers: {
          get: (name) => {
            const want = String(name).toLowerCase();
            for (const k of Object.keys(res.headers)) if (k.toLowerCase() === want) return res.headers[k];
            return null;
          },
        },
        text: async () => res.body,
        json: async () => JSON.parse(res.body),
        arrayBuffer: async () => {
          const bytesRes = await compat._httpFor(h).request(opts.method || 'GET', String(url), {
            headers: opts.headers || {}, data: opts.body, bytes: true,
          });
          const b = bytesRes.bytes || new Uint8Array(0);
          return b.buffer.slice(b.byteOffset, b.byteOffset + b.byteLength);
        },
      };
    };

    // UI surface: messages route to the host toast channel;
    // dialogs need a real host UI — without one they resolve
    // as "dismissed" and the attempt is logged, never faked
    // as a user choice.
    const UI = {
      showMessage: (message) => {
        const h = compat.current;
        if (h && h.activeCtx) h.activeCtx.toast(String(message)).catch(() => {});
      },
      showLoading: () => 0,
      cancelLoading: () => {},
      launchUrl: async (url) => {
        const h = holder();
        try {
          await compat.engine.bridge.call('ui', 'openUrl', h.key, { url: String(url) });
        } catch (e) {
          compat.engine.logger.warn('compat', `launchUrl not handled by host: ${url}`);
        }
      },
      showDialog: async (options) => {
        const h = holder();
        try {
          const r = await compat.engine.bridge.call('ui', 'dialog', h.key, {
            title: options && options.title ? String(options.title) : '',
            content: options && options.content ? String(options.content) : '',
            actions: options && Array.isArray(options.actions)
              ? options.actions.map((a) => ({ text: String((a && a.text) || a || '') }))
              : [],
          });
          return r === undefined ? null : r;
        } catch (e) {
          compat.engine.logger.warn('compat', 'showDialog dismissed (no host UI)');
          return null;
        }
      },
      showInputDialog: async (title, hint) => {
        const h = holder();
        try {
          const r = await compat.engine.bridge.call('ui', 'input', h.key, {
            title: String(title || ''), hint: String(hint || ''),
          });
          return r === undefined ? null : r;
        } catch (e) {
          compat.engine.logger.warn('compat', 'showInputDialog dismissed (no host UI)');
          return null;
        }
      },
    };

    class Cookie {
      constructor(name, value, domain, path, maxAge, expires) {
        this.name = name; this.value = value;
        this.domain = domain; this.path = path;
        this.maxAge = maxAge; this.expires = expires;
      }

      toString() { return `${this.name}=${this.value}`; }
    }

    // The Comic model class: sources construct it directly
    // (82 uses across the real source set). It is a plain
    // data holder; framework normalization reads its fields.
    class Comic {
      constructor(props = {}) {
        this.id = props.id;
        this.title = props.title;
        this.subTitle = props.subTitle || props.subtitle;
        this.cover = props.cover;
        this.tags = props.tags;
        this.description = props.description;
        this.maxPage = props.maxPage;
        this.language = props.language;
        this.sourceKey = props.sourceKey;
        Object.assign(this, props);
      }

      static fromJson(json) {
        return new Comic(typeof json === 'string' ? JSON.parse(json) : json);
      }

      static favoriteId(comic) {
        return comic ? `${comic.sourceKey || ''}:${comic.id || ''}` : '';
      }

      toJson() {
        return {
          id: this.id, title: this.title, subTitle: this.subTitle,
          cover: this.cover, tags: this.tags, description: this.description,
          maxPage: this.maxPage, language: this.language, sourceKey: this.sourceKey,
        };
      }
    }

    // ComicDetails: the loadInfo return model (25 uses).
    // Plain data holder like Comic, plus the fields details
    // results carry (chapters map, thumbnails, ...).
    class ComicDetails {
      constructor(props = {}) {
        Object.assign(this, props);
        this.id = props.id;
        this.title = props.title;
        this.subTitle = props.subTitle || props.subtitle;
        this.cover = props.cover;
        this.description = props.description;
        this.tags = props.tags;
        this.chapters = props.chapters;
        this.thumbnails = props.thumbnails;
        this.recommend = props.recommend;
        this.commentCount = props.commentCount;
        this.likesCount = props.likesCount;
        this.isLiked = props.isLiked;
        this.isFavorite = props.isFavorite;
        this.rating = props.rating;
        this.status = props.status;
        this.author = props.author;
        this.updateTime = props.updateTime;
        Object.assign(this, props);
      }

      static fromJson(json) {
        return new ComicDetails(typeof json === 'string' ? JSON.parse(json) : json);
      }
    }

    class Comment {
      constructor(props = {}) { Object.assign(this, props); }
    }

    globalThis.ComicSource = ComicSource;
    globalThis.Comic = Comic;
    globalThis.Image = MkImage;
    globalThis.ComicDetails = ComicDetails;
    globalThis.Comment = Comment;
    globalThis.Network = Network;
    globalThis.Convert = CompatConvert;
    globalThis.HtmlDocument = CompatHtmlDocument;
    globalThis.UI = UI;
    globalThis.Cookie = Cookie;
    globalThis.APP = { version: this.appVersion, platform: this.platform, locale: 'zh-CN' };
    globalThis.randomInt = (min, max) => Math.floor(Math.random() * (max - min + 1)) + min;
    globalThis.createUuid = () => 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => {
      const r = (Math.random() * 16) | 0;
      const v = c === 'x' ? r : (r & 0x3) | 0x8;
      return v.toString(16);
    });
    globalThis.getRandomText = (len = 16) => {
      const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
      let out = '';
      for (let i = 0; i < len; i++) out += chars[(Math.random() * chars.length) | 0];
      return out;
    };
    globalThis.fetch = fetchShim;
    // Some sources call a bare global log(...).
    globalThis.log = (...args) => {
      try {
        compat.engine.logger.info('source', args.map((a) => String(a)).join(' '));
      } catch (_) { /* never break a source */ }
    };
    this._ComicSource = ComicSource;
  }

  /// Evaluate a Venera-style source file and register it.
  /// Returns {manifest, diagnostics}.
  async registerSource(code) {
    this._installGlobals();
    const classMatch = /class\s+([A-Za-z_$][\w$]*)\s+extends\s+ComicSource/.exec(code);
    if (!classMatch) {
      throw new MkError(ERR.COMPAT_INCOMPATIBLE, 'no `class X extends ComicSource` found in source file');
    }
    const className = classMatch[1];
    const captureKey = '__mkCompatCaptured';
    // Indirect eval in global scope, mirroring how the
    // reference runtime registers sources; the class is
    // captured explicitly because eval class declarations do
    // not leak to the global object.
    (0, eval)(`${code}\n;globalThis.${captureKey} = ${className};`);
    const Ctor = globalThis[captureKey];
    delete globalThis[captureKey];
    if (typeof Ctor !== 'function') {
      throw new MkError(ERR.COMPAT_INCOMPATIBLE, `class ${className} did not evaluate to a constructor`);
    }
    const instance = new Ctor();
    const key = String(instance.key || '');
    if (!key) throw new MkError(ERR.COMPAT_INCOMPATIBLE, 'source instance has no key');

    const holder = {
      key,
      instance,
      settings: {},
      data: {},
      activeCtx: null,
      initWarning: null,
      persistData: (k, v) => {
        this.engine.bridge.call('store', 'set', key,
          { kind: 'data', key: String(k), value: JSON.stringify(v === undefined ? null : v) })
          .catch(() => {});
      },
      deleteData: (k) => {
        this.engine.bridge.call('store', 'delete', key, { kind: 'data', key: String(k) }).catch(() => {});
      },
    };
    instance.__mkHolder = holder;
    this.holders.set(key, holder);

    // Preload the data bucket (loadData is synchronous).
    if (this.engine.bridge.available) {
      try {
        const all = await this.engine.bridge.call('store', 'all', key, { kind: 'data' });
        if (all && typeof all === 'object') {
          for (const k of Object.keys(all)) {
            const raw = all[k];
            if (typeof raw === 'string') {
              try { holder.data[k] = JSON.parse(raw); } catch (_) { holder.data[k] = raw; }
            } else holder.data[k] = raw;
          }
        }
      } catch (e) {
        if (!e || e.code !== ERR.HOST_MISSING) throw e;
      }
    }

    const def = this._buildDef(holder);
    // holder.settings IS the manager's settings snapshot
    // (settingsRef): filled with defaults + stored values
    // before init runs, so synchronous loadSetting reads are
    // correct from the very first call.
    const manifest = await this.engine.registerSource(def, { settingsRef: holder.settings });
    const diagnostics = this._diagnostics(instance, holder);
    return { manifest, diagnostics };
  }

  _withHolder(holder, ctx, fn) {
    return async (...args) => {
      const prev = this.current;
      this.current = holder;
      holder.activeCtx = ctx;
      try {
        return await fn(...args);
      } finally {
        // Restore only if nobody else took the slot meanwhile:
        // a call that outlived its dispatcher timeout (its
        // finally landing during another source's call) must
        // not clobber the active holder.
        if (this.current === holder) this.current = prev;
        if (holder.activeCtx === ctx) holder.activeCtx = null;
      }
    };
  }

  _buildDef(holder) {
    const compat = this;
    const instance = holder.instance;
    const withH = (ctx, fn) => compat._withHolder(holder, ctx, fn)();

    // Image-hook registry: configs produced by onImageLoad /
    // onThumbnailLoad live under their ORIGINAL url so the
    // host can later drive their onResponse / onLoadFailed /
    // modifyImage through the image* call kinds (functions
    // cannot cross to the host; only markers and bytes do).
    // A registry miss (host restart, fresh session) re-runs
    // the producing hook for that one url, mirroring the
    // reference runtime.
    const imageHooks = new Map();
    const hookMarkers = (originalUrl, cfg) => ({
      transformOf: cfg && cfg.onResponse ? originalUrl : null,
      modifyCode: (cfg && cfg.modifyImage) || null,
      fallbackOf: cfg && cfg.onLoadFailed ? originalUrl : null,
    });
    const produceHookCfg = async (mode, url, id, ep) => {
      const comic = instance.comic;
      if (!comic) return null;
      try {
        if (mode === 'thumb') {
          if (typeof comic.onThumbnailLoad !== 'function') return null;
          const cfg = await comic.onThumbnailLoad.call(comic, url);
          return cfg && typeof cfg === 'object' ? cfg : null;
        }
        if (typeof comic.onImageLoad !== 'function') return null;
        const cfg = await comic.onImageLoad.call(comic, url, id || '', ep || '');
        return cfg && typeof cfg === 'object' ? cfg : null;
      } catch (e) {
        return null;
      }
    };
    const hookCfgFor = async (mode, url, id, ep) => {
      let cfg = imageHooks.get(url);
      if (!cfg) {
        cfg = await produceHookCfg(mode, url, id, ep);
        if (cfg) imageHooks.set(url, cfg);
      }
      return cfg;
    };
    // Runs comic.onThumbnailLoad over list results (search /
    // explore / category), the way the reference runtime
    // does: the config may rewrite the cover url and headers
    // and may carry an onResponse transform, which the
    // registry keeps for later imageOnResponse calls.
    const thumbnailPass = async (items) => {
      const hook = instance.comic && instance.comic.onThumbnailLoad;
      if (typeof hook !== 'function' || !Array.isArray(items)) return items;
      for (const comic of items) {
        if (!comic || typeof comic !== 'object') continue;
        const cover = comic.cover;
        if (typeof cover !== 'string' || !cover) continue;
        const cfg = await produceHookCfg('thumb', cover);
        if (!cfg) continue;
        imageHooks.set(cover, cfg);
        if (cfg.url) comic.cover = cfg.url;
        if (cfg.headers) comic.coverHeaders = cfg.headers;
        if (cfg.onResponse) comic.coverTransformOf = cover;
      }
      return items;
    };

    // Bound settings (callbacks keep the instance as `this`).
    const settings = {};
    if (instance.settings && typeof instance.settings === 'object') {
      for (const k of Object.keys(instance.settings)) {
        const s = instance.settings[k];
        settings[k] = s && typeof s === 'object' && typeof s.callback === 'function'
          ? { ...s, callback: () => s.callback.call(instance) }
          : s;
      }
    }

    const adaptPaged = (raw) => {
      if (Array.isArray(raw)) return { items: raw, hasMore: false };
      if (raw && typeof raw === 'object') {
        const items = raw.comics || raw.items || [];
        const maxPage = raw.maxPage;
        return { items, maxPage };
      }
      return { items: [] };
    };

    const def = {
      key: holder.key,
      name: String(instance.name || holder.key),
      version: String(instance.version || '0.0.0'),
      url: String(instance.url || ''),
      description: String(instance.description || ''),
      settings,
      init: async (ctx) => {
        if (typeof instance.init === 'function') {
          try {
            await withH(ctx, async () => instance.init());
          } catch (e) {
            holder.initWarning = e;
            compat.engine.logger.warn('compat',
              `init warning for ${holder.key}: ${e && e.message ? e.message : e}`);
          }
        }
      },
    };

    // Token-paged adapter for loadNext-only surfaces: page N
    // is reached by walking the `next` token chain from
    // page 1 (chains are cached per cache key on the holder).
    const tokenPager = (cacheKey, fetchNext) => {
      if (!holder._tokenChains) holder._tokenChains = new Map();
      return async (page) => {
        let chain = holder._tokenChains.get(cacheKey);
        if (!chain || page === 1) {
          chain = { tokens: [null], done: false };
          holder._tokenChains.set(cacheKey, chain);
        }
        let raw = null;
        while (chain.tokens.length < page && !chain.done) {
          const prev = chain.tokens[chain.tokens.length - 1];
          const r = await fetchNext(prev);
          chain.tokens.push(r && r.next !== undefined ? r.next : null);
          if (!r || r.next === null || r.next === undefined) chain.done = true;
          raw = r;
        }
        if (page === 1 || chain.tokens.length === page) {
          raw = raw || await fetchNext(chain.tokens[page - 1]);
          if (page === 1) {
            chain.tokens[1] = raw && raw.next !== undefined ? raw.next : null;
            if (!raw || raw.next === null || raw.next === undefined) chain.done = true;
          }
        } else {
          raw = await fetchNext(chain.tokens[page - 1]);
        }
        return raw;
      };
    };

    if (typeof (instance.search && instance.search.load) === 'function') {
      def.search = async (ctx, { keyword, page, options }) => withH(ctx, async () => {
        const raw = await instance.search.load(keyword, options && options.length ? options : searchOptionDefaults(instance), page);
        const paged = adaptPaged(raw);
        await thumbnailPass(paged.items);
        return { ...paged, hasMore: paged.maxPage ? page < paged.maxPage : paged.hasMore };
      });
    } else if (typeof (instance.search && instance.search.loadNext) === 'function') {
      def.search = async (ctx, { keyword, page, options }) => withH(ctx, async () => {
        const opts = options && options.length ? options : searchOptionDefaults(instance);
        const pager = tokenPager(`search|${keyword}|${JSON.stringify(opts)}`,
          (next) => instance.search.loadNext(keyword, opts, next));
        const raw = await pager(page);
        const paged = adaptPaged(raw);
        await thumbnailPass(paged.items);
        return {
          ...paged,
          hasMore: raw && raw.next !== null && raw.next !== undefined
            ? true
            : (paged.maxPage ? page < paged.maxPage : paged.hasMore),
        };
      });
    }

    if (Array.isArray(instance.explore)) {
      def.explore = instance.explore.map((section, sectionIndex) => ({
        title: section.title || '',
        load: async (ctx, { page }) => withH(ctx, async () => {
          let raw;
          if (typeof section.load === 'function') {
            raw = await section.load(page);
          } else if (typeof section.loadNext === 'function') {
            const pager = tokenPager(`explore|${sectionIndex}|${section.title || ''}`,
              (next) => section.loadNext(next));
            raw = await pager(page);
          } else if (Array.isArray(section.comics)) {
            raw = section.comics;
          } else {
            raw = section;
          }
          if (Array.isArray(raw)) return thumbnailPass(raw);
          if (raw && typeof raw === 'object' && Array.isArray(raw.comics)) return thumbnailPass(raw.comics);
          return raw; // section maps pass through to normalizeSections
        }),
      }));
    }

    if (instance.category && Array.isArray(instance.category.parts)) {
      def.categories = async () => {
        const out = [];
        for (const part of instance.category.parts) {
          const names = part.categories || [];
          const params = part.categoryParams || [];
          names.forEach((name, i) => out.push({ name, id: params[i] || name, group: part.name || '' }));
        }
        return out;
      };
    }

    if (instance.categoryComics && typeof instance.categoryComics.load === 'function') {
      def.category = async (ctx, { category, param, page, options }) => withH(ctx, async () => {
        const raw = await instance.categoryComics.load(
          category, param, options && options.length ? options : categoryOptionDefaults(instance), page);
        const paged = adaptPaged(raw);
        await thumbnailPass(paged.items);
        return { ...paged, hasMore: paged.maxPage ? page < paged.maxPage : paged.hasMore };
      });
    }

    if (instance.comic && typeof instance.comic.loadInfo === 'function') {
      def.details = async (ctx, { id }) => withH(ctx, async () => {
        const d = await instance.comic.loadInfo(id);
        return adaptDetails(d, id);
      });
      def.chapters = async (ctx, { id }) => withH(ctx, async () => {
        const d = await instance.comic.loadInfo(id);
        const chapters = mapToPlain(d && d.chapters);
        if (!chapters || (typeof chapters === 'object' && Object.keys(chapters).length === 0)) {
          // Single-volume sources: the comic itself is the
          // one chapter (reference behavior).
          return [{ id, title: (d && d.title) || '正文' }];
        }
        return chapters;
      });
    }

    if (instance.comic && typeof instance.comic.loadEp === 'function') {
      def.pages = async (ctx, { comicId, chapterId }) => withH(ctx, async () => {
        const raw = await instance.comic.loadEp(comicId, chapterId);
        let images = (raw && raw.images) || [];
        if (typeof instance.comic.onImageLoad === 'function') {
          const mapped = [];
          for (const url of images) {
            const cfg = await instance.comic.onImageLoad(url);
            if (!cfg || !cfg.url) { mapped.push(url); continue; }
            imageHooks.set(url, cfg);
            mapped.push({
              url: cfg.url,
              headers: cfg.headers || {},
              transformOf: cfg.onResponse ? url : null,
              modifyCode: cfg.modifyImage || null,
              fallbackOf: cfg.onLoadFailed ? url : null,
            });
          }
          images = mapped;
        }
        return { images };
      });
    }

    if (instance.comic && typeof instance.comic.loadThumbnails === 'function') {
      def.thumbnails = async (ctx, { id }) => withH(ctx, async () => {
        const raw = await instance.comic.loadThumbnails(id);
        return Array.isArray(raw) ? raw : [];
      });
    }

    if (instance.account && typeof instance.account === 'object') {
      const account = instance.account;
      def.account = {
        registerWebsite: account.registerWebsite || null,
        login: typeof account.login === 'function'
          ? async (ctx, { username, password }) => withH(ctx, async () => { await account.login(username, password); })
          : undefined,
        logout: typeof account.logout === 'function'
          ? async (ctx) => withH(ctx, async () => { await account.logout(); })
          : undefined,
        isLoggedIn: typeof account.checkLoginStatus === 'function'
          ? async (ctx) => withH(ctx, async () => !!(await account.checkLoginStatus()))
          : undefined,
      };
    }

    // Image-hook execution kinds (host-driven; functions
    // stay in this runtime, the host moves bytes and markers
    // only). Present whenever the source declares either
    // hook.
    if (instance.comic && (typeof instance.comic.onImageLoad === 'function'
        || typeof instance.comic.onThumbnailLoad === 'function')) {
      def.imageOnResponse = async (ctx, { mode, of, id, ep, bytesB64 }) => withH(ctx, async () => {
        const cfg = await hookCfgFor(mode === 'thumb' ? 'thumb' : 'image', of, id, ep);
        if (!cfg || typeof cfg.onResponse !== 'function') return { ok: false, bytesB64: null };
        // Reference contract: onResponse receives a response
        // object {data, status, headers} and may return a
        // response, raw bytes, or nothing (in-place edit of
        // resp.data).
        const resp = {
          data: toBytes(BaseConvert.decodeBase64(bytesB64 || '')),
          status: 200,
          headers: {},
        };
        const out = await cfg.onResponse.call(instance.comic, resp);
        let bytes = null;
        if (out && out.data !== undefined && out.data !== null) bytes = out.data;
        else if (out instanceof Uint8Array || out instanceof ArrayBuffer) bytes = out;
        else if (out === undefined || out === null) bytes = resp.data;
        if (bytes instanceof ArrayBuffer) bytes = new Uint8Array(bytes);
        if (!bytes || typeof bytes.length !== 'number') return { ok: false, bytesB64: null };
        return { ok: true, bytesB64: BaseConvert.encodeBase64(toBytes(bytes)) };
      });
      def.imageFallback = async (ctx, { of, id, ep }) => withH(ctx, async () => {
        const cfg = await hookCfgFor('image', of, id, ep);
        if (!cfg || typeof cfg.onLoadFailed !== 'function') return null;
        const next = await cfg.onLoadFailed.call(instance.comic);
        if (!next || typeof next !== 'object' || !next.url) return null;
        imageHooks.set(next.url, next);
        return {
          url: next.url,
          headers: next.headers || {},
          ...hookMarkers(next.url, next),
        };
      });
      def.imageModify = async (ctx, { code, bytesB64 }) => withH(ctx, async () => {
        // Mirrors the reference runtime: decode host-side,
        // eval the snippet to a `modifyImage` function, run
        // it over an Image handle, re-encode in the input's
        // format family (jpeg stays jpeg).
        const created = mkImageCall({
          method: 'image', function: 'createFromBytes', dataB64: bytesB64 || '',
        });
        if (!created.ok) return { ok: false, bytesB64: null };
        try {
          let fn = null;
          try { fn = (0, eval)(String(code || '') + '\n;modifyImage;'); } catch (e) { fn = null; }
          if (typeof fn !== 'function') {
            try {
              const alt = (0, eval)(String(code || ''));
              if (typeof alt === 'function') fn = alt;
            } catch (e) { /* keep null */ }
          }
          if (typeof fn !== 'function') return { ok: false, bytesB64: null };
          const img = new MkImage(created.v);
          let out = fn(img);
          if (out && typeof out.then === 'function') out = await out;
          const outKey = out && typeof out.key === 'number' ? out.key : created.v;
          const enc = mkImageCall({
            method: 'image', function: 'encode', key: outKey, fmt: created.fmt || '',
          });
          return enc.ok
            ? { ok: true, bytesB64: enc.v }
            : { ok: false, bytesB64: null };
        } catch (e) {
          return { ok: false, bytesB64: null };
        } finally {
          mkImageCall({ method: 'image', function: 'releaseAll' });
        }
      });
    }

    return def;
  }

  _diagnostics(instance, holder) {
    const unmapped = [];
    if (instance.favorites) unmapped.push('favorites');
    if (instance.comic && (instance.comic.loadComments || instance.comic.sendComment)) unmapped.push('comments');
    if (instance.account && instance.account.loginWithWebview) unmapped.push('account.loginWithWebview');
    if (instance.comic && instance.comic.likeId) unmapped.push('comic.like');
    if (instance.comic && instance.comic.starRating) unmapped.push('comic.starRating');
    return {
      sourceKey: holder.key,
      initWarning: holder.initWarning ? String(holder.initWarning.message || holder.initWarning) : null,
      unmappedSurfaces: unmapped,
    };
  }
}

// Option entries are "value-text" strings or {value, text}
// objects. The value a load function receives depends on
// the option type (semantics documented by the sources
// themselves): multi-select gets a JSON string of the
// selected values, dropdown gets the value or null when
// nothing is selected, select gets the value string.
function optionEntryValue(opt) {
  if (opt === null || opt === undefined) return undefined;
  if (typeof opt === 'object') return opt.value;
  const s = String(opt);
  const idx = s.indexOf('-');
  return idx >= 0 ? s.slice(0, idx) : s;
}

function optionDefaultValue(o) {
  if (!o || typeof o !== 'object') return '';
  if (Array.isArray(o.default)) return JSON.stringify(o.default);
  if (o.default !== undefined && o.default !== null) return String(o.default);
  const first = optionEntryValue(o.options && o.options[0]);
  if (o.type === 'dropdown') return first ? first : null;
  if (o.type === 'multi-select') return JSON.stringify(first ? [first] : []);
  return first || '';
}

function searchOptionDefaults(instance) {
  const list = instance.search && instance.search.optionList;
  if (!Array.isArray(list)) return [];
  return list.map(optionDefaultValue);
}

function categoryOptionDefaults(instance) {
  const groups = [];
  const collect = (opts) => {
    if (!Array.isArray(opts)) return;
    for (const o of opts) {
      if (o && typeof o === 'object') groups.push(optionDefaultValue(o));
    }
  };
  if (instance.categoryComics) {
    collect(instance.categoryComics.optionList);
    if (instance.categoryComics.options) collect([instance.categoryComics.options]);
  }
  if (instance.category && instance.category.rank && instance.category.rank.options) {
    collect(instance.category.rank.options);
  }
  return groups;
}

function mapToPlain(v) {
  if (v instanceof Map) {
    const out = {};
    for (const [k, val] of v.entries()) out[String(k)] = mapToPlain(val);
    return out;
  }
  if (v && typeof v === 'object' && !Array.isArray(v)) {
    const out = {};
    for (const k of Object.keys(v)) out[k] = mapToPlain(v[k]);
    return out;
  }
  return v;
}

function adaptDetails(d, id) {
  if (!d || typeof d !== 'object') return d;
  const tags = [];
  if (d.tags && typeof d.tags === 'object') {
    for (const ns of Object.keys(d.tags)) {
      const list = d.tags[ns];
      if (Array.isArray(list)) tags.push(...list);
    }
  }
  return {
    id: d.id || id,
    title: d.title,
    subtitle: d.subTitle || d.subtitle || '',
    cover: d.cover,
    author: Array.isArray(d.author) ? d.author.join(', ') : d.author,
    description: d.description,
    tags: tags.length ? tags : (Array.isArray(d.tags) ? d.tags : []),
    status: d.status,
    chapters: mapToPlain(d.chapters),
    recommendations: Array.isArray(d.recommendations) ? d.recommendations : [],
    raw: d,
  };
}

exports.VeneraCompat = VeneraCompat;

});
__define('src/core/bridge.js', function (module, exports, __require) {
// Host bridge: the ONLY way framework code touches the
// outside world. The host injects one object (global
// `__mangakitHost`, or passed to createMangaKit). Every call
// is wrapped in the bridge protocol v1 envelope
//   { protocol, channel, id, sourceKey, payload }
// so a host can log, route or sandbox calls uniformly, and
// every call carries the dispatcher's callId for tracing.
const { ERR, MkError, wrapError } = __require('./errors.js');
const { BRIDGE_PROTOCOL } = __require('./validate.js');
const { withTimeout } = __require('./utils.js');
const { redactHeaders } = __require('./logger.js');

const CHANNEL_TIMEOUTS = {
  http: 30000,
  store: 5000,
  cookies: 5000,
  ui: 0, // user-paced; no framework timeout
  image: 30000,
  log: 1000,
  delay: 0,
};

class BridgeClient {
  constructor({ host, logger } = {}) {
    this.host = host || null;
    this.logger = logger || null;
    this.seq = 0;
  }

  setHost(host) { this.host = host; }

  get available() { return !!this.host; }

  /// group: 'http'|'store'|'cookies'|'ui'|'image'|'log'
  /// method: the group's function name.
  async call(group, method, sourceKey, payload, opts = {}) {
    const host = this.host;
    const fn = host && host[group] && host[group][method];
    if (typeof fn !== 'function') {
      throw new MkError(ERR.HOST_MISSING, `host does not provide ${group}.${method}`, { sourceKey });
    }
    const envelope = {
      protocol: BRIDGE_PROTOCOL,
      channel: `${group}.${method}`,
      id: ++this.seq,
      callId: opts.callId || null,
      sourceKey: sourceKey || null,
      payload,
    };
    if (this.logger) {
      const safe = payload && payload.headers
        ? { ...payload, headers: redactHeaders(payload.headers) }
        : payload;
      this.logger.debug('bridge', `-> ${envelope.channel}`, { id: envelope.id, payload: safe });
    }
    try {
      const timeout = opts.timeout !== undefined ? opts.timeout : CHANNEL_TIMEOUTS[group] ?? 10000;
      const result = await withTimeout(
        Promise.resolve(fn.call(host[group], envelope)),
        timeout,
        () => new MkError(ERR.TIMEOUT, `host call ${envelope.channel} timed out`, { sourceKey, callId: opts.callId }),
      );
      return result;
    } catch (e) {
      if (e instanceof MkError) throw e;
      throw wrapError(e, ERR.HOST_CALL_FAILED, { sourceKey, callId: opts.callId });
    }
  }
}

/// Hosts report HTTP in one shape:
/// { status, headers, body, bodyB64? }
/// Normalize host replies defensively (hosts are user code).
function normalizeHttpReply(reply, sourceKey) {
  if (!reply || typeof reply !== 'object') {
    throw new MkError(ERR.HTTP_FAILED, 'host http reply is not an object', { sourceKey });
  }
  return {
    status: typeof reply.status === 'number' ? reply.status : 0,
    headers: reply.headers && typeof reply.headers === 'object' ? reply.headers : {},
    body: reply.body === undefined || reply.body === null ? '' : String(reply.body),
    bodyB64: reply.bodyB64 ? String(reply.bodyB64) : null,
  };
}

exports.BridgeClient = BridgeClient;
exports.normalizeHttpReply = normalizeHttpReply;

});
__define('src/core/errors.js', function (module, exports, __require) {
// MangaKit error model: every failure that crosses the
// dispatcher boundary is an MkError with a stable code, so
// hosts and tests assert on codes, never on message text.

const ERR = {
  BAD_MANIFEST: 'MK_BAD_MANIFEST',
  BAD_RESULT: 'MK_BAD_RESULT',
  SOURCE_NOT_FOUND: 'MK_SOURCE_NOT_FOUND',
  SOURCE_EXISTS: 'MK_SOURCE_EXISTS',
  NOT_INITIALIZED: 'MK_NOT_INITIALIZED',
  INIT_FAILED: 'MK_INIT_FAILED',
  UNSUPPORTED_KIND: 'MK_UNSUPPORTED_KIND',
  SOURCE_THROW: 'MK_SOURCE_THROW',
  HOST_MISSING: 'MK_HOST_MISSING',
  HOST_CALL_FAILED: 'MK_HOST_CALL_FAILED',
  HTTP_FAILED: 'MK_HTTP_FAILED',
  TIMEOUT: 'MK_TIMEOUT',
  CANCELLED: 'MK_CANCELLED',
  COMPAT_INCOMPATIBLE: 'MK_COMPAT_INCOMPATIBLE',
  VERIFICATION_REQUIRED: 'MK_VERIFICATION_REQUIRED',
};

class MkError extends Error {
  constructor(code, message, extra = {}) {
    super(message);
    this.name = 'MkError';
    this.code = code;
    this.sourceKey = extra.sourceKey || null;
    this.callId = extra.callId || null;
    this.kind = extra.kind || null;
    if (extra.cause !== undefined) this.cause = extra.cause;
  }

  toJSON() {
    return {
      name: this.name,
      code: this.code,
      message: this.message,
      sourceKey: this.sourceKey,
      callId: this.callId,
      kind: this.kind,
      cause: this.cause === undefined ? undefined : String(this.cause && this.cause.message ? this.cause.message : this.cause),
    };
  }
}

function wrapError(e, code, extra = {}) {
  if (e instanceof MkError) return e;
  const message = e && e.message ? e.message : String(e);
  return new MkError(code, message, { ...extra, cause: e });
}

exports.ERR = ERR;
exports.MkError = MkError;
exports.wrapError = wrapError;

});
__define('src/core/logger.js', function (module, exports, __require) {
// Ring-buffer logger. Secrets never land here: header values
// for cookie / authorization are redacted by key name before
// anything is stored.

const REDACT_KEYS = new Set(['cookie', 'set-cookie', 'authorization', 'x-api-key', 'token']);

function redactHeaders(headers) {
  if (!headers || typeof headers !== 'object') return headers;
  const out = {};
  for (const k of Object.keys(headers)) {
    out[k] = REDACT_KEYS.has(k.toLowerCase()) ? '<redacted>' : headers[k];
  }
  return out;
}

class MkLogger {
  constructor(capacity = 500) {
    this.capacity = capacity;
    this.entries = [];
    this.seq = 0;
  }

  log(level, tag, message, extra) {
    const entry = {
      seq: ++this.seq,
      at: Date.now(),
      level,
      tag: String(tag || ''),
      message: String(message === undefined ? '' : message),
    };
    if (extra !== undefined) entry.extra = extra;
    this.entries.push(entry);
    if (this.entries.length > this.capacity) {
      this.entries.splice(0, this.entries.length - this.capacity);
    }
    return entry;
  }

  debug(tag, m, e) { return this.log('debug', tag, m, e); }
  info(tag, m, e) { return this.log('info', tag, m, e); }
  warn(tag, m, e) { return this.log('warn', tag, m, e); }
  error(tag, m, e) { return this.log('error', tag, m, e); }

  tail(n = 100) {
    return this.entries.slice(Math.max(0, this.entries.length - n));
  }

  clear() { this.entries = []; }
}

exports.redactHeaders = redactHeaders;
exports.MkLogger = MkLogger;

});
__define('src/core/utils.js', function (module, exports, __require) {
// Small shared helpers. No host, no globals beyond JS itself.

function isPlainObject(v) {
  return typeof v === 'object' && v !== null && !Array.isArray(v);
}

function str(v, fallback = '') {
  if (v === null || v === undefined) return fallback;
  return String(v);
}

function num(v, fallback = 0) {
  const n = typeof v === 'number' ? v : Number(v);
  return Number.isFinite(n) ? n : fallback;
}

function clampInt(v, lo, hi, fallback) {
  const n = Math.trunc(num(v, fallback));
  return Math.min(hi, Math.max(lo, n));
}

/// Resolve a possibly-relative URL against a base. Returns the
/// input unchanged when it cannot be parsed (sources in the
/// wild hand back odd strings; the reader layer decides).
function resolveUrl(url, base) {
  const u = str(url);
  if (!u) return u;
  if (/^[a-zA-Z][a-zA-Z0-9+.-]*:/.test(u)) return u;
  if (!base) return u;
  try {
    return new URL(u, base).toString();
  } catch (_) {
    return u;
  }
}

/// Normalize a headers value (object / Map-ish / undefined)
/// into a plain {string: string} object.
function normalizeHeaders(headers) {
  const out = {};
  if (!headers) return out;
  if (Array.isArray(headers)) {
    for (const pair of headers) {
      if (Array.isArray(pair) && pair.length >= 2) out[str(pair[0])] = str(pair[1]);
    }
    return out;
  }
  if (typeof headers === 'object') {
    // Headers-like objects (fetch Headers) expose forEach.
    if (typeof headers.forEach === 'function' && typeof headers.get === 'function') {
      headers.forEach((v, k) => { out[k] = str(v); });
      return out;
    }
    for (const k of Object.keys(headers)) out[k] = str(headers[k]);
  }
  return out;
}

/// Case-insensitive header read from a plain object.
function headerOf(headers, name) {
  if (!headers) return undefined;
  const want = name.toLowerCase();
  for (const k of Object.keys(headers)) {
    if (k.toLowerCase() === want) return headers[k];
  }
  return undefined;
}

/// Join URL + query params (skips null/undefined values).
function withQuery(url, params) {
  if (!params) return url;
  const parts = [];
  for (const k of Object.keys(params)) {
    const v = params[k];
    if (v === null || v === undefined) continue;
    parts.push(`${encodeURIComponent(k)}=${encodeURIComponent(str(v))}`);
  }
  if (!parts.length) return url;
  return url + (url.includes('?') ? '&' : '?') + parts.join('&');
}

/// A promise that rejects with `makeError()` after `ms`.
/// The timer is host-agnostic: uses the global setTimeout when
/// the runtime provides one (Node, browsers); on bare QuickJS
/// the framework bootstrap installs one first (see index.js).
function withTimeout(promise, ms, makeError) {
  if (!ms || ms <= 0) return promise;
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(makeError()), ms);
    promise.then(
      (v) => { clearTimeout(timer); resolve(v); },
      (e) => { clearTimeout(timer); reject(e); },
    );
  });
}

function delayMs(ms) {
  return new Promise((resolve) => setTimeout(resolve, Math.max(0, ms | 0)));
}

exports.isPlainObject = isPlainObject;
exports.str = str;
exports.num = num;
exports.clampInt = clampInt;
exports.resolveUrl = resolveUrl;
exports.normalizeHeaders = normalizeHeaders;
exports.headerOf = headerOf;
exports.withQuery = withQuery;
exports.withTimeout = withTimeout;
exports.delayMs = delayMs;

});
__define('src/core/validate.js', function (module, exports, __require) {
// Data engine: schema validation + normalization for every
// value a source returns. Normalized objects are the ONLY
// shapes the dispatcher hands to hosts; the source's original
// value is preserved untouched under `raw` so no information
// is lost when a source uses fields the schema does not know.
const { ERR, MkError } = __require('./errors.js');
const { isPlainObject, str, num, normalizeHeaders } = __require('./utils.js');

const FRAMEWORK_VERSION = '0.1.0';
const BRIDGE_PROTOCOL = 1;

const KEY_RE = /^[A-Za-z0-9_.-]+$/;

function validateManifest(def, extra = {}) {
  if (!isPlainObject(def)) {
    throw new MkError(ERR.BAD_MANIFEST, 'source definition must be an object', extra);
  }
  const key = str(def.key);
  if (!key || !KEY_RE.test(key)) {
    throw new MkError(ERR.BAD_MANIFEST, `invalid source key: ${JSON.stringify(def.key)}`, extra);
  }
  const name = str(def.name, key);
  const version = str(def.version, '0.0.0');
  const capabilities = [];
  for (const cap of ['search', 'explore', 'details', 'chapters', 'pages',
    'categories', 'category', 'thumbnails', 'settings', 'account',
    'favorites', 'comments', 'imageOnResponse', 'imageModify', 'imageFallback']) {
    // Handlers may be functions, {load} objects, or — for
    // explore — a list of section objects.
    if (typeof def[cap] === 'function' || isPlainObject(def[cap]) || Array.isArray(def[cap])) {
      capabilities.push(cap);
    }
  }
  return {
    key,
    name,
    version,
    description: str(def.description),
    url: str(def.url),
    minFrameworkVersion: str(def.minFrameworkVersion),
    capabilities,
  };
}

/// One comic as lists carry it.
function normalizeComic(raw, sourceKey) {
  // Any non-null object qualifies — sources hand back model
  // class instances (e.g. `new Comic({...})`), not only
  // plain literals.
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return null;
  const id = str(raw.id ?? raw.comicId ?? raw.path_word ?? raw.slug);
  const title = str(raw.title ?? raw.name);
  // An id-bearing item is kept even when its title is empty
  // (some sources return alt-title maps the host resolves);
  // only id-less entries are unusable.
  if (!id) return null;
  const tags = [];
  const rawTags = raw.tags ?? raw.tagList ?? raw.themes;
  if (Array.isArray(rawTags)) {
    for (const t of rawTags) {
      const s = isPlainObject(t) ? str(t.name ?? t.title ?? t.id) : str(t);
      if (s) tags.push(s);
    }
  }
  return {
    id,
    sourceKey,
    title,
    subtitle: str(raw.subtitle) || str(raw.subTitle),
    author: str(raw.author ?? (Array.isArray(raw.authors) ? raw.authors.join(', ') : '')),
    cover: str(raw.cover ?? raw.coverUrl ?? raw.thumb),
    coverHeaders: normalizeHeaders(raw.coverHeaders),
    coverTransformOf: raw.coverTransformOf ? str(raw.coverTransformOf) : null,
    description: str(raw.description ?? raw.brief ?? raw.intro),
    status: normalizeStatus(raw.status),
    tags,
    rating: raw.rating === undefined ? null : num(raw.rating, NaN) || null,
    updatedAt: str(raw.updatedAt ?? raw.datetime_updated ?? raw.lastUpdate),
    raw,
  };
}

function normalizeStatus(raw) {
  const v = str(raw).trim().toLowerCase();
  if (!v) return '';
  if (v === 'ongoing' || v.includes('连载') || v.includes('連載')) return 'ongoing';
  if (v === 'completed' || v.includes('完结') || v.includes('完結') || v.includes('已完')) return 'completed';
  if (v === 'hiatus') return 'hiatus';
  if (v === 'cancelled' || v.includes('腰斩')) return 'cancelled';
  return v;
}

/// A paged list result. Accepts: array, {items|comics|list},
/// {items, hasMore|maxPage|total}. Unknown shapes are errors,
/// not silent empties — a garbage reply must surface.
function normalizePaged(raw, sourceKey, extra = {}) {
  let list = null;
  let hasMore = null;
  let maxPage = null;
  if (Array.isArray(raw)) {
    list = raw;
  } else if (isPlainObject(raw)) {
    list = raw.items ?? raw.comics ?? raw.list ?? raw.results ?? null;
    if (typeof raw.hasMore === 'boolean') hasMore = raw.hasMore;
    if (raw.maxPage !== undefined) maxPage = num(raw.maxPage, 0);
    if (raw.total !== undefined && Array.isArray(list)) {
      hasMore = list.length < num(raw.total, 0);
    }
  }
  if (!Array.isArray(list)) {
    throw new MkError(ERR.BAD_RESULT, 'paged result has no item list', extra);
  }
  const items = [];
  for (const entry of list) {
    const comic = normalizeComic(entry, sourceKey);
    if (comic) items.push(comic);
  }
  return { items, hasMore: hasMore === true, maxPage, raw };
}

/// Sectioned explore result: {sectionTitle: [comics]} or a
/// plain paged result. Sections normalize to
/// [{title, items}].
function normalizeSections(raw, sourceKey, extra = {}) {
  if (Array.isArray(raw)) {
    // An array of {title, comics|items} objects is a
    // multi-part section list, not a comic list.
    const sectionLike = raw.some((e) => e && typeof e === 'object'
      && (Array.isArray(e.comics) || Array.isArray(e.items)));
    if (sectionLike) {
      const sections = [];
      for (const e of raw) {
        if (!e || typeof e !== 'object') continue;
        const list = e.comics ?? e.items;
        if (!Array.isArray(list)) continue;
        sections.push({ title: str(e.title), items: normalizePaged(list, sourceKey, extra).items });
      }
      return sections;
    }
    return [{ title: '', items: normalizePaged(raw, sourceKey, extra).items }];
  }
  if (isPlainObject(raw)) {
    const keys = Object.keys(raw);
    const looksPaged = keys.some((k) => ['items', 'comics', 'list', 'results'].includes(k));
    if (looksPaged) {
      return [{ title: '', items: normalizePaged(raw, sourceKey, extra).items }];
    }
    const sections = [];
    for (const title of keys) {
      const value = raw[title];
      if (!Array.isArray(value)) continue;
      const items = [];
      for (const entry of value) {
        const comic = normalizeComic(entry, sourceKey);
        if (comic) items.push(comic);
      }
      sections.push({ title, items });
    }
    return sections;
  }
  throw new MkError(ERR.BAD_RESULT, 'explore result is not an object', extra);
}

function normalizeChapter(raw, index) {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return null;
  const id = str(raw.id ?? raw.epId ?? raw.chapterId ?? raw.key);
  const title = str(raw.title ?? raw.name, id);
  if (!id) return null;
  return {
    id,
    title,
    group: str(raw.group ?? raw.volume),
    order: raw.order === undefined ? index : num(raw.order, index),
    time: str(raw.time ?? raw.datetime_created ?? raw.date),
    raw,
  };
}

/// Chapters may arrive as a flat list or as grouped maps
/// {groupName: {chapterId: title} | [chapters]} (the shape
/// long-running series use). Groups flatten with `group` set,
/// order preserved.
function normalizeChapters(raw, extra = {}) {
  const out = [];
  let index = 0;
  const pushList = (list, group) => {
    for (const entry of list) {
      const ch = normalizeChapter(isPlainObject(entry) ? { ...entry, group: entry.group ?? group } : entry, index);
      if (ch) { out.push(ch); index++; }
    }
  };
  if (Array.isArray(raw)) {
    pushList(raw, '');
    return out;
  }
  if (isPlainObject(raw)) {
    for (const group of Object.keys(raw)) {
      const value = raw[group];
      if (typeof value === 'string') {
        // Flat chapter map: {chapterId: title}
        pushList([{ id: group, title: value }], '');
      } else if (Array.isArray(value)) {
        pushList(value, group);
      } else if (isPlainObject(value)) {
        const list = Object.keys(value).map((id) => (
          isPlainObject(value[id]) ? { id, ...value[id] } : { id, title: str(value[id]) }
        ));
        pushList(list, group);
      }
    }
    return out;
  }
  throw new MkError(ERR.BAD_RESULT, 'chapters result is not a list or group map', extra);
}

/// Details: a comic summary enriched with description/tags
/// and optionally its chapter list.
function normalizeDetails(raw, sourceKey, extra = {}) {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) {
    throw new MkError(ERR.BAD_RESULT, 'details result is not an object', extra);
  }
  const base = normalizeComic({ id: extra.id, ...raw }, sourceKey);
  if (!base) {
    throw new MkError(ERR.BAD_RESULT, 'details result lacks id/title', extra);
  }
  const details = { ...base };
  const chapterRaw = raw.chapters ?? raw.eps ?? raw.episodes;
  details.chapters = chapterRaw === undefined ? null : normalizeChapters(chapterRaw, extra);
  const recs = raw.recommendations ?? raw.recommend ?? raw.related;
  details.recommendations = Array.isArray(recs)
    ? recs.map((r) => normalizeComic(r, sourceKey)).filter(Boolean)
    : [];
  return details;
}

/// Pages: {images: [url | {url, headers,...}]} or a bare list.
/// Each image keeps its request headers and the three reader
/// hooks (byte transform / modify / fallback source ids) as
/// opaque strings the host pipeline understands.
function normalizePages(raw, extra = {}) {
  let list = null;
  if (Array.isArray(raw)) list = raw;
  else if (isPlainObject(raw)) list = raw.images ?? raw.pages ?? raw.list ?? null;
  if (!Array.isArray(list)) {
    throw new MkError(ERR.BAD_RESULT, 'pages result has no image list', extra);
  }
  const images = [];
  for (const entry of list) {
    if (typeof entry === 'string') {
      if (entry) images.push({ url: entry, headers: {} });
    } else if (isPlainObject(entry)) {
      const url = str(entry.url ?? entry.src);
      if (!url) continue;
      images.push({
        url,
        headers: normalizeHeaders(entry.headers),
        transformOf: entry.transformOf ? str(entry.transformOf) : null,
        modifyCode: entry.modifyCode ? str(entry.modifyCode) : null,
        fallbackOf: entry.fallbackOf ? str(entry.fallbackOf) : null,
        raw: entry,
      });
    }
  }
  return { images, raw };
}

/// Categories: accepts [{name|title, id|key, params}], plain
/// string lists, or grouped {group: [names]} shapes.
function normalizeCategories(raw, extra = {}) {
  const out = [];
  const push = (name, id, group) => {
    const n = str(name);
    if (n) out.push({ name: n, id: str(id, n), group: str(group) });
  };
  if (Array.isArray(raw)) {
    for (const entry of raw) {
      if (isPlainObject(entry)) push(entry.name ?? entry.title, entry.id ?? entry.key ?? entry.param, entry.group);
      else push(entry, entry, '');
    }
    return out;
  }
  if (isPlainObject(raw)) {
    for (const group of Object.keys(raw)) {
      const value = raw[group];
      if (Array.isArray(value)) {
        for (const entry of value) {
          if (isPlainObject(entry)) push(entry.name ?? entry.title, entry.id ?? entry.key ?? entry.param, group);
          else push(entry, entry, group);
        }
      }
    }
    return out;
  }
  throw new MkError(ERR.BAD_RESULT, 'categories result has unexpected shape', extra);
}

exports.FRAMEWORK_VERSION = FRAMEWORK_VERSION;
exports.BRIDGE_PROTOCOL = BRIDGE_PROTOCOL;
exports.validateManifest = validateManifest;
exports.normalizeComic = normalizeComic;
exports.normalizeStatus = normalizeStatus;
exports.normalizePaged = normalizePaged;
exports.normalizeSections = normalizeSections;
exports.normalizeChapter = normalizeChapter;
exports.normalizeChapters = normalizeChapters;
exports.normalizeDetails = normalizeDetails;
exports.normalizePages = normalizePages;
exports.normalizeCategories = normalizeCategories;

});
__define('src/core/verification.js', function (module, exports, __require) {
// Verification-wall detection: sites increasingly gate
// manga pages behind Cloudflare challenges or captcha forms.
// The framework never solves these automatically (no OCR, no
// solver services — that line is deliberate); it DETECTS the
// wall reliably, asks the host to let the USER clear it in a
// web view (bridge ui.solveVerification), replays the
// request with the harvested cookies, and otherwise reports
// a stable coded error instead of garbage content.

/// Body markers that, combined with a challenge status,
/// identify a verification wall (not an ordinary error page).
const WALL_MARKERS = [
  'cf-challenge', 'challenge-platform', 'cf-turnstile',
  'turnstile', 'just a moment', 'checking your browser',
  'attention required', 'g-recaptcha', 'h-captcha',
  'hcaptcha', 'geetest', '安全验证', '人机验证', '请输入验证码',
  '滑动验证', '滑块验证', 'verify you are human',
  'are you a robot', 'captcha',
];

const WALL_STATUSES = new Set([401, 403, 429, 503]);

// A 200 reply can still be a wall (some sites serve the
// captcha form with 200 + a sliver of content); only the
// strongest markers count there, to avoid false positives
// on pages that merely mention captchas (login pages).
const STRONG_MARKERS = ['请输入验证码', 'cf-challenge', 'challenge-platform', 'just a moment', '安全验证'];

/// Returns {kind, marker} when the reply looks like a
/// verification wall, else null. kind: 'cloudflare' when the
/// evidence points at Cloudflare, else 'captcha'.
function detectVerificationWall({ status, body, url }) {
  if (!body || typeof body !== 'string') return null;
  const text = body.slice(0, 16384).toLowerCase();
  if (status === 200) {
    for (const marker of STRONG_MARKERS) {
      if (text.includes(marker)) {
        return { kind: marker.includes('验证码') || marker.includes('安全验证') ? 'captcha' : 'cloudflare', marker, status, url: url || '' };
      }
    }
    return null;
  }
  if (!WALL_STATUSES.has(status)) return null;
  for (const marker of WALL_MARKERS) {
    if (text.includes(marker)) {
      const cloudflare = marker.startsWith('cf-') || marker === 'turnstile'
        || text.includes('cloudflare') || marker === 'just a moment'
        || marker === 'checking your browser' || marker === 'attention required';
      return { kind: cloudflare ? 'cloudflare' : 'captcha', marker, status, url: url || '' };
    }
  }
  return null;
}

/// Sources often surface walls as their own error strings
/// ("Cloudflare 验证拦截：请在漫画源设置中点击「登录」…" —
/// the failure text real sources throw); classify those at
/// the dispatcher boundary so hosts see one stable code.
const MESSAGE_PATTERNS = [
  /cloudflare/i, /captcha/i, /人机验证/, /安全验证/,
  /验证码拦截/, /验证拦截/, /滑块验证/, /滑动验证/,
  /verify you are human/i, /are you a robot/i,
];

function isVerificationMessage(message) {
  if (!message || typeof message !== 'string') return false;
  return MESSAGE_PATTERNS.some((re) => re.test(message));
}

exports.detectVerificationWall = detectVerificationWall;
exports.isVerificationMessage = isVerificationMessage;

});
__define('src/index.js', function (module, exports, __require) {
// MangaKit entry. Hosts either import this module (Node /
// bundlers) or load dist/mangakit.js, which installs the
// same API as globals: `MangaKit` and `Manga`.
const { MangaKitEngine } = __require('./source/manager.js');
const { VeneraCompat } = __require('./compat/venera.js');
const { ERR, MkError } = __require('./core/errors.js');
const { MkLogger } = __require('./core/logger.js');
const { BridgeClient } = __require('./core/bridge.js');
const { FRAMEWORK_VERSION, BRIDGE_PROTOCOL } = __require('./core/validate.js');
const { Convert } = __require('./parser/convert.js');
const { parseHtml } = __require('./parser/html.js');
exports.MangaKitEngine = MangaKitEngine;
exports.VeneraCompat = VeneraCompat;
exports.ERR = ERR;
exports.MkError = MkError;
exports.MkLogger = MkLogger;
exports.BridgeClient = BridgeClient;
exports.FRAMEWORK_VERSION = FRAMEWORK_VERSION;
exports.BRIDGE_PROTOCOL = BRIDGE_PROTOCOL;
exports.Convert = Convert;
exports.parseHtml = parseHtml;

/// Timer bootstrap for bare JS runtimes (QuickJS has no
/// setTimeout). When the host provides `delay(ms)` on its
/// injected bridge object, timers ride on it; in Node the
/// native timers are left untouched.
function installTimerShim(host) {
  if (typeof globalThis.setTimeout === 'function') return false;
  let seq = 0;
  globalThis.setTimeout = (fn, ms, ...args) => {
    const id = ++seq;
    const delay = host && typeof host.delay === 'function'
      ? host.delay(Math.max(0, ms | 0))
      : Promise.resolve();
    Promise.resolve(delay).then(() => {
      if (typeof fn === 'function') fn(...args);
    });
    return id;
  };
  globalThis.clearTimeout = () => {};
  return true;
}

/// Console bootstrap for bare JS runtimes: many sources call
/// console.log freely. Routes to the host log channel when
/// present, else keeps an in-memory no-op. An existing
/// console (Node) is left untouched.
function installConsoleShim(host) {
  if (typeof globalThis.console === 'object' && globalThis.console
    && typeof globalThis.console.log === 'function') return false;
  const write = (level) => (...args) => {
    try {
      if (host && host.log && typeof host.log.write === 'function') {
        host.log.write({
          protocol: 1, channel: 'log.write', id: 0, callId: null, sourceKey: null,
          payload: { level, message: args.map((a) => String(a)).join(' ') },
        });
      }
    } catch (_) { /* logging must never break a source */ }
  };
  globalThis.console = {
    log: write('info'), info: write('info'), debug: write('debug'),
    warn: write('warn'), error: write('error'),
  };
  return true;
}

/// Create an engine bound to a host bridge object. When
/// `host` is omitted, the global `__mangakitHost` is used
/// (the bundle path). Tuning knobs: `httpGate`
/// ({perOrigin=3, global=12, minIntervalMs=20}) caps request
/// bursts per origin; `refreshGuardMs` (default 2000)
/// dedupes identical explore/search/category calls inside
/// the window unless the caller passes refresh: true.
function createMangaKit({ host, appVersion, platform, httpGate, refreshGuardMs } = {}) {
  const resolvedHost = host || globalThis.__mangakitHost || null;
  installTimerShim(resolvedHost);
  installConsoleShim(resolvedHost);
  const engine = new MangaKitEngine({ host: resolvedHost, httpGate, refreshGuardMs });
  const compat = new VeneraCompat(engine, { appVersion, platform });
  const api = {
    version: FRAMEWORK_VERSION,
    engine,
    compat,
    call: (key, kind, args) => engine.call(key, kind, args),
    registerSource: (def, opts) => engine.registerSource(def, opts),
    registerVeneraSource: (code) => compat.registerSource(code),
    listSources: () => engine.listSources(),
    diagnostics: (key) => engine.diagnostics(key),
    Convert,
    parseHtml,
  };
  return api;
}

/// Install the globals the bundle exposes. `Manga` is the
/// autonomous source-facing namespace: a source file can
/// call Manga.defineSource({...}) and hosts drive the same
/// engine through MangaKit.
function installGlobals(api) {
  const kit = api || createMangaKit();
  globalThis.MangaKit = kit;
  globalThis.Manga = {
    defineSource: (def) => kit.registerSource(def),
    version: kit.version,
  };
  return kit;
}

exports.installTimerShim = installTimerShim;
exports.installConsoleShim = installConsoleShim;
exports.createMangaKit = createMangaKit;
exports.installGlobals = installGlobals;

});
__define('src/network/http.js', function (module, exports, __require) {
// HTTP client for sources. Transport itself is the host's
// job (bridge http.request); this layer adds what sources
// expect from a manga-framework network stack:
//   - cookie attach/store via the host-side jar (per URL)
//   - response decoding: text (charset sniff), JSON helper,
//     bytes via base64
//   - one retry for idempotent GETs on transport failure
//   - a short-TTL GET cache + in-flight request coalescing
//     (the speed layer; rules below are deliberate)
//   - verification-wall handling: detect Cloudflare/captcha
//     walls, ask the host to let the user clear them
//     (ui.solveVerification), replay once with the harvested
//     cookies, else throw MK_VERIFICATION_REQUIRED
//   - request/response tracing into the framework log
// Redirects are followed by the host transport.
//
// GET cache rules (hard-won, do not relax casually):
//   - only bodyless GETs, only status 200, body <= 512KB
//   - key = URL + ALL request headers (cookie variants of a
//     URL must never share an entry)
//   - a response carrying Set-Cookie is NEVER cached: it
//     rotates a session/token, and replaying a cached copy
//     would hand the source a stale cookie jar state
//   - TTL 5s, at most 64 entries (oldest evicted)
const { ERR, MkError } = __require('../core/errors.js');
const { normalizeHttpReply } = __require('../core/bridge.js');
const { decodeUtf8, decodeBase64, toBytes } = __require('../parser/convert.js');
const { normalizeHeaders, headerOf } = __require('../core/utils.js');
const { redactHeaders } = __require('../core/logger.js');
const { detectVerificationWall } = __require('../core/verification.js');

const CACHE_TTL_MS = 5000;
const CACHE_MAX_ENTRIES = 64;
const CACHE_MAX_BODY = 512 * 1024;
const WALL_SOLVE_COOLDOWN_MS = 20000;

class HttpResponse {
  constructor({ status, headers, bodyText, bodyBytes }) {
    this.status = status;
    this.headers = headers;
    this._text = bodyText;
    this._bytes = bodyBytes || null;
  }

  get body() { return this._text; }

  text() { return this._text; }

  json() { return JSON.parse(this._text); }

  bytes() {
    if (this._bytes) return this._bytes;
    return toBytes(this._text);
  }
}

// Cache/coalescing/wall/gate state is shared by every
// HttpClient built on the same bridge (contexts create a
// client per call; the speed layer must live across calls).
const sharedStates = new WeakMap();

function sharedState(bridge, gateConfig) {
  let s = sharedStates.get(bridge);
  if (!s) {
    s = {
      cache: new Map(), inflight: new Map(), wallSolvedAt: new Map(),
      gate: new RequestGate(gateConfig),
    };
    sharedStates.set(bridge, s);
  } else if (gateConfig && !s.gate.configured) {
    s.gate.configure(gateConfig);
  }
  return s;
}

/// Request gate (限流): bursts are what gets clients banned
/// — a screen refresh fanning a dozen requests into one
/// site in the same instant reads as abuse to rate
/// limiters, while the same requests paced are fine. The
/// gate caps concurrent requests per origin and globally,
/// and spaces request starts per origin. FIFO-fair: any
/// queued request that fits is granted (no head-of-line
/// blocking across origins).
class RequestGate {
  constructor(config) {
    config = config || {};
    this.perOrigin = config.perOrigin ?? 3;
    this.global = config.global ?? 12;
    // 20ms spaces bursts (a 50 req/s ceiling per origin)
    // without visibly pacing chatty-but-sequential sources;
    // hosts can raise it for touchier sites.
    this.minIntervalMs = config.minIntervalMs ?? 20;
    this.configured = !!config && Object.keys(config).length > 0;
    this.activeGlobal = 0;
    this.activeByOrigin = new Map();
    this.lastStartByOrigin = new Map();
    this.waiters = [];
    this.timer = null;
  }

  configure(config) {
    if (config.perOrigin !== undefined) this.perOrigin = config.perOrigin;
    if (config.global !== undefined) this.global = config.global;
    if (config.minIntervalMs !== undefined) this.minIntervalMs = config.minIntervalMs;
    this.configured = true;
    this._pump();
  }

  async acquire(origin) {
    return new Promise((resolve) => {
      this.waiters.push({ origin, resolve });
      this._pump();
    });
  }

  release(origin) {
    this.activeGlobal = Math.max(0, this.activeGlobal - 1);
    this.activeByOrigin.set(origin, Math.max(0, (this.activeByOrigin.get(origin) || 1) - 1));
    this._pump();
  }

  _pump() {
    if (this.timer) {
      clearTimeout(this.timer);
      this.timer = null;
    }
    const now = Date.now();
    let nextWake = Infinity;
    this.waiters = this.waiters.filter((w) => {
      if (this.activeGlobal >= this.global) return true;
      const active = this.activeByOrigin.get(w.origin) || 0;
      if (active >= this.perOrigin) return true;
      const last = this.lastStartByOrigin.get(w.origin) || 0;
      const due = last + this.minIntervalMs;
      if (now < due) {
        nextWake = Math.min(nextWake, due - now);
        return true;
      }
      this.activeGlobal++;
      this.activeByOrigin.set(w.origin, active + 1);
      this.lastStartByOrigin.set(w.origin, now);
      w.resolve();
      return false;
    });
    if (this.waiters.length && nextWake !== Infinity) {
      this.timer = setTimeout(() => { this.timer = null; this._pump(); }, nextWake);
      if (this.timer && typeof this.timer.unref === 'function') this.timer.unref();
    }
  }
}

function originOf(url) {
  try {
    return new URL(String(url)).origin;
  } catch (_) {
    return String(url).slice(0, 64);
  }
}

function clearSharedHttpCache(bridge) {
  const s = sharedStates.get(bridge);
  if (s) {
    s.cache.clear();
    s.inflight.clear();
  }
}

function cacheKeyOf(url, headers) {
  const parts = Object.keys(headers).sort().map((k) => `${k.toLowerCase()}:${headers[k]}`);
  return `GET ${url}\n${parts.join('\n')}`;
}

class HttpClient {
  constructor(bridge, { sourceKey, logger, gate } = {}) {
    this.bridge = bridge;
    this.sourceKey = sourceKey;
    this.logger = logger || null;
    this.gateConfig = gate || null;
  }

  async request(method, url, opts = {}) {
    const headers = normalizeHeaders(opts.headers);
    // Cookie attach: host jar owns cookies; ask it per URL.
    if (opts.cookies !== false) {
      try {
        const cookie = await this.bridge.call('cookies', 'get', this.sourceKey, { url }, { callId: opts.callId });
        if (cookie && typeof cookie === 'string' && cookie) {
          if (!headerOf(headers, 'cookie')) headers['Cookie'] = cookie;
        }
      } catch (e) {
        if (!e || e.code !== ERR.HOST_MISSING) throw e;
        // A host without a cookie jar is legal; requests just
        // go out cookieless and set-cookie is dropped.
      }
    }

    const cacheable = method === 'GET' && !opts.data && !opts.bytes && opts.cache !== false;
    const state = sharedState(this.bridge, this.gateConfig);
    const key = cacheable ? cacheKeyOf(String(url), headers) : null;

    if (cacheable) {
      const hit = state.cache.get(key);
      if (hit && Date.now() - hit.at < CACHE_TTL_MS) return hit.response;
      if (hit) state.cache.delete(key);
      const flying = state.inflight.get(key);
      if (flying) return flying;
    }

    const promise = this._execute(method, url, headers, opts, state, key);
    if (cacheable) {
      state.inflight.set(key, promise);
      promise.then(() => state.inflight.delete(key), () => state.inflight.delete(key));
    }
    return promise;
  }

  async _execute(method, url, headers, opts, state, cacheKey) {
    const send = () => this.bridge.call('http', 'request', this.sourceKey, {
      method,
      url: String(url),
      headers,
      data: opts.data === undefined ? null : opts.data,
      bytes: !!opts.bytes,
    }, { callId: opts.callId, timeout: opts.timeout });
    // The gate wraps only the network exchange — never the
    // verification-solving wait (user-paced, can take
    // minutes; holding a slot through it would starve the
    // queue).
    const origin = originOf(url);
    await state.gate.acquire(origin);
    let reply;
    try {
      try {
        reply = await send();
      } catch (e) {
        if (method === 'GET' && opts.retry !== false) {
          reply = await send(); // one retry, GET only
        } else throw e;
      }
    } finally {
      state.gate.release(origin);
    }
    const normalized = normalizeHttpReply(reply, this.sourceKey);
    // Persist any set-cookie into the host jar.
    const setCookie = headerOf(normalized.headers, 'set-cookie');
    if (setCookie) {
      try {
        await this.bridge.call('cookies', 'set', this.sourceKey,
          { url: String(url), cookies: Array.isArray(setCookie) ? setCookie : [setCookie] },
          { callId: opts.callId });
      } catch (e) {
        if (!e || e.code !== ERR.HOST_MISSING) throw e;
      }
    }
    let bodyBytes = null;
    let bodyText = normalized.body;
    if (normalized.bodyB64) {
      bodyBytes = decodeBase64(normalized.bodyB64);
      if (!opts.bytes) bodyText = decodeUtf8(bodyBytes);
    }
    if (this.logger) {
      this.logger.debug('http', `${method} ${url} -> ${normalized.status}`,
        { headers: redactHeaders(headers) });
    }
    const response = new HttpResponse({
      status: normalized.status,
      headers: normalized.headers,
      bodyText,
      bodyBytes,
    });

    // Verification wall: try the host's user-clear flow once.
    const wall = opts.bytes ? null : detectVerificationWall({
      status: normalized.status, body: bodyText, url: String(url),
    });
    if (wall) {
      if (opts._wallRetried) {
        throw new MkError(ERR.VERIFICATION_REQUIRED,
          `verification still required (${wall.kind}) at ${url}`,
          { sourceKey: this.sourceKey, kind: wall.kind });
      }
      const solved = await this._trySolveVerification(wall, state, opts);
      if (solved === true) {
        return this.request(method, url, { ...opts, _wallRetried: true, cache: false });
      }
      if (solved === false) {
        throw new MkError(ERR.VERIFICATION_REQUIRED,
          `verification required (${wall.kind}) at ${url}`,
          { sourceKey: this.sourceKey, kind: wall.kind });
      }
      // solved === null: host cannot clear walls; fall
      // through and return the wall page as-is so the
      // source's own error (classified at the dispatcher)
      // is what the caller sees.
    }

    if (cacheKey && normalized.status === 200 && !setCookie
      && typeof bodyText === 'string' && bodyText.length <= CACHE_MAX_BODY) {
      state.cache.set(cacheKey, { at: Date.now(), response });
      while (state.cache.size > CACHE_MAX_ENTRIES) {
        state.cache.delete(state.cache.keys().next().value);
      }
    }
    return response;
  }

  /// Ask the host to let the user clear a verification wall.
  /// Returns true (cleared — cookies are in the host jar),
  /// false (not cleared), or null (host has no such UI).
  async _trySolveVerification(wall, state, opts) {
    let origin = '';
    try { origin = new URL(wall.url).origin; } catch (_) { origin = wall.url; }
    const last = state.wallSolvedAt.get(origin) || 0;
    if (Date.now() - last < WALL_SOLVE_COOLDOWN_MS) return false;
    let result;
    try {
      result = await this.bridge.call('ui', 'solveVerification', this.sourceKey, {
        url: wall.url, kind: wall.kind, status: wall.status,
      }, { callId: opts.callId });
    } catch (e) {
      if (e && e.code === ERR.HOST_MISSING) return null;
      throw e;
    }
    state.wallSolvedAt.set(origin, Date.now());
    return !!(result && (result.solved === true || result === true));
  }

  get(url, opts) { return this.request('GET', url, opts); }
  post(url, opts) { return this.request('POST', url, opts); }

  async fetchBytes(url, opts = {}) {
    const res = await this.request('GET', url, { ...opts, bytes: true });
    return res.bytes();
  }
}

exports.HttpResponse = HttpResponse;
exports.RequestGate = RequestGate;
exports.clearSharedHttpCache = clearSharedHttpCache;
exports.HttpClient = HttpClient;

});
__define('src/parser/aes.js', function (module, exports, __require) {
// AES (128/192/256) in pure JS: ECB + CBC, PKCS#7 padding.
// Tables are generated from the GF(2^8) definitions at load
// instead of embedding 512 constants, which keeps the file
// small and typo-proof. Speed is ample for API payloads and
// image-key unwrapping (the workloads manga sources have).

function gfMul(a, b) {
  let p = 0;
  for (let i = 0; i < 8; i++) {
    if (b & 1) p ^= a;
    const hi = a & 0x80;
    a = (a << 1) & 0xff;
    if (hi) a ^= 0x1b;
    b >>= 1;
  }
  return p;
}

function gfPow(a, e) {
  let r = 1;
  while (e > 0) {
    if (e & 1) r = gfMul(r, a);
    a = gfMul(a, a);
    e >>= 1;
  }
  return r;
}

const SBOX = new Uint8Array(256);
const INV_SBOX = new Uint8Array(256);
for (let i = 0; i < 256; i++) {
  const inv = i === 0 ? 0 : gfPow(i, 254);
  const s = inv ^ ((inv << 1) | (inv >> 7)) ^ ((inv << 2) | (inv >> 6))
    ^ ((inv << 3) | (inv >> 5)) ^ ((inv << 4) | (inv >> 4)) ^ 0x63;
  SBOX[i] = s & 0xff;
  INV_SBOX[s & 0xff] = i;
}
const RCON = [1];
for (let i = 1; i < 15; i++) RCON.push(gfMul(RCON[i - 1], 2));

function expandKey(key) {
  const Nk = key.length / 4;
  const Nr = Nk + 6;
  const w = new Uint8Array(16 * (Nr + 1));
  w.set(key);
  for (let i = Nk; i < 4 * (Nr + 1); i++) {
    let t0 = w[4 * (i - 1)], t1 = w[4 * (i - 1) + 1], t2 = w[4 * (i - 1) + 2], t3 = w[4 * (i - 1) + 3];
    if (i % Nk === 0) {
      const r = RCON[i / Nk - 1];
      const n0 = SBOX[t1] ^ r, n1 = SBOX[t2], n2 = SBOX[t3], n3 = SBOX[t0];
      t0 = n0; t1 = n1; t2 = n2; t3 = n3;
    } else if (Nk > 6 && i % Nk === 4) {
      t0 = SBOX[t0]; t1 = SBOX[t1]; t2 = SBOX[t2]; t3 = SBOX[t3];
    }
    w[4 * i] = w[4 * (i - Nk)] ^ t0;
    w[4 * i + 1] = w[4 * (i - Nk) + 1] ^ t1;
    w[4 * i + 2] = w[4 * (i - Nk) + 2] ^ t2;
    w[4 * i + 3] = w[4 * (i - Nk) + 3] ^ t3;
  }
  return { w, Nr };
}

function addRoundKey(s, w, round) {
  for (let i = 0; i < 16; i++) s[i] ^= w[round * 16 + i];
}

function subBytes(s, box) {
  for (let i = 0; i < 16; i++) s[i] = box[s[i]];
}

function shiftRows(s, inverse) {
  const t = new Uint8Array(16);
  for (let r = 0; r < 4; r++) {
    for (let c = 0; c < 4; c++) {
      const src = inverse ? (c - r + 4) % 4 : (c + r) % 4;
      t[r + 4 * c] = s[r + 4 * src];
    }
  }
  s.set(t);
}

function mixColumns(s, inverse) {
  for (let c = 0; c < 4; c++) {
    const i = 4 * c;
    const a0 = s[i], a1 = s[i + 1], a2 = s[i + 2], a3 = s[i + 3];
    if (!inverse) {
      s[i] = gfMul(a0, 2) ^ gfMul(a1, 3) ^ a2 ^ a3;
      s[i + 1] = a0 ^ gfMul(a1, 2) ^ gfMul(a2, 3) ^ a3;
      s[i + 2] = a0 ^ a1 ^ gfMul(a2, 2) ^ gfMul(a3, 3);
      s[i + 3] = gfMul(a0, 3) ^ a1 ^ a2 ^ gfMul(a3, 2);
    } else {
      s[i] = gfMul(a0, 14) ^ gfMul(a1, 11) ^ gfMul(a2, 13) ^ gfMul(a3, 9);
      s[i + 1] = gfMul(a0, 9) ^ gfMul(a1, 14) ^ gfMul(a2, 11) ^ gfMul(a3, 13);
      s[i + 2] = gfMul(a0, 13) ^ gfMul(a1, 9) ^ gfMul(a2, 14) ^ gfMul(a3, 11);
      s[i + 3] = gfMul(a0, 11) ^ gfMul(a1, 13) ^ gfMul(a2, 9) ^ gfMul(a3, 14);
    }
  }
}

function encryptBlock(input, offset, out, outOffset, ctx) {
  const s = new Uint8Array(16);
  for (let i = 0; i < 16; i++) s[i] = input[offset + i];
  addRoundKey(s, ctx.w, 0);
  for (let round = 1; round < ctx.Nr; round++) {
    subBytes(s, SBOX);
    shiftRows(s, false);
    mixColumns(s, false);
    addRoundKey(s, ctx.w, round);
  }
  subBytes(s, SBOX);
  shiftRows(s, false);
  addRoundKey(s, ctx.w, ctx.Nr);
  out.set(s, outOffset);
}

function decryptBlock(input, offset, out, outOffset, ctx) {
  const s = new Uint8Array(16);
  for (let i = 0; i < 16; i++) s[i] = input[offset + i];
  addRoundKey(s, ctx.w, ctx.Nr);
  for (let round = ctx.Nr - 1; round >= 1; round--) {
    shiftRows(s, true);
    subBytes(s, INV_SBOX);
    addRoundKey(s, ctx.w, round);
    mixColumns(s, true);
  }
  shiftRows(s, true);
  subBytes(s, INV_SBOX);
  addRoundKey(s, ctx.w, 0);
  out.set(s, outOffset);
}

function checkKey(key) {
  if (![16, 24, 32].includes(key.length)) {
    throw new Error(`AES: invalid key length ${key.length}`);
  }
}

function pkcs7Pad(data) {
  const pad = 16 - (data.length % 16);
  const out = new Uint8Array(data.length + pad);
  out.set(data);
  out.fill(pad, data.length);
  return out;
}

function pkcs7Unpad(data) {
  if (data.length === 0) return data;
  const pad = data[data.length - 1];
  if (pad < 1 || pad > 16 || pad > data.length) return data;
  for (let i = data.length - pad; i < data.length; i++) {
    if (data[i] !== pad) return data;
  }
  return data.slice(0, data.length - pad);
}

function aesEncryptEcb(data, key, { pad = true } = {}) {
  checkKey(key);
  const ctx = expandKey(key);
  const input = pad ? pkcs7Pad(data) : data;
  if (input.length % 16 !== 0) throw new Error('AES-ECB: data not a multiple of 16');
  const out = new Uint8Array(input.length);
  for (let o = 0; o < input.length; o += 16) encryptBlock(input, o, out, o, ctx);
  return out;
}

function aesDecryptEcb(data, key, { pad = true } = {}) {
  checkKey(key);
  const ctx = expandKey(key);
  if (data.length % 16 !== 0) throw new Error('AES-ECB: data not a multiple of 16');
  const out = new Uint8Array(data.length);
  for (let o = 0; o < data.length; o += 16) decryptBlock(data, o, out, o, ctx);
  return pad ? pkcs7Unpad(out) : out;
}

function aesEncryptCbc(data, key, iv, { pad = true } = {}) {
  checkKey(key);
  if (!iv || iv.length !== 16) throw new Error('AES-CBC: iv must be 16 bytes');
  const ctx = expandKey(key);
  const input = pad ? pkcs7Pad(data) : data;
  if (input.length % 16 !== 0) throw new Error('AES-CBC: data not a multiple of 16');
  const out = new Uint8Array(input.length);
  const block = new Uint8Array(16);
  let prev = iv;
  for (let o = 0; o < input.length; o += 16) {
    for (let i = 0; i < 16; i++) block[i] = input[o + i] ^ prev[i];
    encryptBlock(block, 0, out, o, ctx);
    prev = out.subarray(o, o + 16);
  }
  return out;
}

function aesDecryptCbc(data, key, iv, { pad = true } = {}) {
  checkKey(key);
  if (!iv || iv.length !== 16) throw new Error('AES-CBC: iv must be 16 bytes');
  const ctx = expandKey(key);
  if (data.length % 16 !== 0) throw new Error('AES-CBC: data not a multiple of 16');
  const out = new Uint8Array(data.length);
  let prev = iv;
  for (let o = 0; o < data.length; o += 16) {
    decryptBlock(data, o, out, o, ctx);
    for (let i = 0; i < 16; i++) out[o + i] ^= prev[i];
    prev = data.subarray(o, o + 16);
  }
  return pad ? pkcs7Unpad(out) : out;
}

exports.aesEncryptEcb = aesEncryptEcb;
exports.aesDecryptEcb = aesDecryptEcb;
exports.aesEncryptCbc = aesEncryptCbc;
exports.aesDecryptCbc = aesDecryptCbc;

});
__define('src/parser/convert.js', function (module, exports, __require) {
// Byte/text conversion + hashes, pure JS (no Node Buffer, no
// Web Crypto assumptions — must run identically on QuickJS).
// Byte arrays are Uint8Array throughout; ArrayBuffer inputs
// are accepted and viewed.

function toBytes(v) {
  if (v === null || v === undefined) return new Uint8Array(0);
  if (v instanceof Uint8Array) return v;
  if (v instanceof ArrayBuffer) return new Uint8Array(v);
  if (Array.isArray(v)) return Uint8Array.from(v);
  if (typeof v === 'string') return encodeUtf8(v);
  return encodeUtf8(String(v));
}

function encodeUtf8(str) {
  const out = [];
  const s = String(str);
  for (let i = 0; i < s.length; i++) {
    let cp = s.codePointAt(i);
    if (cp > 0xffff) i++;
    if (cp < 0x80) out.push(cp);
    else if (cp < 0x800) out.push(0xc0 | (cp >> 6), 0x80 | (cp & 0x3f));
    else if (cp < 0x10000) out.push(0xe0 | (cp >> 12), 0x80 | ((cp >> 6) & 0x3f), 0x80 | (cp & 0x3f));
    else out.push(0xf0 | (cp >> 18), 0x80 | ((cp >> 12) & 0x3f), 0x80 | ((cp >> 6) & 0x3f), 0x80 | (cp & 0x3f));
  }
  return Uint8Array.from(out);
}

function decodeUtf8(bytes) {
  const b = toBytes(bytes);
  let out = '';
  let i = 0;
  while (i < b.length) {
    const c = b[i];
    if (c < 0x80) { out += String.fromCharCode(c); i += 1; }
    else if (c < 0xe0) { out += String.fromCharCode(((c & 0x1f) << 6) | (b[i + 1] & 0x3f)); i += 2; }
    else if (c < 0xf0) { out += String.fromCharCode(((c & 0x0f) << 12) | ((b[i + 1] & 0x3f) << 6) | (b[i + 2] & 0x3f)); i += 3; }
    else {
      const cp = ((c & 0x07) << 18) | ((b[i + 1] & 0x3f) << 12) | ((b[i + 2] & 0x3f) << 6) | (b[i + 3] & 0x3f);
      out += String.fromCodePoint(cp);
      i += 4;
    }
  }
  return out;
}

const B64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
const B64I = (() => { const m = {}; for (let i = 0; i < B64.length; i++) m[B64[i]] = i; return m; })();

function encodeBase64(v) {
  const b = toBytes(v);
  let out = '';
  for (let i = 0; i < b.length; i += 3) {
    const n = (b[i] << 16) | ((b[i + 1] || 0) << 8) | (b[i + 2] || 0);
    out += B64[(n >> 18) & 63] + B64[(n >> 12) & 63]
      + (i + 1 < b.length ? B64[(n >> 6) & 63] : '=')
      + (i + 2 < b.length ? B64[n & 63] : '=');
  }
  return out;
}

function decodeBase64(s) {
  const clean = String(s).replace(/[^A-Za-z0-9+/=]/g, '');
  const out = [];
  for (let i = 0; i < clean.length; i += 4) {
    const a = B64I[clean[i]], b = B64I[clean[i + 1]];
    const c = clean[i + 2] === '=' ? 0 : B64I[clean[i + 2]];
    const d = clean[i + 3] === '=' ? 0 : B64I[clean[i + 3]];
    const n = (a << 18) | (b << 12) | (c << 6) | d;
    out.push((n >> 16) & 255);
    if (clean[i + 2] !== '=') out.push((n >> 8) & 255);
    if (clean[i + 3] !== '=') out.push(n & 255);
  }
  return Uint8Array.from(out);
}

function hexEncode(v) {
  const b = toBytes(v);
  let out = '';
  for (const byte of b) out += byte.toString(16).padStart(2, '0');
  return out;
}

function hexDecode(s) {
  const clean = String(s).replace(/[^0-9a-fA-F]/g, '');
  const out = [];
  for (let i = 0; i + 1 < clean.length; i += 2) out.push(parseInt(clean.slice(i, i + 2), 16));
  return Uint8Array.from(out);
}

function encodeHtml(s) {
  return String(s)
    .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
}

function decodeHtml(s) {
  return String(s)
    .replace(/&#x([0-9a-fA-F]+);/g, (_, h) => String.fromCodePoint(parseInt(h, 16)))
    .replace(/&#(\d+);/g, (_, d) => String.fromCodePoint(parseInt(d, 10)))
    .replace(/&quot;/g, '"').replace(/&apos;/g, "'").replace(/&#39;/g, "'")
    .replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&nbsp;/g, ' ')
    .replace(/&amp;/g, '&');
}

// ---- SHA-256 (FIPS 180-4) --------------------------------
const K256 = [
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
  0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
  0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
  0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
  0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
  0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
];

function sha256Bytes(input) {
  const msg = toBytes(input);
  const H = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19];
  const bitLen = msg.length * 8;
  const padded = Array.from(msg);
  padded.push(0x80);
  while (padded.length % 64 !== 56) padded.push(0);
  // 64-bit length, inputs here are < 2^32 bits in practice.
  padded.push(0, 0, 0, 0, (bitLen >>> 24) & 255, (bitLen >>> 16) & 255, (bitLen >>> 8) & 255, bitLen & 255);
  const rotr = (x, n) => (x >>> n) | (x << (32 - n));
  const w = new Array(64);
  for (let block = 0; block < padded.length; block += 64) {
    for (let t = 0; t < 16; t++) {
      w[t] = (padded[block + t * 4] << 24) | (padded[block + t * 4 + 1] << 16)
        | (padded[block + t * 4 + 2] << 8) | padded[block + t * 4 + 3];
    }
    for (let t = 16; t < 64; t++) {
      const s0 = rotr(w[t - 15], 7) ^ rotr(w[t - 15], 18) ^ (w[t - 15] >>> 3);
      const s1 = rotr(w[t - 2], 17) ^ rotr(w[t - 2], 19) ^ (w[t - 2] >>> 10);
      w[t] = (w[t - 16] + s0 + w[t - 7] + s1) | 0;
    }
    let [a, b, c, d, e, f, g, h] = H;
    for (let t = 0; t < 64; t++) {
      const S1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25);
      const ch = (e & f) ^ (~e & g);
      const t1 = (h + S1 + ch + K256[t] + w[t]) | 0;
      const S0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22);
      const maj = (a & b) ^ (a & c) ^ (b & c);
      const t2 = (S0 + maj) | 0;
      h = g; g = f; f = e; e = (d + t1) | 0;
      d = c; c = b; b = a; a = (t1 + t2) | 0;
    }
    H[0] = (H[0] + a) | 0; H[1] = (H[1] + b) | 0; H[2] = (H[2] + c) | 0; H[3] = (H[3] + d) | 0;
    H[4] = (H[4] + e) | 0; H[5] = (H[5] + f) | 0; H[6] = (H[6] + g) | 0; H[7] = (H[7] + h) | 0;
  }
  const out = new Uint8Array(32);
  H.forEach((word, i) => {
    out[i * 4] = (word >>> 24) & 255; out[i * 4 + 1] = (word >>> 16) & 255;
    out[i * 4 + 2] = (word >>> 8) & 255; out[i * 4 + 3] = word & 255;
  });
  return out;
}

// ---- SHA-1 ------------------------------------------------
function sha1Bytes(input) {
  const msg = toBytes(input);
  const H = [0x67452301, 0xefcdab89, 0x98badcfe, 0x10325476, 0xc3d2e1f0];
  const bitLen = msg.length * 8;
  const padded = Array.from(msg);
  padded.push(0x80);
  while (padded.length % 64 !== 56) padded.push(0);
  padded.push(0, 0, 0, 0, (bitLen >>> 24) & 255, (bitLen >>> 16) & 255, (bitLen >>> 8) & 255, bitLen & 255);
  const rol = (x, n) => (x << n) | (x >>> (32 - n));
  const w = new Array(80);
  for (let block = 0; block < padded.length; block += 64) {
    for (let t = 0; t < 16; t++) {
      w[t] = (padded[block + t * 4] << 24) | (padded[block + t * 4 + 1] << 16)
        | (padded[block + t * 4 + 2] << 8) | padded[block + t * 4 + 3];
    }
    for (let t = 16; t < 80; t++) w[t] = rol(w[t - 3] ^ w[t - 8] ^ w[t - 14] ^ w[t - 16], 1);
    let [a, b, c, d, e] = H;
    for (let t = 0; t < 80; t++) {
      let f, k;
      if (t < 20) { f = (b & c) | (~b & d); k = 0x5a827999; }
      else if (t < 40) { f = b ^ c ^ d; k = 0x6ed9eba1; }
      else if (t < 60) { f = (b & c) | (b & d) | (c & d); k = 0x8f1bbcdc; }
      else { f = b ^ c ^ d; k = 0xca62c1d6; }
      const tmp = (rol(a, 5) + f + e + k + w[t]) | 0;
      e = d; d = c; c = rol(b, 30); b = a; a = tmp;
    }
    H[0] = (H[0] + a) | 0; H[1] = (H[1] + b) | 0; H[2] = (H[2] + c) | 0;
    H[3] = (H[3] + d) | 0; H[4] = (H[4] + e) | 0;
  }
  const out = new Uint8Array(20);
  H.forEach((word, i) => {
    out[i * 4] = (word >>> 24) & 255; out[i * 4 + 1] = (word >>> 16) & 255;
    out[i * 4 + 2] = (word >>> 8) & 255; out[i * 4 + 3] = word & 255;
  });
  return out;
}

// ---- MD5 ---------------------------------------------------
function md5Bytes(input) {
  const msg = toBytes(input);
  const S = [
    7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22,
    5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20,
    4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
    6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21,
  ];
  const K = new Array(64);
  for (let i = 0; i < 64; i++) K[i] = Math.floor(Math.abs(Math.sin(i + 1)) * 4294967296) | 0;
  const padded = Array.from(msg);
  const bitLen = msg.length * 8;
  padded.push(0x80);
  while (padded.length % 64 !== 56) padded.push(0);
  for (let i = 0; i < 4; i++) padded.push((bitLen >>> (8 * i)) & 255);
  padded.push(0, 0, 0, 0);
  let a0 = 0x67452301, b0 = 0xefcdab89, c0 = 0x98badcfe, d0 = 0x10325476;
  const rol = (x, n) => (x << n) | (x >>> (32 - n));
  for (let block = 0; block < padded.length; block += 64) {
    const M = new Array(16);
    for (let j = 0; j < 16; j++) {
      M[j] = padded[block + j * 4] | (padded[block + j * 4 + 1] << 8)
        | (padded[block + j * 4 + 2] << 16) | (padded[block + j * 4 + 3] << 24);
    }
    let a = a0, b = b0, c = c0, d = d0;
    for (let i = 0; i < 64; i++) {
      let f, g;
      if (i < 16) { f = (b & c) | (~b & d); g = i; }
      else if (i < 32) { f = (d & b) | (~d & c); g = (5 * i + 1) % 16; }
      else if (i < 48) { f = b ^ c ^ d; g = (3 * i + 5) % 16; }
      else { f = c ^ (b | ~d); g = (7 * i) % 16; }
      const tmp = d;
      d = c;
      c = b;
      b = (b + rol((a + f + K[i] + M[g]) | 0, S[i])) | 0;
      a = tmp;
    }
    a0 = (a0 + a) | 0; b0 = (b0 + b) | 0; c0 = (c0 + c) | 0; d0 = (d0 + d) | 0;
  }
  const out = new Uint8Array(16);
  [a0, b0, c0, d0].forEach((word, i) => {
    out[i * 4] = word & 255; out[i * 4 + 1] = (word >>> 8) & 255;
    out[i * 4 + 2] = (word >>> 16) & 255; out[i * 4 + 3] = (word >>> 24) & 255;
  });
  return out;
}

const HASHES = { md5: md5Bytes, sha1: sha1Bytes, sha256: sha256Bytes };

function hashBytes(name, value) {
  const fn = HASHES[String(name).toLowerCase()];
  if (!fn) throw new Error(`unsupported hash: ${name}`);
  return fn(value);
}

function hmacBytes(key, value, hash = 'sha256') {
  const fn = HASHES[String(hash).toLowerCase()];
  if (!fn) throw new Error(`unsupported hash: ${hash}`);
  const blockSize = String(hash).toLowerCase() === 'md5' || String(hash).toLowerCase() === 'sha1' ? 64 : 64;
  let k = toBytes(key);
  if (k.length > blockSize) k = fn(k);
  const inner = new Uint8Array(blockSize + toBytes(value).length);
  const outerPad = new Uint8Array(blockSize);
  for (let i = 0; i < blockSize; i++) {
    const kb = i < k.length ? k[i] : 0;
    inner[i] = kb ^ 0x36;
    outerPad[i] = kb ^ 0x5c;
  }
  inner.set(toBytes(value), blockSize);
  const innerHash = fn(inner);
  const outer = new Uint8Array(blockSize + innerHash.length);
  outer.set(outerPad, 0);
  outer.set(innerHash, blockSize);
  return fn(outer);
}
const { aesDecryptCbc, aesDecryptEcb, aesEncryptCbc, aesEncryptEcb } = __require('./aes.js');

/// The Convert surface source code uses (also exported for
/// the autonomous ctx.convert).
const Convert = {
  encodeUtf8,
  decodeUtf8,
  encodeBase64,
  decodeBase64,
  hexEncode,
  hexDecode,
  encodeHtml,
  decodeHtml,
  md5: (v) => md5Bytes(v),
  sha1: (v) => sha1Bytes(v),
  sha256: (v) => sha256Bytes(v),
  hmac: (key, value, hash) => hmacBytes(key, value, hash),
  hmacString: (key, value, hash = 'sha256') => hexEncode(hmacBytes(key, value, hash)),
  // AES, data-first argument order (the order sources use).
  encryptAesEcb: (data, key) => aesEncryptEcb(toBytes(data), toBytes(key)),
  decryptAesEcb: (data, key) => aesDecryptEcb(toBytes(data), toBytes(key)),
  encryptAesCbc: (data, key, iv) => aesEncryptCbc(toBytes(data), toBytes(key), toBytes(iv)),
  decryptAesCbc: (data, key, iv) => aesDecryptCbc(toBytes(data), toBytes(key), toBytes(iv)),
};

exports.toBytes = toBytes;
exports.encodeUtf8 = encodeUtf8;
exports.decodeUtf8 = decodeUtf8;
exports.encodeBase64 = encodeBase64;
exports.decodeBase64 = decodeBase64;
exports.hexEncode = hexEncode;
exports.hexDecode = hexDecode;
exports.encodeHtml = encodeHtml;
exports.decodeHtml = decodeHtml;
exports.sha256Bytes = sha256Bytes;
exports.sha1Bytes = sha1Bytes;
exports.md5Bytes = md5Bytes;
exports.hashBytes = hashBytes;
exports.hmacBytes = hmacBytes;
exports.Convert = Convert;

});
__define('src/parser/html.js', function (module, exports, __require) {
// A compact HTML parser + CSS-selector engine written for
// MangaKit. It is deliberately small: it handles the shapes
// real manga sites serve (tag soup, implied closes, raw
// script/style text, entity soup) and the selector subset
// sources actually use (tag / .class / #id / [attr] /
// descendant / child / :nth-child and friends). Anything
// outside the subset throws a clear error instead of silently
// returning wrong nodes.
const { decodeHtml } = __require('./convert.js');

const VOID_TAGS = new Set(['area', 'base', 'br', 'col', 'embed', 'hr', 'img',
  'input', 'link', 'meta', 'param', 'source', 'track', 'wbr']);
const RAW_TAGS = new Set(['script', 'style', 'textarea', 'title']);
// Which open tags a new start-tag implicitly closes:
// a block-level start closes an open <p>, a new <li> closes
// the previous one, table cells/rows close each other, etc.
const BLOCK_CLOSES_P = new Set(['p', 'div', 'ul', 'ol', 'table', 'section',
  'article', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'blockquote', 'pre', 'li',
  'header', 'footer', 'nav', 'aside', 'figure', 'form', 'fieldset']);

function impliedClosesFor(tag) {
  const s = new Set();
  if (BLOCK_CLOSES_P.has(tag)) s.add('p');
  if (tag === 'li') s.add('li');
  if (tag === 'tr') { s.add('tr'); s.add('td'); s.add('th'); }
  if (tag === 'td' || tag === 'th') { s.add('td'); s.add('th'); }
  if (tag === 'option') s.add('option');
  if (tag === 'dt' || tag === 'dd') { s.add('dt'); s.add('dd'); }
  return s;
}

class HtmlNode {
  constructor(type) {
    this.type = type; // 'element' | 'text' | 'root'
    this.parent = null;
    this.childNodes = [];
  }

  get children() {
    return this.childNodes.filter((n) => n.type === 'element');
  }

  get text() {
    if (this.type === 'text') return this._text || '';
    let out = '';
    const walk = (n) => {
      for (const c of n.childNodes) {
        if (c.type === 'text') out += c._text || '';
        else walk(c);
      }
    };
    walk(this);
    return out;
  }

  querySelector(selector) {
    return queryAll(this, selector)[0] || null;
  }

  querySelectorAll(selector) {
    return queryAll(this, selector);
  }

  getElementById(id) {
    let found = null;
    const walk = (n) => {
      for (const c of n.childNodes) {
        if (found) return;
        if (c.type === 'element' && c.attributes && c.attributes.id === id) { found = c; return; }
        walk(c);
      }
    };
    walk(this);
    return found;
  }
}

class HtmlElement extends HtmlNode {
  constructor(tag, attributes) {
    super('element');
    this.tag = tag;
    this.tagName = tag;
    this.attributes = attributes || {};
  }

  getAttribute(name) {
    const v = this.attributes[String(name).toLowerCase()];
    return v === undefined ? null : v;
  }

  get classNames() {
    const c = this.attributes.class;
    return c ? c.split(/\s+/).filter(Boolean) : [];
  }

  get innerHTML() {
    return this.childNodes.map(serializeNode).join('');
  }

  get outerHTML() {
    return serializeNode(this);
  }
}

function serializeNode(n) {
  if (n.type === 'text') return n._text || '';
  if (n.type === 'root') return n.childNodes.map(serializeNode).join('');
  const attrs = Object.keys(n.attributes)
    .map((k) => (n.attributes[k] === '' ? ` ${k}` : ` ${k}="${String(n.attributes[k]).replace(/"/g, '&quot;')}"`))
    .join('');
  if (VOID_TAGS.has(n.tag)) return `<${n.tag}${attrs}>`;
  return `<${n.tag}${attrs}>${n.childNodes.map(serializeNode).join('')}</${n.tag}>`;
}

function parseAttributes(s) {
  const attrs = {};
  const re = /([^\s=/>]+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]*)))?/g;
  let m;
  while ((m = re.exec(s)) !== null) {
    const name = m[1].toLowerCase();
    const value = m[2] !== undefined ? m[2] : m[3] !== undefined ? m[3] : m[4] !== undefined ? m[4] : '';
    attrs[name] = decodeHtml(value);
  }
  return attrs;
}

function parseHtml(html) {
  const root = new HtmlNode('root');
  const stack = [root];
  const top = () => stack[stack.length - 1];
  const pushText = (raw, decode = true) => {
    if (!raw) return;
    const node = new HtmlNode('text');
    node._text = decode ? decodeHtml(raw) : raw;
    node.parent = top();
    top().childNodes.push(node);
  };
  const s = String(html === undefined || html === null ? '' : html);
  let i = 0;
  while (i < s.length) {
    const lt = s.indexOf('<', i);
    if (lt === -1) { pushText(s.slice(i)); break; }
    if (lt > i) pushText(s.slice(i, lt));
    if (s.startsWith('<!--', lt)) {
      const end = s.indexOf('-->', lt + 4);
      i = end === -1 ? s.length : end + 3;
      continue;
    }
    if (s.startsWith('<!', lt) || s.startsWith('<?', lt)) {
      const end = s.indexOf('>', lt);
      i = end === -1 ? s.length : end + 1;
      continue;
    }
    const gt = findTagEnd(s, lt);
    if (gt === -1) { pushText(s.slice(lt)); break; }
    const inside = s.slice(lt + 1, gt);
    if (inside.startsWith('/')) {
      const tag = inside.slice(1).trim().split(/\s+/)[0].toLowerCase();
      for (let j = stack.length - 1; j > 0; j--) {
        if (stack[j].tag === tag) { stack.length = j; break; }
      }
      i = gt + 1;
      continue;
    }
    const selfClose = /\/\s*$/.test(inside);
    const body = selfClose ? inside.replace(/\/\s*$/, '') : inside;
    const m = /^([A-Za-z][A-Za-z0-9-]*)([\s\S]*)$/.exec(body.trim());
    if (!m) { pushText(s.slice(lt, gt + 1)); i = gt + 1; continue; }
    const tag = m[1].toLowerCase();
    // Implied closes: a new <li> closes an open <li>, etc.
    const closes = impliedClosesFor(tag);
    while (stack.length > 1 && top().type === 'element' && closes.has(top().tag)) stack.pop();
    const el = new HtmlElement(tag, parseAttributes(m[2] || ''));
    el.parent = top();
    top().childNodes.push(el);
    i = gt + 1;
    if (VOID_TAGS.has(tag) || selfClose) continue;
    if (RAW_TAGS.has(tag)) {
      const close = s.toLowerCase().indexOf(`</${tag}`, i);
      const rawText = close === -1 ? s.slice(i) : s.slice(i, close);
      const node = new HtmlNode('text');
      node._text = rawText;
      node.parent = el;
      el.childNodes.push(node);
      if (close === -1) { i = s.length; }
      else {
        const closeGt = s.indexOf('>', close);
        i = closeGt === -1 ? s.length : closeGt + 1;
      }
      continue;
    }
    stack.push(el);
  }
  const doc = new HtmlNode('root');
  doc.childNodes = root.childNodes;
  for (const c of doc.childNodes) c.parent = doc;
  doc.querySelector = root.querySelector.bind(doc);
  doc.querySelectorAll = root.querySelectorAll.bind(doc);
  doc.getElementById = root.getElementById.bind(doc);
  return doc;
}

function findTagEnd(s, lt) {
  let quote = null;
  for (let i = lt + 1; i < s.length; i++) {
    const c = s[i];
    if (quote) { if (c === quote) quote = null; }
    else if (c === '"' || c === "'") quote = c;
    else if (c === '>') return i;
  }
  return -1;
}

// ---- selectors ---------------------------------------------
function splitGroups(selector) {
  const groups = [];
  let depth = 0, quote = null, cur = '';
  for (const c of String(selector)) {
    if (quote) { cur += c; if (c === quote) quote = null; continue; }
    if (c === '"' || c === "'") { quote = c; cur += c; continue; }
    if (c === '[' || c === '(') depth++;
    if (c === ']' || c === ')') depth--;
    if (c === ',' && depth === 0) { groups.push(cur); cur = ''; continue; }
    cur += c;
  }
  if (cur.trim()) groups.push(cur);
  return groups.map((g) => g.trim()).filter(Boolean);
}

function splitGroup(group) {
  // -> [{compound, combinator}] where combinator links this
  // compound to the previous one (' ' or '>').
  const parts = [];
  let cur = '', depth = 0, quote = null, combinator = ' ';
  const flush = () => {
    const t = cur.trim();
    if (t) parts.push({ compound: t, combinator: parts.length === 0 ? null : combinator });
    cur = '';
  };
  for (let i = 0; i < group.length; i++) {
    const c = group[i];
    if (quote) { cur += c; if (c === quote) quote = null; continue; }
    if (c === '"' || c === "'") { quote = c; cur += c; continue; }
    if (c === '[' || c === '(') depth++;
    if (c === ']' || c === ')') depth--;
    if (depth === 0 && (c === '>' || /\s/.test(c))) {
      if (c === '>') { flush(); combinator = '>'; }
      else if (cur.trim()) { flush(); combinator = ' '; }
      continue;
    }
    cur += c;
  }
  flush();
  return parts;
}

function parseCompound(text) {
  const out = { tag: null, id: null, classes: [], attrs: [], pseudos: [] };
  let rest = text;
  const tagMatch = /^([A-Za-z][A-Za-z0-9-]*|\*)/.exec(rest);
  if (tagMatch) { out.tag = tagMatch[1] === '*' ? null : tagMatch[1].toLowerCase(); rest = rest.slice(tagMatch[1].length); }
  while (rest.length) {
    let m;
    if ((m = /^\.([A-Za-z0-9_-]+)/.exec(rest))) { out.classes.push(m[1]); rest = rest.slice(m[0].length); }
    else if ((m = /^#([A-Za-z0-9_-]+)/.exec(rest))) { out.id = m[1]; rest = rest.slice(m[0].length); }
    else if ((m = /^\[\s*([^\s=\]]+)\s*(?:([~|^$*]?=)\s*(?:"([^"]*)"|'([^']*)'|([^\]]*?))\s*)?\]/.exec(rest))) {
      out.attrs.push({ name: m[1].toLowerCase(), op: m[2] || null, value: (m[3] ?? m[4] ?? m[5] ?? '').trim() });
      rest = rest.slice(m[0].length);
    }
    else if ((m = /^:([A-Za-z-]+)(?:\(([^)]*)\))?/.exec(rest))) {
      out.pseudos.push({ name: m[1].toLowerCase(), arg: (m[2] || '').trim() });
      rest = rest.slice(m[0].length);
    }
    else throw new Error(`unsupported selector fragment: ${rest} in ${text}`);
  }
  return out;
}

function elementIndex(el) {
  if (!el.parent) return 1;
  const sibs = el.parent.childNodes.filter((n) => n.type === 'element');
  return sibs.indexOf(el) + 1;
}

function nthMatches(expr, pos) {
  const e = expr.replace(/\s+/g, '').toLowerCase();
  if (e === 'odd') return pos % 2 === 1;
  if (e === 'even') return pos % 2 === 0;
  if (/^\d+$/.test(e)) return pos === parseInt(e, 10);
  const m = /^([+-]?\d*)n([+-]\d+)?$/.exec(e);
  if (m) {
    const a = m[1] === '' || m[1] === '+' ? 1 : m[1] === '-' ? -1 : parseInt(m[1], 10);
    const b = m[2] ? parseInt(m[2], 10) : 0;
    if (a === 0) return pos === b;
    const diff = pos - b;
    return diff % a === 0 && diff / a >= 0;
  }
  return false;
}

function matchesCompound(el, c) {
  if (el.type !== 'element') return false;
  if (c.tag && el.tag !== c.tag) return false;
  if (c.id !== null && el.attributes.id !== c.id) return false;
  for (const cls of c.classes) if (!el.classNames.includes(cls)) return false;
  for (const a of c.attrs) {
    const v = el.attributes[a.name];
    if (v === undefined) return false;
    if (a.op === '=' && v !== a.value) return false;
    if (a.op === '*=' && !v.includes(a.value)) return false;
    if (a.op === '^=' && !v.startsWith(a.value)) return false;
    if (a.op === '$=' && !v.endsWith(a.value)) return false;
    if (a.op === '~=' && !v.split(/\s+/).includes(a.value)) return false;
    if (a.op === '|=' && !(v === a.value || v.startsWith(a.value + '-'))) return false;
  }
  for (const p of c.pseudos) {
    if (p.name === 'first-child' && elementIndex(el) !== 1) return false;
    else if (p.name === 'last-child') {
      const sibs = el.parent ? el.parent.childNodes.filter((n) => n.type === 'element') : [el];
      if (sibs[sibs.length - 1] !== el) return false;
    }
    else if (p.name === 'nth-child' && !nthMatches(p.arg, elementIndex(el))) return false;
    else if (p.name === 'empty' && el.childNodes.length !== 0) return false;
    else if (!['first-child', 'last-child', 'nth-child', 'empty'].includes(p.name)) {
      throw new Error(`unsupported pseudo-class: :${p.name}`);
    }
  }
  return true;
}

function descendantsOf(node, out = []) {
  for (const c of node.childNodes) {
    if (c.type === 'element') { out.push(c); descendantsOf(c, out); }
  }
  return out;
}

function queryAll(rootNode, selector) {
  const results = [];
  const seen = new Set();
  for (const group of splitGroups(selector)) {
    const parts = splitGroup(group).map((p) => ({ ...p, parsed: parseCompound(p.compound) }));
    let current = descendantsOf(rootNode).filter((el) => matchesCompound(el, parts[0].parsed));
    for (let i = 1; i < parts.length; i++) {
      const next = [];
      for (const el of current) {
        const candidates = parts[i].combinator === '>'
          ? el.childNodes.filter((n) => n.type === 'element')
          : descendantsOf(el);
        for (const cand of candidates) if (matchesCompound(cand, parts[i].parsed)) next.push(cand);
      }
      current = next;
    }
    for (const el of current) {
      if (!seen.has(el)) { seen.add(el); results.push(el); }
    }
  }
  return results;
}

exports.HtmlNode = HtmlNode;
exports.HtmlElement = HtmlElement;
exports.parseHtml = parseHtml;
exports.queryAll = queryAll;

});
__define('src/source/context.js', function (module, exports, __require) {
// The capability surface a source handler receives (`ctx`).
// Everything a source can do to the outside world goes
// through here, and everything here goes through the bridge —
// a source can never touch the host directly.
const { HttpClient } = __require('../network/http.js');
const { parseHtml } = __require('../parser/html.js');
const { Convert } = __require('../parser/convert.js');

class SourceContext {
  constructor({ bridge, logger, sourceKey, settings, httpGate }) {
    this.key = sourceKey;
    this.bridge = bridge;
    this.logger = logger;
    this.httpGate = httpGate || null;
    this.http = new HttpClient(bridge, { sourceKey, logger, gate: this.httpGate });
    this.convert = Convert;
    this._settings = settings || {};
    this._callId = null;
  }

  _withCall(callId) {
    const ctx = Object.create(Object.getPrototypeOf(this));
    Object.assign(ctx, this);
    ctx._callId = callId;
    ctx.http = new HttpClient(this.bridge, { sourceKey: this.key, logger: this.logger, gate: this.httpGate });
    return ctx;
  }

  html(htmlText) { return parseHtml(htmlText); }

  parseHtml(htmlText) { return parseHtml(htmlText); }

  setting(key) {
    return this._settings[key];
  }

  get settings() { return this._settings; }

  log(level, message) {
    if (this.logger) this.logger.log(level, `source:${this.key}`, message);
    try {
      this.bridge.call('log', 'write', this.key, { level, message: String(message) }, { callId: this._callId })
        .catch(() => {});
    } catch (_) { /* a host without log must never break a source */ }
  }

  async toast(message) {
    try {
      await this.bridge.call('ui', 'toast', this.key, { message: String(message) }, { callId: this._callId });
    } catch (_) { /* UI is optional */ }
  }

  // ---- per-source persistent store (bridge-owned) --------
  // Values are JSON-serialized on the wire; hosts store
  // strings. `kind` separates source data ('data') from user
  // settings ('settings') exactly like the two buckets hosts
  // already keep per source.
  async _storeGet(kind, key) {
    const raw = await this.bridge.call('store', 'get', this.key, { kind, key: String(key) }, { callId: this._callId });
    if (raw === null || raw === undefined) return null;
    if (typeof raw !== 'string') return raw;
    try { return JSON.parse(raw); } catch (_) { return raw; }
  }

  async _storeSet(kind, key, value) {
    await this.bridge.call('store', 'set', this.key,
      { kind, key: String(key), value: JSON.stringify(value === undefined ? null : value) },
      { callId: this._callId });
  }

  async _storeDelete(kind, key) {
    await this.bridge.call('store', 'delete', this.key, { kind, key: String(key) }, { callId: this._callId });
  }

  get data() {
    const self = this;
    return {
      get: (k) => self._storeGet('data', k),
      set: (k, v) => self._storeSet('data', k, v),
      delete: (k) => self._storeDelete('data', k),
    };
  }

  get prefs() {
    const self = this;
    return {
      get: (k) => self._storeGet('settings', k),
      set: async (k, v) => { await self._storeSet('settings', k, v); self._settings[k] = v; },
      delete: (k) => self._storeDelete('settings', k),
    };
  }
}

exports.SourceContext = SourceContext;

});
__define('src/source/define.js', function (module, exports, __require) {
// Source registry: holds source definitions, their
// manifests and lifecycle state. Registration validates the
// manifest BEFORE the source becomes callable; a source whose
// init fails stays registered in `failed` state with the
// error recorded (diagnosable, re-initializable), instead of
// silently half-working.
const { ERR, MkError } = __require('../core/errors.js');
const { validateManifest } = __require('../core/validate.js');

const SourceState = {
  REGISTERED: 'registered',
  INITIALIZING: 'initializing',
  READY: 'ready',
  FAILED: 'failed',
  DISPOSED: 'disposed',
};

class SourceRegistry {
  constructor() {
    this.entries = new Map(); // key -> entry
  }

  register(def) {
    const manifest = validateManifest(def);
    const existing = this.entries.get(manifest.key);
    if (existing && existing.state !== SourceState.DISPOSED) {
      throw new MkError(ERR.SOURCE_EXISTS, `source already registered: ${manifest.key}`);
    }
    const entry = {
      def,
      manifest,
      state: SourceState.REGISTERED,
      initError: null,
      initializedAt: null,
      callCount: 0,
      failureCount: 0,
      lastError: null,
    };
    this.entries.set(manifest.key, entry);
    return entry;
  }

  get(key) {
    return this.entries.get(key) || null;
  }

  require(key) {
    const entry = this.get(key);
    if (!entry || entry.state === SourceState.DISPOSED) {
      throw new MkError(ERR.SOURCE_NOT_FOUND, `source not registered: ${key}`);
    }
    return entry;
  }

  remove(key) {
    const entry = this.entries.get(key);
    if (entry) entry.state = SourceState.DISPOSED;
    this.entries.delete(key);
    return !!entry;
  }

  list() {
    return Array.from(this.entries.values()).map((e) => ({
      ...e.manifest,
      state: e.state,
      initError: e.initError ? String(e.initError.message || e.initError) : null,
      callCount: e.callCount,
      failureCount: e.failureCount,
      lastError: e.lastError ? String(e.lastError.message || e.lastError) : null,
    }));
  }
}

/// Extract the settings schema from a definition's
/// `settings` object ({key: {title, type, options?, default,
/// validator?, buttonText?, callback?}}). Values only — the
/// callbacks stay on the definition.
function settingsSchemaOf(def) {
  const out = [];
  const settings = def && def.settings;
  if (!settings || typeof settings !== 'object') return out;
  for (const key of Object.keys(settings)) {
    const s = settings[key];
    if (!s || typeof s !== 'object') continue;
    out.push({
      key,
      title: s.title || key,
      type: s.type || 'input',
      options: Array.isArray(s.options) ? s.options : [],
      default: s.default === undefined ? null : s.default,
      validator: s.validator || null,
      buttonText: s.buttonText || null,
      hasCallback: typeof s.callback === 'function',
    });
  }
  return out;
}

/// Default settings snapshot: schema defaults overlaid with
/// stored user values (stored wins).
function settingsSnapshotOf(def, stored) {
  const snap = {};
  for (const item of settingsSchemaOf(def)) {
    if (item.default !== null && item.default !== undefined) snap[item.key] = item.default;
  }
  if (stored && typeof stored === 'object') {
    for (const k of Object.keys(stored)) snap[k] = stored[k];
  }
  return snap;
}

exports.SourceState = SourceState;
exports.SourceRegistry = SourceRegistry;
exports.settingsSchemaOf = settingsSchemaOf;
exports.settingsSnapshotOf = settingsSnapshotOf;

});
__define('src/source/dispatcher.js', function (module, exports, __require) {
// Dispatcher: the single entry point hosts call
// (MangaKit.call). It resolves the source's handler for a
// kind, runs it with a call-scoped ctx, enforces the per-kind
// time budget, and normalizes the result through the data
// engine. Source-thrown values of any type are wrapped into
// MkError so hosts never see a bare string rejection.
const { ERR, MkError, wrapError } = __require('../core/errors.js');
const { withTimeout } = __require('../core/utils.js');
const { normalizePaged, normalizeSections, normalizeDetails, normalizeChapters, normalizePages, normalizeCategories } = __require('../core/validate.js');
const { SourceState } = __require('./define.js');
const { isVerificationMessage } = __require('../core/verification.js');

const KIND_TIMEOUTS = {
  search: 30000,
  explore: 30000,
  categories: 30000,
  category: 30000,
  details: 60000,
  chapters: 60000,
  pages: 60000,
  thumbnails: 30000,
  imageOnResponse: 60000,
  imageModify: 60000,
  imageFallback: 30000,
  account: 15000,
  login: 180000,
  logout: 15000,
};

function handlerOf(def, kind) {
  switch (kind) {
    case 'search': return def.search;
    case 'explore': return def.explore;
    case 'details': return def.details;
    case 'chapters': return def.chapters;
    case 'pages': return def.pages;
    case 'categories': return def.categories;
    case 'category': return def.category;
    case 'thumbnails': return def.thumbnails;
    case 'imageOnResponse': return def.imageOnResponse;
    case 'imageModify': return def.imageModify;
    case 'imageFallback': return def.imageFallback;
    default: return null;
  }
}

function asLoadFn(handler) {
  if (typeof handler === 'function') return handler;
  if (handler && typeof handler === 'object' && typeof handler.load === 'function') return handler.load;
  return null;
}

// Kinds whose results are safe to reuse for a couple of
// seconds: the read-only discovery surfaces that hosts
// re-request every time a screen is entered or refreshed.
// Writes and account flows are never guarded.
const REFRESH_GUARDED_KINDS = new Set(['explore', 'search', 'category']);

function stableArgsKey(args) {
  const keys = Object.keys(args)
    .filter((k) => k !== 'refresh' && k !== 'onSection')
    .sort();
  return keys.map((k) => `${k}=${JSON.stringify(args[k])}`).join('&');
}

class Dispatcher {
  constructor({ registry, bridge, logger, makeContext, refreshGuardMs }) {
    this.registry = registry;
    this.bridge = bridge;
    this.logger = logger;
    this.makeContext = makeContext;
    this.callSeq = 0;
    this.refreshGuardMs = refreshGuardMs === undefined ? 2000 : refreshGuardMs;
    this._refreshMemo = new Map();
  }

  async call(sourceKey, kind, args = {}) {
    // Refresh guard: identical read calls inside the guard
    // window share one execution — hosts re-entering a
    // screen or double-firing a refresh must not fan out
    // into duplicate network storms. An explicit
    // args.refresh === true (pull-to-refresh) always runs.
    if (this.refreshGuardMs > 0 && REFRESH_GUARDED_KINDS.has(kind)
      && args.refresh !== true && typeof args.onSection !== 'function') {
      const memoKey = `${sourceKey}|${kind}|${stableArgsKey(args)}`;
      const existing = this._refreshMemo.get(memoKey);
      if (existing && (existing.pending || Date.now() - existing.at < this.refreshGuardMs)) {
        return existing.promise;
      }
      const slot = { at: Date.now(), pending: true, promise: this._callInner(sourceKey, kind, args) };
      this._refreshMemo.set(memoKey, slot);
      slot.promise.then(
        () => { slot.pending = false; slot.at = Date.now(); },
        () => { if (this._refreshMemo.get(memoKey) === slot) this._refreshMemo.delete(memoKey); },
      );
      return slot.promise;
    }
    return this._callInner(sourceKey, kind, args);
  }

  async _callInner(sourceKey, kind, args = {}) {
    const entry = this.registry.require(sourceKey);
    if (entry.state === SourceState.FAILED) {
      throw new MkError(ERR.INIT_FAILED,
        `source ${sourceKey} failed to initialize: ${entry.initError ? entry.initError.message || entry.initError : 'unknown'}`,
        { sourceKey, kind });
    }
    if (entry.state !== SourceState.READY) {
      throw new MkError(ERR.NOT_INITIALIZED, `source ${sourceKey} is ${entry.state}`, { sourceKey, kind });
    }
    const callId = `${sourceKey}#${++this.callSeq}`;
    const started = Date.now();
    entry.callCount++;
    try {
      const result = await withTimeout(
        this._dispatch(entry, kind, args, callId),
        KIND_TIMEOUTS[kind] || 30000,
        () => new MkError(ERR.TIMEOUT, `${kind} timed out`, { sourceKey, callId, kind }),
      );
      if (this.logger) this.logger.debug('dispatch', `${callId} ${kind} ok in ${Date.now() - started}ms`);
      return result;
    } catch (e) {
      entry.failureCount++;
      entry.lastError = e;
      if (this.logger) this.logger.error('dispatch', `${callId} ${kind} failed: ${e && e.message ? e.message : e}`);
      throw e;
    }
  }

  async _dispatch(entry, kind, args, callId) {
    const def = entry.def;
    const extra = { sourceKey: entry.manifest.key, callId, kind };
    const ctx = this.makeContext(entry, callId);

    if (kind === 'account') {
      const account = def.account;
      if (!account) return { hasLogin: false, hasLogout: false, isLoggedIn: false, registerWebsite: null };
      let isLoggedIn = false;
      if (typeof account.isLoggedIn === 'function') {
        isLoggedIn = !!(await this._runSource(() => account.isLoggedIn(ctx), extra));
      }
      return {
        hasLogin: typeof account.login === 'function',
        hasLogout: typeof account.logout === 'function',
        isLoggedIn,
        registerWebsite: account.registerWebsite || null,
      };
    }
    if (kind === 'login' || kind === 'logout') {
      const account = def.account;
      const fn = account && account[kind];
      if (typeof fn !== 'function') {
        throw new MkError(ERR.UNSUPPORTED_KIND, `source has no account.${kind}`, extra);
      }
      await this._runSource(() => (kind === 'login'
        ? fn(ctx, { username: args.username, password: args.password })
        : fn(ctx)), extra);
      return { ok: true };
    }

    const handler = handlerOf(def, kind);
    const load = asLoadFn(handler);
    if (!load) {
      // Explore may be a section list: [{title, load}].
      if (kind === 'explore' && Array.isArray(handler)) {
        const loadable = handler.filter((s) => s && typeof s.load === 'function');
        const perSection = new Array(loadable.length).fill(null);
        // Sections load concurrently (bounded) — explore is
        // the app's cold-start screen and section loads are
        // independent network calls; order is preserved in
        // the result regardless of completion order, and
        // args.onSection streams each section to the host
        // the moment it lands (progressive output).
        let cursor = 0;
        const worker = async () => {
          while (cursor < loadable.length) {
            const index = cursor++;
            const section = loadable[index];
            const raw = await this._runSource(
              () => section.load(ctx, { page: args.page || 1 }), extra);
            // A section load may return a paged list OR a
            // map of sub-sections; normalizeSections covers
            // both.
            const subs = normalizeSections(raw, entry.manifest.key, extra)
              .map((sub) => ({ title: sub.title || section.title || '', items: sub.items }));
            perSection[index] = subs;
            if (typeof args.onSection === 'function') {
              for (const sub of subs) {
                try { args.onSection(sub, index); } catch (_) { /* host callback must not break loading */ }
              }
            }
          }
        };
        await Promise.all([worker(), worker(), worker(), worker()]);
        return { sections: perSection.flat().filter(Boolean) };
      }
      throw new MkError(ERR.UNSUPPORTED_KIND, `source does not implement ${kind}`, extra);
    }

    switch (kind) {
      case 'search': {
        const raw = await this._runSource(() => load(ctx, {
          keyword: args.keyword || '', page: args.page || 1, options: args.options || [],
        }), extra);
        return normalizePaged(raw, entry.manifest.key, extra);
      }
      case 'explore': {
        const raw = await this._runSource(() => load(ctx, { page: args.page || 1 }), extra);
        return { sections: normalizeSections(raw, entry.manifest.key, extra) };
      }
      case 'details': {
        const raw = await this._runSource(() => load(ctx, { id: args.id }), extra);
        return normalizeDetails(raw, entry.manifest.key, { ...extra, id: args.id });
      }
      case 'chapters': {
        const raw = await this._runSource(() => load(ctx, { id: args.id }), extra);
        if (Array.isArray(raw) || (raw && typeof raw === 'object' && !raw.chapters && !raw.eps)) {
          return { chapters: normalizeChapters(raw, extra) };
        }
        return { chapters: normalizeChapters(raw.chapters ?? raw.eps, extra) };
      }
      case 'pages': {
        const raw = await this._runSource(() => load(ctx, {
          comicId: args.comicId, chapterId: args.chapterId,
        }), extra);
        return normalizePages(raw, extra);
      }
      case 'categories': {
        const raw = await this._runSource(() => load(ctx, {}), extra);
        return { categories: normalizeCategories(raw, extra) };
      }
      case 'category': {
        const raw = await this._runSource(() => load(ctx, {
          category: args.category, param: args.param,
          page: args.page || 1, options: args.options || [],
        }), extra);
        return normalizePaged(raw, entry.manifest.key, extra);
      }
      case 'thumbnails': {
        const raw = await this._runSource(() => load(ctx, { id: args.id }), extra);
        const list = Array.isArray(raw) ? raw : (raw && raw.images) || [];
        return { images: list.map((u) => (typeof u === 'string' ? u : (u && u.url) || '')).filter(Boolean) };
      }
      case 'imageOnResponse': {
        const raw = await this._runSource(() => load(ctx, {
          mode: args.mode, of: args.of, id: args.id, ep: args.ep, bytesB64: args.bytesB64,
        }), extra);
        return { ok: !!(raw && raw.ok), bytesB64: raw && raw.bytesB64 ? raw.bytesB64 : null };
      }
      case 'imageModify': {
        const raw = await this._runSource(() => load(ctx, {
          code: args.code, bytesB64: args.bytesB64,
        }), extra);
        return { ok: !!(raw && raw.ok), bytesB64: raw && raw.bytesB64 ? raw.bytesB64 : null };
      }
      case 'imageFallback': {
        const raw = await this._runSource(() => load(ctx, {
          of: args.of, id: args.id, ep: args.ep,
        }), extra);
        if (!raw) return { image: null };
        const normalized = normalizePages({ images: [raw] }, extra);
        return { image: normalized.images[0] || null };
      }
      default:
        throw new MkError(ERR.UNSUPPORTED_KIND, `unknown kind: ${kind}`, extra);
    }
  }

  async _runSource(fn, extra) {
    try {
      return await fn();
    } catch (e) {
      if (e instanceof MkError) throw e;
      // Sources surface verification walls as their own
      // prose; classify them into the stable code so hosts
      // can offer the clear-the-wall flow uniformly.
      if (isVerificationMessage(e && e.message ? e.message : String(e))) {
        throw new MkError(ERR.VERIFICATION_REQUIRED,
          e && e.message ? e.message : String(e), { ...extra, cause: e });
      }
      throw wrapError(e, ERR.SOURCE_THROW, extra);
    }
  }
}

exports.KIND_TIMEOUTS = KIND_TIMEOUTS;
exports.Dispatcher = Dispatcher;

});
__define('src/source/manager.js', function (module, exports, __require) {
// MangaKit engine facade — what a host actually holds.
// Owns the registry, the bridge, per-source settings
// snapshots and init lifecycle. All state lives in this
// object; creating a second engine is how tests isolate.
const { ERR, MkError } = __require('../core/errors.js');
const { BridgeClient } = __require('../core/bridge.js');
const { MkLogger } = __require('../core/logger.js');
const { withTimeout } = __require('../core/utils.js');
const { SourceRegistry, SourceState, settingsSchemaOf, settingsSnapshotOf } = __require('./define.js');
const { SourceContext } = __require('./context.js');
const { Dispatcher } = __require('./dispatcher.js');

const INIT_TIMEOUT_MS = 15000;

class MangaKitEngine {
  constructor({ host, logger, httpGate, refreshGuardMs } = {}) {
    this.logger = logger || new MkLogger();
    this.bridge = new BridgeClient({ host: host || null, logger: this.logger });
    this.registry = new SourceRegistry();
    this.httpGate = httpGate || null;
    this.dispatcher = new Dispatcher({
      registry: this.registry,
      bridge: this.bridge,
      logger: this.logger,
      makeContext: (entry, callId) => this._makeContext(entry, callId),
      refreshGuardMs,
    });
  }

  setHost(host) { this.bridge.setHost(host); }

  _makeContext(entry, callId) {
    const ctx = new SourceContext({
      bridge: this.bridge,
      logger: this.logger,
      sourceKey: entry.manifest.key,
      settings: entry.settingsSnapshot || {},
      httpGate: this.httpGate,
    });
    return callId ? ctx._withCall(callId) : ctx;
  }

  /// Register a source definition object. Runs init (when
  /// present) with a bounded budget; an init failure leaves
  /// the source registered in `failed` state with the error
  /// recorded. `storedSettings` may pre-seed user settings
  /// (hosts that keep them outside the bridge store).
  /// `settingsRef` may supply the object to use AS the
  /// settings snapshot (filled in place with defaults +
  /// stored values before init runs) — layers that read
  /// settings synchronously (the compat layer) hold this
  /// reference and must see correct values during init too.
  async registerSource(def, { storedSettings, settingsRef } = {}) {
    const entry = this.registry.register(def);
    if (settingsRef) {
      Object.assign(settingsRef, settingsSnapshotOf(def, storedSettings || {}));
      entry.settingsSnapshot = settingsRef;
    } else {
      entry.settingsSnapshot = settingsSnapshotOf(def, storedSettings || {});
    }
    // Stored settings from the bridge store overlay defaults.
    if (this.bridge.available) {
      for (const item of settingsSchemaOf(def)) {
        try {
          const raw = await this.bridge.call('store', 'get', entry.manifest.key,
            { kind: 'settings', key: item.key });
          if (raw !== null && raw !== undefined) {
            try { entry.settingsSnapshot[item.key] = JSON.parse(raw); }
            catch (_) { entry.settingsSnapshot[item.key] = raw; }
          }
        } catch (e) {
          if (!e || e.code !== ERR.HOST_MISSING) throw e;
          break; // host has no store: defaults only
        }
      }
    }
    await this._initEntry(entry);
    return entry.manifest;
  }

  async _initEntry(entry) {
    entry.state = SourceState.INITIALIZING;
    entry.initError = null;
    const init = entry.def.init;
    if (typeof init !== 'function') {
      entry.state = SourceState.READY;
      entry.initializedAt = Date.now();
      return;
    }
    try {
      await withTimeout(
        Promise.resolve(init(this._makeContext(entry, null))),
        INIT_TIMEOUT_MS,
        () => new MkError(ERR.INIT_FAILED, `init timed out after ${INIT_TIMEOUT_MS}ms`, { sourceKey: entry.manifest.key }),
      );
      entry.state = SourceState.READY;
      entry.initializedAt = Date.now();
    } catch (e) {
      entry.state = SourceState.FAILED;
      entry.initError = e;
      entry.lastError = e;
      this.logger.error('manager', `init failed for ${entry.manifest.key}: ${e && e.message ? e.message : e}`);
    }
  }

  async reinit(key) {
    const entry = this.registry.require(key);
    await this._initEntry(entry);
    return entry.state;
  }

  call(key, kind, args) {
    return this.dispatcher.call(key, kind, args);
  }

  removeSource(key) {
    return this.registry.remove(key);
  }

  listSources() {
    return this.registry.list();
  }

  diagnostics(key) {
    const entry = this.registry.get(key);
    if (!entry) return null;
    return {
      ...entry.manifest,
      state: entry.state,
      initError: entry.initError ? String(entry.initError.message || entry.initError) : null,
      initializedAt: entry.initializedAt,
      callCount: entry.callCount,
      failureCount: entry.failureCount,
      lastError: entry.lastError ? String(entry.lastError.message || entry.lastError) : null,
      settingsSchema: settingsSchemaOf(entry.def),
    };
  }

  settingsSchema(key) {
    return settingsSchemaOf(this.registry.require(key).def);
  }

  /// Persist a user setting: bridge store first, then the
  /// in-memory snapshot, then the source's change hook.
  async writeSetting(key, name, value) {
    const entry = this.registry.require(key);
    if (this.bridge.available) {
      try {
        await this.bridge.call('store', 'set', key,
          { kind: 'settings', key: name, value: JSON.stringify(value === undefined ? null : value) });
      } catch (e) {
        if (!e || e.code !== ERR.HOST_MISSING) throw e;
      }
    }
    // Mutate in place: compat layers and live contexts hold a
    // reference to this snapshot and must see writes.
    if (!entry.settingsSnapshot) entry.settingsSnapshot = {};
    entry.settingsSnapshot[name] = value;
    const hook = entry.def.onSettingChange;
    if (typeof hook === 'function') {
      await hook(this._makeContext(entry, null), { key: name, value });
    }
  }

  async invokeSettingCallback(key, name) {
    const entry = this.registry.require(key);
    const def = entry.def.settings && entry.def.settings[name];
    if (!def || typeof def.callback !== 'function') {
      throw new MkError(ERR.UNSUPPORTED_KIND, `setting ${name} has no callback`, { sourceKey: key });
    }
    await def.callback(this._makeContext(entry, null));
    return { ok: true };
  }
}

exports.MangaKitEngine = MangaKitEngine;

});

var __entry = __load('src/index.js');
var __api = __entry.createMangaKit();
__entry.installGlobals(__api);
global.MangaKit = __api;
})(typeof globalThis !== 'undefined' ? globalThis : this);
