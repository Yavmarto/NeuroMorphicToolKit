import 'package:flutter/material.dart';
import 'dark_card_header.dart';
import 'weight_progress_section.dart';

/// "Gain Weight" hero card on the workout page.
class GainWeightCard extends StatelessWidget {
  const GainWeightCard({super.key});

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
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        spacing: 24,
        children: [
          DarkCardHeader(title: 'Gain Weight', iconColor: Color(0xFFFFD88D)),
          WeightProgressSection(),
        ],
      ),
    );
  }
}
