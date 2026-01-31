import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/song.dart';
import '../services/exoplayer_service.dart';
import '../services/play_history_service.dart';
import '../theme/app_theme.dart';
import '../widgets/mini_player.dart';
import '../widgets/hires_badge.dart';
import '../widgets/marquee_text.dart';
import '../widgets/marquee_text.dart';
import '../widgets/expandable_player.dart'; // New Import
import '../widgets/mini_equalizer.dart'; // New Import
import 'player_screen.dart';
import 'search_screen.dart';
import 'collection_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  final GlobalKey<ExpandablePlayerState> _playerKey = GlobalKey<ExpandablePlayerState>();
  final GlobalKey<NavigatorState> _collectionNavKey = GlobalKey<NavigatorState>();
  
  late final List<Widget> _screens = [
    const _HomeContent(),
    const SearchScreen(),
    Navigator(
      key: _collectionNavKey,
      onGenerateRoute: (settings) {
        return MaterialPageRoute(
          builder: (context) => const CollectionScreen(),
        );
      },
    ),
    const SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;

        // 1. Check player state (Expanded -> Collapse)
        final playerState = _playerKey.currentState;
        if (playerState != null && playerState.isExpanded) {
          playerState.collapse();
          return;
        }

        // 2. Check Nested Navigator (Collection Tab)
        if (_currentIndex == 2 && _collectionNavKey.currentState != null && _collectionNavKey.currentState!.canPop()) {
          _collectionNavKey.currentState!.pop();
          return;
        }

        // 3. If on other tabs, go back to Home first (optional standard behavior)
        if (_currentIndex != 0) {
          setState(() => _currentIndex = 0);
          return;
        }

        // Standard exit behavior
        SystemNavigator.pop();
      },
      child: Stack(
        children: [
          Scaffold(
            backgroundColor: AppTheme.background,
            body: IndexedStack(
              index: _currentIndex,
              children: _screens,
            ),
            bottomNavigationBar: _buildBottomNav(),
          ),
          ExpandablePlayer(key: _playerKey),
        ],
      ),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItem(0, Icons.home_outlined, Icons.home, 'Home'),
              _buildNavItem(1, Icons.search_outlined, Icons.search, 'Search'),
              _buildNavItem(2, Icons.library_music_outlined, Icons.library_music, 'Collection'),
              _buildNavItem(3, Icons.settings_outlined, Icons.settings, 'Settings'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, IconData activeIcon, String label) {
    final isActive = _currentIndex == index;
    return InkWell(
      onTap: () => setState(() => _currentIndex = index),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isActive ? activeIcon : icon,
              color: isActive ? AppTheme.primary : AppTheme.textSecondary,
              size: 24,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: isActive ? AppTheme.primary : AppTheme.textSecondary,
                fontSize: 12,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Home Content Widget
class _HomeContent extends StatefulWidget {
  const _HomeContent();

  @override
  State<_HomeContent> createState() => _HomeContentState();
}

class _HomeContentState extends State<_HomeContent> {
  final ExoPlayerService _audio = ExoPlayerService();
  final PlayHistoryService _history = PlayHistoryService();
  final PageController _albumPageController = PageController();
  int _currentAlbumPage = 0;

  @override
  void initState() {
    super.initState();
    _initHistory();
  }

  Future<void> _initHistory() async {
    await _history.init();
    if (mounted) setState(() {});
  }

  void _playSong(Song song, int index, List<Song> songs) {
    _audio.playQueue(songs, index);
    _history.recordPlay(song);
    // Navigation removed - ExpandablePlayer handles it
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(
          children: [
            // Header - only logo and app name
            _buildHeader(),
            
            // Content
            Expanded(
              child: ListenableBuilder(
                listenable: _history,
                builder: (context, _) {
                  return SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Quick Picks - frequently played songs
                        if (_history.frequentSongs.isNotEmpty)
                          _buildQuickPicks(),
                        
                        // Quick Shortcuts - random songs grid
                        if (_history.shuffledSongs.isNotEmpty)
                          _buildQuickShortcuts(),
                        
                        // Empty state if no history
                        if (_history.frequentSongs.isEmpty && _history.shuffledSongs.isEmpty)
                          _buildEmptyState(),
                        
                        const SizedBox(height: 100), // Space for mini player
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          // Logo
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: AppTheme.primaryGradient,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.music_note, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          // App name
          Text(
            'Iqbal Hires',
            style: AppTheme.heading2.copyWith(fontSize: 22),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickPicks() {
    final songs = _history.frequentSongs;
    
    // Calculate columns needed (4 rows per column, max 20 songs)
    final itemsPerColumn = 4;
    final totalColumns = (songs.length / itemsPerColumn).ceil();
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 16, top: 16, bottom: 8),
          child: Text(
            'Pilihan cepat',
            style: AppTheme.heading2.copyWith(fontSize: 20),
          ),
        ),
        SizedBox(
          height: 296, // Increased height for larger items (4 items * 74 height)
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.only(left: 16),
            itemCount: totalColumns,
            itemBuilder: (context, columnIndex) {
              return _buildQuickPickColumn(songs, columnIndex, itemsPerColumn);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildQuickPickColumn(List<Song> songs, int columnIndex, int itemsPerColumn) {
    final startIndex = columnIndex * itemsPerColumn;
    final endIndex = (startIndex + itemsPerColumn).clamp(0, songs.length);
    final columnSongs = songs.sublist(startIndex, endIndex);
    
    // Protect against negative width during layout transitions
    final screenWidth = MediaQuery.of(context).size.width;
    final cardWidth = (screenWidth - 48).clamp(0.0, double.infinity);

    return Container(
      width: cardWidth,
      margin: const EdgeInsets.only(right: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: columnSongs.asMap().entries.map((entry) {
          final index = startIndex + entry.key;
          final song = entry.value;
          return _buildQuickPickItem(song, index, songs);
        }).toList(),
      ),
    );
  }

  Widget _buildQuickPickItem(Song song, int index, List<Song> songs) {
    final isPlaying = _audio.currentSong?.id == song.id;
    
    return InkWell(
      onTap: () => _playSong(song, index, songs),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 72, // Increased item height
        padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 8), // More vertical padding
        child: Row(
          children: [
            // Album art
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6), // Slightly more rounded
                  child: song.albumCover != null
                      ? CachedNetworkImage(
                          imageUrl: song.albumCover!,
                          width: 56, // Increased Image size
                          height: 56,
                          fit: BoxFit.cover,
                          placeholder: (context, url) => Container(
                            width: 56,
                            height: 56,
                            color: AppTheme.divider,
                            child: const Icon(Icons.music_note, size: 24),
                          ),
                          errorWidget: (context, url, error) => Container(
                            width: 56,
                            height: 56,
                            color: AppTheme.divider,
                            child: const Icon(Icons.music_note, size: 24),
                          ),
                        )
                      : Container(
                          width: 56,
                          height: 56, // Increased size

                          color: AppTheme.divider,
                          child: const Icon(Icons.music_note, size: 20),
                        ),
                ),
                // Playing indicator
                // Playing indicator (Equalizer)
                // Playing indicator (Equalizer)
                if (isPlaying)
                  const Positioned(
                    right: 4,
                    bottom: 4,
                    child: MiniEqualizer(
                      size: 14,
                      color: Colors.white,
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 10),
            // Song info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Title with badge
                  Row(
                    children: [
                      Expanded(
                        child: MarqueeText(
                          text: song.title,
                          style: TextStyle(
                            color: isPlaying ? AppTheme.primary : AppTheme.textPrimary,
                            fontWeight: FontWeight.w500,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  // Artist and duration
                  Row(
                    children: [
                      if (song.isHiRes) ...[
                        const AnimatedHiResBadge(),
                        const SizedBox(width: 6),
                      ] else if (song.isLossless) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1DB954),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'Lossless',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Expanded(
                        child: Text(
                          song.artist,
                          style: AppTheme.caption.copyWith(fontSize: 12),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
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
            // More button
            IconButton(
              icon: const Icon(Icons.more_vert, size: 20),
              color: AppTheme.textSecondary,
              onPressed: () {
                // TODO: Show song options
              },
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickShortcuts() {
    final songs = _history.shuffledSongs;
    final totalPages = (songs.length / 9).ceil().clamp(1, 2);
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.only(left: 16, top: 16, bottom: 8),
          child: Text(
            'Pintasan cepat',
            style: AppTheme.heading2.copyWith(fontSize: 18),
          ),
        ),
        // Song grid pages
        SizedBox(
          height: 350,
          child: PageView.builder(
            controller: _albumPageController,
            itemCount: totalPages,
            onPageChanged: (page) {
              setState(() => _currentAlbumPage = page);
            },
            itemBuilder: (context, pageIndex) {
              final startIndex = pageIndex * 9;
              final endIndex = (startIndex + 9).clamp(0, songs.length);
              final pageSongs = songs.sublist(startIndex, endIndex);
              
              return _buildShortcutGrid(pageSongs);
            },
          ),
        ),
        // Page indicator
        if (totalPages > 1)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(totalPages, (index) {
                return Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _currentAlbumPage == index
                        ? AppTheme.primary
                        : AppTheme.divider,
                  ),
                );
              }),
            ),
          ),
      ],
    );
  }

  Widget _buildShortcutGrid(List<Song> songs) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          childAspectRatio: 1.0,
          crossAxisSpacing: 4,
          mainAxisSpacing: 4,
        ),
        itemCount: songs.length,
        itemBuilder: (context, index) {
          final song = songs[index];
          return _buildShortcutItem(song, index, songs);
        },
      ),
    );
  }

  Widget _buildShortcutItem(Song song, int index, List<Song> songs) {
    final isPlaying = _audio.currentSong?.id == song.id;
    
    return GestureDetector(
      onTap: () => _playSong(song, index, songs),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Album cover
            CachedNetworkImage(
              imageUrl: song.albumCover ?? '',
              fit: BoxFit.cover,
              placeholder: (context, url) => Container(
                color: AppTheme.divider,
                child: const Icon(Icons.music_note, size: 24),
              ),
              errorWidget: (context, url, error) => Container(
                color: AppTheme.divider,
                child: const Icon(Icons.music_note, size: 24),
              ),
            ),

            // Gradient overlay at bottom
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                height: 30,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withOpacity(0.85),
                    ],
                  ),
                ),
              ),
            ),
            // Song title inside
            Positioned(
              left: 4,
              right: 4,
              bottom: 4,
              child: MarqueeText(
                text: song.title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                  shadows: [
                    Shadow(
                      color: Colors.black,
                      blurRadius: 4,
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

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Center(
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
              'Welcome to Iqbal Hires',
              style: AppTheme.heading2,
            ),
            const SizedBox(height: 8),
            Text(
              'Search and play some songs to\nsee your quick picks here!',
              style: AppTheme.caption,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                // Navigate to search tab
                final homeState = context.findAncestorStateOfType<_HomeScreenState>();
                homeState?.setState(() => homeState._currentIndex = 1);
              },
              icon: const Icon(Icons.search),
              label: const Text('Start Searching'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _albumPageController.dispose();
    super.dispose();
  }
}
