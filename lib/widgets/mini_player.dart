import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/song.dart';
import '../services/exoplayer_service.dart';
import '../theme/app_theme.dart';
import '../screens/player_screen.dart';
import 'hires_badge.dart';

class MiniPlayer extends StatefulWidget {
  const MiniPlayer({super.key});

  @override
  State<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends State<MiniPlayer> with SingleTickerProviderStateMixin {
  late AnimationController _exitController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  bool _isTransitioning = false;

  @override
  void initState() {
    super.initState();
    _exitController = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );
    
    _fadeAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _exitController, curve: Curves.easeOut),
    );
    
    _slideAnimation = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(0.3, 0.0), // Slide to right
    ).animate(
      CurvedAnimation(parent: _exitController, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _exitController.dispose();
    super.dispose();
  }

  Future<void> _openPlayer(BuildContext context) async {
    if (_isTransitioning) return;
    setState(() => _isTransitioning = true);
    
    // Start exit animation for text/controls
    _exitController.forward();
    
    // Navigate immediately - Hero will handle the image flight
    // We use a transparent route so the MiniPlayer's text exiting is visible
    await Navigator.push(
      context,
      PageRouteBuilder(
        opaque: false,
        pageBuilder: (context, animation, secondaryAnimation) => const PlayerScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          // Just simple fade for the page background
          // The Hero widget will automatically fly on top of this
          return FadeTransition(
            opacity: animation,
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 500),
        reverseTransitionDuration: const Duration(milliseconds: 400),
      ),
    );
    
    // Reset animation when returning
    if (mounted) {
      _exitController.reset();
      setState(() => _isTransitioning = false);
    }
  }

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
                // Progress bar
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
                      
                      if (audio.isSongEnding && progress > 0.1) {
                        return TweenAnimationBuilder<double>(
                          key: ValueKey('mini_anim_${audio.currentSong?.id ?? 0}'),
                          tween: Tween(begin: progress, end: 1.0),
                          duration: Duration(milliseconds: (duration.inMilliseconds * (1.0 - progress)).clamp(100, 2000).toInt()),
                          curve: Curves.linear,
                          builder: (context, value, _) {
                            return LinearProgressIndicator(
                              value: value,
                              backgroundColor: AppTheme.divider,
                              valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primary),
                              minHeight: 3,
                            );
                          },
                        );
                      }
                      
                      return LinearProgressIndicator(
                        value: progress,
                        backgroundColor: AppTheme.divider,
                        valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primary),
                        minHeight: 3,
                      );
                    },
                  ),
                ),
                // Content
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      // Album art - stays in place (Hero handles animation)
                      Hero(
                        tag: 'album_art_${song.id}',
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: [
                              BoxShadow(
                                color: AppTheme.primary.withOpacity(0.2),
                                blurRadius: 8,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
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
                      ),
                      const SizedBox(width: 12),
                      // Song info - animated exit (slide right + fade)
                      Expanded(
                        child: SlideTransition(
                          position: _slideAnimation,
                          child: FadeTransition(
                            opacity: _fadeAnimation,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(
                                  children: [
                                    if (song.isLossless) ...[
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
                        ),
                      ),
                      // Controls - animated exit (slide right + fade)
                      SlideTransition(
                        position: _slideAnimation,
                        child: FadeTransition(
                          opacity: _fadeAnimation,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
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
                      ),
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
}
