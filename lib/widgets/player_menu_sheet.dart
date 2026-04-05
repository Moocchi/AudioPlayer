import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/song.dart';
import '../services/exoplayer_service.dart';
import '../theme/app_theme.dart';
import 'hires_badge.dart';
import 'sleep_timer_sheet.dart';

class PlayerMenuSheet extends StatelessWidget {
  final Song song;

  const PlayerMenuSheet({super.key, required this.song});

  static Future<void> show(BuildContext context, Song song) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useRootNavigator: true,
      builder: (context) => PlayerMenuSheet(song: song),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).padding.bottom + 24,
      ),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Song info
          Row(
            children: [
              // Album cover
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: song.albumCover != null
                    ? CachedNetworkImage(
                        imageUrl: song.albumCover!,
                        width: 60,
                        height: 60,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => _placeholderCover(),
                      )
                    : _placeholderCover(),
              ),
              const SizedBox(width: 12),
              // Title & Artist
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      song.title,
                      style: AppTheme.heading2.copyWith(fontSize: 16),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (song.isHiRes) ...[
                          const AnimatedHiResBadge(),
                          const SizedBox(width: 6),
                        ] else if (song.isLossless) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
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
                                fontSize: 9,
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
                  ],
                ),
              ),
              // Close button
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Sleep Timer Button
          ListenableBuilder(
            listenable: ExoPlayerService(),
            builder: (context, child) {
              final audio = ExoPlayerService();
              String statusText = '';
              Color iconColor = AppTheme.textPrimary;

              if (audio.stopAfterCurrentSong) {
                statusText = 'Selesai Lagu';
                iconColor = AppTheme.primary;
              } else if (audio.sleepTimerDuration != null &&
                  audio.sleepTimerDuration!.inSeconds > 0) {
                final duration = audio.sleepTimerDuration!;
                String timeStr;
                if (duration.inHours > 0) {
                  final h = duration.inHours;
                  final m = (duration.inMinutes % 60).toString().padLeft(
                    2,
                    '0',
                  );
                  final s = (duration.inSeconds % 60).toString().padLeft(
                    2,
                    '0',
                  );
                  timeStr = '$h:$m:$s';
                } else {
                  final m = duration.inMinutes;
                  final s = (duration.inSeconds % 60).toString().padLeft(
                    2,
                    '0',
                  );
                  timeStr = '$m:$s';
                }
                statusText = timeStr;
                iconColor = AppTheme.primary;
              }

              return InkWell(
                onTap: () {
                  SleepTimerSheet.show(context); // Open Sleep Timer
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.background,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.timer_outlined, color: iconColor, size: 24),
                      const SizedBox(width: 16),
                      Text('Sleep Timer', style: AppTheme.body),
                      const Spacer(),
                      if (statusText.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            statusText,
                            style: AppTheme.caption.copyWith(
                              color: AppTheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      const SizedBox(width: 8),
                      const Icon(
                        Icons.chevron_right_rounded,
                        color: AppTheme.textSecondary,
                        size: 20,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),

          // Menu options
          // Clear Queue
          InkWell(
            onTap: () {
              ExoPlayerService().clearQueue();
              Navigator.pop(context); // Close sheet
              Fluttertoast.showToast(
                msg: 'Antrean dihapus',
                toastLength: Toast.LENGTH_SHORT,
                gravity: ToastGravity.BOTTOM,
                backgroundColor: Colors.black54,
                textColor: Colors.white,
              );
            },
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: AppTheme.background,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.layers_clear_outlined,
                    color: AppTheme.textPrimary,
                    size: 24,
                  ),
                  const SizedBox(width: 16),
                  Text('Hapus antrean', style: AppTheme.body),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _placeholderCover() {
    return Container(
      width: 60,
      height: 60,
      color: AppTheme.divider,
      child: const Icon(Icons.music_note, color: AppTheme.textSecondary),
    );
  }
}
