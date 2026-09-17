import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:neuro_toolkit/features/neurocnl/models/canonical_editor_document.dart';
import 'package:neuro_toolkit/features/neurocnl/models/network_graph.dart';

import 'package:neuro_toolkit/features/neurocnl/models/simulation_result.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/pipeline_provider.dart';

part 'workspace_file.freezed.dart';
part 'workspace_file.g.dart';

// ---------------------------------------------------------------------------
// JsonKey helper functions for complex types that have manual fromJson/toJson
// but are not annotated with @JsonSerializable.
// ---------------------------------------------------------------------------

// PipelineState handles its own Freezed serialization.

CanonicalEditorDocument? _canonicalDocFromJson(Map<String, dynamic>? json) {
  if (json == null) return null;
  try {
    return CanonicalEditorDocument.fromJson(json);
  } catch (_) {
    return null;
  }
}

Map<String, dynamic>? _canonicalDocToJson(CanonicalEditorDocument? doc) =>
    doc?.toJson();

GenerateResult _generateResultFromJson(Map<String, dynamic> json) =>
    GenerateResult.fromJson(json);
Map<String, dynamic> _generateResultToJson(GenerateResult r) => r.toJson();

WorkspacePipelineCache? _pipelineCacheFromJson(Map<String, dynamic>? json) {
  if (json == null) return null;
  try {
    return WorkspacePipelineCache.fromJson(json);
  } catch (_) {
    return null;
  }
}

Map<String, dynamic>? _pipelineCacheToJson(WorkspacePipelineCache? cache) =>
    cache?.toJson();

WorkspaceNirArtifactCache? _nirArtifactCacheFromJson(
  Map<String, dynamic>? json,
) {
  if (json == null) return null;
  try {
    return WorkspaceNirArtifactCache.fromJson(json);
  } catch (_) {
    return null;
  }
}

Map<String, dynamic>? _nirArtifactCacheToJson(
  WorkspaceNirArtifactCache? cache,
) => cache?.toJson();

PipelineState? _pipelineStateFromJson(Map<String, dynamic>? json) {
  if (json == null) return null;
  try {
    return PipelineState.fromJson(json);
  } catch (_) {
    return null;
  }
}

Map<String, dynamic>? _pipelineStateToJson(PipelineState? state) =>
    state?.toJson();

SimulationResult? _simulationResultFromJson(Map<String, dynamic>? json) {
  if (json == null) return null;
  try {
    return SimulationResult.fromJson(json);
  } catch (_) {
    return null;
  }
}

Map<String, dynamic>? _simulationResultToJson(SimulationResult? r) =>
    r?.toJson();

// ---------------------------------------------------------------------------
// Freezed domain models
// ---------------------------------------------------------------------------

@freezed
abstract class WorkspacePipelineCache with _$WorkspacePipelineCache {
  const WorkspacePipelineCache._();
  const factory WorkspacePipelineCache({
    required String sourceHash,
    required String generatedAt,
    @JsonKey(fromJson: _generateResultFromJson, toJson: _generateResultToJson)
    required GenerateResult generateResult,
    String? simulatedAt,
    @JsonKey(
      fromJson: _simulationResultFromJson,
      toJson: _simulationResultToJson,
    )
    SimulationResult? simulationResult,
  }) = _WorkspacePipelineCache;

  factory WorkspacePipelineCache.fromJson(Map<String, dynamic> json) =>
      _$WorkspacePipelineCacheFromJson(json);

  static String sourceHashFor(String content) {
    return sha256.convert(utf8.encode(content)).toString();
  }

  bool isValidForContent(String content) {
    return sourceHash == sourceHashFor(content);
  }
}

@freezed
abstract class WorkspaceNirArtifactCache with _$WorkspaceNirArtifactCache {
  const WorkspaceNirArtifactCache._();
  const factory WorkspaceNirArtifactCache({
    required String sourceHash,
    required String savedAt,
    @Default('network.nir') String filename,
    @Default('application/octet-stream') String mimeType,
    required String payloadBase64,
  }) = _WorkspaceNirArtifactCache;

  factory WorkspaceNirArtifactCache.fromJson(Map<String, dynamic> json) =>
      _$WorkspaceNirArtifactCacheFromJson(json);

  factory WorkspaceNirArtifactCache.fromBytes({
    required String content,
    required String filename,
    required String mimeType,
    required Uint8List payload,
    required String savedAt,
  }) {
    return WorkspaceNirArtifactCache(
      sourceHash: WorkspacePipelineCache.sourceHashFor(content),
      savedAt: savedAt,
      filename: filename,
      mimeType: mimeType,
      payloadBase64: base64Encode(payload),
    );
  }

  Uint8List get payloadBytes => base64Decode(payloadBase64);

  bool isValidForContent(String content) {
    return sourceHash == WorkspacePipelineCache.sourceHashFor(content);
  }
}

@freezed
abstract class WorkspaceFile with _$WorkspaceFile {
  const WorkspaceFile._();
  const factory WorkspaceFile({
    @Default('') String id,
    @Default('Untitled') String name,
    String? path,
    @Default(false) bool dirty,
    @Default(true) bool isUntitled,
    @Default(0) int cursorOffset,
    @Default(0) int selectionBase,
    @Default(0) int selectionExtent,
    @Default(0.0) double scrollOffset,
    @JsonKey(fromJson: _pipelineCacheFromJson, toJson: _pipelineCacheToJson)
    WorkspacePipelineCache? pipelineCache,
    @JsonKey(
      fromJson: _nirArtifactCacheFromJson,
      toJson: _nirArtifactCacheToJson,
    )
    WorkspaceNirArtifactCache? nirArtifactCache,
    // Complex types with manual serializers — use @JsonKey to wire up helpers.
    @JsonKey(fromJson: _pipelineStateFromJson, toJson: _pipelineStateToJson)
    PipelineState? pipelineState,
    @JsonKey(fromJson: _canonicalDocFromJson, toJson: _canonicalDocToJson)
    CanonicalEditorDocument? canonicalDocument,
    @Default(0) int revision,
  }) = _WorkspaceFile;

  factory WorkspaceFile.fromJson(Map<String, dynamic> json) =>
      _$WorkspaceFileFromJson(json);
}

@freezed
abstract class ValidationFocus with _$ValidationFocus {
  const factory ValidationFocus({
    @Default('overall') String section,
    String? itemId,
  }) = _ValidationFocus;

  factory ValidationFocus.fromJson(Map<String, dynamic> json) =>
      _$ValidationFocusFromJson(json);
}

@freezed
abstract class WorkspaceState with _$WorkspaceState {
  const WorkspaceState._();
  const factory WorkspaceState({
    @Default([]) List<WorkspaceFile> files,
    @Default('') String activeFileId,
    @Default('Untitled Workspace') String workspaceName,
    String? workspaceSourceKind,
    @Default('validation') String activePanel,
    @Default('selectData') String activePipelineStep,
    String? selectedBenchmarkId,
    String? selectedBenchmarkName,
    String? selectedDataset,
    String? selectedDatasetPath,
    @Default([]) List<String> selectedPlatforms,
    @Default('sc_neurocore_fpga') String selectedDeployTarget,
    @Default({}) Map<String, dynamic> benchmarkResultSummary,
    ValidationFocus? validationFocus,
    @Default(0.5) double splitRatio,
    @Default([]) List<WorkspaceActivity> recentActivities,
    // Absolute path of the last `.nmtk` file this
    // workspace was opened from or saved to, used by autosave to write
    // through to that file. Deliberately excluded from the saved JSON
    // payload itself — it's local-machine state, not portable workspace
    // content, and must not get restored as a stale path when the same
    // workspace is opened on a different machine or from a Hub asset.
    @JsonKey(includeToJson: false, includeFromJson: false)
    String? workspaceFilePath,
  }) = _WorkspaceState;

  WorkspaceFile? get activeFile {
    for (final file in files) {
      if (file.id == activeFileId) {
        return file;
      }
    }
    return files.isEmpty ? null : files.first;
  }

  factory WorkspaceState.fromJson(Map<String, dynamic> json) =>
      _$WorkspaceStateFromJson(json);
}

@freezed
abstract class WorkspaceActivity with _$WorkspaceActivity {
  const factory WorkspaceActivity({
    @Default('') String id,
    @Default('activity') String kind,
    @Default('Workspace activity') String title,
    @Default('') String detail,
    @Default('info') String status,
    @Default('') String timestamp,
    String? panelId,
  }) = _WorkspaceActivity;

  factory WorkspaceActivity.fromJson(Map<String, dynamic> json) =>
      _$WorkspaceActivityFromJson(json);
}

String encodeWorkspacePayload(Map<String, dynamic> value) => jsonEncode(value);
