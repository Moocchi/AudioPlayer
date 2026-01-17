import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import '../models/song.dart';

// Custom StreamAudioSource untuk Hi-Res streaming
class ByteStreamSource extends StreamAudioSource {
  final List<int> _buffer = [];
  bool _isCompleted = false;
  
  void addBytes(List<int> bytes) {
    if (!_isCompleted) {
      _buffer.addAll(bytes);
      debugPrint("Added ${bytes.length} bytes to stream, total buffer: ${_buffer.length} bytes");
    }
  }
  
  void complete() {
    _isCompleted = true;
  }
  
  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    start = start ?? 0;
    
    debugPrint("StreamAudioSource request: start=$start, end=$end, buffer_size=${_buffer.length}, completed=$_isCompleted");
    
    // Tunggu sampai ada data di buffer
    while (_buffer.isEmpty && !_isCompleted) {
      await Future.delayed(Duration(milliseconds: 100));
    }
    
    if (start >= _buffer.length && _isCompleted) {
      // Return empty response jika sudah selesai dan start melebihi buffer
      return StreamAudioResponse(
        sourceLength: _buffer.length,
        contentLength: 0,
        offset: start,
        stream: Stream.value(Uint8List(0)),
        contentType: 'audio/mp4',
      );
    }
    
    end = end ?? _buffer.length;
    if (end > _buffer.length) {
      end = _buffer.length;
    }
    
    if (start >= end) {
      return StreamAudioResponse(
        sourceLength: _isCompleted ? _buffer.length : null,
        contentLength: 0,
        offset: start,
        stream: Stream.value(Uint8List(0)),
        contentType: 'audio/mp4',
      );
    }
    
    final chunk = _buffer.sublist(start, end);
    debugPrint("Serving chunk: start=$start, end=$end, chunk_size=${chunk.length}");
    
    return StreamAudioResponse(
      sourceLength: _isCompleted ? _buffer.length : null,
      contentLength: chunk.length,
      offset: start,
      stream: Stream.value(Uint8List.fromList(chunk)),
      contentType: 'audio/mp4',
    );
  }
}

class AudioService extends ChangeNotifier {
  static final AudioService _instance = AudioService._internal();
  factory AudioService() => _instance;
  AudioService._internal() {
    _initPlayer();
  }

  final AudioPlayer _player = AudioPlayer();
  Song? _currentSong;
  List<Song> _queue = [];
  int _currentIndex = -1;
  bool _isLoading = false;
  String _loadingStatus = '';
  
  bool _isDownloadingHiRes = false;
  int _downloadedSegments = 0;
  int _totalSegments = 0;
  File? _currentHiResFile;
  ByteStreamSource? _currentStreamSource;

  AudioPlayer get player => _player;
  Song? get currentSong => _currentSong;
  List<Song> get queue => _queue;
  int get currentIndex => _currentIndex;
  bool get isLoading => _isLoading;
  String get loadingStatus => _loadingStatus;
  bool get isPlaying => _player.playing;
  Duration get position => _player.position;
  Duration get duration => _player.duration ?? Duration.zero;
  Stream<Duration> get positionStream => _player.positionStream;
  Stream<PlayerState> get playerStateStream => _player.playerStateStream;
  bool get isDownloadingHiRes => _isDownloadingHiRes;
  String get downloadProgress => _totalSegments > 0 ? '$_downloadedSegments/$_totalSegments' : '';

  void _initPlayer() {
    _player.playerStateStream.listen((state) {
      notifyListeners();
    });
    _player.positionStream.listen((_) {
      notifyListeners();
    });
    _player.processingStateStream.listen((state) {
      debugPrint("Processing state changed: $state (downloading: $_isDownloadingHiRes)");
      
      if (state == ProcessingState.completed) {
        _handlePlaybackComplete();
      }
    });
  }

  void _handlePlaybackComplete() {
    debugPrint("Playback completed - downloading: $_isDownloadingHiRes");
    
    // Jika masih download, artinya lagu memang selesai
    if (_isDownloadingHiRes) {
      debugPrint("Hi-Res playback completed, playing next song");
    }
    playNext();
  }

  Future<void> playQueue(List<Song> songs, int startIndex) async {
    _queue = List.from(songs);
    _currentIndex = startIndex;
    await _playSong(_queue[startIndex]);
  }

  void addToQueue(Song song) {
    _queue.add(song);
    notifyListeners();
  }

  Future<void> playNext() async {
    if (_currentIndex < _queue.length - 1) {
      _currentIndex++;
      await _playSong(_queue[_currentIndex]);
    }
  }

  Future<void> playPrevious() async {
    if (_player.position.inSeconds > 3) {
      await _player.seek(Duration.zero);
    } else if (_currentIndex > 0) {
      _currentIndex--;
      await _playSong(_queue[_currentIndex]);
    }
  }

  Future<void> togglePlayPause() async {
    if (_player.playing) {
      await _player.pause();
    } else {
      await _player.play();
    }
    notifyListeners();
  }

  Future<void> seek(Duration position) async {
    try {
      await _player.seek(position);
    } catch (e) {
      debugPrint("Seek error: $e");
    }
    notifyListeners();
  }

  Future<void> _playSong(Song song) async {
    _stopProgressiveDownload();
    await _player.stop();
    _currentSong = song;
    _isLoading = true;
    _loadingStatus = 'Fetching...';
    _currentHiResFile = null;
    _currentStreamSource = null;
    notifyListeners();

    try {
      String quality = song.isHiRes ? "HI_RES_LOSSLESS" : "LOSSLESS";
      var url = Uri.parse('https://katze.qqdl.site/track/?id=${song.id}&quality=$quality');
      var res = await http.get(url);
      var data = json.decode(res.body);
      String manifestMimeType = data['data']['manifestMimeType'] ?? '';
      String manifestB64 = data['data']['manifest'];
      String manifestDecoded = utf8.decode(base64.decode(manifestB64));

      if (manifestMimeType == 'application/dash+xml' || manifestDecoded.startsWith('<?xml')) {
        debugPrint("Hi-Res DASH manifest detected");
        await _playDashStream(song, manifestDecoded);
      } else {
        Map manifest = json.decode(manifestDecoded);
        String audioUrl = manifest['urls'][0];
        _isLoading = false;
        _loadingStatus = '';
        notifyListeners();
        await _player.setUrl(audioUrl);
        await _player.play();
      }
    } catch (e) {
      debugPrint("Error playing: $e");
      _isLoading = false;
      _loadingStatus = '';
      notifyListeners();
    }
  }

  void _stopProgressiveDownload() {
    _isDownloadingHiRes = false;
    _downloadedSegments = 0;
    _totalSegments = 0;
    _currentStreamSource = null;
  }

  Future<void> _playDashStream(Song song, String manifestDecoded) async {
    String mpdContent = manifestDecoded
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll("&apos;", "'");

    RegExp initRegex = RegExp(r'initialization="([^"]+)"');
    RegExp mediaRegex = RegExp(r'media="([^"]+)"');
    var initMatch = initRegex.firstMatch(mpdContent);
    var mediaMatch = mediaRegex.firstMatch(mpdContent);

    if (initMatch != null && mediaMatch != null) {
      String initUrl = initMatch.group(1)!;
      String mediaUrlTemplate = mediaMatch.group(1)!;
      final tempDir = await getTemporaryDirectory();
      final cachedFile = File('${tempDir.path}/hires_${song.id}.mp4');
      final progressFile = File('${tempDir.path}/hires_progress_${song.id}.mp4');

      // Cek cache lengkap terlebih dahulu
      if (await cachedFile.exists()) {
        final fileSize = await cachedFile.length();
        if (fileSize > 10 * 1024 * 1024) { // Minimal 10MB untuk Hi-Res lengkap
          debugPrint("Playing Hi-Res from complete cache (${fileSize} bytes)");
          _currentHiResFile = cachedFile;
          _isLoading = false;
          _loadingStatus = '';
          notifyListeners();
          await _player.setFilePath(cachedFile.path);
          await _player.play();
          return;
        }
      }

      // Cek apakah sedang ada download yang belum selesai
      if (await progressFile.exists()) {
        final fileSize = await progressFile.length();
        debugPrint("Found incomplete download (${fileSize} bytes), resuming...");
        // Bisa ditambahkan logic untuk resume download dari segment tertentu
        await progressFile.delete(); // Untuk sekarang, hapus dan mulai ulang
      }

      _loadingStatus = 'Starting Hi-Res download...';
      notifyListeners();
      
      // Start progressive download dengan file-based approach
      await _downloadHiResWithStream(song, initUrl, mediaUrlTemplate, cachedFile);
    } else {
      _isLoading = false;
      _loadingStatus = '';
      notifyListeners();
    }
  }

  Future<void> _downloadHiResWithStream(Song song, String initUrl, String mediaUrlTemplate, File cachedFile) async {
    debugPrint("=== Starting Hi-Res Progressive File Download ===");
    
    try {
      _isDownloadingHiRes = true;
      
      // Download init segment
      final initResponse = await http.get(Uri.parse(initUrl));
      if (initResponse.statusCode != 200) throw Exception("Init failed: ${initResponse.statusCode}");
      
      List<int> allBytes = [...initResponse.bodyBytes];
      debugPrint("Init segment: ${initResponse.bodyBytes.length} bytes");
      
      // Download first 5 segments untuk buffer awal
      debugPrint("Downloading first 5 segments for initial playback...");
      
      for (int segmentNum = 1; segmentNum <= 5; segmentNum++) {
        if (_currentSong?.id != song.id) {
          debugPrint("Song changed, stopping download");
          return;
        }
        
        String mediaUrl = mediaUrlTemplate.replaceAll(RegExp(r'\$Number\$'), segmentNum.toString());
        debugPrint("Downloading segment $segmentNum...");
        
        final mediaResponse = await http.get(Uri.parse(mediaUrl));
        if (mediaResponse.statusCode != 200) {
          throw Exception("Segment $segmentNum failed: ${mediaResponse.statusCode}");
        }
        
        allBytes.addAll(mediaResponse.bodyBytes);
        debugPrint("Segment $segmentNum: ${mediaResponse.bodyBytes.length} bytes");
        _downloadedSegments = segmentNum;
        
        _loadingStatus = 'Loading Hi-Res... ($segmentNum/5)';
        notifyListeners();
      }
      
      // Write initial file with 5 segments
      await cachedFile.writeAsBytes(allBytes);
      _currentHiResFile = cachedFile;
      
      debugPrint("First 5 segments ready (${allBytes.length} bytes), starting file playback...");
      
      // Set file dan mulai play
      _isLoading = false;
      _loadingStatus = '';
      notifyListeners();
      
      await _player.setFilePath(cachedFile.path);
      await _player.play();
      
      debugPrint("🎵 File playback started, continuing background download...");
      
      // Lanjutkan download di background
      _downloadRemainingSegmentsToFile(song, mediaUrlTemplate, allBytes, 6, cachedFile);
      
    } catch (e) {
      debugPrint("Error in progressive file download: $e");
      _isLoading = false;
      _loadingStatus = 'Hi-Res download failed';
      _isDownloadingHiRes = false;
      notifyListeners();
    }
  }
  
  Future<void> _downloadRemainingSegmentsToFile(Song song, String mediaUrlTemplate, List<int> allBytes, int startSegment, File cachedFile) async {
    debugPrint("🔄 === BACKGROUND FILE DOWNLOAD STARTED ===");
    debugPrint("Starting from segment $startSegment");
    
    try {
      int segmentNum = startSegment;
      List<int> backgroundBytes = List.from(allBytes); // Copy untuk avoid conflict
      
      while (segmentNum <= 200) { // Max 200 segments
        if (_currentSong?.id != song.id) {
          debugPrint("Song changed, stopping background download");
          return;
        }
        
        String mediaUrl = mediaUrlTemplate.replaceAll(RegExp(r'\$Number\$'), segmentNum.toString());
        
        final mediaResponse = await http.get(Uri.parse(mediaUrl));
        if (mediaResponse.statusCode == 200) {
          backgroundBytes.addAll(mediaResponse.bodyBytes);
          
          debugPrint("Background segment $segmentNum: ${mediaResponse.bodyBytes.length} bytes");
          _downloadedSegments = segmentNum;
          
          // Update file every 5 segments
          if (segmentNum % 5 == 0) {
            await cachedFile.writeAsBytes(backgroundBytes);
            debugPrint("Updated file with segments up to $segmentNum (${backgroundBytes.length} bytes)");
          }
          
          segmentNum++;
          
          // Small delay to prevent overwhelming
          await Future.delayed(Duration(milliseconds: 200));
          
        } else if (mediaResponse.statusCode == 404) {
          debugPrint("Reached end of segments at $segmentNum");
          break;
        } else {
          debugPrint("Background segment $segmentNum failed: ${mediaResponse.statusCode}");
          segmentNum++;
        }
      }
      
      // Download selesai - simpan file lengkap final
      await cachedFile.writeAsBytes(backgroundBytes);
      _isDownloadingHiRes = false;
      
      debugPrint("=== Hi-Res file download complete: ${backgroundBytes.length} bytes ===");
      
    } catch (e) {
      debugPrint("Error in background file download: $e");
      _isDownloadingHiRes = false;
    }
  }

  @override
  void dispose() {
    _stopProgressiveDownload();
    _player.dispose();
    super.dispose();
  }
}
