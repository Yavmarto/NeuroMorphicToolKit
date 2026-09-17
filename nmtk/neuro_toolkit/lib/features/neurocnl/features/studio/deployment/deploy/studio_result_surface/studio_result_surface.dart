library;

import 'package:flutter/material.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/deploy/studio_result_surface/support.dart';

class StudioResultSurface extends StatelessWidget {
  const StudioResultSurface({
    super.key,
    required this.selectedView,
    required this.onViewChanged,
    required this.sampleChild,
    required this.benchmarkChild,
  });

  final StudioResultSurfaceView selectedView;
  final ValueChanged<StudioResultSurfaceView> onViewChanged;
  final Widget sampleChild;
  final Widget benchmarkChild;

  @override
  Widget build(BuildContext context) {
    final colors = Zeta.of(context).colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ZetaSegmentedControl<StudioResultSurfaceView>(
          semanticLabel: 'Result kind',
          selected: selectedView,
          onChanged: onViewChanged,
          segments: [
            for (final view in StudioResultSurfaceView.values)
              ZetaButtonSegment<StudioResultSurfaceView>(
                value: view,
                child: Text(view.label),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Divider(height: 1, color: colors.borderSubtle),
        const SizedBox(height: 16),
        Semantics(
          container: true,
          label: selectedView == StudioResultSurfaceView.sample
              ? 'Akida sample result'
              : 'Akida benchmark result',
          child: selectedView == StudioResultSurfaceView.sample
              ? sampleChild
              : benchmarkChild,
        ),
      ],
    );
  }
}
