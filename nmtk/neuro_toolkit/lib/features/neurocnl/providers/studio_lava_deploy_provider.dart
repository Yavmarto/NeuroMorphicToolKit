import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:neuro_toolkit/features/neurocnl/providers/api_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/services/studio_lava_deploy_service.dart';

part 'studio_lava_deploy_provider.g.dart';

enum StudioLavaDeployPhase {
  idle,
  validating,
  compiling,
  running,
  completed,
  failed,
}

/// Immutable state for [StudioLavaDeployController].
class StudioLavaDeployState {
  const StudioLavaDeployState({
    this.phase = StudioLavaDeployPhase.idle,
    this.exportResult,
    this.runResult,
    this.bitWidth = 8,
    this.runSteps = 8,
    this.runConfig = 'sim',
    this.sessionId,
    this.activityMessage,
    this.errorMessage,
  });

  final StudioLavaDeployPhase phase;
  final Map<String, dynamic>? exportResult;
  final Map<String, dynamic>? runResult;
  final int bitWidth;
  final int runSteps;
  final String runConfig;
  final String? sessionId;
  final String? activityMessage;
  final String? errorMessage;

  bool get isBusy =>
      phase == StudioLavaDeployPhase.validating ||
      phase == StudioLavaDeployPhase.compiling ||
      phase == StudioLavaDeployPhase.running;

  StudioLavaDeployState copyWith({
    StudioLavaDeployPhase? phase,
    Map<String, dynamic>? exportResult,
    bool clearExportResult = false,
    Map<String, dynamic>? runResult,
    bool clearRunResult = false,
    int? bitWidth,
    int? runSteps,
    String? runConfig,
    String? sessionId,
    bool clearSessionId = false,
    String? activityMessage,
    bool clearActivityMessage = false,
    String? errorMessage,
    bool clearErrorMessage = false,
  }) {
    return StudioLavaDeployState(
      phase: phase ?? this.phase,
      exportResult: clearExportResult
          ? null
          : (exportResult ?? this.exportResult),
      runResult: clearRunResult ? null : (runResult ?? this.runResult),
      bitWidth: bitWidth ?? this.bitWidth,
      runSteps: runSteps ?? this.runSteps,
      runConfig: runConfig ?? this.runConfig,
      sessionId: clearSessionId ? null : (sessionId ?? this.sessionId),
      activityMessage: clearActivityMessage
          ? null
          : (activityMessage ?? this.activityMessage),
      errorMessage: clearErrorMessage
          ? null
          : (errorMessage ?? this.errorMessage),
    );
  }
}

@riverpod
class StudioLavaDeployController extends _$StudioLavaDeployController {
  StudioLavaDeployService get _service =>
      ref.read(studioLavaDeployServiceProvider);

  @override
  StudioLavaDeployState build() => const StudioLavaDeployState();

  void _fail(Object error) {
    if (!ref.mounted) return;
    state = state.copyWith(
      phase: StudioLavaDeployPhase.failed,
      errorMessage: error.toString(),
    );
  }

  void setBitWidth(int bitWidth) {
    state = state.copyWith(
      bitWidth: bitWidth,
      clearExportResult: true,
      clearRunResult: true,
      clearSessionId: true,
    );
  }

  void setRunSteps(int value) {
    state = state.copyWith(runSteps: value < 1 ? 1 : value);
  }

  void setRunConfig(String value) {
    state = state.copyWith(
      runConfig: value == 'hw' ? 'hw' : 'sim',
      clearSessionId: true,
      clearRunResult: true,
    );
  }

  Future<void> validate(String spec) async {
    state = state.copyWith(
      phase: StudioLavaDeployPhase.validating,
      activityMessage: 'Checking Lava simulator exportability.',
      clearErrorMessage: true,
    );
    try {
      final result = await _service.validate(
        spec: spec,
        bitWidth: state.bitWidth,
      );
      if (!ref.mounted) return;
      state = state.copyWith(
        exportResult: result,
        phase: StudioLavaDeployPhase.idle,
        activityMessage: _supportLabel(result['support_state'] as String?),
      );
    } catch (error) {
      _fail(error);
    }
  }

  Future<void> compile(String spec) async {
    if (state.exportResult == null) {
      await validate(spec);
      if (!ref.mounted) return;
    }

    final resolvedExportResult = state.exportResult;
    final deployPayload = resolvedExportResult?['deploy_payload'];
    if (resolvedExportResult == null ||
        deployPayload is! Map<String, dynamic>) {
      return;
    }

    state = state.copyWith(
      phase: StudioLavaDeployPhase.compiling,
      activityMessage: state.runConfig == 'hw'
          ? 'Checking Lava hardware preflight.'
          : 'Compiling Lava simulator session.',
      clearErrorMessage: true,
    );
    try {
      final sessionId = await _service.compile(
        deployPayload: deployPayload,
        runConfig: state.runConfig,
      );
      if (!ref.mounted) return;
      state = state.copyWith(
        sessionId: sessionId,
        phase: StudioLavaDeployPhase.completed,
        activityMessage: state.runConfig == 'hw'
            ? 'Hardware preflight passed.'
            : 'Lava simulator compile completed.',
      );
    } catch (error) {
      _fail(error);
    }
  }

  Future<void> run(String spec) async {
    if (state.sessionId == null) {
      await compile(spec);
      if (!ref.mounted) return;
    }
    if (state.sessionId == null) return;

    state = state.copyWith(
      phase: StudioLavaDeployPhase.running,
      activityMessage: 'Running Lava simulator session.',
      clearErrorMessage: true,
    );
    try {
      final result = await _service.run(
        sessionId: state.sessionId!,
        steps: state.runSteps,
      );
      if (!ref.mounted) return;
      state = state.copyWith(
        runResult: result,
        phase: StudioLavaDeployPhase.completed,
        activityMessage: 'Simulator run completed.',
      );
    } catch (error) {
      _fail(error);
    }
  }

  String _supportLabel(String? supportState) {
    return switch (supportState) {
      'exportable' => 'Exportable for Lava simulator execution.',
      'exportable_with_warnings' =>
        'Exportable for Lava simulator execution with warnings.',
      'unsupported' => 'Unsupported for Lava simulator execution.',
      _ => 'Lava deployability checked.',
    };
  }
}

/// Backward-compat alias.
final studioLavaDeployProvider = studioLavaDeployControllerProvider;
