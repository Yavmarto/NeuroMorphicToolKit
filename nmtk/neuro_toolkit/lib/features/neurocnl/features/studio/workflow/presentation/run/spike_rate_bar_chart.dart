import 'package:flutter/material.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

/// Bar chart for simulator spike rates.

class SpikeRateBarChart extends StatelessWidget {
  const SpikeRateBarChart({super.key, required this.rates});
  final Map<String, double> rates;

  @override
  Widget build(BuildContext context) {
    if (rates.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text(
            'No spike data available.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    final colors = Zeta.of(context).colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rates.entries.map((e) {
        final rate = e.value;
        final color = rate > 0.4 ? colors.mainWarning : colors.mainPrimary;
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    e.key,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(fontSize: 11),
                  ),
                  Text(
                    '${(rate * 100).toStringAsFixed(1)}%',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              LinearProgressIndicator(
                value: rate,
                backgroundColor: colors.surfaceHover,
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}
