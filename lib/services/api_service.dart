import 'dart:convert';
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
}
