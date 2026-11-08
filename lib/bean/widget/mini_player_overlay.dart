import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'package:anikumo/services/player/mini_player_session.dart';

/// Batch 113: the in-app picture-in-picture floating window. Lives
/// in the app-level overlay (above the navigator), so the video
/// keeps playing over the anime home and other pages after the
/// player page closes. Zone visibility (hidden in manga/novel,
/// never over the full player) is decided by [MiniPlayerSession].
class MiniPlayerHost extends StatefulWidget {
  const MiniPlayerHost({super.key});

  @override
  State<MiniPlayerHost> createState() => _MiniPlayerHostState();
}

class _MiniPlayerHostState extends State<MiniPlayerHost> {
  /// Absolute top-left of the window; null until first layout (then
  /// defaults to bottom-right, above the navigation bar).
  Offset? _offset;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: MiniPlayerSession.instance,
      builder: (context, _) {
        final session = MiniPlayerSession.instance;
        final playerController = session.playerController;
        if (!session.visible || playerController == null) {
          return const SizedBox.shrink();
        }
        final videoController = playerController.playback.videoController;
        if (videoController == null) {
          return const SizedBox.shrink();
        }
        return LayoutBuilder(
          builder: (context, constraints) {
            final maxWidth = constraints.maxWidth;
            final maxHeight = constraints.maxHeight;
            final width = (maxWidth * 0.44).clamp(180.0, 280.0);
            final height = width * 9 / 16;
            final topPadding = MediaQuery.of(context).padding.top;
            _offset ??= Offset(
              maxWidth - width - 12,
              maxHeight - height - 100,
            );
            final dx = _offset!.dx.clamp(8.0, maxWidth - width - 8);
            final dy =
                _offset!.dy.clamp(topPadding + 8, maxHeight - height - 8);
            return Stack(
              children: [
                Positioned(
                  left: dx,
                  top: dy,
                  width: width,
                  height: height,
                  child: _MiniPlayerWindow(
                    session: session,
                    onDrag: (delta) {
                      setState(() {
                        _offset = Offset(dx + delta.dx, dy + delta.dy);
                      });
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _MiniPlayerWindow extends StatelessWidget {
  const _MiniPlayerWindow({
    required this.session,
    required this.onDrag,
  });

  final MiniPlayerSession session;
  final ValueChanged<Offset> onDrag;

  @override
  Widget build(BuildContext context) {
    final playerController = session.playerController!;
    final videoPageController = session.videoPageController;
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: Colors.black,
      elevation: 8,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: GestureDetector(
        onPanUpdate: (details) => onDrag(details.delta),
        onTap: () {
          final args = session.args;
          if (args != null) {
            unawaited(context.pushNamed('/video/', arguments: args));
          }
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            Video(
              controller: playerController.playback.videoController!,
              controls: NoVideoControls,
              pauseUponEnteringBackgroundMode: false,
              fit: BoxFit.contain,
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(8, 14, 4, 2),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black54],
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        videoPageController?.title ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                        ),
                      ),
                    ),
                    Observer(builder: (context) {
                      final playing = playerController.playback.playing;
                      return IconButton(
                        visualDensity: VisualDensity.compact,
                        iconSize: 20,
                        color: Colors.white,
                        icon: Icon(
                          playing
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                        ),
                        onPressed: () {
                          unawaited(playerController.playOrPause());
                        },
                      );
                    }),
                  ],
                ),
              ),
            ),
            Positioned(
              top: 0,
              right: 0,
              child: IconButton(
                visualDensity: VisualDensity.compact,
                iconSize: 18,
                color: Colors.white,
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black45,
                ),
                icon: const Icon(Icons.close_rounded),
                onPressed: () {
                  unawaited(session.close());
                },
              ),
            ),
            Positioned(
              top: 6,
              left: 8,
              child: Icon(
                Icons.picture_in_picture_alt_rounded,
                size: 14,
                color: colors.primary.withValues(alpha: 0.9),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
