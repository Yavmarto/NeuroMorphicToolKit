import 'package:flutter/material.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';
import 'package:nmtk_ui_core/neat/dark/cut/chart_legend_row.dart';
import 'package:nmtk_ui_core/neat/dark/cut/dark_card_header.dart';

/// Customer Growth card with a placeholder chart area and three legend rows.
class CustomerGrowthCard extends StatelessWidget {
  const CustomerGrowthCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 343,
      padding: const EdgeInsets.all(20),
      clipBehavior: Clip.antiAlias,
      decoration: ShapeDecoration(
        color: const Color(0xFF1D1D25),
        shape: RoundedRectangleBorder(
          side: const BorderSide(width: 1, color: Color(0xFF4B4C57)),
          borderRadius: BorderRadius.circular(
            NmtkShellTokens.of(context).radiusSm,
          ),
        ),
      ),
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        spacing: 24,
        children: [
          DarkCardHeader(
            title: 'Customer Growth',
            iconColor: Color(0xFFCABDFE),
          ),
          SizedBox(height: 120),
          ChartLegendRow(color: Color(0xFF2180FF), label: '10-20 yo'),
          ChartLegendRow(color: Color(0xFF20BFF7), label: '21-30 yo'),
          ChartLegendRow(color: Color(0xFFFFBC99), label: '31 + yo'),
        ],
      ),
    );
  }
}
