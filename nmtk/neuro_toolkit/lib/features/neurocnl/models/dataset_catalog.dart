// Catalog entry and download result from GET/POST /api/datasets.

class DatasetFolder {
  const DatasetFolder({
    required this.folderName,
    required this.folderPath,
    required this.description,
    required this.files,
  });

  final String folderName;
  final String folderPath;
  final String description;
  final List<DatasetEntry> files;

  factory DatasetFolder.fromJson(Map<String, dynamic> json) {
    final rawFiles = json['files'] as List<dynamic>? ?? const <dynamic>[];
    return DatasetFolder(
      folderName: json['folder_name'] as String? ?? '',
      folderPath: json['folder_path'] as String? ?? '',
      description: json['description'] as String? ?? '',
      files: rawFiles
          .whereType<Map<String, dynamic>>()
          .map(DatasetEntry.fromJson)
          .toList(growable: false),
    );
  }

  bool get hasReadyFiles => files.any((f) => f.isReady);
}

class DatasetCatalogList {
  const DatasetCatalogList({
    required this.firebaseAvailable,
    required this.datasets,
    this.folders = const [],
  });

  final bool firebaseAvailable;
  final List<DatasetEntry> datasets;
  final List<DatasetFolder> folders;

  factory DatasetCatalogList.fromJson(Map<String, dynamic> json) {
    final raw = json['datasets'] as List<dynamic>? ?? const <dynamic>[];
    final rawFolders = json['folders'] as List<dynamic>? ?? const <dynamic>[];
    return DatasetCatalogList(
      firebaseAvailable: json['firebase_available'] as bool? ?? false,
      datasets: raw
          .whereType<Map<String, dynamic>>()
          .map(DatasetEntry.fromJson)
          .toList(growable: false),
      folders: rawFolders
          .whereType<Map<String, dynamic>>()
          .map(DatasetFolder.fromJson)
          .toList(growable: false),
    );
  }

  DatasetEntry? findEntryById(String? id) {
    if (id == null || id.isEmpty) {
      return null;
    }
    for (final folder in folders) {
      for (final entry in folder.files) {
        if (entry.id == id) {
          return entry;
        }
      }
    }
    for (final entry in datasets) {
      if (entry.id == id) {
        return entry;
      }
    }
    return null;
  }
}

enum DatasetServerStatus {
  notDownloaded,
  downloading,
  ready,
  error;

  static DatasetServerStatus fromApi(String value) => switch (value) {
    'ready' => DatasetServerStatus.ready,
    'downloading' => DatasetServerStatus.downloading,
    'error' => DatasetServerStatus.error,
    _ => DatasetServerStatus.notDownloaded,
  };
}

class DatasetEntry {
  const DatasetEntry({
    required this.id,
    required this.label,
    required this.description,
    required this.storagePath,
    required this.status,
    this.folderPath,
    this.sourceFilename,
    this.sizeBytes,
    this.contentSha256,
    this.localPath,
    this.downloadedAt,
    this.errorMessage,
    this.downloadProgress,
    this.source,
    this.format,
  });

  final String id;
  final String label;
  final String description;
  final String storagePath;
  final String? folderPath;
  final String? sourceFilename;
  final int? sizeBytes;
  final String? contentSha256;
  final DatasetServerStatus status;
  final String? localPath;
  final String? downloadedAt;
  final String? errorMessage;
  final double? downloadProgress;
  final String? source;
  final String? format;

  bool get isReady => status == DatasetServerStatus.ready;
  bool get isLocalImport => source == 'local';
  bool get isDownloading => status == DatasetServerStatus.downloading;

  factory DatasetEntry.fromJson(Map<String, dynamic> json) => DatasetEntry(
    id: json['id'] as String,
    label: json['label'] as String,
    description: json['description'] as String,
    storagePath: json['storage_path'] as String,
    folderPath: json['folder_path'] as String?,
    sourceFilename: json['source_filename'] as String?,
    sizeBytes: json['size_bytes'] as int?,
    contentSha256: json['content_sha256'] as String?,
    status: DatasetServerStatus.fromApi(json['status'] as String? ?? ''),
    localPath: json['local_path'] as String?,
    downloadedAt: json['downloaded_at'] as String?,
    errorMessage: json['error_message'] as String?,
    downloadProgress: _parseDoubleOrNull(json['download_progress']),
    source: json['source'] as String?,
    format: json['format'] as String?,
  );

  static double? _parseDoubleOrNull(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) {
      final parsed = double.tryParse(value);
      if (parsed != null) return parsed;
    }
    return null;
  }

  DatasetEntry copyWith({
    DatasetServerStatus? status,
    String? localPath,
    String? downloadedAt,
    String? errorMessage,
    double? downloadProgress,
    String? source,
    String? format,
  }) => DatasetEntry(
    id: id,
    label: label,
    description: description,
    storagePath: storagePath,
    folderPath: folderPath,
    sourceFilename: sourceFilename,
    sizeBytes: sizeBytes,
    contentSha256: contentSha256,
    status: status ?? this.status,
    localPath: localPath ?? this.localPath,
    downloadedAt: downloadedAt ?? this.downloadedAt,
    errorMessage: errorMessage ?? this.errorMessage,
    downloadProgress: downloadProgress ?? this.downloadProgress,
    source: source ?? this.source,
    format: format ?? this.format,
  );
}

class DatasetDownloadResult {
  const DatasetDownloadResult({
    required this.datasetId,
    required this.localPath,
    required this.downloadedAt,
    required this.sha256Verified,
    this.sizeBytes,
  });

  final String datasetId;
  final String localPath;
  final String downloadedAt;
  final bool sha256Verified;
  final int? sizeBytes;

  factory DatasetDownloadResult.fromJson(Map<String, dynamic> json) =>
      DatasetDownloadResult(
        datasetId: json['dataset_id'] as String,
        localPath: json['local_path'] as String,
        downloadedAt: json['downloaded_at'] as String,
        sha256Verified: json['sha256_verified'] as bool? ?? false,
        sizeBytes: json['size_bytes'] as int?,
      );
}
