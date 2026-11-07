import 'package:flutter_modular/flutter_modular.dart';
import 'package:anikumo/pages/plugin_editor/plugin_editor_page.dart';
import 'package:anikumo/pages/plugin_editor/plugin_test_page.dart';
import 'package:anikumo/pages/plugin_editor/plugin_view_page.dart';
import 'package:anikumo/pages/plugin_editor/rule_repository_page.dart';
import 'package:anikumo/pages/route_error_page.dart';
import 'package:anikumo/plugins/plugins.dart';
import 'package:anikumo/plugins/plugins_controller.dart';

final pluginModule = createModule(
  path: '/plugin',
  register: (c) {
    c
      ..route(
        '/',
        child: (context, state) => PluginViewPage(
          controller: inject<PluginsController>(),
        ),
      )
      ..route(
        '/repository',
        child: (context, state) => RuleRepositoryPage(
          controller: inject<PluginsController>(),
          initialAddress:
              state.arguments is String ? state.arguments as String : null,
        ),
      )
      ..route(
        '/test',
        child: (context, state) {
          final plugin = state.arguments;
          if (plugin is! Plugin) {
            return const RouteErrorPage(message: '规则测试参数无效，请返回后重试。');
          }
          return PluginTestPage(plugin: plugin);
        },
      )
      ..route(
        '/editor',
        child: (context, state) {
          final plugin = state.arguments;
          if (plugin is! Plugin) {
            return const RouteErrorPage(message: '规则编辑参数无效，请返回后重试。');
          }
          return PluginEditorPage(
            plugin: plugin,
            controller: inject<PluginsController>(),
          );
        },
      );
  },
);
