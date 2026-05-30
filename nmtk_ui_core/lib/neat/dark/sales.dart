import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:nmtk_ui_core/neat/dark/cut/dark_status_bar.dart';
import 'package:nmtk_ui_core/neat/dark/cut/dark_top_bar.dart';
import 'package:nmtk_ui_core/neat/dark/cut/sales_widgets.dart';

class NeatSales extends StatelessWidget {
  @Preview(name: 'Neat Dark – Sales', group: 'Neat Dark Pages', size: Size(375, 1035))
  const NeatSales({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 375,
          height: 1035,
          clipBehavior: Clip.antiAlias,
          decoration: const BoxDecoration(color: Color(0xFF1D1D25)),
          child: const Stack(
            children: [
              Positioned(left: 0, top: 0, child: DarkStatusBar()),
              Positioned(left: 0, top: 44, child: DarkTopBar()),
              Positioned(left: 16, top: 156, child: SalesReportCard()),
              Positioned(left: 16, top: 538, child: AvgSalesCard()),
              Positioned(left: 16, top: 871, child: SalesKpiCard(label: 'Total Visitors', value: '\$8,901', change: '37.8%', positive: true)),
              Positioned(left: 196, top: 871, child: SalesKpiCard(label: 'New Customers', value: '\$2,986', change: '37.8%', positive: false)),
            ],
          ),
        ),
      ],
    );
  }
}
