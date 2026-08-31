import 'package:flutter/material.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurocnl/models/dataset_sample.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/presentation/pynq/frame_painter.dart';

class SamplePreview extends StatelessWidget {
  const SamplePreview({super.key, required this.sample});

  final DatasetSample sample;

  @override
  Widget build(BuildContext context) {
    final colors = Zeta.of(context).colors;
    final side = sample.previewSide;
    if (side == null) return const SizedBox.shrink();
    return SizedBox(
      key: const Key('pynq-sample-preview'),
      width: 84,
      height: 84,
      child: CustomPaint(
        painter: FramePainter(
          spikes: sample.inputSpikes,
          side: side,
          on: colors.mainDefault,
          off: colors.surfaceHover,
        ),
      ),
    );
  }
}
