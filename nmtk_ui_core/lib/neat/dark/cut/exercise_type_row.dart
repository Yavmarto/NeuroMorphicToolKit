import 'package:flutter/material.dart';

/// One row inside [WorkoutOverviewCard]: coloured square + label + percent.
class ExerciseTypeRow extends StatelessWidget {
  const ExerciseTypeRow({super.key, required this.label, required this.percent, required this.color});
  final String label, percent;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(spacing: 8, children: [
          Container(width: 8, height: 8, decoration: ShapeDecoration(color: color, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)))),
          Text(label, style: const TextStyle(color: Color(0xFF808D9E), fontSize: 14, fontFamily: 'Inter', fontWeight: FontWeight.w600, height: 1.43)),
        ]),
        Text(percent, textAlign: TextAlign.right, style: const TextStyle(color: Colors.white, fontSize: 14, fontFamily: 'Inter', fontWeight: FontWeight.w600, height: 1.43)),
      ],
    );
  }
}
