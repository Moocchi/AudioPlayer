import 'package:flutter/foundation.dart';
import '../models/song.dart';

/// Global service to manage and access songs by ID
class SongService extends ChangeNotifier {
  static final SongService _instance = SongService._internal();
  factory SongService() => _instance;
  SongService._internal();

  final Map<String, Song> _songCache = {};

  /// Register songs to the cache
  void registerSongs(List<Song> songs) {
    for (var song in songs) {
      _songCache[song.id] = song;
    }
    notifyListeners();
  }

  /// Get a song by ID
  Song? getSongById(String id) {
    return _songCache[id];
  }

  /// Get multiple songs by IDs
  List<Song> getSongsByIds(List<String> ids) {
    return ids
        .map((id) => _songCache[id])
        .where((song) => song != null)
        .cast<Song>()
        .toList();
  }

  /// Get all songs
  List<Song> get allSongs => _songCache.values.toList();

  /// Clear cache (for testing)
  void clearCache() {
    _songCache.clear();
    notifyListeners();
  }
}
