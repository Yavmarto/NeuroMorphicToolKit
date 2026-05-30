import 'package:flutter/material.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';
import 'package:nmtk_ui_core/neat/dark/cut/oximeter_value.dart';

/// Red "OXIMETER" tile showing two [OximeterValue] readings side by side.
class OximeterCard extends StatelessWidget {
  const OximeterCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 164,
      height: 174,
      decoration: ShapeDecoration(color: const Color(0xFFFF5555), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(NmtkShellTokens.of(context).radiusSm))),
      padding: const EdgeInsets.all(16),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 8,
        children: [
          Opacity(opacity: 0.50, child: Text('OXIMETER', style: TextStyle(color: Colors.white, fontSize: 14, fontFamily: 'Inter', fontWeight: FontWeight.w600, height: 1.43))),
          Row(spacing: 16, children: [
            OximeterValue(value: '98', label: 'Sp02%'),
            OximeterValue(value: '77', label: 'PR bpm'),
          ]),
        ],
      ),
    );
  }
}
