import 'package:flutter/material.dart';

/// One row inside [RecentProjectsCard]: title, visibility, time-left, and a
/// progress bar.
class ProjectRow extends StatelessWidget {
  const ProjectRow({super.key, required this.title, required this.visibility, required this.timeLeft, required this.progress, required this.positive});
  final String title, visibility, timeLeft;
  final double progress;
  final bool positive;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 8,
      children: [
        Text(title, style: const TextStyle(color: Colors.white, fontSize: 16, fontFamily: 'Inter', fontWeight: FontWeight.w700, height: 1.25)),
        Row(spacing: 8, children: [
          Text(visibility, style: const TextStyle(color: Color(0xFF7E8BA0), fontSize: 14, fontFamily: 'Inter', fontWeight: FontWeight.w400, height: 1.57, letterSpacing: -0.50)),
          Container(width: 4, height: 4, decoration: const ShapeDecoration(color: Color(0xFF808D9E), shape: OvalBorder())),
          Text(timeLeft, style: TextStyle(color: positive ? const Color(0xFF20BFF7) : const Color(0xFFFF5555), fontSize: 14, fontFamily: 'Inter', fontWeight: FontWeight.w400, height: 1.57, letterSpacing: -0.50)),
        ]),
        LinearProgressIndicator(
          value: progress,
          backgroundColor: const Color(0xFF808D9E),
          valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF47BD68)),
          minHeight: 4,
          borderRadius: BorderRadius.circular(6),
        ),
        const Divider(color: Color(0xFF4B4C57), thickness: 1),
      ],
    );
  }
}
