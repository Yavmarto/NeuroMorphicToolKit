import 'package:neuro_toolkit/features/neurocnl/providers/training_provider.dart';

enum StudioResultView {
  architecture,
  grid,
  raster,
  weights;

  /// Human-readable name for the view switch.
  ///
  /// Also what a screen reader announces: `ZetaSegmentedControl` excludes its
  /// child semantics and exposes `value.toString()` instead, so the label has
  /// to live on the value itself rather than only in the `Text` we hand it.
  /// Serialization is unaffected — that goes through `.name`.
  String get label => switch (this) {
    StudioResultView.architecture => 'Architecture',
    StudioResultView.grid => 'Grid',
    StudioResultView.raster => 'Raster',
    StudioResultView.weights => 'Weights',
  };

  @override
  String toString() => label;
}

enum StudioResultArchitectureSource { sourceRun, hardware }

enum StudioPlatformOutcome {
  idle,
  running,
  complete,
  error,
  notApplicable,
  cancelled,
}

class StudioVisualizationSelection {
  const StudioVisualizationSelection({
    this.view = StudioResultView.grid,
    this.platform,
    this.epochIndex = 0,
    this.layer,
  });

  factory StudioVisualizationSelection.fromJson(Map<String, dynamic> json) {
    return StudioVisualizationSelection(
      view: StudioResultView.values.firstWhere(
        (value) => value.name == json['view'],
        orElse: () => StudioResultView.grid,
      ),
      platform: json['platform'] as String?,
      epochIndex: (json['epochIndex'] as num?)?.toInt() ?? 0,
      layer: json['layer'] as String?,
    );
  }

  final StudioResultView view;
  final String? platform;
  final int epochIndex;
  final String? layer;

  StudioVisualizationSelection copyWith({
    StudioResultView? view,
    String? platform,
    int? epochIndex,
    String? layer,
    bool clearLayer = false,
  }) {
    return StudioVisualizationSelection(
      view: view ?? this.view,
      platform: platform ?? this.platform,
      epochIndex: epochIndex ?? this.epochIndex,
      layer: clearLayer ? null : (layer ?? this.layer),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'view': view.name,
    'platform': platform,
    'epochIndex': epochIndex,
    'layer': layer,
  };
}

class CompletedJobReference {
  const CompletedJobReference({required this.jobId, this.service = 'training'});

  factory CompletedJobReference.fromJson(Map<String, dynamic> json) {
    return CompletedJobReference(
      jobId: json['jobId'] as String,
      service: json['service'] as String? ?? 'training',
    );
  }

  final String jobId;
  final String service;

  Map<String, Object?> toJson() => <String, Object?>{
    'jobId': jobId,
    'service': service,
  };
}

class StudioResultProvenance {
  const StudioResultProvenance({
    required this.workspaceName,
    required this.modelFingerprint,
  });

  factory StudioResultProvenance.fromJson(Map<String, dynamic> json) {
    return StudioResultProvenance(
      workspaceName: json['workspaceName'] as String? ?? 'Workspace',
      modelFingerprint: json['modelFingerprint'] as String? ?? 'legacy',
    );
  }

  final String workspaceName;
  final String modelFingerprint;

  Map<String, Object?> toJson() => <String, Object?>{
    'workspaceName': workspaceName,
    'modelFingerprint': modelFingerprint,
  };
}

class StudioPlatformResult {
  const StudioPlatformResult({
    required this.platform,
    this.outcome = StudioPlatformOutcome.idle,
    this.history = const <TrainingEpochEvent>[],
    this.completedJob,
    this.summary,
    this.detail,
    this.notApplicableReason,
  });

  factory StudioPlatformResult.fromJson(Map<String, dynamic> json) {
    final historyJson = json['history'] as List<dynamic>? ?? const <dynamic>[];
    final jobJson = json['completedJob'];
    return StudioPlatformResult(
      platform: json['platform'] as String,
      outcome: StudioPlatformOutcome.values.firstWhere(
        (value) => value.name == json['outcome'],
        orElse: () => StudioPlatformOutcome.complete,
      ),
      history: historyJson
          .whereType<Map<Object?, Object?>>()
          .map(
            (entry) =>
                TrainingEpochEvent.fromJson(Map<String, dynamic>.from(entry)),
          )
          .toList(growable: false),
      completedJob: jobJson is Map<Object?, Object?>
          ? CompletedJobReference.fromJson(Map<String, dynamic>.from(jobJson))
          : null,
      summary: json['summary'] as String?,
      detail: json['detail'] as String?,
      notApplicableReason: json['notApplicableReason'] as String?,
    );
  }

  final String platform;
  final StudioPlatformOutcome outcome;
  final List<TrainingEpochEvent> history;
  final CompletedJobReference? completedJob;
  final String? summary;
  final String? detail;
  final String? notApplicableReason;

  bool get isTerminal => switch (outcome) {
    StudioPlatformOutcome.complete ||
    StudioPlatformOutcome.error ||
    StudioPlatformOutcome.notApplicable ||
    StudioPlatformOutcome.cancelled => true,
    _ => false,
  };

  bool get hasResultData => history.isNotEmpty || completedJob != null;

  StudioPlatformResult copyWith({
    StudioPlatformOutcome? outcome,
    List<TrainingEpochEvent>? history,
    CompletedJobReference? completedJob,
    String? summary,
    String? detail,
    String? notApplicableReason,
    bool clearSummary = false,
    bool clearDetail = false,
    bool clearNotApplicableReason = false,
  }) {
    return StudioPlatformResult(
      platform: platform,
      outcome: outcome ?? this.outcome,
      history: history ?? this.history,
      completedJob: completedJob ?? this.completedJob,
      summary: clearSummary ? null : (summary ?? this.summary),
      detail: clearDetail ? null : (detail ?? this.detail),
      notApplicableReason: clearNotApplicableReason
          ? null
          : (notApplicableReason ?? this.notApplicableReason),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'platform': platform,
    'outcome': outcome.name,
    'history': history.map((event) => event.toJson()).toList(growable: false),
    'completedJob': completedJob?.toJson(),
    'summary': summary,
    'detail': detail,
    'notApplicableReason': notApplicableReason,
  };
}

class StudioResultSnapshot {
  const StudioResultSnapshot({
    required this.id,
    required this.completedAt,
    required this.provenance,
    required this.platforms,
    required this.selection,
    required this.isPartial,
  });

  static const int schemaVersion = 1;
  static const int maxEventsPerPlatform = 512;

  factory StudioResultSnapshot.fromJson(Map<String, dynamic> json) {
    final platformJson =
        json['platforms'] as Map? ?? const <dynamic, dynamic>{};
    return StudioResultSnapshot(
      id: json['id'] as String,
      completedAt:
          DateTime.tryParse(json['completedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      provenance: StudioResultProvenance.fromJson(
        Map<String, dynamic>.from(
          json['provenance'] as Map? ?? const <String, dynamic>{},
        ),
      ),
      platforms: platformJson.map(
        (key, value) => MapEntry(
          key.toString(),
          StudioPlatformResult.fromJson(
            Map<String, dynamic>.from(value as Map),
          ),
        ),
      ),
      selection: StudioVisualizationSelection.fromJson(
        Map<String, dynamic>.from(
          json['selection'] as Map? ?? const <String, dynamic>{},
        ),
      ),
      isPartial: json['isPartial'] == true,
    );
  }

  factory StudioResultSnapshot.fromLegacyHistory(
    Map<String, dynamic> history, {
    String workspaceName = 'Restored workspace',
  }) {
    final platforms = <String, StudioPlatformResult>{};
    for (final entry in history.entries) {
      final rawEvents = entry.value;
      if (rawEvents is! List) continue;
      final events = rawEvents
          .whereType<Map<Object?, Object?>>()
          .map(
            (event) =>
                TrainingEpochEvent.fromJson(Map<String, dynamic>.from(event)),
          )
          .toList(growable: false);
      if (events.isEmpty) continue;
      platforms[entry.key] = StudioPlatformResult(
        platform: entry.key,
        outcome: StudioPlatformOutcome.complete,
        history: compactHistory(events),
      );
    }
    final now = DateTime.now().toUtc();
    return StudioResultSnapshot(
      id: 'legacy-${now.microsecondsSinceEpoch}',
      completedAt: now,
      provenance: StudioResultProvenance(
        workspaceName: workspaceName,
        modelFingerprint: 'legacy',
      ),
      platforms: platforms,
      selection: StudioVisualizationSelection(
        platform: platforms.keys.firstOrNull,
      ),
      isPartial: false,
    );
  }

  final String id;
  final DateTime completedAt;
  final StudioResultProvenance provenance;
  final Map<String, StudioPlatformResult> platforms;
  final StudioVisualizationSelection selection;
  final bool isPartial;

  Map<String, List<TrainingEpochEvent>> get history =>
      <String, List<TrainingEpochEvent>>{
        for (final entry in platforms.entries) entry.key: entry.value.history,
      };

  bool get hasVisualizationData =>
      platforms.values.any((platform) => platform.hasResultData);

  StudioResultSnapshot copyWith({StudioVisualizationSelection? selection}) {
    return StudioResultSnapshot(
      id: id,
      completedAt: completedAt,
      provenance: provenance,
      platforms: platforms,
      selection: selection ?? this.selection,
      isPartial: isPartial,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'id': id,
    'completedAt': completedAt.toIso8601String(),
    'provenance': provenance.toJson(),
    'platforms': platforms.map(
      (platform, result) => MapEntry(platform, result.toJson()),
    ),
    'selection': selection.toJson(),
    'isPartial': isPartial,
  };

  static List<TrainingEpochEvent> compactHistory(
    List<TrainingEpochEvent> events,
  ) {
    final summarized = <String, TrainingEpochEvent>{};
    for (final event in events) {
      summarized['${event.phase}:${event.epoch}'] = event;
    }
    final values = summarized.values.toList(growable: false);
    if (values.length <= maxEventsPerPlatform) return values;
    final half = maxEventsPerPlatform ~/ 2;
    return <TrainingEpochEvent>[
      ...values.take(half),
      ...values.skip(values.length - half),
    ];
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
