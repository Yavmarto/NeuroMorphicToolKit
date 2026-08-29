import 'package:flutter/material.dart';

import 'package:neuro_toolkit/features/neurocnl/theme/app_theme.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/canvas/spike_raster_plot.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/canvas/time_series_chart.dart';

/// Combined SNN dynamics visualization for a single population.
///
/// Shows (top to bottom):
///   1. Population firing-rate bar chart over time
///   2. Spike raster plot
///   3. Membrane-potential time-series traces
///
/// The three views share the same horizontal time axis so the causal
/// relationship between firing rate, individual spikes, and membrane
/// potential is visually aligned.
///
/// When [voltages] is absent or empty the voltage section is omitted and
/// the raster expands to fill the extra space.
class SnnDynamicsView extends StatelessWidget {
  /// neuron_id → list of spike times (ms)
  final Map<String, List<double>> spikes;

  /// neuron_id → list of voltage samples (mV)
  final Map<String, List<double>>? voltages;

  /// Total simulation duration in milliseconds
  final double duration;

  /// Population name shown in the header
  final String populationName;

  const SnnDynamicsView({
    super.key,
    required this.spikes,
    this.voltages,
    required this.duration,
    this.populationName = '',
  });

  bool get _hasVoltages =>
      voltages != null &&
      voltages!.isNotEmpty &&
      voltages!.values.any((v) => v.isNotEmpty);

  /// Computes per-window firing rates for the population.
  List<double> _computeFiringRates(int nWindows) {
    final rates = List<double>.filled(nWindows, 0.0);
    final windowSize = duration / nWindows;
    for (final neuronSpikes in spikes.values) {
      for (final t in neuronSpikes) {
        final idx = (t / windowSize).floor().clamp(0, nWindows - 1);
        rates[idx] += 1.0;
      }
    }
    // Normalise to Hz (spikes per second) for the window.
    final scale = 1000.0 / windowSize; // ms → s
    for (int i = 0; i < nWindows; i++) {
      rates[i] = rates[i] * scale;
    }
    return rates;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final spikeList = spikes.values.toList();

    if (spikeList.isEmpty && !_hasVoltages) {
      return Center(
        child: Text(
          'No data recorded for this population.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: AppTheme.textSecondaryOf(context),
          ),
        ),
      );
    }

    final title = populationName.isNotEmpty
        ? '$populationName Dynamics'
        : 'Population Dynamics';

    // Firing-rate chart (compact, always shown when spikes exist)
    final firingRateWidget = _FiringRateBarChart(
      rates: _computeFiringRates(40),
      duration: duration,
    );

    if (!_hasVoltages) {
      return Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 2),
              child: Text(
                title,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            SizedBox(height: 48, child: firingRateWidget),
            const SizedBox(height: 4),
            Expanded(
              child: SpikeRasterPlot(
                spikes: spikeList,
                duration: duration,
                title: 'Spike Raster (spikes only — no membrane traces)',
              ),
            ),
          ],
        ),
      );
    }

    final timePoints = List<double>.generate(
      voltages!.values.first.length,
      (i) => i.toDouble(),
    );
    final voltageLabels = voltages!.keys.toList();
    final voltageTraces = voltages!.values.toList();

    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 2),
            child: Text(
              title,
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          SizedBox(height: 48, child: firingRateWidget),
          const SizedBox(height: 4),
          Expanded(
            flex: 8,
            child: SpikeRasterPlot(
              spikes: spikeList,
              duration: duration,
              title: '',
            ),
          ),
          const SizedBox(height: 4),
          if (voltageLabels.isNotEmpty)
            _VoltageLegend(
              labels: voltageLabels,
              count: voltageLabels.length.clamp(0, 8),
            ),
          Expanded(
            flex: 10,
            child: TimeSeriesChart(
              traces: voltageTraces,
              time: timePoints,
              labels: voltageLabels,
              title: 'Membrane Potential (mV)',
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact horizontal bar chart showing population firing rate over time.
class _FiringRateBarChart extends StatelessWidget {
  final List<double> rates;
  final double duration;

  const _FiringRateBarChart({required this.rates, required this.duration});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (rates.isEmpty) return const SizedBox.shrink();

    final maxRate = rates.reduce((a, b) => a > b ? a : b);
    final scale = maxRate > 0 ? 1.0 / maxRate : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 1),
          child: Text(
            'Population Firing Rate',
            style: theme.textTheme.labelSmall?.copyWith(fontSize: 9),
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final barWidth = constraints.maxWidth / rates.length;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final rate in rates)
                    Container(
                      width: barWidth - 0.5,
                      height: rate * scale * constraints.maxHeight,
                      // Interpolate dim→primary so colour communicates activity.
                      color: Color.lerp(
                        AppTheme.primaryDim,
                        AppTheme.primaryOf(context),
                        rate * scale,
                      ),
                    ),
                ],
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 4, top: 1),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '0 ms',
                style: theme.textTheme.bodySmall?.copyWith(fontSize: 8),
              ),
              Text(
                '${duration.toStringAsFixed(0)} ms',
                style: theme.textTheme.bodySmall?.copyWith(fontSize: 8),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Small horizontal legend for voltage traces.
class _VoltageLegend extends StatelessWidget {
  final List<String> labels;
  final int count;

  const _VoltageLegend({required this.labels, required this.count});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final colors = <Color>[
      AppTheme.primaryOf(context),
      AppTheme.success,
      AppTheme.errorOf(context),
      AppTheme.warning,
      AppTheme.info,
      AppTheme.primaryDim,
      isDark
          ? AppTheme.primaryOf(context).withValues(alpha: 0.6)
          : AppTheme.primaryOf(context).withValues(alpha: 0.5),
      isDark
          ? AppTheme.success.withValues(alpha: 0.6)
          : AppTheme.success.withValues(alpha: 0.5),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Wrap(
        spacing: 8,
        runSpacing: 2,
        children: [
          for (int i = 0; i < labels.length && i < count; i++)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: colors[i % colors.length],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 3),
                Text(
                  labels[i],
                  style: theme.textTheme.bodySmall?.copyWith(fontSize: 9),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
