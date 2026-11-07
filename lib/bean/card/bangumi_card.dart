
import 'package:anikumo/utils/tap_debouncer.dart';
import 'package:flutter/material.dart';
import 'package:anikumo/bean/widget/motion_kit.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:anikumo/bean/card/network_img_layer.dart';
import 'package:anikumo/bean/dialog/dialog_helper.dart';
import 'package:anikumo/modules/bangumi/bangumi_item.dart';
import 'package:anikumo/services/library/user_library.dart';
import 'package:anikumo/services/ui/card_style.dart';
import 'package:anikumo/services/ui/glass_style.dart';

// 视频卡片 - 垂直布局
//
// Renders in one of five visual styles (see [CardStyle]); the
// classic style is the original layout, the other four are batch-5
// alternatives applied app-wide from the same data and tap target.
class BangumiCardV extends StatelessWidget {
  const BangumiCardV({
    super.key,
    required this.bangumiItem,
    this.canTap = true,
    this.enableHero = true,
  });

  final BangumiItem bangumiItem;
  final bool canTap;
  final bool enableHero;

  void _handleTap(BuildContext context) {
    if (!canTap) {
      AnikumoDialog.showToast(
        message: '编辑模式',
      );
      return;
    }
    if (!TapDebouncer.accept('info:${bangumiItem.id}')) return;
    context.pushNamed('/info/', arguments: bangumiItem);
  }

  Widget _cover({required double width, required double height}) {
    final image = NetworkImgLayer(
      src: bangumiItem.images['large'] ?? '',
      fallbackSrc: bangumiItem.images['common'],
      width: width,
      height: height,
    );
    if (!enableHero) return image;
    return Hero(
      transitionOnUserGestures: true,
      flightShuttleBuilder: NetworkImgLayer.heroFlightShuttleBuilder,
      tag: bangumiItem.id,
      child: image,
    );
  }

  Widget _cardShell(BuildContext context, Widget child) {
    // Batch 21: press feedback on every anime card.
    return PressableScale(
      child: Card(
        elevation: 0,
        clipBehavior: Clip.antiAlias,
        margin: EdgeInsets.zero,
        child: InkWell(
          onTap: () => _handleTap(context),
          child: child,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Batch 16: isolate each card's repaint — grid scrolling
    // no longer repaints neighbouring cards' glass/gradient
    // layers.
    return RepaintBoundary(
      child: ValueListenableBuilder<int>(
        valueListenable: CardStyle.styleNotifier,
        builder: (context, style, _) {
          return switch (style) {
          CardStyle.wide => _buildWide(context),
          CardStyle.magazine => _buildMagazine(context),
          CardStyle.minimal => _buildMinimal(context),
          CardStyle.framed => _buildFramed(context),
            _ => _buildClassic(context),
          };
        },
      ),
    );
  }

  /// Style 0: the original layout, unchanged.
  Widget _buildClassic(BuildContext context) {
    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: GestureDetector(
        child: InkWell(
          onTap: () => _handleTap(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AspectRatio(
                aspectRatio: 0.65,
                child: LayoutBuilder(builder: (context, boxConstraints) {
                  final double maxWidth = boxConstraints.maxWidth;
                  final double maxHeight = boxConstraints.maxHeight;
                  return _cover(width: maxWidth, height: maxHeight);
                }),
              ),
              BangumiContent(bangumiItem: bangumiItem)
            ],
          ),
        ),
      ),
    );
  }

  /// Style 1 宽幅映画： full-bleed cover, glass title bar at the bottom.
  Widget _buildWide(BuildContext context) {
    final theme = Theme.of(context);
    return _cardShell(
      context,
      Stack(
        fit: StackFit.expand,
        children: [
          LayoutBuilder(
            builder: (context, constraints) =>
                _cover(width: constraints.maxWidth, height: constraints.maxHeight),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            // Batch 21: no per-card BackdropFilter. This card
            // style is the default and fills every grid/rail —
            // dozens of live backdrop blurs recomputed per
            // scroll frame were the "glass makes it lag"
            // report. The strip is now a static scrim: a
            // gradient into the same translucent surface fill
            // (still following the glass level), which reads
            // as frosted glass over cover art at zero filter
            // cost. Real blur stays on the few big surfaces
            // (navigation bar, hero cards, sheets).
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    theme.colorScheme.surface.withValues(alpha: 0),
                    theme.colorScheme.surface
                        .withValues(alpha: GlassStyle.fillOpacity()),
                  ],
                  stops: const [0, 0.45],
                ),
              ),
              padding: const EdgeInsets.fromLTRB(8, 16, 8, 7),
              child: Text(
                bangumiDisplayTitle(bangumiItem),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Style 2 杂志封面： full-bleed cover, score chip, bold title block.
  Widget _buildMagazine(BuildContext context) {
    return _cardShell(
      context,
      Stack(
        fit: StackFit.expand,
        children: [
          LayoutBuilder(
            builder: (context, constraints) =>
                _cover(width: constraints.maxWidth, height: constraints.maxHeight),
          ),
          if (bangumiItem.ratingScore > 0)
            Positioned(
              left: 8,
              top: 8,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  bangumiItem.ratingScore.toStringAsFixed(1),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              color: Colors.black.withValues(alpha: 0.55),
              padding: const EdgeInsets.fromLTRB(9, 8, 9, 8),
              child: Text(
                bangumiDisplayTitle(bangumiItem),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  height: 1.15,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Style 3 极简留白： small centered cover, centered title.
  Widget _buildMinimal(BuildContext context) {
    final theme = Theme.of(context);
    return _cardShell(
      context,
      LayoutBuilder(
        builder: (context, constraints) {
          final coverWidth = constraints.maxWidth * 0.6;
          return Column(
            children: [
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: SizedBox(
                  width: coverWidth,
                  child: AspectRatio(
                    aspectRatio: 0.65,
                    child: _cover(
                      width: coverWidth,
                      height: coverWidth / 0.65,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  bangumiDisplayTitle(bangumiItem),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w500),
                ),
              ),
              if (bangumiItem.ratingScore > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    '评分 ${bangumiItem.ratingScore.toStringAsFixed(1)}',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.outline),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  /// Style 4 相框典藏： the cover sits inside a visible frame.
  Widget _buildFramed(BuildContext context) {
    final theme = Theme.of(context);
    return _cardShell(
      context,
      Padding(
        padding: const EdgeInsets.all(7),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(
              color: theme.colorScheme.outlineVariant,
              width: 3,
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.all(4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: AspectRatio(
                  aspectRatio: 0.78,
                  child: LayoutBuilder(
                    builder: (context, constraints) => _cover(
                      width: constraints.maxWidth,
                      height: constraints.maxHeight,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                bangumiDisplayTitle(bangumiItem),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class BangumiContent extends StatelessWidget {
  const BangumiContent({super.key, required this.bangumiItem});

  final BangumiItem bangumiItem;

  @override
  Widget build(BuildContext context) {
    final ts = MediaQuery.textScalerOf(context);

    return Expanded(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(5, 3, 5, 1),
        child: LayoutBuilder(builder: (context, constraints) {
          final style = DefaultTextStyle.of(context).style.copyWith(
                fontWeight: FontWeight.w500,
                letterSpacing: 0.3,
              );
          final textScaler = ts.clamp(maxScaleFactor: 1.1);
          final painter = TextPainter(
            text: TextSpan(text: bangumiItem.nameCn, style: style),
            textDirection: Directionality.of(context),
            textScaler: textScaler,
          );
          final lines = (constraints.maxHeight / painter.preferredLineHeight)
              .floor()
              .clamp(1, 3);
          painter.dispose();
          return Text(
            bangumiItem.nameCn,
            textAlign: TextAlign.start,
            style: style,
            textScaler: textScaler,
            maxLines: lines,
            overflow: TextOverflow.ellipsis,
          );
        }),
      ),
    );
  }
}
