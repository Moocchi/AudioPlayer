import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/song.dart';
import '../services/exoplayer_service.dart';
import '../theme/app_theme.dart';
import '../widgets/cache_badge.dart';

class CachedSongsScreen extends StatefulWidget {
  const CachedSongsScreen({super.key});

  @override
  State<CachedSongsScreen> createState() => _CachedSongsScreenState();
}

class _CachedSongsScreenState extends State<CachedSongsScreen> {
  final ExoPlayerService _audio = ExoPlayerService();
  List<_CachedSongEntry> _entries = [];
  bool _isLoading = true;
  int _totalCachedBytes = 0;
  int _cacheSizeLimit = 1; // GB
  static const _cacheSizeKey = 'cache_size_limit_gb';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    if (mounted) setState(() => _isLoading = true);
    final prefs = await SharedPreferences.getInstance();
    _cacheSizeLimit = prefs.getInt(_cacheSizeKey) ?? 1;

    // Collect all unique song IDs from shared prefs keys
    final allKeys = prefs.getKeys();
    final songIds = <String>{};
    for (final key in allKeys) {
      if (key.startsWith('audio_full_cached_')) {
        songIds.add(key.replaceFirst('audio_full_cached_', ''));
      } else if (key.startsWith('song_catalog_')) {
        songIds.add(key.replaceFirst('song_catalog_', ''));
      } else if (key.startsWith('api_cache_')) {
        // format: api_cache_<id>_<quality>
        final withoutPrefix = key.replaceFirst('api_cache_', '');
        final parts = withoutPrefix.split('_');
        if (parts.isNotEmpty) songIds.add(parts[0]);
      }
    }

    final entries = <_CachedSongEntry>[];
    for (final songId in songIds) {
      final Song? song = _getSongFromPrefs(prefs, songId);
      if (song == null) continue;

      final isFullyCached = prefs.getBool('audio_full_cached_$songId') ?? false;
      final cachedBytes = await _audio.getAudioCachedBytes(songId);
      // Only show songs that actually have some audio cached
      if (cachedBytes == 0 && !isFullyCached) continue;

      entries.add(_CachedSongEntry(
        song: song,
        isFullyCached: isFullyCached,
        cachedBytes: cachedBytes,
      ));
    }

    entries.sort((a, b) {
      if (a.isFullyCached && !b.isFullyCached) return -1;
      if (!a.isFullyCached && b.isFullyCached) return 1;
      return b.cachedBytes.compareTo(a.cachedBytes);
    });

    final total = await _audio.getTotalCachedBytes();

    if (mounted) {
      setState(() {
        _entries = entries;
        _totalCachedBytes = total;
        _isLoading = false;
      });
    }
  }

  Song? _getSongFromPrefs(SharedPreferences prefs, String songId) {
    final catalogKey = 'song_catalog_$songId';
    String? catalogJson = prefs.getString(catalogKey);
    
    // Recovery Logic: If missing from catalog, search other metadata sources
    if (catalogJson == null) {
      debugPrint('🔍 Recovering metadata for $songId...');
      
      // Sources to check in priority order
      final sources = [
        'recent_songs',
        'play_history_songs',
        'liked_songs',
        'last_played_song'
      ];
      
      for (final sourceKey in sources) {
        final sourceJson = prefs.getString(sourceKey);
        if (sourceJson != null) {
          try {
            final dynamic decoded = jsonDecode(sourceJson);
            if (decoded is List) {
              // Search in list of songs
              final match = decoded.firstWhere(
                (s) => s['id'] == songId || s['id'].toString() == songId,
                orElse: () => null,
              );
              if (match != null) {
                catalogJson = jsonEncode(match);
                // Auto-save back to catalog for future performance
                prefs.setString(catalogKey, catalogJson);
                debugPrint('✅ Recovered $songId from $sourceKey');
                break;
              }
            } else if (decoded is Map && (decoded['id'] == songId || decoded['id'].toString() == songId)) {
              // Single song match (e.g. last_played_song)
              catalogJson = jsonEncode(decoded);
              prefs.setString(catalogKey, catalogJson);
              debugPrint('✅ Recovered $songId from $sourceKey');
              break;
            }
          } catch (e) {
            debugPrint('⚠️ Error decoding $sourceKey: $e');
          }
        }
      }
    }

    if (catalogJson == null) return null;
    try {
      return Song.fromJson(jsonDecode(catalogJson) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> _deleteSongCache(int index) async {
    final entry = _entries[index];
    final confirmed = await _showDeleteConfirm(entry.song.title);
    if (!confirmed) return;
    await _doDelete(index);
  }

  Future<void> _doDelete(int index) async {
    final entry = _entries[index];
    final song = entry.song;
    final prefs = await SharedPreferences.getInstance();
    
    // 1. Clear native audio cache
    await _audio.clearSongCache(song.id);
    
    // 2. Clear lyrics cache (using artist/title key format)
    final lyricsKey = '${song.artist.split(',').first.trim().toLowerCase()}_${song.title.toLowerCase()}';
    await prefs.remove('lyrics_plain_$lyricsKey');
    await prefs.remove('lyrics_sync_$lyricsKey');
    
    // 3. Clear cache flags and metadata
    await prefs.remove('audio_full_cached_${song.id}');
    await prefs.remove('api_cache_${song.id}_HI_RES_LOSSLESS');
    await prefs.remove('api_cache_${song.id}_LOSSLESS');
    await prefs.remove('song_catalog_${song.id}');
    
    if (mounted) setState(() => _entries.removeAt(index));
    await _refreshTotal();
    
    Fluttertoast.showToast(
      msg: 'Cache "${entry.song.title}" berhasil dihapus.',
      toastLength: Toast.LENGTH_SHORT,
      gravity: ToastGravity.BOTTOM,
    );
  }

  Future<void> _refreshTotal() async {
    final total = await _audio.getTotalCachedBytes();
    if (mounted) setState(() => _totalCachedBytes = total);
  }

  Future<bool> _showDeleteConfirm(String title) async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppTheme.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('Remove from Cache?',
                style: TextStyle(color: AppTheme.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
            content: Text(
              '"$title" cache will be removed.\nIt will need to be downloaded again when played.',
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14, height: 1.4),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('Cancel', style: TextStyle(color: AppTheme.textSecondary)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Remove', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ) ??
        false;
  }

  void _showCacheSettings() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _CacheSettingsSheet(
        currentLimitGb: _cacheSizeLimit,
        totalCachedBytes: _totalCachedBytes,
        onSizeChanged: (gb) async {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setInt(_cacheSizeKey, gb);
          final bytes = gb * 1024 * 1024 * 1024;
          await _audio.setCacheSize(bytes);
          if (mounted) setState(() => _cacheSizeLimit = gb);
        },
        onClearAll: () async {
          Navigator.pop(ctx);
          final confirmed = await _showClearAllConfirm();
          if (!confirmed) return;
          final prefs = await SharedPreferences.getInstance();
          await _audio.clearAllCache();
          final keys = prefs.getKeys().toList();
          for (final k in keys) {
            if (k.startsWith('audio_full_cached_') ||
                k.startsWith('api_cache_') ||
                k.startsWith('lyrics_plain_') ||
                k.startsWith('lyrics_sync_') ||
                k.startsWith('song_catalog_')) {
              await prefs.remove(k);
            }
          }
          await _loadData();
          Fluttertoast.showToast(
            msg: 'Semua cache berhasil dihapus.',
            toastLength: Toast.LENGTH_SHORT,
            gravity: ToastGravity.BOTTOM,
          );
        },
      ),
    );
  }

  Future<bool> _showClearAllConfirm() async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppTheme.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('Clear All Cache?',
                style: TextStyle(color: AppTheme.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
            content: const Text(
              'All audio cache, lyrics, and metadata will be removed.\nAll songs will need to be redownloaded.',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 14, height: 1.4),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('Cancel', style: TextStyle(color: AppTheme.textSecondary)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Clear All',
                    style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ) ??
        false;
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadData,
          color: AppTheme.primary,
          backgroundColor: AppTheme.surface,
          strokeWidth: 2.5,
          displacement: 16,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              // ── Header ──────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back, color: AppTheme.textPrimary),
                        onPressed: () => Navigator.pop(context),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Cached Songs', style: AppTheme.heading2.copyWith(fontSize: 20)),
                            if (!_isLoading)
                              Text(
                                '${_entries.length} songs · ${_formatBytes(_totalCachedBytes)} used',
                                style: AppTheme.caption.copyWith(fontSize: 11),
                              ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.more_vert, color: AppTheme.textPrimary),
                        onPressed: _showCacheSettings,
                      ),
                    ],
                  ),
                ),
              ),

              // ── Storage bar ─────────────────────────────────
              if (!_isLoading) SliverToBoxAdapter(child: _buildStorageBar()),

              // ── Divider ─────────────────────────────────────
              SliverToBoxAdapter(
                child: Divider(color: AppTheme.divider.withOpacity(0.5), height: 1),
              ),

              // ── Content ─────────────────────────────────────
              if (_isLoading)
                const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator(color: AppTheme.primary)),
                )
              else if (_entries.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _buildEmptyState(),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.only(bottom: 100, top: 4),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (ctx, i) => _buildSongTile(i),
                      childCount: _entries.length,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStorageBar() {

    final limitBytes = _cacheSizeLimit * 1024 * 1024 * 1024;
    final progress = (_totalCachedBytes / limitBytes).clamp(0.0, 1.0);
    // Format: "500 MB / 2 GB" or "1.23 GB / 3 GB"
    final usedStr = _totalCachedBytes < 1024 * 1024 * 1024
        ? '${(_totalCachedBytes / (1024 * 1024)).toStringAsFixed(0)} MB'
        : '${(_totalCachedBytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    final pct = '${(progress * 100).toStringAsFixed(0)}%';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Cache Storage', style: AppTheme.caption.copyWith(fontSize: 11)),
              Text(
                '$usedStr / ${_cacheSizeLimit} GB  ($pct)',
                style: AppTheme.caption.copyWith(
                    fontSize: 11, color: progress > 0.85 ? Colors.orange : AppTheme.primary),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: AppTheme.divider,
              valueColor: AlwaysStoppedAnimation<Color>(
                progress > 0.85 ? Colors.orange : AppTheme.primary,
              ),
              minHeight: 5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSongTile(int index) {
    final entry = _entries[index];
    final song = entry.song;
    return Dismissible(
      key: Key('cached_${song.id}_$index'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => _showDeleteConfirm(song.title),
      onDismissed: (_) => _doDelete(index),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.red.withOpacity(0.85),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.delete_outline, color: Colors.white, size: 24),
            SizedBox(height: 2),
            Text('Delete', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.divider.withOpacity(0.4), width: 0.5),
        ),
        child: Row(
          children: [
            // Album art with badge
            CacheBadge(
              song: song,
              size: 8,
              top: 4,
              right: 4,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: song.albumCover != null
                    ? CachedNetworkImage(
                        imageUrl: song.albumCover!,
                        width: 52,
                        height: 52,
                        fit: BoxFit.cover,
                        placeholder: (_, __) =>
                            Container(width: 52, height: 52, color: AppTheme.divider),
                        errorWidget: (_, __, ___) => Container(
                          width: 52,
                          height: 52,
                          color: AppTheme.divider,
                          child: const Icon(Icons.music_note, color: AppTheme.textSecondary, size: 22),
                        ),
                      )
                    : Container(
                        width: 52,
                        height: 52,
                        color: AppTheme.divider,
                        child: const Icon(Icons.music_note, color: AppTheme.textSecondary, size: 22),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    song.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.caption.copyWith(fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // Stats on the right
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _StatusBadge(isFullyCached: entry.isFullyCached),
                const SizedBox(height: 4),
                Text(
                  _formatBytes(entry.cachedBytes),
                  style: AppTheme.caption.copyWith(fontSize: 11),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.storage_outlined, size: 72, color: AppTheme.textSecondary.withOpacity(0.3)),
          const SizedBox(height: 16),
          Text('No cached songs yet',
              style: AppTheme.heading2.copyWith(color: AppTheme.textSecondary, fontSize: 16)),
          const SizedBox(height: 8),
          const Text(
            'Play songs to their end to\nsave them fully in the cache',
            style: AppTheme.caption,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// Data model for a cached song entry
class _CachedSongEntry {
  final Song song;
  final bool isFullyCached;
  final int cachedBytes;

  const _CachedSongEntry({
    required this.song,
    required this.isFullyCached,
    required this.cachedBytes,
  });
}

class _StatusBadge extends StatelessWidget {
  final bool isFullyCached;
  const _StatusBadge({required this.isFullyCached});

  @override
  Widget build(BuildContext context) {
    return Text(
      isFullyCached ? 'Full Cache' : 'Partial',
      style: TextStyle(
        color: isFullyCached ? const Color(0xFF00FF41) : Colors.orange,
        fontSize: 11,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

// ─── Cache Settings Bottom Sheet ───────────────────────────────────────────────
class _CacheSettingsSheet extends StatefulWidget {
  final int currentLimitGb;
  final int totalCachedBytes;
  final void Function(int gb) onSizeChanged;
  final VoidCallback onClearAll;

  const _CacheSettingsSheet({
    required this.currentLimitGb,
    required this.totalCachedBytes,
    required this.onSizeChanged,
    required this.onClearAll,
  });

  @override
  State<_CacheSettingsSheet> createState() => _CacheSettingsSheetState();
}

class _CacheSettingsSheetState extends State<_CacheSettingsSheet> {
  late int _selectedGb;

  @override
  void initState() {
    super.initState();
    _selectedGb = widget.currentLimitGb.clamp(1, 3);
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).padding.bottom + 24,
      ),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: AppTheme.divider, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 20),

          Row(
            children: [
              const Icon(Icons.storage_outlined, color: AppTheme.primary, size: 22),
              const SizedBox(width: 10),
              Text('Cache Settings', style: AppTheme.heading2.copyWith(fontSize: 18)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Used: ${_formatBytes(widget.totalCachedBytes)}',
            style: AppTheme.caption.copyWith(fontSize: 13),
          ),

          const SizedBox(height: 24),

          Text('Cache size limit', style: AppTheme.body.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(
            'When full, the oldest songs are automatically removed',
            style: AppTheme.caption.copyWith(fontSize: 12),
          ),
          const SizedBox(height: 14),

          Row(
            children: [1, 2, 3].map((gb) {
              final selected = _selectedGb == gb;
              return Expanded(
                child: GestureDetector(
                  onTap: () {
                    setState(() => _selectedGb = gb);
                    widget.onSizeChanged(gb);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    height: 56,
                    decoration: BoxDecoration(
                      color: selected ? AppTheme.primary.withOpacity(0.12) : AppTheme.background,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: selected ? AppTheme.primary : AppTheme.divider,
                        width: selected ? 1.5 : 0.8,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '$gb GB',
                          style: TextStyle(
                            color: selected ? AppTheme.primary : AppTheme.textSecondary,
                            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                            fontSize: 18,
                          ),
                        ),
                        Text(
                          ['~20 lagu', '~40 lagu', '~60 lagu'][gb - 1],
                          style: TextStyle(
                            color: selected
                                ? AppTheme.primary.withOpacity(0.7)
                                : AppTheme.textSecondary.withOpacity(0.5),
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 28),

          Material(
            color: Colors.red.withOpacity(0.08),
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: widget.onClearAll,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 15),
                alignment: Alignment.center,
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.delete_sweep_outlined, color: Colors.red, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Clear All Cache',
                      style: TextStyle(
                          color: Colors.red, fontWeight: FontWeight.w600, fontSize: 15),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
