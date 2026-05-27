import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'cut/dark_status_bar.dart';
import 'cut/dark_top_bar.dart';
import 'cut/finance_widgets.dart';

class NeatFinance extends StatelessWidget {
  @Preview(name: 'Neat Dark – Finance', group: 'Neat Dark Pages', size: Size(375, 1148))
  const NeatFinance({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 375,
          height: 1148,
          clipBehavior: Clip.antiAlias,
          decoration: const BoxDecoration(color: Color(0xFF1D1D25)),
          child: const Stack(
            children: [
              Positioned(left: 0, top: 0, child: DarkStatusBar()),
              Positioned(left: 0, top: 44, child: DarkTopBar()),
              Positioned(left: 16, top: 156, child: IncomeCard()),
              Positioned(left: 16, top: 509, child: FlowCard(title: 'Inflow', amount: '700', change: '10% from previous month', iconBg: Color(0x3382BE6D))),
              Positioned(left: 16, top: 605, child: FlowCard(title: 'Outflow', amount: '450', change: '15% from previous month', iconBg: Color(0x33FF6955))),
              Positioned(left: 16, top: 701, child: OutcomeCard()),
            ],
          ),
        ),
      ],
    );
  }
}
