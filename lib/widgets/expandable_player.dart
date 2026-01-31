import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:ui';
import '../models/song.dart';
import '../services/exoplayer_service.dart';
import '../theme/app_theme.dart';
import '../widgets/hires_badge.dart';
import '../widgets/queue_sheet.dart';
import '../models/loop_mode.dart';

class ExpandablePlayer extends StatefulWidget {
  const ExpandablePlayer({super.key});

  @override
  State<ExpandablePlayer> createState() => ExpandablePlayerState();
}

class ExpandablePlayerState extends State<ExpandablePlayer> with TickerProviderStateMixin {
  late AnimationController _controller;
  
  bool get isExpanded => _controller.value > 0.5;
  
  void collapse() {
    _controller.reverse();
  }
  
  // Dimensions
  static const double _miniPlayerHeight = 66.0;
  static const double _albumArtSizeMini = 48.0;
  static const double _albumArtSizeFull = 290.0;
  
  double _dragStartY = 0.0;
  double _dragStartValue = 0.0;
  
  // Player Slider State
  bool _isDraggingSlider = false;
  double _dragSliderValue = 0.0;
  double _previousSliderValue = 0.0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
      value: 0.0, // Start minimized
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleDragStart(DragStartDetails details) {
    _dragStartY = details.globalPosition.dy;
    _dragStartValue = _controller.value;
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    final screenHeight = MediaQuery.of(context).size.height;
    final dragDistance = details.globalPosition.dy - _dragStartY;
    final valueDelta = dragDistance / (screenHeight - _miniPlayerHeight);
    
    _controller.value = (_dragStartValue - valueDelta).clamp(0.0, 1.0);
  }

  void _handleDragEnd(DragEndDetails details) {
    if (_controller.value > 0.5 || details.primaryVelocity! < -500) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  void _toggle() {
    if (_controller.value < 0.5) _controller.forward();
    else _controller.reverse();
  }
  
  String _formatDuration(Duration d) {
    if (d.inMilliseconds < 0) return "0:00";
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final bottomNavHeight = kBottomNavigationBarHeight + MediaQuery.of(context).padding.bottom;
    
    return ListenableBuilder(
      listenable: ExoPlayerService(),
      builder: (context, _) {
        final audio = ExoPlayerService();
        final song = audio.currentSong;

        return AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final value = _controller.value;
            // Height interpolation
            final currentHeight = lerpDouble(_miniPlayerHeight, screenHeight, value)!;
            
            // Bottom position (above nav bar when mini, at 0 when full)
            final bottomPos = lerpDouble(bottomNavHeight + 24, 0, value)!;
            
            // Margins for mini player look
            final horizontalMargin = lerpDouble(12, 0, value)!;
            final borderRadius = lerpDouble(16, 0, value)!;

            return Positioned(
              bottom: bottomPos,
              left: horizontalMargin,
              right: horizontalMargin,
              height: currentHeight,
              child: GestureDetector(
                // Only allow tap to open if we have a song
                onTap: (song != null && _controller.value < 0.5) ? _toggle : null, 
                // Only allow drag if we have a song
                onVerticalDragStart: song != null ? _handleDragStart : null,
                onVerticalDragUpdate: song != null ? _handleDragUpdate : null,
                onVerticalDragEnd: song != null ? _handleDragEnd : null,
                child: Material(
                  elevation: 10 * value + 2, // Native optimized shadow
                  shadowColor: Colors.black.withOpacity(0.2),
                  color: Color.lerp(Colors.white, AppTheme.background, value),
                  borderRadius: BorderRadius.circular(borderRadius),
                  clipBehavior: Clip.hardEdge, // Faster clipping
                  child: Stack(
                    children: [
                      // Mini Player Content (Always present, fades out)
                      Opacity(
                        opacity: (1 - value * 3).clamp(0.0, 1.0), // Fade out quickly
                        child: IgnorePointer(
                          ignoring: value > 0.5,
                          child: RepaintBoundary(
                            child: _buildMiniPlayerContent(audio, song),
                          ),
                        ),
                      ),

                      // Only show full player if song exists
                      if (song != null)
                        RepaintBoundary(
                          child: Opacity(
                            opacity: value,
                            child: IgnorePointer(
                              ignoring: value < 0.5,
                              child: OverflowBox(
                                alignment: Alignment.topCenter,
                                minHeight: screenHeight,
                                maxHeight: screenHeight,
                                child: _buildFullPlayerContent(context, audio, song, value),
                              ),
                            ),
                          ),
                        ),

                      // Animated Album Art (Connecting Mini and Full)
                      if (song != null)
                        _buildAnimatedAlbumArt(song, value),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildAnimatedAlbumArt(Song song, double value) {
    final screenWidth = MediaQuery.of(context).size.width;
    final fullLeft = (screenWidth - _albumArtSizeFull) / 2;
    
    final safeTop = MediaQuery.of(context).padding.top;
    final fullTop = safeTop + 60 + 20; 

    final currentLeft = lerpDouble(12, fullLeft, value)!;
    final currentTop = lerpDouble(9, fullTop, value)!;
    final currentSize = lerpDouble(_albumArtSizeMini, _albumArtSizeFull, value)!;

    return Positioned(
      left: currentLeft,
      top: currentTop,
      width: currentSize,
      height: currentSize,
      child: Material(
        elevation: lerpDouble(0, 8, value)!,
        color: AppTheme.background,
        borderRadius: BorderRadius.circular(lerpDouble(10, 20, value)!),
        clipBehavior: Clip.hardEdge,
        child: song.albumCover != null
            ? CachedNetworkImage(
                imageUrl: song.albumCover!,
                fit: BoxFit.cover,
                placeholder: (context, url) => Container(color: AppTheme.divider),
                errorWidget: (context, url, error) => Container(color: AppTheme.divider),
                memCacheWidth: 300,
              )
            : Container(color: AppTheme.divider),
      ),
    );
  }

  Widget _buildMiniPlayerContent(ExoPlayerService audio, Song? song) {
    if (song == null) {
      // Empty state
      return Stack(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.centerLeft,
            height: _miniPlayerHeight,
            child: Row(
              children: [
                // Gray/Empty Placeholder
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(4),
                  ),
                  // No icon requested
                ),
                const SizedBox(width: 12),
                
                // "Tidak ada yang diputar" text
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Tidak ada yang diputar', 
                          style: TextStyle(
                            fontWeight: FontWeight.w600, 
                            fontSize: 14,
                            color: AppTheme.textSecondary,
                          )
                      ),
                    ],
                  ),
                ),
                
                // Play button (inactive)
                IconButton(
                  icon: const Icon(Icons.play_arrow_rounded),
                  color: AppTheme.primary, // Orange
                  onPressed: () {}, // Do nothing
                ),
              ],
            ),
          ),
        ],
      );
    }

    return Stack(
      children: [
        Container(
          padding: const EdgeInsets.only(left: 72, right: 12), // Space for image
          alignment: Alignment.centerLeft,
          height: _miniPlayerHeight,
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                        ),
                      ],
                    ),
                    Text(song.artist, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: AppTheme.caption.copyWith(fontSize: 12)),
                  ],
                ),
              ),
              if (audio.isLoading)
                 const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary))
              else ...[
                IconButton(
                  icon: Icon(audio.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
                  color: AppTheme.primary,
                  onPressed: audio.togglePlayPause,
                ),
                IconButton(
                  icon: const Icon(Icons.skip_next_rounded),
                  color: AppTheme.textSecondary,
                  onPressed: audio.playNext,
                ),
              ]
            ],
          ),
        ),
        // Mini Player Progress Bar
        Positioned(
          bottom: 0,
          left: 0, // Full width
          right: 0,
          height: 2,
          child: StreamBuilder<Duration>(
            stream: audio.positionStream,
            builder: (context, snapshot) {
               final position = snapshot.data ?? Duration.zero;
               final duration = audio.duration;
               double progress = 0.0;
               if (duration.inMilliseconds > 0) {
                 progress = (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
               }
               return LinearProgressIndicator(
                 value: progress,
                 backgroundColor: Colors.transparent,
                 valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primary),
                 minHeight: 2,
               );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildFullPlayerContent(BuildContext context, ExoPlayerService audio, Song song, double value) {
    if (value < 0.1) return const SizedBox.shrink(); // Optimization
    
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 32),
                      onPressed: _toggle,
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
              ),
              
              SizedBox(height: 20 + _albumArtSizeFull + 32), // Spacer for Image
              
              // Song Info
              Center(
                child: SizedBox(
                  width: _albumArtSizeFull,
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
                            style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      Text(
                        song.title,
                        style: AppTheme.heading1.copyWith(fontSize: 22, fontWeight: FontWeight.bold),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        song.artist,
                        style: AppTheme.caption.copyWith(fontSize: 16, color: AppTheme.textSecondary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
              
              const SizedBox(height: 24),
              
              // Progress Slider
              _buildProgressSlider(audio),
              
              const SizedBox(height: 16),
              
              // Controls
              _buildControls(audio),
              
              const Spacer(),
              
              // Tab Bar
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                   _buildTab('Antrean', false),
                   _buildTab('Lirik', false),
                   _buildTab('About', false),
                ],
              ),
              
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
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

  Widget _buildProgressSlider(ExoPlayerService audio) {
    return StreamBuilder<Duration>(
      stream: audio.positionStream,
      builder: (context, snapshot) {
        final duration = audio.duration;
        
        if (duration.inMilliseconds <= 0) {
          return _buildSliderLayout(0.0, 0, 0, false, null);
        }
        
        final streamPosition = snapshot.data ?? Duration.zero;
        final currentPosition = _isDraggingSlider
            ? Duration(milliseconds: (_dragSliderValue * duration.inMilliseconds).round())
            : streamPosition;
        
        final targetSliderValue = _isDraggingSlider
            ? _dragSliderValue
            : (streamPosition.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
            
        final shouldAnimate = audio.isSongEnding && !_isDraggingSlider && _previousSliderValue > 0.1;
        
        if (!audio.isSongEnding) {
          _previousSliderValue = targetSliderValue;
        }

        return _buildSliderLayout(
          targetSliderValue, 
          currentPosition.inMilliseconds, 
          duration.inMilliseconds,
          shouldAnimate,
          (value) async {
             final newPosition = Duration(milliseconds: (value * duration.inMilliseconds).round());
             await audio.seek(newPosition);
             if (mounted) setState(() => _isDraggingSlider = false);
          }
        );
      },
    );
  }

  Widget _buildSliderLayout(double value, int currentMs, int durationMs, bool animate, Function(double)? onSeekEnd) {
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
            child: animate 
              ? TweenAnimationBuilder<double>(
                  key: ValueKey('anim_slider'),
                  tween: Tween(begin: _previousSliderValue, end: 0.0),
                  duration: const Duration(milliseconds: 500),
                  builder: (context, v, child) => Slider(value: v, onChanged: null),
                )
              : Slider(
                  value: value,
                  onChanged: (v) => setState(() {
                    _isDraggingSlider = true;
                    _dragSliderValue = v;
                  }),
                  onChangeEnd: onSeekEnd,
                ),
         ),
         Padding(
           padding: const EdgeInsets.symmetric(horizontal: 16),
           child: Row(
             mainAxisAlignment: MainAxisAlignment.spaceBetween,
             children: [
               Text(_formatDuration(Duration(milliseconds: currentMs)), style: AppTheme.caption.copyWith(fontSize: 12)),
               Text(_formatDuration(Duration(milliseconds: durationMs)), style: AppTheme.caption.copyWith(fontSize: 12)),
             ],
           ),
         ),
       ],
     );
  }

  Widget _buildControls(ExoPlayerService audio) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        IconButton(
          icon: Icon(Icons.shuffle_rounded, color: audio.isShuffleMode ? AppTheme.primary : AppTheme.textSecondary),
          onPressed: audio.toggleShuffle,
        ),
        IconButton(
          icon: const Icon(Icons.skip_previous_rounded, size: 36, color: AppTheme.textPrimary),
          onPressed: audio.playPrevious,
        ),
        Container(
          width: 72,
          height: 72,
          decoration: const BoxDecoration(
            color: AppTheme.primary,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Color(0x66FF6B35),
                blurRadius: 20,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: IconButton(
            icon: Icon(
              audio.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              color: Colors.white,
              size: 40,
            ),
            onPressed: audio.togglePlayPause,
          ),
        ),
        IconButton(
          icon: const Icon(Icons.skip_next_rounded, size: 36, color: AppTheme.textPrimary),
          onPressed: audio.playNext,
        ),
        IconButton(
          icon: Icon(
            audio.loopMode == LoopMode.one ? Icons.repeat_one_rounded : Icons.repeat_rounded,
            color: audio.loopMode == LoopMode.off ? AppTheme.textSecondary : AppTheme.primary,
          ),
          onPressed: audio.toggleLoop,
        ),
      ],
    );
  }
}
