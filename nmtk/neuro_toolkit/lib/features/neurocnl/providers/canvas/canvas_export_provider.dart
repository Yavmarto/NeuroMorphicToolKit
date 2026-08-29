import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:neuro_toolkit/features/neurocnl/models/canvas/validation.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/spec_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/services/export_artifact.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/sync_provider.dart';

class ExportState {
  final bool isLoading;
  final String? error;
  final String? data;
  final String? format;
  final BackendSupport? backendSupport;
  final GeneratorFidelitySummary? generatorFidelity;
  final bool requiresApproximateConfirmation;
  final ExportArtifact? artifact;

  ExportState({
    this.isLoading = false,
    this.error,
    this.data,
    this.format,
    this.backendSupport,
    this.generatorFidelity,
    this.requiresApproximateConfirmation = false,
    this.artifact,
  });

  ExportState copyWith({
    bool? isLoading,
    String? error,
    String? data,
    String? format,
    BackendSupport? backendSupport,
    bool clearBackendSupport = false,
    GeneratorFidelitySummary? generatorFidelity,
    bool clearGeneratorFidelity = false,
    bool? requiresApproximateConfirmation,
    ExportArtifact? artifact,
    bool clearArtifact = false,
  }) {
    return ExportState(
      isLoading: isLoading ?? this.isLoading,
      error: error,
      data: data ?? this.data,
      format: format ?? this.format,
      backendSupport: clearBackendSupport
          ? null
          : (backendSupport ?? this.backendSupport),
      generatorFidelity: clearGeneratorFidelity
          ? null
          : (generatorFidelity ?? this.generatorFidelity),
      requiresApproximateConfirmation:
          requiresApproximateConfirmation ??
          this.requiresApproximateConfirmation,
      artifact: clearArtifact ? null : (artifact ?? this.artifact),
    );
  }
}

class ExportNotifier extends Notifier<ExportState> {
  @override
  ExportState build() => ExportState();

  Future<void> preflight(String format, Map<String, dynamic> graphJson) async {
    if (format == 'cnl') {
      state = state.copyWith(
        isLoading: false,
        error: null,
        format: format,
        backendSupport: BackendSupport(backend: 'cnl', verdict: 'supported'),
        requiresApproximateConfirmation: false,
        clearArtifact: true,
      );
      return;
    }
    final apiClient = ref.read(apiClientProvider);
    state = state.copyWith(isLoading: true, error: null);
    try {
      final response = await apiClient.preflightExport(format, graphJson);
      state = state.copyWith(
        isLoading: false,
        data: null,
        error: null,
        format: format,
        backendSupport: response['backend_support'] == null
            ? null
            : BackendSupport.fromJson(
                response['backend_support'] as Map<String, dynamic>,
              ),
        generatorFidelity: response['generator_fidelity'] == null
            ? null
            : GeneratorFidelitySummary.fromJson(
                response['generator_fidelity'] as Map<String, dynamic>,
              ),
        requiresApproximateConfirmation: false,
        clearArtifact: true,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> export(
    String format,
    Map<String, dynamic> graphJson, {
    bool allowApproximate = false,
  }) async {
    if (format == 'cnl') {
      final currentCnl = ref.read(specTextProvider);
      state = state.copyWith(
        isLoading: false,
        error: null,
        data: currentCnl,
        format: format,
      );
      return;
    }
    final apiClient = ref.read(apiClientProvider);
    final backendSupport = state.backendSupport;
    if (backendSupport?.verdict == 'unsupported') {
      state = state.copyWith(
        error: backendSupport != null && backendSupport.warnings.isNotEmpty
            ? backendSupport.warnings.first
            : 'This export target is unsupported for the current design.',
      );
      return;
    }

    if (backendSupport?.verdict == 'approximate' && !allowApproximate) {
      state = state.copyWith(
        requiresApproximateConfirmation: true,
        error: null,
      );
      return;
    }

    state = state.copyWith(
      isLoading: true,
      error: null,
      requiresApproximateConfirmation: false,
    );
    try {
      final response = await apiClient.exportGraph(
        format,
        graphJson,
        allowApproximate: allowApproximate,
      );
      final content = response['content'] as String?;
      final artifact = format == 'nir' && content != null
          ? ExportArtifact.binary(
              filename: 'network.nir',
              mimeType: 'application/octet-stream',
              payload: base64Decode(content),
            )
          : null;
      state = state.copyWith(
        isLoading: false,
        data: format == 'nir' ? null : content,
        format: format,
        backendSupport: response['backend_support'] == null
            ? backendSupport
            : BackendSupport.fromJson(
                response['backend_support'] as Map<String, dynamic>,
              ),
        generatorFidelity: response['generator_fidelity'] == null
            ? state.generatorFidelity
            : GeneratorFidelitySummary.fromJson(
                response['generator_fidelity'] as Map<String, dynamic>,
              ),
        artifact: artifact,
        clearArtifact: artifact == null,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  void reset() {
    state = ExportState();
  }
}

final exportProvider = NotifierProvider<ExportNotifier, ExportState>(
  () => ExportNotifier(),
);
