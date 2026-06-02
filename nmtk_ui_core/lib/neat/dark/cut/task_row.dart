import 'package:flutter/material.dart';

/// One row inside [TodayTasksCard]: title (struck-through when [done]) and date.
class TaskRow extends StatelessWidget {
  const TaskRow({
    super.key,
    required this.title,
    required this.date,
    required this.done,
  });
  final String title, date;
  final bool done;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 4,
      children: [
        Text(
          title,
          style: TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontFamily: 'Inter',
            fontWeight: FontWeight.w600,
            height: 1.43,
            decoration: done ? TextDecoration.lineThrough : null,
          ),
        ),
        Text(
          date,
          style: const TextStyle(
            color: Color(0xFF808D9E),
            fontSize: 12,
            fontFamily: 'Inter',
            fontWeight: FontWeight.w400,
            height: 1.33,
          ),
        ),
        const Divider(color: Color(0xFF4B4C57), thickness: 1),
      ],
    );
  }
}
