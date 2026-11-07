import 'dart:io';
import 'dart:convert';
import 'package:mobx/mobx.dart';
import 'package:path_provider/path_provider.dart';
import 'package:anikumo/plugins/plugins.dart';
import 'package:anikumo/services/plugin/plugin_validity_tracker.dart';
import 'package:anikumo/services/logging/logger.dart';
import 'package:anikumo/utils/async_serial_queue.dart';

part 'plugins_controller.g.dart';

class PluginsController = _PluginsController with _$PluginsController;

typedef PluginJsonWriter = Future<void> Function(String jsonData);
typedef PluginErrorReporter = void Function(
  String message,
  Object error,
  StackTrace stackTrace,
);

void _defaultPluginErrorReporter(
  String message,
  Object error,
  StackTrace stackTrace,
) {
  AnikumoLogger().e(message, error: error, stackTrace: stackTrace);
}

/// The user's own rule collection. Batch 59: the built-in
/// rule catalog (规则仓库) is gone — rules only ever enter
/// through the user's own imports (URL / paste / file /
/// manual creation), and nothing here phones a repository.
abstract class _PluginsController with Store {
  _PluginsController({
    PluginJsonWriter? pluginJsonWriter,
    PluginErrorReporter? errorReporter,
  })  : _pluginJsonWriter = pluginJsonWriter,
        _errorReporter = errorReporter ?? _defaultPluginErrorReporter;

  final PluginJsonWriter? _pluginJsonWriter;
  final PluginErrorReporter _errorReporter;
  final AsyncSerialQueue _mutations = AsyncSerialQueue();
  int _optimisticReorderRevision = 0;

  @observable
  ObservableList<Plugin> pluginList = ObservableList.of([]);

  final validityTracker = PluginValidityTracker();

  static const _pluginsFileName = 'plugins.json';
  File? _pluginsFile;

  Future<void> init() async {
    final supportDirectory = await getApplicationSupportDirectory();
    final legacyDirectory = Directory('${supportDirectory.path}/plugins');
    final directory = Directory('${legacyDirectory.path}/v2');
    await directory.create(recursive: true);
    AnikumoLogger().i('Plugins Directory: ${directory.path}');
    final pluginsFile = File('${directory.path}/$_pluginsFileName');
    _pluginsFile = pluginsFile;
    pluginList.clear();
    if (await pluginsFile.exists()) {
      final List<dynamic> json = jsonDecode(await pluginsFile.readAsString());
      pluginList.addAll([for (final item in json) Plugin.fromJson(item)]);
      AnikumoLogger().i('Plugin: Current Plugin number: ${pluginList.length}');
    } else {
      await _migrateLegacyPlugins(legacyDirectory);
    }
  }

  // Before 1.5.1 each rule was a separate JSON file in the parent directory.
  Future<void> _migrateLegacyPlugins(Directory legacyDirectory) async {
    final legacyFiles = legacyDirectory
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('.json'));
    for (final file in legacyFiles) {
      pluginList.add(Plugin.fromJson(jsonDecode(await file.readAsString())));
      await file.delete();
    }
    await _savePlugins();
  }

  List<dynamic> _pluginListToJson() =>
      [for (final plugin in pluginList) plugin.toJson()];

  Future<void> removePlugin(Plugin plugin) {
    return _mutateAndPersist(
      () => pluginList.removeWhere(
        (candidate) =>
            pluginNameKey(candidate.name) == pluginNameKey(plugin.name),
      ),
      errorMessage: 'Plugin: failed to persist rule removal',
    );
  }

  void _replacePlugin(Plugin plugin) {
    bool flag = false;
    for (int i = 0; i < pluginList.length; ++i) {
      if (pluginNameKey(pluginList[i].name) == pluginNameKey(plugin.name)) {
        pluginList.replaceRange(i, i + 1, [plugin]);
        flag = true;
        break;
      }
    }
    if (!flag) {
      pluginList.add(plugin);
    }
  }

  Future<T> _mutateAndPersist<T>(
    T Function() mutate, {
    required String errorMessage,
  }) {
    return _mutations.run(
      () => _mutateAndPersistNow(
        mutate,
        errorMessage: errorMessage,
      ),
    );
  }

  Future<T> _mutateAndPersistNow<T>(
    T Function() mutate, {
    required String errorMessage,
  }) async {
    final previous = List<Plugin>.from(pluginList);
    try {
      final result = mutate();
      await _savePlugins();
      return result;
    } catch (error, stackTrace) {
      pluginList
        ..clear()
        ..addAll(previous);
      _errorReporter(errorMessage, error, stackTrace);
      rethrow;
    }
  }

  Future<void> updatePlugin(Plugin plugin) {
    return _mutateAndPersist(
      () => _replacePlugin(plugin),
      errorMessage: 'Plugin: failed to persist rule update',
    );
  }

  Future<void> updatePlugins(Iterable<Plugin> plugins) {
    return _mutateAndPersist(
      () {
        for (final plugin in plugins) {
          _replacePlugin(plugin);
        }
      },
      errorMessage: 'Plugin: failed to persist imported rules',
    );
  }

  Future<void> onReorder(int oldIndex, int newIndex) {
    final previous = List<Plugin>.from(pluginList);
    final plugin = pluginList.removeAt(oldIndex);
    pluginList.insert(newIndex, plugin);
    final jsonData = jsonEncode(_pluginListToJson());
    final revision = ++_optimisticReorderRevision;
    return _mutations.run(() async {
      try {
        await _writePluginsJson(jsonData);
      } catch (error, stackTrace) {
        if (revision == _optimisticReorderRevision) {
          pluginList
            ..clear()
            ..addAll(previous);
        }
        _errorReporter(
          'Plugin: failed to persist rule order',
          error,
          stackTrace,
        );
        rethrow;
      }
    });
  }

  Future<void> _savePlugins() async {
    final jsonData = jsonEncode(_pluginListToJson());
    await _writePluginsJson(jsonData);
  }

  Future<void> _writePluginsJson(String jsonData) async {
    final writer = _pluginJsonWriter;
    if (writer != null) {
      await writer(jsonData);
    } else {
      await _pluginsFile!.writeAsString(jsonData);
      AnikumoLogger().i('Plugin: updated plugin file $_pluginsFileName');
    }
  }

  Future<void> removePlugins(Set<String> pluginNames) {
    final names = Set<String>.of(pluginNames);
    return _mutateAndPersist(
      () {
        for (int i = pluginList.length - 1; i >= 0; --i) {
          var name = pluginList[i].name;
          if (names.contains(name)) {
            pluginList.removeAt(i);
          }
        }
      },
      errorMessage: 'Plugin: failed to persist batch rule removal',
    );
  }
}
