import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../storage/storage.dart';

/// Batch 233: one optional feature in the anime zone's
/// feature repository — the third zone to adopt the
/// repository pattern (novel Batch 158, film Batch 232).
/// An uninstalled feature is fully inert; extra repository
/// addresses can list further entries, installable only
/// when this version implements their id.
class AnimeFeatureDef {
  const AnimeFeatureDef({
    required this.id,
    required this.name,
    required this.description,
    required this.version,
    required this.sizeLabel,
    this.supported = true,
  });

  final String id;
  final String name;
  final String description;
  final String version;
  final String sizeLabel;
  final bool supported;

  AnimeFeatureDef copyWith({String? name, String? description}) =>
      AnimeFeatureDef(
        id: id,
        name: name ?? this.name,
        description: description ?? this.description,
        version: version,
        sizeLabel: sizeLabel,
        supported: supported,
      );
}

class AnimeFeatures {
  AnimeFeatures._();

  static const bgmProgressId = 'bgm_progress';
  static const autoUpdateId = 'auto_update';
  static const statsId = 'watch_stats';
  static const danmakuStyleId = 'danmaku_style';

  static const builtinCatalog = <AnimeFeatureDef>[
    AnimeFeatureDef(
      id: bgmProgressId,
      name: 'Bangumi 单集进度同步',
      description: '看完一集（超过 95%）后，自动把这一集在 Bangumi 上标记为看过，'
          '补上收藏状态同步一直缺的单集进度。需要先在「Bangumi 同步」里开启同步并连接账号。',
      version: '1.0',
      sizeLabel: '内置功能',
    ),
    AnimeFeatureDef(
      id: autoUpdateId,
      name: '追番自动更新',
      description: '打开应用时自动检查「在看」的番有没有出新集（每 6 小时最多一次），'
          '有更新会在追番页顶部提醒。',
      version: '1.0',
      sizeLabel: '内置功能',
    ),
    AnimeFeatureDef(
      id: statsId,
      name: '观影报告',
      description: '根据本机观看历史生成报告：累计观看时长、看过的番与集数、'
          '最近 7 天的观看节奏。入口在「设置 → 扩展设置」里（安装后出现）。',
      version: '1.0',
      sizeLabel: '内置功能',
    ),
    AnimeFeatureDef(
      id: danmakuStyleId,
      name: '弹幕个性化',
      description: '按番记住弹幕开关（这部关了，下次打开还是关），'
          '并在弹幕设置里提供一键预设（影院 / 护眼 / 极简）。',
      version: '1.0',
      sizeLabel: '内置功能',
    ),
  ];

  static final ValueNotifier<int> revision = ValueNotifier(0);

  static Set<String> installedIds() {
    try {
      final raw = GStorage.getSetting(SettingsKeys.animeFeatureInstallsJson);
      if (raw.isEmpty) return {};
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return {for (final e in decoded) e.toString()};
      }
    } catch (_) {}
    return {};
  }

  static bool isInstalled(String id) => installedIds().contains(id);

  static Future<void> setInstalled(String id, bool installed) async {
    final ids = installedIds();
    if (installed) {
      ids.add(id);
    } else {
      ids.remove(id);
    }
    await GStorage.putSetting(
      SettingsKeys.animeFeatureInstallsJson,
      jsonEncode(ids.toList()),
    );
    revision.value++;
  }

  static List<String> repoUrls() {
    try {
      final raw = GStorage.getSetting(SettingsKeys.animeFeatureReposJson);
      if (raw.isEmpty) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return [for (final e in decoded) e.toString()];
      }
    } catch (_) {}
    return const [];
  }

  static Future<void> addRepo(String url) async {
    final urls = [...repoUrls()];
    if (!urls.contains(url)) urls.add(url);
    await GStorage.putSetting(
      SettingsKeys.animeFeatureReposJson,
      jsonEncode(urls),
    );
    revision.value++;
  }

  static Future<void> removeRepo(String url) async {
    final urls = repoUrls().where((e) => e != url).toList();
    await GStorage.putSetting(
      SettingsKeys.animeFeatureReposJson,
      jsonEncode(urls),
    );
    revision.value++;
  }

  static Future<List<AnimeFeatureDef>> fetchCatalog(String url) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode >= 400) {
        throw StateError('仓库返回 ${response.statusCode}');
      }
      final decoded = jsonDecode(body);
      if (decoded is! List) {
        throw const FormatException('目录格式不对：应为功能列表');
      }
      final known = {for (final f in builtinCatalog) f.id: f};
      final out = <AnimeFeatureDef>[];
      for (final entry in decoded) {
        if (entry is! Map) continue;
        final id = entry['id']?.toString() ?? '';
        if (id.isEmpty) continue;
        final base = known[id];
        if (base != null) {
          out.add(base.copyWith(
            name: entry['name']?.toString() ?? base.name,
            description:
                entry['description']?.toString() ?? base.description,
          ));
        } else {
          out.add(AnimeFeatureDef(
            id: id,
            name: entry['name']?.toString() ?? id,
            description: entry['description']?.toString() ?? '',
            version: entry['version']?.toString() ?? '',
            sizeLabel: '',
            supported: false,
          ));
        }
      }
      return out;
    } finally {
      client.close(force: true);
    }
  }
}

/// Batch 233 （单集进度同步）: the set of episodes already
/// reported to Bangumi as watched ("bangumiId:episode"),
/// so a rewatch or a progress re-fire never double-posts.
abstract final class AnimeBgmSyncedStore {
  static Set<String> _all() {
    try {
      final raw = GStorage.getSetting(SettingsKeys.animeBgmSyncedJson);
      if (raw.isEmpty) return {};
      final decoded = jsonDecode(raw);
      if (decoded is List) return {for (final e in decoded) e.toString()};
    } catch (_) {}
    return {};
  }

  static bool contains(int bangumiId, int episode) =>
      _all().contains('$bangumiId:$episode');

  static Future<void> add(int bangumiId, int episode) async {
    final all = _all()..add('$bangumiId:$episode');
    // Keep the set bounded; the oldest entries are the
    // least likely to be re-fired.
    final list = all.toList();
    if (list.length > 2000) list.removeRange(0, list.length - 2000);
    await GStorage.putSetting(
      SettingsKeys.animeBgmSyncedJson,
      jsonEncode(list),
    );
  }
}

/// Batch 233 （弹幕个性化）: per-anime danmaku on/off
/// memory. A null lookup means "no memory — use the
/// global default".
abstract final class AnimeDanmakuPrefs {
  static Map<String, bool> _all() {
    try {
      final raw = GStorage.getSetting(SettingsKeys.animeDanmakuPrefsJson);
      if (raw.isEmpty) return {};
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return decoded.map((k, v) => MapEntry('$k', v == true));
      }
    } catch (_) {}
    return {};
  }

  static bool? enabledFor(int bangumiId) => _all()['$bangumiId'];

  static Future<void> setEnabled(int bangumiId, bool enabled) async {
    final all = _all();
    all['$bangumiId'] = enabled;
    await GStorage.putSetting(
      SettingsKeys.animeDanmakuPrefsJson,
      jsonEncode(all),
    );
  }
}

/// Batch 233 （弹幕个性化）: one-tap danmaku style presets
/// over the existing danmaku settings keys (opacity, font
/// size, on-screen duration, display area, border).
class DanmakuPreset {
  const DanmakuPreset({
    required this.name,
    required this.opacity,
    required this.fontSize,
    required this.durationSeconds,
    required this.area,
    required this.border,
  });

  final String name;
  final double opacity;
  final double fontSize;

  /// Seconds a danmaku stays on screen — higher is slower.
  final double durationSeconds;

  /// Fraction of the screen height danmaku may occupy.
  final double area;
  final bool border;

  static const presets = <DanmakuPreset>[
    DanmakuPreset(
      name: '影院',
      opacity: 0.85,
      fontSize: 17,
      durationSeconds: 8,
      area: 0.6,
      border: true,
    ),
    DanmakuPreset(
      name: '护眼',
      opacity: 0.55,
      fontSize: 15,
      durationSeconds: 10,
      area: 0.45,
      border: false,
    ),
    DanmakuPreset(
      name: '极简',
      opacity: 0.4,
      fontSize: 14,
      durationSeconds: 10,
      area: 0.3,
      border: false,
    ),
  ];

  Future<void> apply() async {
    await GStorage.putSetting(SettingsKeys.danmakuOpacity, opacity);
    await GStorage.putSetting(SettingsKeys.danmakuFontSize, fontSize);
    await GStorage.putSetting(SettingsKeys.danmakuDuration, durationSeconds);
    await GStorage.putSetting(SettingsKeys.danmakuArea, area);
    await GStorage.putSetting(SettingsKeys.danmakuBorder, border);
  }
}
