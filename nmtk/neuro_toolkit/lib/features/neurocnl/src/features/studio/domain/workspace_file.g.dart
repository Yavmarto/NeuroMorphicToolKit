// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'workspace_file.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_WorkspacePipelineCache _$WorkspacePipelineCacheFromJson(
  Map<String, dynamic> json,
) => _WorkspacePipelineCache(
  sourceHash: json['sourceHash'] as String,
  generatedAt: json['generatedAt'] as String,
  generateResult: _generateResultFromJson(
    json['generateResult'] as Map<String, dynamic>,
  ),
  simulatedAt: json['simulatedAt'] as String?,
  simulationResult: _simulationResultFromJson(
    json['simulationResult'] as Map<String, dynamic>?,
  ),
);

Map<String, dynamic> _$WorkspacePipelineCacheToJson(
  _WorkspacePipelineCache instance,
) => <String, dynamic>{
  'sourceHash': instance.sourceHash,
  'generatedAt': instance.generatedAt,
  'generateResult': _generateResultToJson(instance.generateResult),
  'simulatedAt': instance.simulatedAt,
  'simulationResult': _simulationResultToJson(instance.simulationResult),
};

_WorkspaceNirArtifactCache _$WorkspaceNirArtifactCacheFromJson(
  Map<String, dynamic> json,
) => _WorkspaceNirArtifactCache(
  sourceHash: json['sourceHash'] as String,
  savedAt: json['savedAt'] as String,
  filename: json['filename'] as String? ?? 'network.nir',
  mimeType: json['mimeType'] as String? ?? 'application/octet-stream',
  payloadBase64: json['payloadBase64'] as String,
);

Map<String, dynamic> _$WorkspaceNirArtifactCacheToJson(
  _WorkspaceNirArtifactCache instance,
) => <String, dynamic>{
  'sourceHash': instance.sourceHash,
  'savedAt': instance.savedAt,
  'filename': instance.filename,
  'mimeType': instance.mimeType,
  'payloadBase64': instance.payloadBase64,
};

_WorkspaceFile _$WorkspaceFileFromJson(Map<String, dynamic> json) =>
    _WorkspaceFile(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Untitled',
      path: json['path'] as String?,
      dirty: json['dirty'] as bool? ?? false,
      isUntitled: json['isUntitled'] as bool? ?? true,
      cursorOffset: (json['cursorOffset'] as num?)?.toInt() ?? 0,
      selectionBase: (json['selectionBase'] as num?)?.toInt() ?? 0,
      selectionExtent: (json['selectionExtent'] as num?)?.toInt() ?? 0,
      scrollOffset: (json['scrollOffset'] as num?)?.toDouble() ?? 0.0,
      pipelineCache: _pipelineCacheFromJson(
        json['pipelineCache'] as Map<String, dynamic>?,
      ),
      nirArtifactCache: _nirArtifactCacheFromJson(
        json['nirArtifactCache'] as Map<String, dynamic>?,
      ),
      pipelineState: _pipelineStateFromJson(
        json['pipelineState'] as Map<String, dynamic>?,
      ),
      canonicalDocument: _canonicalDocFromJson(
        json['canonicalDocument'] as Map<String, dynamic>?,
      ),
      revision: (json['revision'] as num?)?.toInt() ?? 0,
    );

Map<String, dynamic> _$WorkspaceFileToJson(_WorkspaceFile instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'path': instance.path,
      'dirty': instance.dirty,
      'isUntitled': instance.isUntitled,
      'cursorOffset': instance.cursorOffset,
      'selectionBase': instance.selectionBase,
      'selectionExtent': instance.selectionExtent,
      'scrollOffset': instance.scrollOffset,
      'pipelineCache': _pipelineCacheToJson(instance.pipelineCache),
      'nirArtifactCache': _nirArtifactCacheToJson(instance.nirArtifactCache),
      'pipelineState': _pipelineStateToJson(instance.pipelineState),
      'canonicalDocument': _canonicalDocToJson(instance.canonicalDocument),
      'revision': instance.revision,
    };

_ValidationFocus _$ValidationFocusFromJson(Map<String, dynamic> json) =>
    _ValidationFocus(
      section: json['section'] as String? ?? 'overall',
      itemId: json['itemId'] as String?,
    );

Map<String, dynamic> _$ValidationFocusToJson(_ValidationFocus instance) =>
    <String, dynamic>{'section': instance.section, 'itemId': instance.itemId};

_WorkspaceState _$WorkspaceStateFromJson(Map<String, dynamic> json) =>
    _WorkspaceState(
      files:
          (json['files'] as List<dynamic>?)
              ?.map((e) => WorkspaceFile.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      activeFileId: json['activeFileId'] as String? ?? '',
      workspaceName: json['workspaceName'] as String? ?? 'Untitled Workspace',
      workspaceSourceKind: json['workspaceSourceKind'] as String?,
      activePanel: json['activePanel'] as String? ?? 'validation',
      activePipelineStep: json['activePipelineStep'] as String? ?? 'selectData',
      selectedBenchmarkId: json['selectedBenchmarkId'] as String?,
      selectedBenchmarkName: json['selectedBenchmarkName'] as String?,
      selectedDataset: json['selectedDataset'] as String?,
      selectedDatasetPath: json['selectedDatasetPath'] as String?,
      selectedPlatforms:
          (json['selectedPlatforms'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      selectedDeployTarget:
          json['selectedDeployTarget'] as String? ?? 'sc_neurocore_fpga',
      benchmarkResultSummary:
          json['benchmarkResultSummary'] as Map<String, dynamic>? ?? const {},
      validationFocus: json['validationFocus'] == null
          ? null
          : ValidationFocus.fromJson(
              json['validationFocus'] as Map<String, dynamic>,
            ),
      splitRatio: (json['splitRatio'] as num?)?.toDouble() ?? 0.5,
      recentActivities:
          (json['recentActivities'] as List<dynamic>?)
              ?.map(
                (e) => WorkspaceActivity.fromJson(e as Map<String, dynamic>),
              )
              .toList() ??
          const [],
    );

Map<String, dynamic> _$WorkspaceStateToJson(_WorkspaceState instance) =>
    <String, dynamic>{
      'files': instance.files,
      'activeFileId': instance.activeFileId,
      'workspaceName': instance.workspaceName,
      'workspaceSourceKind': instance.workspaceSourceKind,
      'activePanel': instance.activePanel,
      'activePipelineStep': instance.activePipelineStep,
      'selectedBenchmarkId': instance.selectedBenchmarkId,
      'selectedBenchmarkName': instance.selectedBenchmarkName,
      'selectedDataset': instance.selectedDataset,
      'selectedDatasetPath': instance.selectedDatasetPath,
      'selectedPlatforms': instance.selectedPlatforms,
      'selectedDeployTarget': instance.selectedDeployTarget,
      'benchmarkResultSummary': instance.benchmarkResultSummary,
      'validationFocus': instance.validationFocus,
      'splitRatio': instance.splitRatio,
      'recentActivities': instance.recentActivities,
    };

_WorkspaceActivity _$WorkspaceActivityFromJson(Map<String, dynamic> json) =>
    _WorkspaceActivity(
      id: json['id'] as String? ?? '',
      kind: json['kind'] as String? ?? 'activity',
      title: json['title'] as String? ?? 'Workspace activity',
      detail: json['detail'] as String? ?? '',
      status: json['status'] as String? ?? 'info',
      timestamp: json['timestamp'] as String? ?? '',
      panelId: json['panelId'] as String?,
    );

Map<String, dynamic> _$WorkspaceActivityToJson(_WorkspaceActivity instance) =>
    <String, dynamic>{
      'id': instance.id,
      'kind': instance.kind,
      'title': instance.title,
      'detail': instance.detail,
      'status': instance.status,
      'timestamp': instance.timestamp,
      'panelId': instance.panelId,
    };
