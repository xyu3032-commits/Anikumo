import 'dart:async';

import 'package:anikumo/modules/search/plugin_search_module.dart';
import 'package:anikumo/pages/info/info_controller.dart';
import 'package:anikumo/plugins/plugins.dart';
import 'package:anikumo/plugins/plugins_controller.dart';
import 'package:anikumo/services/logging/logger.dart';
import 'package:anikumo/services/plugin/plugin_circuit_breaker.dart';
import 'package:anikumo/services/plugin/rule_engine_models.dart';
import 'package:anikumo/utils/async_session.dart';

class PluginSearchService {
  PluginSearchService({
    required this.infoController,
    required this.pluginsController,
    PluginCircuitBreaker? circuitBreaker,
  }) : circuitBreaker = circuitBreaker ?? PluginCircuitBreaker();

  final InfoController infoController;
  final PluginsController pluginsController;

  /// Skips plugins that keep failing after a short streak, so one dead
  /// source can no longer stall every search for a full timeout window.
  final PluginCircuitBreaker circuitBreaker;

  /// Upper bound for a single plugin's search. One hung source must not
  /// stall the whole multi-source search: after this the plugin is
  /// marked [PluginSearchStatus.timeout] and the rest move on, which
  /// also bounds how long [queryAllSource] can take overall.
  static const Duration perPluginTimeout = Duration(seconds: 12);

  final RuleCancelToken _cancelToken = RuleCancelToken();

  /// Per-plugin sessions so a replacement query (alias/manual search)
  /// invalidates the write-back of the still-running previous one.
  final Map<String, AsyncSessionOwner> _querySessions = {};
  bool _isCancelled = false;

  Future<void> querySource(String keyword, String pluginName) async {
    for (final plugin in pluginsController.pluginList) {
      if (plugin.name == pluginName) {
        infoController.pluginSearchResponseList.removeWhere(
          (response) => response.pluginName == pluginName,
        );
        infoController.pluginSearchStatus[pluginName] =
            PluginSearchStatus.pending;
        // A manual single-source query is the user's explicit retry, so it
        // may probe even while the circuit is open.
        await _queryPlugin(plugin, keyword, forceProbe: true);
        return;
      }
    }
  }

  /// Publishes the result page harvested by the captcha webview, skipping
  /// one network round trip. Returns false when the HTML does not parse
  /// into results; callers should fall back to [querySource].
  bool applyHarvestedSearchResult(String pluginName, String html) {
    if (_isCancelled) return false;
    for (final plugin in pluginsController.pluginList) {
      if (plugin.name != pluginName) continue;
      final result = plugin.parseHarvestedSearch(html);
      if (result == null) return false;
      infoController.pluginSearchResponseList.removeWhere(
        (response) => response.pluginName == pluginName,
      );
      infoController.pluginSearchStatus[pluginName] =
          PluginSearchStatus.success;
      circuitBreaker.recordSuccess(pluginName);
      pluginsController.validityTracker.markSearchValid(pluginName);
      infoController.pluginSearchResponseList.add(result);
      return true;
    }
    return false;
  }

  Future<void> queryAllSource(String keyword) async {
    infoController.pluginSearchResponseList.clear();
    infoController.pluginSearchStatus.clear();

    final plugins = List<Plugin>.of(pluginsController.pluginList);
    for (final plugin in plugins) {
      infoController.pluginSearchStatus[plugin.name] =
          PluginSearchStatus.pending;
    }
    await Future.wait(
      plugins.map((plugin) => _queryPlugin(plugin, keyword)),
    );
  }

  Future<void> _queryPlugin(
    Plugin plugin,
    String keyword, {
    bool forceProbe = false,
  }) async {
    if (_isCancelled) return;
    if (!circuitBreaker.canExecute(plugin.name, forceProbe: forceProbe)) {
      AnikumoLogger().i(
        'PluginSearchService: circuit open, skipping ${plugin.name} '
        '(${circuitBreaker.consecutiveFailures(plugin.name)} consecutive '
        'failures)',
      );
      infoController.pluginSearchStatus[plugin.name] =
          PluginSearchStatus.circuitOpen;
      return;
    }
    final session = _querySessions
        .putIfAbsent(plugin.name, AsyncSessionOwner.new)
        .begin();
    try {
      final rawResult = await plugin
          .queryBangumi(
            keyword,
            shouldRethrow: true,
            cancelToken: _cancelToken,
          )
          .timeout(perPluginTimeout);
      // Rule sites often repeat an entry (e.g. a "recommended" block
      // duplicating the first hit); collapse those before publishing.
      final result = PluginSearchResponse(
        pluginName: rawResult.pluginName,
        data: dedupeSearchItems(rawResult.data),
      );
      if (_isCancelled || session.isStale) {
        circuitBreaker.releaseProbe(plugin.name);
        return;
      }
      circuitBreaker.recordSuccess(plugin.name);
      infoController.pluginSearchStatus[plugin.name] =
          PluginSearchStatus.success;
      if (result.data.isNotEmpty) {
        pluginsController.validityTracker.markSearchValid(plugin.name);
      }
      infoController.pluginSearchResponseList.add(result);
    } catch (error) {
      if (_isCancelled || session.isStale) {
        circuitBreaker.releaseProbe(plugin.name);
        return;
      }
      if (error is TimeoutException) {
        // The source is reachable too slowly to be useful right now;
        // count it as a failure so repeated stalls trip the breaker.
        circuitBreaker.recordFailure(plugin.name);
        AnikumoLogger()
            .w('PluginSearchService: search timed out for ${plugin.name}');
        infoController.pluginSearchStatus[plugin.name] =
            PluginSearchStatus.timeout;
        return;
      }
      _handleSearchError(plugin, error);
    }
  }

  void _handleSearchError(Plugin plugin, Object error) {
    if (error is CaptchaRequiredException) {
      // The site answered with a challenge: it is alive, not failing.
      circuitBreaker.recordAlive(error.pluginName);
      AnikumoLogger().i(
        'PluginSearchService: captcha required for ${error.pluginName}',
      );
      infoController.pluginSearchStatus[error.pluginName] =
          PluginSearchStatus.captcha;
      return;
    }
    if (error is NoResultException) {
      // The site answered with an empty result set: also alive.
      circuitBreaker.recordAlive(error.pluginName);
      AnikumoLogger().i(
        'PluginSearchService: no results for ${error.pluginName}',
      );
      infoController.pluginSearchStatus[error.pluginName] =
          PluginSearchStatus.noResult;
      return;
    }
    final name = error is SearchErrorException ? error.pluginName : plugin.name;
    circuitBreaker.recordFailure(name);
    AnikumoLogger().w('PluginSearchService: search error for $name');
    infoController.pluginSearchStatus[name] = PluginSearchStatus.error;
  }

  void cancel() {
    _isCancelled = true;
    _cancelToken.cancel();
  }
}
