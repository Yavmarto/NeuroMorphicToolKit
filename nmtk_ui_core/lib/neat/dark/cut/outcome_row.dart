import 'package:flutter/material.dart';

/// One row inside [OutcomeCard]: label on the left, percentage on the right.
class OutcomeRow extends StatelessWidget {
  const OutcomeRow({super.key, required this.label, required this.percent});
  final String label, percent;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Color(0xFF808D9E), fontSize: 14, fontFamily: 'Inter', fontWeight: FontWeight.w600, height: 1.43)),
        Text(percent, style: const TextStyle(color: Colors.white, fontSize: 14, fontFamily: 'Inter', fontWeight: FontWeight.w600, height: 1.43)),
      ],
    );
  }
}
