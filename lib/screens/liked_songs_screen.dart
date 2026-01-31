import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/song.dart';
import '../services/liked_songs_service.dart';
import '../services/exoplayer_service.dart';
import '../theme/app_theme.dart';
import '../widgets/hires_badge.dart';

class LikedSongsScreen extends StatelessWidget {
  const LikedSongsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: ListenableBuilder(
        listenable: LikedSongsService(),
        builder: (context, _) {
          final songs = LikedSongsService().likedSongs;
          final totalDurationSeconds = songs.fold<int>(0, (sum, item) => sum + item.duration);

          return CustomScrollView(
            slivers: [
              SliverAppBar(
                expandedHeight: 300,
                pinned: true,
                backgroundColor: AppTheme.background,
                flexibleSpace: FlexibleSpaceBar(
                  background: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.purple.shade900,
                          AppTheme.background,
                        ],
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Custom default image
                          Container(
                            width: 140,
                            height: 140,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Colors.white, Colors.purpleAccent],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(4),
                              boxShadow: kElevationToShadow[4],
                            ),
                            child: const Center(
                              child: Icon(Icons.favorite, color: Colors.white, size: 64),
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Liked Songs',
                            style: TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Text(
                                '${songs.length} songs',
                                style: const TextStyle(color: Colors.white70, fontSize: 13),
                              ),
                              const SizedBox(width: 4),
                              const Text('•', style: TextStyle(color: Colors.white70)),
                              const SizedBox(width: 4),
                              Text(
                                _formatTotalDuration(Duration(seconds: totalDurationSeconds)),
                                style: const TextStyle(color: Colors.white70, fontSize: 13),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8), // Spacing for toolbar
                        ],
                      ),
                    ),
                  ),
                ),
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
              
              // Action Buttons (Play/Shuffle)
              SliverToBoxAdapter(
                 child: Padding(
                   padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                   child: Row(
                     mainAxisAlignment: MainAxisAlignment.spaceBetween,
                     children: [
                       // Shuffle/Play Button
                       const Spacer(),
                       
                       // Shuffle Button (Spotify Style Green Button)
                       GestureDetector(
                         onTap: () {
                           if (songs.isNotEmpty) {
                              // Play randomly
                              // Shuffle happens in the service/player logic usually, 
                              // but here we can just shuffle the list before passing
                              final shuffled = List<Song>.from(songs)..shuffle();
                              ExoPlayerService().playQueue(shuffled, 0); 
                           }
                         },
                         child: Container(
                           width: 56,
                           height: 56,
                           decoration: const BoxDecoration(
                            color: AppTheme.primary, // Green usually, using Theme primary (orange) or user requested color? User just said 'ganti logo acak'
                            shape: BoxShape.circle,
                           ),
                           child: const Icon(Icons.shuffle_rounded, color: Colors.white, size: 28),
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
                
              const SliverPadding(padding: EdgeInsets.only(bottom: 120)), // Space for MiniPlayer
            ],
          );
        },
      ),
    );
  }

  // Duration parser helper removed as Song.duration is already int (seconds)

  String _formatTotalDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes % 60;
    if (hours > 0) return '$hours hr $minutes min';
    return '$minutes min';
  }

  Widget _buildSongItem(BuildContext context, Song song, int index, List<Song> songs) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: ClipRRect(
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
      title: Text(
        song.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
      ),
      subtitle: Row(
        children: [
          if (song.isHiRes) ...[
             const AnimatedHiResBadge(),
             const SizedBox(width: 6),
          ],
          Expanded(
            child: Text(
              song.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white60, fontSize: 13),
            ),
          ),
        ],
      ),
      trailing: IconButton(
        icon: const Icon(Icons.more_vert, color: Colors.white60),
        onPressed: () {
          // Options
        },
      ),
      onTap: () {
        // Play specifically this song, but queue assumes shuffle? 
        // User said: "kalo play dari playlist bakal ngacak ga sesuai urutan"
        // Usually clicking a song plays THAT song. The BIG button does shuffle.
        // I'll make the single tap play the context starting from this song, or shuffle?
        // Let's implement standard behavior: Play this song, with queue being the list.
        ExoPlayerService().playQueue(songs, index);
      },
    );
  }
}
