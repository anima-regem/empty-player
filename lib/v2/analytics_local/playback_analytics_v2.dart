class PlaybackAnalyticsEvent {
  final String mediaId;
  final String eventType;
  final int positionMs;
  final DateTime createdAt;

  const PlaybackAnalyticsEvent({
    required this.mediaId,
    required this.eventType,
    required this.positionMs,
    required this.createdAt,
  });
}

abstract interface class PlaybackAnalyticsLocalV2 {
  Future<void> track(PlaybackAnalyticsEvent event);
}
