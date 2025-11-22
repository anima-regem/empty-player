class VideoItem {
  final String name;
  final String path;
  final String? thumbnail;
  final Duration? duration;
  final int? size;
  final DateTime? dateModified;

  VideoItem({
    required this.name,
    required this.path,
    this.thumbnail,
    this.duration,
    this.size,
    this.dateModified,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'path': path,
    'thumbnail': thumbnail,
    'duration': duration?.inSeconds,
    'size': size,
    'dateModified': dateModified?.toIso8601String(),
  };

  factory VideoItem.fromJson(Map<String, dynamic> json) => VideoItem(
    name: json['name'] as String,
    path: json['path'] as String,
    thumbnail: json['thumbnail'] as String?,
    duration: json['duration'] != null
        ? Duration(seconds: json['duration'] as int)
        : null,
    size: json['size'] as int?,
    dateModified: json['dateModified'] != null
        ? DateTime.parse(json['dateModified'] as String)
        : null,
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
