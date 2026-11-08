import 'package:flutter_test/flutter_test.dart';
import 'package:anikumo/modules/bangumi/bangumi_item.dart';
import 'package:anikumo/modules/bangumi/bangumi_tag.dart';
import 'package:anikumo/pages/video/video_playback_args.dart';
import 'package:anikumo/plugins/plugins.dart';
import 'package:anikumo/services/player/mini_player_session.dart';
import 'package:anikumo/services/storage/settings_keys.dart';

BangumiItem _item(int id) {
  return BangumiItem(
    id: id,
    type: 2,
    name: 'subject $id',
    nameCn: '条目 $id',
    summary: '',
    airDate: '2026-01-01',
    airWeekday: 4,
    rank: 0,
    images: const {
      'large': '',
      'common': '',
      'medium': '',
      'small': '',
      'grid': '',
    },
    tags: const <BangumiTag>[],
    alias: const [],
    ratingScore: 0,
    votes: 0,
    votesCount: const [],
    info: '',
  );
}

OnlineVideoPlaybackArgs _online(int id, String pluginName) {
  final plugin = Plugin.fromTemplate()..name = pluginName;
  return OnlineVideoPlaybackArgs(
    bangumiItem: _item(id),
    plugin: plugin,
    title: 't',
    src: '',
    roads: const [],
  );
}

OfflineVideoPlaybackArgs _offline(int id, String pluginName) {
  return OfflineVideoPlaybackArgs(
    bangumiItem: _item(id),
    pluginName: pluginName,
    episodeNumber: 1,
    road: 0,
    downloadedEpisodes: const [],
  );
}

void main() {
  group('batch113 zone classification', () {
    test('manga and novel routes are their own zones', () {
      expect(miniPlayerZoneForRoute('/manga/'), MiniPlayerZone.manga);
      expect(miniPlayerZoneForRoute('/manga/reader'), MiniPlayerZone.manga);
      expect(miniPlayerZoneForRoute('/novel/'), MiniPlayerZone.novel);
      expect(miniPlayerZoneForRoute('/novel/reader'), MiniPlayerZone.novel);
    });

    test('video route is the player zone; everything else is anime side', () {
      expect(miniPlayerZoneForRoute('/video/'), MiniPlayerZone.video);
      expect(miniPlayerZoneForRoute('/'), MiniPlayerZone.anime);
      expect(miniPlayerZoneForRoute('/info/123'), MiniPlayerZone.anime);
      expect(miniPlayerZoneForRoute('/settings/player'), MiniPlayerZone.anime);
      expect(miniPlayerZoneForRoute(null), MiniPlayerZone.anime);
      expect(miniPlayerZoneForRoute(''), MiniPlayerZone.anime);
    });
  });

  group('batch113 visibility matrix', () {
    test('no session never shows', () {
      expect(
        miniPlayerVisible(
          hasSession: false,
          zone: MiniPlayerZone.anime,
          hideInOtherZones: true,
        ),
        isFalse,
      );
    });

    test('never floats over the full player', () {
      expect(
        miniPlayerVisible(
          hasSession: true,
          zone: MiniPlayerZone.video,
          hideInOtherZones: false,
        ),
        isFalse,
      );
    });

    test('manga/novel hide only when the setting is on', () {
      for (final zone in [MiniPlayerZone.manga, MiniPlayerZone.novel]) {
        expect(
          miniPlayerVisible(
            hasSession: true,
            zone: zone,
            hideInOtherZones: true,
          ),
          isFalse,
        );
        expect(
          miniPlayerVisible(
            hasSession: true,
            zone: zone,
            hideInOtherZones: false,
          ),
          isTrue,
        );
      }
    });

    test('anime side always shows', () {
      expect(
        miniPlayerVisible(
          hasSession: true,
          zone: MiniPlayerZone.anime,
          hideInOtherZones: true,
        ),
        isTrue,
      );
    });
  });

  group('batch113 exit-to-mini decision', () {
    test('mobile + in-app mode + playable media parks in the mini window',
        () {
      expect(
        miniPlayerShouldExitToMini(
          isDesktopPlatform: false,
          inAppMode: true,
          hasPlayableMedia: true,
        ),
        isTrue,
      );
    });

    test('desktop, external mode, or no media fall through to normal exit',
        () {
      expect(
        miniPlayerShouldExitToMini(
          isDesktopPlatform: true,
          inAppMode: true,
          hasPlayableMedia: true,
        ),
        isFalse,
      );
      expect(
        miniPlayerShouldExitToMini(
          isDesktopPlatform: false,
          inAppMode: false,
          hasPlayableMedia: true,
        ),
        isFalse,
      );
      expect(
        miniPlayerShouldExitToMini(
          isDesktopPlatform: false,
          inAppMode: true,
          hasPlayableMedia: false,
        ),
        isFalse,
      );
    });
  });

  group('batch113 resume matching', () {
    test('same bangumi + same source matches', () {
      expect(miniPlayerArgsMatch(_online(7, 'srcA'), _online(7, 'srcA')),
          isTrue);
      expect(miniPlayerArgsMatch(_offline(7, 'srcA'), _offline(7, 'srcA')),
          isTrue);
    });

    test('different bangumi, source, or kind does not match', () {
      expect(miniPlayerArgsMatch(_online(7, 'srcA'), _online(8, 'srcA')),
          isFalse);
      expect(miniPlayerArgsMatch(_online(7, 'srcA'), _online(7, 'srcB')),
          isFalse);
      expect(miniPlayerArgsMatch(_online(7, 'srcA'), _offline(7, 'srcA')),
          isFalse);
    });
  });

  group('batch113 settings defaults', () {
    test('in-app mode and zone hiding default on, mute defaults off', () {
      expect(SettingsKeys.pipInAppMode.defaultValue, isTrue);
      expect(SettingsKeys.pipHideInOtherZones.defaultValue, isTrue);
      expect(SettingsKeys.pipMuteWhenHidden.defaultValue, isFalse);
    });
  });
}
