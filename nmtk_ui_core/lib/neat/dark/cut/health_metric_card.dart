import 'package:flutter/material.dart';

/// Coloured health-metric tile (label + big value + unit).
class HealthMetricCard extends StatelessWidget {
  const HealthMetricCard({super.key, required this.color, required this.label, required this.value, required this.unit});
  final Color color;
  final String label, value, unit;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 164,
      height: 174,
      decoration: ShapeDecoration(color: color, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 8,
        children: [
          Opacity(opacity: 0.50, child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 14, fontFamily: 'Inter', fontWeight: FontWeight.w600, height: 1.43))),
          Row(crossAxisAlignment: CrossAxisAlignment.end, spacing: 4, children: [
            Text(value, style: const TextStyle(color: Colors.white, fontSize: 36, fontFamily: 'Inter', fontWeight: FontWeight.w700, height: 1.17, letterSpacing: -0.36)),
            Text(unit, style: const TextStyle(color: Colors.white, fontSize: 14, fontFamily: 'Inter', fontWeight: FontWeight.w400, height: 1.57, letterSpacing: -0.50)),
          ]),
        ],
      ),
    );
  }
}
