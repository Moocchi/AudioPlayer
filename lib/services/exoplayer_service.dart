import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../models/song.dart';
import 'play_history_service.dart';

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
  
  // Song ending state for smooth animation
  bool _isSongEnding = false;
  
  // Position stream with periodic updates
  late Stream<Duration> positionStream;
  StreamController<Duration>? _positionController;
  Timer? _positionTimer;
  Timer? _periodicUpdateTimer;
  
  // Throttle notifyListeners to prevent excessive rebuilds
  DateTime? _lastNotifyTime;
  static const Duration _notifyThrottle = Duration(milliseconds: 250);
  
  // Seek debounce - prevent rapid successive seeks
  DateTime? _lastSeekTime;
  static const Duration _seekCooldown = Duration(milliseconds: 300);
  
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
  bool get isSongEnding => _isSongEnding;
  
  /// Get duration safely - returns zero if invalid
  Duration get duration {
    if (_duration.inMilliseconds > 0) {
      return _duration;
    }
    return Duration.zero;
  }
  
  Map<String, dynamic>? get manifestInfo => _manifestInfo;
  
  /// Fetch actual file size from streaming URL and update song
  Future<void> _fetchAndUpdateFileSize(String streamUrl, Song song) async {
    try {
      final headResponse = await http.head(Uri.parse(streamUrl));
      final contentLength = headResponse.headers['content-length'];
      
      if (contentLength != null) {
        final size = int.tryParse(contentLength);
        if (size != null) {
          song.fileSize = size;
          debugPrint('📦 File size updated: ${song.fileSizeMB}');
          notifyListeners(); // Update UI with actual file size
        }
      }
    } catch (e) {
      debugPrint('Error fetching file size: $e');
    }
  }

  void _initializePlayer() {
    // Initialize position stream with periodic updates
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
    
    // Start periodic position updates every 100ms for smooth UI updates
    _startPeriodicPositionUpdates();
  }
  
  void _startPeriodicPositionUpdates() {
    _periodicUpdateTimer?.cancel();
    // Reduced from 100ms to 500ms for better performance
    _periodicUpdateTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      _updatePositionOnly(); // Only update position, don't notify
      // Emit position through stream for UI
      if (_positionController != null && !_positionController!.isClosed) {
        _positionController!.add(_position);
      }
    });
  }

  void _handlePlayerEvent(dynamic event) {
    debugPrint('📩 Received native event: $event (type: ${event.runtimeType})');
    
    // Convert event to Map<String, dynamic> safely
    Map<String, dynamic>? eventMap;
    if (event is Map<String, dynamic>) {
      eventMap = event;
    } else if (event is Map) {
      // Handle Map<Object?, Object?> from platform channel
      eventMap = Map<String, dynamic>.from(event);
    }
    
    if (eventMap == null) {
      debugPrint('⚠️ Could not parse event as Map');
      return;
    }
    
    final eventType = eventMap['event']?.toString();
    debugPrint('📨 EVENT RECEIVED: $eventType');
      
    switch (eventType) {
        case 'playback_state_changed':
          _playbackState = eventMap['state']?.toString() ?? 'unknown';
          debugPrint('🎭 ExoPlayer state: $_playbackState');
          
          // Handle song ended
          if (_playbackState == 'ended') {
            debugPrint('🏁 Song ended, checking queue...');
            _handleSongEnded();
          }
          
          // Always set loading to false when ready or buffering
          // This ensures UI controls become active immediately
          if (_playbackState == 'ready' || _playbackState == 'buffering') {
            _isLoading = false;
            if (_playbackState == 'ready') {
              _loadingStatus = '';
              debugPrint('✅ Loading complete - state is ready, controls activated');
            } else {
              debugPrint('⏳ Buffering, controls remain active');
            }
          }
          notifyListeners();
          break;
          
        case 'is_playing_changed':
          final isPlayingRaw = eventMap['is_playing'];
          debugPrint('🔍 DEBUG: is_playing raw = $isPlayingRaw (type: ${isPlayingRaw.runtimeType})');
          
          // Handle both bool and dynamic types
          bool newIsPlaying = false;
          if (isPlayingRaw is bool) {
            newIsPlaying = isPlayingRaw;
          } else if (isPlayingRaw != null) {
            newIsPlaying = isPlayingRaw.toString() == 'true';
          }
          
          _isPlaying = newIsPlaying;
          debugPrint('▶️  ExoPlayer playing: $_isPlaying (updated from native)');
          
          // If audio is playing, clear loading status immediately
          // This ensures UI controls stay active and responsive
          if (_isPlaying) {
            _isLoading = false;
            _loadingStatus = '';
            debugPrint('✨ Audio playing detected: loading cleared, controls active');
          }
          
          notifyListeners();
          debugPrint('🔔 notifyListeners() called for is_playing_changed');
          break;
          
        case 'manifestLoaded':
          _manifestInfo = Map<String, dynamic>.from(eventMap);
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
          final error = eventMap['error']?.toString();
          debugPrint('❌ ExoPlayer error: $error');
          _isLoading = false;
          _loadingStatus = 'Error: $error';
          notifyListeners();
          break;
        
        // Handle skip events from notification
        case 'skip_next':
          debugPrint('⏭️ Skip Next event received from notification');
          debugPrint('📋 Current queue: ${_queue.length} songs, index: $_currentIndex');
          playNext(); // Fire and forget - no await needed
          break;
          
        case 'skip_previous':
          debugPrint('⏮️ Skip Previous event received from notification');
          debugPrint('📋 Current queue: ${_queue.length} songs, index: $_currentIndex');
          playPrevious(); // Fire and forget - no await needed
          break;
          
        default:
          debugPrint('⚠️  UNKNOWN EVENT TYPE: "$eventType"');
      }
  }

  /// Update position without notifying listeners (for periodic updates)
  Future<void> _updatePositionOnly() async {
    try {
      final position = await _channel.invokeMethod<int>('getCurrentPosition');
      final duration = await _channel.invokeMethod<int>('getDuration');
      
      if (position != null) {
        _position = Duration(milliseconds: position);
      }
      if (duration != null && duration > 0) {
        _duration = Duration(milliseconds: duration);
      }
    } catch (e) {
      // Position update failed, ignore
    }
  }

  Future<void> _updatePosition() async {
    await _updatePositionOnly();
    _throttledNotify();
  }
  
  /// Throttled notifyListeners to prevent excessive UI rebuilds
  void _throttledNotify() {
    final now = DateTime.now();
    if (_lastNotifyTime == null || 
        now.difference(_lastNotifyTime!) > _notifyThrottle) {
      _lastNotifyTime = now;
      notifyListeners();
    }
  }
  
  /// Handle song ended - animate then play next or reset
  Future<void> _handleSongEnded() async {
    debugPrint('🏁 _handleSongEnded: queue.length=${_queue.length}, currentIndex=$_currentIndex');
    
    // Set song ending flag for UI animation
    _isSongEnding = true;
    _isPlaying = false;
    _position = Duration.zero; // Reset position immediately
    notifyListeners();
    
    // Emit zero position for smooth animation
    if (_positionController != null && !_positionController!.isClosed) {
      _positionController!.add(Duration.zero);
    }
    
    // Wait for animation to complete (500ms)
    await Future.delayed(const Duration(milliseconds: 500));
    
    // Check if there's a next song in queue
    if (_queue.isNotEmpty && _currentIndex < _queue.length - 1) {
      debugPrint('📋 Playing next song in queue...');
      _currentIndex++;
      final nextSong = _queue[_currentIndex];
      // Keep _isSongEnding true until playHiResSong resets it
      await playHiResSong(nextSong);
    } else {
      // No more songs - reset flag and stay at zero
      debugPrint('🔄 No more songs, staying at zero');
      _isSongEnding = false;
      seekTo(Duration.zero);
      notifyListeners();
    }
    
    debugPrint('✅ Song end handled');
  }
  
  /// Reset position to beginning with smooth animation support
  void _resetToBeginning() {
    _isPlaying = false;
    _position = Duration.zero;
    
    // Emit zero position to stream for smooth UI update
    if (_positionController != null && !_positionController!.isClosed) {
      _positionController!.add(Duration.zero);
    }
    
    // Seek to beginning in native player
    seekTo(Duration.zero);
    
    notifyListeners();
    debugPrint('✅ Position reset to zero');
  }

  Future<void> playHiResSong(Song song) async {
    debugPrint('🎵 Playing Hi-Res song: ${song.title}');
    
    // Record play in history
    PlayHistoryService().recordPlay(song);
    
    // Keep _isSongEnding true during transition to prevent slider jump
    // It will be reset when we're ready to play
    
    // Reset position and duration immediately
    _position = Duration.zero;
    _duration = Duration.zero;
    if (_positionController != null && !_positionController!.isClosed) {
      _positionController!.add(Duration.zero);
    }
    
    _isLoading = true;
    _currentSong = song;
    
    // For lossless, use direct URL. For Hi-Res, use DASH
    if (song.isLossless && !song.isHiRes) {
      _loadingStatus = 'Loading Lossless...';
      debugPrint('🎯 Quality: LOSSLESS (Direct URL)');
    } else {
      _loadingStatus = 'Loading Hi-Res stream...';
      debugPrint('🎯 Quality: HI_RES_LOSSLESS (DASH)');
    }
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
      String? directUrl = data['data']['directUrl'] as String?;
      
      // For lossless without Hi-Res, use direct URL if available
      if (song.isLossless && !song.isHiRes && directUrl != null && directUrl.isNotEmpty) {
        debugPrint('🎵 Direct audio URL: $directUrl');
        
        // Fetch actual file size in background (don't await)
        _fetchAndUpdateFileSize(directUrl, song);
        
        // Set source first
        await _channel.invokeMethod('setDashSource', {'url': directUrl});
        
        // Clear loading IMMEDIATELY after source is set, BEFORE play()
        // This ensures UI is responsive without waiting for events
        _isLoading = false;
        _loadingStatus = '';
        _isPlaying = true;
        _isSongEnding = false; // Reset AFTER loading, ready to play
        notifyListeners();
        debugPrint('✅ Loading cleared before play()');
        
        // Now start playback
        await play();
        
        // Update notification AFTER playback starts for better sync
        await _updateNotification(song);
        
        debugPrint('✅ Lossless streaming started!');
        return;
      }
      
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
        
        // Fetch actual file size in background
        _fetchAndUpdateFileSize(audioUrl, song);
        
        // Set source first
        await setDashSource(audioUrl);
        
        // Clear loading IMMEDIATELY after source is set
        _isLoading = false;
        _loadingStatus = '';
        _isPlaying = true;
        _isSongEnding = false; // Reset AFTER loading, ready to play
        notifyListeners();
        debugPrint('✅ Loading cleared for regular manifest');
        
        // Small delay to ensure source is ready
        await Future.delayed(const Duration(milliseconds: 300));
        await play();
        
        // Update notification AFTER playback starts for better sync
        await _updateNotification(song);
        
        debugPrint('✅ Regular streaming started!');
      }
      
    } catch (e) {
      debugPrint('❌ Error playing Hi-Res song: $e');
      _isLoading = false;
      _isSongEnding = false; // Reset on error too
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

      // CRITICAL: Ensure manifest is static (not dynamic/live)
      // This prevents ExoPlayer from re-fetching manifest and re-preparing codec on seek
      if (mpdContent.contains('type="dynamic"')) {
        debugPrint('⚠️  Converting dynamic manifest to static');
        mpdContent = mpdContent.replaceFirst('type="dynamic"', 'type="static"');
      }
      
      // Ensure manifest has static type attribute
      if (!mpdContent.contains('type="')) {
        debugPrint('⚠️  Adding type="static" to manifest');
        mpdContent = mpdContent.replaceFirst('<MPD', '<MPD type="static"');
      }
      
      // Remove or modify attributes that trigger manifest refresh
      // minBufferTime can cause ExoPlayer to re-fetch manifest
      mpdContent = mpdContent.replaceAll(RegExp(r'minBufferTime="[^"]*"'), 'minBufferTime="PT2S"');
      
      // Remove profiles that indicate live streaming capabilities
      mpdContent = mpdContent.replaceAll('urn:mpeg:dash:profile:isoff-live:2011', 'urn:mpeg:dash:profile:isoff-on-demand:2011');
      
      // Ensure mediaPresentationDuration exists for VOD seeking
      if (!mpdContent.contains('mediaPresentationDuration')) {
        // Try to extract duration from Period element
        debugPrint('⚠️  No mediaPresentationDuration found, attempting to extract from segments');
        
        // For DASH, if no duration, set a large one to prevent live detection
        mpdContent = mpdContent.replaceFirst('<MPD', '<MPD mediaPresentationDuration="PT1H"');
      }

      debugPrint('📋 DASH Manifest Preparation:');
      debugPrint('   - Type: ${mpdContent.contains('type="static"') ? 'Static (VOD)' : 'Dynamic (Live)'}');
      debugPrint('   - Has Duration: ${mpdContent.contains('mediaPresentationDuration')}');
      debugPrint('   - minBufferTime: ${RegExp(r'minBufferTime="[^"]*"').firstMatch(mpdContent)?.group(0) ?? 'default'}');
      debugPrint('   - Manifest size: ${mpdContent.length} bytes');
      
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
      
      // Reset song ending flag NOW - right before play starts
      _isSongEnding = false;
      _isPlaying = true;
      _isLoading = false;
      _loadingStatus = '';
      notifyListeners();
      
      await play();
      
      // Update notification AFTER playback starts for better sync
      await _updateNotification(song);
      
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
      debugPrint('▶️  [Dart] Calling play via MethodChannel...');
      // Optimistic update - set playing state before MethodChannel call
      _isPlaying = true;
      notifyListeners();
      debugPrint('✨ [Dart] Optimistic update: _isPlaying = true');
      
      await _channel.invokeMethod('play');
      debugPrint('✅ [Dart] Play method invoked successfully');
    } catch (e) {
      debugPrint('❌ [Dart] Error playing: $e');
      // Revert on error
      _isPlaying = false;
      notifyListeners();
    }
  }

  Future<void> pause() async {
    try {
      debugPrint('⏸️  [Dart] Calling pause via MethodChannel...');
      // Optimistic update - set paused state before MethodChannel call
      _isPlaying = false;
      notifyListeners();
      debugPrint('✨ [Dart] Optimistic update: _isPlaying = false');
      
      await _channel.invokeMethod('pause');
      debugPrint('✅ [Dart] Pause method invoked successfully');
    } catch (e) {
      debugPrint('❌ [Dart] Error pausing: $e');
      // Revert on error
      _isPlaying = true;
      notifyListeners();
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
      // Debounce rapid successive seeks to prevent codec re-initialization
      final now = DateTime.now();
      if (_lastSeekTime != null && now.difference(_lastSeekTime!) < _seekCooldown) {
        debugPrint('⏱️  Seek throttled (cooldown ${_seekCooldown.inMilliseconds}ms)');
        return;
      }
      _lastSeekTime = now;
      
      // Ensure a song is loaded
      if (_currentSong == null) {
        debugPrint('⚠️ Warning: No song loaded, cannot seek');
        return;
      }
      
      debugPrint('⏩ Seeking to ${position.inMilliseconds}ms (${_formatDuration(position)})');
      
      // Send seek command to native side
      await _channel.invokeMethod('seekTo', {
        'positionMs': position.inMilliseconds,
      });
      
      // Update local position so UI doesn't jump back to old position
      _position = position;
      notifyListeners();
      
    } catch (e) {
      debugPrint('❌ Error seeking: $e');
    }
  }

  /// Set source for audio streaming
  /// Status is managed by caller, not in this method
  Future<void> setDashSource(String url) async {
    try {
      await _channel.invokeMethod('setDashSource', {'url': url});
      debugPrint('✅ ExoPlayer: Source set - $url');
    } catch (e) {
      debugPrint('❌ Error setting source: $e');
      throw Exception('Failed to set source: $e');
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
    debugPrint('📋 playQueue called with ${songs.length} songs, startIndex: $startIndex');
    
    _queue = List.from(songs);
    _currentIndex = startIndex;
    
    debugPrint('📋 Queue set: ${_queue.length} songs, currentIndex: $_currentIndex');
    
    if (_queue.isNotEmpty && _currentIndex < _queue.length) {
      final song = _queue[_currentIndex];
      debugPrint('📋 Playing: ${song.title}');
      await playHiResSong(song);
    }
    
    notifyListeners();
  }

  /// Toggle play/pause - fully reactive, no optimistic updates
  Future<void> togglePlayPause() async {
    debugPrint('🔄 togglePlayPause called | isPlaying=$_isPlaying');
    
    // No optimistic update - wait for native event to update _isPlaying
    try {
      if (_isPlaying) {
        debugPrint('⏸️  Calling pause()...');
        await pause();
      } else {
        debugPrint('▶️  Calling play()...');
        await play();
      }
      debugPrint('✅ Play/Pause command sent to native');
    } catch (e) {
      debugPrint('❌ Error in togglePlayPause: $e');
    }
  }

  /// Seek to position
  Future<void> seek(Duration position) async {
    await seekTo(position);
  }

  /// Play next song in queue
  Future<void> playNext() async {
    debugPrint('⏭️ playNext called | queue.length=${_queue.length} | currentIndex=$_currentIndex');
    
    if (_queue.isEmpty) {
      debugPrint('⚠️ Queue is empty, cannot skip next');
      return;
    }
    
    if (_currentIndex < _queue.length - 1) {
      _currentIndex++;
      final nextSong = _queue[_currentIndex];
      debugPrint('⏭️ Playing next song: ${nextSong.title} (index $_currentIndex)');
      await playHiResSong(nextSong);
    } else {
      debugPrint('⚠️ Already at last song in queue');
    }
  }

  /// Play previous song in queue
  Future<void> playPrevious() async {
    debugPrint('⏮️ playPrevious called | queue.length=${_queue.length} | currentIndex=$_currentIndex');
    
    if (_queue.isEmpty) {
      debugPrint('⚠️ Queue is empty, cannot skip previous');
      return;
    }
    
    if (_currentIndex > 0) {
      _currentIndex--;
      final prevSong = _queue[_currentIndex];
      debugPrint('⏮️ Playing previous song: ${prevSong.title} (index $_currentIndex)');
      await playHiResSong(prevSong);
    } else {
      // Jika di awal, restart lagu dari awal
      debugPrint('⏮️ At first song, restarting from beginning');
      await seekTo(Duration.zero);
    }
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  Future<void> _updateNotification(Song song) async {
    try {
      await _channel.invokeMethod('updateMetadata', {
        'title': song.title,
        'artist': song.artist,
        'albumCover': song.albumCover ?? '',
      });
      debugPrint('🔔 Notification updated: ${song.title} - ${song.artist}');
    } catch (e) {
      debugPrint('❌ Error updating notification: $e');
    }
  }

  @override
  void dispose() {
    _eventSubscription?.cancel();
    _periodicUpdateTimer?.cancel();
    _positionTimer?.cancel();
    _positionController?.close();
    stop();
    super.dispose();
  }
}