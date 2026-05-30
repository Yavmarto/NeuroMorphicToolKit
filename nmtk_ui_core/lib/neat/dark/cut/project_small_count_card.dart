import 'package:flutter/material.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';

/// Compact stat tile (icon + value + label) used in the project metrics grid.
class ProjectSmallCountCard extends StatelessWidget {
  const ProjectSmallCountCard({super.key, required this.value, required this.label, required this.iconBg});
  final String value, label;
  final Color iconBg;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 164,
      height: 100,
      decoration: ShapeDecoration(
        color: const Color(0xFF1D1D25),
        shape: RoundedRectangleBorder(
          side: const BorderSide(width: 1, color: Color(0xFF4B4C57)),
          borderRadius: BorderRadius.circular(NmtkShellTokens.of(context).radiusSm),
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        spacing: 12,
        children: [
          Container(width: 36, height: 36, decoration: ShapeDecoration(color: iconBg, shape: const OvalBorder())),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(value, style: const TextStyle(color: Colors.white, fontSize: 24, fontFamily: 'Inter', fontWeight: FontWeight.w700, height: 1.25)),
              Text(label, style: const TextStyle(color: Color(0xFF808D9E), fontSize: 12, fontFamily: 'Inter', fontWeight: FontWeight.w400, height: 1.33)),
            ],
          ),
        ],
      ),
    );
  }
}
