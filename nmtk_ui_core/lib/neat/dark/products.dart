import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:nmtk_ui_core/neat/dark/cut/dark_status_bar.dart';
import 'package:nmtk_ui_core/neat/dark/cut/dark_top_bar.dart';
import 'package:nmtk_ui_core/neat/dark/cut/products_widgets.dart';

class NeatProducts extends StatelessWidget {
  @Preview(
    name: 'Neat Dark – Products',
    group: 'Neat Dark Pages',
    size: Size(375, 1583),
  )
  const NeatProducts({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 375,
          height: 1583,
          clipBehavior: Clip.antiAlias,
          decoration: const BoxDecoration(color: Color(0xFF1D1D25)),
          child: const Stack(
            children: [
              Positioned(left: 0, top: 0, child: DarkStatusBar()),
              Positioned(left: 0, top: 44, child: DarkTopBar()),
              Positioned(left: 16, top: 156, child: ProductViewsCard()),
              Positioned(left: 16, top: 538, child: PopularProductsCard()),
              Positioned(left: 16, top: 1073, child: TransactionHistoryCard()),
            ],
          ),
        ),
      ],
    );
  }
}
