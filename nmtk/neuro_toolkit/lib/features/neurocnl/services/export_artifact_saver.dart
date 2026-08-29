import 'package:flutter/foundation.dart';

import 'package:neuro_toolkit/features/neurocnl/services/file_adapter.dart';
import 'package:neuro_toolkit/features/neurocnl/services/platform_download_result.dart';
import 'package:neuro_toolkit/features/neurocnl/services/platform_helper.dart' as platform;
import 'package:neuro_toolkit/features/neurocnl/services/export_artifact.dart';

Future<DownloadResult> saveExportArtifact(
  FileAdapter fileAdapter,
  ExportArtifact artifact,
) async {
  if (!kIsWeb) {
    final saveResult = artifact.isBinary
        ? await fileAdapter.saveBinaryFile(
            suggestedName: artifact.filename,
            bytes: artifact.bytes!,
          )
        : await fileAdapter.saveTextFile(
            suggestedName: artifact.filename,
            contents: artifact.textContent!,
          );
    return _mapSaveResult(saveResult);
  }

  if (artifact.isBinary) {
    return platform.downloadBytes(
      artifact.filename,
      artifact.bytes!,
      artifact.mimeType,
    );
  }

  return platform.downloadFile(
    artifact.filename,
    artifact.textContent!,
    artifact.mimeType,
  );
}

DownloadResult _mapSaveResult(SaveResult result) {
  return switch (result.outcome) {
    SaveOutcome.saved => DownloadResult(
      status: DownloadStatus.downloaded,
      path: result.path,
    ),
    SaveOutcome.cancelled => const DownloadResult(
      status: DownloadStatus.failed,
      message: 'Save cancelled.',
    ),
    SaveOutcome.failed => DownloadResult(
      status: DownloadStatus.failed,
      message: result.message ?? 'File save failed.',
    ),
  };
}
