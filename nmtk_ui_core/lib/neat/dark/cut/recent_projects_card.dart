import 'package:flutter/material.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';
import 'package:nmtk_ui_core/neat/dark/cut/dark_card_header.dart';
import 'package:nmtk_ui_core/neat/dark/cut/project_row.dart';

/// "Recent Projects" card listing several [ProjectRow]s plus a "See All" footer.
class RecentProjectsCard extends StatelessWidget {
  const RecentProjectsCard({super.key});

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
          borderRadius: BorderRadius.circular(NmtkShellTokens.of(context).radiusSm),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 24,
        children: [
          const DarkCardHeader(title: 'Recent Projects', iconColor: Color(0xFFB0E5FC)),
          const ProjectRow(title: 'Clinic Health Application for Patient', visibility: 'Private', timeLeft: '3 days left', progress: 0.78, positive: false),
          const ProjectRow(title: '#Day 22 Exploration : Health App for...', visibility: 'Private', timeLeft: '3 days left', progress: 0.20, positive: false),
          const ProjectRow(title: 'Epay Wallet App UI Kit', visibility: 'Public', timeLeft: '11 days left', progress: 0.89, positive: true),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: ShapeDecoration(
              color: const Color(0xFF1D1D25),
              shape: RoundedRectangleBorder(
                side: const BorderSide(width: 2, color: Color(0xFF4B4C57)),
                borderRadius: BorderRadius.circular(NmtkShellTokens.of(context).radiusSm),
              ),
            ),
            child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text('See All Project', style: TextStyle(color: Colors.white, fontSize: 16, fontFamily: 'Inter', fontWeight: FontWeight.w700, height: 1.25)),
            ]),
          ),
        ],
      ),
    );
  }
}
