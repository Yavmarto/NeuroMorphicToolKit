import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:nmtk_ui_core/neat/dark/cut/dark_status_bar.dart';
import 'package:nmtk_ui_core/neat/dark/cut/dark_top_bar.dart';
import 'package:nmtk_ui_core/neat/dark/cut/student_widgets.dart';

class NeatStudent extends StatelessWidget {
  @Preview(name: 'Neat Dark – Student', group: 'Neat Dark Pages', size: Size(375, 1021))
  const NeatStudent({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 375,
          height: 1021,
          clipBehavior: Clip.antiAlias,
          decoration: const BoxDecoration(color: Color(0xFF1D1D25)),
          child: const Stack(
            children: [
              Positioned(left: 0, top: 0, child: DarkStatusBar()),
              Positioned(left: 0, top: 44, child: DarkTopBar()),
              Positioned(left: 16, top: 156, child: StudentProfileCard()),
              Positioned(left: 16, top: 384, child: SksCard()),
              Positioned(left: 152, top: 384, child: TodayScheduleCard()),
              Positioned(left: 16, top: 586, child: StudentAssignmentCard()),
              Positioned(left: 265, top: 586, child: BillCard()),
              Positioned(left: 16, top: 816, child: IpsGraphCard()),
            ],
          ),
        ),
      ],
    );
  }
}
