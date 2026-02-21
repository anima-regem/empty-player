enum IndexJobStatus { idle, running, completed, failed, canceled }

class IndexJobState {
  final IndexJobStatus status;
  final double progress;
  final DateTime? lastRunAt;
  final String? error;

  const IndexJobState({
    required this.status,
    this.progress = 0,
    this.lastRunAt,
    this.error,
  });

  static const idle = IndexJobState(status: IndexJobStatus.idle);

  IndexJobState copyWith({
    IndexJobStatus? status,
    double? progress,
    DateTime? lastRunAt,
    String? error,
  }) {
    return IndexJobState(
      status: status ?? this.status,
      progress: progress ?? this.progress,
      lastRunAt: lastRunAt ?? this.lastRunAt,
      error: error,
    );
  }
}
