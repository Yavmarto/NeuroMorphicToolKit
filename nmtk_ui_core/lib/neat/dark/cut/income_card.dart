import 'package:flutter/material.dart';
import 'amount_display.dart';
import 'dark_card_header.dart';

/// "Income" card on the finance page: header + [AmountDisplay] + chart slot.
class IncomeCard extends StatelessWidget {
  const IncomeCard({super.key});

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
          DarkCardHeader(title: 'Income', iconColor: Color(0xFFC7DFFF)),
          AmountDisplay(amount: '2,180', currency: 'USD'),
          SizedBox(height: 80),
        ],
      ),
    );
  }
}
