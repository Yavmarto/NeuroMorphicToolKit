import 'package:flutter/material.dart';

/// Coloured square + label, used as a chart legend entry inside the health
/// dashboard cards (e.g. inside [SpirometryCard]).
class HealthLegendItem extends StatelessWidget {
  const HealthLegendItem({super.key, required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      spacing: 8,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: ShapeDecoration(
            color: color,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFFE9ECF2),
            fontSize: 14,
            fontFamily: 'Inter',
            fontWeight: FontWeight.w400,
            height: 1.57,
            letterSpacing: -0.50,
          ),
        ),
      ],
    );
  }
}
