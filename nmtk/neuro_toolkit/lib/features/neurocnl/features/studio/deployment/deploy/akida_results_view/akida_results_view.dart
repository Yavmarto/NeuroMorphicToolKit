import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurocnl/models/studio_result_session.dart';
import 'package:neuro_toolkit/features/neurocnl/models/studio_result_visualization.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/studio_akida_deploy_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/studio_result_session_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/workflow/workflow_feature.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/deploy/akida_benchmark_result_view/akida_benchmark_result_view.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/deploy/akida_sample_result_view/akida_sample_result_view.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/deploy/akida_visualization_panel/akida_visualization_panel.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/deploy/studio_result_surface/studio_result_surface.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/deploy/studio_result_surface/support.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/deploy/akida_results_view/support.dart';

class AkidaResultsView extends ConsumerStatefulWidget {
  const AkidaResultsView({super.key, this.sourceBuilder});

  final Widget Function(
    StudioVisualizationContext context,
    StudioResultView view,
  )?
  sourceBuilder;

  @override
  ConsumerState<AkidaResultsView> createState() => _AkidaResultsViewState();
}

class _AkidaResultsViewState extends ConsumerState<AkidaResultsView> {
  late StudioResultSurfaceView _selectedView;

  @override
  void initState() {
    super.initState();
    _selectedView = _viewFor(
      ref.read(studioAkidaDeployProvider).latestResultKind,
    );
  }

  StudioResultSurfaceView _viewFor(StudioAkidaResultKind? kind) =>
      kind == StudioAkidaResultKind.benchmark
      ? StudioResultSurfaceView.benchmark
      : StudioResultSurfaceView.sample;

  Map<String, double> _normalizedLayerActivity(
    StudioAkidaSampleSnapshot? snapshot,
  ) {
    final layers = snapshot?.prediction.layerSpikes;
    if (layers == null || layers.isEmpty) return const <String, double>{};
    final maximum = layers.fold<int>(
      0,
      (current, layer) => math.max(current, layer.nzSpikes),
    );
    return <String, double>{
      for (final layer in layers)
        layer.name: maximum == 0 ? 0 : layer.nzSpikes / maximum,
    };
  }

  StudioVisualizationContext _visualizationContext(
    StudioAkidaDeployState provider,
    StudioResultSnapshot? sourceSnapshot,
  ) {
    final sample = provider.sampleResult;
    final job = provider.deploymentJob;
    final resultProvenance = sample?.provenance;
    final hardwareVerified = provider.hardwareVerified;
    final runtimeTarget =
        resultProvenance?.runtimeTarget ?? job?.runtimeTarget ?? 'hardware';
    final architectureActivity = _normalizedLayerActivity(sample);
    final sourceSnapshotId =
        resultProvenance?.sourceSnapshotId ?? provider.deployedSourceSnapshotId;
    final overlay = architectureActivity.isEmpty
        ? null
        : StudioHardwareArchitectureOverlay(
            provenance: StudioVisualizationProvenance(
              source: StudioVisualizationSource.hardware,
              label: hardwareVerified || runtimeTarget == 'hardware'
                  ? 'Akida hardware · aggregate layer activity'
                  : 'Akida simulator · aggregate layer activity',
              hostId: resultProvenance?.hostId ?? provider.selectedHost?.id,
              modelId: resultProvenance?.modelId ?? job?.modelId,
              sourceSnapshotId: sourceSnapshotId,
              hardwareVerified: hardwareVerified,
            ),
            activity: architectureActivity,
          );
    return StudioVisualizationContext(
      sourceSnapshot: sourceSnapshot,
      hardwareArchitectureOverlay: overlay,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Follow the most recent result rather than latching whatever was showing
    // when this step was opened. A listener rather than an assignment during
    // build: mutating selection mid-build moved the segmented control under
    // the user's finger when a background result landed.
    ref.listen(
      studioAkidaDeployProvider.select((state) => state.latestResultKind),
      (previous, next) {
        if (next == null || next == previous) return;
        setState(() => _selectedView = _viewFor(next));
      },
    );
    final provider = ref.watch(studioAkidaDeployProvider);
    final sourceSnapshot = ref.watch(
      studioResultSessionProvider.select(
        (session) => session.persistableSnapshot,
      ),
    );
    final visualization = AkidaVisualizationPanel(
      sourceBuilder: (view) {
        final builder = widget.sourceBuilder;
        if (builder != null) {
          return builder(_visualizationContext(provider, sourceSnapshot), view);
        }
        return const SizedBox.shrink();
      },
      visualization: provider.visualizationResult,
      loading: provider.isLoadingVisualization,
      error: provider.visualizationError,
      physicalHardwareVerified: provider.hardwareVerified,
      onLayerSelected: ref
          .read(studioAkidaDeployProvider.notifier)
          .selectVisualizationLayer,
    );

    final surface = StudioResultSurface(
      selectedView: _selectedView,
      onViewChanged: (view) => setState(() => _selectedView = view),
      sampleChild: AkidaSampleResultView(snapshot: provider.sampleResult),
      benchmarkChild: AkidaBenchmarkResultView(
        snapshot: provider.benchmarkResult,
      ),
    );

    // The step header already titles this page and states the hardware
    // provenance, so this view starts straight at the content.
    return LayoutBuilder(
      builder: (context, constraints) {
        // Both panels need a bounded height — the whole step scrolls — but the
        // bound follows the window instead of a fixed 680/560.
        final panelHeight = math.max(
          kMinPanelHeight,
          MediaQuery.sizeOf(context).height - kPanelChromeAllowance,
        );
        if (constraints.maxWidth >= NmtkShellTokens.wideBreakpoint) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 2,
                child: SizedBox(height: panelHeight, child: visualization),
              ),
              const SizedBox(width: 24),
              // Flexes with the window rather than pinning to 360, but stays
              // inside a readable measure for stacked metric tiles.
              Expanded(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minWidth: kSurfaceMinWidth,
                    maxWidth: kSurfaceMaxWidth,
                  ),
                  child: surface,
                ),
              ),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(height: panelHeight, child: visualization),
            const SizedBox(height: 24),
            surface,
          ],
        );
      },
    );
  }
}
