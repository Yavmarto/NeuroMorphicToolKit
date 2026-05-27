import 'package:flutter/material.dart';

/// Small "value over label" pair (e.g. "+ 3.9 kg / Gained") used inside
/// [WeightProgressSection].
class WorkoutStatItem extends StatelessWidget {
  const WorkoutStatItem({super.key, required this.value, required this.label});
  final String value, label;

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Text(value, style: const TextStyle(color: Colors.white, fontSize: 16, fontFamily: 'Inter', fontWeight: FontWeight.w700, height: 1.25)),
      Text(label, style: const TextStyle(color: Color(0xFF808D9E), fontSize: 14, fontFamily: 'Inter', fontWeight: FontWeight.w400, height: 1.57, letterSpacing: -0.50)),
    ]);
  }
}
