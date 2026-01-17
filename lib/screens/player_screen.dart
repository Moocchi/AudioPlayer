import 'package:flutter/material.dart';
import '../models/song.dart';
import '../services/exoplayer_service.dart';
import '../theme/app_theme.dart';
import '../widgets/queue_sheet.dart';

class PlayerScreen extends StatelessWidget {
  const PlayerScreen({super.key});

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

        return Scaffold(
          backgroundColor: AppTheme.background,
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  // Header
                  _buildHeader(context, audio),
                  
                  const SizedBox(height: 20),
                  
                  // Album art - fixed size, square
                  _buildAlbumArt(song),
                  
                  const SizedBox(height: 24),
                  
                  // Song info
                  _buildSongInfo(song),
                  
                  const SizedBox(height: 24),
                  
                  // Progress slider
                  _buildProgressSlider(audio),
                  
                  const Spacer(),
                  
                  // Controls
                  _buildControls(audio),
                  
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        );
      },
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
            child: Column(
              children: [
                Text('NOW PLAYING', style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textSecondary,
                  letterSpacing: 1,
                )),
                Text('My music list', style: TextStyle(
                  fontSize: 14,
                  color: AppTheme.primary,
                )),
              ],
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

  Widget _buildAlbumArt(Song song) {
    return Center(
      child: Hero(
        tag: 'album_art_${song.id}',
        child: Container(
          width: 260,
          height: 260,
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
                ? Image.network(
                    song.albumCover!,
                    fit: BoxFit.cover,
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

  Widget _buildSongInfo(Song song) {
    return Column(
      children: [
        // Quality badge
        if (song.isHiRes) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              gradient: AppTheme.primaryGradient,
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Text(
              'Hi-Res 24bit',
              style: TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ] else if (song.isLossless) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFF1DB954),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Text(
              'Lossless 16bit',
              style: TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),
        // Title
        Text(
          song.title,
          style: AppTheme.heading1.copyWith(fontSize: 22),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 6),
        // Artist
        Text(
          song.artist,
          style: AppTheme.caption.copyWith(fontSize: 15),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildProgressSlider(ExoPlayerService audio) {
    return StreamBuilder<Duration>(
      stream: audio.positionStream,
      builder: (context, snapshot) {
        final position = snapshot.data ?? Duration.zero;
        final duration = audio.duration;
        final progress = duration.inMilliseconds > 0
            ? position.inMilliseconds / duration.inMilliseconds
            : 0.0;

        return Column(
          children: [
            // Slider
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
              child: Slider(
                value: progress.clamp(0.0, 1.0),
                onChanged: (value) {
                  final newPosition = Duration(
                    milliseconds: (value * duration.inMilliseconds).round(),
                  );
                  audio.seek(newPosition);
                },
              ),
            ),
            // Time labels
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _formatDuration(position),
                    style: AppTheme.caption.copyWith(fontSize: 12),
                  ),
                  if (audio.isLoading)
                    Text(
                      audio.loadingStatus,
                      style: AppTheme.caption.copyWith(
                        color: AppTheme.primary,
                        fontSize: 12,
                      ),
                    ),
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
          onTap: audio.isLoading ? null : audio.togglePlayPause,
          child: Container(
            width: 64,
            height: 64,
            decoration: AppTheme.gradientButtonDecoration,
            child: audio.isLoading
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
