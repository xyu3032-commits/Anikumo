import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:anikumo/plugins/plugins.dart';
import 'package:anikumo/services/plugin/rule_repository.dart';
import 'package:anikumo/utils/encoding.dart';
import 'package:anikumo/utils/error_message.dart';
import 'package:anikumo/utils/transient_retry.dart';

/// Batch 59: whether pasted text is a single bare http(s)
/// URL (a rule file the user wants downloaded), as opposed
/// to rule JSON or an anikumo:// share link.
bool isBareRuleUrl(String text) {
  final value = text.trim();
  if (!value.startsWith('http://') && !value.startsWith('https://')) {
    return false;
  }
  return !RegExp(r'\s').hasMatch(value);
}

typedef RuleTextFetcher = Future<String> Function(String url);

Future<String> _dioFetchRuleText(String url) async {
  final response = await Dio().get<String>(
    url.trim(),
    options: Options(
      responseType: ResponseType.plain,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
    ),
  );
  return response.data ?? '';
}

/// Batch 59: downloads a rule file from a user-supplied
/// URL and parses it exactly like pasted content. Throws
/// on transport failure; parse problems come back inside
/// the result's failures.
///
/// Batch 62 optimization: kept as the single-URL spelling
/// of [parseRuleUrls] for existing callers; new code should
/// prefer [importFromPastedText].
Future<PluginImportParseResult> parseRuleUrl(String url) async {
  final text = await _dioFetchRuleText(url);
  if (text.trim().isEmpty) {
    return const PluginImportParseResult(
      plugins: [],
      failures: ['下载到的文件是空的'],
      duplicateCount: 0,
    );
  }
  return PluginImportParser.parse(text);
}

/// Batch 62 optimization: the bare http(s) URLs standing on
/// their own lines in [text], in order, deduplicated. The
/// old import only recognized a paste that was ONE bare
/// URL; users paste lists of rule links, one per line.
List<String> extractBareRuleUrls(String text) {
  final seen = <String>{};
  final urls = <String>[];
  for (final line in text.split('\n')) {
    final value = line.trim();
    if (isBareRuleUrl(value) && seen.add(value)) {
      urls.add(value);
    }
  }
  return urls;
}

/// Batch 62 optimization: merges per-file parse results
/// into one, deduplicating by rule name (a later file wins,
/// matching PluginImportParser's own semantics).
PluginImportParseResult mergeImportResults(
  List<PluginImportParseResult> results,
) {
  final uniquePlugins = <String, Plugin>{};
  var duplicateCount = 0;
  final failures = <String>[];
  for (final result in results) {
    duplicateCount += result.duplicateCount;
    failures.addAll(result.failures);
    for (final plugin in result.plugins) {
      final key = pluginNameKey(plugin.name);
      if (uniquePlugins.containsKey(key)) duplicateCount++;
      uniquePlugins[key] = plugin;
    }
  }
  return PluginImportParseResult(
    plugins: List.unmodifiable(uniquePlugins.values),
    failures: List.unmodifiable(failures),
    duplicateCount: duplicateCount,
  );
}

/// Batch 62 optimization: downloads and parses several
/// rule files with bounded concurrency and one transient
/// retry each (a flaky CDN no longer fails the whole
/// import). A file that cannot be fetched or parsed lands
/// in the merged failures with its URL named; it never
/// sinks the other files.
Future<PluginImportParseResult> parseRuleUrls(
  List<String> urls, {
  RuleTextFetcher? fetcher,
  int concurrency = 5,
}) async {
  final fetch = fetcher ?? _dioFetchRuleText;
  final results = <PluginImportParseResult>[];
  for (var start = 0; start < urls.length; start += concurrency) {
    final end =
        start + concurrency > urls.length ? urls.length : start + concurrency;
    final chunk = urls.sublist(start, end);
    results.addAll(await Future.wait(chunk.map((url) async {
      try {
        final text = await retryTransient(() => fetch(url));
        if (text.trim().isEmpty) {
          return PluginImportParseResult(
            plugins: const [],
            failures: ['下载到的文件是空的：$url'],
            duplicateCount: 0,
          );
        }
        return PluginImportParser.parse(text);
      } catch (e) {
        return PluginImportParseResult(
          plugins: const [],
          failures: ['下载失败（$url）：${friendlyError(e)}'],
          duplicateCount: 0,
        );
      }
    })));
  }
  return mergeImportResults(results);
}

/// Batch 62 optimization: the single entry point for
/// paste-style rule import (import dialog, first-run step).
///
/// Local content (JSON, JSON arrays, anikumo:// links) is
/// parsed exactly as before and, when it yields rules,
/// returned untouched. Only when local parsing finds
/// nothing are standalone URL lines treated as downloads —
/// as many as the user pasted, fetched via [parseRuleUrls].
/// Lines that are rule *repository* addresses are not
/// downloaded (a repo page is HTML, not a rule); they come
/// back as a guidance failure pointing at the repository
/// page, which owns batch import.
Future<PluginImportParseResult> importFromPastedText(
  String text, {
  RuleTextFetcher? fetcher,
}) async {
  final local = PluginImportParser.parse(text);
  if (local.plugins.isNotEmpty) return local;
  final urls = extractBareRuleUrls(text);
  if (urls.isEmpty) return local;
  final fileUrls = <String>[];
  final repoNotes = <String>[];
  for (final url in urls) {
    if (RuleRepository.normalizeBase(url) != null) {
      repoNotes.add('「$url」是规则仓库地址，请到「规则管理 → 规则仓库」粘贴它批量导入');
    } else {
      fileUrls.add(url);
    }
  }
  if (fileUrls.isEmpty) {
    return PluginImportParseResult(
      plugins: const [],
      failures: List.unmodifiable(repoNotes),
      duplicateCount: 0,
    );
  }
  final downloaded = await parseRuleUrls(fileUrls, fetcher: fetcher);
  if (repoNotes.isEmpty) return downloaded;
  return PluginImportParseResult(
    plugins: downloaded.plugins,
    failures: List.unmodifiable([...downloaded.failures, ...repoNotes]),
    duplicateCount: downloaded.duplicateCount,
  );
}

class PluginImportParseResult {
  const PluginImportParseResult({
    required this.plugins,
    required this.failures,
    required this.duplicateCount,
  });

  final List<Plugin> plugins;
  final List<String> failures;
  final int duplicateCount;

  int get failureCount => failures.length;
}

class PluginImportParser {
  const PluginImportParser._();

  static final RegExp _ruleLinkPayloadPrefixPattern = RegExp(
    r'^[A-Za-z0-9+/_=%\-\s]+',
  );
  static final RegExp _whitespacePattern = RegExp(r'\s+');

  static PluginImportParseResult parse(String input) {
    final value = input.trim();
    if (value.isEmpty) {
      return const PluginImportParseResult(
        plugins: [],
        failures: ['导入内容为空'],
        duplicateCount: 0,
      );
    }

    final parsed = <Plugin>[];
    final failures = <String>[];
    Object? jsonValue;
    var decodedAsJson = false;
    try {
      jsonValue = json.decode(value);
      decodedAsJson = true;
    } on FormatException {
      // Share links and text files are parsed below.
    }

    if (decodedAsJson) {
      if (jsonValue is List) {
        for (var index = 0; index < jsonValue.length; index++) {
          _parseEntry(jsonValue[index], index + 1, parsed, failures);
        }
      } else {
        _parseEntry(jsonValue, 1, parsed, failures);
      }
    } else {
      final segments = findAnikumoRuleLinkSegments(value).toList();
      if (segments.isEmpty) {
        failures.add('未找到有效的 JSON 或 anikumo:// 规则链接');
      } else {
        for (var index = 0; index < segments.length; index++) {
          final segment = segments[index];
          _parseRuleLinkSegment(
            segment.scheme,
            segment.rawPayload,
            index + 1,
            parsed,
            failures,
          );
        }
      }
    }

    final uniquePlugins = <String, Plugin>{};
    var duplicateCount = 0;
    for (final plugin in parsed) {
      final key = pluginNameKey(plugin.name);
      if (uniquePlugins.containsKey(key)) {
        duplicateCount++;
      }
      uniquePlugins[key] = plugin;
    }

    return PluginImportParseResult(
      plugins: List.unmodifiable(uniquePlugins.values),
      failures: List.unmodifiable(failures),
      duplicateCount: duplicateCount,
    );
  }

  static void _parseRuleLinkSegment(
    String scheme,
    String rawPayload,
    int index,
    List<Plugin> plugins,
    List<String> failures,
  ) {
    try {
      final entry = _decodeRuleEntry(scheme, rawPayload);
      _parseEntry(entry, index, plugins, failures);
    } catch (error) {
      failures.add('第 $index 条：$error');
    }
  }

  static Map<String, dynamic> _decodeRuleEntry(
    String scheme,
    String rawPayload,
  ) {
    final payload = _ruleLinkPayloadPrefixPattern
        .firstMatch(rawPayload)
        ?.group(0)
        ?.trimRight();
    if (payload == null || payload.isEmpty) {
      throw const FormatException('Missing payload in Anikumo rule link');
    }

    final candidates = <String>[payload];
    final whitespaceMatches = _whitespacePattern.allMatches(payload).toList();
    for (final whitespaceMatch in whitespaceMatches.reversed) {
      final candidate = payload.substring(0, whitespaceMatch.start).trimRight();
      if (candidate.isNotEmpty && candidate != candidates.last) {
        candidates.add(candidate);
      }
    }

    FormatException? firstError;
    for (final candidate in candidates) {
      try {
        final decoded = json.decode(anikumoBase64ToJson('$scheme$candidate'));
        if (decoded is Map) {
          return Map<String, dynamic>.from(decoded);
        }
        firstError ??=
            const FormatException('规则链接内容必须是 JSON object');
      } on FormatException catch (error) {
        firstError ??= error;
        // Try a shorter prefix in case prose follows the rule link.
      }
    }
    throw firstError ?? const FormatException('Invalid Anikumo rule link');
  }

  static void _parseEntry(
    Object? entry,
    int index,
    List<Plugin> plugins,
    List<String> failures,
  ) {
    try {
      late final Plugin plugin;
      if (entry is Map) {
        plugin = Plugin.fromJson(Map<String, dynamic>.from(entry));
      } else if (entry is String) {
        final decoded = json.decode(anikumoBase64ToJson(entry));
        if (decoded is! Map) {
          throw const FormatException('规则链接内容必须是 JSON object');
        }
        plugin = Plugin.fromJson(Map<String, dynamic>.from(decoded));
      } else {
        throw const FormatException('规则必须是 JSON object 或 anikumo:// 链接');
      }

      if (plugin.name.trim().isEmpty) {
        throw const FormatException('规则名称不能为空');
      }
      if (plugin.requiresNewerClient) {
        throw const FormatException('规则需要更高版本客户端');
      }
      plugins.add(plugin);
    } catch (error) {
      failures.add('第 $index 条：$error');
    }
  }
}
