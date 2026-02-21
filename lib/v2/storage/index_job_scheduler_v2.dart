class IndexJobProgressV2 {
  final String jobId;
  final double progress;
  final bool isRunning;
  final bool isCompleted;
  final String? error;

  const IndexJobProgressV2({
    required this.jobId,
    required this.progress,
    required this.isRunning,
    required this.isCompleted,
    this.error,
  });
}

abstract interface class IndexJobSchedulerV2 {
  Stream<IndexJobProgressV2> states();
  Future<void> scheduleIncremental();
  Future<void> scheduleFullRebuild();
  Future<void> cancel();
}
