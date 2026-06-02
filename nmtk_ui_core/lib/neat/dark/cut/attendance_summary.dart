import 'package:flutter/material.dart';

/// Tiny "name + days" caption used inside [ElearningAttendanceCard].
class AttendanceSummary extends StatelessWidget {
  const AttendanceSummary({super.key, required this.name, required this.days});
  final String name, days;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          name,
          style: const TextStyle(
            color: Color(0xFF1D1D25),
            fontSize: 14,
            fontFamily: 'Inter',
            fontWeight: FontWeight.w600,
            height: 1.43,
          ),
        ),
        Text(
          days,
          style: const TextStyle(
            color: Color(0xFF808D9E),
            fontSize: 12,
            fontFamily: 'Inter',
            fontWeight: FontWeight.w400,
            height: 1.67,
          ),
        ),
      ],
    );
  }
}
