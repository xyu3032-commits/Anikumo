import 'package:anikumo/modules/danmaku/danmaku_module.dart';

/// Danmaku flood control.
///
/// Popular episodes can carry 10k+ comments; rendering all of them is
/// wasteful and unreadable. When an episode exceeds [cap], keep a
/// uniformly strided subset: because the list is time-ordered, a fixed
/// stride preserves the time distribution (and roughly the type mix)
/// while bounding the render load. Below the cap the list is returned
/// untouched.
List<DanmakuEntry> thinDanmaku(List<DanmakuEntry> entries, {int cap = 3000}) {
  if (cap <= 0 || entries.length <= cap) return entries;
  final stride = entries.length / cap;
  final result = <DanmakuEntry>[];
  var next = 0.0;
  for (var i = 0; i < entries.length && result.length < cap; i++) {
    if (i >= next) {
      result.add(entries[i]);
      next += stride;
    }
  }
  return result;
}
