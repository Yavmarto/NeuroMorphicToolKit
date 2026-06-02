import 'package:flutter/material.dart';

/// Big amount + currency pill, used as the headline of [IncomeCard].
class AmountDisplay extends StatelessWidget {
  const AmountDisplay({
    super.key,
    required this.amount,
    required this.currency,
  });
  final String amount, currency;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      spacing: 8,
      children: [
        Text(
          amount,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 36,
            fontFamily: 'Inter',
            fontWeight: FontWeight.w700,
            height: 1.17,
            letterSpacing: -0.36,
          ),
        ),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: ShapeDecoration(
            color: const Color(0xFFFFD88D),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          child: Text(
            currency,
            style: const TextStyle(
              color: Color(0xFF1D1D25),
              fontSize: 10,
              fontFamily: 'Inter',
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
