class Song {
  final String id;
  final String title;
  final String artist;
  final String albumTitle;
  final String? albumCover;
  final int duration;
  final bool isHiRes;
  final List<String> mediaTags;

  Song({
    required this.id,
    required this.title,
    required this.artist,
    required this.albumTitle,
    this.albumCover,
    required this.duration,
    this.isHiRes = false,
    this.mediaTags = const [],
  });

  // Check if song is Lossless (but not Hi-Res)
  bool get isLossless => !isHiRes && mediaTags.contains("LOSSLESS");

  factory Song.fromJson(Map<String, dynamic> json) {
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
  }

  String get durationFormatted {
    int minutes = duration ~/ 60;
    int seconds = duration % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  String get qualityLabel => isHiRes ? 'Hi-Res' : 'Lossless';
}
