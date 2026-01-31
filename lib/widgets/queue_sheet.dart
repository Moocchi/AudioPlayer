import 'package:flutter/material.dart';
import '../models/song.dart';
import '../services/exoplayer_service.dart';
import '../theme/app_theme.dart';

class QueueSheet extends StatelessWidget {
  const QueueSheet({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => const QueueSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ExoPlayerService(),
      builder: (context, _) {
        final audio = ExoPlayerService();
        final queue = audio.queue;
        final currentIndex = audio.currentIndex;

        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          builder: (context, scrollController) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                children: [
                  // Handle
                  Container(
                    margin: const EdgeInsets.only(top: 12),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppTheme.divider,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  // Header
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        const Icon(Icons.queue_music_rounded, color: AppTheme.primary),
                        const SizedBox(width: 12),
                        Text(
                          'Up next',
                          style: AppTheme.heading2,
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppTheme.divider,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '${queue.length} songs',
                            style: AppTheme.caption,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  // Queue list
                  Expanded(
                    child: queue.isEmpty
                        ? const Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.queue_music_outlined,
                                  size: 64,
                                  color: AppTheme.divider,
                                ),
                                SizedBox(height: 16),
                                Text(
                                  'Queue is empty',
                                  style: AppTheme.caption,
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            controller: scrollController,
                            padding: const EdgeInsets.only(bottom: 20),
                            itemCount: queue.length,
                            itemBuilder: (context, index) {
                              final song = queue[index];
                              final isPlaying = index == currentIndex;
                              
                              return ListTile(
                                onTap: () {
                                  audio.playQueue(queue, index);
                                },
                                leading: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (isPlaying)
                                      _PlayingIndicator()
                                    else
                                      SizedBox(
                                        width: 24,
                                        child: Text(
                                          '${index + 1}',
                                          style: AppTheme.caption,
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                    const SizedBox(width: 12),
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: song.albumCover != null
                                          ? Image.network(
                                              song.albumCover!,
                                              width: 48,
                                              height: 48,
                                              fit: BoxFit.cover,
                                            )
                                          : Container(
                                              width: 48,
                                              height: 48,
                                              color: AppTheme.divider,
                                              child: const Icon(Icons.music_note),
                                            ),
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
                                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                        decoration: BoxDecoration(
                                          gradient: AppTheme.primaryGradient,
                                          borderRadius: BorderRadius.circular(3),
                                        ),
                                        child: const Text(
                                          'Hi-Res',
                                          style: TextStyle(color: Colors.white, fontSize: 9),
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                    ] else if (song.isLossless) ...[
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF1DB954),
                                          borderRadius: BorderRadius.circular(3),
                                        ),
                                        child: const Text(
                                          'Lossless',
                                          style: TextStyle(color: Colors.white, fontSize: 9),
                                        ),
                                      ),
                                      const SizedBox(width: 4),
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
                                trailing: Text(song.durationFormatted, style: AppTheme.caption),
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _PlayingIndicator extends StatefulWidget {
  @override
  State<_PlayingIndicator> createState() => _PlayingIndicatorState();
}

class _PlayingIndicatorState extends State<_PlayingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 24,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(3, (i) {
          return AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              final delay = i * 0.2;
              final value = ((_controller.value + delay) % 1.0);
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 1),
                width: 3,
                height: 8 + (8 * value),
                decoration: BoxDecoration(
                  color: AppTheme.primary,
                  borderRadius: BorderRadius.circular(2),
                ),
              );
            },
          );
        }),
      ),
    );
  }
}
