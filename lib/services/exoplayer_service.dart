import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import '../models/song.dart';
import 'play_history_service.dart';
import '../models/loop_mode.dart'; // Import LoopMode
import 'lyrics_service.dart';

/// Cache completeness status indicator
enum CacheStatus { none, partial, full }

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

  // Shuffle state tracking (no-repeat cycle)
  final Random _random = Random();
  final List<int> _shuffleHistory = <int>[];
  final Set<int> _shufflePlayed = <int>{};

  bool get isShuffleMode => _isShuffleMode;
  LoopMode get loopMode => _loopMode;

  void toggleShuffle() {
    _isShuffleMode = !_isShuffleMode;
    if (_isShuffleMode) {
      _resetShuffleState(keepCurrent: true);
      debugPrint('🔀 Shuffle enabled');
    } else {
      _resetShuffleState(keepCurrent: false);
      debugPrint('🔀 Shuffle disabled');
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

  void _resetShuffleState({required bool keepCurrent}) {
    _shuffleHistory.clear();
    _shufflePlayed.clear();

    if (!keepCurrent) return;

    final current = _resolveCurrentIndex();
    if (current != -1) {
      _shuffleHistory.add(current);
      _shufflePlayed.add(current);
    }
  }

  void _onQueueStructureChanged() {
    if (_isShuffleMode) {
      _resetShuffleState(keepCurrent: true);
    }
  }

  int _resolveCurrentIndex() {
    if (_currentIndex >= 0 && _currentIndex < _queue.length) {
      return _currentIndex;
    }

    if (_currentSong != null) {
      final resolvedIndex = _queue.indexWhere((s) => s.id == _currentSong!.id);
      if (resolvedIndex != -1) {
        _currentIndex = resolvedIndex;
        return resolvedIndex;
      }
    }

    return -1;
  }

  void _recordShuffleVisit(int index) {
    if (!_isShuffleMode) return;
    if (index < 0 || index >= _queue.length) return;

    _shufflePlayed.add(index);
    if (_shuffleHistory.isEmpty || _shuffleHistory.last != index) {
      _shuffleHistory.add(index);
    }
  }

  int? _nextIndexSequential() {
    if (_queue.isEmpty) return null;

    final current = _resolveCurrentIndex();
    if (current == -1) return 0;

    if (current < _queue.length - 1) {
      return current + 1;
    }

    if (_loopMode == LoopMode.all) {
      return 0;
    }

    return null;
  }

  int? _nextIndexShuffle() {
    if (_queue.isEmpty) return null;

    final current = _resolveCurrentIndex();
    if (current != -1) {
      _recordShuffleVisit(current);
    }

    if (_queue.length == 1) {
      return _loopMode == LoopMode.all ? 0 : null;
    }

    List<int> unplayed = List<int>.generate(_queue.length, (i) => i)
        .where((i) => !_shufflePlayed.contains(i) && i != current)
        .toList();

    if (unplayed.isEmpty) {
      if (_loopMode != LoopMode.all) {
        return null;
      }

      // Start a new cycle but avoid immediate repeat of current song.
      _shufflePlayed.clear();
      if (current != -1) {
        _shufflePlayed.add(current);
      }

      unplayed = List<int>.generate(_queue.length, (i) => i)
          .where((i) => !_shufflePlayed.contains(i) && i != current)
          .toList();
    }

    if (unplayed.isEmpty) return null;

    final next = unplayed[_random.nextInt(unplayed.length)];
    return next;
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

  // Lyrics prefetch state
  final LyricsService _lyricsService = LyricsService();
  final Set<String> _lyricsPrefetchInProgress = <String>{};
  String? _lastPrefetchedLyricsSongId;

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

  /// Prefetch lyrics in background so Lyrics tab opens instantly.
  Future<void> _prefetchLyricsForSong(Song song) async {
    if (song.id.isEmpty) return;
    if (_lastPrefetchedLyricsSongId == song.id) return;
    if (_lyricsPrefetchInProgress.contains(song.id)) return;

    _lyricsPrefetchInProgress.add(song.id);
    try {
      await _lyricsService.fetchLyrics(
        title: song.title,
        artist: song.artist,
        albumName: song.albumTitle,
        durationSeconds: song.duration,
      );
      _lastPrefetchedLyricsSongId = song.id;
      debugPrint('🎤 Lyrics prefetched for: ${song.title}');
    } catch (e) {
      debugPrint('🎤 Lyrics prefetch failed: $e');
    } finally {
      _lyricsPrefetchInProgress.remove(song.id);
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

    // ✅ Song played to completion — mark audio as fully cached
    if (_currentSong != null) {
      _markAudioFullyCached(_currentSong!.id);
    }

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

    // Repeat current track forever until mode changes.
    if (_loopMode == LoopMode.one && _currentSong != null) {
      debugPrint('🔁 Loop one active, replaying current track');
      await playHiResSong(_currentSong!);
      return;
    }

    final nextIndex = _isShuffleMode ? _nextIndexShuffle() : _nextIndexSequential();

    if (nextIndex != null && nextIndex >= 0 && nextIndex < _queue.length) {
      _currentIndex = nextIndex;
      if (_isShuffleMode) {
        _recordShuffleVisit(nextIndex);
      }

      final nextSong = _queue[nextIndex];
      debugPrint('📋 Auto next: ${nextSong.title} (index $nextIndex)');
      // Keep _isSongEnding true until playHiResSong resets it
      await playHiResSong(nextSong);
    } else {
      // No more songs in current mode.
      debugPrint('🔄 End of queue reached, staying at zero');
      _isSongEnding = false;
      _isTransitioning = false;
      seekTo(Duration.zero);
      notifyListeners();
    }

    debugPrint('✅ Song end handled');
  }

  /// Mark a song's audio as fully cached (called when song plays to end)
  Future<void> _markAudioFullyCached(String songId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('audio_full_cached_$songId', true);
      debugPrint('💾 Marked $songId as fully cached audio');
    } catch (e) {
      debugPrint('❌ Failed to mark audio as cached: $e');
    }
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
    
    // 💾 Persist song metadata for the Cache Management screen
    unawaited(SharedPreferences.getInstance().then((prefs) {
      prefs.setString('song_catalog_${song.id}', jsonEncode(song.toJson()));
    }));

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
    unawaited(_prefetchLyricsForSong(song));

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
      // ⚡ CACHE-FIRST: If audio is fully cached, skip the API call entirely
      String quality = song.isHiRes ? "HI_RES_LOSSLESS" : "LOSSLESS";
      debugPrint('🎯 Quality: $quality for song: ${song.title}');
      String prefCacheKey = 'api_cache_${song.id}_$quality';
      final prefs = await SharedPreferences.getInstance();

      final isAudioFullyCached = prefs.getBool('audio_full_cached_${song.id}') ?? false;
      if (isAudioFullyCached) {
        final cachedBody = prefs.getString(prefCacheKey);
        if (cachedBody != null && cachedBody.isNotEmpty) {
          debugPrint('⚡ Cache-first: Skipping API, using local cache for ${song.title}');
          _isLoading = true;
          _loadingStatus = 'Loading from cache...';
          notifyListeners();

          if (localGenerationId != _currentSongGenerationId) return;

          final data = json.decode(cachedBody);
          if (data['data'] != null) {
            final manifestMimeType = data['data']['manifestMimeType'] ?? '';
            final directUrl = data['data']['directUrl'] as String?;

            if (song.isLossless && !song.isHiRes && directUrl != null && directUrl.isNotEmpty) {
              if (localGenerationId != _currentSongGenerationId) return;
              await setSource(directUrl, song.id + '_LOSSLESS');
              _isLoading = false; _loadingStatus = ''; _isPlaying = true;
              _isSongEnding = false; _isTransitioning = false;
              notifyListeners();
              await play();
              await _updateNotification(song);
              debugPrint('✅ Cache-first: Lossless playing from cache!');
              return;
            }

            final manifestB64 = data['data']['manifest'] as String?;
            if (manifestB64 != null) {
              final manifestDecoded = utf8.decode(base64.decode(manifestB64));
              if (manifestMimeType == 'application/dash+xml' || manifestDecoded.startsWith('<?xml')) {
                if (localGenerationId != _currentSongGenerationId) return;
                await _playDashStream(song, manifestDecoded);
                debugPrint('✅ Cache-first: DASH playing from cache!');
                return;
              }
            }
          }
          // Fallthrough: cached data invalid, continue to API call below
          debugPrint('⚠️ Cache-first: Stored response invalid, falling back to API');
        }
      }

      // 🌐 NETWORK: Fetch from API (only if not fully cached or cache miss)
      debugPrint('🌐 API Request for: ${song.title}');

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

      // Create a cache key for API response (already defined above)

      String responseBody = '';

      // If all retries failed
      if (res == null || res.statusCode != 200) {
        String? cachedBody = prefs.getString(prefCacheKey);
        if (cachedBody != null && cachedBody.isNotEmpty) {
            debugPrint('⚠️ Offline/API Error: Using offline cached API response for playback!');
            responseBody = cachedBody;
        } else {
            throw lastError ?? Exception('API Error: Unknown');
        }
      } else {
        responseBody = res.body;
        // Save to cache for future offline play
        await prefs.setString(prefCacheKey, responseBody);
      }

      // RACE CONDITION CHECK: If another song started while we were waiting, ABORT.
      if (localGenerationId != _currentSongGenerationId) {
        debugPrint(
          '🛑 Play request aborted: Newer song request detected (Gen: $_currentSongGenerationId vs Local: $localGenerationId)',
        );
        return;
      }

      var data = json.decode(responseBody);

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
        await setSource(directUrl, song.id + '_LOSSLESS');
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
        await setSource(audioUrl, song.id + '_REGULAR');

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

      // Pass song ID with HIRES suffix for solid caching
      await setDashSource(localServer.manifestUrl, song.id + '_HIRES');
      debugPrint('🌐 Local manifest URL: ${localServer.manifestUrl}');

      _loadingStatus = 'Starting Hi-Res stream...';
      notifyListeners();

      // Use ExoPlayer to stream directly from DASH manifest
      // ExoPlayer will fetch segments from Tidal CDN automatically
      // Note: setDashSource was already called above.
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

  Future<void> setDashSource(String url, String songId) async {
    try {
      await _channel.invokeMethod('setDashSource', {'url': url, 'songId': songId});
      debugPrint('✅ ExoPlayer: DASH Source set - $url');
    } catch (e) {
      debugPrint('❌ Error setting source: $e');
      throw Exception('Failed to set source: $e');
    }
  }

  /// Set source for standard audio streaming (Lossless/Regular)
  Future<void> setSource(String url, String songId) async {
    try {
      // Assuming native plugin has setSource or setUrl.
      // If not, we might need setDashSource but usually that's for DASH.
      // Trying "setSource" as a likely method name given standard plugins.
      // If this fails, we might need to fallback.
      await _channel.invokeMethod('setSource', {'url': url, 'songId': songId});
      debugPrint('✅ ExoPlayer: Standard Source set - $url');
    } catch (e) {
      debugPrint('❌ Error setting standard source: $e');
      // Fallback: try setDashSource if setSource fails (unlikely if plugin handles both)
      try {
        debugPrint('⚠️ fallback to setDashSource...');
        await _channel.invokeMethod('setDashSource', {'url': url, 'songId': songId});
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
    _onQueueStructureChanged();
    notifyListeners();
  }

  /// Play an existing item from queue without rebuilding queue.
  Future<void> playAtQueueIndex(int index, {bool userInitiated = false}) async {
    if (index < 0 || index >= _queue.length) return;

    if (userInitiated) {
      if (shouldExpandPlayer.value <= 0) {
        shouldExpandPlayer.value = 1;
      } else {
        shouldExpandPlayer.value++;
      }
    }

    _currentIndex = index;
    _recordShuffleVisit(index);
    final song = _queue[index];
    await playHiResSong(song);
    notifyListeners();
  }

  /// Reorder queue item positions.
  void reorderQueue(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _queue.length) return;
    if (newIndex < 0 || newIndex >= _queue.length) return;
    if (oldIndex == newIndex) return;

    final moved = _queue.removeAt(oldIndex);
    _queue.insert(newIndex, moved);

    if (_currentIndex == oldIndex) {
      _currentIndex = newIndex;
    } else if (oldIndex < _currentIndex && newIndex >= _currentIndex) {
      _currentIndex--;
    } else if (oldIndex > _currentIndex && newIndex <= _currentIndex) {
      _currentIndex++;
    }

    _onQueueStructureChanged();
    notifyListeners();
  }

  /// Move an existing queue item so it plays right after current song.
  void moveToPlayNext(int index) {
    if (index < 0 || index >= _queue.length) return;
    if (_queue.length <= 1) return;
    if (_currentIndex < 0 || _currentIndex >= _queue.length) return;

    var targetIndex = _currentIndex + 1;
    if (index < targetIndex) {
      targetIndex -= 1;
    }
    targetIndex = targetIndex.clamp(0, _queue.length - 1);

    if (index == targetIndex) return;

    reorderQueue(index, targetIndex);
  }

  void removeFromQueue(int index) {
    if (index >= 0 && index < _queue.length) {
      _queue.removeAt(index);
      if (index <= _currentIndex) {
        _currentIndex--;
      }
      if (_queue.isEmpty) {
        _currentIndex = -1;
      }
      _onQueueStructureChanged();
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
    _resetShuffleState(keepCurrent: false);
    notifyListeners();
  }

  /// Add song to queue right after current song (Play Next)
  void addToQueueNext(Song song) {
    int activeIndex = -1;

    // 1) Prefer tracked current index when valid.
    if (_currentIndex >= 0 && _currentIndex < _queue.length) {
      activeIndex = _currentIndex;
    }

    // 2) Fallback: resolve active song from queue by song id.
    if (activeIndex == -1 && _currentSong != null) {
      activeIndex = _queue.indexWhere((s) => s.id == _currentSong!.id);
      if (activeIndex != -1) {
        _currentIndex = activeIndex;
      }
    }

    // 3) If song already exists in queue, move it instead of duplicating.
    final existingIndex = _queue.indexWhere((s) => s.id == song.id);
    if (existingIndex != -1) {
      if (activeIndex == -1) {
        // No active anchor -> place existing song at top of queue.
        reorderQueue(existingIndex, 0);
        debugPrint('▶️ Moved "${song.title}" to top of queue');
      } else {
        moveToPlayNext(existingIndex);
        debugPrint('▶️ Moved "${song.title}" to play next');
      }
      return;
    }

    // 4) Insert new song after active song, or at top when no active song.
    final insertIndex = activeIndex == -1 ? 0 : (activeIndex + 1);
    _queue.insert(insertIndex, song);

    // Keep current pointer stable if insertion happens before current index.
    if (_currentIndex >= insertIndex && _currentIndex != -1) {
      _currentIndex++;
    }

    _onQueueStructureChanged();

    debugPrint(
      '▶️ Added "${song.title}" at index $insertIndex (after active index $activeIndex)',
    );
    notifyListeners();
  }

  /// Add song to end of queue
  void addToQueueEnd(Song song) {
    _queue.add(song);
    _onQueueStructureChanged();
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

    if (_isShuffleMode) {
      _resetShuffleState(keepCurrent: true);
    }

    debugPrint(
      '📋 Queue set: ${_queue.length} songs, currentIndex: $_currentIndex',
    );

    if (_queue.isNotEmpty && _currentIndex < _queue.length) {
      final song = _queue[_currentIndex];
      _recordShuffleVisit(_currentIndex);
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

    final nextIndex = _isShuffleMode ? _nextIndexShuffle() : _nextIndexSequential();

    if (nextIndex == null || nextIndex < 0 || nextIndex >= _queue.length) {
      debugPrint('⚠️ No next song for current mode');
      return;
    }

    _currentIndex = nextIndex;
    if (_isShuffleMode) {
      _recordShuffleVisit(nextIndex);
    }

    final nextSong = _queue[nextIndex];
    debugPrint('⏭️ Playing next song: ${nextSong.title} (index $nextIndex)');
    await playHiResSong(nextSong);
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

    if (_isShuffleMode) {
      final current = _resolveCurrentIndex();
      if (current != -1) {
        _recordShuffleVisit(current);
      }

      if (_shuffleHistory.length > 1) {
        // Remove current and use the previous visited index.
        _shuffleHistory.removeLast();
        final prevIndex = _shuffleHistory.last;
        _currentIndex = prevIndex;
        final prevSong = _queue[prevIndex];
        debugPrint(
          '⏮️ Playing previous (shuffle history): ${prevSong.title} (index $prevIndex)',
        );
        await playHiResSong(prevSong);
      } else {
        debugPrint('⏮️ No previous in shuffle history, restarting current song');
        await seekTo(Duration.zero);
      }
      return;
    }

    final current = _resolveCurrentIndex();
    int? prevIndex;

    if (current > 0) {
      prevIndex = current - 1;
    } else if (current == 0 && _loopMode == LoopMode.all) {
      prevIndex = _queue.length - 1;
    }

    if (prevIndex != null && prevIndex >= 0 && prevIndex < _queue.length) {
      _currentIndex = prevIndex;
      final prevSong = _queue[prevIndex];
      debugPrint('⏮️ Playing previous song: ${prevSong.title} (index $prevIndex)');
      await playHiResSong(prevSong);
    } else {
      // At start in non-loop mode: restart current song.
      debugPrint('⏮️ At start, restarting current song');
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
      String localAlbumCover = song.albumCover ?? '';
      
      if (localAlbumCover.isNotEmpty && localAlbumCover.startsWith('http')) {
        try {
          // Pre-fetch and cache the image using DefaultCacheManager
          final file = await DefaultCacheManager().getSingleFile(localAlbumCover);
          localAlbumCover = 'file://${file.path}';
          debugPrint('🖼️ Album art cached locally: \${file.path}');
        } catch (e) {
          debugPrint('❌ Failed to fetch local album cover: $e');
        }
      }

      await _channel.invokeMethod('updateMetadata', {
        'title': song.title,
        'artist': song.artist,
        'albumCover': localAlbumCover,
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

  /// Get the cache status of a given song
  Future<CacheStatus> getSongCacheStatus(Song song, String quality) async {
      try {
          bool hasAnyCache = false;
          bool isComplete = true; // Assume true until a missing piece is found

          // 1. Check Album Art
          if (song.albumCover != null && song.albumCover!.isNotEmpty) {
              final fileInfo = await DefaultCacheManager().getFileFromCache(song.albumCover!);
              if (fileInfo != null) {
                  hasAnyCache = true;
              } else {
                  isComplete = false;
              }
          }

          // 2. Check Lyrics Cache
          final prefs = await SharedPreferences.getInstance();
          final cacheKey = '${song.artist.split(',').first.trim().toLowerCase()}_${song.title.toLowerCase()}';
          final plain = prefs.getString('lyrics_plain_$cacheKey');
          final syncStr = prefs.getString('lyrics_sync_$cacheKey');
          if ((plain != null && plain.isNotEmpty) || (syncStr != null && syncStr.isNotEmpty)) {
              hasAnyCache = true;
          } else {
              isComplete = false;
          }

          // 3. Check Audio Native Cache
          String songIdForCache = song.id + (quality.contains('LOSSLESS') ? '_LOSSLESS' : 
                                  quality.contains('HI_RES') ? '_HIRES' : '_REGULAR');
                                  
          int cachedBytes = 0;
          try {
              cachedBytes = await _channel.invokeMethod('getAudioCachedBytes', {'songId': songIdForCache}) ?? 0;
          } catch(e) {
              debugPrint('Failed to get audio cache bytes: $e');
          }

          if (cachedBytes > 0) {
              hasAnyCache = true;
              // For non-DASH (lossless/regular), we can check by file size.
              if (song.fileSize != null && song.fileSize! > 0) {
                  // Allow 1% margin of error
                  if (cachedBytes < (song.fileSize! * 0.99)) {
                      isComplete = false;
                  }
              } else {
                  // For DASH Hi-Res, we cannot reliably calculate total size.
                  // Instead, check if we've stored a "played to end" flag.
                  final fullyPlayed = prefs.getBool('audio_full_cached_${song.id}') ?? false;
                  if (!fullyPlayed) {
                      isComplete = false;
                  }
              }
          } else {
              isComplete = false;
          }

          if (!hasAnyCache) return CacheStatus.none;
          if (hasAnyCache && isComplete) return CacheStatus.full;
          return CacheStatus.partial;

      } catch(e) {
         return CacheStatus.none;
      }
  }

  /// Get cached bytes in native layer for a song by its raw ID
  Future<int> getAudioCachedBytes(String songId) async {
    try {
      return await _channel.invokeMethod<int>('getAudioCachedBytes', {'songId': songId}) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// Get total cached bytes across all songs
  Future<int> getTotalCachedBytes() async {
    try {
      return await _channel.invokeMethod<int>('getTotalCachedBytes') ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// Clear native audio cache for a specific song
  Future<void> clearSongCache(String songId) async {
    try {
      await _channel.invokeMethod('clearSongCache', {'songId': songId});
    } catch (e) {
      debugPrint('❌ clearSongCache error: $e');
    }
  }

  /// Clear ALL native audio cache
  Future<void> clearAllCache() async {
    try {
      await _channel.invokeMethod('clearAllCache');
    } catch (e) {
      debugPrint('❌ clearAllCache error: $e');
    }
  }

  /// Set cache size limit (bytes)
  Future<void> setCacheSize(int bytes) async {
    try {
      await _channel.invokeMethod('setCacheSize', {'bytes': bytes});
    } catch (e) {
      debugPrint('❌ setCacheSize error: $e');
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
