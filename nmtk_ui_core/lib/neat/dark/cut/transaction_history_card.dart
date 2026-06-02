import 'package:flutter/material.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';
import 'package:nmtk_ui_core/neat/dark/cut/dark_card_header.dart';
import 'package:nmtk_ui_core/neat/dark/cut/transaction_row.dart';

/// "Transaction History" listing card with rich text rows and a "See All" footer.
class TransactionHistoryCard extends StatelessWidget {
  const TransactionHistoryCard({super.key});

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
            title: 'Transaction History',
            iconColor: Color(0xFFCABDFE),
          ),
          const TransactionRow(
            description: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: 'rakabuming ',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  TextSpan(
                    text: 'purchased ',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  TextSpan(
                    text: 'Epay Wallet App Mobile UI Kit',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            time: 'Just now',
            amount: '+ \$34',
            positive: true,
          ),
          const TransactionRow(
            description: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: 'jovanca ',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  TextSpan(
                    text: 'purchased ',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  TextSpan(
                    text: 'Coca Saas Landing Page UI kit',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            time: '2 hours ago',
            amount: '+ \$39',
            positive: true,
          ),
          const TransactionRow(
            description: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: 'Payout ',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  TextSpan(
                    text: 'to hello@neat.co ',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  TextSpan(
                    text: 'failed',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            time: '2 hours ago',
            amount: '+ \$1,839.67',
            positive: false,
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
                  'See All Transaction',
                  style: TextStyle(
                    color: Color(0xFFE9ECF2),
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
