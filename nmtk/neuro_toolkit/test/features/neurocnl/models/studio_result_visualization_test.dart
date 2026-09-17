import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/features/neurocnl/models/studio_result_session.dart';
import 'package:neuro_toolkit/features/neurocnl/models/studio_result_visualization.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/training_provider.dart';

StudioResultSnapshot _snapshot(String id) => StudioResultSnapshot(
  id: id,
  completedAt: DateTime.utc(2026, 8, 10),
  provenance: const StudioResultProvenance(
    workspaceName: 'Overlay test',
    modelFingerprint: 'model-a',
  ),
  platforms: const <String, StudioPlatformResult>{
    'lava_sim': StudioPlatformResult(
      platform: 'lava_sim',
      outcome: StudioPlatformOutcome.complete,
      history: <TrainingEpochEvent>[TrainingEpochEvent(epoch: 1, loss: 0.1)],
    ),
  },
  selection: const StudioVisualizationSelection(platform: 'lava_sim'),
  isPartial: false,
);

StudioHardwareArchitectureOverlay _overlay(String sourceSnapshotId) {
  return StudioHardwareArchitectureOverlay(
    provenance: StudioVisualizationProvenance(
      source: StudioVisualizationSource.hardware,
      label: 'Akida hardware',
      sourceSnapshotId: sourceSnapshotId,
      hardwareVerified: true,
    ),
    activity: const <String, double>{'lif_1': 1},
  );
}

void main() {
  test(
    'hardware activity is available only for the deployed source snapshot',
    () {
      final matching = StudioVisualizationContext(
        sourceSnapshot: _snapshot('source-a'),
        hardwareArchitectureOverlay: _overlay('source-a'),
      );
      final mismatched = StudioVisualizationContext(
        sourceSnapshot: _snapshot('source-b'),
        hardwareArchitectureOverlay: _overlay('source-a'),
      );

      expect(matching.matchedHardwareOverlay, isNotNull);
      expect(mismatched.matchedHardwareOverlay, isNull);
    },
  );
}
