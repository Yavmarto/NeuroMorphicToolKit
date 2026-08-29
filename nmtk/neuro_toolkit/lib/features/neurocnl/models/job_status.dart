import 'dart:convert';

/// Status of an asynchronous backend job.
class JobStatus<T> {
  final String jobId;
  final String status;
  final T? result;
  final String? error;

  const JobStatus({
    required this.jobId,
    required this.status,
    this.result,
    this.error,
  });

  factory JobStatus.fromJson(
    Map<String, dynamic> json,
    T? Function(Map<String, dynamic>)? fromJsonT,
  ) {
    final rawResult = json['result'];
    final rawError = json['error'];
    T? result;
    String? error;
    if (rawResult != null &&
        fromJsonT != null &&
        rawResult is Map<String, dynamic>) {
      result = fromJsonT(rawResult);
    } else if (rawResult is T) {
      result = rawResult;
    }
    if (rawError is String) {
      error = rawError;
    } else if (rawError != null) {
      error = jsonEncode(rawError);
    }

    return JobStatus<T>(
      jobId: json['job_id'] as String,
      status: json['status'] as String,
      result: result,
      error: error,
    );
  }
}
