import 'package:anikumo/utils/tap_debouncer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:anikumo/bean/card/network_img_layer.dart';
import 'package:anikumo/modules/bangumi/bangumi_item.dart';
import 'package:anikumo/utils/constants.dart';
import 'package:anikumo/bean/widget/anikumo_icons.dart';

/// Wide hero card for the top pick of the 精选 (featured) page.
///
/// Same tap target and hero tag as [BangumiCardV] (`/info/` with the
/// item's id), presented as a 16:9 banner: cover image, a bottom scrim
/// for text legibility, the title, and compact score / year / rank
/// chips. Colors come from the cover and fixed dark scrim only — the
/// app theme and seed color are untouched.
class BangumiFeatureCard extends StatelessWidget {
  const BangumiFeatureCard({
    super.key,
    required this.bangumiItem,
    this.badgeLabel = '本期精选',
  });

  final BangumiItem bangumiItem;
  final String badgeLabel;

  String get _title =>
      bangumiItem.nameCn.isNotEmpty ? bangumiItem.nameCn : bangumiItem.name;

  String get _year =>
      bangumiItem.airDate.length >= 4 ? bangumiItem.airDate.substring(0, 4) : '';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: StyleString.xlRadius),
      child: InkWell(
        onTap: () {
          if (TapDebouncer.accept('info:${bangumiItem.id}')) {
            context.pushNamed('/info/', arguments: bangumiItem);
          }
        },
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Hero(
                transitionOnUserGestures: true,
                flightShuttleBuilder:
                    NetworkImgLayer.heroFlightShuttleBuilder,
                tag: bangumiItem.id,
                child: LayoutBuilder(builder: (context, constraints) {
                  return NetworkImgLayer(
                    src: bangumiItem.images['large'] ?? '',
                    fallbackSrc: bangumiItem.images['common'],
                    width: constraints.maxWidth,
                    height: constraints.maxHeight,
                  );
                }),
              ),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: [0.45, 1.0],
                    colors: [Colors.transparent, Colors.black87],
                  ),
                ),
              ),
              Positioned(
                top: 12,
                left: 12,
                child: _Badge(label: badgeLabel),
              ),
              Positioned(
                left: 16,
                right: 16,
                bottom: 14,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        if (bangumiItem.ratingScore > 0)
                          _MetaChip(
                            icon: AnikumoIcons.star_rounded,
                            label: bangumiItem.ratingScore.toStringAsFixed(1),
                          ),
                        if (_year.isNotEmpty) _MetaChip(label: _year),
                        if (bangumiItem.rank > 0)
                          _MetaChip(label: 'Bangumi 排名 ${bangumiItem.rank}'),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.primary,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: scheme.onPrimary,
                fontWeight: FontWeight.w600,
              ),
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({this.icon, required this.label});

  final IconData? icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black45,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: Colors.amber),
              const SizedBox(width: 3),
            ],
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Colors.white,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
