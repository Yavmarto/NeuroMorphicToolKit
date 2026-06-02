import 'package:flutter/material.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';
import 'package:nmtk_ui_core/neat/dark/cut/dark_card_header.dart';
import 'package:nmtk_ui_core/neat/dark/cut/task_row.dart';

/// "Today Tasks" card listing several [TaskRow]s plus a "See All" footer.
class TodayTasksCard extends StatelessWidget {
  const TodayTasksCard({super.key});

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
          borderRadius: BorderRadius.circular(
            NmtkShellTokens.of(context).radiusSm,
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 24,
        children: [
          const DarkCardHeader(
            title: 'Today Tasks',
            iconColor: Color(0xFFFFBC99),
          ),
          const TaskRow(
            title: 'Continue Iteration Booking Flow',
            date: '18 May, 2022',
            done: true,
          ),
          const TaskRow(
            title: 'Wireframing SIAKAD 4.0',
            date: '18 May, 2022',
            done: true,
          ),
          const TaskRow(
            title: 'Visual Messaging Module',
            date: '18 May, 2022',
            done: false,
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: ShapeDecoration(
              color: const Color(0xFF1D1D25),
              shape: RoundedRectangleBorder(
                side: const BorderSide(width: 2, color: Color(0xFF4B4C57)),
                borderRadius: BorderRadius.circular(
                  NmtkShellTokens.of(context).radiusSm,
                ),
              ),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'See All Task',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
