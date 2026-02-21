class PlaybackSessionSnapshotV2 {
  final String sessionId;
  final String mediaId;
  final String title;
  final int positionMs;
  final int durationMs;
  final bool isPlaying;
  final bool isMinimized;

  const PlaybackSessionSnapshotV2({
    required this.sessionId,
    required this.mediaId,
    required this.title,
    required this.positionMs,
    required this.durationMs,
    required this.isPlaying,
    required this.isMinimized,
  });
}

abstract interface class PlaybackSessionServiceV2 {
  Stream<PlaybackSessionSnapshotV2?> session();
  Future<void> setSession(PlaybackSessionSnapshotV2 snapshot);
  Future<void> clearSession();
}
