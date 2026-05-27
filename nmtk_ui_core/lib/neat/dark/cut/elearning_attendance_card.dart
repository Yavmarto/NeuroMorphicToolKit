import 'package:flutter/material.dart';
import 'attendance_summary.dart';
import 'dark_card_header.dart';

/// "Attendance" placeholder chart card on the e-learning page.
class ElearningAttendanceCard extends StatelessWidget {
  const ElearningAttendanceCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 343,
      padding: const EdgeInsets.all(20),
      clipBehavior: Clip.antiAlias,
      decoration: ShapeDecoration(
        color: const Color(0xFF1D1D25),
        shape: RoundedRectangleBorder(
          side: const BorderSide(width: 1, color: Color(0xFF4B4C57)),
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 24,
        children: const [
          DarkCardHeader(title: 'Attendance', iconColor: Color(0xFFB5E4CA)),
          SizedBox(height: 120),
          AttendanceSummary(name: 'Azalea Zidni', days: '18 days'),
        ],
      ),
    );
  }
}
