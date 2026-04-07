import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:iqbal_hires/models/song.dart';
import 'package:iqbal_hires/services/exoplayer_service.dart';
import 'package:iqbal_hires/theme/app_theme.dart';
import 'package:iqbal_hires/widgets/hires_badge.dart';
import 'package:iqbal_hires/widgets/mini_equalizer.dart';
import 'package:iqbal_hires/widgets/playlist_picker_dialog.dart';

class PlayerQueueView extends StatefulWidget {
  const PlayerQueueView({super.key});

  @override
  State<PlayerQueueView> createState() => _PlayerQueueViewState();
}

class _PlayerQueueViewState extends State<PlayerQueueView> {
  final ExoPlayerService _audio = ExoPlayerService();

  void _onReorder(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) {
      newIndex -= 1;
    }
    _audio.reorderQueue(oldIndex, newIndex);
  }

  Future<void> _showQueueActions(Song song, int index) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useRootNavigator: true,
      builder: (sheetContext) {
        return Container(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(sheetContext).padding.bottom + 20,
          ),
          decoration: const BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: song.albumCover != null
                        ? CachedNetworkImage(
                            imageUrl: song.albumCover!,
                            width: 56,
                            height: 56,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) => _placeholderCover(size: 56),
                          )
                        : _placeholderCover(size: 56),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          song.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.heading3,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          song.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.caption,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(sheetContext),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildActionTile(
                icon: Icons.play_arrow_rounded,
                title: 'Putar setelah ini',
                onTap: () {
                  Navigator.pop(sheetContext);
                  _audio.moveToPlayNext(index);
                  Fluttertoast.showToast(
                    msg: '"${song.title}" dipindah ke setelah lagu saat ini',
                    toastLength: Toast.LENGTH_SHORT,
                    gravity: ToastGravity.BOTTOM,
                    backgroundColor: Colors.black54,
                    textColor: Colors.white,
                  );
                },
              ),
              _buildActionTile(
                icon: Icons.queue_music_rounded,
                title: 'Tambahkan ke antrean',
                onTap: () {
                  Navigator.pop(sheetContext);
                  _audio.addToQueueEnd(song);
                  Fluttertoast.showToast(
                    msg: '"${song.title}" ditambahkan ke antrean',
                    toastLength: Toast.LENGTH_SHORT,
                    gravity: ToastGravity.BOTTOM,
                    backgroundColor: Colors.black54,
                    textColor: Colors.white,
                  );
                },
              ),
              _buildActionTile(
                icon: Icons.playlist_add_rounded,
                title: 'Simpan ke playlist',
                onTap: () async {
                  Navigator.pop(sheetContext);
                  await PlaylistPickerDialog.show(context, song);
                },
              ),
              _buildActionTile(
                icon: Icons.delete_outline_rounded,
                title: 'Hapus dari antrean',
                color: Colors.red,
                onTap: () {
                  Navigator.pop(sheetContext);
                  _audio.removeFromQueue(index);
                  Fluttertoast.showToast(
                    msg: '"${song.title}" dihapus dari antrean',
                    toastLength: Toast.LENGTH_SHORT,
                    gravity: ToastGravity.BOTTOM,
                    backgroundColor: Colors.black54,
                    textColor: Colors.white,
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildActionTile({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    Color? color,
  }) {
    final foreground = color ?? AppTheme.textPrimary;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: AppTheme.background,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, color: foreground),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: AppTheme.body.copyWith(color: foreground),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeholderCover({double size = 54}) {
    return Container(
      width: size,
      height: size,
      color: AppTheme.divider,
      alignment: Alignment.center,
      child: const Icon(Icons.music_note, color: AppTheme.textSecondary),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _audio,
      builder: (context, _) {
        final queue = _audio.queue;
        final currentIndex = _audio.currentIndex;

        if (queue.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(
                  Icons.queue_music_outlined,
                  size: 56,
                  color: AppTheme.divider,
                ),
                SizedBox(height: 12),
                Text(
                  'Antrean kosong',
                  style: TextStyle(color: AppTheme.textSecondary),
                ),
              ],
            ),
          );
        }

        return ReorderableListView.builder(
          buildDefaultDragHandles: false,
          padding: const EdgeInsets.only(top: 16, bottom: 24),
          header: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Antrean (${queue.length} Lagu)',
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 32 / 2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Tahan ikon garis untuk geser urutan, swipe kiri untuk hapus',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
          itemCount: queue.length,
          onReorder: _onReorder,
          proxyDecorator: (child, _, __) {
            return Material(
              color: AppTheme.surface,
              child: child,
            );
          },
          itemBuilder: (context, index) {
            final song = queue[index];
            final isPlaying = index == currentIndex;

            return Dismissible(
              key: ValueKey('queue_${song.id}_${song.title.hashCode}_$index'),
              direction: DismissDirection.endToStart,
              background: Container(
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                color: Colors.red.withValues(alpha: 0.9),
                child: const Icon(
                  Icons.delete_outline_rounded,
                  color: Colors.white,
                ),
              ),
              onDismissed: (_) {
                _audio.removeFromQueue(index);
                Fluttertoast.showToast(
                  msg: '"${song.title}" dihapus dari antrean',
                  toastLength: Toast.LENGTH_SHORT,
                  gravity: ToastGravity.BOTTOM,
                  backgroundColor: Colors.black54,
                  textColor: Colors.white,
                );
              },
              child: InkWell(
                onTap: () => _audio.playAtQueueIndex(index, userInitiated: true),
                onLongPress: () => _showQueueActions(song, index),
                child: Padding(
                  padding: const EdgeInsets.only(
                    left: 16,
                    right: 0,
                    top: 4,
                    bottom: 4,
                  ),
                  child: Row(
                    children: [
                      Stack(
                        children: [
                          Container(
                            height: 54,
                            width: 54,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(6),
                              color: AppTheme.divider,
                            ),
                            child: song.albumCover != null
                                ? CachedNetworkImage(
                                    imageUrl: song.albumCover!,
                                    width: 54,
                                    height: 54,
                                    fit: BoxFit.cover,
                                    imageBuilder: (context, imageProvider) => Container(
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(6),
                                        image: DecorationImage(
                                          image: imageProvider,
                                          fit: BoxFit.cover,
                                        ),
                                      ),
                                    ),
                                    errorWidget: (_, __, ___) => _placeholderCover(size: 54),
                                  )
                                : _placeholderCover(size: 54),
                          ),
                          if (isPlaying)
                            const Positioned(
                              right: 4,
                              bottom: 4,
                              child: MiniEqualizer(size: 14, color: Colors.white),
                            ),
                        ],
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              song.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: isPlaying
                                    ? AppTheme.primary
                                    : AppTheme.textPrimary,
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                if (song.isHiRes) ...[
                                  const AnimatedHiResBadge(),
                                  const SizedBox(width: 6),
                                ] else if (song.isLossless) ...[
                                  const LosslessBadge(),
                                  const SizedBox(width: 6),
                                ],
                                Expanded(
                                  child: Text(
                                    song.artist,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppTheme.caption.copyWith(fontSize: 12),
                                  ),
                                ),
                                Text(
                                  ' ${song.durationFormatted}',
                                  style: AppTheme.caption.copyWith(fontSize: 12),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 4),
                      ReorderableDelayedDragStartListener(
                        index: index,
                        child: const SizedBox(
                          width: 32,
                          height: 32,
                          child: Center(
                            child: Icon(
                              Icons.reorder_rounded,
                              size: 20,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ),
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
}
