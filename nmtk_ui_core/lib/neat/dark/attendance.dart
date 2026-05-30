import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:nmtk_ui_core/neat/dark/cut/dark_status_bar.dart';
import 'package:nmtk_ui_core/neat/dark/cut/dark_top_bar.dart';
import 'package:nmtk_ui_core/neat/dark/cut/attendance_check_in_card.dart';
import 'package:nmtk_ui_core/neat/dark/cut/attendance_recap_card.dart';
import 'package:nmtk_ui_core/neat/dark/cut/weekly_calendar_card.dart';

class NeatAttendance extends StatelessWidget {
  @Preview(name: 'Neat Dark – Attendance', group: 'Neat Dark Pages', size: Size(375, 1072))
  const NeatAttendance({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 375,
          height: 1072,
          clipBehavior: Clip.antiAlias,
          decoration: const BoxDecoration(color: Color(0xFF1D1D25)),
          child: const Stack(
            children: [
              Positioned(left: 0, top: 0, child: DarkStatusBar()),
              Positioned(left: 0, top: 44, child: DarkTopBar()),
              Positioned(left: 16, top: 156, child: AttendanceCheckInCard()),
              Positioned(left: 16, top: 449, child: AttendanceRecapCard()),
              Positioned(left: 16, top: 867, child: WeeklyCalendarCard()),
            ],
          ),
        ),
      ],
    );
  }
}
