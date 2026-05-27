import 'package:flutter/material.dart';

/// Single coloured stat row used inside [AttendanceRecapCard]
/// (e.g. "16 days Present").
class AttendanceStatRow extends StatelessWidget {
  const AttendanceStatRow({
    super.key,
    required this.color,
    required this.label,
    required this.value,
  });

  final Color color;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      spacing: 8,
      children: [
        Container(
          transform: Matrix4.identity()..rotateZ(1.57),
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
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontFamily: 'Inter',
            fontWeight: FontWeight.w700,
            height: 1.25,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF737A8B),
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
