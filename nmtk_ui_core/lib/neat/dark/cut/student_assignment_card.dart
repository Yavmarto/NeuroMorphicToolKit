import 'package:flutter/material.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';
import 'package:nmtk_ui_core/neat/dark/cut/status_badge.dart';

/// Student "Assignment" tile (status badge + assignment title + due date).
class StudentAssignmentCard extends StatelessWidget {
  const StudentAssignmentCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 233,
      padding: const EdgeInsets.all(20),
      clipBehavior: Clip.antiAlias,
      decoration: ShapeDecoration(
        color: const Color(0xFF1D1D25),
        shape: RoundedRectangleBorder(
          side: const BorderSide(width: 1, color: Color(0xFF4B4C57)),
          borderRadius: BorderRadius.circular(NmtkShellTokens.of(context).radiusSm),
        ),
      ),
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 16,
        children: [
          Text('Assignment', style: TextStyle(color: Colors.white, fontSize: 20, fontFamily: 'Inter', fontWeight: FontWeight.w700, height: 1.30)),
          StatusBadge(label: 'Not uploaded yet', color: Color(0xFFFF5555), bg: Color(0x33FFBC99)),
          Text('Database Management System', style: TextStyle(color: Colors.white, fontSize: 14, fontFamily: 'Inter', fontWeight: FontWeight.w600, height: 1.43)),
          Text('12 Mar 2021 - 12:00', style: TextStyle(color: Color(0xFF808D9E), fontSize: 14, fontFamily: 'Inter', fontWeight: FontWeight.w400, height: 1.57, letterSpacing: -0.50)),
        ],
      ),
    );
  }
}
