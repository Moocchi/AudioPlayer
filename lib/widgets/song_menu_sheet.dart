import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import '../models/song.dart';
import '../services/exoplayer_service.dart';
import '../theme/app_theme.dart';
import '../services/playlist_service.dart';
import 'playlist_picker_dialog.dart';
import 'hires_badge.dart';

class SongMenuSheet extends StatelessWidget {
  final Song song;
  final String? playlistId;

  const SongMenuSheet({super.key, required this.song, this.playlistId});

  static Future<void> show(
    BuildContext context,
    Song song, {
    String? playlistId,
  }) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useRootNavigator: true, // Fix: Show on top of everything
      builder: (context) => SongMenuSheet(song: song, playlistId: playlistId),
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
                    ? Image.network(
                        song.albumCover!,
                        width: 60,
                        height: 60,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _placeholderCover(),
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
                          const LosslessBadge(),
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

          // Menu options - Reordered as requested
          // 1. Play Next
          _buildMenuItem(
            context,
            icon: Icons.play_arrow,
            title: 'Putar setelah ini',
            onTap: () {
              ExoPlayerService().addToQueueNext(song);
              Navigator.pop(context);
              Fluttertoast.showToast(
                msg: '"${song.title}" akan diputar setelah ini',
                toastLength: Toast.LENGTH_SHORT,
                gravity: ToastGravity.BOTTOM,
                backgroundColor: Colors.black54,
                textColor: Colors.white,
              );
            },
          ),

          // 2. Add to Queue
          _buildMenuItem(
            context,
            icon: Icons.queue_music,
            title: 'Tambahkan ke antrean',
            onTap: () {
              ExoPlayerService().addToQueueEnd(song);
              Navigator.pop(context);
              Fluttertoast.showToast(
                msg: '"${song.title}" ditambahkan ke antrean',
                toastLength: Toast.LENGTH_SHORT,
                gravity: ToastGravity.BOTTOM,
                backgroundColor: Colors.black54,
                textColor: Colors.white,
              );
            },
          ),

          // 3. Add to Playlist
          _buildMenuItem(
            context,
            icon: Icons.playlist_add,
            title: 'Simpan ke playlist',
            onTap: () async {
              Navigator.pop(context); // Close menu first
              await PlaylistPickerDialog.show(context, song);
            },
          ),

          // 4. Remove from Playlist (Conditional)
          if (playlistId != null) ...[
            const Divider(color: AppTheme.divider, height: 24),
            _buildMenuItem(
              context,
              icon: Icons.remove_circle_outline,
              title: 'Hapus dari playlist',
              color: Colors.red,
              onTap: () async {
                Navigator.pop(context); // Close menu

                await PlaylistService().removeSongFromPlaylist(
                  playlistId!,
                  song.id,
                );

                Fluttertoast.showToast(
                  msg: '"${song.title}" dihapus dari playlist',
                  toastLength: Toast.LENGTH_SHORT,
                  gravity: ToastGravity.BOTTOM,
                  backgroundColor: Colors.black54,
                  textColor: Colors.white,
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMenuItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    Color? color,
  }) {
    final themeColor = color ?? AppTheme.textPrimary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: AppTheme.background,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, color: themeColor, size: 24),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                title,
                style: AppTheme.body.copyWith(
                  color: color != null ? themeColor : null,
                ),
              ),
            ),
          ],
        ),
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
