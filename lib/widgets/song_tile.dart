import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/song.dart';
import '../theme/app_theme.dart';
import 'hires_badge.dart';

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

  String _getFileSize() {
    // Use actual file size if available, otherwise use improved estimation
    return song.fileSizeMB ?? song.estimatedFileSizeMB;
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            // Index number
            if (index != null)
              SizedBox(
                width: 24,
                child: Text(
                  '${index! + 1}',
                  style: TextStyle(
                    color: isPlaying
                        ? AppTheme.primary
                        : AppTheme.textSecondary,
                    fontWeight: isPlaying ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
            if (index != null) const SizedBox(width: 8),

            // Album cover with caching
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: song.albumCover != null
                  ? CachedNetworkImage(
                      imageUrl: song.albumCover!,
                      width: 50,
                      height: 50,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => _placeholder(),
                      errorWidget: (_, __, ___) => _placeholder(),
                    )
                  : _placeholder(),
            ),
            const SizedBox(width: 12),

            // Song info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title row with duration
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          song.title,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                            color: isPlaying
                                ? AppTheme.primary
                                : AppTheme.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (showDuration) ...[
                        const SizedBox(width: 8),
                        Text(
                          song.durationFormatted,
                          style: TextStyle(
                            fontSize: 13,
                            color: isPlaying
                                ? AppTheme.primary
                                : AppTheme.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),

                  // Badge + Artist row
                  Row(
                    children: [
                      if (song.isHiRes) ...[
                        const AnimatedHiResBadge(),
                        const SizedBox(width: 6),
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
                  const SizedBox(height: 2),

                  // Size info
                  Text(
                    '${song.isHiRes ? "24-bit • " : "16-bit • "}${_getFileSize()}',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppTheme.textSecondary.withOpacity(0.7),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
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
