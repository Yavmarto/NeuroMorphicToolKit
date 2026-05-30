import 'package:flutter/material.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';
import 'package:nmtk_ui_core/neat/dark/cut/weekly_day_column.dart';

/// Weekly calendar card showing days S–M with dates 25–31.
/// Day 28 (K/Thursday) is highlighted red, today marked with a blue dot.
class WeeklyCalendarCard extends StatelessWidget {
  const WeeklyCalendarCard({super.key});

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
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        spacing: 24,
        children: [
          const SizedBox(
            width: double.infinity,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              spacing: 377,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  spacing: 16,
                  children: [
                    Text(
                      'Weekly Calendar',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w700,
                        height: 1.30,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Day columns
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              WeeklyDayColumn(dayLabel: 'S', dateLabel: '25', isHighlighted: false),
              WeeklyDayColumn(dayLabel: 'S', dateLabel: '26', isHighlighted: false),
              WeeklyDayColumn(dayLabel: 'R', dateLabel: '27', isHighlighted: false),
              WeeklyDayColumn(dayLabel: 'K', dateLabel: '28', isHighlighted: true),
              WeeklyDayColumn(dayLabel: 'J', dateLabel: '29', isHighlighted: false),
              WeeklyDayColumn(dayLabel: 'S', dateLabel: '30', isHighlighted: false),
              WeeklyDayColumn(dayLabel: 'M', dateLabel: '31', isHighlighted: false),
            ],
          ),
          // Today dot
          Container(
            width: 8.22,
            height: 8,
            decoration: const ShapeDecoration(
              color: Color(0xFF2180FF),
              shape: OvalBorder(),
            ),
          ),
          // Event note
          const Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: 'August ',
                  style: TextStyle(
                    color: Color(0xFFFF5555),
                    fontSize: 12,
                    fontFamily: 'Roboto',
                    fontWeight: FontWeight.w400,
                  ),
                ),
                TextSpan(
                  text: '28',
                  style: TextStyle(
                    color: Color(0xFFFF6955),
                    fontSize: 12,
                    fontFamily: 'Roboto',
                    fontWeight: FontWeight.w400,
                  ),
                ),
                TextSpan(
                  text: ' : Designer Day World Wide',
                  style: TextStyle(
                    color: Color(0xFFFF5555),
                    fontSize: 12,
                    fontFamily: 'Roboto',
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 6,
            height: 6,
            decoration: const ShapeDecoration(
              color: Color(0xFFFF5555),
              shape: OvalBorder(),
            ),
          ),
        ],
      ),
    );
  }
}

