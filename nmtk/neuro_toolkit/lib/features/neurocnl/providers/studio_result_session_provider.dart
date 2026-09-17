import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:neuro_toolkit/features/neurocnl/models/studio_result_session.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/training_provider.dart';

enum StudioResultSessionPhase {
  idle,
  running,
  completed,
  partial,
  failed,
  completedWithoutResults,
}

class StudioResultSessionState {
  const StudioResultSessionState({
    this.phase = StudioResultSessionPhase.idle,
    this.attemptId,
    this.provenance,
    this.platforms = const <String, StudioPlatformResult>{},
    this.activeSnapshot,
    this.lastSuccessfulSnapshot,
    this.dismissedErrors = const <String>{},
  });

  final StudioResultSessionPhase phase;
  final String? attemptId;
  final StudioResultProvenance? provenance;
  final Map<String, StudioPlatformResult> platforms;
  final StudioResultSnapshot? activeSnapshot;
  final StudioResultSnapshot? lastSuccessfulSnapshot;
  final Set<String> dismissedErrors;

  bool get isAnyRunning => platforms.values.any(
    (entry) => entry.outcome == StudioPlatformOutcome.running,
  );

  bool get hasErrors => platforms.entries.any(
    (entry) =>
        entry.value.outcome == StudioPlatformOutcome.error &&
        !dismissedErrors.contains(entry.key),
  );

  bool get allSucceeded =>
      platforms.isNotEmpty &&
      platforms.values.every(
        (entry) =>
            entry.outcome == StudioPlatformOutcome.complete ||
            entry.outcome == StudioPlatformOutcome.notApplicable,
      ) &&
      platforms.values.any(
        (entry) => entry.outcome == StudioPlatformOutcome.complete,
      );

  StudioResultSnapshot? get reviewableSnapshot =>
      activeSnapshot ?? lastSuccessfulSnapshot;

  StudioResultSnapshot? get persistableSnapshot =>
      activeSnapshot ?? lastSuccessfulSnapshot;

  StudioResultSessionState copyWith({
    StudioResultSessionPhase? phase,
    String? attemptId,
    StudioResultProvenance? provenance,
    Map<String, StudioPlatformResult>? platforms,
    StudioResultSnapshot? activeSnapshot,
    StudioResultSnapshot? lastSuccessfulSnapshot,
    Set<String>? dismissedErrors,
    bool clearAttemptId = false,
    bool clearProvenance = false,
    bool clearActiveSnapshot = false,
    bool clearLastSuccessfulSnapshot = false,
  }) {
    return StudioResultSessionState(
      phase: phase ?? this.phase,
      attemptId: clearAttemptId ? null : (attemptId ?? this.attemptId),
      provenance: clearProvenance ? null : (provenance ?? this.provenance),
      platforms: platforms ?? this.platforms,
      activeSnapshot: clearActiveSnapshot
          ? null
          : (activeSnapshot ?? this.activeSnapshot),
      lastSuccessfulSnapshot: clearLastSuccessfulSnapshot
          ? null
          : (lastSuccessfulSnapshot ?? this.lastSuccessfulSnapshot),
      dismissedErrors: dismissedErrors ?? this.dismissedErrors,
    );
  }
}

final studioResultSessionProvider =
    NotifierProvider<StudioResultSessionController, StudioResultSessionState>(
      StudioResultSessionController.new,
    );

class StudioResultSessionController extends Notifier<StudioResultSessionState> {
  int _attemptSequence = 0;

  @override
  StudioResultSessionState build() => const StudioResultSessionState();

  bool isCurrentAttempt(String attemptId) => state.attemptId == attemptId;

  void beginAttempt({
    required Iterable<String> platforms,
    required StudioResultProvenance provenance,
  }) {
    final attemptId =
        '${DateTime.now().toUtc().microsecondsSinceEpoch}-${_attemptSequence++}';
    state = StudioResultSessionState(
      phase: StudioResultSessionPhase.running,
      attemptId: attemptId,
      provenance: provenance,
      platforms: <String, StudioPlatformResult>{
        for (final platform in platforms)
          platform: StudioPlatformResult(
            platform: platform,
            outcome: StudioPlatformOutcome.running,
          ),
      },
      lastSuccessfulSnapshot: state.lastSuccessfulSnapshot,
    );
  }

  void registerJob(
    String platform,
    String jobId, {
    String service = 'training',
  }) {
    _updatePlatform(
      platform,
      (current) => current.copyWith(
        completedJob: CompletedJobReference(jobId: jobId, service: service),
      ),
    );
  }

  void recordEpoch(String platform, TrainingEpochEvent event) {
    _updatePlatform(
      platform,
      (current) => current.copyWith(
        history: StudioResultSnapshot.compactHistory(<TrainingEpochEvent>[
          ...current.history,
          event,
        ]),
      ),
    );
  }

  void markComplete(String platform) {
    _markTerminal(platform, StudioPlatformOutcome.complete);
  }

  void markNotApplicable(String platform, String reason) {
    _markTerminal(
      platform,
      StudioPlatformOutcome.notApplicable,
      notApplicableReason: reason,
    );
  }

  void markCancelled(String platform) {
    _markTerminal(platform, StudioPlatformOutcome.cancelled);
  }

  void markError(String platform, {required String summary, String? detail}) {
    _markTerminal(
      platform,
      StudioPlatformOutcome.error,
      summary: summary,
      detail: detail,
    );
  }

  void cancelRunning() {
    var next = state.platforms;
    for (final entry in state.platforms.entries) {
      if (entry.value.outcome != StudioPlatformOutcome.running) continue;
      next = <String, StudioPlatformResult>{
        ...next,
        entry.key: entry.value.copyWith(
          outcome: StudioPlatformOutcome.cancelled,
        ),
      };
    }
    state = state.copyWith(platforms: next);
    _finalizeIfTerminal();
  }

  void dismissErrors() {
    state = state.copyWith(
      dismissedErrors: <String>{
        ...state.dismissedErrors,
        for (final entry in state.platforms.entries)
          if (entry.value.outcome == StudioPlatformOutcome.error) entry.key,
      },
    );
  }

  void restoreSnapshot(StudioResultSnapshot snapshot) {
    state = StudioResultSessionState(
      phase: snapshot.isPartial
          ? StudioResultSessionPhase.partial
          : StudioResultSessionPhase.completed,
      attemptId: snapshot.id,
      provenance: snapshot.provenance,
      platforms: snapshot.platforms,
      activeSnapshot: snapshot,
      lastSuccessfulSnapshot: snapshot.isPartial ? null : snapshot,
    );
  }

  void updateSelection(StudioVisualizationSelection selection) {
    final target = state.reviewableSnapshot;
    var active = state.activeSnapshot;
    var successful = state.lastSuccessfulSnapshot;
    if (active != null && active.id == target?.id) {
      active = active.copyWith(selection: selection);
    }
    if (successful != null && successful.id == target?.id) {
      successful = successful.copyWith(selection: selection);
    }
    state = state.copyWith(
      activeSnapshot: active,
      lastSuccessfulSnapshot: successful,
    );
  }

  void clear() {
    state = const StudioResultSessionState();
  }

  void _markTerminal(
    String platform,
    StudioPlatformOutcome outcome, {
    String? summary,
    String? detail,
    String? notApplicableReason,
  }) {
    _updatePlatform(
      platform,
      (current) => current.copyWith(
        outcome: outcome,
        summary: summary,
        detail: detail,
        notApplicableReason: notApplicableReason,
      ),
    );
    _finalizeIfTerminal();
  }

  void _updatePlatform(
    String platform,
    StudioPlatformResult Function(StudioPlatformResult current) update,
  ) {
    final current =
        state.platforms[platform] ??
        StudioPlatformResult(
          platform: platform,
          outcome: StudioPlatformOutcome.running,
        );
    state = state.copyWith(
      platforms: <String, StudioPlatformResult>{
        ...state.platforms,
        platform: update(current),
      },
    );
  }

  void _finalizeIfTerminal() {
    if (state.platforms.isEmpty ||
        state.platforms.values.any((entry) => !entry.isTerminal)) {
      return;
    }
    final hasError = state.platforms.values.any(
      (entry) => entry.outcome == StudioPlatformOutcome.error,
    );
    final hasCancellation = state.platforms.values.any(
      (entry) => entry.outcome == StudioPlatformOutcome.cancelled,
    );
    final hasCompleted = state.platforms.values.any(
      (entry) => entry.outcome == StudioPlatformOutcome.complete,
    );
    final hasData = state.platforms.values.any((entry) => entry.hasResultData);
    final isPartial = (hasError || hasCancellation) && hasData;
    final provenance =
        state.provenance ??
        const StudioResultProvenance(
          workspaceName: 'Workspace',
          modelFingerprint: 'unknown',
        );
    final compactPlatforms = state.platforms.map(
      (platform, result) => MapEntry(
        platform,
        result.copyWith(
          history: StudioResultSnapshot.compactHistory(result.history),
        ),
      ),
    );
    final previousSelection = state.lastSuccessfulSnapshot?.selection;
    final firstPlatform = compactPlatforms.keys.first;
    final selection =
        (previousSelection ?? const StudioVisualizationSelection()).copyWith(
          platform: compactPlatforms.containsKey(previousSelection?.platform)
              ? previousSelection?.platform
              : firstPlatform,
          epochIndex: 0,
          clearLayer: true,
        );
    final snapshot = hasData
        ? StudioResultSnapshot(
            id:
                state.attemptId ??
                DateTime.now().toUtc().microsecondsSinceEpoch.toString(),
            completedAt: DateTime.now().toUtc(),
            provenance: provenance,
            platforms: compactPlatforms,
            selection: selection,
            isPartial: isPartial,
          )
        : null;

    if (hasCompleted && !hasError && !hasCancellation && snapshot != null) {
      state = state.copyWith(
        phase: StudioResultSessionPhase.completed,
        platforms: compactPlatforms,
        activeSnapshot: snapshot,
        lastSuccessfulSnapshot: snapshot,
      );
      return;
    }
    if (snapshot != null) {
      state = state.copyWith(
        phase: StudioResultSessionPhase.partial,
        platforms: compactPlatforms,
        activeSnapshot: snapshot,
      );
      return;
    }
    state = state.copyWith(
      phase: hasError
          ? StudioResultSessionPhase.failed
          : StudioResultSessionPhase.completedWithoutResults,
      platforms: compactPlatforms,
      clearActiveSnapshot: true,
    );
  }
}
