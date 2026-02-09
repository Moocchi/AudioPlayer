import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:palette_generator/palette_generator.dart';
import '../models/song.dart';
import '../models/gradient_config.dart';

class LikedSongsService extends ChangeNotifier {
  static final LikedSongsService _instance = LikedSongsService._internal();
  factory LikedSongsService() => _instance;
  LikedSongsService._internal();

  static const String _likedSongsKey = 'liked_songs';
  static const String _likedSongsCoverKey = 'liked_songs_cover';
  static const String _likedSongsColorKey = 'liked_songs_color';
  static const String _gradientConfigKey = 'liked_songs_gradient_config';

  String? _playlistCoverPath;
  int? _dominantColorValue;
  GradientConfig _gradientConfig = const GradientConfig.auto();

  String? get playlistCoverPath => _playlistCoverPath;
  Color? get dominantColor =>
      _dominantColorValue != null ? Color(_dominantColorValue!) : null;
  GradientConfig get gradientConfig => _gradientConfig;

  List<Song> _likedSongs = [];

  List<Song> get likedSongs => _likedSongs;
  int get songCount => _likedSongs.length;

  /// Initialize service - load from storage
  Future<void> init() async {
    await _loadLikedSongs();
    await _loadCoverPath();
    await _loadDominantColor();
    await _loadGradientConfig();
  }

  Future<void> _loadDominantColor() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _dominantColorValue = prefs.getInt(_likedSongsColorKey);
    } catch (e) {
      debugPrint('❌ Error loading dominant color: $e');
    }
  }

  Future<void> _loadCoverPath() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _playlistCoverPath = prefs.getString(_likedSongsCoverKey);
    } catch (e) {
      debugPrint('❌ Error loading cover path: $e');
    }
  }

  Future<void> _loadGradientConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_gradientConfigKey);
      if (jsonStr != null) {
        _gradientConfig = GradientConfig.fromJson(json.decode(jsonStr));
      }
    } catch (e) {
      debugPrint('❌ Error loading gradient config: $e');
    }
  }

  Future<void> setPlaylistCover(
    String path, {
    GradientConfig? gradientConfig,
  }) async {
    _playlistCoverPath = path;
    if (gradientConfig != null) {
      _gradientConfig = gradientConfig;
    }

    // Generate Palette
    try {
      final palette = await PaletteGenerator.fromImageProvider(
        FileImage(File(path)),
        maximumColorCount: 20,
        size: const Size(100, 100), // Optimize: Resize for performance
      );
      if (palette.dominantColor != null) {
        _dominantColorValue = palette.dominantColor!.color.toARGB32();
      }
    } catch (e) {
      debugPrint('❌ Error generating palette in service: $e');
    }

    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_likedSongsCoverKey, path);
      if (_dominantColorValue != null) {
        await prefs.setInt(_likedSongsColorKey, _dominantColorValue!);
      }
      // Save gradient config
      await prefs.setString(
        _gradientConfigKey,
        json.encode(_gradientConfig.toJson()),
      );
    } catch (e) {
      debugPrint('❌ Error saving cover info: $e');
    }
  }

  /// Get gradient colors based on config
  List<Color> getGradientColors() {
    if (_gradientConfig.type == GradientType.custom &&
        _gradientConfig.color1 != null &&
        _gradientConfig.color2 != null) {
      return [_gradientConfig.color1!, _gradientConfig.color2!];
    }
    // Auto: use top 2 colors from last generated palette, or fallback
    return [
      dominantColor ?? const Color(0xFFFF6B35),
      const Color(0xFF121212), // Background
    ];
  }

  Future<void> _loadLikedSongs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? likedJson = prefs.getString(_likedSongsKey);
      if (likedJson != null) {
        final List<dynamic> decoded = json.decode(likedJson);
        _likedSongs = decoded.map((s) => Song.fromJson(s)).toList();
        // Remove reversed to keep original order (Oldest First / Append Mode)
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
      // Add to end of list (append)
      _likedSongs.add(song);
      debugPrint('❤️ Liked: ${song.title}');
    }

    notifyListeners();
    await _saveLikedSongs();
  }
}
