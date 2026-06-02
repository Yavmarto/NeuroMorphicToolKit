import 'package:flutter/material.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';
import 'package:nmtk_ui_core/neat/dark/cut/dark_card_header.dart';

/// "Avg Total Sales" hero card with a USD amount and currency pill.
class AvgSalesCard extends StatelessWidget {
  const AvgSalesCard({super.key});

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
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        spacing: 24,
        children: [
          const DarkCardHeader(
            title: 'Avg Total Sales',
            iconColor: Color(0xFFB5E4CA),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            spacing: 8,
            children: [
              const Text(
                '2,180',
                style: TextStyle(
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
                child: const Text(
                  'USD',
                  style: TextStyle(
                    color: Color(0xFF1D1D25),
                    fontSize: 10,
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const Text(
            'Total Sales',
            style: TextStyle(
              color: Color(0xFF7E8BA0),
              fontSize: 14,
              fontFamily: 'Inter',
              fontWeight: FontWeight.w400,
              height: 1.57,
              letterSpacing: -0.50,
            ),
          ),
        ],
      ),
    );
  }
}
