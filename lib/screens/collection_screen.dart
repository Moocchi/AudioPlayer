import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_reorderable_grid_view/widgets/reorderable_builder.dart';
import 'package:fluttertoast/fluttertoast.dart';
import '../theme/app_theme.dart';
import '../services/liked_songs_service.dart';
import '../services/playlist_service.dart';
import '../services/settings_service.dart';
import '../models/playlist.dart';
import 'liked_songs_screen.dart';
import 'playlist_screen.dart';

class CollectionScreen extends StatefulWidget {
  const CollectionScreen({super.key});

  @override
  State<CollectionScreen> createState() => _CollectionScreenState();
}

class _CollectionScreenState extends State<CollectionScreen> {
  bool _isRearrangeMode = false;
  final ScrollController _scrollController = ScrollController();
  final _gridViewKey = GlobalKey();
  final _listViewKey = GlobalKey();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

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
            // Header
            _buildHeader(),
            // Content
            Expanded(child: _buildContent()),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('Collections', style: AppTheme.heading2),
          IconButton(
            onPressed: () {
              setState(() {
                _isRearrangeMode = !_isRearrangeMode;
              });
              if (_isRearrangeMode) {
                Fluttertoast.showToast(
                  msg: 'Entering Rearrange mode area',
                  toastLength: Toast.LENGTH_SHORT,
                  gravity: ToastGravity.BOTTOM,
                  backgroundColor: Colors.black54,
                  textColor: Colors.white,
                );
              }
            },
            icon: Icon(
              _isRearrangeMode
                  ? Icons.check_circle
                  : Icons.swap_vert_circle_outlined,
              color: _isRearrangeMode
                  ? AppTheme.primary
                  : AppTheme.textSecondary,
              size: 28,
            ),
            tooltip: _isRearrangeMode
                ? 'Done Rearranging'
                : 'Rearrange Playlists',
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    return ListenableBuilder(
      listenable: Listenable.merge([
        LikedSongsService(),
        PlaylistService(),
        SettingsService(),
      ]),
      builder: (context, _) {
        final likedSongsService = LikedSongsService();
        final playlistService = PlaylistService();
        final settingsService = SettingsService();
        final playlists = playlistService.playlists;

        // Check layout mode
        final isGridMode = settingsService.collectionLayoutMode == 'grid';

        // Total items = 1 (Liked Songs) + User Playlists
        final int itemCount = 1 + playlists.length;

        if (isGridMode) {
          if (_isRearrangeMode) {
            return _buildRearrangeGrid(playlistService, playlists);
          }
          return _buildStandardGrid(
            itemCount,
            likedSongsService,
            playlistService,
            playlists,
          );
        } else {
          if (_isRearrangeMode) {
            return _buildRearrangeList(playlistService, playlists, context);
          }
          return _buildStandardList(
            itemCount,
            likedSongsService,
            playlistService,
            playlists,
            context,
          );
        }
      },
    );
  }

  Widget _buildRearrangeGrid(
    PlaylistService playlistService,
    List<Playlist> playlists,
  ) {
    final List<Widget> children = playlists.map<Widget>((playlist) {
      final gradientColors = playlist.gradientConfig != null
          ? playlist.gradientConfig!.getColors()
          : [Colors.blue.shade800, Colors.purple.shade800];

      return Container(
        key: ValueKey(playlist.id),
        child: Material(
          color: Colors.transparent,
          child: _buildGridItem(
            title: playlist.name,
            subtitle: '${playlist.songIds.length} songs',
            icon: Icons.playlist_play,
            gradientColors: gradientColors,
            imagePath: playlist.coverPath,
            onTap: () {}, // Drag only
          ),
        ),
      );
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
          child: Text(
            'Drag to reorder playlists',
            style: AppTheme.caption.copyWith(color: AppTheme.primary),
          ),
        ),
        Expanded(
          child: ReorderableBuilder<Widget>(
            positionDuration: const Duration(milliseconds: 200),
            releasedChildDuration: Duration.zero,
            fadeInDuration: Duration.zero,
            longPressDelay: const Duration(milliseconds: 300),
            dragChildBoxDecoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(16),
            ),
            enableScrollingWhileDragging: true,
            automaticScrollExtent: 100.0,
            scrollController: _scrollController,
            onReorder: (reorderedListFunction) {
              final reorderedWidgets = reorderedListFunction(children);

              final orderedIds = reorderedWidgets
                  .map((widget) => (widget.key as ValueKey<String>).value)
                  .toList();

              playlistService.reorderPlaylistsByOrderedIds(orderedIds);
            },
            children: children,
            builder: (children) {
              return GridView.count(
                key: _gridViewKey,
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                crossAxisCount: 2,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: 1.0,
                children: children,
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildStandardGrid(
    int itemCount,
    LikedSongsService likedSongsService,
    PlaylistService playlistService,
    List<Playlist> playlists,
  ) {
    return GridView.builder(
      physics: const ClampingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 1.0,
      ),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        // Index 0 is always Liked Songs
        if (index == 0) {
          return _buildGridItem(
            title: 'Liked Songs',
            subtitle: '${likedSongsService.songCount} songs',
            icon: Icons.favorite_rounded,
            gradientColors: [Colors.purple.shade800, Colors.blue.shade800],
            imagePath: likedSongsService.playlistCoverPath,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const LikedSongsScreen(),
                ),
              );
            },
          );
        }

        // User Playlists
        final playlist = playlists[index - 1];
        final gradientColors = playlist.gradientConfig != null
            ? playlist.gradientConfig!.getColors()
            : [Colors.blue.shade800, Colors.purple.shade800];

        return GestureDetector(
          onLongPress: () {
            // Show menu or enter rearrange mode hint?
            // For now, just show menu as before or do nothing.
            // Original code didn't have specific long press for standard grid items other than drag.
            // But standard list items had menus.
            // We should ensure the context menu still works if it was there.
            // Checking the file, there was `_showPlaylistMenu`?
            // The previous code for Grid didn't show menu on long press, only on tap of menu button?
            // Wait, I need to check if there is a menu button in grid item.
          },
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
              if (value == 'rename') _showRenameDialog(playlist);
              if (value == 'delete') _showDeleteConfirmation(playlist);
            },
          ),
        );
      },
      // Note: No onReorder here, purely view.
    );
  }

  Widget _buildRearrangeList(
    PlaylistService playlistService,
    List<Playlist> playlists,
    BuildContext context,
  ) {
    // Calculate aspect ratio for list items (fixed height 80)
    final double width = MediaQuery.of(context).size.width;
    final double itemWidth = width - 32; // Horizontal padding 16*2
    final double childAspectRatio = itemWidth / 80;

    final List<Widget> children = playlists.map<Widget>((playlist) {
      final gradientColors = playlist.gradientConfig != null
          ? playlist.gradientConfig!.getColors()
          : [Colors.blue.shade800, Colors.purple.shade800];

      return Container(
        key: ValueKey(playlist.id),
        child: Material(
          color: Colors.transparent,
          child: _buildListItem(
            title: playlist.name,
            subtitle: '${playlist.songIds.length} songs',
            icon: Icons.playlist_play,
            gradientColors: gradientColors,
            imagePath: playlist.coverPath,
            onTap: () {}, // Drag only
          ),
        ),
      );
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
          child: Text(
            'Drag to reorder playlists',
            style: AppTheme.caption.copyWith(color: AppTheme.primary),
          ),
        ),
        Expanded(
          child: ReorderableBuilder<Widget>(
            positionDuration: const Duration(milliseconds: 200),
            releasedChildDuration: Duration.zero,
            fadeInDuration: Duration.zero,
            longPressDelay: const Duration(milliseconds: 300),
            dragChildBoxDecoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(12),
            ),
            enableScrollingWhileDragging: true,
            automaticScrollExtent: 100.0,
            scrollController: _scrollController,
            onReorder: (reorderedListFunction) {
              final reorderedWidgets = reorderedListFunction(children);

              final orderedIds = reorderedWidgets
                  .map((widget) => (widget.key as ValueKey<String>).value)
                  .toList();

              playlistService.reorderPlaylistsByOrderedIds(orderedIds);
            },
            children: children,
            builder: (children) {
              return GridView.count(
                key: _listViewKey,
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                crossAxisCount: 1,
                mainAxisSpacing: 12,
                childAspectRatio: childAspectRatio,
                children: children,
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildStandardList(
    int itemCount,
    LikedSongsService likedSongsService,
    PlaylistService playlistService,
    List<Playlist> playlists,
    BuildContext context,
  ) {
    // Calculate aspect ratio for list items (fixed height 80)
    final double width = MediaQuery.of(context).size.width;
    final double itemWidth = width - 32; // Horizontal padding 16*2
    final double childAspectRatio = itemWidth / 80;

    return GridView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 1,
        mainAxisSpacing: 12,
        childAspectRatio: childAspectRatio,
      ),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        // Index 0 is always Liked Songs
        if (index == 0) {
          return _buildListItem(
            title: 'Liked Songs',
            subtitle: '${likedSongsService.songCount} songs',
            icon: Icons.favorite_rounded,
            gradientColors: [Colors.purple.shade800, Colors.blue.shade800],
            imagePath: likedSongsService.playlistCoverPath,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const LikedSongsScreen(),
                ),
              );
            },
          );
        }

        // User Playlists
        final playlist = playlists[index - 1];
        final gradientColors = playlist.gradientConfig != null
            ? playlist.gradientConfig!.getColors()
            : [Colors.blue.shade800, Colors.purple.shade800];

        return _buildListItem(
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
            if (value == 'rename') _showRenameDialog(playlist);
            if (value == 'delete') _showDeleteConfirmation(playlist);
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
                    icon: const Icon(
                      Icons.more_vert,
                      color: Colors.white,
                      shadows: [
                        Shadow(offset: Offset(-0.5, -0.5), color: Colors.black),
                        Shadow(offset: Offset(0.5, -0.5), color: Colors.black),
                        Shadow(offset: Offset(0.5, 0.5), color: Colors.black),
                        Shadow(offset: Offset(-0.5, 0.5), color: Colors.black),
                      ],
                    ),
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
                            Text('Rename', style: AppTheme.body),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete, size: 20, color: Colors.red),
                            SizedBox(width: 12),
                            Text('Delete', style: TextStyle(color: Colors.red)),
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

  Widget _buildListItem({
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
        height: 80,
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // Thumbnail / Cover
            Container(
              width: 80,
              height: 80,
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
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  bottomLeft: Radius.circular(12),
                ),
              ),
              child: imagePath == null
                  ? Icon(icon, color: Colors.white, size: 32)
                  : null,
            ),

            // Title & Subtitle
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: AppTheme.caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),

            // Menu Button
            if (onMenuSelected != null)
              PopupMenuButton<String>(
                onSelected: onMenuSelected,
                icon: const Icon(
                  Icons.more_vert,
                  color: AppTheme.textSecondary,
                ),
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'rename',
                    child: Row(
                      children: [
                        Icon(Icons.edit, size: 20, color: AppTheme.textPrimary),
                        SizedBox(width: 12),
                        Text('Rename', style: AppTheme.body),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete, size: 20, color: Colors.red),
                        SizedBox(width: 12),
                        Text('Delete', style: TextStyle(color: Colors.red)),
                      ],
                    ),
                  ),
                ],
              )
            else
              const SizedBox(width: 48), // Placeholder for alignment
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
