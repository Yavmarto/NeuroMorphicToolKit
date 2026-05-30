import 'package:flutter/material.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';

/// Tall "Projects Complete" tile showing the cumulative project count (140).
class ProjectsCompletedCard extends StatelessWidget {
  const ProjectsCompletedCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 164,
      height: 216,
      decoration: ShapeDecoration(
        color: const Color(0xFF1D1D25),
        shape: RoundedRectangleBorder(
          side: const BorderSide(width: 1, color: Color(0xFF4B4C57)),
          borderRadius: BorderRadius.circular(NmtkShellTokens.of(context).radiusSm),
        ),
      ),
      padding: const EdgeInsets.all(20),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 12,
        children: [
          CircleAvatar(radius: 21, backgroundColor: Color(0xFFFFD88D)),
          Text('140', style: TextStyle(color: Colors.white, fontSize: 36, fontFamily: 'Inter', fontWeight: FontWeight.w700, height: 1.17, letterSpacing: -0.36)),
          Text('Projects Complete', style: TextStyle(color: Color(0xFF808D9E), fontSize: 12, fontFamily: 'Inter', fontWeight: FontWeight.w400, height: 1.33)),
        ],
      ),
    );
  }
}
