/// The JS prelude for the Legado bridge: a mini-DOM over a
/// JSON-serialized document, Java-flavored String helpers,
/// a `java` object shim (getElements / ajax / post /
/// md5Encode / base64 / put-get / log ...), and HashMap.
///
/// This string is loaded verbatim into QuickJS before any
/// source jsLib or rule JS runs. Network calls from JS are
/// synchronous in Legado (Rhino); here they throw a marked
/// error carrying the request, the Dart host performs it,
/// and re-runs the script with the response in `__netCache`
/// (suspend-and-replay). Scripts are pure functions of the
/// page + responses, so replay is deterministic.
const String legadoJsPrelude = r'''
// ---------- Java-flavored String helpers ----------
if (!String.prototype.contains) {
  String.prototype.contains = function (s) { return this.indexOf(s) !== -1; };
}
if (!String.prototype.equals) {
  String.prototype.equals = function (s) { return String(this) === String(s); };
}
if (!String.prototype.equalsIgnoreCase) {
  String.prototype.equalsIgnoreCase = function (s) {
    return String(this).toLowerCase() === String(s).toLowerCase();
  };
}

// ---------- Base64 (UTF-8 aware) ----------
var __b64chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
function __b64encodeBytes(bytes) {
  var out = '';
  for (var i = 0; i < bytes.length; i += 3) {
    var b0 = bytes[i], b1 = i + 1 < bytes.length ? bytes[i + 1] : 0,
        b2 = i + 2 < bytes.length ? bytes[i + 2] : 0;
    out += __b64chars[b0 >> 2];
    out += __b64chars[((b0 & 3) << 4) | (b1 >> 4)];
    out += i + 1 < bytes.length ? __b64chars[((b1 & 15) << 2) | (b2 >> 6)] : '=';
    out += i + 2 < bytes.length ? __b64chars[b2 & 63] : '=';
  }
  return out;
}
function __utf8Bytes(str) {
  var bytes = [];
  for (var i = 0; i < str.length; i++) {
    var c = str.charCodeAt(i);
    if (c < 0x80) bytes.push(c);
    else if (c < 0x800) { bytes.push(0xc0 | (c >> 6), 0x80 | (c & 63)); }
    else if (c >= 0xd800 && c <= 0xdbff && i + 1 < str.length) {
      var cp = 0x10000 + ((c - 0xd800) << 10) + (str.charCodeAt(++i) - 0xdc00);
      bytes.push(0xf0 | (cp >> 18), 0x80 | ((cp >> 12) & 63),
                 0x80 | ((cp >> 6) & 63), 0x80 | (cp & 63));
    } else {
      bytes.push(0xe0 | (c >> 12), 0x80 | ((c >> 6) & 63), 0x80 | (c & 63));
    }
  }
  return bytes;
}
function __b64decodeToBytes(b64) {
  var clean = String(b64).replace(/[^A-Za-z0-9+/=]/g, '');
  var bytes = [];
  for (var i = 0; i < clean.length; i += 4) {
    var n0 = __b64chars.indexOf(clean[i]), n1 = __b64chars.indexOf(clean[i + 1]);
    var n2 = clean[i + 2] === '=' ? -1 : __b64chars.indexOf(clean[i + 2]);
    var n3 = clean[i + 3] === '=' ? -1 : __b64chars.indexOf(clean[i + 3]);
    bytes.push((n0 << 2) | (n1 >> 4));
    if (n2 >= 0) bytes.push(((n1 & 15) << 4) | (n2 >> 2));
    if (n3 >= 0) bytes.push(((n2 & 3) << 6) | n3);
  }
  return bytes;
}
function __bytesToUtf8(bytes) {
  var out = '', i = 0;
  while (i < bytes.length) {
    var b = bytes[i];
    if (b < 0x80) { out += String.fromCharCode(b); i += 1; }
    else if (b < 0xe0) {
      out += String.fromCharCode(((b & 31) << 6) | (bytes[i + 1] & 63)); i += 2;
    } else if (b < 0xf0) {
      out += String.fromCharCode(((b & 15) << 12) | ((bytes[i + 1] & 63) << 6) |
                                  (bytes[i + 2] & 63)); i += 3;
    } else {
      var cp = ((b & 7) << 18) | ((bytes[i + 1] & 63) << 12) |
               ((bytes[i + 2] & 63) << 6) | (bytes[i + 3] & 63);
      cp -= 0x10000;
      out += String.fromCharCode(0xd800 + (cp >> 10), 0xdc00 + (cp & 1023));
      i += 4;
    }
  }
  return out;
}

// ---------- MD5 ----------
function __md5(str) {
  function rl(n, c) { return (n << c) | (n >>> (32 - c)); }
  function add(a, b) {
    var l = (a & 0xffff) + (b & 0xffff);
    var m = (a >> 16) + (b >> 16) + (l >> 16);
    return (m << 16) | (l & 0xffff);
  }
  function cmn(q, a, b, x, s, t) { return add(rl(add(add(a, q), add(x, t)), s), b); }
  function ff(a, b, c, d, x, s, t) { return cmn((b & c) | (~b & d), a, b, x, s, t); }
  function gg(a, b, c, d, x, s, t) { return cmn((b & d) | (c & ~d), a, b, x, s, t); }
  function hh(a, b, c, d, x, s, t) { return cmn(b ^ c ^ d, a, b, x, s, t); }
  function ii(a, b, c, d, x, s, t) { return cmn(c ^ (b | ~d), a, b, x, s, t); }
  var bytes = __utf8Bytes(str);
  var origLen = bytes.length;
  bytes.push(0x80);
  while (bytes.length % 64 !== 56) bytes.push(0);
  var bitLen = origLen * 8;
  for (var i = 0; i < 4; i++) bytes.push((bitLen >> (8 * i)) & 0xff);
  for (var i = 0; i < 4; i++) bytes.push(0);
  var a = 0x67452301, b = 0xefcdab89, c = 0x98badcfe, d = 0x10325476;
  for (var blk = 0; blk < bytes.length; blk += 64) {
    var x = [];
    for (var j = 0; j < 16; j++) {
      x[j] = bytes[blk + j * 4] | (bytes[blk + j * 4 + 1] << 8) |
             (bytes[blk + j * 4 + 2] << 16) | (bytes[blk + j * 4 + 3] << 24);
    }
    var aa = a, bb = b, cc = c, dd = d;
    a = ff(a, b, c, d, x[0], 7, 0xd76aa478); d = ff(d, a, b, c, x[1], 12, 0xe8c7b756);
    c = ff(c, d, a, b, x[2], 17, 0x242070db); b = ff(b, c, d, a, x[3], 22, 0xc1bdceee);
    a = ff(a, b, c, d, x[4], 7, 0xf57c0faf); d = ff(d, a, b, c, x[5], 12, 0x4787c62a);
    c = ff(c, d, a, b, x[6], 17, 0xa8304613); b = ff(b, c, d, a, x[7], 22, 0xfd469501);
    a = ff(a, b, c, d, x[8], 7, 0x698098d8); d = ff(d, a, b, c, x[9], 12, 0x8b44f7af);
    c = ff(c, d, a, b, x[10], 17, 0xffff5bb1); b = ff(b, c, d, a, x[11], 22, 0x895cd7be);
    a = ff(a, b, c, d, x[12], 7, 0x6b901122); d = ff(d, a, b, c, x[13], 12, 0xfd987193);
    c = ff(c, d, a, b, x[14], 17, 0xa679438e); b = ff(b, c, d, a, x[15], 22, 0x49b40821);
    a = gg(a, b, c, d, x[1], 5, 0xf61e2562); d = gg(d, a, b, c, x[6], 9, 0xc040b340);
    c = gg(c, d, a, b, x[11], 14, 0x265e5a51); b = gg(b, c, d, a, x[0], 20, 0xe9b6c7aa);
    a = gg(a, b, c, d, x[5], 5, 0xd62f105d); d = gg(d, a, b, c, x[10], 9, 0x02441453);
    c = gg(c, d, a, b, x[15], 14, 0xd8a1e681); b = gg(b, c, d, a, x[4], 20, 0xe7d3fbc8);
    a = gg(a, b, c, d, x[9], 5, 0x21e1cde6); d = gg(d, a, b, c, x[14], 9, 0xc33707d6);
    c = gg(c, d, a, b, x[3], 14, 0xf4d50d87); b = gg(b, c, d, a, x[8], 20, 0x455a14ed);
    a = gg(a, b, c, d, x[13], 5, 0xa9e3e905); d = gg(d, a, b, c, x[2], 9, 0xfcefa3f8);
    c = gg(c, d, a, b, x[7], 14, 0x676f02d9); b = gg(b, c, d, a, x[12], 20, 0x8d2a4c8a);
    a = hh(a, b, c, d, x[5], 4, 0xfffa3942); d = hh(d, a, b, c, x[8], 11, 0x8771f681);
    c = hh(c, d, a, b, x[11], 16, 0x6d9d6122); b = hh(b, c, d, a, x[14], 23, 0xfde5380c);
    a = hh(a, b, c, d, x[1], 4, 0xa4beea44); d = hh(d, a, b, c, x[4], 11, 0x4bdecfa9);
    c = hh(c, d, a, b, x[7], 16, 0xf6bb4b60); b = hh(b, c, d, a, x[10], 23, 0xbebfbc70);
    a = hh(a, b, c, d, x[13], 4, 0x289b7ec6); d = hh(d, a, b, c, x[0], 11, 0xeaa127fa);
    c = hh(c, d, a, b, x[3], 16, 0xd4ef3085); b = hh(b, c, d, a, x[6], 23, 0x04881d05);
    a = hh(a, b, c, d, x[9], 4, 0xd9d4d039); d = hh(d, a, b, c, x[12], 11, 0xe6db99e5);
    c = hh(c, d, a, b, x[15], 16, 0x1fa27cf8); b = hh(b, c, d, a, x[2], 23, 0xc4ac5665);
    a = ii(a, b, c, d, x[0], 6, 0xf4292244); d = ii(d, a, b, c, x[7], 10, 0x432aff97);
    c = ii(c, d, a, b, x[14], 15, 0xab9423a7); b = ii(b, c, d, a, x[5], 21, 0xfc93a039);
    a = ii(a, b, c, d, x[12], 6, 0x655b59c3); d = ii(d, a, b, c, x[3], 10, 0x8f0ccc92);
    c = ii(c, d, a, b, x[10], 15, 0xffeff47d); b = ii(b, c, d, a, x[1], 21, 0x85845dd1);
    a = ii(a, b, c, d, x[8], 6, 0x6fa87e4f); d = ii(d, a, b, c, x[15], 10, 0xfe2ce6e0);
    c = ii(c, d, a, b, x[6], 15, 0xa3014314); b = ii(b, c, d, a, x[4], 21, 0x4e0811a1);
    a = ii(a, b, c, d, x[11], 6, 0xf7537e82); d = ii(d, a, b, c, x[13], 10, 0xbd3af235);
    c = ii(c, d, a, b, x[2], 15, 0x2ad7d2bb); b = ii(b, c, d, a, x[9], 21, 0xeb86d391);
    a = add(a, aa); b = add(b, bb); c = add(c, cc); d = add(d, dd);
  }
  function hex(n) {
    var s = '';
    for (var i = 0; i < 4; i++) {
      var byte = (n >> (8 * i)) & 0xff;
      s += ('0' + byte.toString(16)).slice(-2);
    }
    return s;
  }
  return hex(a) + hex(b) + hex(c) + hex(d);
}

// ---------- HashMap ----------
function __HashMap() { this._m = new Map(); }
__HashMap.prototype.put = function (k, v) { this._m.set(String(k), v); return v; };
__HashMap.prototype.get = function (k) {
  var v = this._m.get(String(k)); return v === undefined ? null : v;
};
__HashMap.prototype.containsKey = function (k) { return this._m.has(String(k)); };
__HashMap.prototype.remove = function (k) { this._m.delete(String(k)); };
__HashMap.prototype.size = function () { return this._m.size; };
__HashMap.prototype._entries = function () {
  var arr = []; this._m.forEach(function (v, k) { arr.push([k, v]); }); return arr;
};
var Packages = { java: { util: { HashMap: __HashMap } } };

// ---------- Mini DOM over the JSON document ----------
function __isEl(n) { return n && typeof n === 'object' && typeof n.t === 'string'; }
function __textOf(n, own) {
  if (!__isEl(n)) return '';
  var parts = [];
  for (var i = 0; i < n.c.length; i++) {
    var ch = n.c[i];
    if (typeof ch.x === 'string') { if (ch.x.trim()) parts.push(ch.x.trim()); }
    else if (!own) { var t = __textOf(ch, false); if (t) parts.push(t); }
  }
  return parts.join(' ').replace(/\s+/g, ' ').trim();
}
function __rawText(n) {
  if (!__isEl(n)) return typeof n.x === 'string' ? n.x : '';
  var s = '';
  for (var i = 0; i < n.c.length; i++) s += __rawText(n.c[i]);
  return s;
}
function __htmlOf(n) {
  var s = '';
  for (var i = 0; i < n.c.length; i++) {
    var ch = n.c[i];
    if (typeof ch.x === 'string') { s += ch.x; continue; }
    s += '<' + ch.t;
    for (var k in ch.a) s += ' ' + k + '="' + String(ch.a[k]).replace(/"/g, '&quot;') + '"';
    s += '>' + __htmlOf(ch) + '</' + ch.t + '>';
  }
  return s;
}
function __matchCompound(n, compound) {
  if (!__isEl(n) || n.t === '#root') return false;
  var rest = compound;
  var tagM = rest.match(/^[a-zA-Z][a-zA-Z0-9-]*/);
  if (tagM) {
    if (n.t.toLowerCase() !== tagM[0].toLowerCase()) return false;
    rest = rest.substring(tagM[0].length);
  }
  while (rest.length > 0) {
    if (rest[0] === '.') {
      var m = rest.match(/^\.([a-zA-Z0-9_-]+)/);
      if (!m) return false;
      var cls = String(n.a['class'] || '').split(/\s+/);
      if (cls.indexOf(m[1]) === -1) return false;
      rest = rest.substring(m[0].length);
    } else if (rest[0] === '#') {
      var m2 = rest.match(/^#([a-zA-Z0-9_-]+)/);
      if (!m2) return false;
      if (String(n.a['id'] || '') !== m2[1]) return false;
      rest = rest.substring(m2[0].length);
    } else if (rest[0] === '[') {
      var end = rest.indexOf(']');
      if (end < 0) return false;
      var inner = rest.substring(1, end);
      var eq = inner.indexOf('=');
      if (eq < 0) {
        if (!(inner.trim() in n.a)) return false;
      } else {
        var name = inner.substring(0, eq).replace(/\*$/, '').trim();
        var op = inner.substring(0, eq).indexOf('*') >= 0 ? '*=' : '=';
        var val = inner.substring(eq + 1).trim().replace(/^['"]|['"]$/g, '');
        var actual = String(n.a[name] || '');
        if (op === '=' ? actual !== val : actual.indexOf(val) === -1) return false;
      }
      rest = rest.substring(end + 1);
    } else if (rest[0] === ':') {
      // Pseudo classes are outside the subset; skip the token.
      var m3 = rest.match(/^:[a-z-]+(\([^)]*\))?/);
      if (!m3) return false;
      rest = rest.substring(m3[0].length);
    } else {
      return false;
    }
  }
  return true;
}
function __parseSelector(selector) {
  // Returns groups: [[compound, combinator, compound, ...], ...]
  var groups = [];
  var parts = selector.split(',');
  for (var gi = 0; gi < parts.length; gi++) {
    var s = parts[gi].trim();
    if (!s) continue;
    var seq = [];
    var buf = '', comb = ' ';
    var depth = 0;
    for (var i = 0; i < s.length; i++) {
      var ch = s[i];
      if (ch === '[') depth++;
      if (ch === ']') depth--;
      if (depth === 0 && (ch === '>' || ch === ' ' || ch === '\t')) {
        if (buf.trim()) { seq.push({ c: buf.trim(), comb: comb }); buf = ''; }
        comb = ch === '>' ? '>' : ' ';
        continue;
      }
      buf += ch;
    }
    if (buf.trim()) seq.push({ c: buf.trim(), comb: comb });
    if (seq.length) groups.push(seq);
  }
  return groups;
}
function __selectAll(rootNode, selector) {
  var groups = __parseSelector(selector);
  var out = [];
  var seen = new Set();
  function descendants(n, acc) {
    for (var i = 0; i < n.c.length; i++) {
      var ch = n.c[i];
      if (__isEl(ch)) { acc.push(ch); descendants(ch, acc); }
    }
  }
  for (var g = 0; g < groups.length; g++) {
    var seq = groups[g];
    var current = [rootNode];
    for (var sIdx = 0; sIdx < seq.length; sIdx++) {
      var step = seq[sIdx];
      var next = [];
      for (var c = 0; c < current.length; c++) {
        var base = current[c];
        var candidates = [];
        if (step.comb === '>' && sIdx > 0) {
          for (var i = 0; i < base.c.length; i++) {
            if (__isEl(base.c[i])) candidates.push(base.c[i]);
          }
        } else {
          descendants(base, candidates);
        }
        for (var k = 0; k < candidates.length; k++) {
          if (__matchCompound(candidates[k], step.c)) next.push(candidates[k]);
        }
      }
      current = next;
    }
    for (var r = 0; r < current.length; r++) {
      if (!seen.has(current[r])) { seen.add(current[r]); out.push(current[r]); }
    }
  }
  return out;
}
function __El(node) { this._n = node; }
__El.prototype.attr = function (name) {
  var v = this._n.a[name]; return v === undefined ? '' : String(v);
};
__El.prototype.text = function () { return __textOf(this._n, false); };
__El.prototype.ownText = function () { return __textOf(this._n, true); };
__El.prototype.html = function () { return __htmlOf(this._n); };
__El.prototype.data = function () { return __rawText(this._n); };
__El.prototype.tagName = function () { return String(this._n.t).toLowerCase(); };
__El.prototype.select = function (selector) {
  var all = __selectAll(this._n, selector);
  return all.length ? new __El(all[0]) : null;
};
__El.prototype.selectAll = function (selector) {
  return __elements(__selectAll(this._n, selector));
};
__El.prototype.selectFirst = function (selector) {
  return this.select(selector);
};
__El.prototype.getElementsByTag = function (tag) {
  return this.selectAll(String(tag).toLowerCase());
};
__El.prototype.getElementsByClass = function (cls) {
  return this.selectAll('.' + cls);
};
__El.prototype.children = function () {
  var out = [];
  for (var i = 0; i < this._n.c.length; i++) {
    if (__isEl(this._n.c[i])) out.push(this._n.c[i]);
  }
  return __elements(out);
};
__El.prototype.child = function (i) {
  return this.children().get(i);
};
__El.prototype.hasAttr = function (name) {
  return this._n.a[name] !== undefined;
};
__El.prototype.val = function () { return this.attr('value'); };
__El.prototype.wholeText = function () { return this.data(); };
__El.prototype.parent = function () {
  var found = __findParent(__doc, this._n);
  return found ? new __El(found) : null;
};
__El.prototype.toJSON = function () { return { __elHtml: __htmlOf({ c: [this._n] }) }; };

function __findParent(node, target) {
  for (var i = 0; i < node.c.length; i++) {
    var ch = node.c[i];
    if (ch === target) return node;
    if (__isEl(ch)) {
      var r = __findParent(ch, target);
      if (r) return r;
    }
  }
  return null;
}

// Batch 165: the Jsoup Elements surface. Real Legado hands
// scripts an org.jsoup.select.Elements — an object with
// size()/get()/eachText() and friends. This bridge returns
// arrays of __El, so the common methods ride on the array;
// sources calling list.size() used to die with
// "not a function" (the Qidian search script family).
function __elements(items) {
  var arr = [];
  for (var i = 0; i < items.length; i++) {
    var it = items[i];
    arr.push(it && it._n !== undefined ? it : new __El(it));
  }
  arr.size = function () { return this.length; };
  arr.get = function (i) {
    var pos = i >= 0 ? i : this.length + i;
    return (pos >= 0 && pos < this.length) ? this[pos] : null;
  };
  arr.eachText = function () {
    var out = [];
    for (var i = 0; i < this.length; i++) out.push(this[i].text());
    return out;
  };
  arr.text = function () { return this.eachText().join(' '); };
  arr.html = function () {
    var out = '';
    for (var i = 0; i < this.length; i++) out += this[i].html();
    return out;
  };
  arr.attr = function (name) {
    return this.length ? this[0].attr(name) : '';
  };
  arr.first = function () { return this.length ? this[0] : null; };
  arr.last = function () {
    return this.length ? this[this.length - 1] : null;
  };
  arr.eq = function (i) {
    var el = this.get(i);
    return __elements(el ? [el] : []);
  };
  return arr;
}

function __cssSelectorOf(rule) {
  var r = String(rule || '');
  if (r.indexOf('@css:') === 0) r = r.substring(5);
  else if (r.indexOf('@css ') === 0) r = r.substring(5);
  r = r.trim();
  // Drop a trailing @attr (getElements selects elements).
  var idx = r.lastIndexOf('@');
  if (idx > 0) {
    var tail = r.substring(idx + 1).trim();
    if (tail && !/[\\s>[\\],:]/.test(tail)) r = r.substring(0, idx).trim();
  }
  return r;
}

// ---------- Legado shorthand chains (batch 31) ----------
// Mirrors the Dart side: '@'-joined steps of
// class.NAME[.IDX] / tag.NAME[.IDX] / id.NAME[.IDX] /
// children / plain CSS[.IDX], with an optional trailing
// @attr. Real sources use these inside java.getString /
// java.getElements field rules.
function __descendantsOf(node, acc) {
  for (var i = 0; i < node.c.length; i++) {
    var ch = node.c[i];
    if (__isEl(ch)) { acc.push(ch); __descendantsOf(ch, acc); }
  }
  return acc;
}
function __applyIdx(list, idxStr) {
  if (idxStr === null || idxStr === undefined) return list;
  var idx = parseInt(idxStr, 10);
  var pos = idx >= 0 ? idx : list.length + idx;
  return (pos < 0 || pos >= list.length) ? [] : [list[pos]];
}
// Batch 172: mirror of the Dart index spec — comma
// singles and 'start:end[:step]' ranges (either end
// omittable/negative, descending reverses); exclude
// removes the picked positions instead of selecting.
function __applyIdxSpec(list, spec, exclude) {
  var len = list.length;
  if (!len) return [];
  var picked = [];
  function addSingle(raw) {
    var pos = raw >= 0 ? raw : len + raw;
    if (pos >= 0 && pos < len && picked.indexOf(pos) < 0) picked.push(pos);
  }
  function addRange(a, b, c) {
    var start = a === '' ? 0 : (parseInt(a, 10) || 0);
    if (start < 0) start += len;
    var end = b === '' ? len - 1 : (parseInt(b, 10) || 0);
    if (b !== '' && end === 0 && b !== '0' && b !== '-0') end = len - 1;
    if (end < 0) end += len;
    start = Math.max(0, Math.min(len - 1, start));
    end = Math.max(0, Math.min(len - 1, end));
    var step = c === '' ? 0 : (parseInt(c, 10) || 0);
    if (step === 0) step = end >= start ? 1 : -1;
    if (step > 0) {
      for (var i = start; i <= end; i += step) {
        if (picked.indexOf(i) < 0) picked.push(i);
      }
    } else {
      for (var i2 = start; i2 >= end; i2 += step) {
        if (picked.indexOf(i2) < 0) picked.push(i2);
      }
    }
  }
  var tokens = String(spec).split(',');
  for (var t = 0; t < tokens.length; t++) {
    var tok = tokens[t].trim();
    if (!tok) continue;
    var parts = tok.split(':');
    if (parts.length === 1) {
      var n = parseInt(tok, 10);
      if (!isNaN(n)) addSingle(n);
    } else {
      addRange(parts[0].trim(), parts.length > 1 ? parts[1].trim() : '',
        parts.length > 2 ? parts[2].trim() : '');
    }
  }
  if (exclude) {
    return list.filter(function (_, i) { return picked.indexOf(i) < 0; });
  }
  return picked.map(function (i) { return list[i]; });
}
function __chainStepBase(node, head) {
  var m = /^(class|tag|id|text)\.([^.]+)$/.exec(head);
  if (m) {
    var all = __descendantsOf(node, []);
    return all.filter(function (el) {
      if (m[1] === 'class') {
        return (el.a['class'] || '').split(/\s+/).indexOf(m[2]) >= 0;
      }
      if (m[1] === 'id') return el.a['id'] === m[2];
      if (m[1] === 'text') {
        return __textOf(el, true).toLowerCase()
            .indexOf(m[2].toLowerCase()) >= 0;
      }
      return el.t === m[2];
    });
  }
  if (head === 'children' || head === '') {
    var out = [];
    for (var c = 0; c < node.c.length; c++) {
      if (__isEl(node.c[c])) out.push(node.c[c]);
    }
    return out;
  }
  return __selectAll(node, head);
}
function __chainStep(nodes, step) {
  // Batch 172: step = kind head + optional index spec
  // ('[...]' list / '!a:b' exclusion / dot suffix),
  // mirroring the Dart side. Index specs apply per
  // context node, as the reference applies them per
  // parent element.
  var head = String(step).trim();
  var bracketSpec = null, bracketExclude = false, bangSpec = null;
  var dotSpec = null;
  if (head.charAt(head.length - 1) === ']') {
    var open = head.indexOf('[');
    if (open >= 0) {
      var inner = head.substring(open + 1, head.length - 1).trim();
      head = head.substring(0, open).trim();
      if (inner.charAt(0) === '!') {
        bracketExclude = true;
        inner = inner.substring(1).trim();
      }
      bracketSpec = inner;
    }
  }
  if (bracketSpec === null) {
    var bang = head.indexOf('!');
    if (bang >= 0) {
      bangSpec = head.substring(bang + 1).trim();
      head = head.substring(0, bang).trim();
    }
  }
  var sm = /^(class|tag|id|text)\.([^.]+)(?:\.(.+))?$/.exec(head);
  if (sm) {
    head = sm[1] + '.' + sm[2];
    dotSpec = sm[3] === undefined ? null : sm[3];
  } else if (head.indexOf('children.') === 0) {
    dotSpec = head.substring('children.'.length);
    head = 'children';
  }
  var out = [];
  for (var n = 0; n < nodes.length; n++) {
    var base;
    if (sm || head === 'children' || head === '') {
      base = __chainStepBase(nodes[n], head);
    } else {
      var css = head, idx = null;
      var im = /^(.+)\.(-?\d+)$/.exec(head);
      if (im && head.indexOf(' ') < 0) { css = im[1]; idx = im[2]; }
      base = __applyIdx(__selectAll(nodes[n], css), idx);
    }
    if (bracketSpec !== null) base = __applyIdxSpec(base, bracketSpec, bracketExclude);
    else if (bangSpec !== null) base = __applyIdxSpec(base, bangSpec.replace(/:/g, ','), true);
    else if (dotSpec !== null) base = __applyIdxSpec(base, dotSpec, false);
    out = out.concat(base);
  }
  return out;
}
function __runChainSteps(rootNode, steps) {
  var current = [rootNode];
  for (var i = 0; i < steps.length; i++) {
    current = __chainStep(current, steps[i]);
    if (!current.length) break;
  }
  return current;
}
// Batch 172: combinator-aware chain evaluation — '&&'
// concatenates, '%%' interleaves, '||' takes the first
// non-empty alternative; each alternative is a full
// '@' chain. Mirrors the Dart selectChain.
function __runChainAlt(rootNode, rule) {
  var seps = ['&&', '%%', '||'];
  for (var s = 0; s < seps.length; s++) {
    var parts = rule.split(seps[s]).map(function (x) { return x.trim(); })
      .filter(function (x) { return x !== ''; });
    if (parts.length > 1) {
      var lists = parts.map(function (p) { return __runChainAlt(rootNode, p); });
      if (seps[s] === '&&') {
        var seen = [], out = [];
        for (var a = 0; a < lists.length; a++) {
          for (var b = 0; b < lists[a].length; b++) {
            if (seen.indexOf(lists[a][b]) < 0) {
              seen.push(lists[a][b]);
              out.push(lists[a][b]);
            }
          }
        }
        return out;
      }
      if (seps[s] === '%%') {
        var out2 = [], i = 0, added = true;
        while (added) {
          added = false;
          for (var c = 0; c < lists.length; c++) {
            if (i < lists[c].length) {
              out2.push(lists[c][i]);
              added = true;
            }
          }
          i++;
        }
        return out2;
      }
      for (var d = 0; d < lists.length; d++) {
        if (lists[d].length) return lists[d];
      }
      return [];
    }
  }
  var steps = rule.split('@').map(function (x) { return x.trim(); })
    .filter(function (x) { return x !== ''; });
  return __runChainSteps(rootNode, steps);
}
function __chainSelect(rootNode, rule) {
  var r = String(rule || '');
  if (r.indexOf('@css:') === 0) r = r.substring(5);
  else if (r.indexOf('@css ') === 0) r = r.substring(5);
  r = r.trim();
  var parts = r.split('@').map(function (x) { return x.trim(); })
    .filter(function (x) { return x !== ''; });
  if (parts.length <= 1) {
    // Batch 172: a BARE extraction token ('text', 'href',
    // any carried attribute) reads the element itself —
    // the same starvation the Dart side had (UU看书's
    // chapterName 'text' / chapterUrl 'href').
    var token = parts.length ? parts[0] : '';
    var known0 = { text: 1, ownText: 1, html: 1, outerHtml: 1, textNodes: 1 };
    if (token &&
        (known0[token] || (__isEl(rootNode) && rootNode.a[token] !== undefined))) {
      return { nodes: [rootNode], attr: token };
    }
    return { nodes: __runChainAlt(rootNode, r), attr: null };
  }
  var last = parts[parts.length - 1];
  var stepLike = last.indexOf('.') >= 0 || last === 'children';
  if (stepLike) {
    return { nodes: __runChainAlt(rootNode, r), attr: null };
  }
  // Batch 165: mirror the Dart side (batch 36) — a bare
  // trailing token is an attribute only when it is a known
  // extraction name or an attribute a matched element
  // actually carries. Otherwise it is one more step:
  // '.book-img-text@ul@li' ends in an li STEP, and reading
  // it as an attribute silently matched the ul instead
  // (the Qidian search script takes exactly this shape).
  var known = { text: 1, ownText: 1, html: 1, outerHtml: 1, textNodes: 1 };
  var headNodes = __runChainAlt(
    rootNode, parts.slice(0, parts.length - 1).join('@'));
  if (headNodes.length &&
      (known[last] || headNodes[0].a[last] !== undefined)) {
    return { nodes: headNodes, attr: last };
  }
  return { nodes: __runChainAlt(rootNode, r), attr: null };
}

// ---------- The java bridge ----------
var __netCache = {};
var __docCache = {};
var __vars = {};
var __doc = { t: '#root', a: {}, c: [] };
var java = {
  getElements: function (rule) {
    var found = __chainSelect(__doc, rule);
    return __elements(found.nodes);
  },
  getElement: function (rule) {
    var found = __chainSelect(__doc, rule);
    return found.nodes.length ? new __El(found.nodes[0]) : null;
  },
  getString: function (rule) {
    var r = String(rule || '').trim();
    try {
      if (r.indexOf('$.') === 0 || r[0] === '$') {
        var parts = r.substring(1).split(/[.[\]]+/).filter(function (x) { return x !== ''; });
        var v = result;
        for (var i = 0; i < parts.length; i++) {
          if (v === null || v === undefined) return '';
          v = v[parts[i]];
        }
        return v === null || v === undefined ? '' : String(v);
      }
      // CSS or shorthand-chain rule (batch 31: chains like
      // 'tag.h3.0@tag.a.1@href' now resolve too).
      var found = __chainSelect(__doc, r);
      if (!found.nodes.length) return '';
      var el = new __El(found.nodes[0]);
      var tail = found.attr || '';
      if (tail === '' || tail === 'text') return el.text();
      if (tail === 'ownText') return el.ownText();
      if (tail === 'html') return el.html();
      return el.attr(tail);
    } catch (e) { }
    return '';
  },
  ajax: function (spec) {
    var key = 'GET|' + String(spec) + '||';
    var hit = __netCache[key];
    if (hit) return hit.body;
    throw new Error('__LEGADO_NET__' + JSON.stringify({
      method: 'GET', url: String(spec), body: '', headers: {}
    }));
  },
  post: function (url, body, headers) {
    var hdrs = {};
    if (headers && typeof headers._entries === 'function') {
      var es = headers._entries();
      for (var i = 0; i < es.length; i++) hdrs[es[i][0]] = String(es[i][1]);
    } else if (headers && typeof headers === 'object') {
      for (var k in headers) hdrs[k] = String(headers[k]);
    }
    var key = 'POST|' + url + '|' + (body || '') + '|' + JSON.stringify(hdrs);
    var hit = __netCache[key];
    if (hit) {
      var code = hit.code;
      var bodyStr = hit.body;
      return {
        statusCode: function () { return code; },
        body: function () { return bodyStr; },
      };
    }
    throw new Error('__LEGADO_NET__' + JSON.stringify({
      method: 'POST', url: String(url), body: String(body || ''), headers: hdrs
    }));
  },
  log: function (x) { },
  md5Encode: function (s) { return __md5(String(s)); },
  base64Encode: function (s) { return __b64encodeBytes(__utf8Bytes(String(s))); },
  base64Decode: function (s) { return __bytesToUtf8(__b64decodeToBytes(String(s))); },
  base64DecodeToByteArray: function (s) { return __b64decodeToBytes(String(s)); },
  encodeURI: function (s) { return encodeURI(String(s)); },
  timeFormat: function (ts) {
    var d = new Date(Number(ts));
    function p(n) { return ('0' + n).slice(-2); }
    return d.getFullYear() + '-' + p(d.getMonth() + 1) + '-' + p(d.getDate()) +
           ' ' + p(d.getHours()) + ':' + p(d.getMinutes()) + ':' + p(d.getSeconds());
  },
  put: function (k, v) { __vars[String(k)] = v; },
  get: function (k) {
    var v = __vars[String(k)]; return v === undefined ? '' : v;
  },
  getLoginHeaderMap: function () { return new __HashMap(); },
  util: { HashMap: __HashMap },
};
var source = {
  getKey: function () { return ''; },
  getLoginHeaderMap: function () { return {}; },
};
var book = {};
var chapter = {};

// ---------- Batch 170: flow snapshots + StrResponse ----------
// The engine hands each run a snapshot of the current
// book/chapter (fields scripts read AND write — a script
// may rewrite book.tocUrl and the engine adopts it). The
// snapshot merges onto the long-lived book/chapter
// objects so their helper methods survive; the host
// collects the merged fields back from the envelope.
var __snapshotKeys = {};
function __mergeSnapshot(target, data, slot) {
  var prev = __snapshotKeys[slot] || [];
  for (var i = 0; i < prev.length; i++) {
    if (!(prev[i] in data)) delete target[prev[i]];
  }
  var keys = [];
  for (var k in data) {
    target[k] = data[k];
    keys.push(k);
  }
  __snapshotKeys[slot] = keys;
}
function __snapshotOut(slot, target) {
  var keys = __snapshotKeys[slot] || [];
  var out = {};
  for (var i = 0; i < keys.length; i++) {
    out[keys[i]] = target[keys[i]];
  }
  return out;
}
// The response object login-check scripts receive as
// `result`: data rides in underscore fields (so it
// survives the JSON envelope), the accessor methods are
// what scripts actually call.
function __strResponse(body, url, code) {
  return {
    __strResp: true,
    _body: body === null || body === undefined ? '' : String(body),
    _url: url === null || url === undefined ? '' : String(url),
    _code: code || 0,
    body: function () { return this._body; },
    code: function () { return this._code; },
    url: function () { return this._url; },
    message: function () { return ''; },
    isSuccessful: function () {
      return this._code >= 200 && this._code < 300;
    },
    headers: function () { return {}; },
    errorBody: function () { return ''; },
    toString: function () { return this._body; }
  };
}

// ---------- Batch 157: cookie / cache / misc bridges ----------
// Real-world bundles lean on three objects this bridge
// used to lack entirely — `cookie`, `cache`, and a fuller
// `source`/`book` — plus a tail of small java.* helpers.
// Any script touching them died with a ReferenceError and
// the whole search/explore failed ("书源 JS 报错"). The
// host mirrors the stores into every run: __cookies is a
// snapshot of the app cookie jar (domain -> {name: value}),
// __cacheStore is this source's memory cache, __bookVars
// the current book's variables. Cookie writes cannot call
// back into Dart synchronously, so they are collected in
// __cookieWrites and applied by the host after the run;
// the local snapshot is updated immediately so later reads
// in the same script see them.
var __cookies = {};
var __cookieWrites = [];
var __cacheStore = {};
var __bookVars = {};
function __hostOf(u) {
  var m = /^[a-zA-Z][a-zA-Z0-9+.-]*:\/\/([^\/:?#]+)/.exec(String(u || ''));
  return m ? m[1].toLowerCase() : String(u || '').toLowerCase();
}
function __cookieBucket(url) {
  var host = __hostOf(url);
  var best = null;
  for (var d in __cookies) {
    if (host === d || host.slice(-(d.length + 1)) === '.' + d) {
      if (!best || d.length > best.length) best = d;
    }
  }
  return best ? __cookies[best] : {};
}
var cookie = {
  getKey: function (url, name) {
    var v = __cookieBucket(url)[String(name)];
    return v === undefined || v === null ? '' : String(v);
  },
  getCookie: function (url) {
    var b = __cookieBucket(url);
    var parts = [];
    for (var k in b) parts.push(k + '=' + b[k]);
    return parts.join('; ');
  },
  setKey: function (url, name, value) {
    __cookieWrites.push({
      op: 'set', url: String(url),
      name: String(name), value: String(value),
    });
    var host = __hostOf(url);
    if (!__cookies[host]) __cookies[host] = {};
    __cookies[host][String(name)] = String(value);
  },
  setCookie: function (url, str) {
    __cookieWrites.push({ op: 'raw', url: String(url), raw: String(str) });
    var first = String(str).split(';')[0];
    var eq = first.indexOf('=');
    if (eq > 0) {
      var host = __hostOf(url);
      if (!__cookies[host]) __cookies[host] = {};
      __cookies[host][first.substring(0, eq).trim()] =
          first.substring(eq + 1).trim();
    }
  },
  removeKey: function (url, name) {
    __cookieWrites.push({ op: 'del', url: String(url), name: String(name) });
    delete __cookieBucket(url)[String(name)];
  },
  removeCookie: function (url) {
    __cookieWrites.push({ op: 'clear', url: String(url) });
    var host = __hostOf(url);
    for (var d in __cookies) {
      if (host === d || host.slice(-(d.length + 1)) === '.' + d) {
        delete __cookies[d];
      }
    }
    return '';
  },
};
var cache = {
  get: function (key) {
    var e = __cacheStore[String(key)];
    if (!e) return null;
    if (e.exp && e.exp < Date.now()) {
      delete __cacheStore[String(key)];
      return null;
    }
    return e.v === undefined ? null : e.v;
  },
  put: function (key, value, saveTime) {
    var ttl = Number(saveTime) || 0;
    __cacheStore[String(key)] = {
      v: value,
      exp: ttl > 0 ? Date.now() + ttl * 1000 : 0,
    };
    return value;
  },
  delete: function (key) { delete __cacheStore[String(key)]; },
  getFromMemory: function (key) { return cache.get(key); },
  putMemory: function (key, value) { return cache.put(key, value); },
};
// source/book completion: identity comes from the host
// (source.__key is the source URL, source.bookSourceName
// its display name — assigned per run).
source.getKey = function () { return String(source.__key || ''); };
source.getVariable = function () {
  var v = __vars['__sourceVar'];
  return v === undefined ? '' : v;
};
source.setVariable = function (v) {
  __vars['__sourceVar'] = v === undefined ? '' : String(v);
};
source.put = function (k, v) { __vars[String(k)] = v; };
source.get = function (k) {
  var v = __vars[String(k)];
  return v === undefined ? '' : v;
};
source.getLoginHeader = function () { return ''; };
// Batch 169: the host injects the source's saved login
// info per run — the raw JSON string (null when the user
// never saved the login form) and the materialized map
// (declared defaults overlaid with saved values).
var __loginInfoRaw = null;
var __loginInfoMap = null;
var __browseCache = {};
source.getLoginInfo = function () { return __loginInfoRaw; };
source.getLoginInfoMap = function () { return __loginInfoMap; };
book.getVariable = function (k) {
  var v = __bookVars[String(k)];
  return v === undefined ? null : v;
};
book.setVariable = function (k, v) { __bookVars[String(k)] = v; };
// java.* tail: UI calls are no-ops (a toast must never
// kill a rule script), Thread.sleep is a no-op (the Dart
// side is synchronous here), the rest are small utilities
// real bundles use in URL templates and rule JS.
java.toast = function (x) { };
java.longToast = function (x) { };
java.getWebViewUA = function () {
  return 'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 ' +
      '(KHTML, like Gecko) Chrome/120.0 Mobile Safari/537.36';
};
java.t2s = function (s) { return String(s); };
java.s2t = function (s) { return String(s); };
java.hexDecodeToString = function (s) {
  var hex = String(s).replace(/[^0-9a-fA-F]/g, '');
  var bytes = [];
  for (var i = 0; i + 1 < hex.length; i += 2) {
    bytes.push(parseInt(hex.substring(i, i + 2), 16));
  }
  return __bytesToUtf8(bytes);
};
java.timeFormatUTC = function (ts, format) {
  var d = new Date(Number(ts));
  function p(n) { return ('0' + n).slice(-2); }
  var f = String(format || 'yyyy-MM-dd HH:mm:ss');
  return f.replace('yyyy', String(d.getUTCFullYear()))
      .replace('MM', p(d.getUTCMonth() + 1))
      .replace('dd', p(d.getUTCDate()))
      .replace('HH', p(d.getUTCHours()))
      .replace('mm', p(d.getUTCMinutes()))
      .replace('ss', p(d.getUTCSeconds()));
};
java.getCookie = function (tag, key) {
  if (key !== undefined && key !== null && String(key) !== '') {
    return cookie.getKey(tag, key);
  }
  return cookie.getCookie(tag);
};
java.__resp = function (method, url, body, headers) {
  var hdrs = {};
  if (headers && typeof headers === 'object') {
    if (typeof headers._entries === 'function') {
      var es = headers._entries();
      for (var i = 0; i < es.length; i++) hdrs[es[i][0]] = String(es[i][1]);
    } else {
      for (var k in headers) hdrs[k] = String(headers[k]);
    }
  }
  var key = method === 'GET' && !Object.keys(hdrs).length
      ? 'GET|' + url + '||'
      : method + '|' + url + '|' + (body || '') + '|' + JSON.stringify(hdrs);
  var hit = __netCache[key];
  if (hit) {
    var code = hit.code, bodyStr = hit.body;
    return {
      code: function () { return code; },
      statusCode: function () { return code; },
      body: function () { return bodyStr; },
      toString: function () { return bodyStr; },
    };
  }
  throw new Error('__LEGADO_NET__' + JSON.stringify({
    method: method, url: url, body: body || '', headers: hdrs
  }));
};
java.connect = function (url, headers) {
  return java.__resp('GET', String(url), '', headers || {});
};
java.getStrResponse = function (url, headers) {
  return java.__resp('GET', String(url), '', headers || {});
};
java.ajaxAll = function (urls) {
  var out = [];
  var list = urls || [];
  for (var i = 0; i < list.length; i++) out.push(java.ajax(list[i]));
  return out;
};
java.getStringList = function (rule) {
  var r = String(rule || '').trim();
  try {
    if (r.indexOf('$.') === 0 || r[0] === '$') {
      var parts = r.substring(1).split(/[.[\]]+/)
          .filter(function (x) { return x !== ''; });
      var v = result;
      for (var i = 0; i < parts.length; i++) {
        if (v === null || v === undefined) return [];
        v = v[parts[i]];
      }
      if (v === null || v === undefined) return [];
      var arr = Array.isArray(v) ? v : [v];
      return arr.map(function (x) { return String(x); });
    }
    var found = __chainSelect(__doc, r);
    var tail = found.attr || '';
    return found.nodes.map(function (n) {
      var el = new __El(n);
      if (tail === '' || tail === 'text') return el.text();
      if (tail === 'ownText') return el.ownText();
      if (tail === 'html') return el.html();
      return el.attr(tail);
    });
  } catch (e) { }
  return [];
};
// Batch 169: browser requests suspend to the host
// (__LEGADO_BROWSE__), the same suspend-replay pattern
// as the network bridge. The host routes the URL to
// whatever surface can show it (the login page's
// WebView) or, with no surface registered, marks the
// request handled-empty so incidental calls in shared
// code paths degrade instead of crashing the script.
java.startBrowserAwait = function (url, title) {
  var key = String(url || '');
  if (__browseCache[key] !== undefined) return __browseCache[key];
  throw new Error('__LEGADO_BROWSE__' + JSON.stringify({
    url: key,
    title: String(title || '')
  }));
};
java.startBrowser = function (url, title) {
  java.startBrowserAwait(url, title);
};
// Batch 162: sources call webView to harvest cookies from
// a rendered page before parsing （起点男频 reads
// document.cookie through it). There is no renderer here;
// the shared jar already holds whatever the plain fetch
// collected, so document.cookie reads are answered from
// it and everything else stays empty instead of dying
// with "not a function".
java.webView = function (html, url, js) {
  if (String(js || '').indexOf('document.cookie') >= 0) {
    return cookie.getCookie(String(url || baseUrl || ''));
  }
  return '';
};
// Batch 162: 第X章 with Chinese numerals -> Arabic
// digits, for the circulating chapter-name cleaners.
function __cnChapterNum(t) {
  var digits = {'零': 0, '一': 1, '二': 2, '两': 2, '三': 3, '四': 4, '五': 5, '六': 6, '七': 7, '八': 8, '九': 9};
  var units = {'十': 10, '百': 100, '千': 1000};
  var total = 0;
  var num = 0;
  for (var i = 0; i < t.length; i++) {
    var ch = t.charAt(i);
    if (Object.prototype.hasOwnProperty.call(digits, ch)) {
      num = digits[ch];
    } else if (Object.prototype.hasOwnProperty.call(units, ch)) {
      if (num === 0) num = 1;
      total += num * units[ch];
      num = 0;
    } else {
      return null;
    }
  }
  return total + num;
}
java.toNumChapter = function (s) {
  return String(s).replace(/第([零一二两三四五六七八九十百千]+)章/g, function (m, g) {
    var n = __cnChapterNum(g);
    return n === null ? m : '第' + n + '章';
  });
};
java.openUrl = function () { };
java.open = function () { };
java.reLoginView = function () { };
java.upLoginData = function () { };
java.getVerificationCode = function () { return ''; };
function __docHash(text) {
  var h = 5381;
  for (var i = 0; i < text.length; i++) {
    h = ((h << 5) + h + text.charCodeAt(i)) | 0;
  }
  return String(h);
}
// Batch 168: real setContent — the reference swaps the
// document the rest of the rule evaluates against (the
// only way to retarget getElements after an ajax). The
// mini-DOM is built Dart-side, so an uncached document
// suspends to the host (__LEGADO_DOC__), which parses it
// and replays the script with __docCache warm — the same
// suspend-replay the network bridge uses.
java.setContent = function (html, url) {
  var text = html === null || html === undefined ? '' : String(html);
  var key = 'DOC|' + text.length + '|' + __docHash(text);
  var hit = __docCache[key];
  if (hit) {
    __doc = hit;
    if (url) baseUrl = String(url);
    return;
  }
  throw new Error('__LEGADO_DOC__' + JSON.stringify({
    key: key,
    html: text,
    url: url ? String(url) : ''
  }));
};
java.lang = { Thread: { sleep: function (ms) { } } };
var Packages = { java: { lang: { Thread: { sleep: function (ms) { } } } } };

// ---------- Batch 161: ES2022 polyfills ----------
// The bundled QuickJS predates a few standard library
// additions that current sources use freely; calling them
// died with a bare "not a function". Fill only what is
// missing, so a native implementation wins where the
// engine already has one.
if (!Array.prototype.at) {
  Array.prototype.at = function (i) {
    var n = this.length;
    var k = Math.trunc(Number(i) || 0);
    if (k < 0) k += n;
    return (k < 0 || k >= n) ? undefined : this[k];
  };
}
if (!String.prototype.at) {
  String.prototype.at = function (i) {
    var s = String(this);
    var k = Math.trunc(Number(i) || 0);
    if (k < 0) k += s.length;
    return (k < 0 || k >= s.length) ? undefined : s.charAt(k);
  };
}
if (!Array.prototype.findLast) {
  Array.prototype.findLast = function (fn) {
    for (var i = this.length - 1; i >= 0; i--) {
      if (fn(this[i], i, this)) return this[i];
    }
    return undefined;
  };
}
if (!Array.prototype.findLastIndex) {
  Array.prototype.findLastIndex = function (fn) {
    for (var i = this.length - 1; i >= 0; i--) {
      if (fn(this[i], i, this)) return i;
    }
    return -1;
  };
}
if (!Object.hasOwn) {
  Object.hasOwn = function (o, k) {
    return Object.prototype.hasOwnProperty.call(o, k);
  };
}

// jsLib helpers: bilinovel-style glyph maps expose a global
// `map` HashMap and call replContent(result).
function replContent(s) {
  if (typeof s !== 'string') return s;
  try {
    if (typeof map !== 'undefined' && map && typeof map._entries === 'function') {
      var es = map._entries();
      for (var i = 0; i < es.length; i++) {
        if (es[i][0]) s = s.split(es[i][0]).join(String(es[i][1]));
      }
    }
  } catch (e) { }
  return s;
}
''';
