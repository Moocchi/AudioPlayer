import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../models/song.dart';

/// Local HTTP server for serving DASH manifests
class LocalManifestServer {
  static LocalManifestServer? _instance;
  HttpServer? _server;
  String? _currentManifest;
  int _port = 8765;
  
  static Future<LocalManifestServer> getInstance() async {
    if (_instance == null) {
      _instance = LocalManifestServer();
      await _instance!._startServer();
    }
    return _instance!;
  }
  
  Future<void> _startServer() async {
    try {
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, _port);
      debugPrint('🌐 Local manifest server started on port $_port');
      
      _server!.listen((HttpRequest request) async {
        if (request.uri.path == '/manifest.mpd' && _currentManifest != null) {
          request.response
            ..headers.contentType = ContentType('application', 'dash+xml')
            ..headers.add('Access-Control-Allow-Origin', '*')
            ..write(_currentManifest)
            ..close();
          debugPrint('📄 Served DASH manifest');
        } else {
          request.response
            ..statusCode = HttpStatus.notFound
            ..close();
        }
      });
    } catch (e) {
      debugPrint('❌ Failed to start local server: $e');
      // Try another port
      _port = 8766;
      try {
        _server = await HttpServer.bind(InternetAddress.loopbackIPv4, _port);
        debugPrint('🌐 Local manifest server started on port $_port (fallback)');
        
        _server!.listen((HttpRequest request) async {
          if (request.uri.path == '/manifest.mpd' && _currentManifest != null) {
            request.response
              ..headers.contentType = ContentType('application', 'dash+xml')
              ..headers.add('Access-Control-Allow-Origin', '*')
              ..write(_currentManifest)
              ..close();
          } else {
            request.response
              ..statusCode = HttpStatus.notFound
              ..close();
          }
        });
      } catch (e2) {
        debugPrint('❌ Failed to start fallback server: $e2');
      }
    }
  }
  
  void setManifest(String manifest) {
    _currentManifest = manifest;
  }
  
  String get manifestUrl => 'http://127.0.0.1:$_port/manifest.mpd';
  
  Future<void> stop() async {
    await _server?.close();
    _server = null;
    _instance = null;
  }
}

class ExoPlayerService extends ChangeNotifier {
  static final ExoPlayerService _instance = ExoPlayerService._internal();
  factory ExoPlayerService() => _instance;
  ExoPlayerService._internal() {
    _initializePlayer();
  }

  static const MethodChannel _channel = MethodChannel('exoplayer');
  static const EventChannel _eventChannel = EventChannel('exoplayer/events');
  
  StreamSubscription<dynamic>? _eventSubscription;
  Song? _currentSong;
  List<Song> _queue = [];
  int _currentIndex = -1;
  bool _isLoading = false;
  String _loadingStatus = '';
  
  // Player state
  bool _isPlaying = false;
  String _playbackState = 'idle';
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  
  // Position stream
  late Stream<Duration> positionStream;
  StreamController<Duration>? _positionController;
  Timer? _positionTimer;
  
  // DASH manifest info
  Map<String, dynamic>? _manifestInfo;
  
  // Getters
  Song? get currentSong => _currentSong;
  List<Song> get queue => _queue;
  int get currentIndex => _currentIndex;
  bool get isLoading => _isLoading;
  String get loadingStatus => _loadingStatus;
  bool get isPlaying => _isPlaying;
  String get playbackState => _playbackState;
  Duration get position => _position;
  Duration get duration => _duration;
  Map<String, dynamic>? get manifestInfo => _manifestInfo;

  void _initializePlayer() {
    // Initialize position stream
    _positionController = StreamController<Duration>.broadcast();
    positionStream = _positionController!.stream;
    
    _eventSubscription = _eventChannel.receiveBroadcastStream().listen(
      (dynamic event) {
        _handlePlayerEvent(event);
      },
      onError: (error) {
        debugPrint('ExoPlayer event error: $error');
      },
    );
    
    // Start position updates
    Timer.periodic(const Duration(milliseconds: 1000), (timer) {
      if (_isPlaying) {
        _updatePosition();
      }
    });
  }

  void _handlePlayerEvent(dynamic event) {
    if (event is Map<String, dynamic>) {
      final eventType = event['event'] as String?;
      
      switch (eventType) {
        case 'playbackStateChanged':
          _playbackState = event['state'] as String? ?? 'unknown';
          debugPrint('🎵 ExoPlayer state: $_playbackState');
          
          if (_playbackState == 'ready' && _isLoading) {
            _isLoading = false;
            _loadingStatus = '';
          }
          notifyListeners();
          break;
          
        case 'isPlayingChanged':
          _isPlaying = event['isPlaying'] as bool? ?? false;
          debugPrint('🎵 ExoPlayer playing: $_isPlaying');
          
          if (_isPlaying) {
            _startPositionTimer();
          } else {
            _stopPositionTimer();
          }
          
          notifyListeners();
          break;
          
        case 'manifestLoaded':
          _manifestInfo = Map<String, dynamic>.from(event);
          _manifestInfo!.remove('event'); // Remove event type
          
          debugPrint('📄 DASH Manifest loaded:');
          debugPrint('   Periods: ${_manifestInfo!['periodCount']}');
          debugPrint('   Duration: ${_manifestInfo!['durationMs']}ms');
          debugPrint('   Dynamic: ${_manifestInfo!['dynamic']}');
          debugPrint('   Adaptation Sets: ${_manifestInfo!['adaptationSetCount']}');
          
          if (_manifestInfo!['adaptationSets'] != null) {
            final adaptationSets = _manifestInfo!['adaptationSets'] as List;
            for (int i = 0; i < adaptationSets.length; i++) {
              final set = adaptationSets[i] as Map;
              debugPrint('   Set $i: ID=${set['id']}, Type=${set['type']}, Reps=${set['representationCount']}');
            }
          }
          
          notifyListeners();
          break;
          
        case 'error':
          final error = event['error'] as String?;
          debugPrint('❌ ExoPlayer error: $error');
          _isLoading = false;
          _loadingStatus = 'Error: $error';
          notifyListeners();
          break;
      }
    }
  }

  Future<void> _updatePosition() async {
    try {
      final position = await _channel.invokeMethod<int>('getCurrentPosition');
      final duration = await _channel.invokeMethod<int>('getDuration');
      
      if (position != null) {
        _position = Duration(milliseconds: position);
      }
      if (duration != null && duration > 0) {
        _duration = Duration(milliseconds: duration);
      }
      
      notifyListeners();
    } catch (e) {
      // Position update failed, ignore
    }
  }

  Future<void> playHiResSong(Song song) async {
    debugPrint('🎵 Playing Hi-Res song: ${song.title}');
    
    _isLoading = true;
    _loadingStatus = 'Fetching manifest...';
    _currentSong = song;
    notifyListeners();
    
    try {
      // Determine quality based on song tags
      String quality = song.isHiRes ? "HI_RES_LOSSLESS" : "LOSSLESS";
      debugPrint('🎯 Quality: $quality for song: ${song.title}');
      
      // Get manifest from katze API
      var url = Uri.parse('https://katze.qqdl.site/track/?id=${song.id}&quality=$quality');
      debugPrint('🌐 API Request: $url');
      
      var res = await http.get(url);
      
      if (res.statusCode != 200) {
        throw Exception('API Error: ${res.statusCode}');
      }
      
      var data = json.decode(res.body);
      
      if (data['data'] == null) {
        throw Exception('No data in API response');
      }
      
      String manifestMimeType = data['data']['manifestMimeType'] ?? '';
      String manifestB64 = data['data']['manifest'];
      String manifestDecoded = utf8.decode(base64.decode(manifestB64));
      
      debugPrint('📄 Manifest MIME type: $manifestMimeType');
      
      if (manifestMimeType == 'application/dash+xml' || manifestDecoded.startsWith('<?xml')) {
        debugPrint("🎵 Hi-Res DASH manifest detected, processing...");
        await _playDashStream(song, manifestDecoded);
      } else {
        // Regular manifest with direct URL
        Map manifest = json.decode(manifestDecoded);
        String audioUrl = manifest['urls'][0];
        
        debugPrint('🎵 Direct audio URL: $audioUrl');
        _loadingStatus = 'Setting up ExoPlayer...';
        notifyListeners();
        
        // Use ExoPlayer for direct URL
        await setDashSource(audioUrl);
        await Future.delayed(const Duration(milliseconds: 500));
        await play();
      }
      
    } catch (e) {
      debugPrint('❌ Error playing Hi-Res song: $e');
      _isLoading = false;
      _loadingStatus = 'Error: $e';
      notifyListeners();
    }
  }

  Future<void> _playDashStream(Song song, String manifestDecoded) async {
    try {
      _loadingStatus = 'Processing DASH manifest...';
      notifyListeners();
      
      // The manifest should already have proper XML encoding (&amp; etc)
      // Only decode HTML entities that are NOT valid XML entities
      // Keep &amp; as is because ExoPlayer's XML parser needs it
      String mpdContent = manifestDecoded
          .replaceAll('&lt;', '<')
          .replaceAll('&gt;', '>')
          .replaceAll('&quot;', '"')
          .replaceAll("&apos;", "'");
      
      // If & is not followed by amp;, encode it properly for XML
      // This handles cases where raw & exists in URLs
      mpdContent = mpdContent.replaceAllMapped(
        RegExp(r'&(?!amp;|lt;|gt;|quot;|apos;)'),
        (match) => '&amp;'
      );

      debugPrint('🔍 Processed DASH manifest, length: ${mpdContent.length}');
      
      // Start local HTTP server and serve manifest
      final localServer = await LocalManifestServer.getInstance();
      localServer.setManifest(mpdContent);
      
      final manifestUrl = localServer.manifestUrl;
      debugPrint('🌐 Local manifest URL: $manifestUrl');
      
      _loadingStatus = 'Starting Hi-Res stream...';
      notifyListeners();
      
      // Use ExoPlayer to stream directly from DASH manifest
      // ExoPlayer will fetch segments from Tidal CDN automatically
      await _channel.invokeMethod('setDashSource', {'url': manifestUrl});
      await Future.delayed(const Duration(milliseconds: 500));
      await play();
      
      _isLoading = false;
      _loadingStatus = '';
      notifyListeners();
      
      debugPrint('🎵 ExoPlayer Hi-Res streaming started!');
      
    } catch (e) {
      debugPrint('❌ Error in DASH stream: $e');
      _isLoading = false;
      _loadingStatus = 'DASH Error: $e';
      notifyListeners();
    }
  }

  Future<void> play() async {
    try {
      await _channel.invokeMethod('play');
    } catch (e) {
      debugPrint('❌ Error playing: $e');
    }
  }

  Future<void> pause() async {
    try {
      await _channel.invokeMethod('pause');
    } catch (e) {
      debugPrint('❌ Error pausing: $e');
    }
  }

  Future<void> stop() async {
    try {
      await _channel.invokeMethod('stop');
      _currentSong = null;
      _position = Duration.zero;
      _duration = Duration.zero;
      _manifestInfo = null;
      notifyListeners();
    } catch (e) {
      debugPrint('❌ Error stopping: $e');
    }
  }

  Future<void> seekTo(Duration position) async {
    try {
      await _channel.invokeMethod('seekTo', {
        'positionMs': position.inMilliseconds,
      });
    } catch (e) {
      debugPrint('❌ Error seeking: $e');
    }
  }

  /// Set DASH source for Hi-Res streaming
  Future<void> setDashSource(String url) async {
    try {
      _loadingStatus = 'Loading Hi-Res stream...';
      notifyListeners();
      
      await _channel.invokeMethod('setDashSource', {'url': url});
      debugPrint('✅ ExoPlayer: DASH source set - $url');
    } catch (e) {
      debugPrint('❌ Error setting DASH source: $e');
      throw Exception('Failed to set DASH source: $e');
    }
  }



  Future<Map<String, dynamic>?> getManifestInfo() async {
    try {
      final info = await _channel.invokeMethod<Map<String, dynamic>>('getManifestInfo');
      return info;
    } catch (e) {
      debugPrint('❌ Error getting manifest info: $e');
      return null;
    }
  }

  void addToQueue(Song song) {
    _queue.add(song);
    notifyListeners();
  }

  void removeFromQueue(int index) {
    if (index >= 0 && index < _queue.length) {
      _queue.removeAt(index);
      if (index <= _currentIndex) {
        _currentIndex--;
      }
      notifyListeners();
    }
  }

  void clearQueue() {
    _queue.clear();
    _currentIndex = -1;
    notifyListeners();
  }

  /// Play queue of songs starting from specific index
  Future<void> playQueue(List<Song> songs, int startIndex) async {
    _queue = List.from(songs);
    _currentIndex = startIndex;
    
    if (_queue.isNotEmpty && _currentIndex < _queue.length) {
      final song = _queue[_currentIndex];
      await playHiResSong(song);
    }
    
    notifyListeners();
  }

  /// Toggle play/pause
  Future<void> togglePlayPause() async {
    if (_isPlaying) {
      await pause();
    } else {
      await play();
    }
  }

  /// Seek to position
  Future<void> seek(Duration position) async {
    await seekTo(position);
  }

  /// Play next song in queue
  Future<void> playNext() async {
    if (_queue.isNotEmpty && _currentIndex < _queue.length - 1) {
      _currentIndex++;
      final nextSong = _queue[_currentIndex];
      await playHiResSong(nextSong);
    }
  }

  /// Play previous song in queue
  Future<void> playPrevious() async {
    if (_queue.isNotEmpty && _currentIndex > 0) {
      _currentIndex--;
      final prevSong = _queue[_currentIndex];
      await playHiResSong(prevSong);
    }
  }

  void _startPositionTimer() {
    _positionTimer?.cancel();
    _positionTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (_isPlaying) {
        _updatePosition();
        _positionController?.add(_position);
      }
    });
  }

  void _stopPositionTimer() {
    _positionTimer?.cancel();
  }

  @override
  void dispose() {
    _eventSubscription?.cancel();
    _stopPositionTimer();
    _positionController?.close();
    stop();
    super.dispose();
  }
}