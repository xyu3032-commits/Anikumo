import 'dart:async';

import 'package:flutter_modular/flutter_modular.dart';
import 'package:anikumo/pages/download/download_controller.dart';
import 'package:anikumo/pages/history/history_controller.dart';
import 'package:anikumo/pages/player/player_controller.dart';
import 'package:anikumo/pages/route_error_page.dart';
import 'package:anikumo/pages/video/video_controller.dart';
import 'package:anikumo/pages/video/video_page.dart';
import 'package:anikumo/pages/video/video_playback_args.dart';
import 'package:anikumo/services/player/mini_player_session.dart';

final videoModule = createModule(
  path: '/video',
  register: (c) {
    c.route(
      '/',
      provide: (s) => s
        ..add<VideoPageController>(VideoPageController.new)
        ..add<PlayerController>(PlayerController.new),
      child: (context, state) {
        final args = state.arguments;
        if (args is! VideoPlaybackArgs) {
          return const RouteErrorPage(message: '播放参数无效，请返回后重试。');
        }
        // Batch 113: the in-app mini player owns a live pair between
        // visits. Reopening the same video reattaches to that pair;
        // opening a different video ends the mini session for real
        // (the mini window never survives into another video).
        // Batch 116: "same video" now means same ANIME for online
        // playback — tapping the anime the mini window is playing
        // resumes it directly, whichever source the entry point
        // happened to build its args from.
        final session = MiniPlayerSession.instance;
        // Batch 127: an explicit episode pick never resumes
        // the mini session — the user chose a specific episode,
        // so the session ends and the pick starts fresh.
        final explicitPick =
            args is OnlineVideoPlaybackArgs && args.initialEpisode != null;
        final resumeArgs = explicitPick ? null : session.resumeArgsFor(args);
        final resume = resumeArgs != null;
        if (session.hasSession && !resume) {
          unawaited(session.close());
        }
        return VideoPage(
          args: resumeArgs ?? args,
          playerController: resume
              ? session.playerController!
              : context.read<PlayerController>(),
          videoPageController: resume
              ? session.videoPageController!
              : context.read<VideoPageController>(),
          historyController: inject<HistoryController>(),
          downloadController: inject<DownloadController>(),
          resumeFromMini: resume,
        );
      },
    );
  },
);
