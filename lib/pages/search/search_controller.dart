import 'package:mobx/mobx.dart';
import 'package:anikumo/modules/bangumi/bangumi_item.dart';
import 'package:anikumo/modules/collect/collect_type.dart';
import 'package:anikumo/modules/search/search_history_module.dart';
import 'package:anikumo/repositories/collect_repository.dart';
import 'package:anikumo/repositories/search_history_repository.dart';
import 'package:anikumo/request/apis/bangumi_api.dart';
import 'package:anikumo/utils/keyword_normalizer.dart';
import 'package:anikumo/utils/search_parser.dart';

part 'search_controller.g.dart';

class SearchPageController = _SearchPageController with _$SearchPageController;

abstract class _SearchPageController with Store {
  static const int _searchPageSize = 20;
  static const int _maxPagesPerSearch = 3;

  _SearchPageController(
    this._collectRepository,
    this._searchHistoryRepository,
  );

  final ICollectRepository _collectRepository;
  final ISearchHistoryRepository _searchHistoryRepository;

  int _searchOffset = 0;
  int _searchGeneration = 0;

  bool hasMoreSearchResults = true;

  @observable
  bool isLoading = false;

  @observable
  bool isTimeOut = false;

  /// True when the search could not reach the server at all, as opposed
  /// to a completed search that simply found nothing.
  @observable
  bool isSearchError = false;

  /// The cleaned keyword that produced results after the original
  /// keyword came back empty; empty when no fallback was needed.
  @observable
  String fallbackKeywordUsed = '';

  @observable
  bool notShowWatchedBangumis = false;

  @observable
  bool notShowAbandonedBangumis = false;

  @observable
  ObservableList<BangumiItem> bangumiList = ObservableList.of([]);

  @observable
  ObservableList<SearchHistory> searchHistories = ObservableList.of([]);

  @action
  void loadSearchHistories() {
    final histories = _searchHistoryRepository.getAllHistories();
    searchHistories.clear();
    searchHistories.addAll(histories);
  }

  @action
  Future<void> searchBangumi(String input, {String type = 'add'}) async {
    if (type == 'add' && (isLoading || !hasMoreSearchResults)) return;
    final generation = type == 'add' ? _searchGeneration : ++_searchGeneration;
    isLoading = true;
    isTimeOut = false;
    if (type != 'add') {
      isSearchError = false;
      fallbackKeywordUsed = '';
    }
    if (type != 'add') {
      bangumiList.clear();
      _searchOffset = 0;
      hasMoreSearchResults = true;
      if (!_collectRepository.getPrivateMode() && input.trim().isNotEmpty) {
        await _searchHistoryRepository.deleteDuplicates(input);
        if (_searchHistoryRepository.isHistoryFull(10)) {
          await _searchHistoryRepository.deleteOldest();
        }
        await _searchHistoryRepository.saveHistory(input);
        loadSearchHistories();
      }
    }
    if (generation != _searchGeneration) return;
    final filterState = SearchParser(input).toFilterState();
    final id = int.tryParse(filterState.id);
    if (id != null) {
      final item = await BangumiApi.getBangumiInfoByID(id);
      if (generation != _searchGeneration) return;
      if (item != null) {
        bangumiList.add(item);
      }
      hasMoreSearchResults = false;
      isLoading = false;
      isTimeOut = bangumiList.isEmpty;
      return;
    }
    var pagesFetched = 0;
    do {
      final page = await BangumiApi.bangumiSearch(filterState.keyword,
          tags: filterState.tags,
          limit: _searchPageSize,
          offset: _searchOffset,
          sort: filterState.sort,
          dateRange: filterState.effectiveDateRange,
          rankRange: filterState.rankRange,
          scoreRange: filterState.scoreRange,
          weekdays: filterState.weekdays);
      // Discard stale responses before mutating the current search.
      if (generation != _searchGeneration) return;
      if (page == null) {
        break;
      }
      pagesFetched++;
      _searchOffset += page.rawCount;
      hasMoreSearchResults = page.rawCount == _searchPageSize;
      final existingIds = bangumiList.map((item) => item.id).toSet();
      final newItems =
          page.items.where((item) => existingIds.add(item.id)).toList();
      if (newItems.isNotEmpty) {
        bangumiList.addAll(newItems);
        break;
      }
    } while (hasMoreSearchResults && pagesFetched < _maxPagesPerSearch);
    if (bangumiList.isEmpty && pagesFetched == 0) {
      // Every page request failed: a network error, not an empty
      // result set. The page shows a retry state for this.
      isSearchError = true;
    }
    if (bangumiList.isEmpty && !isSearchError && type != 'add') {
      // Decorated titles (season markers, year brackets) often miss
      // Bangumi's index entirely; retry once with the cleaned keyword.
      final fallback = KeywordNormalizer.fallbackKeyword(filterState.keyword);
      if (fallback != null) {
        final page = await BangumiApi.bangumiSearch(fallback,
            tags: filterState.tags,
            limit: _searchPageSize,
            offset: 0,
            sort: filterState.sort,
            dateRange: filterState.effectiveDateRange,
            rankRange: filterState.rankRange,
            scoreRange: filterState.scoreRange,
            weekdays: filterState.weekdays);
        if (generation != _searchGeneration) return;
        if (page != null && page.items.isNotEmpty) {
          bangumiList.addAll(page.items);
          fallbackKeywordUsed = fallback;
          hasMoreSearchResults = false;
        }
      }
    }
    isLoading = false;
    isTimeOut = bangumiList.isEmpty && !isSearchError;
  }

  @action
  Future<void> deleteSearchHistory(SearchHistory history) async {
    await _searchHistoryRepository.deleteHistory(history);
    loadSearchHistories();
  }

  @action
  Future<void> clearSearchHistory() async {
    await _searchHistoryRepository.clearAllHistories();
    loadSearchHistories();
  }

  @action
  Future<void> setNotShowWatchedBangumis(bool value) async {
    notShowWatchedBangumis = value;
  }

  @action
  Future<void> setNotShowAbandonedBangumis(bool value) async {
    notShowAbandonedBangumis = value;
  }

  Set<int> loadWatchedBangumiIds() {
    return _collectRepository.getBangumiIdsByType(CollectType.watched);
  }

  Set<int> loadAbandonedBangumiIds() {
    return _collectRepository.getBangumiIdsByType(CollectType.abandoned);
  }
}
