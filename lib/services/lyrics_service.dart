import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class LyricLine {
  final Duration timestamp;
  final String text;

  LyricLine({required this.timestamp, required this.text});

  @override
  String toString() => '[${timestamp.inMilliseconds}ms] $text';
}

class LyricsResult {
  final List<LyricLine> syncedLyrics;
  final String? plainLyrics;
  final bool hasSyncedLyrics;

  LyricsResult({
    required this.syncedLyrics,
    this.plainLyrics,
  }) : hasSyncedLyrics = syncedLyrics.isNotEmpty;
}

class LyricsService {
  static final LyricsService _instance = LyricsService._internal();
  factory LyricsService() => _instance;
  LyricsService._internal();

  // Cache lyrics by "artist - title" key
  final Map<String, LyricsResult?> _cache = {};

  /// Fetch lyrics from lrclib.net
  Future<LyricsResult?> fetchLyrics({
    required String title,
    required String artist,
    String? albumName,
    int? durationSeconds,
  }) async {
    final cacheKey = '${artist.toLowerCase()}_${title.toLowerCase()}';

    // Return cached result
    if (_cache.containsKey(cacheKey)) {
      return _cache[cacheKey];
    }

    try {
      // First try the /api/get endpoint with exact metadata
      LyricsResult? result;
      
      if (durationSeconds != null && durationSeconds > 0) {
        result = await _fetchWithGet(
          title: title,
          artist: artist,
          albumName: albumName ?? '',
          duration: durationSeconds,
        );
      }

      // Fallback: search endpoint
      if (result == null) {
        result = await _fetchWithSearch(title: title, artist: artist);
      }

      _cache[cacheKey] = result;
      return result;
    } catch (e) {
      debugPrint('❌ Lyrics fetch error: $e');
      _cache[cacheKey] = null;
      return null;
    }
  }

  Future<LyricsResult?> _fetchWithGet({
    required String title,
    required String artist,
    required String albumName,
    required int duration,
  }) async {
    try {
      // Clean artist: only take the first artist name
      final cleanArtist = artist.split(',').first.trim();

      final uri = Uri.parse('https://lrclib.net/api/get').replace(
        queryParameters: {
          'track_name': title,
          'artist_name': cleanArtist,
          'album_name': albumName,
          'duration': duration.toString(),
        },
      );

      debugPrint('🎤 Fetching lyrics (get): $uri');

      final response = await http.get(uri, headers: {
        'User-Agent': 'IqbalHiRes/1.0',
      }).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return _parseResponse(data);
      }

      debugPrint('🎤 GET returned ${response.statusCode}');
    } catch (e) {
      debugPrint('🎤 GET failed: $e');
    }
    return null;
  }

  Future<LyricsResult?> _fetchWithSearch({
    required String title,
    required String artist,
  }) async {
    try {
      // Clean artist: only take the first artist name
      final cleanArtist = artist.split(',').first.trim();
      final query = '$cleanArtist $title';

      final uri = Uri.parse('https://lrclib.net/api/search').replace(
        queryParameters: {'q': query},
      );

      debugPrint('🎤 Fetching lyrics (search): $uri');

      final response = await http.get(uri, headers: {
        'User-Agent': 'IqbalHiRes/1.0',
      }).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final List<dynamic> results = json.decode(response.body);

        if (results.isEmpty) {
          debugPrint('🎤 No search results');
          return null;
        }

        // Prefer results with synced lyrics
        final withSynced = results.firstWhere(
          (r) => r['syncedLyrics'] != null && r['syncedLyrics'].toString().isNotEmpty,
          orElse: () => results.first,
        );

        return _parseResponse(withSynced);
      }

      debugPrint('🎤 Search returned ${response.statusCode}');
    } catch (e) {
      debugPrint('🎤 Search failed: $e');
    }
    return null;
  }

  LyricsResult? _parseResponse(Map<String, dynamic> data) {
    final syncedLyricsRaw = data['syncedLyrics'] as String?;
    final plainLyricsRaw = data['plainLyrics'] as String?;

    List<LyricLine> syncedLines = [];

    if (syncedLyricsRaw != null && syncedLyricsRaw.isNotEmpty) {
      syncedLines = _parseLrc(syncedLyricsRaw);
      debugPrint('🎤 Parsed ${syncedLines.length} synced lyrics lines');
    }

    if (syncedLines.isEmpty && (plainLyricsRaw == null || plainLyricsRaw.isEmpty)) {
      return null;
    }

    return LyricsResult(
      syncedLyrics: syncedLines,
      plainLyrics: plainLyricsRaw,
    );
  }

  /// Parse LRC format: [mm:ss.xx] lyrics text
  List<LyricLine> _parseLrc(String lrc) {
    final lines = lrc.split('\n');
    final List<LyricLine> result = [];

    // Regex for [mm:ss.xx] or [mm:ss.xxx]
    final regex = RegExp(r'\[(\d{2}):(\d{2})\.(\d{2,3})\]');

    for (var line in lines) {
      final match = regex.firstMatch(line);
      if (match != null) {
        final minutes = int.parse(match.group(1)!);
        final seconds = int.parse(match.group(2)!);
        final msStr = match.group(3)!;
        // Pad to 3 digits for consistent millisecond parsing
        final milliseconds = int.parse(msStr.padRight(3, '0'));

        final timestamp = Duration(
          minutes: minutes,
          seconds: seconds,
          milliseconds: milliseconds,
        );

        // Get text after the timestamp tag
        final text = line.substring(match.end).trim();

        // Skip empty lines but keep them as spacing markers
        result.add(LyricLine(timestamp: timestamp, text: text));
      }
    }

    // Sort by timestamp
    result.sort((a, b) => a.timestamp.compareTo(b.timestamp));

    return result;
  }

  /// Clear cache
  void clearCache() => _cache.clear();

  /// Remove specific cache entry
  void removeCacheEntry(String title, String artist) {
    final key = '${artist.toLowerCase()}_${title.toLowerCase()}';
    _cache.remove(key);
  }
}
