/// JavaScript glue for the Venera-compatible source runtime.
///
/// Venera sources are plain JS classes extending `ComicSource`
/// (defined by the bundled _venera_.js library), and every
/// native capability flows through one global: `sendMessage`.
/// Batch 34 rebuilt the host on Venera's own architecture
/// (flutter_qjs + a background isolate + an injected Dart
/// function bridge — see venera_engine.dart), so the runtime
/// is assembled in stages:
///
/// 1. [veneraScriptStash] binds `__dartSendMessage` to the
///    injected native bridge function.
/// 2. At registration the host seeds
///    `globalThis.__anikumoKvByKey[sourceKey]` with the source's
///    persisted data/settings (one shared runtime hosts all
///    sources; the library includes its key in every data
///    message, which is what the shim routes on).
/// 3. [veneraBridgeScript] installs Venera-semantics
///    `sendMessage`: the data/setting methods Venera answers
///    synchronously are served synchronously from the KV
///    store (with write-through persistence), cookies live in
///    a JS mirror jar, and everything else (http…) crosses to
///    Dart through the native bridge, whose returned Dart
///    Futures surface as real JS Promises.
/// 4. The bundled _venera_.js library is evaluated.
/// 5. [veneraOverridesScript] replaces the pieces that cannot
///    cross an async bridge synchronously: `compute` (pure JS)
///    and `HtmlDocument`/`HtmlElement` (a compact pure-JS HTML
///    parser + selector engine below).
/// 6. The downloaded source file is evaluated, then
///    [veneraInstantiateScript] creates the instance.
const String veneraScriptStash = '''
globalThis.__dartSendMessage = globalThis.__anikumoNativeBridge;
''';

const String veneraBridgeScript = r'''
if (typeof appVersion === 'undefined') {
  // Batch 25 (compat): report 1.6.0, the plaza's mainstream
  // minAppVersion (e.g. copy_manga declares 1.6.0 and gates
  // features on isAppVersionAfter). 1.5.0 silently disabled
  // those branches. The bridge covers the documented
  // 1.6-era surface; genuinely unsupported areas
  // (AES-CFB/OFB, RSA) still fail loudly by design. Login
  // flows ride the UI channel since batch 74, GBK rides
  // gbk_table.dart since batch 76.
  globalThis.appVersion = '1.6.0';
}
globalThis.__anikumoJar = {};
// Batch 34: one runtime hosts every source (Venera's model),
// so persisted data/settings live in a per-source-key map.
// The library includes its key in every data message, which
// is what makes concurrent sources safe here.
globalThis.__anikumoKvByKey = {};
function __anikumoKvFor(key) {
  if (!key) return {data: {}, settings: {}};
  var kv = globalThis.__anikumoKvByKey[key];
  if (!kv) {
    kv = {data: {}, settings: {}};
    globalThis.__anikumoKvByKey[key] = kv;
  }
  return kv;
}
function __anikumoPersist(key) {
  try {
    if (!key) return;
    globalThis.__dartSendMessage(
        'anikumoPersist',
        JSON.stringify({key: key, kv: __anikumoKvFor(key)}));
  } catch (e) {}
}
function __anikumoHostOf(url) {
  try { return new URL(url).hostname; } catch (e) { return ''; }
}
function __anikumoPersistJar() {
  // Batch 101: the jar used to live and die inside this
  // runtime — every engine kill and app restart forgot all
  // cookies. Report each mutation to the host, which
  // persists it (debounced) and restores it at spawn.
  try {
    globalThis.__dartSendMessage(
        'anikumoPersistCookies',
        JSON.stringify(globalThis.__anikumoJar || {}));
  } catch (e) {}
}
function __anikumoCookieApply(host, cookies) {
  var jar = globalThis.__anikumoJar[host] ||
      (globalThis.__anikumoJar[host] = {});
  (cookies || []).forEach(function (c) {
    if (typeof c === 'string') {
      var pair = c.split(';')[0].split('=');
      if (pair.length >= 2) {
        jar[pair[0].trim()] = pair.slice(1).join('=').trim();
      }
    } else if (c && c.name) {
      jar[c.name] = c.value;
    }
  });
  __anikumoPersistJar();
}
function __anikumoCookie(msg) {
  var host = __anikumoHostOf(msg.url || '');
  if (msg.function === 'set') {
    __anikumoCookieApply(host, msg.cookies);
    return true;
  }
  if (msg.function === 'get') {
    var jar = globalThis.__anikumoJar[host] || {};
    return Object.keys(jar).map(function (k) {
      return {name: k, value: jar[k], domain: host};
    });
  }
  if (msg.function === 'delete') {
    delete globalThis.__anikumoJar[host];
    __anikumoPersistJar();
    return true;
  }
  return null;
}
function __anikumoHttp(msg) {
  var headers = {};
  var src = msg.headers || {};
  Object.keys(src).forEach(function (k) { headers[k] = src[k]; });
  var host = __anikumoHostOf(msg.url || '');
  var jar = globalThis.__anikumoJar[host] || {};
  var names = Object.keys(jar);
  if (names.length && !headers['Cookie'] && !headers['cookie']) {
    headers['Cookie'] = names.map(function (k) {
      return k + '=' + jar[k];
    }).join('; ');
  }
  var out = {};
  Object.keys(msg).forEach(function (k) { out[k] = msg[k]; });
  out.headers = headers;
  return globalThis.__dartSendMessage('anikumoBridge', JSON.stringify(out))
      .then(function (s) {
        var res;
        try { res = JSON.parse(s); } catch (e) { res = {error: String(s)}; }
        if (res && res.headers && res.headers['set-cookie']) {
          var sc = res.headers['set-cookie'];
          __anikumoCookieApply(
              host, Array.isArray(sc) ? sc : String(sc).split('\n'));
        }
        return res;
      });
}
// Batch 103: the image bridge. The bundled library's Image
// class calls sendMessage({method: 'image', ...})
// SYNCHRONOUSLY and expects the new image key / size back as
// a plain value (the reference runtime answers through a
// synchronous native call). The host backs this channel with
// a decoded-image registry in the engine isolate (dart
// `image` package), so it can answer synchronously too.
// Returns the envelope {ok, v, fmt?}; lib-facing callers
// unwrap .v, dispatcher code reads the whole envelope.
function __anikumoImageCall(payload) {
  try {
    var raw = globalThis.__dartSendMessage(
        'anikumoImage', JSON.stringify(payload));
    var env = JSON.parse(raw);
    return (env && typeof env === 'object') ? env : { ok: false };
  } catch (e) {
    return { ok: false };
  }
}

function sendMessage(msg) {
  var kv = __anikumoKvFor(msg && msg.key);
  if (msg && typeof msg === 'object') {
    switch (msg.method) {
      case 'load_data':
        return (msg.data_key in kv.data) ? kv.data[msg.data_key] : null;
      case 'save_data':
        kv.data[msg.data_key] = msg.data;
        __anikumoPersist(msg.key);
        return true;
      case 'delete_data':
        delete kv.data[msg.data_key];
        __anikumoPersist(msg.key);
        return true;
      case 'load_setting':
        return (msg.setting_key in kv.settings)
            ? kv.settings[msg.setting_key]
            : null;
      case 'save_setting':
        kv.settings[msg.setting_key] = msg.data;
        __anikumoPersist(msg.key);
        return true;
      case 'isLogged':
        return !!kv.data['token'];
      case 'getLocale':
        return 'zh_CN';
      case 'getPlatform':
        return 'android';
      case 'cookie':
        return __anikumoCookie(msg);
      case 'random':
        // Batch 18: the library's randomInt/randomDouble return
        // sendMessage('random') directly, expecting a synchronous
        // number (the original runtime answers synchronously).
        // Falling through to the async host channel handed
        // sources a Promise — copy_manga built "[object Promise]"
        // device strings and NUL-filled device ids from it.
        var __lo = (typeof msg.min === 'number') ? msg.min : 0;
        var __hi = (typeof msg.max === 'number') ? msg.max : 1;
        if (msg.type === 'int') {
          return Math.floor(__lo + Math.random() * (__hi - __lo + 1));
        }
        return __lo + Math.random() * (__hi - __lo);
      case 'uuid':
        return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(
            /[xy]/g, function (c) {
              var r = Math.random() * 16 | 0;
              var v = c === 'x' ? r : (r & 0x3 | 0x8);
              return v.toString(16);
            });
      case 'image': {
        // Batch 103: synchronous image ops for the library's
        // Image class (used inside modifyImage snippets).
        var ienv = __anikumoImageCall(msg);
        return ienv.ok ? ienv.v : null;
      }
      case 'http':
        return __anikumoHttp(msg);
      case 'UI':
        return __anikumoUi(msg);
      case 'log':
        // Batch 37: sources log arbitrary values — including
        // our own DOM elements, whose parent pointers are
        // circular. JSON.stringify on those threw INSIDE the
        // source's parse loop and killed the whole load
        // (mh18). Logging is fire-and-forget: stringify
        // safely, forward, never throw.
        try {
          globalThis.__dartSendMessage(
              'anikumoLog',
              '[' + (msg.level || 'info') + '] ' +
                  (msg.title || '') + ' ' +
                  __anikumoSafeString(msg.content));
        } catch (e) {}
        return true;
    }
  }
  return globalThis.__dartSendMessage(
          'anikumoBridge', __anikumoSafeJson(msg))
      .then(function (s) {
        try { return JSON.parse(s); } catch (e) { return s; }
      });
}

// Batch 74: the UI channel. UI messages carry callbacks
// (dialog actions, input validators) that cannot cross the
// JSON bridge, so they are resolved HERE, on the JS side:
// the host (MangaUiGateway, reached through the isolate's
// 'anikumoUi' channel) only renders primitives — a dialog
// with labelled buttons, a text field, a list — and reports
// back which button was tapped / what was typed. Callbacks
// and validators then run locally, exactly as the library
// expects.
function __anikumoUiRequest(payload) {
  return globalThis.__dartSendMessage(
          'anikumoUi', __anikumoSafeJson(payload))
      .then(function (s) {
        try { return JSON.parse(s); } catch (e) { return s; }
      });
}
async function __anikumoUi(msg) {
  var fn = msg['function'];
  if (fn === 'showDialog') {
    var actions = Array.isArray(msg.actions) ? msg.actions : [];
    var callbacks = actions.map(function (a) {
      return a && typeof a.callback === 'function' ? a.callback : null;
    });
    var plainActions = actions.map(function (a) {
      return {
        text: String((a && a.text) || ''),
        style: (a && a.style) || 'text',
      };
    });
    var dlgRes = await __anikumoUiRequest({
      method: 'UI', 'function': 'showDialog',
      title: msg.title || '', content: msg.content || '',
      actions: plainActions,
    });
    if (dlgRes && dlgRes.error) return dlgRes;
    var idx =
        (dlgRes && typeof dlgRes.action === 'number') ? dlgRes.action : -1;
    if (idx >= 0 && callbacks[idx]) {
      try { await callbacks[idx](); } catch (e) {}
    }
    return dlgRes;
  }
  if (fn === 'showInputDialog') {
    var errorText = null;
    while (true) {
      var r = await __anikumoUiRequest({
        method: 'UI', 'function': 'showInputDialog',
        title: msg.title || '',
        image: (typeof msg.image === 'string') ? msg.image : null,
        error: errorText,
      });
      if (r && r.error) throw new Error(String(r.error));
      var value = (r && typeof r.value === 'string') ? r.value : null;
      if (value === null) return null;
      if (typeof msg.validator === 'function') {
        var verdict = null;
        try {
          verdict = msg.validator(value);
        } catch (e) {
          verdict = String(e);
        }
        if (typeof verdict === 'string' && verdict) {
          errorText = verdict;
          continue;
        }
      }
      return value;
    }
  }
  var out = await __anikumoUiRequest(msg);
  if (out && out.error) {
    // Awaited calls (select / loading) must fail loudly;
    // fire-and-forget calls (message / launch / cancel)
    // just hand the result back like other bridge calls.
    if (fn === 'showSelectDialog' || fn === 'showLoading') {
      throw new Error(String(out.error));
    }
    return out;
  }
  return out;
}

function __anikumoSafeString(v) {
  if (typeof v === 'string') return v;
  try {
    return __anikumoSafeJson(v);
  } catch (e) {
    try { return String(v); } catch (e2) { return '[unprintable]'; }
  }
}

function __anikumoSafeJson(v) {
  var seen = [];
  return JSON.stringify(v, function (k, val) {
    if (val && typeof val === 'object') {
      if (seen.indexOf(val) >= 0) return '[circular]';
      seen.push(val);
    }
    return val;
  });
}

''';

/// Overrides applied after the stock library loads: `compute`
/// evaluated locally, and a pure-JS HTML implementation (the
/// stock one round-trips every query through the native side
/// synchronously, which an async channel cannot do).
const String veneraOverridesScript = r'''
compute = function (func) {
  var args = Array.prototype.slice.call(arguments, 1);
  var fn = (0, eval)('(' + func + ')');
  return Promise.resolve(fn(args));
};

class __AnikumoHtmlElement {
  constructor(tag, attrs) {
    this.tagName = (tag || '').toLowerCase();
    this.attributes = attrs || {};
    this.childNodes = [];
    this.parentNode = null;
  }
  get children() {
    return this.childNodes.filter(function (n) {
      return n instanceof __AnikumoHtmlElement;
    });
  }
  get nodes() { return this.children; }
  get text() {
    var out = '';
    var walk = function (n) {
      n.childNodes.forEach(function (c) {
        if (typeof c === 'string') out += c; else walk(c);
      });
    };
    walk(this);
    return out;
  }
  get innerHTML() {
    return this.childNodes.map(__anikumoSerializeNode).join('');
  }
  get outerHTML() { return __anikumoSerializeNode(this); }
  getAttribute(name) {
    var v = this.attributes[name];
    return v === undefined ? null : v;
  }
  // Batch 37: element surface the stock HtmlElement exposes
  // and sources read (id / classNames / localName / parent /
  // element siblings).
  get id() { return this.attributes['id'] || ''; }
  get classNames() {
    var c = this.attributes['class'];
    return c ? c.split(/\s+/).filter(Boolean) : [];
  }
  get localName() { return this.tagName; }
  get parent() { return this.parentNode; }
  get nextElementSibling() {
    if (!this.parentNode) return null;
    var sibs = this.parentNode.children;
    var i = sibs.indexOf(this);
    return i >= 0 && i + 1 < sibs.length ? sibs[i + 1] : null;
  }
  get previousElementSibling() {
    if (!this.parentNode) return null;
    var sibs = this.parentNode.children;
    var i = sibs.indexOf(this);
    return i > 0 ? sibs[i - 1] : null;
  }
  querySelector(query) {
    var all = __anikumoQueryAll(this, query);
    return all.length ? all[0] : null;
  }
  querySelectorAll(query) { return __anikumoQueryAll(this, query); }
}

function __anikumoSerializeNode(n) {
  if (typeof n === 'string') {
    return n.replace(/&/g, '&amp;').replace(/</g, '&lt;');
  }
  var attrs = Object.keys(n.attributes).map(function (k) {
    return ' ' + k + '="' +
        String(n.attributes[k]).replace(/"/g, '&quot;') + '"';
  }).join('');
  var inner = n.childNodes.map(__anikumoSerializeNode).join('');
  if (__HUNKO_VOID_TAGS[n.tagName]) {
    return '<' + n.tagName + attrs + '>';
  }
  return '<' + n.tagName + attrs + '>' + inner + '</' + n.tagName + '>';
}

var __HUNKO_VOID_TAGS = {
  area: 1, base: 1, br: 1, col: 1, embed: 1, hr: 1, img: 1,
  input: 1, link: 1, meta: 1, param: 1, source: 1, track: 1, wbr: 1
};

function __anikumoDecodeEntities(s) {
  return s
      .replace(/&#x([0-9a-fA-F]+);/g, function (_, h) {
        return String.fromCharCode(parseInt(h, 16));
      })
      .replace(/&#(\d+);/g, function (_, d) {
        return String.fromCharCode(parseInt(d, 10));
      })
      .replace(/&nbsp;/g, ' ')
      .replace(/&quot;/g, '"')
      .replace(/&apos;|&#39;/g, "'")
      .replace(/&lt;/g, '<')
      .replace(/&gt;/g, '>')
      .replace(/&amp;/g, '&');
}

function __anikumoParseHtml(html) {
  var root = new __AnikumoHtmlElement('#document', {});
  var stack = [root];
  var tokenRe =
      /<!--[\s\S]*?-->|<![^>]*>|<\/?[a-zA-Z][^>]*>|[^<]+/g;
  var m;
  while ((m = tokenRe.exec(html)) !== null) {
    var tok = m[0];
    if (tok.charAt(0) !== '<') {
      stack[stack.length - 1].childNodes.push(__anikumoDecodeEntities(tok));
      continue;
    }
    if (tok.indexOf('<!--') === 0 || tok.indexOf('<!') === 0) continue;
    if (tok.charAt(1) === '/') {
      var closeName = tok.slice(2, -1).trim().toLowerCase();
      for (var i = stack.length - 1; i > 0; i--) {
        if (stack[i].tagName === closeName) {
          stack.length = i;
          break;
        }
      }
      continue;
    }
    var inner = tok.slice(1, -1);
    var selfClose = /\/\s*$/.test(inner);
    if (selfClose) inner = inner.replace(/\/\s*$/, '');
    var spaceAt = inner.search(/\s/);
    var tag = (spaceAt < 0 ? inner : inner.slice(0, spaceAt)).toLowerCase();
    var attrText = spaceAt < 0 ? '' : inner.slice(spaceAt + 1);
    var attrs = {};
    var attrRe = /([\w:-]+)(?:\s*=\s*("([^"]*)"|'([^']*)'|([^\s"'>]+)))?/g;
    var am;
    while ((am = attrRe.exec(attrText)) !== null) {
      var val = am[3] !== undefined ? am[3]
          : (am[4] !== undefined ? am[4]
          : (am[5] !== undefined ? am[5] : ''));
      attrs[am[1]] = __anikumoDecodeEntities(val);
    }
    var el = new __AnikumoHtmlElement(tag, attrs);
    el.parentNode = stack[stack.length - 1];
    stack[stack.length - 1].childNodes.push(el);
    if (!selfClose && !__HUNKO_VOID_TAGS[tag]) {
      stack.push(el);
      if (tag === 'script' || tag === 'style') {
        // Raw-text elements: swallow everything to the close tag.
        var closeTag = '</' + tag + '>';
        var end = html.toLowerCase().indexOf(closeTag, tokenRe.lastIndex);
        if (end >= 0) {
          el.childNodes.push(html.slice(tokenRe.lastIndex, end));
          tokenRe.lastIndex = end;
        }
      }
    }
  }
  return root;
}

function __anikumoParseCompound(text) {
  var compound = {tag: null, id: null, classes: [], attrs: [], pseudos: []};
  var re = /(\*)|([a-zA-Z][\w-]*)|\.([\w-]+)|#([\w-]+)|\[([\w:-]+)(?:([~|^$*]?=)\s*("([^"]*)"|'([^']*)'|([^\]]*)))?\]|:([a-zA-Z-]+)(?:\(([^)]*)\))?/g;
  var m;
  while ((m = re.exec(text)) !== null) {
    if (m[1] || m[2]) compound.tag = (m[1] || m[2]).toLowerCase();
    else if (m[3]) compound.classes.push(m[3]);
    else if (m[4]) compound.id = m[4];
    else if (m[11]) {
      // Batch 103: structural pseudo-classes (:nth-child
      // and friends). Sources build selectors with them —
      // previously the pseudo was silently dropped and the
      // compound matched EVERY sibling.
      compound.pseudos.push({
        name: m[11].toLowerCase(),
        arg: (m[12] || '').trim().toLowerCase(),
      });
    }
    else if (m[5]) {
      compound.attrs.push({
        name: m[5],
        op: m[6] || null,
        value: m[8] !== undefined ? m[8]
            : (m[9] !== undefined ? m[9]
            : (m[10] !== undefined ? m[10].trim() : null)),
      });
    }
  }
  return compound;
}

function __anikumoMatchesCompound(el, compound) {
  if (!(el instanceof __AnikumoHtmlElement)) return false;
  if (compound.tag && compound.tag !== '*' && el.tagName !== compound.tag) {
    return false;
  }
  if (compound.id && el.attributes['id'] !== compound.id) return false;
  var classAttr = (el.attributes['class'] || '').split(/\s+/);
  for (var i = 0; i < compound.classes.length; i++) {
    if (classAttr.indexOf(compound.classes[i]) < 0) return false;
  }
  for (var j = 0; j < compound.attrs.length; j++) {
    var a = compound.attrs[j];
    var v = el.attributes[a.name];
    if (v === undefined) return false;
    if (a.op === '=' && v !== a.value) return false;
    if (a.op === '*=' && v.indexOf(a.value) < 0) return false;
    if (a.op === '^=' && v.indexOf(a.value) !== 0) return false;
    if (a.op === '$=' &&
        v.slice(v.length - a.value.length) !== a.value) return false;
    if (a.op === '~=' && v.split(/\s+/).indexOf(a.value) < 0) return false;
    if (a.op === '|=' && v !== a.value && v.indexOf(a.value + '-') !== 0) {
      return false;
    }
  }
  for (var p = 0; p < compound.pseudos.length; p++) {
    if (!__anikumoMatchesPseudo(el, compound.pseudos[p])) return false;
  }
  return true;
}

// Batch 103: :nth-child / :nth-of-type expression check.
// `pos` is the 1-based position; supports odd / even /
// plain integers / an+b forms (2n+1, n, -n+3, ...).
function __anikumoNthMatches(expr, pos) {
  if (expr === 'odd') return pos % 2 === 1;
  if (expr === 'even') return pos % 2 === 0;
  if (/^[+-]?\d+$/.test(expr)) return pos === parseInt(expr, 10);
  var m = /^([+-]?\d*)n([+-]\d+)?$/.exec(expr.replace(/\s+/g, ''));
  if (!m) return false;
  var a = m[1] === '' || m[1] === '+' ? 1
      : (m[1] === '-' ? -1 : parseInt(m[1], 10));
  var b = m[2] ? parseInt(m[2], 10) : 0;
  if (a === 0) return pos === b;
  var d = pos - b;
  return d % a === 0 && d / a >= 0;
}

function __anikumoMatchesPseudo(el, pseudo) {
  var name = pseudo.name;
  if (name === 'empty') {
    // No element children and no non-whitespace text.
    for (var i = 0; i < el.childNodes.length; i++) {
      var n = el.childNodes[i];
      if (n instanceof __AnikumoHtmlElement) return false;
      if (typeof n === 'string' && n.trim() !== '') return false;
    }
    return true;
  }
  var isChild = name === 'first-child' || name === 'last-child' ||
      name === 'nth-child';
  var isOfType = name === 'first-of-type' || name === 'last-of-type' ||
      name === 'nth-of-type';
  if (!isChild && !isOfType) {
    // Unknown/dynamic pseudo (:hover, :not, ...) — a static
    // document has no state for it to match against.
    return false;
  }
  var siblings = [];
  var parent = el.parentNode;
  if (parent) {
    parent.childNodes.forEach(function (c) {
      if (c instanceof __AnikumoHtmlElement) {
        if (!isOfType || c.tagName === el.tagName) siblings.push(c);
      }
    });
  } else {
    siblings = [el];
  }
  var pos = siblings.indexOf(el) + 1;
  if (pos === 0) return false;
  if (name.indexOf('first') === 0) return pos === 1;
  if (name.indexOf('last') === 0) return pos === siblings.length;
  return __anikumoNthMatches(pseudo.arg, pos);
}

function __anikumoQueryAll(rootEl, selector) {
  var results = [];
  var groups = selector.split(',');
  groups.forEach(function (group) {
    var parts = group.trim().split(/\s*(>)\s*|\s+/).filter(function (p) {
      return p !== undefined && p !== '';
    });
    // parts alternates compound, combinator, compound…
    var compounds = [];
    var combinators = [];
    parts.forEach(function (p) {
      if (p === '>') combinators.push('>');
      else {
        if (compounds.length > combinators.length) combinators.push(' ');
        compounds.push(__anikumoParseCompound(p));
      }
    });
    if (!compounds.length) return;
    var candidates = [];
    var collect = function (n) {
      n.childNodes.forEach(function (c) {
        if (c instanceof __AnikumoHtmlElement) {
          candidates.push(c);
          collect(c);
        }
      });
    };
    collect(rootEl);
    candidates.forEach(function (el) {
      var idx = compounds.length - 1;
      if (!__anikumoMatchesCompound(el, compounds[idx])) return;
      var node = el;
      var ok = true;
      while (idx > 0) {
        var comb = combinators[idx - 1] || ' ';
        idx--;
        if (comb === '>') {
          node = node.parentNode;
          if (!node || node === rootEl.parentNode ||
              !__anikumoMatchesCompound(node, compounds[idx])) {
            ok = false;
            break;
          }
        } else {
          var anc = node.parentNode;
          var found = null;
          while (anc && anc !== rootEl.parentNode) {
            if (__anikumoMatchesCompound(anc, compounds[idx])) {
              found = anc;
              break;
            }
            if (anc === rootEl) break;
            anc = anc.parentNode;
          }
          if (!found) { ok = false; break; }
          node = found;
        }
      }
      if (ok && results.indexOf(el) < 0) results.push(el);
    });
  });
  return results;
}

class __AnikumoHtmlDocument {
  constructor(html) {
    this._root = __anikumoParseHtml(String(html || ''));
  }
  querySelector(query) {
    var all = __anikumoQueryAll(this._root, query);
    return all.length ? all[0] : null;
  }
  querySelectorAll(query) { return __anikumoQueryAll(this._root, query); }
  getElementById(id) {
    var found = null;
    var walk = function (n) {
      if (found) return;
      n.childNodes.forEach(function (c) {
        if (found || typeof c === 'string') return;
        if (c.attributes && c.attributes['id'] === id) { found = c; return; }
        walk(c);
      });
    };
    walk(this._root);
    return found;
  }
  // Batch 37: the stock library's HtmlDocument has dispose()
  // (it frees the Dart-side document); 5 plaza sources call
  // it (wnacg, ehentai, manga_dex, mxs, happy) and died with
  // "TypeError: not a function" on every load. Ours is a
  // pure-JS tree — disposal is a no-op.
  dispose() {}
}

HtmlDocument = __AnikumoHtmlDocument;
HtmlElement = __AnikumoHtmlElement;
''';

/// Compat layer evaluated right after the stock library:
/// pure-JS replacements for everything the stock library
/// expects the host to do synchronously — `Convert` (utf8 /
/// base64 / hex / md5 / sha1 / sha256 / hmac), the global
/// `fetch`, and `Network.fetchBytes` (byte requests return
/// base64 in body_b64 since batch 41; decoded to a real
/// ArrayBuffer here). GBK and AES/RSA decryption throw explicit errors
/// instead of silently returning garbage.
const String veneraCompatScript = r'''

// ---- environment polyfills, applied AFTER the library ----
// Batch 18: these used to live in the bridge (before the
// library). Pre-creating globals before the library loads
// collides with the library's own lexical declarations on
// device (`let console` -> "redeclaration of 'console'" made
// EVERY JS source fail at the library stage). The library
// provides console/setTimeout/setInterval itself; URL and
// URLSearchParams it does not, so they are defined here,
// after it.
if (typeof URLSearchParams === 'undefined') {
  globalThis.URLSearchParams = class {
    constructor(init) {
      this._pairs = [];
      if (typeof init === 'string') {
        var q = init.charAt(0) === '?' ? init.slice(1) : init;
        var self = this;
        q.split('&').forEach(function (part) {
          if (!part) return;
          var eq = part.indexOf('=');
          if (eq < 0) self.append(part, '');
          else self.append(
              decodeURIComponent(part.slice(0, eq).replace(/\+/g, ' ')),
              decodeURIComponent(part.slice(eq + 1).replace(/\+/g, ' ')));
        });
      } else if (init && typeof init === 'object') {
        var self2 = this;
        Object.keys(init).forEach(function (k) {
          self2.append(k, String(init[k]));
        });
      }
    }
    append(k, v) { this._pairs.push([String(k), String(v)]); }
    set(k, v) {
      this.delete(k);
      this.append(k, v);
    }
    get(k) {
      for (var i = 0; i < this._pairs.length; i++) {
        if (this._pairs[i][0] === k) return this._pairs[i][1];
      }
      return null;
    }
    getAll(k) {
      return this._pairs.filter(function (p) { return p[0] === k; })
          .map(function (p) { return p[1]; });
    }
    has(k) { return this.get(k) !== null; }
    delete(k) {
      this._pairs = this._pairs.filter(function (p) { return p[0] !== k; });
    }
    toString() {
      return this._pairs.map(function (p) {
        return encodeURIComponent(p[0]) + '=' + encodeURIComponent(p[1]);
      }).join('&');
    }
    forEach(fn) {
      this._pairs.forEach(function (p) { fn(p[1], p[0]); });
    }
  };
}
if (typeof URL === 'undefined') {
  globalThis.URL = class {
    constructor(url, base) {
      var u = String(url);
      if (base && !/^[a-zA-Z][a-zA-Z0-9+.-]*:/.test(u)) {
        var b = new URL(base);
        if (u.charAt(0) === '/') u = b.protocol + '//' + b.host + u;
        else u = b.protocol + '//' + b.host +
            b.pathname.replace(/[^/]*$/, '') + u;
      }
      var m = u.match(
          /^([a-zA-Z][a-zA-Z0-9+.-]*:)?(\/\/([^/?#]*))?([^?#]*)(\?[^#]*)?(#.*)?$/);
      this.protocol = m[1] || '';
      var auth = m[3] || '';
      var hp = auth.split('@').pop();
      var colon = hp.lastIndexOf(':');
      this.hostname = colon >= 0 ? hp.slice(0, colon) : hp;
      this.port = colon >= 0 ? hp.slice(colon + 1) : '';
      this.host = hp;
      this.pathname = m[4] || '/';
      this.search = m[5] || '';
      this.hash = m[6] || '';
      this.origin = this.protocol + '//' + this.host;
      this.href = u;
      this.searchParams = new URLSearchParams(this.search);
    }
    toString() { return this.href; }
  };
}
function __anikumoBytes(v) {
  if (v === null || v === undefined) return new Uint8Array(0);
  if (typeof v === 'string') return __anikumoUtf8Encode(v);
  if (v instanceof Uint8Array) return v;
  if (v instanceof ArrayBuffer) return new Uint8Array(v);
  if (Array.isArray(v)) return new Uint8Array(v);
  return __anikumoUtf8Encode(String(v));
}
function __anikumoUtf8Encode(str) {
  var out = [];
  for (var i = 0; i < str.length; i++) {
    var c = str.charCodeAt(i);
    if (c < 0x80) out.push(c);
    else if (c < 0x800) {
      out.push(0xc0 | (c >> 6), 0x80 | (c & 0x3f));
    } else if (c >= 0xd800 && c <= 0xdbff && i + 1 < str.length) {
      var c2 = str.charCodeAt(++i);
      var cp = 0x10000 + ((c & 0x3ff) << 10) + (c2 & 0x3ff);
      out.push(0xf0 | (cp >> 18), 0x80 | ((cp >> 12) & 0x3f),
          0x80 | ((cp >> 6) & 0x3f), 0x80 | (cp & 0x3f));
    } else {
      out.push(0xe0 | (c >> 12), 0x80 | ((c >> 6) & 0x3f),
          0x80 | (c & 0x3f));
    }
  }
  return new Uint8Array(out);
}
function __anikumoUtf8Decode(bytes) {
  var out = '';
  var i = 0;
  while (i < bytes.length) {
    var b = bytes[i];
    var cp;
    if (b < 0x80) { cp = b; i += 1; }
    else if ((b & 0xe0) === 0xc0) {
      cp = ((b & 0x1f) << 6) | (bytes[i + 1] & 0x3f); i += 2;
    } else if ((b & 0xf0) === 0xe0) {
      cp = ((b & 0x0f) << 12) | ((bytes[i + 1] & 0x3f) << 6) |
          (bytes[i + 2] & 0x3f); i += 3;
    } else {
      cp = ((b & 0x07) << 18) | ((bytes[i + 1] & 0x3f) << 12) |
          ((bytes[i + 2] & 0x3f) << 6) | (bytes[i + 3] & 0x3f); i += 4;
    }
    if (cp > 0xffff) {
      cp -= 0x10000;
      out += String.fromCharCode(0xd800 + (cp >> 10),
          0xdc00 + (cp & 0x3ff));
    } else {
      out += String.fromCharCode(cp);
    }
  }
  return out;
}
var __anikumoB64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
function __anikumoB64Encode(bytes) {
  var out = '';
  for (var i = 0; i < bytes.length; i += 3) {
    var a = bytes[i];
    var b = i + 1 < bytes.length ? bytes[i + 1] : 0;
    var c = i + 2 < bytes.length ? bytes[i + 2] : 0;
    var n = (a << 16) | (b << 8) | c;
    out += __anikumoB64[(n >> 18) & 63] + __anikumoB64[(n >> 12) & 63] +
        (i + 1 < bytes.length ? __anikumoB64[(n >> 6) & 63] : '=') +
        (i + 2 < bytes.length ? __anikumoB64[n & 63] : '=');
  }
  return out;
}
function __anikumoB64Decode(str) {
  var clean = String(str).replace(/[^A-Za-z0-9+/=]/g, '');
  var out = [];
  for (var i = 0; i < clean.length; i += 4) {
    var a = __anikumoB64.indexOf(clean[i]);
    var b = __anikumoB64.indexOf(clean[i + 1]);
    var c = clean[i + 2] === '=' ? 0 : __anikumoB64.indexOf(clean[i + 2]);
    var d = clean[i + 3] === '=' ? 0 : __anikumoB64.indexOf(clean[i + 3]);
    var n = (a << 18) | (b << 12) | (c << 6) | d;
    out.push((n >> 16) & 0xff);
    if (clean[i + 2] !== '=') out.push((n >> 8) & 0xff);
    if (clean[i + 3] !== '=') out.push(n & 0xff);
  }
  return new Uint8Array(out);
}
function __anikumoHex(bytes) {
  var out = '';
  for (var i = 0; i < bytes.length; i++) {
    out += ('0' + bytes[i].toString(16)).slice(-2);
  }
  return out;
}
function __anikumoMd5(input) {
  var bytes = __anikumoBytes(input);
  var S = [
    7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22,
    5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20,
    4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
    6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21];
  var K = [];
  for (var ki = 0; ki < 64; ki++) {
    K.push(Math.floor(Math.abs(Math.sin(ki + 1)) * 4294967296));
  }
  var bitLen = bytes.length * 8;
  var padded = Array.from(bytes);
  padded.push(0x80);
  while (padded.length % 64 !== 56) padded.push(0);
  for (var li = 0; li < 8; li++) {
    padded.push(Math.floor(bitLen / Math.pow(2, 8 * li)) & 0xff);
  }
  var a0 = 0x67452301, b0 = 0xefcdab89, c0 = 0x98badcfe, d0 = 0x10325476;
  function rol(x, n) { return (x << n) | (x >>> (32 - n)); }
  for (var off = 0; off < padded.length; off += 64) {
    var M = [];
    for (var j = 0; j < 16; j++) {
      M.push(padded[off + j * 4] | (padded[off + j * 4 + 1] << 8) |
          (padded[off + j * 4 + 2] << 16) |
          (padded[off + j * 4 + 3] << 24));
    }
    var A = a0, B = b0, C = c0, D = d0;
    for (var t = 0; t < 64; t++) {
      var F, g;
      if (t < 16) { F = (B & C) | (~B & D); g = t; }
      else if (t < 32) { F = (D & B) | (~D & C); g = (5 * t + 1) % 16; }
      else if (t < 48) { F = B ^ C ^ D; g = (3 * t + 5) % 16; }
      else { F = C ^ (B | ~D); g = (7 * t) % 16; }
      var tmp = D;
      D = C;
      C = B;
      B = (B + rol((A + F + K[t] + M[g]) | 0, S[t])) | 0;
      A = tmp;
    }
    a0 = (a0 + A) | 0; b0 = (b0 + B) | 0;
    c0 = (c0 + C) | 0; d0 = (d0 + D) | 0;
  }
  var out = new Uint8Array(16);
  [a0, b0, c0, d0].forEach(function (w, wi) {
    out[wi * 4] = w & 0xff;
    out[wi * 4 + 1] = (w >>> 8) & 0xff;
    out[wi * 4 + 2] = (w >>> 16) & 0xff;
    out[wi * 4 + 3] = (w >>> 24) & 0xff;
  });
  return out;
}
function __anikumoSha1(input) {
  var bytes = __anikumoBytes(input);
  var bitLen = bytes.length * 8;
  var padded = Array.from(bytes);
  padded.push(0x80);
  while (padded.length % 64 !== 56) padded.push(0);
  for (var li = 7; li >= 0; li--) {
    padded.push(Math.floor(bitLen / Math.pow(2, 8 * li)) & 0xff);
  }
  var H = [0x67452301, 0xefcdab89, 0x98badcfe, 0x10325476, 0xc3d2e1f0];
  function rol(x, n) { return (x << n) | (x >>> (32 - n)); }
  for (var off = 0; off < padded.length; off += 64) {
    var W = [];
    for (var j = 0; j < 16; j++) {
      W.push((padded[off + j * 4] << 24) |
          (padded[off + j * 4 + 1] << 16) |
          (padded[off + j * 4 + 2] << 8) | padded[off + j * 4 + 3]);
    }
    for (var t = 16; t < 80; t++) {
      W.push(rol(W[t - 3] ^ W[t - 8] ^ W[t - 14] ^ W[t - 16], 1));
    }
    var a = H[0], b = H[1], c = H[2], d = H[3], e = H[4];
    for (var t2 = 0; t2 < 80; t2++) {
      var f, k;
      if (t2 < 20) { f = (b & c) | (~b & d); k = 0x5a827999; }
      else if (t2 < 40) { f = b ^ c ^ d; k = 0x6ed9eba1; }
      else if (t2 < 60) { f = (b & c) | (b & d) | (c & d); k = 0x8f1bbcdc; }
      else { f = b ^ c ^ d; k = 0xca62c1d6; }
      var tmp = (rol(a, 5) + f + e + k + W[t2]) | 0;
      e = d; d = c; c = rol(b, 30); b = a; a = tmp;
    }
    H[0] = (H[0] + a) | 0; H[1] = (H[1] + b) | 0; H[2] = (H[2] + c) | 0;
    H[3] = (H[3] + d) | 0; H[4] = (H[4] + e) | 0;
  }
  var out = new Uint8Array(20);
  H.forEach(function (w, wi) {
    out[wi * 4] = (w >>> 24) & 0xff;
    out[wi * 4 + 1] = (w >>> 16) & 0xff;
    out[wi * 4 + 2] = (w >>> 8) & 0xff;
    out[wi * 4 + 3] = w & 0xff;
  });
  return out;
}
var __anikumoSha256K = [
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1,
  0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
  0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786,
  0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147,
  0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
  0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
  0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a,
  0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
  0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2];
function __anikumoSha256(input) {
  var bytes = __anikumoBytes(input);
  var bitLen = bytes.length * 8;
  var padded = Array.from(bytes);
  padded.push(0x80);
  while (padded.length % 64 !== 56) padded.push(0);
  for (var li = 7; li >= 0; li--) {
    padded.push(Math.floor(bitLen / Math.pow(2, 8 * li)) & 0xff);
  }
  var H = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
    0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19];
  function rr(x, n) { return (x >>> n) | (x << (32 - n)); }
  for (var off = 0; off < padded.length; off += 64) {
    var W = [];
    for (var j = 0; j < 16; j++) {
      W.push((padded[off + j * 4] << 24) |
          (padded[off + j * 4 + 1] << 16) |
          (padded[off + j * 4 + 2] << 8) | padded[off + j * 4 + 3]);
    }
    for (var t = 16; t < 64; t++) {
      var s0 = rr(W[t - 15], 7) ^ rr(W[t - 15], 18) ^ (W[t - 15] >>> 3);
      var s1 = rr(W[t - 2], 17) ^ rr(W[t - 2], 19) ^ (W[t - 2] >>> 10);
      W.push((W[t - 16] + s0 + W[t - 7] + s1) | 0);
    }
    var a = H[0], b = H[1], c = H[2], d = H[3],
        e = H[4], f = H[5], g = H[6], h = H[7];
    for (var t2 = 0; t2 < 64; t2++) {
      var S1 = rr(e, 6) ^ rr(e, 11) ^ rr(e, 25);
      var ch = (e & f) ^ (~e & g);
      var t1 = (h + S1 + ch + __anikumoSha256K[t2] + W[t2]) | 0;
      var S0 = rr(a, 2) ^ rr(a, 13) ^ rr(a, 22);
      var maj = (a & b) ^ (a & c) ^ (b & c);
      var t2v = (S0 + maj) | 0;
      h = g; g = f; f = e; e = (d + t1) | 0;
      d = c; c = b; b = a; a = (t1 + t2v) | 0;
    }
    H[0] = (H[0] + a) | 0; H[1] = (H[1] + b) | 0; H[2] = (H[2] + c) | 0;
    H[3] = (H[3] + d) | 0; H[4] = (H[4] + e) | 0; H[5] = (H[5] + f) | 0;
    H[6] = (H[6] + g) | 0; H[7] = (H[7] + h) | 0;
  }
  var out = new Uint8Array(32);
  H.forEach(function (w, wi) {
    out[wi * 4] = (w >>> 24) & 0xff;
    out[wi * 4 + 1] = (w >>> 16) & 0xff;
    out[wi * 4 + 2] = (w >>> 8) & 0xff;
    out[wi * 4 + 3] = w & 0xff;
  });
  return out;
}
// Batch 103: SHA-512 (the reference runtime's Convert has
// it; one index source needs it for request signing). BigInt
// does the 64-bit words — QuickJS-NG supports it natively.
var __anikumoSha512K = null;
function __anikumoSha512(input) {
  if (!__anikumoSha512K) {
    __anikumoSha512K = (
      '428a2f98d728ae22 7137449123ef65cd b5c0fbcfec4d3b2f e9b5dba58189dbbc ' +
      '3956c25bf348b538 59f111f1b605d019 923f82a4af194f9b ab1c5ed5da6d8118 ' +
      'd807aa98a3030242 12835b0145706fbe 243185be4ee4b28c 550c7dc3d5ffb4e2 ' +
      '72be5d74f27b896f 80deb1fe3b1696b1 9bdc06a725c71235 c19bf174cf692694 ' +
      'e49b69c19ef14ad2 efbe4786384f25e3 0fc19dc68b8cd5b5 240ca1cc77ac9c65 ' +
      '2de92c6f592b0275 4a7484aa6ea6e483 5cb0a9dcbd41fbd4 76f988da831153b5 ' +
      '983e5152ee66dfab a831c66d2db43210 b00327c898fb213f bf597fc7beef0ee4 ' +
      'c6e00bf33da88fc2 d5a79147930aa725 06ca6351e003826f 142929670a0e6e70 ' +
      '27b70a8546d22ffc 2e1b21385c26c926 4d2c6dfc5ac42aed 53380d139d95b3df ' +
      '650a73548baf63de 766a0abb3c77b2a8 81c2c92e47edaee6 92722c851482353b ' +
      'a2bfe8a14cf10364 a81a664bbc423001 c24b8b70d0f89791 c76c51a30654be30 ' +
      'd192e819d6ef5218 d69906245565a910 f40e35855771202a 106aa07032bbd1b8 ' +
      '19a4c116b8d2d0c8 1e376c085141ab53 2748774cdf8eeb99 34b0bcb5e19b48a8 ' +
      '391c0cb3c5c95a63 4ed8aa4ae3418acb 5b9cca4f7763e373 682e6ff3d6b2b8a3 ' +
      '748f82ee5defb2fc 78a5636f43172f60 84c87814a1f0ab72 8cc702081a6439ec ' +
      '90befffa23631e28 a4506cebde82bde9 bef9a3f7b2c67915 c67178f2e372532b ' +
      'ca273eceea26619c d186b8c721c0c207 eada7dd6cde0eb1e f57d4f7fee6ed178 ' +
      '06f067aa72176fba 0a637dc5a2c898a6 113f9804bef90dae 1b710b35131c471b ' +
      '28db77f523047d84 32caab7b40c72493 3c9ebe0a15c9bebc 431d67c49c100d4c ' +
      '4cc5d4becb3e42b6 597f299cfc657e2a 5fcb6fab3ad6faec 6c44198c4a475817'
    ).split(/\s+/).map(function (h) { return BigInt('0x' + h); });
  }
  var K = __anikumoSha512K;
  var MASK = (1n << 64n) - 1n;
  function rotr(x, n) { return ((x >> n) | (x << (64n - n))) & MASK; }
  var H = (
    '6a09e667f3bcc908 bb67ae8584caa73b 3c6ef372fe94f82b a54ff53a5f1d36f1 ' +
    '510e527fade682d1 9b05688c2b3e6c1f 1f83d9abfb41bd6b 5be0cd19137e2179'
  ).split(/\s+/).map(function (h) { return BigInt('0x' + h); });
  var bytes = __anikumoBytes(input);
  var bitLen = BigInt(bytes.length) * 8n;
  var padded = new Uint8Array(((bytes.length + 17 + 127) >> 7) << 7);
  padded.set(bytes);
  padded[bytes.length] = 0x80;
  for (var i = 0; i < 8; i++) {
    padded[padded.length - 1 - i] = Number((bitLen >> BigInt(i * 8)) & 0xffn);
  }
  var W = new Array(80);
  for (var block = 0; block < padded.length; block += 128) {
    for (var t = 0; t < 16; t++) {
      var w = 0n;
      for (var j = 0; j < 8; j++) {
        w = (w << 8n) | BigInt(padded[block + t * 8 + j]);
      }
      W[t] = w;
    }
    for (var t2 = 16; t2 < 80; t2++) {
      var s0 = rotr(W[t2 - 15], 1n) ^ rotr(W[t2 - 15], 8n) ^ (W[t2 - 15] >> 7n);
      var s1 = rotr(W[t2 - 2], 19n) ^ rotr(W[t2 - 2], 61n) ^ (W[t2 - 2] >> 6n);
      W[t2] = (W[t2 - 16] + s0 + W[t2 - 7] + s1) & MASK;
    }
    var a = H[0], b = H[1], c = H[2], d = H[3];
    var e = H[4], f = H[5], g = H[6], h = H[7];
    for (var r = 0; r < 80; r++) {
      var S1 = rotr(e, 14n) ^ rotr(e, 18n) ^ rotr(e, 41n);
      var ch = (e & f) ^ ((~e & MASK) & g);
      var temp1 = (h + S1 + ch + K[r] + W[r]) & MASK;
      var S0 = rotr(a, 28n) ^ rotr(a, 34n) ^ rotr(a, 39n);
      var maj = (a & b) ^ (a & c) ^ (b & c);
      var temp2 = (S0 + maj) & MASK;
      h = g; g = f; f = e; e = (d + temp1) & MASK;
      d = c; c = b; b = a; a = (temp1 + temp2) & MASK;
    }
    H[0] = (H[0] + a) & MASK; H[1] = (H[1] + b) & MASK;
    H[2] = (H[2] + c) & MASK; H[3] = (H[3] + d) & MASK;
    H[4] = (H[4] + e) & MASK; H[5] = (H[5] + f) & MASK;
    H[6] = (H[6] + g) & MASK; H[7] = (H[7] + h) & MASK;
  }
  var out = new Uint8Array(64);
  H.forEach(function (w, wi) {
    for (var j = 0; j < 8; j++) {
      out[wi * 8 + j] = Number((w >> BigInt((7 - j) * 8)) & 0xffn);
    }
  });
  return out;
}
function __anikumoHash(name, value) {
  if (name === 'md5') return __anikumoMd5(value);
  if (name === 'sha1') return __anikumoSha1(value);
  if (name === 'sha256') return __anikumoSha256(value);
  if (name === 'sha512') return __anikumoSha512(value);
  throw new Error('anikumo: 不支持的哈希 ' + name);
}
function __anikumoHmac(key, value, hash) {
  var blockSize = 64;
  var k = __anikumoBytes(key);
  if (k.length > blockSize) k = __anikumoHash(hash, k);
  var ipad = new Uint8Array(blockSize).fill(0x36);
  var opad = new Uint8Array(blockSize).fill(0x5c);
  for (var i = 0; i < k.length; i++) { ipad[i] ^= k[i]; opad[i] ^= k[i]; }
  var v = __anikumoBytes(value);
  var inner = new Uint8Array(blockSize + v.length);
  inner.set(ipad); inner.set(v, blockSize);
  var innerHash = __anikumoHash(hash, inner);
  var outer = new Uint8Array(blockSize + innerHash.length);
  outer.set(opad); outer.set(innerHash, blockSize);
  return __anikumoHash(hash, outer);
}

Convert.encodeUtf8 = function (str) { return __anikumoUtf8Encode(String(str)).buffer; };
Convert.decodeUtf8 = function (value) {
  if (typeof value === 'string') return value;
  return __anikumoUtf8Decode(__anikumoBytes(value));
};
Convert.encodeBase64 = function (value) {
  return __anikumoB64Encode(__anikumoBytes(value));
};
Convert.decodeBase64 = function (value) {
  return __anikumoB64Decode(String(value)).buffer;
};
Convert.hexEncode = function (bytes) { return __anikumoHex(__anikumoBytes(bytes)); };
Convert.md5 = function (value) { return __anikumoMd5(value).buffer; };
Convert.sha1 = function (value) { return __anikumoSha1(value).buffer; };
Convert.sha256 = function (value) { return __anikumoSha256(value).buffer; };
Convert.sha512 = function (value) { return __anikumoSha512(value).buffer; };
Convert.hmac = function (key, value, hash) {
  return __anikumoHmac(key, value, hash).buffer;
};
Convert.hmacString = function (key, value, hash) {
  return __anikumoHex(__anikumoHmac(key, value, hash));
};

// Batch 37: pure-JS AES (the compat layer used to throw for
// every AES call). jm's whole API — domain config AND
// response bodies — is AES-ECB, so the source was dead
// without it. Standard FIPS-197 with programmatically
// generated S-boxes; ECB/CBC, PKCS7 padding, 128/192/256-bit
// keys. Byte values follow the Convert convention
// (ArrayBuffer in/out, via __anikumoBytes).
var __anikumoAes = (function () {
  function gfMul(a, b) {
    var p = 0;
    for (var i = 0; i < 8; i++) {
      if (b & 1) p ^= a;
      var hi = a & 0x80;
      a = (a << 1) & 0xff;
      if (hi) a ^= 0x1b;
      b >>= 1;
    }
    return p;
  }
  function gfInv(a) {
    if (a === 0) return 0;
    for (var i = 1; i < 256; i++) {
      if (gfMul(a, i) === 1) return i;
    }
    return 0;
  }
  var sbox = new Uint8Array(256);
  var invSbox = new Uint8Array(256);
  for (var si = 0; si < 256; si++) {
    var inv = gfInv(si);
    var x = inv ^ ((inv << 1) | (inv >> 7)) ^ ((inv << 2) | (inv >> 6)) ^
        ((inv << 3) | (inv >> 5)) ^ ((inv << 4) | (inv >> 4)) ^ 0x63;
    sbox[si] = x & 0xff;
    invSbox[x & 0xff] = si;
  }
  var rcon = [0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80, 0x1b, 0x36];
  function expandKey(key) {
    var Nk = key.length / 4;
    var Nr = Nk + 6;
    var w = new Uint8Array(16 * (Nr + 1));
    w.set(key);
    for (var i = Nk; i < 4 * (Nr + 1); i++) {
      var t = [w[4 * i - 4], w[4 * i - 3], w[4 * i - 2], w[4 * i - 1]];
      if (i % Nk === 0) {
        t = [sbox[t[1]] ^ rcon[i / Nk - 1], sbox[t[2]], sbox[t[3]], sbox[t[0]]];
      } else if (Nk > 6 && i % Nk === 4) {
        t = [sbox[t[0]], sbox[t[1]], sbox[t[2]], sbox[t[3]]];
      }
      for (var j = 0; j < 4; j++) w[4 * i + j] = w[4 * (i - Nk) + j] ^ t[j];
    }
    return {w: w, Nr: Nr};
  }
  function addRoundKey(st, w, round) {
    for (var i = 0; i < 16; i++) st[i] ^= w[round * 16 + i];
  }
  // State is column-major like FIPS-197: st[r + 4c].
  function subBytes(st, box) {
    for (var i = 0; i < 16; i++) st[i] = box[st[i]];
  }
  function shiftRows(st, inv) {
    var t = new Uint8Array(16);
    for (var r = 0; r < 4; r++) {
      for (var c = 0; c < 4; c++) {
        var src = inv ? (c - r + 4) % 4 : (c + r) % 4;
        t[r + 4 * c] = st[r + 4 * src];
      }
    }
    st.set(t);
  }
  function mixColumns(st, inv) {
    for (var c = 0; c < 4; c++) {
      var a0 = st[4 * c], a1 = st[4 * c + 1], a2 = st[4 * c + 2], a3 = st[4 * c + 3];
      if (!inv) {
        st[4 * c] = gfMul(a0, 2) ^ gfMul(a1, 3) ^ a2 ^ a3;
        st[4 * c + 1] = a0 ^ gfMul(a1, 2) ^ gfMul(a2, 3) ^ a3;
        st[4 * c + 2] = a0 ^ a1 ^ gfMul(a2, 2) ^ gfMul(a3, 3);
        st[4 * c + 3] = gfMul(a0, 3) ^ a1 ^ a2 ^ gfMul(a3, 2);
      } else {
        st[4 * c] = gfMul(a0, 14) ^ gfMul(a1, 11) ^ gfMul(a2, 13) ^ gfMul(a3, 9);
        st[4 * c + 1] = gfMul(a0, 9) ^ gfMul(a1, 14) ^ gfMul(a2, 11) ^ gfMul(a3, 13);
        st[4 * c + 2] = gfMul(a0, 13) ^ gfMul(a1, 9) ^ gfMul(a2, 14) ^ gfMul(a3, 11);
        st[4 * c + 3] = gfMul(a0, 11) ^ gfMul(a1, 13) ^ gfMul(a2, 9) ^ gfMul(a3, 14);
      }
    }
  }
  function cryptBlock(input, off, out, outOff, expanded, decrypt) {
    var st = new Uint8Array(16);
    for (var i = 0; i < 16; i++) st[i] = input[off + i];
    var Nr = expanded.Nr;
    if (!decrypt) {
      addRoundKey(st, expanded.w, 0);
      for (var round = 1; round < Nr; round++) {
        subBytes(st, sbox); shiftRows(st, false); mixColumns(st, false);
        addRoundKey(st, expanded.w, round);
      }
      subBytes(st, sbox); shiftRows(st, false);
      addRoundKey(st, expanded.w, Nr);
    } else {
      addRoundKey(st, expanded.w, Nr);
      for (var round = Nr - 1; round >= 1; round--) {
        subBytes(st, invSbox); shiftRows(st, true);
        addRoundKey(st, expanded.w, round);
        mixColumns(st, true);
      }
      subBytes(st, invSbox); shiftRows(st, true);
      addRoundKey(st, expanded.w, 0);
    }
    for (var j = 0; j < 16; j++) out[outOff + j] = st[j];
  }
  function unpad(data) {
    if (!data.length) return data;
    var n = data[data.length - 1];
    if (n < 1 || n > 16 || n > data.length) return data;
    for (var i = data.length - n; i < data.length; i++) {
      if (data[i] !== n) return data;
    }
    return data.slice(0, data.length - n);
  }
  function pad(data) {
    var n = 16 - (data.length % 16);
    var out = new Uint8Array(data.length + n);
    out.set(data);
    for (var i = data.length; i < out.length; i++) out[i] = n;
    return out;
  }
  function ecb(data, key, decrypt) {
    var expanded = expandKey(key);
    var input = decrypt ? data : pad(data);
    var out = new Uint8Array(input.length);
    for (var off = 0; off + 16 <= input.length; off += 16) {
      cryptBlock(input, off, out, off, expanded, decrypt);
    }
    return decrypt ? unpad(out) : out;
  }
  function cbc(data, key, iv, decrypt) {
    var expanded = expandKey(key);
    var input = decrypt ? data : pad(data);
    var out = new Uint8Array(input.length);
    var prev = new Uint8Array(iv);
    for (var off = 0; off + 16 <= input.length; off += 16) {
      if (!decrypt) {
        var block = new Uint8Array(16);
        for (var i = 0; i < 16; i++) block[i] = input[off + i] ^ prev[i];
        cryptBlock(block, 0, out, off, expanded, false);
        prev = out.slice(off, off + 16);
      } else {
        cryptBlock(input, off, out, off, expanded, true);
        for (var j = 0; j < 16; j++) out[off + j] ^= prev[j];
        prev = input.slice(off, off + 16);
      }
    }
    return decrypt ? unpad(out) : out;
  }
  return {ecb: ecb, cbc: cbc};
})();
Convert.decryptAesEcb = function (value, key) {
  return __anikumoAes.ecb(__anikumoBytes(value), __anikumoBytes(key), true).buffer;
};
Convert.encryptAesEcb = function (value, key) {
  return __anikumoAes.ecb(__anikumoBytes(value), __anikumoBytes(key), false).buffer;
};
Convert.decryptAesCbc = function (value, key, iv) {
  return __anikumoAes.cbc(
      __anikumoBytes(value), __anikumoBytes(key), __anikumoBytes(iv), true).buffer;
};
Convert.encryptAesCbc = function (value, key, iv) {
  return __anikumoAes.cbc(
      __anikumoBytes(value), __anikumoBytes(key), __anikumoBytes(iv), false).buffer;
};

function __anikumoUnsupportedConvert() {
  throw new Error('anikumo: 该源需要 RSA 或 CFB/OFB 解密，暂不支持');
}
// Batch 76: Convert.encodeGbk / decodeGbk are real now —
// they live in gbk_table.dart's veneraGbkScript, evaluated
// right after this overrides script.
Convert.decryptAesCfb = __anikumoUnsupportedConvert;
Convert.decryptAesOfb = __anikumoUnsupportedConvert;
Convert.decryptRsa = __anikumoUnsupportedConvert;

Network.fetchBytes = async function (method, url, headers, data) {
  var res = await sendMessage({
    method: 'http', http_method: method, bytes: true,
    url: url, headers: headers, data: data,
  });
  if (res && res.error) throw res.error;
  // Batch 41: the bridge returns the binary body base64-
  // encoded in body_b64 (the message channel is a JSON
  // string). Decode to a real ArrayBuffer — sources like
  // hitomi DataView() over it and string bodies throw
  // "ArrayBuffer object expected". __anikumoB64Decode builds
  // an exact-length Uint8Array, so .buffer is byte-exact.
  if (res && typeof res.body_b64 === 'string') {
    return {
      status: res.status,
      headers: res.headers || {},
      body: __anikumoB64Decode(res.body_b64).buffer,
    };
  }
  return res;
};

globalThis.fetch = async function (url, options) {
  options = options || {};
  var method = options.method || 'GET';
  var headers = options.headers || {};
  var data = options.body !== undefined ? options.body : null;
  var res = await Network.sendRequest(method, String(url), headers, data);
  var bodyText = typeof res.body === 'string' ? res.body : '';
  return {
    ok: res.status >= 200 && res.status < 300,
    status: res.status,
    statusText: '',
    headers: res.headers || {},
    text: async function () { return bodyText; },
    json: async function () { return JSON.parse(bodyText); },
    arrayBuffer: async function () {
      return __anikumoUtf8Encode(bodyText).buffer;
    },
  };
};
''';


/// Result normalization + the typed call dispatcher the Dart
/// side drives. Defined after the source class is instantiated.
const String veneraDispatcherScript = r'''
function __anikumoNormalize(v) {
  if (v instanceof Map) {
    var o = {};
    v.forEach(function (val, k) { o[String(k)] = __anikumoNormalize(val); });
    return o;
  }
  if (v instanceof Set) {
    return Array.from(v).map(__anikumoNormalize);
  }
  if (Array.isArray(v)) return v.map(__anikumoNormalize);
  if (v && typeof v === 'object') {
    var o2 = {};
    Object.keys(v).forEach(function (k) {
      o2[k] = __anikumoNormalize(v[k]);
    });
    return o2;
  }
  return v;
}

function __anikumoDefaultOptions(holder) {
  var list = (holder && holder.optionList) || [];
  return list.map(function (entry) {
    var opts = (entry && entry.options) || [];
    var d = entry && entry.default;
    if (Array.isArray(d)) return JSON.stringify(d.map(String));
    if (d !== undefined && d !== null && d !== '') {
      return String(d).split('-')[0];
    }
    if (!opts.length) return '';
    return String(opts[0]).split('-')[0];
  });
}

// Batch 37: token-paged loads. Some sources (ehentai,
// lanraragi) implement ONLY loadNext — the next page is
// reached through an opaque token from the previous result,
// not a page number. Chains are walked sequentially from
// page 1 and cached per (source, kind, discriminator), so
// our page-numbered calls can serve any page by replaying
// the chain. Bounded to the last 10 chains.
globalThis.__anikumoTokenChains = {};
globalThis.__anikumoChainOrder = [];
async function __anikumoPaged(chainKey, page, fetch) {
  var chains = globalThis.__anikumoTokenChains;
  var c = chains[chainKey];
  if (!c) {
    c = {tokens: [null], pages: {}};
    chains[chainKey] = c;
    globalThis.__anikumoChainOrder.push(chainKey);
    while (globalThis.__anikumoChainOrder.length > 10) {
      var old = globalThis.__anikumoChainOrder.shift();
      delete chains[old];
    }
  }
  while (!(page in c.pages)) {
    var idx = Object.keys(c.pages).length + 1;
    if (idx > page) break;
    var token = c.tokens[idx - 1];
    if (token === undefined) break;
    var r = await fetch(token);
    c.pages[idx] = r;
    c.tokens[idx] = (r && typeof r === 'object' && 'next' in r)
        ? r.next : undefined;
    if (c.tokens[idx] === undefined && idx < page) break;
  }
  return (page in c.pages) ? c.pages[page] : null;
}

globalThis.__anikumoSources = {};
globalThis.__anikumoRegisterInstance = function (sourceKey, instance) {
  globalThis.__anikumoSources[sourceKey] = instance;
  try {
    var schema =
        (instance && (instance.settings || instance.setting)) || {};
    var kv = __anikumoKvFor(sourceKey);
    Object.keys(schema).forEach(function (k) {
      var d = schema[k] && schema[k].default;
      // Batch 37: a select setting with no explicit default
      // reads as its first option in Venera (the settings UI
      // preselects it). jm's apiDomain is exactly that shape:
      // unseeded, loadSetting returned null and its baseUrl
      // getter computed apiDomains[NaN] -> undefined.
      if (d === undefined && schema[k] &&
          schema[k].options && schema[k].options.length) {
        var first = schema[k].options[0];
        d = (first && typeof first === 'object' && 'value' in first)
            ? first.value
            : first;
      }
      if (d !== undefined && !(k in kv.settings)) {
        kv.settings[k] = d;
      }
    });
  } catch (e) {}
  if (instance && typeof instance.init === 'function') {
    try {
      var p = instance.init();
      if (p && typeof p.catch === 'function') {
        // Batch 37: keep the init promise — the host awaits
        // it (bounded) before answering register. jm's init
        // fetches its API domain list; calls that raced ahead
        // of it read JM.apiDomains while still undefined.
        globalThis.__anikumoInitPromises =
            globalThis.__anikumoInitPromises || {};
        globalThis.__anikumoInitPromises[sourceKey] =
            Promise.resolve(p).catch(function (e) {
              globalThis.__anikumoInitWarnings =
                  globalThis.__anikumoInitWarnings || {};
              globalThis.__anikumoInitWarnings[sourceKey] =
                  String(e && e.stack || e);
            });
      }
    } catch (e) {
      // init() is best-effort in Venera too: a source whose
      // init probe fails (e.g. its first mirror domain 403s
      // from this network) can still serve every load call.
      globalThis.__anikumoInitWarnings =
          globalThis.__anikumoInitWarnings || {};
      globalThis.__anikumoInitWarnings[sourceKey] =
          String(e && e.stack || e);
    }
  }
};
// Batch 102: onResponse byte transforms. A config whose
// onResponse is a function cannot cross the bridge (functions
// are not data), so the function stays here in a registry
// keyed by source + kind + the ORIGINAL url the hook was
// called with; the config that crosses carries only
// `transform: true`, and the host sends the downloaded bytes
// back through the 'transformImage' call kind. The registry
// is capped (oldest registrations drop out) — a missing entry
// is re-registered lazily by re-running the hook, which also
// covers a host restart wiping this runtime.
globalThis.__anikumoTx = globalThis.__anikumoTx || {};
function __anikumoTxKey(sourceKey, mode, url) {
  return sourceKey + '|' + mode + '|' + url;
}
function __anikumoTxRegister(sourceKey, mode, url, fn) {
  var key = __anikumoTxKey(sourceKey, mode, url);
  var reg = globalThis.__anikumoTx;
  if (!(key in reg)) {
    var keys = Object.keys(reg);
    if (keys.length >= 512) delete reg[keys[0]];
  }
  reg[key] = fn;
}
// Normalizes one hook config for the trip to the host:
// function fields cannot cross the isolate boundary, so
// they are registered here under (mode, original url) and
// the copy is flagged instead.
//   onResponse   -> registered ('image'/'thumb'), `transform`
//   onLoadFailed -> registered ('fallback'), `fallback`
//                   (page images only — the reference runtime
//                   ignores it for thumbnails)
//   modifyImage  -> a code STRING in the reference runtime's
//                   contract; strings cross as-is under the
//                   `modify` key (page images only).
function __anikumoNormalizeCfg(sourceKey, mode, url, cfg) {
  var copy = {};
  for (var k in cfg) copy[k] = cfg[k];
  if (typeof cfg.onResponse === 'function') {
    __anikumoTxRegister(sourceKey, mode, url, cfg.onResponse);
    copy.transform = true;
  }
  if (mode === 'image') {
    if (typeof cfg.onLoadFailed === 'function') {
      __anikumoTxRegister(sourceKey, 'fallback', url, cfg.onLoadFailed);
      copy.fallback = true;
    }
    if (typeof cfg.modifyImage === 'string' && cfg.modifyImage) {
      copy.modify = cfg.modifyImage;
    }
  }
  delete copy.onResponse;
  delete copy.onLoadFailed;
  delete copy.modifyImage;
  return copy;
}
globalThis.__anikumoCall = async function (sourceKey, kind, args) {
  var src = globalThis.__anikumoSources[sourceKey];
  if (!src) throw new Error('source not initialized: ' + sourceKey);
  var r = null;
  if (kind === 'search') {
    if (typeof src.search.load === 'function') {
      r = await src.search.load(
          args.keyword, __anikumoDefaultOptions(src.search), args.page);
    } else if (typeof src.search.loadNext === 'function') {
      var sOpts = __anikumoDefaultOptions(src.search);
      r = await __anikumoPaged(
          'search:' + sourceKey + ':' + args.keyword, args.page,
          function (tok) {
            return src.search.loadNext(args.keyword, sOpts, tok);
          });
    }
  } else if (kind === 'explore') {
    if (!src.explore) return null;
    var pages = Array.isArray(src.explore) ? src.explore : [src.explore];
    var entry = pages[0];
    if (!entry) return null;
    if (typeof entry.load === 'function') {
      if (entry.optionList && entry.optionList.length) {
        r = await entry.load(
            __anikumoDefaultOptions(entry)[0], args.page);
      } else {
        r = await entry.load(args.page);
      }
    } else if (typeof entry.loadNext === 'function') {
      r = await __anikumoPaged(
          'explore:' + sourceKey, args.page,
          function (tok) { return entry.loadNext(tok); });
    } else {
      return null;
    }
  } else if (kind === 'categories') {
    r = (src.category && src.category.categories) || null;
  } else if (kind === 'categoryComics') {
    r = await src.categoryComics.load(
        args.category, args.param || '',
        __anikumoDefaultOptions(src.categoryComics), args.page);
  } else if (kind === 'loadInfo') {
    r = await src.comic.loadInfo(args.id);
  } else if (kind === 'loadEp') {
    r = await src.comic.loadEp(args.id, args.ep);
  } else if (kind === 'imageConfigs') {
    // Batch 88: comic.onImageLoad was never invoked — sources
    // that sign page URLs, exchange an image key, or attach
    // per-image headers (18 of the 33 index sources define it)
    // served pages this app could not load. Resolve every URL
    // in ONE call, in parallel on the JS side; a per-image
    // failure or a missing hook yields null for that slot and
    // the host keeps the original page.
    var ihook = src.comic && src.comic.onImageLoad;
    if (typeof ihook !== 'function') return null;
    var iurls = Array.isArray(args.urls) ? args.urls : [];
    r = await Promise.all(iurls.map(async function (u) {
      try {
        var cfg = await ihook.call(src.comic, u, args.id, args.ep);
        if (!cfg || typeof cfg !== 'object') return null;
        // Batch 102/103: function-bearing configs are
        // normalized — onResponse (byte transform),
        // onLoadFailed (fallback config) and modifyImage
        // (image-edit code) become registry entries + flags.
        return __anikumoNormalizeCfg(sourceKey, 'image', u, cfg);
      } catch (e) {
        return null;
      }
    }));
  } else if (kind === 'thumbnailConfigs') {
    // Batch 88: comic.onThumbnailLoad, same story for covers
    // (15 of 33 sources): host/CDN rewrites and Referer headers
    // that list and detail covers need to load at all.
    var thook = src.comic && src.comic.onThumbnailLoad;
    if (typeof thook !== 'function') return null;
    var turls = Array.isArray(args.urls) ? args.urls : [];
    r = await Promise.all(turls.map(async function (u) {
      try {
        var cfg = await thook.call(src.comic, u);
        if (!cfg || typeof cfg !== 'object') return null;
        // Batch 102/103: same normalization as page images,
        // under the 'thumb' mode (fallback/modify are
        // page-only in the reference runtime).
        return __anikumoNormalizeCfg(sourceKey, 'thumb', u, cfg);
      } catch (e) {
        return null;
      }
    }));
  } else if (kind === 'transformImage') {
    // Batch 102: run a registered onResponse over downloaded
    // bytes. A registry miss (host restart, cap eviction)
    // re-runs the hook for this one url to re-register.
    var tmode = args.mode === 'thumb' ? 'thumb' : 'image';
    var tkey = __anikumoTxKey(sourceKey, tmode, args.url);
    var tfn = globalThis.__anikumoTx[tkey];
    if (typeof tfn !== 'function') {
      var thook2 = tmode === 'thumb'
          ? (src.comic && src.comic.onThumbnailLoad)
          : (src.comic && src.comic.onImageLoad);
      if (typeof thook2 === 'function') {
        var tcfg = tmode === 'thumb'
            ? await thook2.call(src.comic, args.url)
            : await thook2.call(
                  src.comic, args.url, args.id || '', args.ep || '');
        if (tcfg && typeof tcfg === 'object') {
          // Batch 103: normalize on the re-run too, so the
          // sibling registrations (fallback / modify) are
          // refreshed alongside the transform.
          __anikumoNormalizeCfg(sourceKey, tmode, args.url, tcfg);
          tfn = globalThis.__anikumoTx[tkey];
        }
      }
    }
    if (typeof tfn !== 'function') {
      r = { ok: false };
    } else {
      var traw = __anikumoB64Decode(args.dataB64 || '');
      var tresp = { data: traw, status: 200, headers: {} };
      var tout = await tfn(tresp);
      var tbytes = null;
      if (tout && tout.data !== undefined && tout.data !== null) {
        tbytes = tout.data;
      } else if (tout instanceof Uint8Array ||
          tout instanceof ArrayBuffer) {
        tbytes = tout;
      } else if (tout === undefined || tout === null) {
        // In-place mutation style: the source edited
        // resp.data and returned nothing.
        tbytes = tresp.data;
      }
      if (tbytes instanceof ArrayBuffer) {
        tbytes = new Uint8Array(tbytes);
      }
      if (tbytes && typeof tbytes.length === 'number') {
        r = { ok: true, dataB64: __anikumoB64Encode(tbytes) };
      } else {
        r = { ok: false };
      }
    }
  } else if (kind === 'loadFailed') {
    // Batch 103: a page download failed and the config for
    // the original url carried onLoadFailed — ask it for a
    // replacement config (mirror host, alternate CDN). The
    // replacement is normalized like any hook config, so a
    // fallback may itself carry transform/modify/fallback.
    var fkey = __anikumoTxKey(sourceKey, 'fallback', args.url);
    var ffn = globalThis.__anikumoTx[fkey];
    if (typeof ffn !== 'function') {
      var fhook = src.comic && src.comic.onImageLoad;
      if (typeof fhook === 'function') {
        var fcfg0 = await fhook.call(
            src.comic, args.url, args.id || '', args.ep || '');
        if (fcfg0 && typeof fcfg0 === 'object') {
          __anikumoNormalizeCfg(sourceKey, 'image', args.url, fcfg0);
          ffn = globalThis.__anikumoTx[fkey];
        }
      }
    }
    if (typeof ffn !== 'function') {
      r = null;
    } else {
      var fcfg = await ffn.call(src.comic);
      if (!fcfg || typeof fcfg !== 'object') {
        r = null;
      } else {
        r = __anikumoNormalizeCfg(
            sourceKey, 'image', fcfg.url || args.url, fcfg);
      }
    }
  } else if (kind === 'modifyImage') {
    // Batch 103: run a config's modifyImage code string over
    // downloaded bytes. The snippet defines a function named
    // `modifyImage` (the reference runtime's contract); it
    // receives an Image backed by the host's synchronous
    // image registry and returns the edited Image. Output is
    // re-encoded in the input's format family (jpeg stays
    // jpeg) so reassembled pages don't balloon as PNGs.
    var mcreated = __anikumoImageCall({
      method: 'image', 'function': 'createFromBytes',
      dataB64: args.dataB64 || '',
    });
    if (!mcreated.ok) {
      r = { ok: false };
    } else {
      var mfn = null;
      try {
        mfn = (0, eval)(String(args.code || '') + '\n;modifyImage;');
      } catch (e) {
        mfn = null;
      }
      if (typeof mfn !== 'function') {
        try {
          var malt = (0, eval)(String(args.code || ''));
          if (typeof malt === 'function') mfn = malt;
        } catch (e) {}
      }
      if (typeof mfn !== 'function') {
        r = { ok: false };
      } else {
        try {
          var mimg = new Image(mcreated.v);
          var mout = mfn(mimg);
          if (mout && typeof mout.then === 'function') {
            mout = await mout;
          }
          var mkey = (mout && typeof mout.key === 'number')
              ? mout.key
              : mcreated.v;
          var menc = __anikumoImageCall({
            method: 'image', 'function': 'encode',
            key: mkey, fmt: mcreated.fmt || '',
          });
          r = menc.ok
              ? { ok: true, dataB64: menc.v }
              : { ok: false };
        } catch (e) {
          r = { ok: false };
        }
      }
      __anikumoImageCall({ method: 'image', 'function': 'releaseAll' });
    }
  } else if (kind === 'loadThumbnails') {
    // Batch 103: comic.loadThumbnails(id) — preview page
    // urls for the detail screen. Null when the source has
    // no such hook (distinct from an empty list).
    if (src.comic && typeof src.comic.loadThumbnails === 'function') {
      var tlist = await src.comic.loadThumbnails(args.id);
      r = Array.isArray(tlist)
          ? tlist.filter(function (u) { return typeof u === 'string'; })
          : [];
    } else {
      r = null;
    }
  } else if (kind === 'account') {
    // Batch 74: account surface (picacg/jm/kavita shape):
    // {login(account, pwd), logout(), registerWebsite}.
    // hasToken mirrors the library's isLogged getter, which
    // the shim answers from kv.data['token'].
    var acc = src.account || null;
    r = {
      hasLogin: !!(acc && typeof acc.login === 'function'),
      hasLogout: !!(acc && typeof acc.logout === 'function'),
      registerWebsite:
          (acc && typeof acc.registerWebsite === 'string' &&
           acc.registerWebsite)
              ? acc.registerWebsite
              : null,
      hasToken: !!__anikumoKvFor(sourceKey).data['token'],
    };
  } else if (kind === 'login') {
    if (!src.account || typeof src.account.login !== 'function') {
      throw new Error('该源不支持账号登录');
    }
    await src.account.login(
        String(args.username || ''), String(args.password || ''));
    r = true;
  } else if (kind === 'logout') {
    if (src.account && typeof src.account.logout === 'function') {
      await src.account.logout();
    }
    var kvOut = __anikumoKvFor(sourceKey);
    if ('token' in kvOut.data) {
      delete kvOut.data['token'];
      __anikumoPersist(sourceKey);
    }
    r = true;
  }
  return JSON.stringify(__anikumoNormalize(r === undefined ? null : r));
};
''';

/// Creates the source instance; [className] is extracted from
/// the source file on the Dart side.
/// Wraps a source file for evaluation in the shared
/// runtime: the file's class declaration stays scoped inside
/// the IIFE (Venera's parser does the same), and the created
/// instance registers itself under [sourceKey].
String veneraWrapSourceScript(
        String className, String sourceKey, String code) =>
    '''
(() => {
$code
try {
  __anikumoRegisterInstance('$sourceKey', new $className());
} catch (e) {
  globalThis.__anikumoInitErrors = globalThis.__anikumoInitErrors || {};
  globalThis.__anikumoInitErrors['$sourceKey'] =
      String(e && e.stack || e);
}
})()
''';
