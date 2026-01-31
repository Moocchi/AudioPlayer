import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/song.dart';
import '../services/exoplayer_service.dart';
import '../theme/app_theme.dart';
import '../widgets/queue_sheet.dart';
import '../widgets/hires_badge.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> with TickerProviderStateMixin {
  bool _isDragging = false;
  double _dragValue = 0.0;
  double _previousSliderValue = 0.0;
  String? _lastSongId; // Track song changes
  
  static const double albumSize = 290;
  
  // Entrance animations
  late AnimationController _entranceController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.3, 1.0, curve: Curves.easeOut),
      ),
    );
    
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0.0, 0.3),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.2, 1.0, curve: Curves.easeOutCubic),
      ),
    );
    
    // Start animation after Hero completes
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) _entranceController.forward();
    });
  }

  @override
  void dispose() {
    _entranceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ExoPlayerService(),
      builder: (context, _) {
        final audio = ExoPlayerService();
        final song = audio.currentSong;

        if (song == null) {
          return const Scaffold(
            body: Center(child: Text('No song playing')),
          );
        }
        
        // Reset slider state when song changes
        if (_lastSongId != song.id) {
          _lastSongId = song.id;
          _previousSliderValue = 0.0;
          _isDragging = false;
          _dragValue = 0.0;
        }

        return Scaffold(
          backgroundColor: AppTheme.background,
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  // Header - animated
                  SlideTransition(
                    position: _slideAnimation,
                    child: FadeTransition(
                      opacity: _fadeAnimation,
                      child: _buildHeader(context, audio),
                    ),
                  ),
                  
                  const SizedBox(height: 20),
                  
                  // Album art - Hero handles animation
                  _buildAlbumArt(song, albumSize),
                  
                  const SizedBox(height: 32),
                  
                  // Song info - animated slide up + fade
                  SlideTransition(
                    position: _slideAnimation,
                    child: FadeTransition(
                      opacity: _fadeAnimation,
                      child: _buildSongInfo(song, albumSize),
                    ),
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // Progress slider - animated
                  SlideTransition(
                    position: _slideAnimation,
                    child: FadeTransition(
                      opacity: _fadeAnimation,
                      child: _buildProgressSlider(audio),
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Controls - animated
                  SlideTransition(
                    position: _slideAnimation,
                    child: FadeTransition(
                      opacity: _fadeAnimation,
                      child: _buildControls(audio),
                    ),
                  ),
                  
                  const Spacer(),
                  
                  // Tab bar - animated
                  SlideTransition(
                    position: _slideAnimation,
                    child: FadeTransition(
                      opacity: _fadeAnimation,
                      child: _buildTabBar(),
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTabBar() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _buildTab('Antrean', false),
        _buildTab('Lirik', false),
        _buildTab('About', false),
      ],
    );
  }

  Widget _buildTab(String label, bool enabled) {
    return Opacity(
      opacity: enabled ? 1.0 : 0.4,
      child: Text(
        label,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: AppTheme.textSecondary,
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, ExoPlayerService audio) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 32),
            onPressed: () => Navigator.pop(context),
          ),
          const Expanded(
            child: Center(
              child: Text(
                'NOW PLAYING',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textSecondary,
                  letterSpacing: 1,
                ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.queue_music_rounded),
            onPressed: () => QueueSheet.show(context),
          ),
        ],
      ),
    );
  }

  Widget _buildAlbumArt(Song song, double albumSize) {
    return Center(
      child: Hero(
        tag: 'album_art_${song.id}',
        child: Container(
          width: albumSize,
          height: albumSize,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primary.withOpacity(0.25),
                blurRadius: 30,
                offset: const Offset(0, 15),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: song.albumCover != null
                ? CachedNetworkImage(
                    imageUrl: song.albumCover!,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => Container(
                      color: AppTheme.divider,
                      child: const Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                    errorWidget: (context, url, error) => Container(
                      color: AppTheme.divider,
                      child: const Icon(
                        Icons.music_note_rounded,
                        size: 80,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  )
                : Container(
                    color: AppTheme.divider,
                    child: const Icon(
                      Icons.music_note_rounded,
                      size: 80,
                      color: AppTheme.textSecondary,
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildSongInfo(Song song, double albumSize) {
    return Center(
      child: SizedBox(
        width: albumSize,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (song.isHiRes) ...[
              const AnimatedHiResBadge(),
              const SizedBox(height: 12),
            ] else if (song.isLossless) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF1DB954),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'Lossless',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],

            Text(
              song.title,
              style: AppTheme.heading1.copyWith(
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),

            const SizedBox(height: 4),

            Text(
              song.artist,
              style: AppTheme.caption.copyWith(
                fontSize: 16,
                color: AppTheme.textSecondary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressSlider(ExoPlayerService audio) {
    return StreamBuilder<Duration>(
      stream: audio.positionStream,
      builder: (context, snapshot) {
        final duration = audio.duration;
        
        // Safety check for zero duration
        if (duration.inMilliseconds <= 0) {
          return Column(
            children: [
              SliderTheme(
                data: SliderThemeData(
                  trackHeight: 4,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                  activeTrackColor: AppTheme.primary,
                  inactiveTrackColor: AppTheme.divider,
                  thumbColor: AppTheme.primary,
                  overlayColor: AppTheme.primary.withOpacity(0.2),
                ),
                child: const Slider(
                  value: 0.0,
                  onChanged: null,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '0:00',
                      style: AppTheme.caption.copyWith(fontSize: 12),
                    ),
                    if (audio.isLoading)
                      Text(
                        audio.loadingStatus,
                        style: AppTheme.caption.copyWith(
                          color: AppTheme.primary,
                          fontSize: 12,
                        ),
                      )
                    else
                      const SizedBox.shrink(),
                    Text(
                      '0:00',
                      style: AppTheme.caption.copyWith(fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          );
        }
        
        // Get position from stream if not dragging, otherwise use drag value
        final streamPosition = snapshot.data ?? Duration.zero;
        final currentPosition = _isDragging
            ? Duration(
                milliseconds: (_dragValue * duration.inMilliseconds).round(),
              )
            : streamPosition;
        
        // Calculate slider value
        final targetSliderValue = _isDragging
            ? _dragValue
            : (streamPosition.inMilliseconds / duration.inMilliseconds)
                .clamp(0.0, 1.0);
        
        // Use isSongEnding flag from service for reliable animation trigger
        // Only animate if we have a meaningful previous position (> 0.1)
        final shouldAnimate = audio.isSongEnding && !_isDragging && _previousSliderValue > 0.1;
        
        // Store for animation begin value before updating
        final animBeginValue = _previousSliderValue;
        
        // Update previous value for next frame
        if (!audio.isSongEnding) {
          _previousSliderValue = targetSliderValue;
        }

        return Column(
          children: [
            // Slider - only animate on song end
            SliderTheme(
              data: SliderThemeData(
                trackHeight: 4,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                activeTrackColor: AppTheme.primary,
                inactiveTrackColor: AppTheme.divider,
                thumbColor: AppTheme.primary,
                overlayColor: AppTheme.primary.withOpacity(0.2),
              ),
              child: shouldAnimate
                  // Animated slider only for song end reset
                  ? TweenAnimationBuilder<double>(
                      key: ValueKey('song_end_anim_${audio.currentSong?.id ?? 0}'),
                      tween: Tween(begin: animBeginValue, end: 0.0),
                      duration: const Duration(milliseconds: 500),
                      curve: Curves.easeOutCubic,
                      builder: (context, animatedValue, child) {
                        return Slider(
                          value: animatedValue,
                          onChanged: null, // Disabled during animation
                        );
                      },
                    )
                  // Normal slider without animation
                  : Slider(
                      value: targetSliderValue,
                      onChanged: (value) {
                        setState(() {
                          _isDragging = true;
                          _dragValue = value;
                        });
                      },
                      onChangeEnd: (value) async {
                        final newPosition = Duration(
                          milliseconds: (value * duration.inMilliseconds).round(),
                        );
                        await audio.seek(newPosition);
                        
                        if (mounted) {
                          setState(() {
                            _isDragging = false;
                          });
                        }
                      },
                    ),
            ),
            // Time labels - update in real-time including during drag
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _formatDuration(currentPosition),
                    style: AppTheme.caption.copyWith(fontSize: 12),
                  ),
                  if (audio.isLoading)
                    Text(
                      audio.loadingStatus,
                      style: AppTheme.caption.copyWith(
                        color: AppTheme.primary,
                        fontSize: 12,
                      ),
                    )
                  else
                    const SizedBox.shrink(),
                  Text(
                    _formatDuration(duration),
                    style: AppTheme.caption.copyWith(fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildControls(ExoPlayerService audio) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        IconButton(
          icon: const Icon(Icons.shuffle_rounded),
          iconSize: 26,
          color: AppTheme.textSecondary,
          onPressed: () {},
        ),
        IconButton(
          icon: const Icon(Icons.skip_previous_rounded),
          iconSize: 36,
          color: AppTheme.textPrimary,
          onPressed: audio.playPrevious,
        ),
        // Play/Pause button
        GestureDetector(
          onTap: () {
            debugPrint('🔘 BUTTON TAPPED | isPlaying=${audio.isPlaying} | isLoading=${audio.isLoading}');
            if (audio.isLoading && !audio.isPlaying) {
              debugPrint('🚫 Button disabled (loading && !playing)');
              return;
            }
            audio.togglePlayPause();
          },
          child: Container(
            width: 64,
            height: 64,
            decoration: AppTheme.gradientButtonDecoration,
            child: audio.isLoading && !audio.isPlaying
                ? const Padding(
                    padding: EdgeInsets.all(18),
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 3,
                    ),
                  )
                : Icon(
                    audio.isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 36,
                  ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.skip_next_rounded),
          iconSize: 36,
          color: AppTheme.textPrimary,
          onPressed: audio.playNext,
        ),
        IconButton(
          icon: const Icon(Icons.repeat_rounded),
          iconSize: 26,
          color: AppTheme.textSecondary,
          onPressed: () {},
        ),
      ],
    );
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}
