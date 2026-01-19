import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/song.dart';

class ApiService {
  static const String _baseUrl = 'https://katze.qqdl.site';

  static Future<List<Song>> searchSongs(String query) async {
    try {
      final url = Uri.parse('$_baseUrl/search/?s=$query');
      final response = await http.get(url);
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final items = data['data']['items'] as List? ?? [];
        return items.map((item) => Song.fromJson(item)).toList();
      }
    } catch (e) {
      print('Search error: $e');
    }
    return [];
  }

  static Future<List<Song>> getAlbumTracks(String albumId) async {
    try {
      final url = Uri.parse('$_baseUrl/album/?id=$albumId');
      final response = await http.get(url);
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final items = data['data']['items'] as List? ?? [];
        return items.map((item) => Song.fromJson(item)).toList();
      }
    } catch (e) {
      print('Album error: $e');
    }
    return [];
  }
  
  /// Fetch actual file size from streaming URL using HTTP HEAD request
  static Future<int?> fetchFileSize(String songId, {bool isHiRes = false}) async {
    try {
      final quality = isHiRes ? 'HI_RES_LOSSLESS' : 'LOSSLESS';
      final trackUrl = Uri.parse('$_baseUrl/track/?id=$songId&quality=$quality');
      
      final response = await http.get(trackUrl);
      if (response.statusCode != 200) return null;
      
      final data = json.decode(response.body);
      if (data['data'] == null) return null;
      
      // Try to get direct URL
      String? streamUrl = data['data']['directUrl'] as String?;
      
      // If no direct URL, try to decode manifest
      if (streamUrl == null || streamUrl.isEmpty) {
        final manifestB64 = data['data']['manifest'] as String?;
        if (manifestB64 != null) {
          try {
            final manifestDecoded = utf8.decode(base64.decode(manifestB64));
            // Check if it's JSON (contains URL)
            if (!manifestDecoded.startsWith('<?xml')) {
              final manifest = json.decode(manifestDecoded);
              streamUrl = (manifest['urls'] as List?)?.first as String?;
            }
          } catch (e) {
            debugPrint('Error decoding manifest for size: $e');
          }
        }
      }
      
      if (streamUrl == null || streamUrl.isEmpty) return null;
      
      // Make HEAD request to get Content-Length
      final headResponse = await http.head(Uri.parse(streamUrl));
      final contentLength = headResponse.headers['content-length'];
      
      if (contentLength != null) {
        final size = int.tryParse(contentLength);
        debugPrint('📦 File size for $songId: $size bytes (${(size ?? 0) / 1024 / 1024} MB)');
        return size;
      }
    } catch (e) {
      debugPrint('Error fetching file size: $e');
    }
    return null;
  }
}
