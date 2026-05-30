import 'package:flutter/material.dart';

/// One row inside [TransactionHistoryCard]: a description widget, time, and
/// signed amount. [positive] flips the amount colour between green and red.
class TransactionRow extends StatelessWidget {
  const TransactionRow({
    super.key,
    required this.description,
    required this.time,
    required this.amount,
    required this.positive,
  });
  final Widget description;
  final String time, amount;
  final bool positive;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 8,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(child: description),
            Text(
              amount,
              style: TextStyle(
                color: positive
                    ? const Color(0xFF60D39C)
                    : const Color(0xFFFF5555),
                fontSize: 14,
                fontFamily: 'Inter',
                fontWeight: FontWeight.w600,
                height: 1.43,
              ),
            ),
          ],
        ),
        Text(
          time,
          style: const TextStyle(
            color: Color(0xFF2180FF),
            fontSize: 14,
            fontFamily: 'Inter',
            fontWeight: FontWeight.w400,
            height: 1.57,
            letterSpacing: -0.50,
          ),
        ),
        const Divider(color: Color(0xFF4B4C57), thickness: 1),
      ],
    );
  }
}
