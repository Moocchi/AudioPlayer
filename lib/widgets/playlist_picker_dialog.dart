import 'dart:io';

import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import '../models/song.dart';
import '../models/playlist.dart';
import '../services/playlist_service.dart';
import '../services/song_service.dart';
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
  final _songService = SongService();
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
            '"${widget.song.title}" berhasil disimpan ke "${playlist.name}"',
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.BOTTOM,
      );
    }
  }

  Future<void> _addToPlaylist(Playlist playlist) async {
    await _playlistService.addSongToPlaylist(playlist.id, widget.song.id);

    if (mounted) {
      Navigator.pop(context);
      Fluttertoast.showToast(
        msg:
            '"${widget.song.title}" berhasil disimpan ke "${playlist.name}"',
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.BOTTOM,
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
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      titlePadding: const EdgeInsets.fromLTRB(18, 18, 18, 6),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Simpan ke playlist', style: AppTheme.heading2),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFF8F9FA),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.divider),
            ),
            child: Row(
              children: [
                _buildSongCover(),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.song.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.body.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.song.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.caption,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      contentPadding: const EdgeInsets.fromLTRB(0, 8, 0, 6),
      content: ListenableBuilder(
        listenable: _playlistService,
        builder: (context, _) {
          final playlists = _playlistService.playlists;

          if (playlists.isEmpty) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 30),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: const Color(0x14FF6B35),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Icon(
                      Icons.playlist_play,
                      size: 38,
                      color: AppTheme.primary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Belum ada playlist',
                    style: AppTheme.body.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text('Buat playlist baru untuk simpan lagu ini', style: AppTheme.caption),
                ],
              ),
            );
          }

          return ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 300),
            child: SizedBox(
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

                  return _buildPlaylistTile(playlist, isAdded);
                },
              ),
            ),
          );
        },
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 2, 16, 16),
      actions: [
        SizedBox(
          width: double.infinity,
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.textSecondary,
                    side: const BorderSide(color: AppTheme.divider),
                    minimumSize: const Size.fromHeight(46),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text('Tutup'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _showCreatePlaylistDialog,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Playlist baru'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(46),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSongCover() {
    final coverUrl = widget.song.albumCover;

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 46,
        height: 46,
        child: (coverUrl != null && coverUrl.isNotEmpty)
            ? Image.network(
                coverUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _fallbackAlbumCover(),
              )
            : _fallbackAlbumCover(),
      ),
    );
  }

  Widget _buildPlaylistTile(Playlist playlist, bool isAdded) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: isAdded ? null : () => _addToPlaylist(playlist),
          child: Ink(
            decoration: BoxDecoration(
              color: isAdded ? const Color(0x14FF6B35) : const Color(0xFFF8F9FA),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isAdded ? const Color(0x66FF6B35) : AppTheme.divider,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  _buildPlaylistCover(playlist),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          playlist.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.body.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          isAdded
                              ? '${playlist.songIds.length} lagu · Sudah ada'
                              : '${playlist.songIds.length} lagu',
                          style: AppTheme.caption,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  isAdded
                      ? const Icon(
                          Icons.check_circle,
                          color: AppTheme.primary,
                          size: 22,
                        )
                      : const Icon(
                          Icons.add_circle_outline,
                          color: AppTheme.textSecondary,
                          size: 20,
                        ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPlaylistCover(Playlist playlist) {
    Widget fallback() => _fallbackAlbumCover(iconSize: 20);

    if (playlist.coverPath != null && playlist.coverPath!.isNotEmpty) {
      final coverFile = File(playlist.coverPath!);
      if (coverFile.existsSync()) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            width: 44,
            height: 44,
            child: Image.file(
              coverFile,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => fallback(),
            ),
          ),
        );
      }
    }

    if (playlist.songIds.isNotEmpty) {
      final song = _songService.getSongById(playlist.songIds.first);
      final coverUrl = song?.albumCover;

      if (coverUrl != null && coverUrl.isNotEmpty) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            width: 44,
            height: 44,
            child: Image.network(
              coverUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => fallback(),
            ),
          ),
        );
      }
    }

    return fallback();
  }

  Widget _fallbackAlbumCover({double iconSize = 22}) {
    return Container(
      color: const Color(0xFFF2F4F7),
      alignment: Alignment.center,
      child: Icon(
        Icons.music_note_rounded,
        size: iconSize,
        color: AppTheme.textSecondary,
      ),
    );
  }
}
