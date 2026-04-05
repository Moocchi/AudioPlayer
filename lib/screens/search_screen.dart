import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/song.dart';
import '../services/api_service.dart';
import '../services/exoplayer_service.dart';
import '../services/play_history_service.dart';
import '../theme/app_theme.dart';
import '../widgets/hires_badge.dart';
import '../widgets/song_menu_sheet.dart';
import '../widgets/mini_equalizer.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => SearchScreenState();
}

class SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();

  /// Returns true if back was handled (search cleared), false if not
  bool handleBack() {
    if (_hasSearched) {
      _searchController.clear();
      setState(() {
        _songs = [];
        _hasSearched = false;
        _lastQuery = '';
      });
      return true;
    }
    return false;
  }

  final FocusNode _searchFocus = FocusNode();
  final ExoPlayerService _audio = ExoPlayerService();
  final PlayHistoryService _history = PlayHistoryService();
  List<Song> _songs = [];
  bool _isLoading = false;
  bool _hasSearched = false;
  Timer? _debounce;
  List<String> _searchHistory = [];
  String _lastQuery = '';

  static const String _historyKey = 'search_history';
  static const int _maxHistory = 100;

  @override
  void initState() {
    super.initState();
    _loadSearchHistory();
  }

  Future<void> _loadSearchHistory() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _searchHistory = prefs.getStringList(_historyKey) ?? [];
    });
  }

  Future<void> _addToHistory(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    // Remove if already exists (to move to top)
    _searchHistory.remove(trimmed);
    // Add to front
    _searchHistory.insert(0, trimmed);
    // Cap at max
    if (_searchHistory.length > _maxHistory) {
      _searchHistory = _searchHistory.sublist(0, _maxHistory);
    }
    setState(() {});
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_historyKey, _searchHistory);
  }

  Future<void> _removeFromHistory(String query) async {
    _searchHistory.remove(query);
    setState(() {});
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_historyKey, _searchHistory);
  }

  void _showDeleteHistoryDialog(String query) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Hapus "$query" dari penelusuran?',
          style: const TextStyle(color: AppTheme.textPrimary, fontSize: 16),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Batal',
              style: TextStyle(color: AppTheme.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _removeFromHistory(query);
            },
            child: Text('Hapus', style: TextStyle(color: AppTheme.primary)),
          ),
        ],
      ),
    );
  }

  Future<void> _clearAllHistory() async {
    _searchHistory.clear();
    setState(() {});
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_historyKey);
  }

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
      _lastQuery = query.trim();
    });
  }

  void _playSong(int index) {
    FocusScope.of(context).unfocus(); // Dismiss keyboard
    final song = _songs[index];
    // Queue only the selected song
    _audio.playQueue([song], 0, userInitiated: true);
    _history.recordPlay(song);
    _history.addRecentSong(song);
  }

  void _onHistoryTap(String query) {
    _searchController.text = query;
    _searchController.selection = TextSelection.fromPosition(
      TextPosition(offset: query.length),
    );
    _addToHistory(query);
    _search(query);
  }

  /// Fill the search bar with history text (arrow icon tap)
  void _onHistoryFill(String query) {
    _searchController.text = query;
    _searchController.selection = TextSelection.fromPosition(
      TextPosition(offset: query.length),
    );
    _searchFocus.requestFocus();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(
          children: [
            // YTM-style search bar
            _buildSearchBar(),

            // Content
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: AppTheme.primary),
                    )
                  : _hasSearched
                  ? _buildSearchResults()
                  : _buildSearchHistory(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(28),
        ),
        child: Row(
          children: [
            // Search icon
            const Padding(
              padding: EdgeInsets.only(left: 14),
              child: Icon(
                Icons.search,
                color: AppTheme.textSecondary,
                size: 22,
              ),
            ),
            // Input
            Expanded(
              child: TextField(
                controller: _searchController,
                focusNode: _searchFocus,
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 16,
                ),
                decoration: const InputDecoration(
                  hintText: 'Search songs, artists...',
                  hintStyle: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 16,
                  ),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 14,
                  ),
                ),
                onSubmitted: (value) {
                  _addToHistory(value);
                  if (value.trim() != _lastQuery) {
                    _search(value);
                  }
                },
                onChanged: (value) {
                  setState(() {});
                  _debounce?.cancel();
                  if (value.trim().isEmpty) {
                    setState(() {
                      _songs = [];
                      _hasSearched = false;
                    });
                    return;
                  }
                  _debounce = Timer(const Duration(milliseconds: 100), () {
                    _search(value);
                  });
                },
              ),
            ),
            // Clear button
            if (_searchController.text.isNotEmpty)
              IconButton(
                icon: const Icon(
                  Icons.close,
                  color: AppTheme.textSecondary,
                  size: 20,
                ),
                onPressed: () {
                  _searchController.clear();
                  setState(() {
                    _songs = [];
                    _hasSearched = false;
                  });
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentSongsSection() {
    return ListenableBuilder(
      listenable: _history,
      builder: (context, _) {
        final recentSongs = _history.recentSongs;
        if (recentSongs.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Text(
                'Recently played',
                style: AppTheme.body.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textSecondary,
                ),
              ),
            ),
            SizedBox(
              height: 108,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: recentSongs.length,
                itemBuilder: (context, index) {
                  final song = recentSongs[index];
                  return _buildRecentSongItem(song, index);
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildRecentSongItem(Song song, int index) {
    return _ScaleButton(
      onTap: () {
        // Queue only this song
        _audio.playQueue([song], 0, userInitiated: true);
        _history.recordPlay(song);
        _history.addRecentSong(song);
      },
      onLongPress: () {
        SongMenuSheet.show(
          context,
          song,
          onRemoveFromHistory: () {
            _history.removeRecentSong(song.id);
          },
        );
      },
      child: Container(
        width: 74,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Album art
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: song.albumCover != null
                  ? CachedNetworkImage(
                      imageUrl: song.albumCover!,
                      width: 70,
                      height: 70,
                      memCacheWidth: 210,
                      maxWidthDiskCache: 210,
                      fadeInDuration: Duration.zero,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(
                        width: 70,
                        height: 70,
                        color: AppTheme.divider,
                      ),
                      errorWidget: (_, __, ___) => Container(
                        width: 70,
                        height: 70,
                        color: AppTheme.divider,
                        child: const Icon(
                          Icons.music_note,
                          color: Colors.white54,
                          size: 24,
                        ),
                      ),
                    )
                  : Container(
                      width: 70,
                      height: 70,
                      color: AppTheme.divider,
                      child: const Icon(
                        Icons.music_note,
                        color: Colors.white54,
                        size: 24,
                      ),
                    ),
            ),
            const SizedBox(height: 4),
            // Song title
            Text(
              song.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchHistory() {
    final hasRecentSongs = _history.recentSongs.isNotEmpty;
    final hasSearchHistory = _searchHistory.isNotEmpty;

    if (!hasRecentSongs && !hasSearchHistory) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search,
              size: 64,
              color: AppTheme.textSecondary.withOpacity(0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'Search for music',
              style: AppTheme.heading2.copyWith(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 8),
            const Text(
              'Find your favorite songs, artists, and albums',
              style: AppTheme.caption,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      children: [
        // Recent songs horizontal section
        _buildRecentSongsSection(),

        // Header: "Search history" + Clear all
        if (hasSearchHistory) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 8, 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Search history',
                  style: AppTheme.body.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textSecondary,
                  ),
                ),
                TextButton(
                  onPressed: _clearAllHistory,
                  child: Text(
                    'Clear all',
                    style: TextStyle(
                      color: AppTheme.primary,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // History items
          ..._searchHistory.map((query) => _buildHistoryItem(query)),
        ],
        const SizedBox(height: 100),
      ],
    );
  }

  Widget _buildHistoryItem(String query) {
    return Dismissible(
      key: Key('history_$query'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: Colors.red.withOpacity(0.2),
        child: const Icon(Icons.delete, color: Colors.red),
      ),
      onDismissed: (_) => _removeFromHistory(query),
      child: InkWell(
        onTap: () => _onHistoryTap(query),
        onLongPress: () => _showDeleteHistoryDialog(query),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              // Clock icon
              const Icon(
                Icons.history,
                color: AppTheme.textSecondary,
                size: 20,
              ),
              const SizedBox(width: 16),
              // Query text
              Expanded(
                child: Text(
                  query,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 14,
                  ),
                ),
              ),
              // Arrow fill icon (fills search bar)
              IconButton(
                icon: const Icon(
                  Icons.north_west,
                  color: AppTheme.textSecondary,
                  size: 18,
                ),
                onPressed: () => _onHistoryFill(query),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchResults() {
    if (_songs.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_off,
              size: 64,
              color: AppTheme.textSecondary.withOpacity(0.5),
            ),
            const SizedBox(height: 16),
            const Text('No results found', style: AppTheme.caption),
          ],
        ),
      );
    }

    return ListenableBuilder(
      listenable: _audio,
      builder: (context, _) {
        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: _songs.length,
          itemBuilder: (context, index) {
            final song = _songs[index];
            final isPlaying = _audio.currentSong?.id == song.id;

            return _buildSongItem(song, index, isPlaying);
          },
        );
      },
    );
  }

  Widget _buildSongItem(Song song, int index, bool isPlaying) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () => _playSong(index),
        onLongPress: () {
          SongMenuSheet.show(context, song);
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.only(left: 8, right: 0, top: 8, bottom: 8),
          child: Row(
            children: [
              // Album Art (48x48)
              Stack(
                children: [
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
                              child: Icon(
                                Icons.music_note,
                                color: Colors.white54,
                              ),
                            ),
                          )
                        : const SizedBox(
                            width: 48,
                            height: 48,
                            child: Icon(
                              Icons.music_note,
                              color: Colors.white54,
                            ),
                          ),
                  ),
                  if (isPlaying)
                    const Positioned(
                      right: 3,
                      bottom: 3,
                      child: MiniEqualizer(size: 14, color: Colors.white),
                    ),
                ],
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
                        fontSize: 14,
                        color: isPlaying ? AppTheme.primary : null,
                      ),
                    ),
                    const SizedBox(height: 4),
                    // Subtitle (Badges + Artist + Duration)
                    Row(
                      children: [
                        // Badges
                        if (song.isHiRes) ...{
                          const AnimatedHiResBadge(),
                          const SizedBox(width: 6),
                        } else if (song.isLossless) ...{
                          const LosslessBadge(),
                          const SizedBox(width: 6),
                        },
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
                  SongMenuSheet.show(context, song);
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

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    _debounce?.cancel();
    super.dispose();
  }
}

class _ScaleButton extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _ScaleButton({
    required this.child,
    required this.onTap,
    this.onLongPress,
  });

  @override
  State<_ScaleButton> createState() => _ScaleButtonState();
}

class _ScaleButtonState extends State<_ScaleButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
      lowerBound: 0.0,
      upperBound: 0.05, // Scale down by 5% (to 0.95)
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.95,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) {
        _controller.reverse();
        widget.onTap();
      },
      onTapCancel: () => _controller.reverse(),
      onLongPress: () {
        _controller.reverse(); // Bounce back when long press triggers
        widget.onLongPress?.call();
      },
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) =>
            Transform.scale(scale: 1.0 - _controller.value, child: child),
        child: widget.child,
      ),
    );
  }
}
