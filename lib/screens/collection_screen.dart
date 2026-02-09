import 'dart:io';
import 'package:flutter/material.dart';
import 'package:reorderable_grid_view/reorderable_grid_view.dart';
import '../theme/app_theme.dart';
import '../services/liked_songs_service.dart';
import '../services/playlist_service.dart';
import '../models/playlist.dart';
import 'liked_songs_screen.dart';
import 'playlist_screen.dart';

class CollectionScreen extends StatefulWidget {
  const CollectionScreen({super.key});

  @override
  State<CollectionScreen> createState() => _CollectionScreenState();
}

class _CollectionScreenState extends State<CollectionScreen> {
  void _showRenameDialog(Playlist playlist) {
    final controller = TextEditingController(text: playlist.name);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Rename Playlist', style: AppTheme.heading2),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: AppTheme.body,
          maxLength: 25,
          decoration: InputDecoration(
            hintText: 'Playlist name',
            hintStyle: AppTheme.caption,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Cancel',
              style: TextStyle(color: AppTheme.textSecondary),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              if (controller.text.trim().isNotEmpty) {
                await PlaylistService().renamePlaylist(
                  playlist.id,
                  controller.text.trim(),
                );
                if (mounted) Navigator.pop(context);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('Rename'),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirmation(Playlist playlist) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Delete Playlist?', style: AppTheme.heading2),
        content: Text(
          'Are you sure you want to delete "${playlist.name}"?',
          style: AppTheme.body,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text(
              'Cancel',
              style: TextStyle(color: AppTheme.textSecondary),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              await PlaylistService().deletePlaylist(playlist.id);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(
          children: [
            // Content
            Expanded(child: _buildContent()),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    return ListenableBuilder(
      listenable: Listenable.merge([LikedSongsService(), PlaylistService()]),
      builder: (context, _) {
        final likedSongsService = LikedSongsService();
        final playlistService = PlaylistService();
        final playlists = playlistService.playlists;

        // Total items = 1 (Liked Songs) + User Playlists
        final int itemCount = 1 + playlists.length;

        return ReorderableGridView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            childAspectRatio: 1.0,
          ),
          itemCount: itemCount,
          dragWidgetBuilder: (index, child) {
            return Material(
              color: Colors.transparent,
              elevation: 0,
              child: Opacity(opacity: 0.8, child: child),
            );
          },

          onReorder: (oldIndex, newIndex) {
            // Prevent Liked Songs (Index 0) from moving or being replaced
            if (oldIndex == 0) return;

            // Adjust for Liked Songs offset
            if (newIndex == 0) newIndex = 1;

            // Correct newIndex calculation for PlaylistService
            int pOldIndex = oldIndex - 1;
            int pNewIndex = newIndex - 1;

            playlistService.reorderPlaylists(pOldIndex, pNewIndex);
          },
          itemBuilder: (context, index) {
            // Index 0 is always Liked Songs
            if (index == 0) {
              return Container(
                key: const ValueKey('liked_songs'),
                child: _buildGridItem(
                  title: 'Liked Songs',
                  subtitle: '${likedSongsService.songCount} songs',
                  icon: Icons.favorite_rounded,
                  gradientColors: [
                    Colors.purple.shade800,
                    Colors.blue.shade800,
                  ],
                  imagePath: likedSongsService.playlistCoverPath,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const LikedSongsScreen(),
                      ),
                    );
                  },
                ),
              );
            }

            // User Playlists
            final playlist = playlists[index - 1];
            final gradientColors = playlist.gradientConfig != null
                ? playlist.gradientConfig!.getColors()
                : [Colors.blue.shade800, Colors.purple.shade800];

            return Container(
              key: ValueKey(playlist.id),
              child: _buildGridItem(
                title: playlist.name,
                subtitle: '${playlist.songIds.length} songs',
                icon: Icons.playlist_play,
                gradientColors: gradientColors,
                imagePath: playlist.coverPath,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => PlaylistScreen(playlist: playlist),
                    ),
                  );
                },
                onMenuSelected: (value) {
                  if (value == 'rename') {
                    _showRenameDialog(playlist);
                  } else if (value == 'delete') {
                    _showDeleteConfirmation(playlist);
                  }
                },
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildGridItem({
    required String title,
    required String subtitle,
    required IconData icon,
    required List<Color> gradientColors,
    required VoidCallback onTap,
    String? imagePath,
    Function(String)? onMenuSelected,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Background Image / Gradient
            Container(
              decoration: BoxDecoration(
                gradient: imagePath == null
                    ? LinearGradient(
                        colors: gradientColors,
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : null,
                image: _getSafeImage(imagePath) != null
                    ? DecorationImage(
                        image: _getSafeImage(imagePath)!,
                        fit: BoxFit.cover,
                      )
                    : null,
              ),
              child: imagePath == null
                  ? Center(child: Icon(icon, color: Colors.white, size: 48))
                  : null,
            ),

            // Gradient Overlay for text readability
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withOpacity(0.0),
                    Colors.black.withOpacity(0.6),
                  ],
                  stops: const [0.5, 0.7, 1.0],
                ),
              ),
            ),

            // Text Overlay (Bottom Left)
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      shadows: [
                        Shadow(
                          offset: const Offset(-0.5, -0.5),
                          color: Colors.black,
                        ),
                        Shadow(
                          offset: const Offset(0.5, -0.5),
                          color: Colors.black,
                        ),
                        Shadow(
                          offset: const Offset(0.5, 0.5),
                          color: Colors.black,
                        ),
                        Shadow(
                          offset: const Offset(-0.5, 0.5),
                          color: Colors.black,
                        ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                      shadows: [
                        Shadow(
                          offset: Offset(0, 1),
                          blurRadius: 2,
                          color: Colors.black,
                        ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),

            // More Options Menu (Top Right)
            if (onMenuSelected != null)
              Positioned(
                top: 0,
                right: 0,
                child: Material(
                  color: Colors.transparent,
                  child: PopupMenuButton<String>(
                    onSelected: onMenuSelected,
                    icon: const Icon(Icons.more_vert, color: Colors.white),
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'rename',
                        child: Row(
                          children: [
                            Icon(
                              Icons.edit,
                              size: 20,
                              color: AppTheme.textPrimary,
                            ),
                            SizedBox(width: 12),
                            Text('Ganti nama', style: AppTheme.body),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete, size: 20, color: Colors.red),
                            SizedBox(width: 12),
                            Text('Hapus', style: TextStyle(color: Colors.red)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  ImageProvider? _getSafeImage(String? path) {
    if (path == null) return null;
    try {
      final file = File(path);
      if (file.existsSync() && file.lengthSync() > 0) {
        return FileImage(file);
      }
    } catch (e) {
      debugPrint('Error loading image: $e');
    }
    return null;
  }
}
