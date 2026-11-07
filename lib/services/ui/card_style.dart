import 'package:flutter/foundation.dart';
import 'package:anikumo/services/storage/storage.dart';

/// Global bangumi card visual style — five looks for the same card,
/// switchable in one place and applied everywhere [BangumiCardV] is
/// used (browse grids, lists, rails).
///
/// 0 经典海报 (the original layout), 1 宽幅映画 (full-bleed image with
/// a glass title bar), 2 杂志封面 (full-bleed, score chip, bold title),
/// 3 极简留白 (small centered cover on a plain surface), 4 相框典藏
/// (bordered frame around the cover).
class CardStyle {
  CardStyle._();

  static const int classic = 0;
  static const int wide = 1;
  static const int magazine = 2;
  static const int minimal = 3;
  static const int framed = 4;

  static const List<({String name, String description})> options = [
    (name: '经典海报', description: '原来的竖版海报卡，和以前一样'),
    (name: '宽幅映画', description: '封面铺满卡片，底部玻璃标题条'),
    (name: '杂志封面', description: '封面铺满，评分角标 + 粗体大标题'),
    (name: '极简留白', description: '小封面居中，大量留白，标题居中'),
    (name: '相框典藏', description: '封面装进边框，像陈列出来的收藏'),
  ];

  static final ValueNotifier<int> styleNotifier =
      ValueNotifier<int>(_storedStyle());

  static int _storedStyle() {
    try {
      final value = GStorage.getSetting(SettingsKeys.cardStyle);
      return value.clamp(classic, framed);
    } catch (_) {
      return wide;
    }
  }

  static int get style => styleNotifier.value;

  static Future<void> setStyle(int value) async {
    final clamped = value.clamp(classic, framed);
    styleNotifier.value = clamped;
    await GStorage.putSetting(SettingsKeys.cardStyle, clamped);
  }
}
