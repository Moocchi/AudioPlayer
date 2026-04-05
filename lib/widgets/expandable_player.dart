import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'dart:ui';
import 'package:palette_generator/palette_generator.dart';
import '../models/song.dart';
import '../services/exoplayer_service.dart';
import '../theme/app_theme.dart';
import '../widgets/hires_badge.dart';

import '../services/liked_songs_service.dart';
import '../models/loop_mode.dart';
import '../widgets/player_menu_sheet.dart';
import '../widgets/player/player_queue_view.dart';
import '../widgets/player/player_lyrics_view.dart';
import '../widgets/player/player_about_view.dart';

class ExpandablePlayer extends StatefulWidget {
  const ExpandablePlayer({super.key});

  @override
  State<ExpandablePlayer> createState() => ExpandablePlayerState();
}

class ExpandablePlayerState extends State<ExpandablePlayer>
    with TickerProviderStateMixin {
  late AnimationController _controller;
  late CurvedAnimation _curvedAnimation;
  final ValueNotifier<double> _animationValue = ValueNotifier(0.0);

  bool get isExpanded => _controller.value > 0.5;
  bool get isSheetOpen => _sheetController.value > 0.5;

  // Public getter for animation value (for bottom nav animation)
  Animation<double> get animation => _curvedAnimation;
  ValueNotifier<double> get animationNotifier => _animationValue;

  void collapse() {
    _controller.reverse();
  }

  void expand() {
    _controller.forward();
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

  // Dynamic Shadow Color State
  Color _shadowColor = AppTheme.primary;
  String? _lastAnalyzedSongId;

  // Sheet Animation (tabs + content sliding up)
  // Sheet Animation (tabs + content sliding up)
  late AnimationController _sheetController;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _curvedAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic, // Fast start (Opening)
      reverseCurve: Curves.easeOutCubic, // Fast start (Closing)
    );

    // Update notifier on animation changes
    _curvedAnimation.addListener(() {
      _animationValue.value = _curvedAnimation.value;
    });

    _sheetController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _animationValue.dispose();
    _curvedAnimation.dispose();
    _controller.dispose();
    _sheetController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  void openSheet() {
    _sheetController.animateTo(
      1.0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  void closeSheet() {
    _sheetController.animateTo(
      0.0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
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
    final velocity = details.primaryVelocity ?? 0;
    
    // If swiping down fast enough, close it.
    if (velocity > 300) {
      _controller.reverse();
      return;
    }
    
    // If swiping up fast enough, open it.
    if (velocity < -300) {
      _controller.forward();
      return;
    }
    
    // Otherwise, close it if pulled down by more than 20% (value < 0.8)
    if (_controller.value > 0.8) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  void _toggle() {
    if (_controller.value < 0.5)
      _controller.forward();
    else
      _controller.reverse();
  }

  void _updateShadowColor(Song song) async {
    if (song.id == _lastAnalyzedSongId) return;
    final targetId = song.id;
    _lastAnalyzedSongId = targetId;

    if (song.albumCover == null) {
      if (mounted) setState(() => _shadowColor = AppTheme.primary);
      return;
    }

    try {
      final provider = CachedNetworkImageProvider(song.albumCover!);
      final palette = await PaletteGenerator.fromImageProvider(provider);
      if (mounted && targetId == _lastAnalyzedSongId) {
        setState(() {
          _shadowColor = palette.dominantColor?.color ?? 
                         palette.lightVibrantColor?.color ?? 
                         AppTheme.primary;
        });
      }
    } catch (e) {
      // ignore
    }
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
    final bottomNavHeight =
        kBottomNavigationBarHeight + MediaQuery.of(context).padding.bottom;

    return ListenableBuilder(
      listenable: ExoPlayerService(),
      builder: (context, _) {
        final audio = ExoPlayerService();
        final song = audio.currentSong;
        if (song != null) {
          _updateShadowColor(song);
        }

        return AnimatedBuilder(
          animation: _curvedAnimation,
          builder: (context, child) {
            final value = _curvedAnimation.value;
            // Height interpolation
            final currentHeight = lerpDouble(
              _miniPlayerHeight,
              screenHeight,
              value,
            )!;

            // Bottom position (above nav bar when mini, at 0 when full)
            final bottomPos = lerpDouble(bottomNavHeight + 24, 0, value)!;

            // Margins for mini player look
            final horizontalMargin = lerpDouble(12, 0, value)!;
            final borderRadius = lerpDouble(12, 0, value)!;

            return Positioned(
              bottom: bottomPos,
              left: horizontalMargin,
              right: horizontalMargin,
              height: currentHeight,
              child: GestureDetector(
                // Only allow tap to open if we have a song
                onTap: (song != null && _controller.value < 0.5)
                    ? _toggle
                    : null,
                // Only allow drag if we have a song
                onVerticalDragStart: song != null ? _handleDragStart : null,
                onVerticalDragUpdate: song != null ? _handleDragUpdate : null,
                onVerticalDragEnd: song != null ? _handleDragEnd : null,
                child: Material(
                  elevation: 0, // No shadow for performance
                  color: Color.lerp(Colors.white, AppTheme.background, value),
                  borderRadius: BorderRadius.circular(borderRadius),
                  clipBehavior: Clip.antiAlias, // Smoother clipping
                  child: Stack(
                    children: [
                      // Mini Player Content (Always present, fades out)
                      Opacity(
                        opacity: ((1 - value * 3).clamp(
                          0.0,
                          1.0,
                        )).toDouble(), // Fade out quickly
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
                          child: IgnorePointer(
                            ignoring: value < 0.5,
                            child: OverflowBox(
                              alignment: Alignment.topCenter,
                              minHeight: screenHeight,
                              maxHeight: screenHeight,
                              child: _buildFullPlayerContent(
                                context,
                                audio,
                                song,
                                value,
                              ),
                            ),
                          ),
                        ),

                      // Animated Album Art (Connecting Mini and Full) - hidden when sheet opens
                      if (song != null)
                        AnimatedBuilder(
                          animation: _sheetController,
                          builder: (context, child) {
                            // Hide original art when sheet starts opening (Layer 4 takes over)
                            if (_sheetController.value > 0)
                              return const SizedBox.shrink();
                            return _buildAnimatedAlbumArt(song, value);
                          },
                        ),
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
    final currentSize = lerpDouble(
      _albumArtSizeMini,
      _albumArtSizeFull,
      value,
    )!;

    return Positioned(
      left: currentLeft,
      top: currentTop,
      width: currentSize,
      height: currentSize,
      child: TweenAnimationBuilder<Color?>(
        tween: ColorTween(begin: _shadowColor, end: _shadowColor),
        duration: const Duration(milliseconds: 600),
        builder: (context, color, child) {
          final currentColor = color ?? AppTheme.primary;
          return Container(
            decoration: BoxDecoration(
              color: AppTheme.background,
              borderRadius: BorderRadius.circular(lerpDouble(8, 16, value)!),
              boxShadow: [
                BoxShadow(
                  color: currentColor.withOpacity(
                    lerpDouble(0.0, 0.45, value)!.clamp(0.0, 1.0),
                  ),
                  blurRadius: lerpDouble(0, 24, value)!,
                  offset: Offset(0, lerpDouble(0, 12, value)!),
                  spreadRadius: lerpDouble(0, 4, value)!,
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: song.albumCover != null
                ? CachedNetworkImage(
                    imageUrl: song.albumCover!,
                    fit: BoxFit.cover,
                    placeholder: (context, url) =>
                        Container(color: AppTheme.divider),
                    errorWidget: (context, url, error) =>
                        Container(color: AppTheme.divider),
                    memCacheWidth: 300,
                  )
                : Container(color: AppTheme.divider),
          );
        },
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
                      Text(
                        'Tidak ada yang diputar',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: AppTheme.textSecondary,
                        ),
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
          padding: const EdgeInsets.only(
            left: 72,
            right: 12,
          ), // Space for image
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
                          child: Text(
                            song.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                    Text(
                      song.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.caption.copyWith(fontSize: 12),
                    ),
                  ],
                ),
              ),
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
                  ),
                  color: AppTheme.primary,
                  onPressed: audio.togglePlayPause,
                ),
                IconButton(
                  icon: const Icon(Icons.skip_next_rounded),
                  color: AppTheme.textSecondary,
                  onPressed: audio.playNext,
                ),
              ],
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
            initialData: audio.position,
            builder: (context, snapshot) {
              final position = snapshot.data ?? Duration.zero;
              final duration = audio.duration;
              double progress = 0.0;
              if (duration.inMilliseconds > 0) {
                progress = (position.inMilliseconds / duration.inMilliseconds)
                    .clamp(0.0, 1.0);
              }
              return LinearProgressIndicator(
                value: progress,
                backgroundColor: Colors.transparent,
                valueColor: const AlwaysStoppedAnimation<Color>(
                  AppTheme.primary,
                ),
                minHeight: 2,
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildFullPlayerContent(
    BuildContext context,
    ExoPlayerService audio,
    Song song,
    double value,
  ) {
    if (value < 0.1) return const SizedBox.shrink();

    final double screenWidth = MediaQuery.of(context).size.width;
    final double paddedWidth = screenWidth - 32;

    final double mainArtSize = _albumArtSizeFull;
    const double mainArtTop = 80.0;
    final double mainArtLeft = (paddedWidth - mainArtSize) / 2;

    const double sheetArtSize = _albumArtSizeMini; // 48.0
    const double sheetArtTop = 9.0;
    const double sheetArtLeft = 12.0;

    const double headerHeight = _miniPlayerHeight; // 66.0
    const double tabsBarHeight = 66.0; // 50 tabs + 16 padding

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Opacity(
            opacity: ((value - 0.3) / 0.7).clamp(0.0, 1.0),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final double totalHeight = constraints.maxHeight;

                return Stack(
                  clipBehavior: Clip.hardEdge,
                  children: [
                    // Layer 1: Player Controls (Fade Out in place — NO tabs)
                    AnimatedBuilder(
                      animation: _sheetController,
                      builder: (context, child) {
                        final opacity = (1.0 - _sheetController.value * 2)
                            .clamp(0.0, 1.0);
                        return IgnorePointer(
                          ignoring: _sheetController.value > 0.5,
                          child: Opacity(opacity: opacity, child: child),
                        );
                      },
                      child: _buildControlsOnly(context, audio, song),
                    ),

                    // Layer 2: Sheet Header (Fade In, FIXED at top)
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      height: headerHeight,
                      child: AnimatedBuilder(
                        animation: _sheetController,
                        builder: (context, child) {
                          final opacity = (_sheetController.value * 2 - 0.5)
                              .clamp(0.0, 1.0);
                          return IgnorePointer(
                            ignoring: _sheetController.value < 0.5,
                            child: Opacity(opacity: opacity, child: child),
                          );
                        },
                        child: _buildSheetHeader(context, audio, song),
                      ),
                    ),

                    // Layer 3: Tabs + Content — slides from bottom to below header
                    AnimatedBuilder(
                      animation: _sheetController,
                      builder: (context, child) {
                        final double t = _sheetController.value;
                        final double currentTop = lerpDouble(
                          totalHeight - tabsBarHeight,
                          headerHeight,
                          t,
                        )!;
                        
                        // Only show indicator when sheet is opening/open
                        final double indicatorOpacity = (t > 0.1) ? 1.0 : 0.0;
                        
                        return Positioned(
                          top: currentTop,
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: GestureDetector(
                            onVerticalDragUpdate: (details) {
                              if (_sheetController.isAnimating) return;
                              final delta =
                                  details.primaryDelta! /
                                  MediaQuery.of(context).size.height;
                              _sheetController.value -= delta * 2;
                            },
                            onVerticalDragEnd: (details) {
                              if (_sheetController.isAnimating) return;
                              final velocity = details.primaryVelocity ?? 0;
                              if (velocity > 300) {
                                closeSheet();
                                return;
                              }
                              if (velocity < -300) {
                                openSheet();
                                return;
                              }
                              if (_sheetController.value > 0.8) {
                                openSheet();
                              } else {
                                closeSheet();
                              }
                            },
                            child: Container(
                              color: AppTheme.background,
                              child: Column(
                                children: [
                                  // Tab bar
                                  Container(
                                    height: 50,
                                    child: TabBar(
                                      controller: _tabController,
                                      dividerColor: Colors.transparent,
                                      labelColor: AppTheme.textPrimary,
                                      unselectedLabelColor: AppTheme.textSecondary,
                                      indicatorColor: AppTheme.primary.withOpacity(indicatorOpacity),
                                      indicatorSize: TabBarIndicatorSize.label,
                                      indicator: indicatorOpacity > 0 ? UnderlineTabIndicator(
                                        borderSide: const BorderSide(
                                          width: 3,
                                          color: AppTheme.primary,
                                        ),
                                        borderRadius: BorderRadius.circular(1.5),
                                      ) : const BoxDecoration(), // Hide indicator when closed
                                      labelStyle: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      onTap: (index) {
                                        // Tap to open if closed
                                        if (_sheetController.value < 0.1) {
                                          openSheet();
                                        }
                                      },
                                      tabs: const [
                                        Tab(text: 'Antrean'),
                                        Tab(text: 'Lirik'),
                                        Tab(text: 'About'),
                                      ],
                                    ),
                                  ),
                                  // Content fills remaining space below tabs
                                  Expanded(
                                    child: Opacity(
                                      opacity: t.clamp(0.0, 1.0), // Fade content in as sheet opens
                                      child: TabBarView(
                                        controller: _tabController,
                                        children: const [
                                          PlayerQueueView(),
                                          PlayerLyricsView(),
                                          PlayerAboutView(),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),

                    // Layer 4: Animated Album Art (visual only, no touch)
                    AnimatedBuilder(
                      animation: _sheetController,
                      builder: (context, child) {
                        if (_sheetController.value <= 0)
                          return const SizedBox.shrink();
                        final double t = _sheetController.value;

                        final double currentRadius = lerpDouble(16, 8, t)!;

                        return Positioned(
                          top: lerpDouble(mainArtTop, sheetArtTop, t),
                          left: lerpDouble(mainArtLeft, sheetArtLeft, t),
                          width: lerpDouble(mainArtSize, sheetArtSize, t),
                          height: lerpDouble(mainArtSize, sheetArtSize, t),
                          child: IgnorePointer(
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(
                                  currentRadius,
                                ),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: CachedNetworkImage(
                                imageUrl: song.albumCover ?? '',
                                fit: BoxFit.cover,
                                fadeInDuration: Duration.zero,
                                fadeOutDuration: Duration.zero,
                                placeholder: (context, url) =>
                                    Container(color: AppTheme.divider),
                                errorWidget: (_, __, ___) => Container(
                                  color: Colors.grey[850],
                                  child: const Icon(
                                    Icons.music_note,
                                    color: Colors.white,
                                    size: 64,
                                  ),
                                ),
                                memCacheWidth: 300,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  /// Player controls without tabs — fades out when sheet opens
  Widget _buildControlsOnly(
    BuildContext context,
    ExoPlayerService audio,
    Song song,
  ) {
    return Column(
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
                icon: const Icon(Icons.more_vert_rounded),
                onPressed: () => PlayerMenuSheet.show(context, song),
              ),
            ],
          ),
        ),

        SizedBox(height: 20 + _albumArtSizeFull + 32), // Spacer for art
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
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
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
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
                    ListenableBuilder(
                      listenable: LikedSongsService(),
                      builder: (context, _) {
                        final isLiked = LikedSongsService().isLiked(song.id);
                        return IconButton(
                          icon: Icon(
                            isLiked ? Icons.favorite : Icons.favorite_border,
                            color: isLiked
                                ? AppTheme.primary
                                : AppTheme.textSecondary,
                            size: 28,
                          ),
                          onPressed: () {
                            final wasLiked = LikedSongsService().isLiked(
                              song.id,
                            );
                            LikedSongsService().toggleLike(song);
                            if (!wasLiked) {
                              Fluttertoast.showToast(
                                msg:
                                    '"${song.title}" ditambahkan ke Liked Songs',
                                toastLength: Toast.LENGTH_SHORT,
                                gravity: ToastGravity.BOTTOM,
                                backgroundColor: Colors.black54,
                                textColor: Colors.white,
                              );
                            }
                          },
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 24),
        _buildProgressSlider(audio),
        const SizedBox(height: 16),
        _buildControls(audio),
        const Spacer(),
      ],
    );
  }

  /// Mini header that fades in when sheet is open
  Widget _buildSheetHeader(
    BuildContext context,
    ExoPlayerService audio,
    Song song,
  ) {
    return Material(
      color: AppTheme.background,
      child: GestureDetector(
        onTap: () {
          if (_sheetController.value > 0.5) closeSheet();
        },
        child: Stack(
          children: [
            Container(
              padding: const EdgeInsets.only(left: 72, right: 12),
              alignment: Alignment.centerLeft,
              height: _miniPlayerHeight,
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          song.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          song.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.caption.copyWith(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      audio.isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                    ),
                    color: AppTheme.primary,
                    onPressed: audio.togglePlayPause,
                  ),
                  IconButton(
                    icon: const Icon(Icons.skip_next_rounded),
                    color: AppTheme.textSecondary,
                    onPressed: audio.playNext,
                  ),
                ],
              ),
            ),
            // Mini Player Progress Bar
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              height: 2,
              child: StreamBuilder<Duration>(
                stream: audio.positionStream,
                initialData: audio.position,
                builder: (context, snapshot) {
                  final position = snapshot.data ?? Duration.zero;
                  final duration = audio.duration;
                  double progress = 0.0;
                  if (duration.inMilliseconds > 0) {
                    progress = (position.inMilliseconds / duration.inMilliseconds)
                        .clamp(0.0, 1.0);
                  }
                  return LinearProgressIndicator(
                    value: progress,
                    backgroundColor: Colors.transparent,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      AppTheme.primary,
                    ),
                    minHeight: 2,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressSlider(ExoPlayerService audio) {
    return StreamBuilder<Duration>(
      stream: audio.positionStream,
      initialData: audio.position,
      builder: (context, snapshot) {
        final duration = audio.duration;

        if (duration.inMilliseconds <= 0) {
          return _buildSliderLayout(0.0, 0, 0, false, null);
        }

        final streamPosition = snapshot.data ?? Duration.zero;
        final currentPosition = _isDraggingSlider
            ? Duration(
                milliseconds: (_dragSliderValue * duration.inMilliseconds)
                    .round(),
              )
            : streamPosition;

        final targetSliderValue = _isDraggingSlider
            ? _dragSliderValue
            : (streamPosition.inMilliseconds / duration.inMilliseconds).clamp(
                0.0,
                1.0,
              );

        final shouldAnimate =
            audio.isSongEnding &&
            !_isDraggingSlider &&
            _previousSliderValue > 0.1;

        if (!audio.isSongEnding) {
          _previousSliderValue = targetSliderValue;
        }

        return _buildSliderLayout(
          targetSliderValue,
          currentPosition.inMilliseconds,
          duration.inMilliseconds,
          shouldAnimate,
          (value) async {
            final newPosition = Duration(
              milliseconds: (value * duration.inMilliseconds).round(),
            );
            await audio.seek(newPosition);
            if (mounted) setState(() => _isDraggingSlider = false);
          },
        );
      },
    );
  }

  Widget _buildSliderLayout(
    double value,
    int currentMs,
    int durationMs,
    bool animate,
    Function(double)? onSeekEnd,
  ) {
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
                  builder: (context, v, child) =>
                      Slider(value: v, onChanged: null),
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
              Text(
                _formatDuration(Duration(milliseconds: currentMs)),
                style: AppTheme.caption.copyWith(fontSize: 12),
              ),
              Text(
                _formatDuration(Duration(milliseconds: durationMs)),
                style: AppTheme.caption.copyWith(fontSize: 12),
              ),
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
          icon: Icon(
            Icons.shuffle_rounded,
            color: audio.isShuffleMode
                ? AppTheme.primary
                : AppTheme.textSecondary,
          ),
          onPressed: audio.toggleShuffle,
        ),
        IconButton(
          icon: const Icon(
            Icons.skip_previous_rounded,
            size: 36,
            color: AppTheme.textPrimary,
          ),
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
                color: Color(0x66FF6B35), // Orange glow
                blurRadius: 20,
                offset: Offset(0, 8),
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
          icon: const Icon(
            Icons.skip_next_rounded,
            size: 36,
            color: AppTheme.textPrimary,
          ),
          onPressed: audio.playNext,
        ),
        IconButton(
          icon: Icon(
            audio.loopMode == LoopMode.one
                ? Icons.repeat_one_rounded
                : Icons.repeat_rounded,
            color: audio.loopMode == LoopMode.off
                ? AppTheme.textSecondary
                : AppTheme.primary,
          ),
          onPressed: audio.toggleLoop,
        ),
      ],
    );
  }
}
