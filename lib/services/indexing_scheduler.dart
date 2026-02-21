import 'dart:async';

import 'package:empty_player/models/index_job_state.dart';

abstract interface class IndexingScheduler {
  Stream<IndexJobState> get state;

  Future<void> scheduleIncremental();
  Future<void> scheduleFull();
  Future<void> cancel();
}

typedef IndexingTask = Future<void> Function();

class InProcessIndexingScheduler implements IndexingScheduler {
  final StreamController<IndexJobState> _controller =
      StreamController<IndexJobState>.broadcast();
  final IndexingTask runIncremental;
  final IndexingTask runFull;

  bool _isRunning = false;
  bool _cancelRequested = false;

  InProcessIndexingScheduler({
    required this.runIncremental,
    required this.runFull,
  }) {
    _controller.add(IndexJobState.idle);
  }

  @override
  Stream<IndexJobState> get state => _controller.stream;

  @override
  Future<void> scheduleIncremental() => _runJob(runIncremental);

  @override
  Future<void> scheduleFull() => _runJob(runFull);

  @override
  Future<void> cancel() async {
    _cancelRequested = true;
    if (!_isRunning) {
      _controller.add(
        const IndexJobState(status: IndexJobStatus.canceled, progress: 0),
      );
    }
  }

  Future<void> _runJob(IndexingTask task) async {
    if (_isRunning) return;
    _isRunning = true;
    _cancelRequested = false;
    _controller.add(const IndexJobState(status: IndexJobStatus.running));
    try {
      await task();
      if (_cancelRequested) {
        _controller.add(
          IndexJobState(
            status: IndexJobStatus.canceled,
            progress: 0,
            lastRunAt: DateTime.now(),
          ),
        );
      } else {
        _controller.add(
          IndexJobState(
            status: IndexJobStatus.completed,
            progress: 1,
            lastRunAt: DateTime.now(),
          ),
        );
      }
    } catch (error) {
      _controller.add(
        IndexJobState(
          status: IndexJobStatus.failed,
          progress: 0,
          lastRunAt: DateTime.now(),
          error: error.toString(),
        ),
      );
    } finally {
      _isRunning = false;
    }
  }

  void dispose() {
    unawaited(_controller.close());
  }
}
