import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/song.dart';
import '../services/exoplayer_service.dart';
import '../theme/app_theme.dart';
import '../screens/player_screen.dart';
import 'hires_badge.dart';

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ExoPlayerService(),
      builder: (context, _) {
        final audio = ExoPlayerService();
        final song = audio.currentSong;
        
        if (song == null) return const SizedBox.shrink();

        return GestureDetector(
          onTap: () => _openPlayer(context),
          onVerticalDragEnd: (details) {
            if (details.primaryVelocity! < 0) {
              _openPlayer(context);
            }
          },
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 20,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Progress bar - no animation for normal updates
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                  child: StreamBuilder<Duration>(
                    stream: audio.positionStream,
                    builder: (context, snapshot) {
                      final position = snapshot.data ?? Duration.zero;
                      final duration = audio.duration;
                      final progress = duration.inMilliseconds > 0
                          ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0)
                          : 0.0;
                      
                      // Animate on song end only if we have meaningful progress
                      if (audio.isSongEnding && progress > 0.1) {
                        return TweenAnimationBuilder<double>(
                          key: ValueKey('mini_anim_${audio.currentSong?.id ?? 0}'),
                          tween: Tween(begin: progress, end: 0.0),
                          duration: const Duration(milliseconds: 500),
                          curve: Curves.easeOutCubic,
                          builder: (context, animatedValue, child) {
                            return LinearProgressIndicator(
                              value: animatedValue,
                              backgroundColor: AppTheme.divider,
                              valueColor: const AlwaysStoppedAnimation(AppTheme.primary),
                              minHeight: 3,
                            );
                          },
                        );
                      }
                      
                      return LinearProgressIndicator(
                        value: progress,
                        backgroundColor: AppTheme.divider,
                        valueColor: const AlwaysStoppedAnimation(AppTheme.primary),
                        minHeight: 3,
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      // Album art with caching
                      Hero(
                        tag: 'album_art_${song.id}',
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: song.albumCover != null
                              ? CachedNetworkImage(
                                  imageUrl: song.albumCover!,
                                  width: 48,
                                  height: 48,
                                  fit: BoxFit.cover,
                                  placeholder: (context, url) => Container(
                                    width: 48,
                                    height: 48,
                                    color: AppTheme.divider,
                                    child: const Icon(Icons.music_note, size: 24),
                                  ),
                                  errorWidget: (context, url, error) => Container(
                                    width: 48,
                                    height: 48,
                                    color: AppTheme.divider,
                                    child: const Icon(Icons.music_note),
                                  ),
                                )
                              : Container(
                                  width: 48,
                                  height: 48,
                                  color: AppTheme.divider,
                                  child: const Icon(Icons.music_note),
                                ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Song info
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                if (song.isHiRes) ...[
                                  const AnimatedHiResBadge(),
                                  const SizedBox(width: 4),
                                ] else if (song.isLossless) ...[
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF1DB954),
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                    child: const Text(
                                      'Lossless',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 8,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                ],
                                Expanded(
                                  child: Text(
                                    song.title,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            Text(
                              song.artist,
                              style: AppTheme.caption.copyWith(fontSize: 12),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      // Loading indicator or controls
                      if (audio.isLoading)
                        const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppTheme.primary,
                          ),
                        )
                      else ...[
                        IconButton(
                          icon: Icon(
                            audio.isPlaying 
                                ? Icons.pause_rounded 
                                : Icons.play_arrow_rounded,
                            color: AppTheme.primary,
                          ),
                          onPressed: audio.togglePlayPause,
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.skip_next_rounded,
                            color: AppTheme.textSecondary,
                          ),
                          onPressed: audio.playNext,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _openPlayer(BuildContext context) {
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => const PlayerScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          const begin = Offset(0.0, 1.0);
          const end = Offset.zero;
          const curve = Curves.easeOutCubic;
          var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
          return SlideTransition(
            position: animation.drive(tween),
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );
  }
}
