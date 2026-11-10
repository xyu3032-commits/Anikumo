import 'package:anikumo/modules/bangumi/episode_item.dart';

/// Batch 153: one episode of a subject as the picker shows
/// it — [sort] is Bangumi's own episode number, [number]
/// the picker's local 1-based number. The two differ when
/// a subject's sorts do not start at 1 (sequel subjects
/// whose numbering continues the series) or when the plan
/// is sliced to one season of a combined subject.
class PlannedEpisode {
  const PlannedEpisode({
    required this.sort,
    required this.number,
    required this.title,
    required this.airDate,
  });

  final int sort;
  final int number;
  final String title;
  final String airDate;
}

class EpisodePlan {
  const EpisodePlan({required this.episodes, required this.scoped});

  final List<PlannedEpisode> episodes;

  /// True when the picker's numbering differs from
  /// Bangumi's raw sorts (sliced to the stated season, or
  /// renumbered from a non-1 start). Watch history and
  /// remembered lines were recorded in sort space, so
  /// consumers must translate (watched fills) or hold off
  /// (the auto line) when this is set.
  final bool scoped;

  int get count => episodes.length;

  Map<int, int> get sortToNumber => {
        for (final e in episodes) e.sort: e.number,
      };
}

/// Builds the picker's episode plan from a subject's
/// Bangumi episode list.
///
/// Why this exists (the user's v41 test): the subject he
/// watches 药屋少女的呢喃 under is a COMBINED subject —
/// one Bangumi entry carrying all three seasons, 60
/// episodes — while its title says 第三季. The picker
/// showed all 60 in franchise numbering, so a tap on
/// 第52集 (a season-3 episode by that numbering) landed
/// on the source's season entry at the wrong position
/// (「点52集自动49集」). His standing call is that an
/// entry titled 第N季 shows only that season.
///
/// Seasons are located by air-date clusters: inside a
/// season episodes run about weekly, a new season starts
/// months later, so a gap over [seasonGapDays] between
/// consecutive dated episodes opens a new cluster.
/// Undated episodes stay with the previous dated one.
/// When the title states season N and at least two
/// clusters exist, only cluster N is kept; either way the
/// kept episodes are renumbered from 1 — the numbering
/// the season's own source entries use positionally.
/// When nothing can be sliced (single cluster, or a
/// stated season beyond the clusters found), the whole
/// list is kept; renumbering still normalises a non-1
/// sort start.
EpisodePlan planEpisodes({
  required List<EpisodeInfo> episodes,
  required int? statedSeason,
  int seasonGapDays = 56,
}) {
  final mains = [
    for (final e in episodes)
      if (e.type == 0) e,
  ]..sort((a, b) => a.episode.compareTo(b.episode));
  if (mains.isEmpty) {
    return const EpisodePlan(episodes: [], scoped: false);
  }

  final clusters = <List<EpisodeInfo>>[];
  DateTime? lastDate;
  for (final e in mains) {
    final date = DateTime.tryParse(e.airDate);
    if (clusters.isEmpty) {
      clusters.add([e]);
    } else if (date != null &&
        lastDate != null &&
        date.difference(lastDate).inDays > seasonGapDays) {
      clusters.add([e]);
    } else {
      clusters.last.add(e);
    }
    if (date != null) lastDate = date;
  }

  var chosen = mains;
  var sliced = false;
  if (statedSeason != null &&
      clusters.length > 1 &&
      statedSeason >= 1 &&
      statedSeason <= clusters.length) {
    chosen = clusters[statedSeason - 1];
    sliced = true;
  }

  final planned = <PlannedEpisode>[
    for (var i = 0; i < chosen.length; i++)
      PlannedEpisode(
        sort: chosen[i].episode.toInt(),
        number: i + 1,
        title: chosen[i].nameCn.isNotEmpty
            ? chosen[i].nameCn
            : chosen[i].name,
        airDate: chosen[i].airDate,
      ),
  ];
  final renumbered = planned.any((e) => e.sort != e.number);
  return EpisodePlan(episodes: planned, scoped: sliced || renumbered);
}
