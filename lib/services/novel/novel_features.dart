import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../storage/storage.dart';
import 'legado_http.dart';

/// Batch 158: one optional feature in the novel zone's
/// feature repository. Features are capability modules the
/// user installs or leaves out; an uninstalled feature is
/// fully inert (its UI entries and integrations do not
/// exist). The built-in catalog ships with the app; extra
/// repository addresses can list further entries, and an
/// entry is installable only when its id matches a
/// capability this version actually implements — anything
/// else is shown as unsupported instead of pretending.
class NovelFeatureDef {
  const NovelFeatureDef({
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

  /// False for entries coming from a remote repository
  /// whose id this version does not implement.
  final bool supported;

  NovelFeatureDef copyWith({String? name, String? description}) =>
      NovelFeatureDef(
        id: id,
        name: name ?? this.name,
        description: description ?? this.description,
        version: version,
        sizeLabel: sizeLabel,
        supported: supported,
      );
}

/// The repository: catalog, install state, and the user's
/// extra repository addresses.
class NovelFeatures {
  NovelFeatures._();

  static const ttsId = 'tts';
  static const localBooksId = 'local_books';

  static const builtinCatalog = <NovelFeatureDef>[
    NovelFeatureDef(
      id: ttsId,
      name: '语音朗读',
      description: '用设备系统语音逐段朗读章节，可暂停、续读、调语速，'
          '读完一章自动接着读下一章。安装后，阅读器右上角会出现朗读按钮。',
      version: '1.0',
      sizeLabel: '内置功能',
    ),
    NovelFeatureDef(
      id: localBooksId,
      name: '本地书籍',
      description: '把 EPUB / TXT 文件导入本地书架，离线阅读；'
          '本地书籍也会出现在小说搜索和发现里。卸载后书籍文件保留，重装即恢复。',
      version: '1.0',
      sizeLabel: '内置功能',
    ),
  ];

  static final ValueNotifier<int> revision = ValueNotifier(0);

  static Set<String> installedIds() {
    final raw = GStorage.getSetting(SettingsKeys.novelFeatureInstallsJson);
    if (raw.isEmpty) return {};
    try {
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
      SettingsKeys.novelFeatureInstallsJson,
      jsonEncode(ids.toList()),
    );
    revision.value++;
  }

  static List<String> repoUrls() {
    final raw = GStorage.getSetting(SettingsKeys.novelFeatureReposJson);
    if (raw.isEmpty) return const [];
    try {
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
      SettingsKeys.novelFeatureReposJson,
      jsonEncode(urls),
    );
    revision.value++;
  }

  static Future<void> removeRepo(String url) async {
    final urls = repoUrls().where((e) => e != url).toList();
    await GStorage.putSetting(
      SettingsKeys.novelFeatureReposJson,
      jsonEncode(urls),
    );
    revision.value++;
  }

  /// Fetch and parse one repository address's catalog.
  /// Throws on network/HTTP/format errors so the caller can
  /// say why the address was rejected.
  static Future<List<NovelFeatureDef>> fetchCatalog(String url) async {
    final response = await LegadoHttp.fetchRaw(url);
    if (response.statusCode >= 400) {
      throw StateError('仓库返回 ${response.statusCode}');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! List) {
      throw const FormatException('目录格式不对：应为功能列表');
    }
    final known = {for (final f in builtinCatalog) f.id: f};
    final out = <NovelFeatureDef>[];
    for (final entry in decoded) {
      if (entry is! Map) continue;
      final id = entry['id']?.toString() ?? '';
      if (id.isEmpty) continue;
      final base = known[id];
      if (base != null) {
        // A known capability: the repository may refine
        // its display name/description.
        out.add(base.copyWith(
          name: entry['name']?.toString() ?? base.name,
          description:
              entry['description']?.toString() ?? base.description,
        ));
      } else {
        out.add(NovelFeatureDef(
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
  }
}
