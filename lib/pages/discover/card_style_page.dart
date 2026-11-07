import 'package:flutter/material.dart';
import 'package:anikumo/bean/card/bangumi_card.dart';
import 'package:anikumo/modules/bangumi/bangumi_item.dart';
import 'package:anikumo/pages/discover/bangumi_picker.dart';
import 'package:anikumo/services/ui/card_style.dart';
import 'package:anikumo/utils/constants.dart';

/// 卡片样式： five looks for the bangumi card used across the whole
/// app. The preview uses the first title from the library/history
/// when one exists; switching applies everywhere immediately.
class CardStylePage extends StatefulWidget {
  const CardStylePage({super.key});

  @override
  State<CardStylePage> createState() => _CardStylePageState();
}

class _CardStylePageState extends State<CardStylePage> {
  BangumiItem? _sample;

  @override
  void initState() {
    super.initState();
    final candidates = loadBangumiCandidates();
    if (candidates.isNotEmpty) {
      _sample = candidates.first;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('卡片样式')),
      body: ValueListenableBuilder<int>(
        valueListenable: CardStyle.styleNotifier,
        builder: (context, current, _) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(
              StyleString.pagePadding,
              12,
              StyleString.pagePadding,
              StyleString.sectionSpace,
            ),
            children: [
              if (_sample != null) ...[
                Center(
                  // The card's layouts flex against a BOUNDED
                  // height (Expanded cover) — inside a ListView
                  // a width-only box leaves height unbounded
                  // and the card throws during layout, which
                  // blanked this whole page in release builds
                  // (batch 32). Pin the grid's aspect instead.
                  child: SizedBox(
                    width: 160,
                    // Same extent formula the browse grids
                    // give the card (width / 0.65 + a scaled
                    // 32 for its text block).
                    height: 160 / 0.65 +
                        MediaQuery.textScalerOf(context).scale(32),
                    child: BangumiCardV(
                      bangumiItem: _sample!,
                      canTap: false,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  '预览（样式会应用到全 App 的番剧卡片）',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
              ],
              RadioGroup<int>(
                groupValue: current,
                onChanged: (value) {
                  if (value != null) {
                    CardStyle.setStyle(value);
                  }
                },
                child: Column(
                  children: [
                    for (var i = 0; i < CardStyle.options.length; i++)
                      RadioListTile<int>(
                        value: i,
                        title: Text(CardStyle.options[i].name),
                        subtitle: Text(CardStyle.options[i].description),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
