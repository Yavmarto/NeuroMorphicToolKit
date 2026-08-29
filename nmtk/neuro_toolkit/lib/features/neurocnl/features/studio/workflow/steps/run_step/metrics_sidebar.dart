import 'package:flutter/material.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart' hide AppTheme;

import 'package:neuro_toolkit/features/neurocnl/theme/app_theme.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/workflow/workflow_feature.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/workflow/steps/run_step/support.dart';

class MetricsSidebar extends StatefulWidget {
  const MetricsSidebar({
    super.key,
    required this.status,
    required this.epochs,
    required this.lastEpoch,
    required this.colors,
    this.isHorizontal = false,
  });

  final TrainingStatus status;
  final List<TrainingEpochEvent> epochs;
  final TrainingEpochEvent? lastEpoch;
  final ZetaColors colors;

  /// Mobile layout: a full-width horizontal strip instead of a fixed-width
  /// vertical column (see run_step.dart's LayoutBuilder in _RunStepState).
  /// The taller Spikes chart moves into a bottom sheet since there's no room
  /// for it in a strip.
  final bool isHorizontal;

  @override
  State<MetricsSidebar> createState() => _MetricsSidebarState();
}

class _MetricsSidebarState extends State<MetricsSidebar> {
  /// Shared between the vertical-collapsed and horizontal layouts. Short
  /// labels (`Ep`/`Lss`/`Acc`) exist only because an 80px column has no room
  /// for full words — a full-width horizontal strip does, so it uses the
  /// long form instead.
  List<Widget> _compactRows({required bool shortLabels}) => [
    MetricRow(
      label: shortLabels ? 'Ep' : 'Epoch',
      value: widget.lastEpoch == null ? '—' : '${widget.lastEpoch!.epoch}',
      isExpanded: false,
    ),
    MetricRow(
      label: shortLabels ? 'Lss' : 'Loss',
      value: widget.lastEpoch == null
          ? '—'
          : widget.lastEpoch!.loss.toStringAsFixed(4),
      isExpanded: false,
    ),
    MetricRow(
      label: shortLabels ? 'Acc' : 'Accuracy',
      value: widget.lastEpoch?.accuracy == null
          ? '—'
          : '${(widget.lastEpoch!.accuracy! * 100).toStringAsFixed(1)}%',
      isExpanded: false,
    ),
  ];

  void _openSpikesSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(NmtkShellTokens.of(context).radiusLg),
        ),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Spikes',
                style: Theme.of(
                  sheetContext,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: SingleChildScrollView(
                  child: SpikeRateBarChart(
                    rates: widget.lastEpoch?.layerSpikeRates ?? {},
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isHorizontal) {
      final bool running = widget.status == TrainingStatus.running;
      return Container(
        color: AppTheme.surface,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            for (final row in _compactRows(shortLabels: false))
              Expanded(child: row),
            if (running)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
              ),
            IconButton(
              tooltip: 'Spike rates',
              constraints: const BoxConstraints.tightFor(width: 40, height: 40),
              icon: const Icon(ZetaIcons.expand_less, size: 20),
              onPressed: () => _openSpikesSheet(context),
            ),
          ],
        ),
      );
    }

    return Container(
      width: 240,
      decoration: const BoxDecoration(
        border: Border(right: BorderSide(color: AppTheme.border)),
        color: AppTheme.surface,
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Text(
            'Live Metrics',
            style: Zeta.of(
              context,
            ).textStyles.titleMedium.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),

          // Metrics
          Expanded(
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        MetricRow(
                          label: 'Epoch',
                          value: widget.lastEpoch == null
                              ? '—'
                              : '${widget.lastEpoch!.epoch} / ${widget.lastEpoch!.totalEpochs ?? '?'}',
                          isExpanded: true,
                        ),
                        MetricRow(
                          label: 'Loss',
                          value: widget.lastEpoch == null
                              ? '—'
                              : widget.lastEpoch!.loss.toStringAsFixed(4),
                          isExpanded: true,
                        ),
                        MetricRow(
                          label: 'Accuracy',
                          value: widget.lastEpoch?.accuracy == null
                              ? '—'
                              : '${(widget.lastEpoch!.accuracy! * 100).toStringAsFixed(1)}%',
                          isExpanded: true,
                        ),
                        if (widget.status == TrainingStatus.running) ...[
                          const SizedBox(height: 12),
                          LinearProgressIndicator(
                            value:
                                (widget.lastEpoch != null &&
                                    widget.lastEpoch!.totalEpochs != null)
                                ? widget.lastEpoch!.epoch /
                                      widget.lastEpoch!.totalEpochs!
                                : null,
                            backgroundColor: widget.colors.surfaceHover,
                            valueColor: AlwaysStoppedAnimation(
                              widget.colors.mainPrimary,
                            ),
                          ),
                        ],
                        const SizedBox(height: 24),
                        Text(
                          'Spikes',
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 12),
                        SpikeRateBarChart(
                          rates: widget.lastEpoch?.layerSpikeRates ?? {},
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
