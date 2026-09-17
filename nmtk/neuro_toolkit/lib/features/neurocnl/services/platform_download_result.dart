enum DownloadStatus { downloaded, fallback, failed }

class DownloadResult {
  const DownloadResult({required this.status, this.path, this.message});

  final DownloadStatus status;
  final String? path;
  final String? message;

  bool get isDownloaded => status == DownloadStatus.downloaded;
  bool get needsFallback => status == DownloadStatus.fallback;
  bool get isFailure => status == DownloadStatus.failed;
}
