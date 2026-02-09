import 'gradient_config.dart';

class Playlist {
  final String id;
  final String name;
  final List<String> songIds; // Store song IDs
  final DateTime createdAt;
  final String? coverPath;
  final GradientConfig? gradientConfig;

  const Playlist({
    required this.id,
    required this.name,
    required this.songIds,
    required this.createdAt,
    this.coverPath,
    this.gradientConfig,
  });

  // Create from JSON
  factory Playlist.fromJson(Map<String, dynamic> json) => Playlist(
    id: json['id'] as String,
    name: json['name'] as String,
    songIds: List<String>.from(json['songIds'] as List),
    createdAt: DateTime.parse(json['createdAt'] as String),
    coverPath: json['coverPath'] as String?,
    gradientConfig: json['gradientConfig'] != null
        ? GradientConfig.fromJson(
            json['gradientConfig'] as Map<String, dynamic>,
          )
        : null,
  );

  // Convert to JSON
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'songIds': songIds,
    'createdAt': createdAt.toIso8601String(),
    'coverPath': coverPath,
    'gradientConfig': gradientConfig?.toJson(),
  };

  // Copy with
  Playlist copyWith({
    String? id,
    String? name,
    List<String>? songIds,
    DateTime? createdAt,
    String? coverPath,
    GradientConfig? gradientConfig,
  }) {
    return Playlist(
      id: id ?? this.id,
      name: name ?? this.name,
      songIds: songIds ?? this.songIds,
      createdAt: createdAt ?? this.createdAt,
      coverPath: coverPath ?? this.coverPath,
      gradientConfig: gradientConfig ?? this.gradientConfig,
    );
  }

  // Add song
  Playlist addSong(String songId) {
    if (songIds.contains(songId)) return this;
    return copyWith(songIds: [...songIds, songId]);
  }

  // Remove song
  Playlist removeSong(String songId) {
    return copyWith(songIds: songIds.where((id) => id != songId).toList());
  }
}
