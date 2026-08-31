import 'package:flutter/material.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart' hide AppTheme;

import 'package:neuro_toolkit/features/neurocnl/models/simulator.dart';
import 'package:neuro_toolkit/features/neurocnl/theme/app_theme.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/canvas/animated_snn_playback.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/simulator/signals_metrics.dart';

/// What went into a run, and what carried it.
///
/// The Activity tab plots one population's output three ways, which shows the
/// answer without the question: a raster where early neurons burst and late
/// ones wake up has no visible cause. This tab supplies the missing halves —
/// the input spike train, the per-population rates, and whether the weights
/// doing the work were real.
///
/// Everything here comes from the run being shown and nothing else. A
/// layer-to-layer flow view was tried and removed: its only source was the
/// canvas's Nengo preview, a different engine on a different run, so it would
/// have sat beside this backend's raster implying the two matched.
class SimulatorSignalsTab extends StatelessWidget {
  const SimulatorSignalsTab({super.key, required this.result});

  final SimulatorRunResult result;

  @override
  Widget build(BuildContext context) {
    final dtMs = resolveDtMs(result.metadata);
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _SignalsSection(
          title: 'Input',
          subtitle: result.stimulus == null
              ? null
              : _stimulusSubtitle(result.stimulus!),
          child: _InputRaster(
            stimulus: result.stimulus,
            timesteps: result.timesteps,
            dtMs: dtMs,
          ),
        ),
        const SizedBox(height: 12),
        _SignalsSection(
          title: 'Rates',
          subtitle:
              'Averaged over every neuron in each population, silent ones '
              'included.',
          child: _RatesTable(result: result, dtMs: dtMs),
        ),
        const SizedBox(height: 12),
        _SignalsSection(
          title: 'Weights',
          child: _WeightBreakdown(status: result.trainedWeights),
        ),
      ],
    );
  }

  static String _stimulusSubtitle(SimulatorStimulusRecord stimulus) {
    final origin = stimulus.generated
        ? 'Generated from the run seed'
        : 'Supplied with the run';
    final capped = stimulus.truncated
        ? ' Capped for transport — later neurons are not shown.'
        : '';
    return '$origin, driving ${stimulus.population} '
        '(${stimulus.neuronCount} neurons).$capped';
  }
}

/// The Studio panel container, matching the Run step's result cards.
class _SignalsSection extends StatelessWidget {
  const _SignalsSection({
    required this.title,
    required this.child,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = NmtkShellTokens.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceOf(context).withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        border: Border.all(color: AppTheme.borderOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitle!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppTheme.textSecondaryOf(context),
              ),
            ),
          ],
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _InputRaster extends StatelessWidget {
  const _InputRaster({
    required this.stimulus,
    required this.timesteps,
    required this.dtMs,
  });

  final SimulatorStimulusRecord? stimulus;
  final int timesteps;
  final double dtMs;

  @override
  Widget build(BuildContext context) {
    final record = stimulus;
    if (record == null || record.spikes.isEmpty) {
      return _EmptyNote(
        record == null
            ? 'This run did not record its input. Re-run the simulator to '
                  'capture it.'
            : 'The input spike train was empty, so nothing drove the network.',
      );
    }

    final rows = rasterRows(
      record.spikes,
      dtMs: dtMs,
      neuronCount: record.neuronCount,
    );

    return SizedBox(
      height: 260,
      child: AnimatedSnnPlayback(
        spikes: {for (var i = 0; i < rows.length; i++) '$i': rows[i]},
        duration: timesteps * dtMs,
        populationName: record.population,
        showHeader: false,
      ),
    );
  }
}

class _RatesTable extends StatelessWidget {
  const _RatesTable({required this.result, required this.dtMs});

  final SimulatorRunResult result;
  final double dtMs;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];

    final stimulus = result.stimulus;
    if (stimulus != null && stimulus.spikes.isNotEmpty) {
      rows.add(
        _rateRow(
          context,
          '${stimulus.population} (input)',
          populationStats(
            stimulus.spikes,
            timesteps: result.timesteps,
            dtMs: dtMs,
            neuronCount: stimulus.neuronCount,
          ),
        ),
      );
    }

    for (final entry in result.spikes.entries) {
      rows.add(
        _rateRow(
          context,
          entry.key,
          populationStats(entry.value, timesteps: result.timesteps, dtMs: dtMs),
        ),
      );
    }

    if (rows.isEmpty) {
      return const _EmptyNote('This run recorded no populations.');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows,
    );
  }

  static Widget _rateRow(
    BuildContext context,
    String label,
    PopulationStats stats,
  ) {
    return NmtkKeyValueRow(
      label: label,
      value:
          '${stats.meanRateHz.toStringAsFixed(1)} Hz · '
          '${stats.spikeCount} spikes · '
          '${stats.activeNeurons}/${stats.neuronCount} active',
    );
  }
}

class _WeightBreakdown extends StatelessWidget {
  const _WeightBreakdown({required this.status});

  final TrainedWeightStatus? status;

  @override
  Widget build(BuildContext context) {
    final weights = status;
    if (weights == null) {
      return const _EmptyNote(
        'No trained weights were loaded — this run used the spec\'s zeros, so '
        'nothing could reach threshold.',
      );
    }

    // An older backend sends totals but no breakdown. Show them as layer 1
    // rather than nothing, and say that is what they are.
    final layers = weights.layers.isNotEmpty
        ? weights.layers
        : <TrainedWeightLayer>[
            if (weights.shape != null)
              TrainedWeightLayer(
                name: weights.sourceNode ?? 'layer 1',
                shape: weights.shape!,
                nonzero: weights.nonzero,
              ),
          ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          weights.detail,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: AppTheme.textSecondaryOf(context),
          ),
        ),
        if (layers.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: _EmptyNote('This network has no weight matrix.'),
          )
        else ...[
          const SizedBox(height: 10),
          for (final layer in layers) _DensityBar(layer: layer),
        ],
      ],
    );
  }
}

/// One layer's fill, as a bar plus the numbers behind it.
class _DensityBar extends StatelessWidget {
  const _DensityBar({required this.layer});

  final TrainedWeightLayer layer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = Zeta.of(context).colors;
    final shape = layer.shape.length >= 2
        ? '${layer.shape[0]}×${layer.shape[1]}'
        : 'unknown shape';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Both halves flex: a long layer name and a long figures string can
          // each outgrow a narrow pane, and a fixed-width child in a Row
          // overflows rather than shrinking.
          Row(
            children: [
              Expanded(
                child: Text(
                  layer.name,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  '$shape · ${layer.nonzero} non-zero · '
                  '${(layer.density * 100).toStringAsFixed(1)}% filled',
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppTheme.textSecondaryOf(context),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: layer.density.clamp(0.0, 1.0),
              minHeight: 6,
              backgroundColor: AppTheme.borderOf(context),
              valueColor: AlwaysStoppedAnimation<Color>(
                layer.nonzero == 0 ? colors.mainNegative : colors.mainPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyNote extends StatelessWidget {
  const _EmptyNote(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Text(
      message,
      style: Theme.of(
        context,
      ).textTheme.bodySmall?.copyWith(color: AppTheme.textSecondaryOf(context)),
    );
  }
}
