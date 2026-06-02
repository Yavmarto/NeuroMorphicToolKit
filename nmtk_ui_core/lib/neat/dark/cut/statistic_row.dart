import 'package:flutter/material.dart';

/// One row inside [StatisticsCard]: bold value + label + signed change.
class StatisticRow extends StatelessWidget {
  const StatisticRow({
    super.key,
    required this.value,
    required this.label,
    required this.change,
    required this.positive,
  });
  final String value, label, change;
  final bool positive;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontFamily: 'Inter',
            fontWeight: FontWeight.w700,
            height: 1.30,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF1D1D25),
            fontSize: 14,
            fontFamily: 'Inter',
            fontWeight: FontWeight.w600,
            height: 1.43,
          ),
        ),
        Text(
          change,
          style: TextStyle(
            color: positive ? const Color(0xFF60D39C) : const Color(0xFFFF5555),
            fontSize: 14,
            fontFamily: 'Inter',
            fontWeight: FontWeight.w600,
            height: 1.43,
          ),
        ),
      ],
    );
  }
}
