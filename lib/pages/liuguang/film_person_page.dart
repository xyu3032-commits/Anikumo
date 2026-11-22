import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:anikumo/bean/widget/anikumo_icons.dart';
import 'package:anikumo/pages/liuguang/film_widgets.dart';
import 'package:anikumo/services/i18n/app_strings.dart';
import 'package:anikumo/services/tmdb/tmdb_catalog.dart';

/// Batch 281: route arguments for '/film/person' — the
/// TMDB person id plus what the cast row already knows
/// (name / photo), so the header paints instantly while
/// the detail and credits load.
class FilmPersonArgs {
  const FilmPersonArgs({
    required this.id,
    required this.name,
    this.imageUrl,
  });

  final int id;
  final String name;
  final String? imageUrl;
}

/// Batch 281: 人物页 — a cast member's page: photo, name,
/// vitals and biography from the metadata service, then
/// the works they appear in. Works are metadata only, so
/// a tap searches the title across the film sources (the
/// same landing as the detail page's similar rail).
/// Without a key or on any failure the page degrades to
/// its empty state — enrichment never breaks navigation.
class FilmPersonPage extends StatefulWidget {
  const FilmPersonPage({super.key, required this.args});

  final FilmPersonArgs args;

  @override
  State<FilmPersonPage> createState() => _FilmPersonPageState();
}

class _FilmPersonPageState extends State<FilmPersonPage> {
  TmdbPersonInfo? _info;
  List<TmdbPersonCredit> _credits = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final results = await Future.wait<dynamic>([
      TmdbCatalogService.personDetail(widget.args.id),
      TmdbCatalogService.personCredits(widget.args.id),
    ]);
    if (!mounted) return;
    setState(() {
      _info = results[0] as TmdbPersonInfo?;
      _credits = results[1] as List<TmdbPersonCredit>;
      _loading = false;
    });
  }

  String get _name => _info?.name ?? widget.args.name;

  String get _photo {
    final fromDetail = _info?.profileUrl ?? '';
    return fromDetail.isNotEmpty ? fromDetail : (widget.args.imageUrl ?? '');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_name, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _info == null && _credits.isEmpty
              ? FilmEmptyState(
                  icon: AnikumoIcons.person_outline_rounded,
                  title: S.t('人物'),
                  message: S.t('没有查到这位人物的资料。'),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                  children: [
                    _header(context),
                    const SizedBox(height: 20),
                    _sectionTitle(context, S.t('简介')),
                    const SizedBox(height: 6),
                    Text(
                      (_info?.biography ?? '').isEmpty
                          ? S.t('暂无简介')
                          : _info!.biography,
                      style: const TextStyle(fontSize: 13.5, height: 1.55),
                    ),
                    if (_credits.isNotEmpty) ...[
                      const SizedBox(height: 22),
                      _sectionTitle(context, S.t('参演作品')),
                      const SizedBox(height: 10),
                      _creditsGrid(context),
                    ],
                  ],
                ),
    );
  }

  Widget _header(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final photo = _photo;
    final vitals = [
      if ((_info?.birthday ?? '').isNotEmpty)
        S.f('生日：{}', [_info!.birthday]),
      if ((_info?.placeOfBirth ?? '').isNotEmpty)
        S.f('出生地：{}', [_info!.placeOfBirth]),
    ];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: 92,
            height: 92,
            child: photo.isEmpty
                ? Container(
                    color: scheme.surfaceContainerHighest,
                    child: Icon(
                      AnikumoIcons.person_outline_rounded,
                      size: 40,
                      color: scheme.outline,
                    ),
                  )
                : CachedNetworkImage(
                    imageUrl: photo,
                    fit: BoxFit.cover,
                    cacheManager: filmCoverCacheManager,
                    errorWidget: (_, __, ___) => Container(
                      color: scheme.surfaceContainerHighest,
                    ),
                  ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _name,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              for (final line in vitals) ...[
                const SizedBox(height: 6),
                Text(
                  line,
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 13,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _sectionTitle(BuildContext context, String text) {
    return Text(
      text,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w700,
      ),
    );
  }

  Widget _creditsGrid(BuildContext context) {
    final theme = Theme.of(context);
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 12,
        mainAxisSpacing: 14,
        childAspectRatio: 0.52,
      ),
      itemCount: _credits.length,
      itemBuilder: (context, index) {
        final credit = _credits[index];
        final entry = credit.entry;
        return GestureDetector(
          onTap: () => context.pushNamed(
            '/film/search',
            arguments: entry.title,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: entry.posterUrl.isEmpty
                    ? Container(
                        width: double.infinity,
                        height: 150,
                        color: theme.colorScheme.surfaceContainerHigh,
                        child: Icon(
                          AnikumoIcons.movie_rounded,
                          color: theme.colorScheme.outline,
                        ),
                      )
                    : CachedNetworkImage(
                        imageUrl: entry.posterUrl,
                        width: double.infinity,
                        height: 150,
                        fit: BoxFit.cover,
                        cacheManager: filmCoverCacheManager,
                        errorWidget: (_, __, ___) => Container(
                          height: 150,
                          color: theme.colorScheme.surfaceContainerHigh,
                        ),
                      ),
              ),
              const SizedBox(height: 6),
              Text(
                entry.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              Text(
                [
                  if (entry.year.isNotEmpty) entry.year,
                  if (entry.score > 0) entry.score.toStringAsFixed(1),
                ].join(' · '),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
              if (credit.character.isNotEmpty)
                Text(
                  S.f('饰 {}', [credit.character]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
