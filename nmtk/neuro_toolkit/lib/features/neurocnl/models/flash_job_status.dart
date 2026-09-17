/// Status snapshot for a Neurochip flash job.
///
/// Mirrors the response schema of
/// `GET /api/neurochip/serial/flash/{job_id}`.
class FlashJobStatus {
  final String jobId;

  /// One of: `pending`, `compiling`, `uploading`, `verifying`, `done`,
  /// `failed`.
  final String status;

  /// Progress from 0 to 100.
  final double progressPct;

  /// Human-readable status message from the backend.
  final String message;

  /// Error description when [status] is `failed`; null otherwise.
  final String? error;

  const FlashJobStatus({
    required this.jobId,
    required this.status,
    required this.progressPct,
    required this.message,
    this.error,
  });

  factory FlashJobStatus.fromJson(Map<String, dynamic> json) {
    return FlashJobStatus(
      jobId: json['job_id'] as String? ?? '',
      status: json['status'] as String? ?? 'pending',
      progressPct: (json['progress_pct'] as num?)?.toDouble() ?? 0.0,
      message: json['message'] as String? ?? '',
      error: json['error'] as String?,
    );
  }

  bool get isDone => status == 'done';
  bool get isFailed => status == 'failed';
  bool get isTerminal => isDone || isFailed;
}
