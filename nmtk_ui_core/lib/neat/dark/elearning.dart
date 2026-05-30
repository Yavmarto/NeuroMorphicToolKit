import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:nmtk_ui_core/neat/dark/cut/dark_status_bar.dart';
import 'package:nmtk_ui_core/neat/dark/cut/dark_top_bar.dart';
import 'package:nmtk_ui_core/neat/dark/cut/elearning_widgets.dart';

class NeatElearning extends StatelessWidget {
  @Preview(name: 'Neat Dark – E-Learning', group: 'Neat Dark Pages', size: Size(375, 1222))
  const NeatElearning({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 375,
          height: 1222,
          clipBehavior: Clip.antiAlias,
          decoration: const BoxDecoration(color: Color(0xFF1D1D25)),
          child: const Stack(
            children: [
              Positioned(left: 0, top: 0, child: DarkStatusBar()),
              Positioned(left: 0, top: 44, child: DarkTopBar()),
              Positioned(left: 16, top: 156, child: AnnouncementCard()),
              Positioned(left: 16, top: 257, child: _QuickLinksRow()),
              Positioned(left: 16, top: 405, child: NewMaterialCard()),
              Positioned(left: 16, top: 865, child: ElearningAttendanceCard()),
            ],
          ),
        ),
      ],
    );
  }
}

class _QuickLinksRow extends StatelessWidget {
  const _QuickLinksRow();

  @override
  Widget build(BuildContext context) {
    return const Row(
      spacing: 16,
      children: [
        QuickLinkCard(label: 'Assignment', sublabel: 'Online'),
        QuickLinkCard(label: 'Lecturer Site', sublabel: 'Academic'),
        QuickLinkCard(label: 'Assignment', sublabel: 'Online'),
      ],
    );
  }
}
