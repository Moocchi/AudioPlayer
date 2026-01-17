import 'package:flutter/material.dart';
import '../models/song.dart';
import '../services/audio_service.dart';
import '../theme/app_theme.dart';

class SongTile extends StatelessWidget {
  final Song song;
  final int? index;
  final VoidCallback? onTap;
  final bool isPlaying;
  final bool showDuration;

  const SongTile({
    super.key,
    required this.song,
    this.index,
    this.onTap,
    this.isPlaying = false,
    this.showDuration = true,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (index != null)
            SizedBox(
              width: 24,
              child: Text(
                '${index! + 1}',
                style: TextStyle(
                  color: isPlaying ? AppTheme.primary : AppTheme.textSecondary,
                  fontWeight: isPlaying ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
          const SizedBox(width: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: song.albumCover != null
                ? Image.network(
                    song.albumCover!,
                    width: 50,
                    height: 50,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _placeholder(),
                  )
                : _placeholder(),
          ),
        ],
      ),
      title: Text(
        song.title,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: isPlaying ? AppTheme.primary : AppTheme.textPrimary,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Row(
        children: [
          if (song.isHiRes) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                gradient: AppTheme.primaryGradient,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'Hi-Res',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 6),
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
            const SizedBox(width: 6),
          ],
          Expanded(
            child: Text(
              song.artist,
              style: AppTheme.caption,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      trailing: showDuration
          ? Text(
              song.durationFormatted,
              style: AppTheme.caption,
            )
          : null,
    );
  }

  Widget _placeholder() {
    return Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        color: AppTheme.divider,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(Icons.music_note, color: AppTheme.textSecondary),
    );
  }
}
