import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../storage/storage.dart';

/// Batch 234: one optional feature in the manga zone's
/// feature repository — the fourth zone to adopt the
/// repository pattern (novel Batch 158, film Batch 232,
/// anime Batch 233). An uninstalled feature is fully
/// inert; extra repository addresses can list further
/// entries, installable only when this version
/// implements their id.
class MangaFeatureDef {
  const MangaFeatureDef({
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

  MangaFeatureDef copyWith({String? name, String? description}) =>
      MangaFeatureDef(
        id: id,
        name: name ?? this.name,
        description: description ?? this.description,
        version: version,
        sizeLabel: sizeLabel,
        supported: supported,
      );
}

class MangaFeatures {
  MangaFeatures._();

  static const cbzExportId = 'cbz_export';
  static const readerFiltersId = 'reader_filters';
  static const autoScrollId = 'auto_scroll';
  static const deepPrefetchId = 'deep_prefetch';

  static const builtinCatalog = <MangaFeatureDef>[
    MangaFeatureDef(
      id: cbzExportId,
      name: '章节导出 CBZ',
      description: '把已下载的章节打包成 CBZ 文件保存到你选择的位置，'
          '可以在其他阅读器里打开。入口在「下载管理」每章的导出按钮（安装后出现）。',
      version: '1.0',
      sizeLabel: '内置功能',
    ),
    MangaFeatureDef(
      id: readerFiltersId,
      name: '阅读滤镜',
      description: '给阅读器页面加颜色滤镜：灰度（省电护眼）、反色（白页变黑，夜里不刺眼）、'
          '暖色（降低蓝光）。在「漫画设置 → 阅读」里选，随时可关。',
      version: '1.0',
      sizeLabel: '内置功能',
    ),
    MangaFeatureDef(
      id: autoScrollId,
      name: '条漫自动滚动',
      description: '连续滚动模式下自动往下滚，不用一直划。阅读器底栏多一个播放/暂停按钮，'
          '速度在「漫画设置 → 阅读」里调；点住屏幕或滚到底会自动停。',
      version: '1.0',
      sizeLabel: '内置功能',
    ),
    MangaFeatureDef(
      id: deepPrefetchId,
      name: '深度预读',
      description: '原本读到 70% 只预读下一话；装后连下下话的页图也提前备好，'
          '连看三话以上时章节交界不再等加载（会多用一点流量与缓存）。',
      version: '1.0',
      sizeLabel: '内置功能',
    ),
  ];

  static final ValueNotifier<int> revision = ValueNotifier(0);

  static Set<String> installedIds() {
    try {
      final raw = GStorage.getSetting(SettingsKeys.mangaFeatureInstallsJson);
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
      SettingsKeys.mangaFeatureInstallsJson,
      jsonEncode(ids.toList()),
    );
    revision.value++;
  }

  static List<String> repoUrls() {
    try {
      final raw = GStorage.getSetting(SettingsKeys.mangaFeatureReposJson);
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
      SettingsKeys.mangaFeatureReposJson,
      jsonEncode(urls),
    );
    revision.value++;
  }

  static Future<void> removeRepo(String url) async {
    final urls = repoUrls().where((e) => e != url).toList();
    await GStorage.putSetting(
      SettingsKeys.mangaFeatureReposJson,
      jsonEncode(urls),
    );
    revision.value++;
  }

  static Future<List<MangaFeatureDef>> fetchCatalog(String url) async {
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
      final out = <MangaFeatureDef>[];
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
          out.add(MangaFeatureDef(
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

/// Batch 234 （阅读滤镜 pack): the reader's color filters.
/// The matrices are the standard luminance / invert /
/// warm-tint color matrices.
abstract final class MangaReaderFilters {
  static const modes = <(String, String)>[
    ('', '关闭'),
    ('gray', '灰度'),
    ('invert', '反色'),
    ('warm', '暖色'),
  ];

  static ColorFilter? filterFor(String mode) {
    return switch (mode) {
      'gray' => const ColorFilter.matrix(<double>[
          0.2126, 0.7152, 0.0722, 0, 0,
          0.2126, 0.7152, 0.0722, 0, 0,
          0.2126, 0.7152, 0.0722, 0, 0,
          0, 0, 0, 1, 0,
        ]),
      'invert' => const ColorFilter.matrix(<double>[
          -1, 0, 0, 0, 255,
          0, -1, 0, 0, 255,
          0, 0, -1, 0, 255,
          0, 0, 0, 1, 0,
        ]),
      'warm' => const ColorFilter.matrix(<double>[
          1.0, 0, 0, 0, 12,
          0, 0.92, 0, 0, 4,
          0, 0, 0.78, 0, 0,
          0, 0, 0, 1, 0,
        ]),
      _ => null,
    };
  }
}
