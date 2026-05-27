import 'package:flutter/material.dart';

/// One row inside [PopularProductsCard]: thumbnail + name + price + likes pill.
class ProductRow extends StatelessWidget {
  const ProductRow({super.key, required this.name, required this.price, required this.likes});
  final String name, price, likes;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 8,
      children: [
        Row(spacing: 16, children: [
          Container(width: 78, height: 78, decoration: ShapeDecoration(color: const Color(0xFFE9ECF2), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)))),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 4, children: [
            Text(name, style: const TextStyle(color: Colors.white, fontSize: 14, fontFamily: 'Inter', fontWeight: FontWeight.w600, height: 1.43)),
            Text(price, style: const TextStyle(color: Color(0xFF60D39C), fontSize: 14, fontFamily: 'Inter', fontWeight: FontWeight.w600, height: 1.43)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: ShapeDecoration(color: const Color(0x192A85FF), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4))),
              child: Text(likes, style: const TextStyle(color: Color(0xFF2180FF), fontSize: 12, fontFamily: 'Inter', fontWeight: FontWeight.w700, height: 1.33, letterSpacing: -0.12)),
            ),
          ])),
        ]),
        const Divider(color: Color(0xFF4B4C57), thickness: 1),
      ],
    );
  }
}
