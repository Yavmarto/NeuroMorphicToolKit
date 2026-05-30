import 'package:flutter/material.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';

/// Outline filter chip used inside [OverviewChartCard]. Note: this class
/// shadows Flutter's `material.FilterChip`; consumers in this neat/dark tree
/// should reference it by its package path.
class FilterChip extends StatelessWidget {
  const FilterChip({super.key, required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: ShapeDecoration(
        shape: RoundedRectangleBorder(
          side: const BorderSide(width: 2, color: Color(0xFF808D9E)),
          borderRadius: BorderRadius.circular(NmtkShellTokens.of(context).radiusSm),
        ),
      ),
      child: Text(label, style: const TextStyle(color: Color(0xFF808D9E), fontSize: 14, fontFamily: 'Inter', fontWeight: FontWeight.w600, height: 1.43)),
    );
  }
}
