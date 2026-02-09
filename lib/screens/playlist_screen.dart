import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:fluttertoast/fluttertoast.dart';
import '../models/playlist.dart';
import '../models/song.dart';
import '../models/gradient_config.dart';
import '../services/playlist_service.dart';
import '../services/song_service.dart';
import '../services/exoplayer_service.dart';
import '../theme/app_theme.dart';
import '../widgets/gradient_picker_sheet.dart';
import '../widgets/song_menu_sheet.dart';
import '../widgets/hires_badge.dart';

class PlaylistScreen extends StatefulWidget {
  final Playlist playlist;

  const PlaylistScreen({super.key, required this.playlist});

  @override
  State<PlaylistScreen> createState() => _PlaylistScreenState();
}

class _PlaylistScreenState extends State<PlaylistScreen> {
  final _playlistService = PlaylistService();
  final _songService = SongService();
  final _audioService = ExoPlayerService();
  bool _isShuffleOn = false;

  Future<void> _pickAndCropImage() async {
    try {
      // Step 1: Pick image
      final picker = ImagePicker();
      final XFile? picked = await picker.pickImage(source: ImageSource.gallery);
      if (picked == null) return;

      // Step 2: Crop image (using newer image_cropper API)
      final croppedFile = await ImageCropper().cropImage(
        sourcePath: picked.path,
        aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Crop Playlist Cover',
            toolbarColor: AppTheme.primary,
            toolbarWidgetColor: Colors.white,
            lockAspectRatio: false,
          ),
        ],
        maxWidth: 512,
        maxHeight: 512,
        compressQuality: 90,
      );

      if (croppedFile == null) return;

      // Step 3: Generate palette
      final image = FileImage(File(croppedFile.path));
      final paletteGenerator = await PaletteGenerator.fromImageProvider(image);

      if (!mounted) return;

      // Step 4: Show gradient picker
      final gradientConfig = await showModalBottomSheet<GradientConfig>(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (context) => GradientPickerSheet(
          palette: paletteGenerator,
          initialConfig: null,
          coverImagePath: croppedFile.path,
        ),
      );

      // Fix: If user cancels gradient picker (returns null), ABORT the whole flow
      // Do not save the image if the wizard was cancelled.
      if (gradientConfig == null) return;

      // Step 5: Save everything
      await _playlistService.setPlaylistCover(
        widget.playlist.id,
        croppedFile.path,
        gradientConfig: gradientConfig,
      );
    } catch (e) {
      debugPrint('Error in pick and crop flow: $e');
      if (mounted) {
        Fluttertoast.showToast(
          msg: 'Error: $e',
          toastLength: Toast.LENGTH_SHORT,
          gravity: ToastGravity.BOTTOM,
          backgroundColor: Colors.black54,
          textColor: Colors.white,
        );
      }
    }
  }

  void _showGradientPicker(String coverPath) async {
    try {
      final image = FileImage(File(coverPath));
      final paletteGenerator = await PaletteGenerator.fromImageProvider(image);

      if (!mounted) return;

      final gradientConfig = await showModalBottomSheet<GradientConfig>(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (context) => GradientPickerSheet(
          palette: paletteGenerator,
          initialConfig: widget.playlist.gradientConfig,
          coverImagePath: coverPath,
        ),
      );

      if (gradientConfig != null) {
        await _playlistService.setPlaylistCover(
          widget.playlist.id,
          coverPath,
          gradientConfig: gradientConfig,
        );
      }
    } catch (e) {
      debugPrint('Error showing gradient picker: $e');
    }
  }

  void _playAll(List<Song> songs) {
    if (songs.isEmpty) return;
    if (_isShuffleOn) {
      final shuffled = List<Song>.from(songs)..shuffle();
      _audioService.playQueue(shuffled, 0);
    } else {
      _audioService.playQueue(songs, 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: ListenableBuilder(
        listenable: Listenable.merge([_playlistService, _songService]),
        builder: (context, _) {
          // Get current playlist data
          final playlist = _playlistService.playlists.firstWhere(
            (p) => p.id == widget.playlist.id,
            orElse: () => widget.playlist,
          );

          // Get songs from IDs
          final List<Song> songs = _songService.getSongsByIds(playlist.songIds);

          // Get gradient colors
          final gradientColors = playlist.gradientConfig != null
              ? playlist.gradientConfig!.getColors()
              : [Colors.blue.shade800, Colors.purple.shade800];

          // Calculate total duration
          final int totalSeconds = songs.fold(
            0,
            (sum, item) => sum + item.duration,
          );
          final int totalMinutes = totalSeconds ~/ 60;

          return CustomScrollView(
            slivers: [
              // App Bar with gradient
              SliverAppBar(
                expandedHeight: 280.0,
                floating: false,
                pinned: true,
                backgroundColor: Colors.transparent,
                leading: Container(
                  margin: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(
                    color: Colors.black26,
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                    padding: EdgeInsets.zero,
                  ),
                ),
                actions: [
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert),
                    color: AppTheme.surface,
                    onSelected: (value) {
                      if (value == 'delete') {
                        _showDeleteConfirmation();
                      } else if (value == 'rename') {
                        _showRenameDialog();
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'rename',
                        child: Row(
                          children: [
                            Icon(Icons.edit, color: Colors.black87),
                            SizedBox(width: 12),
                            Text('Rename Playlist'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete, color: Colors.red),
                            SizedBox(width: 12),
                            Text(
                              'Delete Playlist',
                              style: TextStyle(color: Colors.red),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
                flexibleSpace: LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints constraints) {
                    final double top = constraints.biggest.height;
                    final double expandedHeight = 280.0;
                    final double minHeight =
                        kToolbarHeight + MediaQuery.of(context).padding.top;
                    final double collapseRange = expandedHeight - minHeight;
                    final double t = (top - minHeight) / collapseRange;
                    final double opacity = t.clamp(0.0, 1.0);

                    // Dynamic AppBar background: gradient color when collapsed, transparent when expanded
                    final collapsedBgColor = gradientColors.first;

                    return Container(
                      color: Color.lerp(
                        collapsedBgColor,
                        Colors.transparent,
                        opacity,
                      ),
                      child: FlexibleSpaceBar(
                        background: Opacity(
                          opacity: opacity,
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: gradientColors,
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                              ),
                            ),
                            child: Padding(
                              padding: EdgeInsets.only(
                                top:
                                    MediaQuery.of(context).padding.top +
                                    kToolbarHeight,
                                left: 24, // Matched with song list (16+8)
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Playlist Cover
                                  GestureDetector(
                                    onTap: _pickAndCropImage,
                                    child: Stack(
                                      children: [
                                        Container(
                                          width: 140,
                                          height: 140,
                                          decoration: BoxDecoration(
                                            color: AppTheme.surface,
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                            image:
                                                _getSafeImage(
                                                      playlist.coverPath,
                                                    ) !=
                                                    null
                                                ? DecorationImage(
                                                    image: _getSafeImage(
                                                      playlist.coverPath,
                                                    )!,
                                                    fit: BoxFit.cover,
                                                  )
                                                : null,
                                            gradient: playlist.coverPath == null
                                                ? LinearGradient(
                                                    colors: gradientColors,
                                                    begin: Alignment.topLeft,
                                                    end: Alignment.bottomRight,
                                                  )
                                                : null,
                                          ),
                                          child: playlist.coverPath == null
                                              ? const Center(
                                                  child: Icon(
                                                    Icons.playlist_play,
                                                    color: Colors.white,
                                                    size: 64,
                                                  ),
                                                )
                                              : null,
                                        ),
                                        // Camera icon overlay
                                        Positioned(
                                          bottom: 4,
                                          right: 4,
                                          child: Container(
                                            padding: const EdgeInsets.all(6),
                                            decoration: BoxDecoration(
                                              color: Colors.black54,
                                              borderRadius:
                                                  BorderRadius.circular(20),
                                            ),
                                            child: const Icon(
                                              Icons.camera_alt,
                                              color: Colors.white,
                                              size: 16,
                                            ),
                                          ),
                                        ),
                                        // Gradient picker icon
                                        if (playlist.coverPath != null)
                                          Positioned(
                                            bottom: 4,
                                            left: 4,
                                            child: GestureDetector(
                                              onTap: () => _showGradientPicker(
                                                playlist.coverPath!,
                                              ),
                                              child: Container(
                                                padding: const EdgeInsets.all(
                                                  6,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: Colors.black54,
                                                  borderRadius:
                                                      BorderRadius.circular(20),
                                                ),
                                                child: const Icon(
                                                  Icons.palette,
                                                  color: Colors.white,
                                                  size: 16,
                                                ),
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),

                                  const SizedBox(width: 16),

                                  // Info
                                  Expanded(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisAlignment:
                                          MainAxisAlignment.start,
                                      children: [
                                        Text(
                                          playlist.name.length > 25
                                              ? playlist.name.substring(0, 25)
                                              : playlist.name,
                                          style: const TextStyle(
                                            fontSize: 28,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.visible,
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          '${playlist.songIds.length} songs • $totalMinutes Minutes',
                                          style: const TextStyle(
                                            fontSize: 14,
                                            color: Colors.white70,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),

              // Play and Shuffle buttons
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(
                    left:
                        20, // Center match: 20 + 28 = 48 (Song List Image Center)
                    top: 16,
                    bottom: 16,
                    right: 16,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                      // Play Button
                      GestureDetector(
                        onTap: () => _playAll(songs),
                        child: Container(
                          width: 56,
                          height: 56,
                          decoration: const BoxDecoration(
                            color: AppTheme.primary,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.play_arrow_rounded,
                            color: Colors.white,
                            size: 36,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      // Shuffle Toggle
                      IconButton(
                        onPressed: () {
                          setState(() {
                            _isShuffleOn = !_isShuffleOn;
                          });
                        },
                        icon: Icon(
                          Icons.shuffle_rounded,
                          color: _isShuffleOn ? AppTheme.primary : Colors.grey,
                          size: 28,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Song List
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: songs.isEmpty
                    ? SliverToBoxAdapter(
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Column(
                              children: [
                                Icon(
                                  Icons.music_note,
                                  size: 64,
                                  color: AppTheme.textSecondary.withOpacity(
                                    0.5,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'No songs in this playlist',
                                  style: AppTheme.caption,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Add songs from the song menu',
                                  style: AppTheme.caption.copyWith(
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      )
                    : SliverList(
                        delegate: SliverChildBuilderDelegate((context, index) {
                          final song = songs[index];
                          return _buildSongItem(song, index, songs);
                        }, childCount: songs.length),
                      ),
              ),

              // Bottom padding
              const SliverToBoxAdapter(child: SizedBox(height: 100)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSongItem(Song song, int index, List<Song> allSongs) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () => _audioService.playQueue(allSongs, index),
        onLongPress: () {
          SongMenuSheet.show(context, song, playlistId: widget.playlist.id);
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.only(left: 8, right: 0, top: 8, bottom: 8),
          child: Row(
            children: [
              // Album Art (48x48 like LikedSongs)
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  color: Colors.grey[800],
                ),
                child: song.albumCover != null
                    ? CachedNetworkImage(
                        imageUrl: song.albumCover!,
                        memCacheWidth: 144,
                        maxWidthDiskCache: 144,
                        fadeInDuration: Duration.zero,
                        width: 48,
                        height: 48,
                        fit: BoxFit.cover,
                        imageBuilder: (context, imageProvider) => Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(4),
                            image: DecorationImage(
                              image: imageProvider,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                        placeholder: (_, __) =>
                            Container(color: AppTheme.divider),
                        errorWidget: (_, __, ___) => const SizedBox(
                          width: 48,
                          height: 48,
                          child: Icon(Icons.music_note, color: Colors.white54),
                        ),
                      )
                    : const SizedBox(
                        width: 48,
                        height: 48,
                        child: Icon(Icons.music_note, color: Colors.white54),
                      ),
              ),

              const SizedBox(width: 12),

              // Song Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Title
                    Text(
                      song.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.body.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: 14, // Match Home Screen
                      ),
                    ),
                    const SizedBox(height: 4),
                    // Subtitle (Badges + Artist + Duration)
                    Row(
                      children: [
                        // Badges
                        if (song.isHiRes) ...[
                          const AnimatedHiResBadge(),
                          const SizedBox(width: 6),
                        ] else if (song.isLossless) ...[
                          const LosslessBadge(),
                          const SizedBox(width: 6),
                        ],
                        // Artist
                        Expanded(
                          child: Text(
                            song.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTheme.caption.copyWith(fontSize: 13),
                          ),
                        ),
                        // Duration
                        Text(
                          song.durationFormatted,
                          style: AppTheme.caption.copyWith(fontSize: 13),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // More Button
              IconButton(
                icon: const Icon(Icons.more_vert, size: 20),
                color: AppTheme.textSecondary,
                onPressed: () {
                  SongMenuSheet.show(
                    context,
                    song,
                    playlistId: widget.playlist.id, // Pass playlist context
                  );
                },
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showRenameDialog() {
    final controller = TextEditingController(text: widget.playlist.name);
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
                await _playlistService.renamePlaylist(
                  widget.playlist.id,
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

  void _showDeleteConfirmation() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Delete Playlist?', style: AppTheme.heading2),
        content: Text(
          'Are you sure you want to delete "${widget.playlist.name}"?',
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
              // Close dialog first
              Navigator.pop(dialogContext); // Use dialogContext

              // Delete playlist
              await _playlistService.deletePlaylist(widget.playlist.id);

              // Go back to previous screen
              if (mounted) {
                Navigator.pop(context); // Use outer context
              }
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
