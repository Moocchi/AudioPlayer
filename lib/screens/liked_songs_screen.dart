import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
import '../models/song.dart';
import '../services/liked_songs_service.dart';
import '../services/exoplayer_service.dart';
import '../theme/app_theme.dart';
import '../widgets/hires_badge.dart';

class LikedSongsScreen extends StatefulWidget {
  const LikedSongsScreen({super.key});

  @override
  State<LikedSongsScreen> createState() => _LikedSongsScreenState();
}

class _LikedSongsScreenState extends State<LikedSongsScreen> {
  final ImagePicker _picker = ImagePicker();
  bool _isShuffleOn = false;

  Future<void> _pickImage() async {
    try {
      final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
      if (image != null) {
        await LikedSongsService().setPlaylistCover(image.path);
      }
    } catch (e) {
      debugPrint('Error picking image: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: ListenableBuilder(
        listenable: LikedSongsService(),
        builder: (context, _) {
          final service = LikedSongsService();
          final songs = service.likedSongs;
          final totalDurationSeconds = songs.fold<int>(0, (sum, item) => sum + item.duration);
          final coverPath = service.playlistCoverPath;
          
          // Use persisted color or default
          final dominantColor = service.dominantColor ?? AppTheme.primary;
          final gradientColors = [
            dominantColor,
            AppTheme.background,
          ];

          return CustomScrollView(
            slivers: [
              SliverAppBar(
                expandedHeight: 250, // Reduced from 350 to reduce gap
                pinned: true,
                backgroundColor: Colors.white, // Pure white as requested
                surfaceTintColor: Colors.transparent, // Disable M3 color tint overlay
                actions: [
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert),
                    onSelected: (value) {
                      if (value == 'change_photo') {
                        _pickImage();
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'change_photo',
                        child: Row(
                          children: [
                            Icon(Icons.photo_camera, color: Colors.black87),
                            SizedBox(width: 12),
                            Text('Ubah Foto Playlist'),
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
                    final double collapseRange = expandedHeight - kToolbarHeight;
                    final double t = (top - kToolbarHeight) / collapseRange;
                    final double opacity = t.clamp(0.0, 1.0);

                    return FlexibleSpaceBar(
                      background: Opacity(
                        opacity: opacity,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 500),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: gradientColors,
                            ),
                          ),
                          child: Padding(
                            padding: EdgeInsets.only(
                              top: MediaQuery.of(context).padding.top + kToolbarHeight,
                              left: 16, // Match list tile padding
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start, // Top align text with image
                              children: [
                                // Playlist Cover
                                Container(
                                  width: 140,
                                  height: 140,
                                  decoration: BoxDecoration(
                                    color: AppTheme.surface,
                                    borderRadius: BorderRadius.circular(8),
                                    boxShadow: kElevationToShadow[4],
                                    image: coverPath != null 
                                        ? DecorationImage(
                                            image: FileImage(File(coverPath)),
                                            fit: BoxFit.cover,
                                          ) 
                                        : null,
                                  ),
                                  child: coverPath == null 
                                      ? Container(
                                          decoration: const BoxDecoration(
                                            gradient: LinearGradient(
                                              colors: [Colors.white, Colors.purpleAccent],
                                              begin: Alignment.topLeft,
                                              end: Alignment.bottomRight,
                                            ),
                                            borderRadius: BorderRadius.all(Radius.circular(8)),
                                          ),
                                          child: const Center(
                                            child: Icon(Icons.favorite, color: Colors.white, size: 64),
                                          ),
                                        )
                                      : null,
                                ),
                                
                                const SizedBox(width: 16),
                                
                                // Info (Right Side)
                                Expanded(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min, // Wrap content height
                                    crossAxisAlignment: CrossAxisAlignment.start, // Align text to left
                                    mainAxisAlignment: MainAxisAlignment.start, // Align to top
                                    children: [
                                      _buildOutlinedText(
                                        'Liked Songs',
                                        const TextStyle(
                                          fontSize: 24,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                          height: 1.1,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      // Subtitle
                                      _buildOutlinedText(
                                        '${songs.length} songs • ${_formatTotalDuration(Duration(seconds: totalDurationSeconds))}',
                                        const TextStyle(
                                          color: Colors.white, 
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
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
                    );
                  },
                ),
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
              
              // Action Buttons
              SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                         // Play Button
                         GestureDetector(
                           onTap: () {
                             if (songs.isNotEmpty) {
                                if (_isShuffleOn) {
                                  final shuffled = List<Song>.from(songs)..shuffle();
                                  ExoPlayerService().playQueue(shuffled, 0);
                                } else {
                                  ExoPlayerService().playQueue(songs, 0);
                                }
                             }
                           },
                           child: Container(
                             width: 56,
                             height: 56,
                             decoration: const BoxDecoration(
                              color: AppTheme.primary,
                              shape: BoxShape.circle,
                              boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 4))],
                             ),
                             child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 36),
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
              if (songs.isEmpty)
                const SliverFillRemaining(
                  child: Center(
                    child: Text('No liked songs yet', style: TextStyle(color: Colors.grey)),
                  ),
                )
              else
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final song = songs[index];
                      return _buildSongItem(context, song, index, songs);
                    },
                    childCount: songs.length,
                  ),
                ),
                
              const SliverPadding(padding: EdgeInsets.only(bottom: 120)), 
            ],
          );
        },
      ),
    );
  }

  String _formatTotalDuration(Duration d) {
    if (d.inHours > 0) {
      return '${d.inHours} hr ${d.inMinutes % 60} min';
    }
    return '${d.inMinutes} min';
  }

  Widget _buildSongItem(BuildContext context, Song song, int index, List<Song> songs) {
    return InkWell(
      onTap: () {
        ExoPlayerService().playQueue(songs, index);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            // Album Art
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: song.albumCover != null
                  ? CachedNetworkImage(
                      imageUrl: song.albumCover!,
                      width: 48,
                      height: 48,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(color: Colors.grey[800]),
                      errorWidget: (_, __, ___) => Container(color: Colors.grey[800], child: const Icon(Icons.music_note, color: Colors.white54)),
                    )
                  : Container(width: 48, height: 48, color: Colors.grey[800], child: const Icon(Icons.music_note, color: Colors.white54)),
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
                    style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.w600, fontSize: 16),
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
                          style: const TextStyle(color: Colors.black54, fontSize: 13),
                        ),
                      ),
                      // Duration (Right next to More button effectively)
                      Text(
                        song.durationFormatted,
                        style: const TextStyle(color: Colors.black54, fontSize: 13),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            
            // More Button (close to duration)
            IconButton(
              icon: const Icon(Icons.more_vert, color: Colors.black54),
              padding: EdgeInsets.zero, // Remove default padding to get "mepet"
              constraints: const BoxConstraints(), // Minimize constraints
              onPressed: () {
                // Future options
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOutlinedText(String text, TextStyle style) {
    return Stack(
      children: [
        // Outline
        Text(
          text,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: style.copyWith(
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 0.5 // Requested 0.5 width
              ..color = Colors.black,
          ),
        ),
        // Fill
        Text(
          text,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: style,
        ),
      ],
    );
  }
}
