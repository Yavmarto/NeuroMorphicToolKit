import 'package:flutter/material.dart';

/// Compact "Workspace" tile (icon + workspace name) shown above project metrics.
class WorkspaceHeader extends StatelessWidget {
  const WorkspaceHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 343,
      height: 92,
      decoration: ShapeDecoration(
        color: const Color(0xFF1D1D25),
        shape: RoundedRectangleBorder(
          side: const BorderSide(width: 1, color: Color(0xFF4B4C57)),
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      padding: const EdgeInsets.all(20),
      child: Row(
        spacing: 12,
        children: [
          Container(
            width: 48, height: 48,
            decoration: ShapeDecoration(
              color: const Color(0xFF1D1D25),
              shape: RoundedRectangleBorder(
                side: const BorderSide(width: 1, color: Color(0xFF4B4C57)),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Workspace', style: TextStyle(color: Color(0xFF7E8BA0), fontSize: 12, fontFamily: 'Inter', fontWeight: FontWeight.w400, height: 1.33)),
              Text('Sans Design', style: TextStyle(color: Colors.white, fontSize: 20, fontFamily: 'Inter', fontWeight: FontWeight.w700, height: 1.30)),
            ],
          ),
        ],
      ),
    );
  }
}
