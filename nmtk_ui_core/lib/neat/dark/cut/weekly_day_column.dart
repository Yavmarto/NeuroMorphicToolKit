import 'package:flutter/material.dart';

/// One day cell (letter + date) used in [WeeklyCalendarCard]'s row.
/// When [isHighlighted] is true the date number renders in red.
class WeeklyDayColumn extends StatelessWidget {
  const WeeklyDayColumn({
    super.key,
    required this.dayLabel,
    required this.dateLabel,
    required this.isHighlighted,
  });

  final String dayLabel;
  final String dateLabel;
  final bool isHighlighted;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          dayLabel,
          style: const TextStyle(
            color: Color(0xFF737A8B),
            fontSize: 14,
            fontFamily: 'Inter',
            fontWeight: FontWeight.w400,
            height: 1.57,
            letterSpacing: -0.50,
          ),
        ),
        Text(
          dateLabel,
          style: TextStyle(
            color: isHighlighted ? const Color(0xFFFF5555) : Colors.white,
            fontSize: 16,
            fontFamily: 'Inter',
            fontWeight: FontWeight.w700,
            height: 1.25,
          ),
        ),
      ],
    );
  }
}
