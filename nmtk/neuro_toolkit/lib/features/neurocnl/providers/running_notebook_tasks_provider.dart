import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:neuro_toolkit/features/neurocnl/providers/api_provider.dart';

enum RunningNotebookTaskSource { run, notebook }

/// A notebook-related task currently active on the server — either an
/// automated Run (step 5, tracked as a job) or a manually-run JupyterLab
/// kernel session (opened on demand from the Run step's "Open Notebook"
/// action, tracked only by the Jupyter server itself).
class RunningNotebookTask {
  const RunningNotebookTask({
    required this.id,
    required this.source,
    required this.label,
    required this.isExecuting,
  });

  final String id;
  final RunningNotebookTaskSource source;
  final String label;

  /// Whether this task represents code actually executing right now. A
  /// [RunningNotebookTaskSource.run] job is always executing. A
  /// [RunningNotebookTaskSource.notebook] entry merely reflects a live
  /// Jupyter kernel session — opening a notebook auto-attaches a kernel
  /// with no cell run, so this is only true when the kernel's own
  /// `execution_state` reports `busy` (see [isJupyterSessionExecuting]).
  final bool isExecuting;
}

/// Jupyter's session model reports `execution_state` as `starting`, `idle`,
/// `busy`, `restarting`, or `dead`. Only `busy` means notebook code is
/// executing. `starting` is automatic kernel attachment, not a user run.
bool isJupyterSessionExecuting(Map<String, dynamic> session) {
  final state =
      (session['kernel'] as Map<String, dynamic>?)?['execution_state'];
  return state == 'busy';
}

bool hasExecutingJupyterSessionForPath(
  List<Map<String, dynamic>> sessions,
  String notebookPath,
) => sessions.any(
  (session) =>
      session['path'] == notebookPath && isJupyterSessionExecuting(session),
);

/// Polls the server for every running notebook task (both sources) so the UI
/// can show — and stop — tasks started from the Run step or its embedded
/// notebook, regardless of which client/tab/session started them.
final runningNotebookTasksProvider =
    AsyncNotifierProvider<
      RunningNotebookTasksNotifier,
      List<RunningNotebookTask>
    >(RunningNotebookTasksNotifier.new);

class RunningNotebookTasksNotifier
    extends AsyncNotifier<List<RunningNotebookTask>> {
  Timer? _pollTimer;
  bool _pollInFlight = false;

  @override
  Future<List<RunningNotebookTask>> build() async {
    ref.onDispose(() => _pollTimer?.cancel());
    _startPolling();
    return _fetch();
  }

  /// Poll cadence, or null to disable polling entirely.
  ///
  /// Overridable because a `Timer.periodic` is only cancelled in `ref.onDispose`,
  /// and flutter_test runs `_verifyInvariants` — which fails on any pending
  /// timer — *before* teardown disposes the container. A live poller therefore
  /// fails every widget test that mounts this provider, whatever the test is
  /// actually asserting.
  static Duration? _pollInterval = const Duration(seconds: 3);

  @visibleForTesting
  static void debugSetPollInterval(Duration? interval) {
    _pollInterval = interval;
  }

  void _startPolling() {
    _pollTimer?.cancel();
    final interval = _pollInterval;
    if (interval == null) return;
    _pollTimer = Timer.periodic(interval, (_) {
      unawaited(_poll());
    });
  }

  Future<void> _poll() async {
    if (_pollInFlight) return;
    _pollInFlight = true;
    try {
      final tasks = await _fetch();
      state = AsyncData(tasks);
    } catch (_) {
      // Transient poll failures shouldn't blank out an already-populated
      // list — keep showing the last known-good state.
    } finally {
      _pollInFlight = false;
    }
  }

  Future<List<RunningNotebookTask>> _fetch() async {
    final api = ref.read(apiClientProvider);
    final jobs = await api.getActiveNotebookJobs();
    final sessions = await api.getJupyterSessions();

    return [
      for (final job in jobs)
        RunningNotebookTask(
          id: job['job_id'] as String,
          source: RunningNotebookTaskSource.run,
          label: (job['platform'] as String?)?.isNotEmpty == true
              ? job['platform'] as String
              : (job['notebook_path'] as String? ?? 'Run'),
          isExecuting: true,
        ),
      for (final session in sessions)
        RunningNotebookTask(
          id: session['id'] as String,
          source: RunningNotebookTaskSource.notebook,
          label:
              ((session['notebook'] as Map<String, dynamic>?)?['path']
                  as String?) ??
              (session['path'] as String?) ??
              'Notebook',
          isExecuting: isJupyterSessionExecuting(session),
        ),
    ];
  }

  Future<void> cancel(RunningNotebookTask task) async {
    final api = ref.read(apiClientProvider);
    switch (task.source) {
      case RunningNotebookTaskSource.run:
        await api.cancelNotebookJob(task.id);
      case RunningNotebookTaskSource.notebook:
        await api.stopJupyterSession(task.id);
    }
    await _poll();
  }
}
