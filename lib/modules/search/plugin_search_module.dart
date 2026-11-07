/// Per-plugin search progress, written solely by PluginSearchService.
enum PluginSearchStatus {
  pending,
  success,
  error,
  noResult,
  captcha,

  /// The plugin's circuit breaker is open after repeated failures; the
  /// search was skipped instantly instead of waiting out a full timeout.
  circuitOpen,

  /// The plugin did not answer within the per-plugin search timeout; the
  /// overall search finished without it instead of stalling.
  timeout,
}

class SearchItem {
  String name;
  String src;

  SearchItem({
    required this.name,
    required this.src,
  });

  factory SearchItem.fromJson(Map<String, dynamic> json) {
    return SearchItem(name: json['name'], src: json['src']);
  }
}

class PluginSearchResponse {
  String pluginName;
  List<SearchItem> data;

  PluginSearchResponse({
    required this.pluginName,
    required this.data,
  });

  factory PluginSearchResponse.fromJson(Map<String, dynamic> json) {
    return PluginSearchResponse(
      pluginName: json['pluginName'],
      data: (json['data'] as List)
          .map((itemJson) => SearchItem.fromJson(itemJson))
          .toList(),
    );
  }
}

/// Removes duplicate entries a single source returned for the same title
/// and page (rule sites frequently repeat the first result in a
/// "recommended" block). Identity is the trimmed, case-insensitive name
/// plus the trimmed target URL; first occurrence wins, order is kept.
List<SearchItem> dedupeSearchItems(List<SearchItem> items) {
  final seen = <String>{};
  final result = <SearchItem>[];
  for (final item in items) {
    final key = '${item.name.trim().toLowerCase()}|${item.src.trim()}';
    if (seen.add(key)) {
      result.add(item);
    }
  }
  return result;
}
