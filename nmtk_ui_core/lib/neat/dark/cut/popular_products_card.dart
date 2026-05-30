import 'package:flutter/material.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';
import 'package:nmtk_ui_core/neat/dark/cut/dark_card_header.dart';
import 'package:nmtk_ui_core/neat/dark/cut/product_row.dart';

/// "Popular Products" listing card with rows and a "See All" footer.
class PopularProductsCard extends StatelessWidget {
  const PopularProductsCard({super.key});

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
          borderRadius: BorderRadius.circular(NmtkShellTokens.of(context).radiusSm),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 24,
        children: [
          const DarkCardHeader(title: 'Popular Products', iconColor: Color(0xFFFFD88D)),
          const ProductRow(name: 'Coca Saas Landing Page UI Kit', price: '\$9,212.90', likes: '178 likes'),
          const ProductRow(name: 'StayGo Statycation & Hotel UI Kit', price: '\$1,829.47', likes: '2.102 likes'),
          const ProductRow(name: 'Epay Wallet App Mobile UI Kit', price: 'Free', likes: '284 likes'),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: ShapeDecoration(
              color: const Color(0xFF1D1D25),
              shape: RoundedRectangleBorder(
                side: const BorderSide(width: 2, color: Color(0xFF4B4C57)),
                borderRadius: BorderRadius.circular(NmtkShellTokens.of(context).radiusSm),
              ),
            ),
            child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text('See All Product', style: TextStyle(color: Color(0xFFE9ECF2), fontSize: 16, fontFamily: 'Inter', fontWeight: FontWeight.w700, height: 1.25)),
            ]),
          ),
        ],
      ),
    );
  }
}
