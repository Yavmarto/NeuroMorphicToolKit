import 'package:flutter/material.dart';
import 'package:zeta_flutter/zeta_flutter.dart';
import 'package:nmtk_ui_core/models/energy_report.dart';
import 'package:nmtk_ui_core/shell_tokens.dart';

/// Horizontal bar chart showing per-ensemble energy consumption.
class NmtkEnergyBarChart extends StatelessWidget {
  final EnergyReport report;
  final Color? totalEnergyColor;
  final Color? operationsColor;

  const NmtkEnergyBarChart({
    super.key,
    required this.report,
    this.totalEnergyColor,
    this.operationsColor,
  });

  @override
  Widget build(BuildContext context) {
    final entries = report.perEnsemblePj.entries.toList();
    final theme = Theme.of(context);
    final tokens = NmtkShellTokens.of(context);

    if (entries.isEmpty) {
      return Center(
        child: Text(
          'No ensemble data',
          style: Zeta.of(context).textStyles.bodyMedium.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    final maxValue = entries
        .map((e) => e.value)
        .reduce((a, b) => a > b ? a : b);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Summary row
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(tokens.radiusSm),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Row(
            children: [
              _SummaryChip(
                icon: Icons.bolt,
                label: 'Total Energy',
                value: '${report.totalPj.toStringAsFixed(2)} pJ',
                color: totalEnergyColor ?? theme.colorScheme.primary,
              ),
              const SizedBox(width: 16),
              _SummaryChip(
                icon: Icons.functions,
                label: 'Operations',
                value: report.opsCount.toString(),
                color: operationsColor ?? theme.colorScheme.secondary,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Per-ensemble bars
        Expanded(
          child: ListView.separated(
            itemCount: entries.length,
            separatorBuilder: (context, index) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final entry = entries[index];
              final fraction = maxValue > 0 ? entry.value / maxValue : 0.0;
              return _EnergyBar(
                name: entry.key,
                valuePj: entry.value,
                fraction: fraction,
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SummaryChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _SummaryChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: Zeta.of(context).textStyles.bodyMedium.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 11,
                ),
              ),
              Text(
                value,
                style: Zeta.of(context).textStyles.bodyMedium.copyWith(
                  color: color,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EnergyBar extends StatelessWidget {
  final String name;
  final double valuePj;
  final double fraction;

  const _EnergyBar({
    required this.name,
    required this.valuePj,
    required this.fraction,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              name,
              style: Zeta.of(context).textStyles.bodyMedium.copyWith(
                color: theme.colorScheme.onSurface,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            Text(
              '${valuePj.toStringAsFixed(2)} pJ',
              style: Zeta.of(context).textStyles.bodyMedium.copyWith(
                color: theme.colorScheme.primary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        LinearProgressIndicator(
          value: fraction,
          minHeight: 10,
          backgroundColor: theme.colorScheme.surfaceContainerHighest,
          valueColor: AlwaysStoppedAnimation<Color>(
            Color.lerp(
                  theme.colorScheme.primary,
                  theme.colorScheme.error,
                  fraction,
                ) ??
                theme.colorScheme.primary,
          ),
        ),
      ],
    );
  }
}
