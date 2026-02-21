class PlaybackState {
  final String mediaId;
  final String sourceInput;
  final String title;
  final int positionMs;
  final int durationMs;
  final DateTime updatedAt;
  final int playCount;

  const PlaybackState({
    required this.mediaId,
    required this.sourceInput,
    required this.title,
    required this.positionMs,
    required this.durationMs,
    required this.updatedAt,
    this.playCount = 0,
  });

  Duration get position => Duration(milliseconds: positionMs);
  Duration get duration => Duration(milliseconds: durationMs);

  PlaybackState copyWith({
    String? mediaId,
    String? sourceInput,
    String? title,
    int? positionMs,
    int? durationMs,
    DateTime? updatedAt,
    int? playCount,
  }) {
    return PlaybackState(
      mediaId: mediaId ?? this.mediaId,
      sourceInput: sourceInput ?? this.sourceInput,
      title: title ?? this.title,
      positionMs: positionMs ?? this.positionMs,
      durationMs: durationMs ?? this.durationMs,
      updatedAt: updatedAt ?? this.updatedAt,
      playCount: playCount ?? this.playCount,
    );
  }

  Map<String, dynamic> toJson() => {
    'mediaId': mediaId,
    'sourceInput': sourceInput,
    'title': title,
    'positionMs': positionMs,
    'durationMs': durationMs,
    'updatedAt': updatedAt.toIso8601String(),
    'playCount': playCount,
  };

  factory PlaybackState.fromJson(Map<String, dynamic> json) => PlaybackState(
    mediaId: json['mediaId'] as String,
    sourceInput: (json['sourceInput'] ?? json['mediaId']) as String,
    title: (json['title'] ?? 'Unknown') as String,
    positionMs: (json['positionMs'] as num?)?.toInt() ?? 0,
    durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
    updatedAt:
        DateTime.tryParse((json['updatedAt'] ?? '') as String) ??
        DateTime.fromMillisecondsSinceEpoch(0),
    playCount: (json['playCount'] as num?)?.toInt() ?? 0,
  );
}
