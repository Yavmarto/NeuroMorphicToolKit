import 'package:flutter/material.dart';
import 'package:nmtk_ui_core/widgets/adaptive_layout.dart';
import 'package:neuro_toolkit/features/neurocnl/models/quantization_report.dart';
import 'package:neuro_toolkit/features/neurocnl/theme/app_theme.dart';

/// Table/visual showing bit-width vs accuracy drop and sparsity.
class QuantizationCurveChart extends StatelessWidget {
  final QuantizationReport report;

  const QuantizationCurveChart({super.key, required this.report});

  @override
  Widget build(BuildContext context) {
    if (report.bitWidths.isEmpty) {
      return const Center(
        child: Text(
          'No quantization data',
          style: TextStyle(color: AppTheme.textSecondary),
        ),
      );
    }
    return NmtkAdaptiveLayout(
      desktopBuilder: (_) => _buildTable(),
      mobileBuilder: (_) => _buildList(),
    );
  }

  Widget _buildTable() {
    return DataTable(
      headingRowColor: const WidgetStatePropertyAll(AppTheme.surfaceVariant),
      dataRowColor: const WidgetStatePropertyAll(AppTheme.surface),
      border: TableBorder.all(color: AppTheme.border, width: 1),
      columnSpacing: 24,
      columns: const [
        DataColumn(
          label: Text(
            'Bit Width',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        DataColumn(
          label: Text(
            'Accuracy Drop',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        DataColumn(
          label: Text(
            'Sparsity',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
      rows: List.generate(report.bitWidths.length, (i) {
        final bits = report.bitWidths[i];
        final drop = report.accuracyDrops[i];
        final sparsity = report.sparsity[i];
        return DataRow(
          cells: [
            DataCell(
              Text(
                '$bits-bit',
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            DataCell(_AccuracyDropIndicator(drop: drop)),
            DataCell(
              Text(
                '${(sparsity * 100).toStringAsFixed(1)}%',
                style: const TextStyle(color: AppTheme.textPrimary),
              ),
            ),
          ],
        );
      }),
    );
  }

  Widget _buildList() {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: report.bitWidths.length,
      itemBuilder: (context, i) {
        final bits = report.bitWidths[i];
        final drop = report.accuracyDrops[i];
        final sparsity = report.sparsity[i];
        return ListTile(
          leading: _AccuracyDropIndicator(drop: drop),
          title: Text(
            '$bits-bit',
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontWeight: FontWeight.w500,
            ),
          ),
          subtitle: Text(
            'Drop ${(drop * 100).toStringAsFixed(2)}%  ·  '
            'Sparsity ${(sparsity * 100).toStringAsFixed(1)}%',
            style: const TextStyle(color: AppTheme.textSecondary),
          ),
        );
      },
    );
  }
}

/// Colored indicator for accuracy drop: green < 2%, yellow < 5%, red >= 5%.
class _AccuracyDropIndicator extends StatelessWidget {
  final double drop;

  const _AccuracyDropIndicator({required this.drop});

  @override
  Widget build(BuildContext context) {
    final pct = drop * 100;
    final Color color;
    if (pct < 2) {
      color = AppTheme.success;
    } else if (pct < 5) {
      color = AppTheme.warning;
    } else {
      color = AppTheme.error;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(
          '${pct.toStringAsFixed(2)}%',
          style: TextStyle(color: color, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}
