class VideoItem {
  final String id;
  final String name;
  final String path;
  final String? thumbnail;
  final String? mimeType;
  final Duration? duration;
  final int? size;
  final DateTime? dateModified;
  final int? lastPositionMs;
  final DateTime? lastPlayedAt;
  final int playCount;
  final bool isFavorite;

  VideoItem({
    String? id,
    required this.name,
    required this.path,
    this.thumbnail,
    this.mimeType,
    this.duration,
    this.size,
    this.dateModified,
    this.lastPositionMs,
    this.lastPlayedAt,
    this.playCount = 0,
    this.isFavorite = false,
  }) : id = id ?? path;

  VideoItem copyWith({
    String? id,
    String? name,
    String? path,
    String? thumbnail,
    String? mimeType,
    Duration? duration,
    int? size,
    DateTime? dateModified,
    int? lastPositionMs,
    DateTime? lastPlayedAt,
    int? playCount,
    bool? isFavorite,
  }) {
    return VideoItem(
      id: id ?? this.id,
      name: name ?? this.name,
      path: path ?? this.path,
      thumbnail: thumbnail ?? this.thumbnail,
      mimeType: mimeType ?? this.mimeType,
      duration: duration ?? this.duration,
      size: size ?? this.size,
      dateModified: dateModified ?? this.dateModified,
      lastPositionMs: lastPositionMs ?? this.lastPositionMs,
      lastPlayedAt: lastPlayedAt ?? this.lastPlayedAt,
      playCount: playCount ?? this.playCount,
      isFavorite: isFavorite ?? this.isFavorite,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'path': path,
    'thumbnail': thumbnail,
    'mimeType': mimeType,
    'duration': duration?.inSeconds,
    'size': size,
    'dateModified': dateModified?.toIso8601String(),
    'lastPositionMs': lastPositionMs,
    'lastPlayedAt': lastPlayedAt?.toIso8601String(),
    'playCount': playCount,
    'isFavorite': isFavorite,
  };

  factory VideoItem.fromJson(Map<String, dynamic> json) => VideoItem(
    id: (json['id'] ?? json['path']) as String?,
    name: json['name'] as String,
    path: json['path'] as String,
    thumbnail: json['thumbnail'] as String?,
    mimeType: json['mimeType'] as String?,
    duration: json['duration'] != null
        ? Duration(seconds: json['duration'] as int)
        : null,
    size: json['size'] as int?,
    dateModified: json['dateModified'] != null
        ? DateTime.parse(json['dateModified'] as String)
        : null,
    lastPositionMs: json['lastPositionMs'] as int?,
    lastPlayedAt: json['lastPlayedAt'] != null
        ? DateTime.parse(json['lastPlayedAt'] as String)
        : null,
    playCount: (json['playCount'] as int?) ?? 0,
    isFavorite: (json['isFavorite'] as bool?) ?? false,
  );
}

class VideoFolder {
  final String name;
  final String path;
  final List<VideoItem> videos;
  final int videoCount;

  VideoFolder({required this.name, required this.path, required this.videos})
    : videoCount = videos.length;
}
