import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../models/song.dart';
import 'play_history_service.dart';
import '../models/loop_mode.dart'; // Import LoopMode

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
        debugPrint(
          '🌐 Local manifest server started on port $_port (fallback)',
        );

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

  // Signal to expand player when user taps a song
  final ValueNotifier<int> shouldExpandPlayer = ValueNotifier<int>(0);

  // Playback Modes
  bool _isShuffleMode = false;
  LoopMode _loopMode = LoopMode.off;

  bool get isShuffleMode => _isShuffleMode;
  LoopMode get loopMode => _loopMode;

  void toggleShuffle() {
    _isShuffleMode = !_isShuffleMode;
    if (_isShuffleMode) {
      // Logic to shuffle queue would go here
      // For now just UI toggle
    } else {
      // Logic to restore queue
    }
    notifyListeners();
  }

  void toggleLoop() {
    switch (_loopMode) {
      case LoopMode.off:
        _loopMode = LoopMode.all;
        break;
      case LoopMode.all:
        _loopMode = LoopMode.one;
        break;
      case LoopMode.one:
        _loopMode = LoopMode.off;
        break;
    }
    notifyListeners();
  }

  // Player state
  bool _isPlaying = false;
  String _playbackState = 'idle';
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  // Song ending state for smooth animation
  bool _isSongEnding = false;

  // Block position updates during song transition
  bool _isTransitioning = false;

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

  // Sleep Timer
  Timer? _sleepTimer;
  Duration? _sleepTimerDuration;
  bool _stopAfterCurrentSong = false;

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
  Duration? get sleepTimerDuration => _sleepTimerDuration;
  bool get stopAfterCurrentSong => _stopAfterCurrentSong;

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

  Future<void> _initializePlayer() async {
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

    // Restore last played song (but don't play it)
    await _restoreLastPlayedSong();

    // Sync with native player state (in case app was killed but music is playing)
    _syncWithNativeState();
  }

  Future<void> _restoreLastPlayedSong() async {
    final lastSong = await PlayHistoryService().getLastPlayedSong();
    if (lastSong != null) {
      if (_currentSong == null) {
        _currentSong = lastSong;
        debugPrint('💾 Restored last played song: ${lastSong.title}');
        notifyListeners();
      }
    }
  }

  Future<void> _syncWithNativeState() async {
    try {
      final state = await _channel.invokeMethod('getPlaybackState');
      if (state != null && state is Map) {
        final bool isPlaying = state['isPlaying'] ?? false;
        final String playbackState = state['playbackState'] ?? 'idle';
        final int positionMs = state['position'] ?? 0;

        debugPrint(
          '🔄 Syncing with native state: isPlaying=$isPlaying, state=$playbackState',
        );

        if (isPlaying ||
            playbackState == 'ready' ||
            playbackState == 'buffering') {
          _isPlaying = isPlaying;
          _playbackState = playbackState;
          if (positionMs > 0) {
            _position = Duration(milliseconds: positionMs);
          }
          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint('Error syncing with native state: $e');
    }
  }

  void _startPeriodicPositionUpdates() {
    _periodicUpdateTimer?.cancel();
    // Reduced from 100ms to 500ms for better performance
    _periodicUpdateTimer = Timer.periodic(const Duration(milliseconds: 500), (
      timer,
    ) {
      // Don't update position during song transition to prevent slider jump
      if (_isTransitioning) return;

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
            debugPrint(
              '✅ Loading complete - state is ready, controls activated',
            );
          } else {
            debugPrint('⏳ Buffering, controls remain active');
          }
        }
        notifyListeners();
        break;

      case 'is_playing_changed':
        final isPlayingRaw = eventMap['is_playing'];
        debugPrint(
          '🔍 DEBUG: is_playing raw = $isPlayingRaw (type: ${isPlayingRaw.runtimeType})',
        );

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
          debugPrint(
            '✨ Audio playing detected: loading cleared, controls active',
          );
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
        debugPrint(
          '   Adaptation Sets: ${_manifestInfo!['adaptationSetCount']}',
        );

        if (_manifestInfo!['adaptationSets'] != null) {
          final adaptationSets = _manifestInfo!['adaptationSets'] as List;
          for (int i = 0; i < adaptationSets.length; i++) {
            final set = adaptationSets[i] as Map;
            debugPrint(
              '   Set $i: ID=${set['id']}, Type=${set['type']}, Reps=${set['representationCount']}',
            );
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
        debugPrint(
          '📋 Current queue: ${_queue.length} songs, index: $_currentIndex',
        );
        playNext(); // Fire and forget - no await needed
        break;

      case 'skip_previous':
        debugPrint('⏮️ Skip Previous event received from notification');
        debugPrint(
          '📋 Current queue: ${_queue.length} songs, index: $_currentIndex',
        );
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
    debugPrint(
      '🏁 _handleSongEnded: queue.length=${_queue.length}, currentIndex=$_currentIndex',
    );

    // Block position updates during transition
    _isTransitioning = true;

    // Set song ending flag for UI animation
    _isSongEnding = true;
    _isPlaying = false;
    _position = Duration.zero; // Reset position immediately
    _duration = Duration.zero; // Also reset duration
    notifyListeners();

    // Emit zero position for smooth animation
    if (_positionController != null && !_positionController!.isClosed) {
      _positionController!.add(Duration.zero);
    }

    // Wait for animation to complete (500ms)
    await Future.delayed(const Duration(milliseconds: 500));

    // Check if Sleep Timer "End of Song" is active
    if (_stopAfterCurrentSong) {
      debugPrint('🛑 Sleep Timer: Stopping after current song.');
      _stopAfterCurrentSong = false;
      _sleepTimerDuration = null;
      _isPlaying = false;
      notifyListeners();
      return; // Stop playback here
    }

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
      _isTransitioning = false;
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

  // Generation ID to handle race conditions (rapid song switching)
  int _currentSongGenerationId = 0;

  Future<void> playHiResSong(Song song) async {
    // Increment generation ID for the new request
    _currentSongGenerationId++;
    final int localGenerationId = _currentSongGenerationId;

    debugPrint(
      '🎵 Playing Hi-Res song: ${song.title} (Gen: $localGenerationId)',
    );

    // Record play in history
    PlayHistoryService().recordPlay(song);
    // Save as last played for restoration
    PlayHistoryService().saveLastPlayedSong(song);

    // STOP previous playback to ensure clean state (Fixes HiRes -> Lossless switch bug)
    await stop();

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

      // Get manifest from katze API with retry logic
      var url = Uri.parse(
        'https://katze.qqdl.site/track/?id=${song.id}&quality=$quality',
      );
      debugPrint('🌐 API Request: $url');

      // Retry logic for transient API errors (e.g., 500)
      const maxRetries = 3;
      http.Response? res;
      Exception? lastError;

      for (int attempt = 0; attempt < maxRetries; attempt++) {
        try {
          if (attempt > 0) {
            // Exponential backoff: 1s, 2s, 4s
            final delayMs = 1000 * (1 << (attempt - 1));
            debugPrint(
              '🔄 Retry attempt ${attempt + 1}/$maxRetries after ${delayMs}ms...',
            );
            await Future.delayed(Duration(milliseconds: delayMs));

            // Check if request is still valid before retrying
            if (localGenerationId != _currentSongGenerationId) {
              debugPrint('🛑 Retry aborted: Newer song request detected');
              return;
            }
          }

          res = await http
              .get(url)
              .timeout(
                const Duration(seconds: 15),
                onTimeout: () => throw Exception('Request timeout'),
              );

          // Success - break out of retry loop
          if (res.statusCode == 200) {
            if (attempt > 0) {
              debugPrint('✅ Retry successful on attempt ${attempt + 1}');
            }
            break;
          }

          // Non-retryable error codes
          if (res.statusCode == 404 || res.statusCode == 403) {
            throw Exception('API Error: ${res.statusCode}');
          }

          // Retryable error (5xx)
          lastError = Exception('API Error: ${res.statusCode}');
          if (attempt < maxRetries - 1) {
            debugPrint('⚠️ API returned ${res.statusCode}, will retry...');
          }
        } catch (e) {
          lastError = e is Exception ? e : Exception(e.toString());
          if (attempt < maxRetries - 1) {
            debugPrint('⚠️ Request failed: $e, will retry...');
          }
        }
      }

      // If all retries failed
      if (res == null || res.statusCode != 200) {
        throw lastError ?? Exception('API Error: Unknown');
      }

      // RACE CONDITION CHECK: If another song started while we were waiting, ABORT.
      if (localGenerationId != _currentSongGenerationId) {
        debugPrint(
          '🛑 Play request aborted: Newer song request detected (Gen: $_currentSongGenerationId vs Local: $localGenerationId)',
        );
        return;
      }

      var data = json.decode(res.body);

      if (data['data'] == null) {
        throw Exception('No data in API response');
      }

      String manifestMimeType = data['data']['manifestMimeType'] ?? '';
      String? directUrl = data['data']['directUrl'] as String?;

      // For lossless without Hi-Res, use direct URL if available
      if (song.isLossless &&
          !song.isHiRes &&
          directUrl != null &&
          directUrl.isNotEmpty) {
        debugPrint('🎵 Direct audio URL: $directUrl');

        // Fetch actual file size in background (don't await)
        _fetchAndUpdateFileSize(directUrl, song);

        // RACE CONDITION CHECK AGAIN prior to native calls
        if (localGenerationId != _currentSongGenerationId) return;

        // Set source first (Use setSource for direct URLs, not setDashSource)
        await setSource(directUrl);
        // await _channel.invokeMethod('setDashSource', {'url': directUrl});

        // Clear loading IMMEDIATELY after source is set, BEFORE play()
        // This ensures UI is responsive without waiting for events
        _isLoading = false;
        _loadingStatus = '';
        _isPlaying = true;
        _isSongEnding = false; // Reset AFTER loading, ready to play
        _isTransitioning = false; // Allow position updates again
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

      // RACE CONDITION CHECK AGAIN prior to native calls
      if (localGenerationId != _currentSongGenerationId) return;

      if (manifestMimeType == 'application/dash+xml' ||
          manifestDecoded.startsWith('<?xml')) {
        debugPrint("🎵 Hi-Res DASH manifest detected, processing...");
        await _playDashStream(song, manifestDecoded);
      } else {
        // Regular manifest with direct URL
        Map manifest = json.decode(manifestDecoded);
        String audioUrl = manifest['urls'][0];

        debugPrint('🎵 Regular audio source: $audioUrl');

        // Use setSource for regular playback
        await setSource(audioUrl);

        _isPlaying = true;
        _isSongEnding = false; // Reset AFTER loading, ready to play
        _isTransitioning = false; // Allow position updates again
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
      // Only handle error if we are still the relevant request
      if (localGenerationId == _currentSongGenerationId) {
        debugPrint('❌ Error playing Hi-Res song: $e');
        _isLoading = false;
        _isSongEnding = false; // Reset on error too
        _isTransitioning = false; // Allow position updates again
        _loadingStatus = 'Error: $e';
        notifyListeners();
      } else {
        debugPrint('❌ Error ignored in aborted request: $e');
      }
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
        (match) => '&amp;',
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
      mpdContent = mpdContent.replaceAll(
        RegExp(r'minBufferTime="[^"]*"'),
        'minBufferTime="PT2S"',
      );

      // Remove profiles that indicate live streaming capabilities
      mpdContent = mpdContent.replaceAll(
        'urn:mpeg:dash:profile:isoff-live:2011',
        'urn:mpeg:dash:profile:isoff-on-demand:2011',
      );

      // Ensure mediaPresentationDuration exists for VOD seeking
      if (!mpdContent.contains('mediaPresentationDuration')) {
        // Try to extract duration from Period element
        debugPrint(
          '⚠️  No mediaPresentationDuration found, attempting to extract from segments',
        );

        // For DASH, if no duration, set a large one to prevent live detection
        mpdContent = mpdContent.replaceFirst(
          '<MPD',
          '<MPD mediaPresentationDuration="PT1H"',
        );
      }

      debugPrint('📋 DASH Manifest Preparation:');
      debugPrint(
        '   - Type: ${mpdContent.contains('type="static"') ? 'Static (VOD)' : 'Dynamic (Live)'}',
      );
      debugPrint(
        '   - Has Duration: ${mpdContent.contains('mediaPresentationDuration')}',
      );
      debugPrint(
        '   - minBufferTime: ${RegExp(r'minBufferTime="[^"]*"').firstMatch(mpdContent)?.group(0) ?? 'default'}',
      );
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
      _isTransitioning = false; // Allow position updates again
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
      _isSongEnding = false;
      _isTransitioning = false; // Allow position updates again on error
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
      if (_lastSeekTime != null &&
          now.difference(_lastSeekTime!) < _seekCooldown) {
        debugPrint(
          '⏱️  Seek throttled (cooldown ${_seekCooldown.inMilliseconds}ms)',
        );
        return;
      }
      _lastSeekTime = now;

      // Ensure a song is loaded
      if (_currentSong == null) {
        debugPrint('⚠️ Warning: No song loaded, cannot seek');
        return;
      }

      debugPrint(
        '⏩ Seeking to ${position.inMilliseconds}ms (${_formatDuration(position)})',
      );

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

  Future<void> setDashSource(String url) async {
    try {
      await _channel.invokeMethod('setDashSource', {'url': url});
      debugPrint('✅ ExoPlayer: DASH Source set - $url');
    } catch (e) {
      debugPrint('❌ Error setting source: $e');
      throw Exception('Failed to set source: $e');
    }
  }

  /// Set source for standard audio streaming (Lossless/Regular)
  Future<void> setSource(String url) async {
    try {
      // Assuming native plugin has setSource or setUrl.
      // If not, we might need setDashSource but usually that's for DASH.
      // Trying "setSource" as a likely method name given standard plugins.
      // If this fails, we might need to fallback.
      await _channel.invokeMethod('setSource', {'url': url});
      debugPrint('✅ ExoPlayer: Standard Source set - $url');
    } catch (e) {
      debugPrint('❌ Error setting standard source: $e');
      // Fallback: try setDashSource if setSource fails (unlikely if plugin handles both)
      try {
        debugPrint('⚠️ fallback to setDashSource...');
        await _channel.invokeMethod('setDashSource', {'url': url});
      } catch (e2) {
        throw Exception('Failed to set standard source: $e');
      }
    }
  }

  Future<Map<String, dynamic>?> getManifestInfo() async {
    try {
      final info = await _channel.invokeMethod<Map<String, dynamic>>(
        'getManifestInfo',
      );
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

  Future<void> clearQueue() async {
    debugPrint('🗑️ Clear Queue: Triggering collapse animation');
    shouldExpandPlayer.value = -1; // Trigger collapse animation immediately

    // Pause audio first (stops sound, keeps metadata visible)
    try {
      if (_isPlaying) {
        await pause();
      }
    } catch (e) {
      debugPrint('Error pausing: $e');
    }

    // Wait for animation to finish (ExpandablePlayer duration is 300ms)
    await Future.delayed(const Duration(milliseconds: 400));

    debugPrint('🗑️ Clear Queue: Clearing data');
    await stop(); // Stops playback fully and clears current song
    _queue.clear();
    _currentIndex = -1;
    _currentSong = null;
    _isPlaying = false;
    _position = Duration.zero;
    _duration = Duration.zero;
    _isLoading = false;
    notifyListeners();
  }

  /// Add song to queue right after current song (Play Next)
  void addToQueueNext(Song song) {
    if (_currentIndex >= 0 && _currentIndex < _queue.length - 1) {
      // Insert after current song
      _queue.insert(_currentIndex + 1, song);
      debugPrint('▶️ Added "${song.title}" to play next');
    } else {
      // No current song or at end, just add to queue
      _queue.add(song);
      debugPrint('▶️ Added "${song.title}" to queue');
    }
    notifyListeners();
  }

  /// Add song to end of queue
  void addToQueueEnd(Song song) {
    _queue.add(song);
    debugPrint('➕ Added "${song.title}" to end of queue');
    notifyListeners();
  }

  /// Play queue of songs starting from specific index
  Future<void> playQueue(
    List<Song> songs,
    int startIndex, {
    bool userInitiated = false,
  }) async {
    debugPrint(
      '📋 playQueue called with ${songs.length} songs, startIndex: $startIndex',
    );

    // Trigger player expand IMMEDIATELY if user initiated (don't wait for loading)
    if (userInitiated) {
      if (shouldExpandPlayer.value <= 0) {
        shouldExpandPlayer.value = 1; // Start fresh positive
      } else {
        shouldExpandPlayer.value++; // Increment
      }
    }

    _queue = List.from(songs);
    _currentIndex = startIndex;

    debugPrint(
      '📋 Queue set: ${_queue.length} songs, currentIndex: $_currentIndex',
    );

    if (_queue.isNotEmpty && _currentIndex < _queue.length) {
      final song = _queue[_currentIndex];
      debugPrint('📋 Playing: ${song.title}');
      await playHiResSong(song);
    }

    notifyListeners();
  }

  /// Toggle play/pause - fully reactive, no optimistic updates
  Future<void> togglePlayPause() async {
    debugPrint(
      '🔄 togglePlayPause called | isPlaying=$_isPlaying | state=$_playbackState',
    );

    // No optimistic update - wait for native event to update _isPlaying
    try {
      if (_isPlaying) {
        debugPrint('⏸️  Calling pause()...');
        await pause();
      } else {
        // If player is idle (no source loaded) but we have a song, load it first
        if (_playbackState == 'idle' && _currentSong != null) {
          debugPrint('📥 Player idle, loading song: ${_currentSong!.title}');
          await playHiResSong(_currentSong!);
        } else {
          // Player has source (Ready/Buffering/Ended), just play
          debugPrint('▶️  Calling play()...');
          await play();
        }
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
    debugPrint(
      '⏭️ playNext called | queue.length=${_queue.length} | currentIndex=$_currentIndex',
    );

    if (_queue.isEmpty) {
      debugPrint('⚠️ Queue is empty, cannot skip next');
      return;
    }

    if (_currentIndex < _queue.length - 1) {
      _currentIndex++;
      final nextSong = _queue[_currentIndex];
      debugPrint(
        '⏭️ Playing next song: ${nextSong.title} (index $_currentIndex)',
      );
      await playHiResSong(nextSong);
    } else {
      debugPrint('⚠️ Already at last song in queue');
    }
  }

  /// Play previous song in queue
  Future<void> playPrevious() async {
    debugPrint(
      '⏮️ playPrevious called | queue.length=${_queue.length} | currentIndex=$_currentIndex',
    );

    if (_queue.isEmpty) {
      debugPrint('⚠️ Queue is empty, cannot skip previous');
      return;
    }

    if (_currentIndex > 0) {
      _currentIndex--;
      final prevSong = _queue[_currentIndex];
      debugPrint(
        '⏮️ Playing previous song: ${prevSong.title} (index $_currentIndex)',
      );
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

  // Sleep Timer Methods
  void setSleepTimer(double sliderValue) {
    cancelSleepTimer(); // Clear existing

    if (sliderValue <= 0) {
      debugPrint('⏰ Sleep Timer: Cancelled');
      notifyListeners();
      return;
    }

    if (sliderValue >= 13) {
      // End of Song Mode
      _stopAfterCurrentSong = true;
      debugPrint('⏰ Sleep Timer: Set to End of Song');
    } else {
      // Countdown Mode
      int minutes = (sliderValue * 5).toInt();
      if (sliderValue == 0.33) {
        // Debug: 20 seconds
        _sleepTimerDuration = const Duration(seconds: 20);
        debugPrint('⏰ Sleep Timer: Set to 20 seconds (Debug)');
      } else {
        _sleepTimerDuration = Duration(minutes: minutes);
        debugPrint('⏰ Sleep Timer: Set to $minutes minutes');
      }

      _sleepTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
        if (_sleepTimerDuration == null) {
          timer.cancel();
          return;
        }

        final newDuration = _sleepTimerDuration! - const Duration(seconds: 1);
        if (newDuration.inSeconds <= 0) {
          // Time's up!
          debugPrint('⏰ Sleep Timer: Time is up!');
          _sleepTimerDuration = Duration.zero; // Ensure zero for UI
          setVolume(0.0); // Ensure silence
          if (_isPlaying) {
            await pause(); // Pause playback
          }
          cancelSleepTimer(); // Reset state and volume to 1.0
        } else {
          _sleepTimerDuration = newDuration;
        }

        // Fade out logic (Last 10 seconds)
        if (_sleepTimerDuration != null &&
            _sleepTimerDuration!.inSeconds <= 10) {
          final secondsLeft = _sleepTimerDuration!.inSeconds;
          final volume = (secondsLeft / 10.0).clamp(0.0, 1.0);
          setVolume(volume);
        }

        notifyListeners();
      });
    }
    setVolume(1.0); // Reset volume when setting timer
    notifyListeners();
  }

  void addSleepTimerDuration(Duration d) {
    if (_sleepTimerDuration != null) {
      _sleepTimerDuration = _sleepTimerDuration! + d;
      notifyListeners();
    } else {
      // If not running, maybe start it?
      // User said "kalau timer lagi jalan".
      // So assume only when running.
    }
  }

  void cancelSleepTimer() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepTimerDuration = null;
    _stopAfterCurrentSong = false;
    setVolume(1.0); // Reset volume
    notifyListeners();
  }

  Future<void> setVolume(double volume) async {
    try {
      await _channel.invokeMethod('setVolume', {'volume': volume});
    } catch (e) {
      debugPrint('❌ Error setting volume: $e');
    }
  }

  @override
  void dispose() {
    _eventSubscription?.cancel();
    _periodicUpdateTimer?.cancel();
    _positionTimer?.cancel();
    _positionController?.close();
    _sleepTimer?.cancel();
    stop();
    super.dispose();
  }
}
