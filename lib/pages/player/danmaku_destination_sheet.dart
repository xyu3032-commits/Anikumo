import 'package:flutter/material.dart';

import 'package:anikumo/bean/dialog/adaptive_bottom_sheet.dart';
import 'package:anikumo/bean/dialog/material_bottom_sheet.dart';
import 'package:anikumo/bean/widget/split_list_row.dart';
import 'package:anikumo/bean/widget/anikumo_icons.dart';

enum DanmakuDestination {
  chatRoom,
  remoteDanmaku,
}

Future<DanmakuDestination?> showDanmakuDestinationSheet(BuildContext context) {
  return showAdaptiveBottomSheet<DanmakuDestination>(
    context: context,
    builder: (context) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        MaterialBottomSheetHeader(
          title: '发送到',
          onClose: () => Navigator.of(context).pop(),
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: materialBottomSheetContentPadding,
            child: SplitListGroup(
              children: [
                ListTile(
                  leading: const Icon(AnikumoIcons.groups_rounded),
                  title: const Text('一起看聊天室'),
                  subtitle: const Text('与同房间的朋友聊天'),
                  onTap: () =>
                      Navigator.of(context).pop(DanmakuDestination.chatRoom),
                ),
                ListTile(
                  leading: const Icon(AnikumoIcons.subtitles_outlined),
                  title: const Text('视频弹幕'),
                  subtitle: const Text('保存在本机，在这集播放时显示'),
                  onTap: () => Navigator.of(context)
                      .pop(DanmakuDestination.remoteDanmaku),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
