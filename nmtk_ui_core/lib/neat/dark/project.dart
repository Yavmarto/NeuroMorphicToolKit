import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:nmtk_ui_core/neat/dark/cut/dark_status_bar.dart';
import 'package:nmtk_ui_core/neat/dark/cut/dark_top_bar.dart';
import 'package:nmtk_ui_core/neat/dark/cut/project_widgets.dart';

class NeatProject extends StatelessWidget {
  @Preview(
    name: 'Neat Dark – Project',
    group: 'Neat Dark Pages',
    size: Size(375, 1497),
  )
  const NeatProject({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 375,
          height: 1497,
          clipBehavior: Clip.antiAlias,
          decoration: const BoxDecoration(color: Color(0xFF1D1D25)),
          child: const Stack(
            children: [
              Positioned(left: 0, top: 0, child: DarkStatusBar()),
              Positioned(left: 0, top: 44, child: DarkTopBar()),
              Positioned(left: 16, top: 156, child: WorkspaceHeader()),
              Positioned(left: 16, top: 264, child: ProjectsCompletedCard()),
              Positioned(
                left: 195,
                top: 264,
                child: ProjectSmallCountCard(
                  value: '12',
                  label: 'Inquiry',
                  iconBg: Color(0xFFB5E4CA),
                ),
              ),
              Positioned(
                left: 195,
                top: 380,
                child: ProjectSmallCountCard(
                  value: '28',
                  label: 'On Going',
                  iconBg: Color(0xFFCABDFE),
                ),
              ),
              Positioned(left: 16, top: 496, child: RecentProjectsCard()),
              Positioned(left: 16, top: 1037, child: TodayTasksCard()),
            ],
          ),
        ),
      ],
    );
  }
}
