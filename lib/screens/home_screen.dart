import 'package:flutter/material.dart';
import '../models/song.dart';
import '../services/api_service.dart';
import '../services/exoplayer_service.dart';
import '../theme/app_theme.dart';
import '../widgets/mini_player.dart';
import '../widgets/song_tile.dart';
import 'player_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _searchController = TextEditingController();
  final ExoPlayerService _audio = ExoPlayerService();
  List<Song> _songs = [];
  bool _isLoading = false;
  bool _hasSearched = false;

  Future<void> _search(String query) async {
    if (query.trim().isEmpty) return;

    setState(() {
      _isLoading = true;
      _hasSearched = true;
    });

    final results = await ApiService.searchSongs(query);
    
    setState(() {
      _songs = results;
      _isLoading = false;
    });
  }

  void _playSong(int index) {
    _audio.playQueue(_songs, index);
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, _) => const PlayerScreen(),
        transitionsBuilder: (context, animation, _, child) {
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 1),
              end: Offset.zero,
            ).animate(CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            )),
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
          children: [
            // Search header
            _buildSearchHeader(),
            
            // Content
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: AppTheme.primary),
                    )
                  : _hasSearched
                      ? _buildSearchResults()
                      : _buildWelcome(),
            ),
            
            // Mini player
            const MiniPlayer(),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: AppTheme.primaryGradient,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.music_note, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Iqbal Hires',
                    style: AppTheme.heading2.copyWith(fontSize: 20),
                  ),
                  const Text('Hi-Res Lossless Music', style: AppTheme.caption),
                ],
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.settings_outlined),
                color: AppTheme.textSecondary,
                onPressed: () {},
              ),
            ],
          ),
          const SizedBox(height: 20),
          // Search bar
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search songs, artists, albums...',
                hintStyle: AppTheme.caption,
                prefixIcon: const Icon(Icons.search, color: AppTheme.textSecondary),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: AppTheme.textSecondary),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _songs = [];
                            _hasSearched = false;
                          });
                        },
                      )
                    : null,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              ),
              onSubmitted: _search,
              onChanged: (_) => setState(() {}),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWelcome() {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppTheme.primary.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.headphones_rounded,
                size: 64,
                color: AppTheme.primary,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Discover Hi-Res Music',
              style: AppTheme.heading2,
            ),
            const SizedBox(height: 8),
            Text(
              'Search for your favorite songs\nand enjoy 24-bit lossless audio',
              style: AppTheme.caption,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchResults() {
    if (_songs.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off, size: 64, color: AppTheme.divider),
            SizedBox(height: 16),
            Text('No results found', style: AppTheme.caption),
          ],
        ),
      );
    }

    return ListenableBuilder(
      listenable: _audio,
      builder: (context, _) {
        return ListView.builder(
          padding: const EdgeInsets.only(bottom: 20),
          itemCount: _songs.length,
          itemBuilder: (context, index) {
            final song = _songs[index];
            final isPlaying = _audio.currentSong?.id == song.id;

            return SongTile(
              song: song,
              index: index,
              isPlaying: isPlaying,
              onTap: () => _playSong(index),
            );
          },
        );
      },
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}
