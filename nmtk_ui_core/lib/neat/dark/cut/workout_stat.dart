import 'package:flutter/material.dart';

/// Single workout summary cell (icon disc + value + label) used inside
/// [WorkoutStatsCard].
class WorkoutStat extends StatelessWidget {
  const WorkoutStat({super.key, required this.iconBg, required this.value, required this.label});
  final Color iconBg;
  final String value, label;

  @override
  Widget build(BuildContext context) {
    return Column(spacing: 8, children: [
      Container(width: 48, height: 48, decoration: ShapeDecoration(color: iconBg, shape: const OvalBorder())),
      Text(value, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 16, fontFamily: 'Inter', fontWeight: FontWeight.w700, height: 1.25)),
      Text(label, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF808D9E), fontSize: 14, fontFamily: 'Inter', fontWeight: FontWeight.w400, height: 1.57, letterSpacing: -0.50)),
    ]);
  }
}
