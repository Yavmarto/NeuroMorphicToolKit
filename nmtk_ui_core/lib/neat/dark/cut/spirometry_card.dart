import 'package:flutter/material.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';
import 'package:nmtk_ui_core/neat/dark/cut/dark_card_header.dart';
import 'package:nmtk_ui_core/neat/dark/cut/health_legend_item.dart';

/// Spirometry chart card with legend rows for FEV1 and PEF.
class SpirometryCard extends StatelessWidget {
  const SpirometryCard({super.key});

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
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 24,
        children: [
          DarkCardHeader(title: 'Spirometry', iconColor: Color(0xFFCABDFE)),
          SizedBox(height: 160),
          HealthLegendItem(color: Color(0xFF60D39C), label: 'FEV1, L'),
          HealthLegendItem(color: Color(0xFFFF5555), label: 'PEF, L/sec'),
        ],
      ),
    );
  }
}
