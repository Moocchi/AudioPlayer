import 'package:flutter/material.dart';
import 'package:iqbal_hires/services/exoplayer_service.dart';
import 'package:iqbal_hires/theme/app_theme.dart';

class PlayerQueueView extends StatelessWidget {
  const PlayerQueueView({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ExoPlayerService(),
      builder: (context, _) {
        final audio = ExoPlayerService();
        final queue = audio.queue;
        final currentIndex = audio.currentIndex;

        if (queue.isEmpty) {
          return Center(
            child: Text(
              'Antrean Kosong',
              style: TextStyle(color: AppTheme.textSecondary),
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: queue.length + 1, // Add header
          itemBuilder: (context, index) {
            if (index == 0) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  'Antrean (${queue.length} Lagu)',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              );
            }

            final songIndex = index - 1;
            final song = queue[songIndex];
            final isPlaying = songIndex == currentIndex;

            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: isPlaying
                    ? AppTheme.primary.withOpacity(0.1)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: ListTile(
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Image.network(
                    song.albumCover ?? '',
                    width: 48,
                    height: 48,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 48,
                      height: 48,
                      color: Colors.grey[800],
                      child: const Icon(Icons.music_note, color: Colors.white),
                    ),
                  ),
                ),
                title: Text(
                  song.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isPlaying ? AppTheme.primary : AppTheme.textPrimary,
                    fontWeight: isPlaying ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                subtitle: Text(
                  song.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isPlaying
                        ? AppTheme.primary.withOpacity(0.7)
                        : AppTheme.textSecondary,
                    fontSize: 12,
                  ),
                ),
                trailing: isPlaying
                    ? const Icon(Icons.equalizer, color: AppTheme.primary)
                    : null,
                onTap: () {
                  audio.playQueue(queue, songIndex, userInitiated: true);
                },
              ),
            );
          },
        );
      },
    );
  }
}
