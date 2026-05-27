import 'package:flutter/material.dart';

/// Shared chart legend row (coloured square + label) used across multiple
/// neat dark screens.
class ChartLegendRow extends StatelessWidget {
  const ChartLegendRow({super.key, required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 8,
      children: [
        Container(
          width: 10, height: 10,
          decoration: ShapeDecoration(color: color, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2))),
        ),
        Text(label, style: const TextStyle(color: Colors.white, fontSize: 14, fontFamily: 'Inter', fontWeight: FontWeight.w600, height: 1.43)),
      ],
    );
  }
}
