import 'package:flutter_test/flutter_test.dart';
import 'package:anikumo/bean/widget/mini_player_overlay.dart';
import 'package:anikumo/modules/bangumi/bangumi_item.dart';
import 'package:anikumo/modules/bangumi/bangumi_tag.dart';
import 'package:anikumo/pages/video/video_playback_args.dart';
import 'package:anikumo/plugins/plugins.dart';
import 'package:anikumo/services/player/mini_player_session.dart';
import 'package:anikumo/services/player/pip_utils.dart';
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

/// Batch 116: picture-in-picture overhaul — settings conflict fix,
/// reliable hide over the player page, bigger/pinchable window,
/// seek controls, snap math.
void main() {
  group('effectiveAndroidAutoEnterPIP', () {
    test('in-app mode always forces the native flag off', () {
      expect(
        effectiveAndroidAutoEnterPIP(inAppMode: true, autoEnter: true),
        isFalse,
      );
      expect(
        effectiveAndroidAutoEnterPIP(inAppMode: true, autoEnter: false),
        isFalse,
      );
    });

    test('external mode honours the auto-enter switch', () {
      expect(
        effectiveAndroidAutoEnterPIP(inAppMode: false, autoEnter: true),
        isTrue,
      );
      expect(
        effectiveAndroidAutoEnterPIP(inAppMode: false, autoEnter: false),
        isFalse,
      );
    });
  });

  group('miniPlayerVisible with playerPageOpen', () {
    test('the page being open hides the window in any zone', () {
      expect(
        miniPlayerVisible(
          hasSession: true,
          zone: MiniPlayerZone.anime,
          hideInOtherZones: true,
          playerPageOpen: true,
        ),
        isFalse,
      );
    });

    test('page closed restores the zone rules', () {
      expect(
        miniPlayerVisible(
          hasSession: true,
          zone: MiniPlayerZone.anime,
          hideInOtherZones: true,
          playerPageOpen: false,
        ),
        isTrue,
      );
      expect(
        miniPlayerVisible(
          hasSession: true,
          zone: MiniPlayerZone.manga,
          hideInOtherZones: true,
          playerPageOpen: false,
        ),
        isFalse,
      );
    });
  });

  group('miniPlayerBaseWidth', () {
    test('68 percent of the screen, clamped (batch 121 size-up)', () {
      expect(miniPlayerBaseWidth(500), 340);
      expect(miniPlayerBaseWidth(360), 260); // 244.8 clamped up
      expect(miniPlayerBaseWidth(800), 420); // 544 clamped down
    });

    test('bigger than the batch 113 window on a phone', () {
      // Batch 113: 44% clamped to [180, 280] → 176 at 400px wide.
      expect(miniPlayerBaseWidth(400), greaterThan(200));
    });
  });

  group('seek math', () {
    test('fraction guards zero duration and clamps', () {
      expect(miniPlayerSeekFraction(Duration.zero, Duration.zero), 0);
      expect(
        miniPlayerSeekFraction(
            const Duration(seconds: 30), const Duration(seconds: 60)),
        0.5,
      );
      expect(
        miniPlayerSeekFraction(
            const Duration(seconds: 90), const Duration(seconds: 60)),
        1,
      );
    });

    test('target clamps into the media', () {
      expect(miniPlayerSeekTarget(0.5, const Duration(seconds: 100)),
          const Duration(seconds: 50));
      expect(miniPlayerSeekTarget(2, const Duration(seconds: 100)),
          const Duration(seconds: 100));
      expect(miniPlayerSeekTarget(0.5, Duration.zero), Duration.zero);
    });
  });

  group('miniPlayerSnapDx', () {
    test('snaps to the nearest side edge by centre', () {
      // screen 400, window 200: maxDx = 192
      expect(miniPlayerSnapDx(dx: 0, width: 200, screenWidth: 400), 8);
      expect(miniPlayerSnapDx(dx: 150, width: 200, screenWidth: 400), 192);
      expect(miniPlayerSnapDx(dx: 60, width: 200, screenWidth: 400), 8);
    });
  });

  group('settings', () {
    test('auto system PiP on leave is opt-in (default off)', () {
      expect(SettingsKeys.pipAutoSystemOnLeave.defaultValue, isFalse);
    });
  });

  group('miniPlayerResumeArgs (same-anime direct entry)', () {
    test('same anime from another source resumes the session args', () {
      final sessionArgs = _online(7, 'sourceA');
      final tapped = _online(7, 'sourceB');
      expect(miniPlayerResumeArgs(sessionArgs, tapped), same(sessionArgs));
    });

    test('a different anime does not resume', () {
      expect(miniPlayerResumeArgs(_online(7, 'a'), _online(8, 'a')), isNull);
    });

    test('offline entries keep the strict same-source match', () {
      final sessionArgs = _online(7, 'sourceA');
      expect(miniPlayerResumeArgs(sessionArgs, _offline(7, 'sourceA')),
          isNull);
      final offlineSession = _offline(7, 'sourceA');
      expect(miniPlayerResumeArgs(offlineSession, _offline(7, 'sourceA')),
          same(offlineSession));
      expect(miniPlayerResumeArgs(offlineSession, _offline(7, 'sourceB')),
          isNull);
    });
  });
}
