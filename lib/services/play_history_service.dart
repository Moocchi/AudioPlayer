import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/song.dart';

/// Service to track play history and frequency
class PlayHistoryService extends ChangeNotifier {
  static final PlayHistoryService _instance = PlayHistoryService._internal();
  factory PlayHistoryService() => _instance;
  PlayHistoryService._internal();

  static const String _historyKey = 'play_history';
  static const String _albumsKey = 'recent_albums';
  static const int _maxHistorySongs = 20;
  static const int _maxAlbums = 18; // 9 albums x 2 slides

  // Play count map: songId -> playCount
  Map<String, int> _playCount = {};
  
  // Cached songs with their data (LIVE - updates constantly)
  List<Song> _frequentSongs = [];
  
  // Session snapshot of frequent songs (STABLE - only updates on app restart)
  List<Song> _sessionFrequentSongs = [];
  
  // Shuffled songs for Quick Shortcuts (randomized on init)
  List<Song> _shuffledSongs = [];
  
  // Recent albums: albumTitle -> albumCover
  List<Map<String, String>> _recentAlbums = [];

  // Return the SESSION snapshot so UI doesn't jump around
  List<Song> get frequentSongs => _sessionFrequentSongs;
  List<Song> get shuffledSongs => _shuffledSongs;
  List<Map<String, String>> get recentAlbums => _recentAlbums;

  /// Initialize service - load from storage
  Future<void> init() async {
    await _loadHistory();
    await _loadAlbums();
    
    // Initialize session snapshot once
    _sessionFrequentSongs = List.from(_frequentSongs);
  }

  /// Record a song play
  Future<void> recordPlay(Song song) async {
    // Update play count
    _playCount[song.id] = (_playCount[song.id] ?? 0) + 1;
    
    // Update frequent songs list (background only)
    _updateFrequentSongs(song);
    
    // Update recent albums
    _updateRecentAlbums(song);
    
    // Save to storage
    await _saveHistory();
    await _saveAlbums();
    
    // Notify listeners so UI updates (e.g. play counts if shown), 
    // but frequentSongs getter returns the stable list
    notifyListeners();
    debugPrint('📊 Recorded play: ${song.title} (count: ${_playCount[song.id]})');
  }

  void _updateFrequentSongs(Song song) {
    // Remove if exists
    _frequentSongs.removeWhere((s) => s.id == song.id);
    
    // Add to list
    _frequentSongs.add(song);
    
    // Sort by play count (highest first)
    _frequentSongs.sort((a, b) {
      final countA = _playCount[a.id] ?? 0;
      final countB = _playCount[b.id] ?? 0;
      return countB.compareTo(countA);
    });
    
    // Trim to max
    if (_frequentSongs.length > _maxHistorySongs) {
      _frequentSongs = _frequentSongs.sublist(0, _maxHistorySongs);
    }
  }

  void _updateRecentAlbums(Song song) {
    if (song.albumCover == null || song.albumTitle.isEmpty) return;
    
    final albumData = {
      'title': song.albumTitle,
      'cover': song.albumCover!,
      'artist': song.artist,
    };
    
    // Remove if exists
    _recentAlbums.removeWhere((a) => a['title'] == song.albumTitle);
    
    // Add to front
    _recentAlbums.insert(0, albumData);
    
    // Trim to max
    if (_recentAlbums.length > _maxAlbums) {
      _recentAlbums = _recentAlbums.sublist(0, _maxAlbums);
    }
  }

  Future<void> _loadHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Load play counts
      final countJson = prefs.getString('${_historyKey}_counts');
      if (countJson != null) {
        final Map<String, dynamic> decoded = json.decode(countJson);
        _playCount = decoded.map((k, v) => MapEntry(k, v as int));
      }
      
      // Load song data
      final songsJson = prefs.getString('${_historyKey}_songs');
      if (songsJson != null) {
        final List<dynamic> decoded = json.decode(songsJson);
        _frequentSongs = decoded.map((s) => Song.fromJson(s)).toList();
        
        // Sort by play count
        _frequentSongs.sort((a, b) {
          final countA = _playCount[a.id] ?? 0;
          final countB = _playCount[b.id] ?? 0;
          return countB.compareTo(countA);
        });
        
        // Create shuffled version for Quick Shortcuts
        _shuffleShortcuts();
      }
      
      debugPrint('📂 Loaded ${_frequentSongs.length} frequent songs');
    } catch (e) {
      debugPrint('❌ Error loading history: $e');
    }
  }
  
  /// Shuffle songs for Quick Shortcuts (called on init and can be refreshed)
  void _shuffleShortcuts() {
    _shuffledSongs = List<Song>.from(_frequentSongs);
    _shuffledSongs.shuffle(Random());
    // Take max 18 for 2 pages of 9
    if (_shuffledSongs.length > 18) {
      _shuffledSongs = _shuffledSongs.sublist(0, 18);
    }
  }
  
  /// Reshuffle Quick Shortcuts (call when user wants new random order)
  void reshuffleShortcuts() {
    _shuffleShortcuts();
    notifyListeners();
  }

  Future<void> _saveHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Save play counts
      await prefs.setString('${_historyKey}_counts', json.encode(_playCount));
      
      // Save song data
      final songsJson = _frequentSongs.map((s) => s.toJson()).toList();
      await prefs.setString('${_historyKey}_songs', json.encode(songsJson));
    } catch (e) {
      debugPrint('❌ Error saving history: $e');
    }
  }

  // --- Last Played Song Persistence ---

  static const String _lastSongKey = 'last_played_song';

  Future<void> saveLastPlayedSong(Song song) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lastSongKey, json.encode(song.toJson()));
    } catch (e) {
      debugPrint('❌ Error saving last song: $e');
    }
  }

  Future<Song?> getLastPlayedSong() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final songJson = prefs.getString(_lastSongKey);
      if (songJson != null) {
        return Song.fromJson(json.decode(songJson));
      }
    } catch (e) {
      debugPrint('❌ Error loading last song: $e');
    }
    return null;
  }

  Future<void> _loadAlbums() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final albumsJson = prefs.getString(_albumsKey);
      
      if (albumsJson != null) {
        final List<dynamic> decoded = json.decode(albumsJson);
        _recentAlbums = decoded.map((a) => Map<String, String>.from(a)).toList();
      }
      
      debugPrint('📂 Loaded ${_recentAlbums.length} recent albums');
    } catch (e) {
      debugPrint('❌ Error loading albums: $e');
    }
  }

  Future<void> _saveAlbums() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_albumsKey, json.encode(_recentAlbums));
    } catch (e) {
      debugPrint('❌ Error saving albums: $e');
    }
  }

  /// Get play count for a song
  int getPlayCount(String songId) => _playCount[songId] ?? 0;

  /// Clear all history
  Future<void> clearHistory() async {
    _playCount.clear();
    _frequentSongs.clear();
    _recentAlbums.clear();
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('${_historyKey}_counts');
    await prefs.remove('${_historyKey}_songs');
    await prefs.remove(_albumsKey);
    
    notifyListeners();
  }
}
