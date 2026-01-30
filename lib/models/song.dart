class Song {
  final String id;
  final String title;
  final String artist;
  final String albumTitle;
  final String? albumCover;
  final int duration;
  final bool isHiRes;
  final List<String> mediaTags;
  
  // File size in bytes (fetched from API/streaming URL)
  int? fileSize;

  Song({
    required this.id,
    required this.title,
    required this.artist,
    required this.albumTitle,
    this.albumCover,
    required this.duration,
    this.isHiRes = false,
    this.mediaTags = const [],
    this.fileSize,
  });

  // Check if song is Lossless (but not Hi-Res)
  bool get isLossless => !isHiRes && mediaTags.contains("LOSSLESS");
  
  // Get file size in MB formatted string
  String? get fileSizeMB {
    if (fileSize == null) return null;
    double mb = fileSize! / (1024 * 1024);
    if (mb >= 100) {
      return '${mb.toStringAsFixed(0)} MB';
    } else if (mb >= 10) {
      return '${mb.toStringAsFixed(1)} MB';
    } else {
      return '${mb.toStringAsFixed(2)} MB';
    }
  }
  
  // Estimate file size if not fetched yet
  String get estimatedFileSizeMB {
    // More accurate estimation:
    // 24-bit/44.1kHz FLAC: ~12 MB per minute
    // 16-bit/44.1kHz FLAC: ~5.5 MB per minute
    double mbPerMinute = isHiRes ? 12.0 : 5.5;
    double minutes = duration / 60.0;
    double sizeMB = mbPerMinute * minutes;
    
    if (sizeMB >= 100) {
      return '${sizeMB.toStringAsFixed(0)} MB';
    } else if (sizeMB >= 10) {
      return '${sizeMB.toStringAsFixed(1)} MB';
    } else {
      return '${sizeMB.toStringAsFixed(1)} MB';
    }
  }

  factory Song.fromJson(Map<String, dynamic> json) {
    // Check if this is from API or from local storage
    if (json.containsKey('mediaMetadata') || json.containsKey('album')) {
      // From API
      List mediaTags = json['mediaMetadata']?['tags'] is List 
          ? json['mediaMetadata']['tags'] 
          : [];
      
      String? coverUrl;
      if (json['album']?['cover'] != null) {
        coverUrl = 'https://resources.tidal.com/images/${json['album']['cover'].toString().replaceAll('-', '/')}/640x640.jpg';
      }

      return Song(
        id: json['id'].toString(),
        title: json['title'] ?? 'Unknown',
        artist: (json['artists'] as List?)?.map((a) => a['name']).join(', ') ?? 'Unknown Artist',
        albumTitle: json['album']?['title'] ?? 'Unknown Album',
        albumCover: coverUrl,
        duration: json['duration'] ?? 0,
        isHiRes: mediaTags.contains("HIRES_LOSSLESS"),
        mediaTags: List<String>.from(mediaTags),
      );
    } else {
      // From local storage
      return Song(
        id: json['id'].toString(),
        title: json['title'] ?? 'Unknown',
        artist: json['artist'] ?? 'Unknown Artist',
        albumTitle: json['albumTitle'] ?? 'Unknown Album',
        albumCover: json['albumCover'],
        duration: json['duration'] ?? 0,
        isHiRes: json['isHiRes'] ?? false,
        mediaTags: List<String>.from(json['mediaTags'] ?? []),
      );
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'artist': artist,
      'albumTitle': albumTitle,
      'albumCover': albumCover,
      'duration': duration,
      'isHiRes': isHiRes,
      'mediaTags': mediaTags,
    };
  }

  String get durationFormatted {
    int minutes = duration ~/ 60;
    int seconds = duration % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  String get qualityLabel => isHiRes ? 'Hi-Res' : 'Lossless';
}
