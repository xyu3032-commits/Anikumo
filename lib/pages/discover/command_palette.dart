import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:anikumo/services/hub/command_registry.dart';

/// 命令面板： type a few characters, jump straight to a feature.
/// Matching is pure (see command_registry); this widget is only the
/// sheet, the search field and the result list.
Future<void> showCommandPalette(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) {
      var query = '';
      return StatefulBuilder(
        builder: (context, setSheetState) {
          final results = matchCommands(query);
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.62,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: TextField(
                      autofocus: true,
                      decoration: const InputDecoration(
                        hintText: '输入功能名，如 备份 / 排行 / 弹幕',
                        prefixIcon: Icon(Icons.search_rounded),
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (value) =>
                          setSheetState(() => query = value),
                    ),
                  ),
                  Expanded(
                    child: results.isEmpty
                        ? const Center(child: Text('没有匹配的功能'))
                        : ListView.builder(
                            itemCount: results.length,
                            itemBuilder: (context, index) {
                              final command = results[index];
                              return ListTile(
                                leading: const Icon(
                                    Icons.arrow_forward_rounded),
                                title: Text(command.title),
                                onTap: () {
                                  Navigator.of(sheetContext).pop();
                                  context.pushNamed(command.route);
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}
