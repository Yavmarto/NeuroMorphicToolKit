import 'package:flutter/material.dart';
import 'dark_card_header.dart';
import 'outcome_row.dart';

/// "Outcome" breakdown card on the finance page (chart placeholder + 4 rows).
class OutcomeCard extends StatelessWidget {
  const OutcomeCard({super.key});

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
          DarkCardHeader(title: 'Outcome', iconColor: Color(0xFFCABDFE)),
          SizedBox(height: 120),
          OutcomeRow(label: 'Transfers', percent: '45%'),
          OutcomeRow(label: 'Withdrawals', percent: '25%'),
          OutcomeRow(label: 'Subscription', percent: '10%'),
          OutcomeRow(label: 'Others', percent: '5%'),
        ],
      ),
    );
  }
}
