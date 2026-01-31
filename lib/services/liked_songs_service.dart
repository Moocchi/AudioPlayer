import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/song.dart';

class LikedSongsService extends ChangeNotifier {
  static final LikedSongsService _instance = LikedSongsService._internal();
  factory LikedSongsService() => _instance;
  LikedSongsService._internal();

  static const String _likedSongsKey = 'liked_songs';

  List<Song> _likedSongs = [];

  List<Song> get likedSongs => _likedSongs;
  int get songCount => _likedSongs.length;

  /// Initialize service - load from storage
  Future<void> init() async {
    await _loadLikedSongs();
  }

  Future<void> _loadLikedSongs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? likedJson = prefs.getString(_likedSongsKey);
      if (likedJson != null) {
        final List<dynamic> decoded = json.decode(likedJson);
        _likedSongs = decoded.map((s) => Song.fromJson(s)).toList();
        // Add new songs to the top
        _likedSongs = _likedSongs.reversed.toList();
      }
      debugPrint('❤️ Loaded ${_likedSongs.length} liked songs');
    } catch (e) {
      debugPrint('❌ Error loading liked songs: $e');
    }
  }

  Future<void> _saveLikedSongs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Save in order of addition (newest last or first? usually list is storage). 
      // Let's store as is.
      final songsJson = _likedSongs.map((s) => s.toJson()).toList();
      await prefs.setString(_likedSongsKey, json.encode(songsJson));
    } catch (e) {
      debugPrint('❌ Error saving liked songs: $e');
    }
  }

  bool isLiked(String songId) {
    return _likedSongs.any((s) => s.id == songId);
  }

  Future<void> toggleLike(Song song) async {
    if (isLiked(song.id)) {
      _likedSongs.removeWhere((s) => s.id == song.id);
      debugPrint('💔 Unliked: ${song.title}');
    } else {
      // Add to beginning of list (newest first)
      _likedSongs.insert(0, song);
      debugPrint('❤️ Liked: ${song.title}');
    }
    
    notifyListeners();
    await _saveLikedSongs();
  }
}
