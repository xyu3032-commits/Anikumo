import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:anikumo/bean/card/network_img_layer.dart';
import 'package:anikumo/modules/bangumi/bangumi_item.dart';
import 'package:anikumo/repositories/collect_crud_repository.dart';
import 'package:anikumo/repositories/history_repository.dart';
import 'package:anikumo/services/library/user_library.dart';
import 'package:anikumo/utils/constants.dart';

/// Candidates the user plausibly wants to file away: everything in
/// their collections, plus everything in their watch history.
List<BangumiItem> loadBangumiCandidates() {
  final byId = <int, BangumiItem>{};
  for (final item
      in inject<ICollectCrudRepository>().getAllCollectibles()) {
    byId[item.bangumiItem.id] = item.bangumiItem;
  }
  for (final history in inject<IHistoryRepository>().getAllHistories()) {
    byId.putIfAbsent(history.bangumiItem.id, () => history.bangumiItem);
  }
  return byId.values.toList();
}

/// Bottom-sheet picker over [loadBangumiCandidates]; resolves to the
/// chosen bangumi, or null when dismissed.
Future<BangumiItem?> showBangumiPicker(
  BuildContext context, {
  String title = '选择番剧',
}) {
  return showModalBottomSheet<BangumiItem>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _BangumiPickerSheet(title: title),
  );
}

class _BangumiPickerSheet extends StatefulWidget {
  const _BangumiPickerSheet({required this.title});

  final String title;

  @override
  State<_BangumiPickerSheet> createState() => _BangumiPickerSheetState();
}

class _BangumiPickerSheetState extends State<_BangumiPickerSheet> {
  late final List<BangumiItem> _all = loadBangumiCandidates();
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final query = _query.trim().toLowerCase();
    final items = query.isEmpty
        ? _all
        : _all
            .where((item) =>
                item.name.toLowerCase().contains(query) ||
                item.nameCn.toLowerCase().contains(query))
            .toList();
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.72,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                StyleString.pagePadding,
                StyleString.safeSpace,
                StyleString.pagePadding,
                8,
              ),
              child: TextField(
                autofocus: true,
                decoration: InputDecoration(
                  hintText: widget.title,
                  prefixIcon: const Icon(Icons.search),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
            Expanded(
              child: items.isEmpty
                  ? const Center(child: Text('没有可选的番剧'))
                  : ListView.builder(
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final item = items[index];
                        return ListTile(
                          leading: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: NetworkImgLayer(
                              src: item.images['large'] ?? '',
                              width: 36,
                              height: 48,
                            ),
                          ),
                          title: Text(
                            bangumiDisplayTitle(item),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: item.ratingScore > 0
                              ? Text(
                                  '评分 ${item.ratingScore.toStringAsFixed(1)}',
                                )
                              : null,
                          onTap: () => Navigator.of(context).pop(item),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
