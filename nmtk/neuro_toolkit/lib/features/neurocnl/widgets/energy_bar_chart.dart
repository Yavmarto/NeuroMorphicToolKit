import 'package:flutter/material.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart' hide AppTheme;
import 'package:neuro_toolkit/features/neurocnl/models/energy_report.dart';
import 'package:neuro_toolkit/features/neurocnl/theme/app_theme.dart';

/// Horizontal bar chart showing per-ensemble energy consumption.
class EnergyBarChart extends StatelessWidget {
  final EnergyReport report;

  const EnergyBarChart({super.key, required this.report});

  @override
  Widget build(BuildContext context) {
    final entries = report.perEnsemblePj.entries.toList();
    if (entries.isEmpty) {
      return const Center(
        child: Text(
          'No ensemble data',
          style: TextStyle(color: AppTheme.textSecondary),
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
            color: AppTheme.surfaceVariant,
            borderRadius: BorderRadius.circular(
              NmtkShellTokens.of(context).radiusSm,
            ),
            border: Border.all(color: AppTheme.border),
          ),
          child: Row(
            children: [
              _SummaryChip(
                icon: Icons.bolt, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
                label: 'Total Energy',
                value: '${report.totalPj.toStringAsFixed(2)} pJ',
                color: AppTheme.warning,
              ),
              const SizedBox(width: 16),
              _SummaryChip(
                icon: Icons
                    .functions, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
                label: 'Operations',
                value: report.opsCount.toString(),
                color: AppTheme.info,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Per-ensemble bars
        Expanded(
          child: ListView.separated(
            itemCount: entries.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
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
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 11,
                ),
              ),
              Text(
                value,
                style: TextStyle(
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              name,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            Text(
              '${valuePj.toStringAsFixed(2)} pJ',
              style: const TextStyle(
                color: AppTheme.synNumber,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: fraction,
            minHeight: 10,
            backgroundColor: AppTheme.surfaceVariant,
            valueColor: AlwaysStoppedAnimation<Color>(
              Color.lerp(AppTheme.success, AppTheme.warning, fraction) ??
                  AppTheme.primary,
            ),
          ),
        ),
      ],
    );
  }
}
