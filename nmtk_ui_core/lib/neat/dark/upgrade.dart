import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:nmtk_ui_core/neat/dark/cut/dark_status_bar.dart';
import 'package:nmtk_ui_core/neat/dark/cut/dark_top_bar.dart';
import 'package:nmtk_ui_core/neat/dark/cut/upgrade_widgets.dart';

class NeatUpgrade extends StatelessWidget {
  @Preview(name: 'Neat Dark – Upgrade', group: 'Neat Dark Pages', size: Size(375, 1475))
  const NeatUpgrade({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 375,
          height: 1475,
          clipBehavior: Clip.antiAlias,
          decoration: const BoxDecoration(color: Color(0xFF1D1D25)),
          child: const Stack(
            children: [
              Positioned(left: 0, top: 0, child: DarkStatusBar()),
              Positioned(left: 0, top: 44, child: DarkTopBar()),
              Positioned(left: 16, top: 156, child: PricingHeaderCard()),
              Positioned(left: 16, top: 398, child: PricingTierCard(tier: 'SILVER', price: '\$50', isHighlighted: false)),
              Positioned(left: 16, top: 925, child: PricingTierCard(tier: 'GOLD', price: '\$100', isHighlighted: true)),
            ],
          ),
        ),
      ],
    );
  }
}
