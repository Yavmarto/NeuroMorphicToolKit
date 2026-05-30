import 'package:flutter/material.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';
import 'package:nmtk_ui_core/neat/dark/cut/dark_card_header.dart';
import 'package:nmtk_ui_core/neat/dark/cut/material_file_row.dart';

/// "New Material" listing card with file rows separated by dividers.
class NewMaterialCard extends StatelessWidget {
  const NewMaterialCard({super.key});

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
          const DarkCardHeader(title: 'New Material', iconColor: Color(0xFFFFBC99)),
          const MaterialFileRow(name: 'Kemanan Data Bab 3', size: '290.23 KB'),
          const Divider(color: Color(0xFF4B4C57), thickness: 1),
          const MaterialFileRow(name: 'Database Administration', size: '290.23 KB'),
          const Divider(color: Color(0xFF4B4C57), thickness: 1),
          const MaterialFileRow(name: 'MPD-Bab III-Komjar', size: '290.23 KB'),
          const Divider(color: Color(0xFF4B4C57), thickness: 1),
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
              Text('See All Material', style: TextStyle(color: Colors.white, fontSize: 16, fontFamily: 'Inter', fontWeight: FontWeight.w700, height: 1.25)),
            ]),
          ),
        ],
      ),
    );
  }
}
