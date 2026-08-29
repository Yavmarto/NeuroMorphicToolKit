import 'package:neuro_toolkit/features/neurocnl/models/studio_result_session.dart';

enum StudioVisualizationSource { sourceRun, hardware }

/// Identifies the runtime and model behind an optional hardware overlay.
class StudioVisualizationProvenance {
  const StudioVisualizationProvenance({
    required this.source,
    required this.label,
    this.hostId,
    this.modelId,
    this.sourceSnapshotId,
    this.hardwareVerified = false,
  });

  final StudioVisualizationSource source;
  final String label;
  final String? hostId;
  final String? modelId;
  final String? sourceSnapshotId;
  final bool hardwareVerified;
}

class StudioHardwareArchitectureOverlay {
  const StudioHardwareArchitectureOverlay({
    required this.provenance,
    required this.activity,
  });

  final StudioVisualizationProvenance provenance;
  final Map<String, double> activity;

  bool matches(StudioResultSnapshot snapshot) =>
      provenance.sourceSnapshotId != null &&
      provenance.sourceSnapshotId == snapshot.id;
}

/// Source results are always the primary visualization context. Hardware may
/// add a provenance-matched Architecture overlay, but it cannot replace or
/// disable the source Grid, Raster, or Weights views.
class StudioVisualizationContext {
  const StudioVisualizationContext({
    required this.sourceSnapshot,
    this.hardwareArchitectureOverlay,
  });

  final StudioResultSnapshot? sourceSnapshot;
  final StudioHardwareArchitectureOverlay? hardwareArchitectureOverlay;

  StudioHardwareArchitectureOverlay? get matchedHardwareOverlay {
    final snapshot = sourceSnapshot;
    final overlay = hardwareArchitectureOverlay;
    if (snapshot == null || overlay == null || !overlay.matches(snapshot)) {
      return null;
    }
    return overlay;
  }
}
