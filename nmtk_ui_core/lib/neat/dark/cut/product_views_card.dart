import 'package:flutter/material.dart';
import 'dark_card_header.dart';

/// "Product Views" placeholder chart card.
class ProductViewsCard extends StatelessWidget {
  const ProductViewsCard({super.key});

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
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 24,
        children: [
          DarkCardHeader(title: 'Product Views', iconColor: Color(0xFFB5E4CA)),
          SizedBox(height: 160),
        ],
      ),
    );
  }
}
