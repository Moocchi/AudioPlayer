import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import 'dart:async';
import '../../services/exoplayer_service.dart';
import '../../services/lyrics_service.dart';
import '../../theme/app_theme.dart';

class PlayerLyricsView extends StatefulWidget {
  const PlayerLyricsView({super.key});

  @override
  State<PlayerLyricsView> createState() => _PlayerLyricsViewState();
}

class _PlayerLyricsViewState extends State<PlayerLyricsView> {
  final LyricsService _lyricsService = LyricsService();
  final ScrollController _scrollController = ScrollController();
  final ExoPlayerService _audio = ExoPlayerService();

  LyricsResult? _lyricsResult;
  bool _isLoading = false;
  String? _loadedSongId;
  int _currentLineIndex = -1;
  bool _userScrolling = false;
  StreamSubscription<Duration>? _positionSub;

  @override
  void initState() {
    super.initState();
    _audio.addListener(_onPlayerChanged);
    _positionSub = _audio.positionStream.listen(_onPositionChanged);

    // Initial load
    final song = _audio.currentSong;
    if (song != null) {
      _loadLyrics(song.id, song.title, song.artist, song.duration);
    }
  }

  @override
  void dispose() {
    _audio.removeListener(_onPlayerChanged);
    _positionSub?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _onPlayerChanged() {
    final song = _audio.currentSong;
    if (song == null) {
      if (_loadedSongId != null) {
        setState(() {
          _loadedSongId = null;
          _lyricsResult = null;
          _isLoading = false;
          _currentLineIndex = -1;
        });
      }
      return;
    }

    if (song.id != _loadedSongId) {
      _loadLyrics(song.id, song.title, song.artist, song.duration);
    }
  }

  void _onPositionChanged(Duration position) {
    if (_lyricsResult == null || !_lyricsResult!.hasSyncedLyrics) return;

    final lines = _lyricsResult!.syncedLyrics;
    final newIndex = _findCurrentLineIndex(position, lines);

    if (newIndex != _currentLineIndex && newIndex >= 0) {
      setState(() {
        _currentLineIndex = newIndex;
      });
      if (!_userScrolling) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollToLine(newIndex);
        });
      }
    }
  }

  Future<void> _loadLyrics(String songId, String title, String artist, int duration) async {
    _loadedSongId = songId;

    setState(() {
      _isLoading = true;
      _lyricsResult = null;
      _currentLineIndex = -1;
    });

    final result = await _lyricsService.fetchLyrics(
      title: title,
      artist: artist,
      durationSeconds: duration,
    );

    if (mounted && _loadedSongId == songId) {
      setState(() {
        _lyricsResult = result;
        _isLoading = false;
      });
    }
  }

  int _findCurrentLineIndex(Duration position, List<LyricLine> lines) {
    int index = -1;
    for (int i = 0; i < lines.length; i++) {
      if (lines[i].timestamp <= position) {
        index = i;
      } else {
        break;
      }
    }
    return index;
  }

  void _scrollToLine(int index) {
    if (!_scrollController.hasClients) return;

    if (index < 0) {
      _scrollController.animateTo(
        0.0,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
      );
      return;
    }

    // Each line is roughly 56px (padding + text), center it
    final targetOffset = (index * 56.0) - 120.0;
    final clampedOffset = targetOffset.clamp(
      0.0,
      _scrollController.position.maxScrollExtent,
    );

    _scrollController.animateTo(
      clampedOffset,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
    );
  }

  void _seekToLine(int index) {
    if (_lyricsResult == null || index >= _lyricsResult!.syncedLyrics.length) return;
    final line = _lyricsResult!.syncedLyrics[index];

    // Pause auto-scroll so it doesn't snap back before seek takes effect
    _userScrolling = true;
    _audio.seek(line.timestamp);

    // Resume auto-scroll after seek settles
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        _userScrolling = false;
      }
    });
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      // User started dragging
      _userScrolling = true;
    } else if (notification is ScrollEndNotification) {
      // Resume auto-scroll after 3 seconds
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) {
          _userScrolling = false;
        }
      });
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    if (_audio.currentSong == null) {
      return _buildEmptyState('Tidak ada lagu yang diputar');
    }

    if (_isLoading) {
      return _buildLoadingState();
    }

    if (_lyricsResult == null) {
      return _buildEmptyState('Lirik Tidak Ditemukan');
    }

    // If we have synced lyrics, show them
    if (_lyricsResult!.hasSyncedLyrics) {
      return _buildSyncedLyrics();
    }

    // Otherwise show plain lyrics
    if (_lyricsResult!.plainLyrics != null) {
      return _buildPlainLyrics(_lyricsResult!.plainLyrics!);
    }

    return _buildEmptyState('Lirik Tidak Ditemukan');
  }

  Widget _buildSyncedLyrics() {
    final lines = _lyricsResult!.syncedLyrics;

    return NotificationListener<ScrollNotification>(
      onNotification: _handleScrollNotification,
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        itemCount: lines.length + 2, // +2 for top and bottom spacers
        itemBuilder: (context, index) {
          // Top spacer
          if (index == 0) return const SizedBox(height: 24);
          // Bottom spacer
          if (index == lines.length + 1) return const SizedBox(height: 200);

          final lineIndex = index - 1;
          final line = lines[lineIndex];
          final isActive = lineIndex == _currentLineIndex;
          final isPast = lineIndex < _currentLineIndex;

          // Skip rendering completely empty interlude lines
          if (line.text.isEmpty) {
            return const SizedBox(height: 32);
          }

          return GestureDetector(
            onTap: () => _seekToLine(lineIndex),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(
                vertical: 8,
                horizontal: 12,
              ),
              child: AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic,
                style: TextStyle(
                  fontSize: isActive ? 24 : 20,
                  fontWeight: isActive ? FontWeight.w800 : FontWeight.w700,
                  color: isActive
                      ? AppTheme.primary
                      : isPast
                          ? AppTheme.textSecondary.withOpacity(0.35)
                          : AppTheme.textSecondary.withOpacity(0.5),
                  height: 1.3,
                ),
                child: Text(line.text),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPlainLyrics(String lyrics) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      child: Text(
        lyrics,
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: AppTheme.textPrimary.withOpacity(0.8),
          height: 1.8,
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Shimmer.fromColors(
        baseColor: AppTheme.surface,
        highlightColor: AppTheme.divider,
        child: ListView.builder(
          itemCount: 12,
          itemBuilder: (context, index) {
            double widthFactor;
            switch (index % 4) {
              case 0: widthFactor = 0.8; break;
              case 1: widthFactor = 0.6; break;
              case 2: widthFactor = 0.9; break;
              default: widthFactor = 0.5; break;
            }
            
            return Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: Container(
                width: MediaQuery.of(context).size.width * widthFactor,
                height: 22,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildEmptyState(String message) {
    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.lyrics_outlined,
              size: 64,
              color: AppTheme.textSecondary.withOpacity(0.3),
            ),
            const SizedBox(height: 16),
            Text(
              message,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary.withOpacity(0.7),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Coba lagu lain',
              style: TextStyle(color: AppTheme.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
