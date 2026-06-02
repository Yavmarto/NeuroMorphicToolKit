import 'package:flutter/material.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';
import 'package:nmtk_ui_core/neat/dark/cut/exercise_type_row.dart';

/// "Workout overview" card listing cardio/strength/stretch percentages.
class WorkoutOverviewCard extends StatelessWidget {
  const WorkoutOverviewCard({super.key});

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
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        spacing: 24,
        children: [
          ExerciseTypeRow(
            label: 'Cardio',
            percent: '50%',
            color: Color(0xFF8E59FF),
          ),
          ExerciseTypeRow(
            label: 'Strength',
            percent: '30%',
            color: Color(0xFFFF5555),
          ),
          ExerciseTypeRow(
            label: 'Stretch',
            percent: '20%',
            color: Color(0xFF20BFF7),
          ),
        ],
      ),
    );
  }
}
