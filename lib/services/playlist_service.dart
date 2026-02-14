import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import '../models/playlist.dart';
import '../models/gradient_config.dart';

class PlaylistService extends ChangeNotifier {
  static final PlaylistService _instance = PlaylistService._internal();
  factory PlaylistService() => _instance;
  PlaylistService._internal();

  static const String _playlistsKey = 'user_playlists';

  List<Playlist> _playlists = [];

  List<Playlist> get playlists => _playlists;

  /// Initialize service
  Future<void> init() async {
    await _loadPlaylists();
  }

  Future<void> _loadPlaylists() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? playlistsJson = prefs.getString(_playlistsKey);
      if (playlistsJson != null) {
        final List<dynamic> decoded = json.decode(playlistsJson);
        _playlists = decoded.map((p) => Playlist.fromJson(p)).toList();
        debugPrint('📋 Loaded ${_playlists.length} playlists');
      }
    } catch (e) {
      debugPrint('❌ Error loading playlists: $e');
    }
  }

  Future<void> _savePlaylists() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final playlistsJson = _playlists.map((p) => p.toJson()).toList();
      await prefs.setString(_playlistsKey, json.encode(playlistsJson));
    } catch (e) {
      debugPrint('❌ Error saving playlists: $e');
    }
  }

  /// Create new playlist
  Future<Playlist?> createPlaylist(String name) async {
    if (_playlists.length >= 20) {
      debugPrint('⚠️ Playlist limit reached (20)');
      return null;
    }
    final playlist = Playlist(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      songIds: [],
      createdAt: DateTime.now(),
    );
    _playlists.add(playlist);
    notifyListeners();
    await _savePlaylists();
    debugPrint('✅ Created playlist: $name');
    return playlist;
  }

  /// Add song to playlist
  Future<void> addSongToPlaylist(String playlistId, String songId) async {
    final index = _playlists.indexWhere((p) => p.id == playlistId);
    if (index != -1) {
      _playlists[index] = _playlists[index].addSong(songId);
      notifyListeners();
      await _savePlaylists();
      debugPrint('✅ Added song to ${_playlists[index].name}');
    }
  }

  /// Remove song from playlist
  Future<void> removeSongFromPlaylist(String playlistId, String songId) async {
    final index = _playlists.indexWhere((p) => p.id == playlistId);
    if (index != -1) {
      _playlists[index] = _playlists[index].removeSong(songId);
      notifyListeners();
      await _savePlaylists();
    }
  }

  /// Delete playlist
  Future<void> deletePlaylist(String playlistId) async {
    _playlists.removeWhere((p) => p.id == playlistId);
    notifyListeners();
    await _savePlaylists();
  }

  /// Rename playlist
  Future<void> renamePlaylist(String playlistId, String newName) async {
    final index = _playlists.indexWhere((p) => p.id == playlistId);
    if (index != -1) {
      _playlists[index] = _playlists[index].copyWith(name: newName);
      notifyListeners();
      await _savePlaylists();
    }
  }

  /// Reorder playlists
  Future<void> reorderPlaylists(
    int oldIndex,
    int newIndex, {
    bool adjustIndex = true,
  }) async {
    if (adjustIndex && oldIndex < newIndex) {
      newIndex -= 1;
    }
    final Playlist item = _playlists.removeAt(oldIndex);
    _playlists.insert(newIndex, item);
    notifyListeners();
    await _savePlaylists();
  }

  /// Reorder by IDs (safer for ReorderableBuilder)
  Future<void> reorderPlaylistsByOrderedIds(List<String> orderedIds) async {
    final Map<String, Playlist> playlistMap = {
      for (var p in _playlists) p.id: p,
    };
    final List<Playlist> newOrder = [];
    for (var id in orderedIds) {
      if (playlistMap.containsKey(id)) {
        newOrder.add(playlistMap[id]!);
      }
    }
    // append any missing (fallback)
    for (var p in _playlists) {
      if (!newOrder.any((np) => np.id == p.id)) {
        newOrder.add(p);
      }
    }
    _playlists = newOrder;
    notifyListeners();
    await _savePlaylists();
  }

  /// Update entire playlist list (for ReorderableBuilder)
  Future<void> setPlaylists(List<Playlist> newPlaylists) async {
    _playlists = newPlaylists;
    notifyListeners();
    await _savePlaylists();
  }

  /// Check if song is in playlist
  bool isSongInPlaylist(String playlistId, String songId) {
    final playlist = _playlists.firstWhere(
      (p) => p.id == playlistId,
      orElse: () =>
          Playlist(id: '', name: '', songIds: [], createdAt: DateTime.now()),
    );
    return playlist.songIds.contains(songId);
  }

  /// Set playlist cover image and gradient
  Future<void> setPlaylistCover(
    String playlistId,
    String imagePath, {
    GradientConfig? gradientConfig,
  }) async {
    final index = _playlists.indexWhere((p) => p.id == playlistId);
    if (index == -1) return;

    // Get app directory
    final appDir = await getApplicationDocumentsDirectory();
    final playlistCoversDir = Directory('${appDir.path}/playlist_covers');
    if (!await playlistCoversDir.exists()) {
      await playlistCoversDir.create(recursive: true);
    }

    // Fix: Use unique filename with timestamp to force UI update (cache busting)
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final fileName = 'playlist_${playlistId}_$timestamp.jpg';
    final savedImagePath = '${playlistCoversDir.path}/$fileName';

    // Copy new image
    await File(imagePath).copy(savedImagePath);

    // Delete old image if it exists to save space
    final oldPath = _playlists[index].coverPath;
    if (oldPath != null && oldPath != savedImagePath) {
      final oldFile = File(oldPath);
      if (await oldFile.exists()) {
        try {
          await oldFile.delete();
        } catch (e) {
          debugPrint('Could not delete old cover: $e');
        }
      }
    }

    // Update playlist with NEW path
    _playlists[index] = _playlists[index].copyWith(
      coverPath: savedImagePath,
      gradientConfig: gradientConfig,
    );

    // No need to evict manually anymore since path changed!
    notifyListeners();
    await _savePlaylists();
    debugPrint('✅ Set cover for ${_playlists[index].name} (v$timestamp)');
  }

  /// Remove playlist cover
  Future<void> removePlaylistCover(String playlistId) async {
    final index = _playlists.indexWhere((p) => p.id == playlistId);
    if (index == -1) return;

    final coverPath = _playlists[index].coverPath;
    if (coverPath != null) {
      // Delete image file
      try {
        final file = File(coverPath);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (e) {
        debugPrint('Error deleting cover: $e');
      }
    }

    // Update playlist
    _playlists[index] = _playlists[index].copyWith(
      coverPath: null,
      gradientConfig: null,
    );

    notifyListeners();
    await _savePlaylists();
  }
}
