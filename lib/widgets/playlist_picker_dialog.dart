import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import '../models/song.dart';
import '../models/playlist.dart';
import '../services/playlist_service.dart';
import '../theme/app_theme.dart';

class PlaylistPickerDialog extends StatefulWidget {
  final Song song;

  const PlaylistPickerDialog({super.key, required this.song});

  static Future<void> show(BuildContext context, Song song) async {
    return showDialog(
      context: context,
      builder: (context) => PlaylistPickerDialog(song: song),
    );
  }

  @override
  State<PlaylistPickerDialog> createState() => _PlaylistPickerDialogState();
}

class _PlaylistPickerDialogState extends State<PlaylistPickerDialog> {
  final _playlistService = PlaylistService();
  final _nameController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _createNewPlaylist() async {
    if (_nameController.text.trim().isEmpty) {
      Fluttertoast.showToast(
        msg: 'Nama playlist tidak boleh kosong',
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.black54,
        textColor: Colors.white,
      );
      return;
    }

    final playlist = await _playlistService.createPlaylist(
      _nameController.text.trim(),
    );

    if (playlist == null) {
      if (mounted) {
        Fluttertoast.showToast(
          msg: 'Batas playlist tercapai (Maksimal 20)',
          toastLength: Toast.LENGTH_SHORT,
          gravity: ToastGravity.BOTTOM,
          backgroundColor: Colors.red,
          textColor: Colors.white,
        );
      }
      return;
    }
    await _playlistService.addSongToPlaylist(playlist.id, widget.song.id);

    if (mounted) {
      Navigator.pop(context); // Close create dialog
      Navigator.pop(context); // Close picker dialog
      Fluttertoast.showToast(
        msg:
            '"${widget.song.title}" ditambahkan ke playlist "${playlist.name}"',
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.black54,
        textColor: Colors.white,
      );
    }
  }

  Future<void> _addToPlaylist(Playlist playlist) async {
    await _playlistService.addSongToPlaylist(playlist.id, widget.song.id);

    if (mounted) {
      Navigator.pop(context);
      Fluttertoast.showToast(
        msg:
            '"${widget.song.title}" ditambahkan ke playlist "${playlist.name}"',
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.black54,
        textColor: Colors.white,
      );
    }
  }

  void _showCreatePlaylistDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Playlist baru', style: AppTheme.heading2),
        content: TextField(
          controller: _nameController,
          autofocus: true,
          style: AppTheme.body,
          maxLength: 25,
          decoration: InputDecoration(
            hintText: 'Nama playlist',
            hintStyle: AppTheme.caption,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppTheme.divider),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppTheme.primary),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Batal',
              style: TextStyle(color: AppTheme.textSecondary),
            ),
          ),
          ElevatedButton(
            onPressed: _createNewPlaylist,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('Buat'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.surface,
      title: const Text('Simpan ke playlist', style: AppTheme.heading2),
      contentPadding: const EdgeInsets.symmetric(vertical: 16),
      content: ListenableBuilder(
        listenable: _playlistService,
        builder: (context, _) {
          final playlists = _playlistService.playlists;

          if (playlists.isEmpty) {
            return Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.playlist_play,
                    size: 48,
                    color: AppTheme.textSecondary,
                  ),
                  const SizedBox(height: 16),
                  Text('Belum ada playlist', style: AppTheme.caption),
                ],
              ),
            );
          }

          return SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: playlists.length,
              itemBuilder: (context, index) {
                final playlist = playlists[index];
                final isAdded = _playlistService.isSongInPlaylist(
                  playlist.id,
                  widget.song.id,
                );

                return ListTile(
                  leading: const Icon(
                    Icons.playlist_play,
                    color: AppTheme.primary,
                  ),
                  title: Text(playlist.name, style: AppTheme.body),
                  subtitle: Text(
                    '${playlist.songIds.length} lagu',
                    style: AppTheme.caption,
                  ),
                  trailing: isAdded
                      ? const Icon(Icons.check, color: AppTheme.primary)
                      : null,
                  onTap: isAdded ? null : () => _addToPlaylist(playlist),
                );
              },
            ),
          );
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text(
            'Tutup',
            style: TextStyle(color: AppTheme.textSecondary),
          ),
        ),
        ElevatedButton.icon(
          onPressed: _showCreatePlaylistDialog,
          icon: const Icon(Icons.add, size: 20),
          label: const Text('Playlist baru'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primary,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }
}
